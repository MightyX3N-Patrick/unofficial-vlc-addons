--[[
  unofficial_vlc_intf.lua
  VLC Interface Script - Unofficial VLC Addons
  
  Runs a raw TCP HTTP server using vlc.net.listen_tcp.
  No dependency on vlc.httpd() at all.
  
  Install: C:\Program Files\VideoLAN\VLC\lua\intf\unofficial_vlc_intf.lua
--]]

-- Log to file so we can debug without VLC messages
local _log_path = nil
local function log(msg)
    if not _log_path then
        local sep = package.config:sub(1,1)
        local appdata = os.getenv("APPDATA") or os.getenv("HOME") or ""
        _log_path = appdata .. sep .. "vlc" .. sep .. "uva_debug.log"
    end
    local f = io.open(_log_path, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg .. "\n")
        f:close()
    end
    pcall(vlc.msg.info, "[UVA] " .. msg)
end

log("Script loaded")
vlc.msg.info("[UVA] Script file loaded")

local PORT = 8181
local CONFIG_PATH   = nil
local SETTINGS_PATH = nil
local _json = nil

-- ---------------------------------------------------------------------------
-- JSON
-- ---------------------------------------------------------------------------

local function lazy_json()
    if not _json then
        local ok, m = pcall(require, "dkjson")
        if ok then _json = m end
    end
    return _json
end

local function json_decode(s)
    if not s or s == "" then return nil end
    local j = lazy_json()
    if j then
        local ok, t = pcall(j.decode, s)
        if ok and t then return t end
    end
    return nil
end

local function json_encode(t)
    local j = lazy_json()
    if j then
        local ok, s = pcall(j.encode, t)
        if ok then return s end
    end
    return "[]"
end

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------

local function get_config_path()
    if CONFIG_PATH then return CONFIG_PATH end
    local sep = package.config:sub(1,1)
    CONFIG_PATH = vlc.config.userdatadir() .. sep .. "lua" .. sep .. "sd" .. sep .. "addons.json"
    return CONFIG_PATH
end

local function load_addons()
    local f = io.open(get_config_path(), "r")
    if not f then return {} end
    local body = f:read("*a")
    f:close()
    return json_decode(body) or {}
end

local function save_addons(addons)
    local f = io.open(get_config_path(), "w")
    if not f then return false end
    f:write(json_encode(addons))
    f:close()
    return true
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local function get_settings_path()
    if SETTINGS_PATH then return SETTINGS_PATH end
    local sep = package.config:sub(1,1)
    SETTINGS_PATH = vlc.config.userdatadir() .. sep .. "lua" .. sep .. "sd" .. sep .. "uva_settings.json"
    return SETTINGS_PATH
end

local function load_settings()
    local f = io.open(get_settings_path(), "r")
    if not f then return {auto_pick="off", prefer="", avoid=""} end
    local body = f:read("*a")
    f:close()
    local t = json_decode(body) or {}
    t.auto_pick = t.auto_pick or "off"
    t.prefer    = t.prefer    or ""
    t.avoid     = t.avoid     or ""
    return t
end

local function save_settings(s)
    local f = io.open(get_settings_path(), "w")
    if not f then return false end
    f:write(json_encode(s))
    f:close()
    return true
end

-- Score a stream for auto-pick-best: higher = better
local function stream_score(s)
    local t = ((s.title or "") .. " " .. (s.name or "")):lower()
    local score = 0
    -- Resolution
    if t:find("2160") or t:find("4k") or t:find("uhd") then score = score + 1000
    elseif t:find("1080") then score = score + 500
    elseif t:find("720")  then score = score + 200
    elseif t:find("480")  then score = score + 50
    end
    -- HDR bonus
    if t:find("hdr") or t:find("dolby") then score = score + 100 end
    -- Prefer direct url over manifest
    local url = s.url or ""
    if url:match("%.mp4") or url:match("%.mkv") or url:match("%.avi") then score = score + 20 end
    if url:match("%.m3u8") then score = score - 10 end
    return score
end

