-- Language learner helpers for mpv:
--   0-9           jump back N seconds (0 = 10 s)
--   Shift+0-9     jump forward N seconds (Alt+0-9 works too)
--   l             cycle subtitle track (language)
--   t             toggle back to the previously used subtitle track
--   L             cycle secondary subtitle track (shown at the top)
--   e             expand subtitles: show previous and next lines
--   h             show/hide the legend of these controls

local mp = require "mp"
local options = require "mp.options"

local o = {
    -- keyboard layout for Shift+digit: "ch" (Swiss German) or "us"
    layout = "ch",
    -- number of lines shown before and after the current line in expanded mode
    context_lines = 2,
}
options.read_options(o, "learner")

-- Characters produced by Shift+0 .. Shift+9 (index 1 = digit 0)
local SHIFT_KEYS = {
    ch = { "=", "+", '"', "*", "ç", "%", "&", "/", "(", ")" },
    us = { ")", "!", "@", "SHARP", "$", "%", "^", "&", "*", "(" },
}

---------------------------------------------------------------------------
-- Seeking
---------------------------------------------------------------------------

local function jump(seconds)
    mp.commandv("seek", seconds, "relative+exact")
    mp.osd_message(string.format("%+d s", seconds), 1)
end

local shiftKeys = SHIFT_KEYS[o.layout] or SHIFT_KEYS.ch
for digit = 0, 9 do
    local seconds = digit == 0 and 10 or digit
    mp.add_forced_key_binding(tostring(digit), "jump-back-" .. digit, function()
        jump(-seconds)
    end, { repeatable = true })
    mp.add_forced_key_binding(shiftKeys[digit + 1], "jump-forward-" .. digit, function()
        jump(seconds)
    end, { repeatable = true })
    -- Alt+digit as layout-independent alternative (e.g. keyboards that drop Shift on digits)
    mp.add_forced_key_binding("Alt+" .. digit, "jump-forward-alt-" .. digit, function()
        jump(seconds)
    end, { repeatable = true })
end

-- Number keys replace mpv's default volume keys (9/0), so use the arrows instead
mp.add_forced_key_binding("UP", "volume-up", function() mp.commandv("add", "volume", 5) end, { repeatable = true })
mp.add_forced_key_binding("DOWN", "volume-down", function() mp.commandv("add", "volume", -5) end, { repeatable = true })

---------------------------------------------------------------------------
-- Subtitle tracks
---------------------------------------------------------------------------

