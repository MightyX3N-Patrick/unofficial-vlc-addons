--[[
  unofficial_vlc_playlist.lua
  VLC Playlist Parser - Unofficial VLC Addons
  Install: lua/playlist/unofficial_vlc_playlist.lua
--]]

local _json = nil

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

function probe()
    return vlc.access == "http"
        and vlc.path ~= nil
        and vlc.path:find("127%.0%.0%.1:8181/vlc/") ~= nil
end

function parse()
    local data = ""
    repeat
        local chunk = vlc.read(65536)
        if chunk and #chunk > 0 then data = data .. chunk end
    until not chunk or #chunk == 0

    if not data or data == "" then return {} end

    local arr = json_decode(data)
    if not arr then return {} end

    local items = {}
    for _, item in ipairs(arr) do
        if item.path and item.path ~= "" then
            local entry = {path = item.path, title = item.title or "Unknown"}
            if item.arturl and item.arturl ~= "" then
                entry.arturl = item.arturl
            end
            table.insert(items, entry)
        end
    end
    return items
end