-- Apply auto-pick settings to a list of raw stream objects, return chosen {path,title} or nil
local function autopick_stream(streams, settings)
    if not streams or #streams == 0 then return nil end
    local ap = settings.auto_pick or "off"
    if ap == "off" then return nil end  -- caller handles showing all

    -- Filter out avoided keywords first
    local avoid = settings.avoid ~= "" and settings.avoid:lower() or nil
    local filtered = {}
    for _, s in ipairs(streams) do
        if s.url and s.url ~= "" then
            local t = ((s.title or "") .. " " .. (s.name or "")):lower()
            if not avoid or not t:find(avoid, 1, true) then
                table.insert(filtered, s)
            end
        end
    end
    if #filtered == 0 then filtered = streams end  -- fallback: ignore avoid if nothing left

    if ap == "first" then
        local s = filtered[1]
        return {path=s.url, title=(s.title or s.name or "Stream"):gsub("\n"," · ")}
    elseif ap == "best" then
        table.sort(filtered, function(a,b) return stream_score(a) > stream_score(b) end)
        local s = filtered[1]
        return {path=s.url, title=(s.title or s.name or "Stream"):gsub("\n"," · ")}
    elseif ap == "prefer" then
        local prefer = settings.prefer ~= "" and settings.prefer:lower() or nil
        if prefer then
            for _, s in ipairs(filtered) do
                local t = ((s.title or "") .. " " .. (s.name or "")):lower()
                if t:find(prefer, 1, true) then
                    return {path=s.url, title=(s.title or s.name or "Stream"):gsub("\n"," · ")}
                end
            end
        end
        -- Fallback to first if no match
        local s = filtered[1]
        return {path=s.url, title=(s.title or s.name or "Stream"):gsub("\n"," · ")}
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- HTTP fetch
-- ---------------------------------------------------------------------------

local function http_get(url)
    local s = vlc.stream(url)
    if not s then return nil end
    local buf = ""
    local line = s:readline()
    while line do buf = buf .. line .. "\n"; line = s:readline() end
    return buf
end

