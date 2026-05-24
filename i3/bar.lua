#!/usr/bin/lua

local posix = require("posix")

local USE_PANGO = true
local DEFAULT_PREFIX = "<span font_features='tnum'>"
local DEFAULT_POSTFIX = "</span>"

local GROUP_SEP_WIDTH = 30
local SEP_WIDTH = 10

---@param frac number
---@param icons string[]
local function range_icon(frac, icons)
	return icons[math.min(math.ceil((frac + 1e-10) * #icons), #icons)]
end

--------------------
--- bar protocol ---
--------------------

---@class BarSection
---@field text string?
---@field color string?

local function bar_start()
	io.write('{"version": 1}', "\n")
	io.write("[", "\n")
	io.flush()
end

---@param groups BarSection[][]
local function bar_flush(groups)
	local sections_strs = {}
	for _, sections in pairs(groups) do
		for i, section in pairs(sections) do
			local text = section.text
				and string.format("%q", DEFAULT_PREFIX .. section.text .. DEFAULT_POSTFIX):gsub("\\\n", "\\n")

			---@type string?
			local color = section.color and '"' .. section.color:match("#[0-9A-Fa-f]+") .. '"'

			local is_last_section = i == #sections
			sections_strs[#sections_strs + 1] = text
				and string.format(
					'{"full_text": %s, "color": %s, "markup": %s, "separator_block_width": %d, "separator": %s}',
					text,
					color and color or "null",
					USE_PANGO and '"pango"' or "null",
					is_last_section and GROUP_SEP_WIDTH or SEP_WIDTH,
					is_last_section and "true" or "false"
				)
		end
	end

	io.write("[" .. table.concat(sections_strs, ",") .. "],", "\n")
	io.flush()
end

----------------
--- sections ---
----------------

---@return BarSection?
local function volume()
	local vol_pipe = io.popen("pactl get-sink-volume @DEFAULT_SINK@")
	local mute_pipe = io.popen("pactl get-sink-mute @DEFAULT_SINK@")
	if not mute_pipe or not vol_pipe then
		if vol_pipe then
			vol_pipe:close()
		end
		if mute_pipe then
			mute_pipe:close()
		end
		return
	end

	local vol, is_muted =
		tonumber(vol_pipe:read("*a"):match("Volume:%s*[-%w]+:%s*[^/]+%s*/%s*(%d+)%%")),
		mute_pipe:read("*a"):match("Mute: (%w+)") == "yes"

	vol_pipe:close()
	mute_pipe:close()

	return {
		text = string.format("%s %d%%", is_muted and "󰝟" or range_icon(vol / 100, { "󰕿", "󰖀", "󰕾" }), vol),
	}
end

---@return BarSection?
local function brightness()
	local brightness_pipe = io.popen("brightnessctl i")
	if not brightness_pipe then
		return
	end

	local br = tonumber(brightness_pipe:read("*a"):match(".+%s*Current brightness:%s*%d+%s*%((%d+)%%%)"))

	return {
		text = string.format("%s %d%%", range_icon(br / 100, { "󰃞", "󰃟", "󰃠" }), br),
	}
end

---@return BarSection?
local function updates()
	local file = io.open("/tmp/update_checker_count", "r")
	if not file then
		return
	end
	local count = file:read("*n")
	file:close()

	return { text = count > 0 and string.format("󰑐 %d", count) or nil }
end

---@return BarSection?
local function time()
	return { text = string.format("󰃭 %s", os.date("%d %b  ·  %H:%M:%S")) }
end

------------
--- main ---
------------

bar_start()
while true do
	bar_flush({
		{},
		{ brightness(), volume(), updates(), time() },
	})
	posix.sleep(1)
end
