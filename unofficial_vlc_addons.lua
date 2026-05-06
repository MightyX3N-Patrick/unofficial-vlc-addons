--[[
  unofficial_vlc_addons.lua
  VLC Service Discovery - Unofficial VLC Addons
  Install: lua/sd/unofficial_vlc_addons.lua
--]]

local SERVER = "http://127.0.0.1:8181"
local _json  = nil

function descriptor()
    return { title = "Unofficial VLC Addons", capabilities = {} }
end

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

local function http_get(url)
    local auth_url = url:gsub("http://127%.0%.0%.1", "http://:vlcaddons@127.0.0.1")
    local s = vlc.stream(auth_url) or vlc.stream(url)
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

local function strip_manifest(url)
    return url:gsub("/manifest%.json$", ""):gsub("/$", "")
end

local TYPE_LABELS = {
    movie  = "Movies",
    series = "Series",
    tv     = "TV / Live",
    channel= "TV / Live",
    other  = "Other",
}

function main()
    local body = nil
    for i = 1, 10 do
        body = http_get(SERVER .. "/addons")
        if body then break end
        vlc.misc.mwait(vlc.misc.mdate() + 500000)
    end

    if not body then
        vlc.sd.add_node({title = "⚠ Enable extra interface: unofficial_vlc_intf"})
        return
    end

    local addons = json_decode(body) or {}
    local enabled = {}
    for _, a in ipairs(addons) do
        if a.enabled ~= false then table.insert(enabled, a) end
    end

    if #enabled == 0 then
        vlc.sd.add_node({title = "No addons — open http://127.0.0.1:8181"})
        return
    end

    -- Load settings to check view_mode
    local settings_body = http_get(SERVER .. "/settings")
    local settings = json_decode(settings_body) or {}
    local view_mode = settings.view_mode or "per_addon"

    if view_mode == "combined" then
        -- Fetch all manifests (fast - just JSON), group catalogs by type,
        -- build proper node tree. Catalog item fetching happens later in playlist parser.
        local by_type = {}   -- type -> list of {vlc_url, label}
        local type_order = {}
        local type_seen = {}
        for _, addon in ipairs(enabled) do
            local base = strip_manifest(addon.url)
            local mf_body = http_get(base .. "/manifest.json")
            if mf_body then
                local manifest = json_decode(mf_body)
                local catalogs = manifest and manifest.catalogs or {}
                for _, cat in ipairs(catalogs) do
                    local ctype = cat.type or "other"
                    if not type_seen[ctype] then
                        type_seen[ctype] = true
                        table.insert(type_order, ctype)
                        by_type[ctype] = {}
                    end
                    local cat_url = base .. "/catalog/" .. ctype .. "/" .. urlencode(cat.id) .. ".json"
                    local vlc_url = SERVER .. "/vlc/stremio-catalog?url=" .. urlencode(cat_url) .. "&base=" .. urlencode(base) .. "&type=" .. urlencode(ctype)
                    table.insert(by_type[ctype], {path=vlc_url, title=cat.name or cat.id})
                end
            end
        end
        -- Sort types: movie first, series second, rest after
        local priority = {movie=1, series=2, tv=3, channel=3}
        table.sort(type_order, function(a, b)
            return (priority[a] or 9) < (priority[b] or 9)
        end)
        for _, ctype in ipairs(type_order) do
            local label = TYPE_LABELS[ctype] or (ctype:sub(1,1):upper() .. ctype:sub(2))
            local type_node = vlc.sd.add_node({title = label})
            for _, item in ipairs(by_type[ctype]) do
                type_node:add_subitem(item)
            end
        end
    else
        -- Per-addon view (original behaviour)
        for _, addon in ipairs(enabled) do
            local base = strip_manifest(addon.url)
            local mf_body = http_get(base .. "/manifest.json")
            if not mf_body then
                vlc.sd.add_node({title = addon.name .. " (unavailable)"})
            else
                local manifest = json_decode(mf_body)
                local catalogs = manifest and manifest.catalogs or {}
                if #catalogs == 0 then
                    vlc.sd.add_node({title = addon.name .. " (no catalogs)"})
                else
                    local has_movie, has_series = false, false
                    for _, cat in ipairs(catalogs) do
                        if cat.type == "movie"  then has_movie  = true end
                        if cat.type == "series" then has_series = true end
                    end
                    local addon_node = vlc.sd.add_node({title = addon.name})
                    if has_movie and has_series then
                        local series_node = addon_node:add_subnode({title = "Series"})
                        local movie_node  = addon_node:add_subnode({title = "Movies"})
                        for _, cat in ipairs(catalogs) do
                            local cat_url = base .. "/catalog/" .. cat.type .. "/" .. urlencode(cat.id) .. ".json"
                            local vlc_url = SERVER .. "/vlc/stremio-catalog?url=" .. urlencode(cat_url) .. "&base=" .. urlencode(base) .. "&type=" .. urlencode(cat.type)
                            local n = cat.type == "series" and series_node or movie_node
                            n:add_subitem({path = vlc_url, title = cat.name or cat.id})
                        end
                    else
                        for _, cat in ipairs(catalogs) do
                            local cat_url = base .. "/catalog/" .. cat.type .. "/" .. urlencode(cat.id) .. ".json"
                            local vlc_url = SERVER .. "/vlc/stremio-catalog?url=" .. urlencode(cat_url) .. "&base=" .. urlencode(base) .. "&type=" .. urlencode(cat.type)
                            addon_node:add_subitem({path = vlc_url, title = cat.name or cat.id})
                        end
                    end
                end
            end
        end
    end
end