local function subTracks()
    local tracks = {}
    for _, track in ipairs(mp.get_property_native("track-list", {})) do
        if track.type == "sub" then
            tracks[#tracks + 1] = track
        end
    end
    return tracks
end

local function trackLabel(track)
    if not track then
        return "off"
    end
    local parts = { "[" .. (track.lang or "?") .. "]" }
    if track.title then
        parts[#parts + 1] = track.title
    elseif track["external-filename"] then
        parts[#parts + 1] = track["external-filename"]:match("[^/]+$")
    end
    return table.concat(parts, " ")
end

local function findTrack(id)
    for _, track in ipairs(subTracks()) do
        if track.id == id then
            return track
        end
    end
end

-- Cycles through all subtitle tracks plus "off"; returns the new id or false
local function nextTrackId(currentId, skipId)
    local ids = {}
    for _, track in ipairs(subTracks()) do
        if track.id ~= skipId then
            ids[#ids + 1] = track.id
        end
    end
    ids[#ids + 1] = false
    for i, id in ipairs(ids) do
        if id == currentId then
            return ids[i % #ids + 1]
        end
    end
    return ids[1]
end

local previousSid = nil

local function setSid(id)
    -- remember only real tracks, so "t" swaps between two languages, never to "off"
    local current = mp.get_property_native("sid")
    if current and current ~= id then
        previousSid = current
    end
    mp.set_property_native("sid", id)
    mp.osd_message("Subtitles: " .. trackLabel(id and findTrack(id)), 2)
end

mp.add_forced_key_binding("l", "cycle-sub", function()
    setSid(nextTrackId(mp.get_property_native("sid"), mp.get_property_native("secondary-sid")))
end)

mp.add_forced_key_binding("t", "toggle-sub", function()
    if previousSid == nil then
        mp.osd_message("No previous subtitle track yet (press l first)", 2)
        return
    end
    setSid(previousSid)
end)

mp.add_forced_key_binding("L", "cycle-secondary-sub", function()
    local id = nextTrackId(mp.get_property_native("secondary-sid"), mp.get_property_native("sid"))
    mp.set_property_native("secondary-sid", id)
    mp.osd_message("Secondary subtitles: " .. trackLabel(id and findTrack(id)), 2)
end)

---------------------------------------------------------------------------
-- Expanded subtitles (previous / current / next lines)
---------------------------------------------------------------------------

local overlay = mp.create_osd_overlay("ass-events")
local expanded = false
local cache = {}        -- track id -> list of { start, stop, text } or "loading"/"error"
local lastRender = nil

local function parseTime(h, m, s, ms)
    return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) + tonumber(ms) / 1000
end

local function parseSrt(data)
    local events = {}
    data = data:gsub("\r", "") .. "\n\n"
    for block in data:gmatch("(.-)\n\n+") do
        local h1, m1, s1, ms1, h2, m2, s2, ms2, text = block:match(
            "(%d+):(%d+):(%d+)[,.](%d+)%s*%-%->%s*(%d+):(%d+):(%d+)[,.](%d+)[^\n]*\n?(.*)")
        if h1 then
            text = text:gsub("<[^>]->", ""):gsub("{[^}]-}", "")
            events[#events + 1] = {
                start = parseTime(h1, m1, s1, ms1),
                stop = parseTime(h2, m2, s2, ms2),
                text = text,
            }
        end
    end
    table.sort(events, function(a, b) return a.start < b.start end)
    return events
end

local function assEscape(text)
    text = text:gsub("\\", "\\\239\187\191")
    text = text:gsub("{", "\\{"):gsub("}", "\\}")
    text = text:gsub("\n", "\\N")
    return text
end

-- Index of the last event that started at or before t (0 if none)
local function eventIndexAt(events, t)
    local lo, hi = 1, #events
    local found = 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if events[mid].start <= t then
            found = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return found
end

local function showOverlay(text)
    overlay.res_x = 0
    overlay.res_y = 720
    overlay.data = text
    mp.msg.trace("overlay: " .. text)
    overlay:update()
end

local function render()
    if not expanded then
        return
    end
    local sid = mp.get_property_native("sid")
    if sid ~= false and type(sid) ~= "number" then
        return  -- "auto" while a file is (un)loading
    end
    local events = sid and cache[sid]
    if not sid then
        showOverlay("{\\an2\\fs30}No subtitle track selected")
        return
    elseif events == "loading" then
        showOverlay("{\\an2\\fs30}Loading subtitles…")
        return
    elseif events == "error" or type(events) ~= "table" then
        showOverlay("{\\an2\\fs30}Subtitle context not available for this track (image-based?)")
        return
    end

    local t = (mp.get_property_number("time-pos") or 0) - (mp.get_property_number("sub-delay") or 0)
    local idx = eventIndexAt(events, t)
    local active = idx > 0 and t < events[idx].stop
    local key = idx .. (active and "a" or "i")
    if key == lastRender then
        return
    end
    lastRender = key

    local lines = {}
    local from = math.max(1, idx - o.context_lines)
    local to = math.min(#events, idx + o.context_lines)
    for i = from, to do
        local style
        if i == idx and active then
            style = "{\\fs34\\b1\\1c&HFFFFFF&\\bord2}"
        else
            style = "{\\fs26\\b0\\1c&HA0A0A0&\\bord1.5}"
        end
        lines[#lines + 1] = style .. assEscape(events[i].text)
    end
    showOverlay("{\\an2}" .. table.concat(lines, "\\N"))
end

local function loadTrack(track)
    if cache[track.id] then
        render()
        return
    end
    cache[track.id] = "loading"
    render()

    -- ffmpeg converts any text subtitle format (srt, ass, vtt, embedded) to srt
    local args = { "ffmpeg", "-v", "error", "-nostdin" }
    if track.external then
        args[#args + 1] = "-i"
        args[#args + 1] = track["external-filename"]
        args[#args + 1] = "-map"
        args[#args + 1] = "0:s:0"
    else
        args[#args + 1] = "-i"
        args[#args + 1] = mp.get_property("path")
        args[#args + 1] = "-map"
        args[#args + 1] = "0:" .. track["ff-index"]
    end
    for _, a in ipairs({ "-f", "srt", "-" }) do
        args[#args + 1] = a
    end

    mp.command_native_async({
        name = "subprocess",
        args = args,
        capture_stdout = true,
        capture_stderr = true,
        playback_only = false,
    }, function(success, result)
        local events = success and result.status == 0 and parseSrt(result.stdout or "")
        mp.msg.debug(string.format("track %d: success=%s status=%s events=%s",
            track.id, tostring(success), tostring(result and result.status), tostring(events and #events)))
        if events and #events > 0 then
            cache[track.id] = events
        else
            cache[track.id] = "error"
            mp.msg.warn("subtitle extraction failed: " .. ((result and result.stderr) or "unknown"))
        end
        lastRender = nil
        render()
    end)
end

local function refreshTrack()
    lastRender = nil
    local sid = mp.get_property_native("sid")
    local track = sid and findTrack(sid)
    if track then
        loadTrack(track)
    else
        render()
    end
end

mp.add_forced_key_binding("e", "expand-subs", function()
    expanded = not expanded
    lastRender = nil
    if expanded then
        mp.set_property_native("sub-visibility", false)
        refreshTrack()
    else
        overlay:remove()
        mp.set_property_native("sub-visibility", true)
    end
    mp.osd_message(expanded and "Subtitles expanded" or "Subtitles normal", 1)
end)

mp.observe_property("time-pos", "number", function() render() end)
mp.observe_property("sid", "native", function()
    if expanded then
        refreshTrack()
    end
end)
mp.register_event("file-loaded", function()
    cache = {}
    previousSid = nil
    if expanded then
        refreshTrack()
    end
end)

---------------------------------------------------------------------------
-- Legend of the custom controls
---------------------------------------------------------------------------

local LEGEND = {
    { "1-9 / 0", "back N s (0 = 10 s)" },
    { "Shift/Alt+digit", "forward N s" },
    { "l", "cycle subtitle language" },
    { "t", "previous subtitle language" },
    { "L", "secondary subtitles (top)" },
    { "e", "expand subtitles (prev/next lines)" },
    { "v", "subtitles on/off" },
    { "Up / Down", "volume" },
    { "Space", "pause" },
    { "h", "hide this legend" },
    { "q", "quit" },
}

local legendOverlay = mp.create_osd_overlay("ass-events")
local legendVisible = false

local function legendText()
    local lines = {}
    for _, entry in ipairs(LEGEND) do
        lines[#lines + 1] = string.format("{\\1c&H66CCFF&}%-16s{\\1c&HFFFFFF&}%s", entry[1], entry[2])
    end
    local fontSize, lineHeight = 20, 20
    local width, height = 425, #lines * lineHeight + 22
    -- semi-transparent background box, then the text on top of it
    local box = string.format(
        "{\\an7\\pos(10,10)\\bord0\\shad0\\1c&H000000&\\1a&H30&\\p1}m 0 0 l %d 0 %d %d 0 %d{\\p0}",
        width, width, height, height)
    local text = string.format("{\\an7\\pos(22,20)\\fnmonospace\\fs%d\\bord0\\shad0}", fontSize)
        .. table.concat(lines, "\\N")
    return box .. "\n" .. text
end

local function setLegend(visible)
    legendVisible = visible
    if visible then
        legendOverlay.res_x = 0
        legendOverlay.res_y = 720
        legendOverlay.data = legendText()
        mp.msg.trace("legend: " .. legendOverlay.data)
        legendOverlay:update()
    else
        legendOverlay:remove()
    end
end

mp.add_forced_key_binding("h", "toggle-legend", function()
    setLegend(not legendVisible)
end)

local hintShown = false
mp.register_event("file-loaded", function()
    if not hintShown then
        hintShown = true
        mp.osd_message("h: show controls", 3)
    end
end)
