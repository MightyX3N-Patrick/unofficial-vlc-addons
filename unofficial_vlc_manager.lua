--[[
  unofficial_vlc_manager.lua
  VLC Extension: Unofficial VLC Addons Manager
  
  Add, remove, enable/disable Stremio addons.
  Talks to the interface server at 127.0.0.1:8181.
  
  Install: lua/extensions/unofficial_vlc_manager.lua
  Open:    View > Unofficial VLC Addons Manager
--]]

local SERVER = "http://127.0.0.1:8181"
local _json  = nil

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

-- Simple HTTP POST via vlc.stream using a data URI workaround
-- vlc.stream doesn't support POST, so we use GET with query params for simplicity
local function post(path, params)
    local qs = {}
    for k, v in pairs(params) do
        table.insert(qs, urlencode(k) .. "=" .. urlencode(v))
    end
    local url = SERVER .. path .. "?" .. table.concat(qs, "&")
    -- Use GET-based endpoints since vlc.stream only does GET
    return http_get(url)
end

-- ---------------------------------------------------------------------------
-- UI state
-- ---------------------------------------------------------------------------

local dlg, w_url, w_list, w_status
local addons = {}
local selected_idx = nil

local function set_status(msg, err)
    if w_status then
        w_status:set_text((err and "⚠ " or "✓ ") .. msg)
    end
end

local function refresh_list()
    local body = http_get(SERVER .. "/addons")
    if not body then
        set_status("Interface not running. Enable unofficial_vlc_intf.", true)
        return
    end
    addons = json_decode(body) or {}
    w_list:clear()
    selected_idx = nil
    for i, a in ipairs(addons) do
        local label = (a.enabled and "● " or "○ ") .. (a.name or a.id or "?")
        w_list:add_value(label, i)
    end
    if #addons == 0 then
        set_status("No addons. Paste a manifest URL and click Add.", false)
    else
        set_status(#addons .. " addon(s) installed. Open http://127.0.0.1:8181 to manage.", false)
    end
end

function on_add()
    local url = w_url:get_text():gsub("^%s+", ""):gsub("%s+$", "")
    if url == "" then set_status("Enter a manifest URL.", true); return end
    set_status("Adding...", false)
    dlg:update()
    local body = post("/addons/add", {url=url})
    local data = json_decode(body or "")
    if data and data.ok then
        w_url:set_text("")
        set_status("Added: " .. (data.name or "?"), false)
        refresh_list()
    else
        set_status((data and data.error) or "Failed to add addon.", true)
    end
end

function on_select()
    local _, idx = w_list:get_value()
    selected_idx = tonumber(idx)
end

function on_toggle()
    if not selected_idx or not addons[selected_idx] then
        set_status("Select an addon first.", true); return
    end
    local a = addons[selected_idx]
    local enabled = not a.enabled
    post("/addons/toggle", {id=a.id, enabled=enabled and "true" or "false"})
    set_status((enabled and "Enabled: " or "Disabled: ") .. a.name, false)
    refresh_list()
end

function on_remove()
    if not selected_idx or not addons[selected_idx] then
        set_status("Select an addon first.", true); return
    end
    local name = addons[selected_idx].name
    post("/addons/remove", {id=addons[selected_idx].id})
    set_status("Removed: " .. name, false)
    refresh_list()
end

-- ---------------------------------------------------------------------------
-- Extension entry points
-- ---------------------------------------------------------------------------

function descriptor()
    return {
        title        = "Unofficial VLC Addons Manager",
        version      = "1.0",
        author       = "Unofficial VLC Addons",
        description  = "Manage Stremio addon sources for VLC.",
        capabilities = {}
    }
end

function activate()
    dlg = vlc.dialog("Unofficial VLC Addons Manager")
    dlg:add_label("Manifest URL:", 1, 1, 1, 1)
    w_url = dlg:add_text_input("", 2, 1, 4, 1)
    dlg:add_button("Add", on_add, 6, 1, 1, 1)
    w_status = dlg:add_label("Loading...", 1, 2, 6, 1)
    w_list = dlg:add_list(1, 3, 6, 6)
    dlg:add_button("Enable / Disable", on_toggle, 1, 10, 3, 1)
    dlg:add_button("Remove",           on_remove, 4, 10, 3, 1)
    dlg:show()
    refresh_list()
end

function deactivate()
    if dlg then dlg:delete(); dlg = nil end
end

function close()
    vlc.deactivate()
end