local function urlencode(s)
    s = tostring(s or "")
    return (s:gsub("([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function urldecode(s)
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

local function parse_query(q)
    local params = {}
    if not q then return params end
    for k, v in q:gmatch("([^&=]+)=([^&]*)") do
        params[urldecode(k)] = urldecode(v)
    end
    return params
end

-- ---------------------------------------------------------------------------
-- Stremio helpers
-- ---------------------------------------------------------------------------

local function strip_manifest(url)
    return url:gsub("/manifest%.json$", ""):gsub("/$", "")
end

local function find_addon(addons, id)
    for _, a in ipairs(addons) do
        if a.id == id then return a end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- HTTP response builder
-- ---------------------------------------------------------------------------

local function make_response(status, mime, body)
    body = body or ""
    mime = mime or "application/json"
    return table.concat({
        "HTTP/1.1 " .. status,
        "Content-Type: " .. mime,
        "Content-Length: " .. #body,
        "Access-Control-Allow-Origin: *",
        "Connection: close",
        "",
        body
    }, "\r\n")
end

local function ok_json(body)
    return make_response("200 OK", "application/json", body)
end

local function ok_html(body)
    return make_response("200 OK", "text/html; charset=utf-8", body)
end

local function not_found()
    return make_response("404 Not Found", "text/plain", "Not Found")
end

-- ---------------------------------------------------------------------------
-- Route handlers
-- ---------------------------------------------------------------------------

local function handle_addons()
    return ok_json(json_encode(load_addons()))
end

local function handle_add(params)
    local url = params.url or ""
    if url == "" then return ok_json('{"ok":false,"error":"No URL"}') end
    if not url:match("/manifest%.json$") then
        url = url:gsub("/$", "") .. "/manifest.json"
    end
    local body = http_get(url)
    if not body then return ok_json('{"ok":false,"error":"Could not fetch manifest"}') end
    local manifest = json_decode(body)
    if not manifest or not manifest.id then return ok_json('{"ok":false,"error":"Invalid manifest"}') end
    local addons = load_addons()
    for _, a in ipairs(addons) do
        if a.id == manifest.id then return ok_json('{"ok":false,"error":"Already added"}') end
    end
    table.insert(addons, {id=manifest.id, name=manifest.name or manifest.id, url=url, enabled=true})
    save_addons(addons)
    return ok_json('{"ok":true,"name":"' .. (manifest.name or manifest.id) .. '"}')
end

local function handle_remove(params)
    local id = params.id or ""
    local addons = load_addons()
    local new = {}
    for _, a in ipairs(addons) do if a.id ~= id then table.insert(new, a) end end
    save_addons(new)
    return ok_json('{"ok":true}')
end

local function handle_toggle(params)
    local id = params.id or ""
    local enabled = params.enabled ~= "false" and params.enabled ~= "0"
    local addons = load_addons()
    for _, a in ipairs(addons) do if a.id == id then a.enabled = enabled end end
    save_addons(addons)
    return ok_json('{"ok":true}')
end

local function handle_catalog(path, query_str)
    local addon_id, ctype, cid = path:match("^/vlc/catalog/([^/]+)/([^/]+)/(.+)$")
    if not addon_id then return not_found() end
    local addons = load_addons()
    local addon = find_addon(addons, urldecode(addon_id))
    if not addon then return not_found() end
    local base = strip_manifest(addon.url)
    local params = parse_query(query_str)
    local api_url
    if params.search and params.search ~= "" then
        api_url = base .. "/catalog/" .. ctype .. "/" .. cid .. "/search=" .. urlencode(params.search) .. ".json"
    elseif params.skip and params.skip ~= "" then
        api_url = base .. "/catalog/" .. ctype .. "/" .. cid .. "/skip=" .. params.skip .. ".json"
    else
        api_url = base .. "/catalog/" .. ctype .. "/" .. cid .. ".json"
    end
    local body = http_get(api_url)
    if not body then return ok_json("[]") end
    local data = json_decode(body)
    if not data then return ok_json("[]") end
    local metas = data.metas or {}
    local items = {}
    for _, meta in ipairs(metas) do
        local mid    = meta.id or ""
        local mtype  = meta.type or ctype
        local name   = meta.name or mid
        local poster = meta.poster or ""
        local item_path
        if mtype == "movie" then
            item_path = "http://127.0.0.1:" .. PORT .. "/vlc/stream/" .. urlencode(addon_id) .. "/" .. mtype .. "/" .. urlencode(mid)
        else
            item_path = "http://127.0.0.1:" .. PORT .. "/vlc/meta/" .. urlencode(addon_id) .. "/" .. mtype .. "/" .. urlencode(mid)
        end
        table.insert(items, {path=item_path, title=name, arturl=poster})
    end
    return ok_json(json_encode(items))
end

local function handle_meta(path)
    local addon_id, mtype, mid = path:match("^/vlc/meta/([^/]+)/([^/]+)/(.+)$")
    if not addon_id then return not_found() end
    local addons = load_addons()
    local addon = find_addon(addons, urldecode(addon_id))
    if not addon then return not_found() end
    local base = strip_manifest(addon.url)
    local body = http_get(base .. "/meta/" .. mtype .. "/" .. urldecode(mid) .. ".json")
    if not body then return ok_json("[]") end
    local data = json_decode(body)
    if not data then return ok_json("[]") end
    local meta   = data.meta or {}
    local videos = meta.videos or {}
    local poster = meta.poster or ""
    if #videos == 0 then
        return ok_json(json_encode({{
            path   = "http://127.0.0.1:" .. PORT .. "/vlc/stream/" .. urlencode(addon_id) .. "/" .. mtype .. "/" .. urlencode(urldecode(mid)),
            title  = meta.name or mid,
            arturl = poster,
        }}))
    end
    local seasons, order = {}, {}
    for _, v in ipairs(videos) do
        local s = v.season or 1
        if not seasons[s] then seasons[s] = {}; table.insert(order, s) end
        table.insert(seasons[s], v)
    end
    table.sort(order)
    local items = {}
    local multi = #order > 1
    for _, snum in ipairs(order) do
        for _, ep in ipairs(seasons[snum]) do
            local ep_id    = ep.id or ""
            local ep_title = ep.title or ("Episode " .. (ep.episode or "?"))
            local thumb    = ep.thumbnail or poster
            if multi then
                ep_title = string.format("S%02dE%02d - %s", snum, ep.episode or 0, ep_title)
            else
                ep_title = string.format("E%02d - %s", ep.episode or 0, ep_title)
            end
            table.insert(items, {
                path   = "http://127.0.0.1:" .. PORT .. "/vlc/stream/" .. urlencode(addon_id) .. "/" .. mtype .. "/" .. urlencode(ep_id),
                title  = ep_title,
                arturl = thumb,
            })
        end
    end
    return ok_json(json_encode(items))
end

local function handle_stream(path)
    local addon_id, mtype, mid = path:match("^/vlc/stream/([^/]+)/([^/]+)/(.+)$")
    if not addon_id then return not_found() end
    local addons = load_addons()
    local addon = find_addon(addons, urldecode(addon_id))
    if not addon then return not_found() end
    local base = strip_manifest(addon.url)
    local body = http_get(base .. "/stream/" .. mtype .. "/" .. urldecode(mid) .. ".json")
    if not body then return ok_json("[]") end
    local data = json_decode(body)
    if not data then return ok_json("[]") end
    local streams = data.streams or {}
    local items = {}
    for _, s in ipairs(streams) do
        if s.url and s.url ~= "" then
            local title = (s.title or s.name or "Stream"):gsub("\n", " · ")
            table.insert(items, {path=s.url, title=title})
        end
    end
    return ok_json(json_encode(items))
end

local function handle_manifest(query_str)
    local params = parse_query(query_str)
    local addon_id = params.id or ""
    if addon_id == "" then return not_found() end
    local addons = load_addons()
    local addon = find_addon(addons, addon_id)
    if not addon then return not_found() end
    local base = strip_manifest(addon.url)
    local body = http_get(base .. "/manifest.json")
    if not body then return not_found() end
    return make_response("200 OK", "application/json", body)
end

local function handle_ui()
    return ok_html([[<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Unofficial VLC Addons</title>
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:system-ui,sans-serif;background:#0f0f13;color:#e0e0e0;min-height:100vh}header{background:#1a1a24;padding:20px 32px;border-bottom:1px solid #2a2a38}h1{font-size:20px;color:#fff}.c{max-width:700px;margin:0 auto;padding:32px 20px}h2{font-size:12px;font-weight:600;color:#666;text-transform:uppercase;letter-spacing:.08em;margin-bottom:14px}section{margin-bottom:36px}.row{display:flex;gap:10px}input{flex:1;background:#1a1a24;border:1px solid #2a2a38;border-radius:8px;padding:10px 14px;color:#e0e0e0;font-size:14px;outline:none}input:focus{border-color:#5b5bf6}.btn{background:#5b5bf6;color:#fff;border:none;border-radius:8px;padding:10px 18px;font-size:14px;cursor:pointer}.btn:hover{background:#4a4ae0}.btn.r{background:#c0392b}.st{font-size:13px;padding:8px 12px;border-radius:6px;margin-top:10px;display:none}.ok{background:#1b3a1b;color:#5cb85c;display:block}.er{background:#3a1b1b;color:#ef5350;display:block}.card{background:#1a1a24;border:1px solid #2a2a38;border-radius:10px;padding:14px 18px;margin-bottom:10px;display:flex;align-items:center;gap:14px}.info{flex:1;min-width:0}.name{font-size:15px;font-weight:600;color:#fff}.url{font-size:12px;color:#555;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:3px}.tgl{position:relative;width:38px;height:20px;cursor:pointer;flex-shrink:0}.tgl input{opacity:0;width:0;height:0}.sl{position:absolute;inset:0;background:#2a2a38;border-radius:20px;transition:.2s}.sl:before{content:"";position:absolute;height:14px;width:14px;left:3px;bottom:3px;background:#666;border-radius:50%;transition:.2s}input:checked+.sl{background:#5b5bf6}input:checked+.sl:before{transform:translateX(18px);background:#fff}.em{color:#444;font-size:14px;padding:8px 0}</style>
</head><body>
<header><h1>📺 Unofficial VLC Addons</h1></header>
<div class="c">
<section><h2>Add Addon</h2>
<div class="row"><input id="u" type="text" placeholder="Stremio manifest URL" onkeydown="if(event.key==='Enter')add()"/><button class="btn" onclick="add()">Add</button></div>
<div id="as" class="st"></div></section>
<section><h2>Installed Addons</h2><div id="list"><div class="em">Loading...</div></div></section>
<section><h2>Stream Settings</h2>
<div class="row" style="align-items:center;gap:12px;flex-wrap:wrap">
<label style="font-size:13px;color:#aaa;white-space:nowrap">Auto-pick stream:</label>
<select id="ap" onchange="updateSettingsUI(this.value)" style="background:#1a1a24;border:1px solid #2a2a38;border-radius:8px;padding:9px 12px;color:#e0e0e0;font-size:14px;outline:none;flex:1">
<option value="off">Off — show all streams</option>
<option value="first">First — use first stream returned</option>
<option value="best">Best quality — auto-detect resolution</option>
<option value="prefer">Prefer keyword — match title contains...</option>
</select>
</div>
<div id="prefer-row" class="row" style="display:none;margin-top:10px;align-items:center;gap:12px">
<label style="font-size:13px;color:#aaa;white-space:nowrap">Prefer keyword:</label>
<input id="pref" type="text" placeholder="e.g. 1080p, HEVC, HDR" style="flex:1"/>
</div>
<div id="avoid-row" class="row" style="display:none;margin-top:10px;align-items:center;gap:12px">
<label style="font-size:13px;color:#aaa;white-space:nowrap">Avoid keyword:</label>
<input id="avd" type="text" placeholder="e.g. CAM, dubbed, 480p"/>
<button class="btn" onclick="saveSettings()">Save</button>
</div>
<div class="row" style="margin-top:10px">
<button class="btn" onclick="saveSettings()" style="width:100%">Save Stream Settings</button>
</div>
<div id="ss" class="st"></div>
</section>
</div>
<script>
async function load(){const r=await fetch('/addons');const d=await r.json();const l=document.getElementById('list');if(!d.length){l.innerHTML='<div class="em">No addons.</div>';return}l.innerHTML=d.map(a=>`<div class="card"><div class="info"><div class="name">${a.name}</div><div class="url">${a.url}</div></div><label class="tgl"><input type="checkbox" ${a.enabled?'checked':''} onchange="toggle('${a.id}',this.checked)"/><span class="sl"></span></label><button class="btn r" style="padding:6px 12px;font-size:13px" onclick="rm('${a.id}')">Remove</button></div>`).join('');}
async function add(){const url=document.getElementById('u').value.trim();const st=document.getElementById('as');if(!url){show(st,'Enter a URL.',false);return}show(st,'Adding...',true);const r=await fetch('/addons/add?url='+encodeURIComponent(url));const d=await r.json();if(d.ok){show(st,'Added: '+d.name,true);document.getElementById('u').value='';load()}else show(st,'Error: '+(d.error||'?'),false);}
async function rm(id){if(!confirm('Remove?'))return;await fetch('/addons/remove?id='+encodeURIComponent(id));load();}
async function toggle(id,e){await fetch('/addons/toggle?id='+encodeURIComponent(id)+'&enabled='+(e?'true':'false'));}
function show(el,msg,ok){el.textContent=msg;el.className='st '+(ok?'ok':'er')}
async function loadSettings(){
  const r=await fetch('/settings');const s=await r.json();
  document.getElementById('ap').value=s.auto_pick||'off';
  document.getElementById('pref').value=s.prefer||'';
  document.getElementById('avd').value=s.avoid||'';
  updateSettingsUI(s.auto_pick||'off');
}
function updateSettingsUI(v){
  const pr=document.getElementById('prefer-row');
  const av=document.getElementById('avoid-row');
  pr.style.display=(v==='prefer')?'flex':'none';
  av.style.display=(v!=='off')?'flex':'none';
}
async function saveSettings(){
  const ap=document.getElementById('ap').value;
  const pref=document.getElementById('pref').value.trim();
  const avd=document.getElementById('avd').value.trim();
  const st=document.getElementById('ss');
  show(st,'Saving...',true);
  const r=await fetch('/settings?auto_pick='+encodeURIComponent(ap)+'&prefer='+encodeURIComponent(pref)+'&avoid='+encodeURIComponent(avd),{method:'POST'});
  const d=await r.json();
  show(st,d.ok?'Saved!':'Error saving',d.ok);
  setTimeout(()=>{st.style.display='none'},2000);
}
load();loadSettings();
</script></body></html>]])
end

-- ---------------------------------------------------------------------------
-- Request router
-- ---------------------------------------------------------------------------


local function handle_stremio_catalog(query_str)
    local params = parse_query(query_str)
    local url = params.url or ""
    local base = params.base or ""
    local ctype = params.type or "movie"
    if url == "" then return ok_json("[]") end
    local body = http_get(url)
    if not body then return ok_json("[]") end
    local data = json_decode(body)
    if not data then return ok_json("[]") end
    local metas = data.metas or {}
    local items = {}
    for _, meta in ipairs(metas) do
        local mid    = meta.id or ""
        local mtype  = meta.type or ctype
        local name   = meta.name or mid
        local poster = meta.poster or ""
        local item_path
        if mtype == "movie" then
            item_path = "http://127.0.0.1:" .. PORT .. "/vlc/stremio-stream?base=" .. urlencode(base) .. "&type=" .. mtype .. "&id=" .. urlencode(mid)
        else
            item_path = "http://127.0.0.1:" .. PORT .. "/vlc/stremio-meta?base=" .. urlencode(base) .. "&type=" .. mtype .. "&id=" .. urlencode(mid)
        end
        table.insert(items, {path=item_path, title=name, arturl=poster})
    end
    return ok_json(json_encode(items))
end

local function handle_stremio_meta(query_str)
    local params = parse_query(query_str)
    local base  = params.base or ""
    local mtype = params.type or "series"
    local mid   = params.id or ""
    if base == "" or mid == "" then return ok_json("[]") end
    local body = http_get(base .. "/meta/" .. mtype .. "/" .. mid .. ".json")
    if not body then return ok_json("[]") end
    local data = json_decode(body)
    if not data then return ok_json("[]") end
    local meta   = data.meta or {}
    local videos = meta.videos or {}
    local poster = meta.poster or ""
    if #videos == 0 then
        -- No episode list - try streaming directly
        return ok_json(json_encode({{
            path   = "http://127.0.0.1:" .. PORT .. "/vlc/stremio-stream?base=" .. urlencode(base) .. "&type=" .. mtype .. "&id=" .. urlencode(mid),
            title  = meta.name or mid,
            arturl = poster,
        }}))
    end
    -- Group by season - return one entry per season (each expands to episodes via stremio-season)
    local seasons, order = {}, {}
    for _, v in ipairs(videos) do
        local s = v.season or 1
        if not seasons[s] then seasons[s] = {}; table.insert(order, s) end
        table.insert(seasons[s], v)
    end
    table.sort(order)
    local items = {}
    if #order == 1 then
        -- Only one season - return episodes directly
        local snum = order[1]
        for _, ep in ipairs(seasons[snum]) do
            local ep_id    = ep.id or ""
            local ep_title = ep.title or ("Episode " .. (ep.episode or "?"))
            local thumb    = ep.thumbnail or poster
            ep_title = string.format("E%02d - %s", ep.episode or 0, ep_title)
            table.insert(items, {
                path   = "http://127.0.0.1:" .. PORT .. "/vlc/stremio-stream?base=" .. urlencode(base) .. "&type=" .. mtype .. "&id=" .. urlencode(ep_id),
                title  = ep_title,
                arturl = thumb,
            })
        end
    else
        -- Multiple seasons - return one clickable entry per season
        for _, snum in ipairs(order) do
            local season_url = "http://127.0.0.1:" .. PORT .. "/vlc/stremio-season?base=" .. urlencode(base) .. "&type=" .. mtype .. "&id=" .. urlencode(mid) .. "&season=" .. snum
            table.insert(items, {
                path   = season_url,
                title  = "Season " .. snum,
                arturl = poster,
            })
        end
    end
    return ok_json(json_encode(items))
end

-- Returns all episodes for a specific season of a series
local function handle_stremio_season(query_str)
    local params = parse_query(query_str)
    local base   = params.base or ""
    local mtype  = params.type or "series"
    local mid    = params.id or ""
    local snum   = tonumber(params.season) or 1
    if base == "" or mid == "" then return ok_json("[]") end
    local body = http_get(base .. "/meta/" .. mtype .. "/" .. mid .. ".json")
    if not body then return ok_json("[]") end
    local data = json_decode(body)
    if not data then return ok_json("[]") end
    local meta   = data.meta or {}
    local videos = meta.videos or {}
    local poster = meta.poster or ""
    local items  = {}
    for _, ep in ipairs(videos) do
        if (ep.season or 1) == snum then
            local ep_id    = ep.id or ""
            local ep_title = ep.title or ("Episode " .. (ep.episode or "?"))
            local thumb    = ep.thumbnail or poster
            ep_title = string.format("E%02d - %s", ep.episode or 0, ep_title)
            table.insert(items, {
                path   = "http://127.0.0.1:" .. PORT .. "/vlc/stremio-stream?base=" .. urlencode(base) .. "&type=" .. mtype .. "&id=" .. urlencode(ep_id),
                title  = ep_title,
                arturl = thumb,
            })
        end
    end
    return ok_json(json_encode(items))
end

local function handle_stremio_stream(query_str)
    local params = parse_query(query_str)
    local base  = params.base or ""
    local mtype = params.type or "movie"
    local mid   = params.id or ""
    if base == "" or mid == "" then return ok_json("[]") end
    local body = http_get(base .. "/stream/" .. mtype .. "/" .. mid .. ".json")
    if not body then return ok_json("[]") end
    local data = json_decode(body)
    if not data then return ok_json("[]") end
    local streams = data.streams or {}
    local settings = load_settings()
    -- Try autopick
    local picked = autopick_stream(streams, settings)
    if picked then
        -- Use vlc.playlist directly from the intf thread to add and immediately play
        -- the stream. This is the only reliable way to auto-play in VLC Lua.
        local played = false
        if vlc.playlist then
            log("AUTOPICK: adding " .. picked.path)
            local ok_add, id = pcall(vlc.playlist.add, {
                { path = picked.path, name = picked.title }
            })
            log("AUTOPICK: add result ok=" .. tostring(ok_add) .. " id=" .. tostring(id))
            if ok_add and id then
                local ok_play, perr = pcall(vlc.playlist.play, id)
                log("AUTOPICK: play result ok=" .. tostring(ok_play) .. " err=" .. tostring(perr))
                if ok_play then played = true end
            end
        else
            log("AUTOPICK: vlc.playlist not available")
        end
        if not played then
            log("AUTOPICK: falling back to playlist item")
            return ok_json(json_encode({picked}))
        end
        -- Return empty so playlist parser adds nothing (we already queued via vlc.playlist)
        return ok_json("[]")
    end
    -- No autopick - return all streams for user to choose
    local items = {}
    for _, s in ipairs(streams) do
        if s.url and s.url ~= "" then
            local title = (s.title or s.name or "Stream"):gsub("\n", " · ")
            table.insert(items, {path=s.url, title=title})
        end
    end
    return ok_json(json_encode(items))
end

local function route(method, path, query_str, body)
    local params = parse_query(query_str)
    -- Merge POST body params
    if method == "POST" then
        local bp = parse_query(body)
        for k, v in pairs(bp) do params[k] = v end
    end

    if path == "/" or path == "" then
        return handle_ui()
    elseif path == "/addons" then
        return handle_addons()
    elseif path == "/addons/add" then
        return handle_add(params)
    elseif path == "/addons/remove" then
        return handle_remove(params)
    elseif path == "/addons/toggle" then
        return handle_toggle(params)
    elseif path == "/settings" then
        if method == "POST" then
            local s = load_settings()
            s.auto_pick = params.auto_pick or s.auto_pick
            s.prefer    = params.prefer    ~= nil and params.prefer    or s.prefer
            s.avoid     = params.avoid     ~= nil and params.avoid     or s.avoid
            save_settings(s)
            return ok_json('{"ok":true}')
        else
            return ok_json(json_encode(load_settings()))
        end
    elseif path == "/vlc/stremio-catalog" then
        return handle_stremio_catalog(query_str)
    elseif path == "/vlc/stremio-meta" then
        return handle_stremio_meta(query_str)
    elseif path == "/vlc/stremio-stream" then
        return handle_stremio_stream(query_str)
    elseif path == "/vlc/stremio-season" then
        return handle_stremio_season(query_str)
    elseif path:match("^/vlc/catalog/") then
        return handle_catalog(path, query_str)
    elseif path:match("^/vlc/meta/") then
        return handle_meta(path)
    elseif path:match("^/vlc/stream/") then
        return handle_stream(path)
    elseif path == "/vlc/manifest" then
        return handle_manifest(query_str)
    elseif path == "/shutdown" then
        -- Another VLC instance is asking us to release the port
        return make_response("200 OK", "text/plain", "bye")
    else
        return not_found()
    end
end

-- ---------------------------------------------------------------------------
-- Raw TCP HTTP server
-- ---------------------------------------------------------------------------

local function parse_request(raw)
    local method, full_path, headers_str, body = "", "/", "", ""
    local lines = {}
    -- Split headers from body
    local header_part, body_part = raw:match("^(.-)\r\n\r\n(.*)$")
    if not header_part then
        header_part = raw
        body_part = ""
    end
    body = body_part or ""
    -- Parse request line
    local first_line = header_part:match("^([^\r\n]+)")
    if first_line then
        method, full_path = first_line:match("^(%S+)%s+(%S+)")
    end
    method = method or "GET"
    full_path = full_path or "/"
    -- Split path and query
    local path, query = full_path:match("^([^?]+)%??(.*)$")
    path = path or full_path
    query = query or ""
    return method, path, query, body
end

local function handle_client(fd)
    local pollfds = {}
    pollfds[fd] = vlc.net.POLLIN
    vlc.net.poll(pollfds)
    local data = ""
    local chunk = vlc.net.recv(fd, 65536)
    while chunk and #chunk > 0 do
        data = data .. chunk
        if data:find("\r\n\r\n") then break end
        pollfds[fd] = vlc.net.POLLIN
        local r = vlc.net.poll(pollfds)
        if not r or r == 0 then break end
        chunk = vlc.net.recv(fd, 65536)
    end
    if data == "" then return end
    local method, path, query, body = parse_request(data)
    local ok, response = pcall(route, method, path, query, body)
    if not ok then
        response = make_response("500 Internal Server Error", "text/plain", tostring(response))
    end
    vlc.net.send(fd, response)
end

-- ---------------------------------------------------------------------------
-- Interface entry points
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------------

log("Starting TCP server on port " .. PORT)
local listener = vlc.net.listen_tcp("127.0.0.1", PORT)
if not listener then
    log("ERROR: could not bind port " .. PORT)
else
    log("Listening on http://127.0.0.1:" .. PORT)
    while true do
        local ok, err = pcall(function()
            local fds = listener:fds()
            local pollfds = {}
            if type(fds) == "table" then
                for _, fd in ipairs(fds) do
                    pollfds[fd] = vlc.net.POLLIN
                end
            elseif type(fds) == "number" then
                pollfds[fds] = vlc.net.POLLIN
            end
            local n = vlc.net.poll(pollfds)
            if not n or n <= 0 then
                vlc.misc.mwait(vlc.misc.mdate() + 50000)
                return
            end
            if n > 0 then
                local fd = listener:accept()
                if fd and fd >= 0 then
                    local ok2, err2 = pcall(handle_client, fd)
                    if not ok2 then
                        log("Client error: " .. tostring(err2))
                    end
                    vlc.net.close(fd)
                end
            end
        end)
        if not ok then
            local msg = tostring(err)
            if msg:find("Interrupted") then
                -- VLC is shutting down - stop the loop so the process can exit
                log("Shutting down")
                vlc.deactivate()
                break
            else
                log("ERROR in loop: " .. msg)
                vlc.misc.mwait(vlc.misc.mdate() + 200000)
            end
        end
    end
end
