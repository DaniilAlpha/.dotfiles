#!/usr/bin/lua

local posix = require("posix")

local USE_PANGO = true
local DEFAULT_PREFIX = "<span font_features='tnum'>"
local DEFAULT_POSTFIX = "</span>"

local GROUP_SEP_WIDTH = 30
local SEP_WIDTH = 10

---comment
---@param t table?
---@param ... any
function table.get_in(t, ...)
	for _, key in pairs({ ... }) do
		if t ~= nil then
			t = t[key]
		else
			break
		end
	end
	return t
end

---@param frac number
---@param icons string[]
local function range_icon(frac, icons)
	return icons[math.min(math.ceil((frac + 1e-10) * #icons), #icons)]
end

--------------------
--- bar protocol ---
--------------------

---@class BarSection
---@field [number] string
---@field color string?

local function bar_start()
	io.write('{"version": 1}', "\n")
	io.write("[", "\n")
	io.flush()
end

---@param groups BarSection[][]
local function bar_flush(groups)
	---@param s string?
	---@return string
	local function to_json_string_or_nil(s)
		return s and string.format("%q", s):gsub("\\\n", "\\n") or "null"
	end

	local sections_strs = {}
	for _, sections in pairs(groups) do
		for i, section in pairs(sections) do
			local text = #section > 0 and table.concat(section, " ") or nil
			text = text and DEFAULT_PREFIX .. text .. DEFAULT_POSTFIX

			---@type string?
			local color = section.color and '"' .. section.color:match("#[0-9A-Fa-f]+") .. '"'

			local is_last_section = i == #sections

			sections_strs[#sections_strs + 1] = text
				and string.format(
					'{"full_text": %s, "color": %s, "markup": %s, "separator_block_width": %d, "separator": %s}',
					to_json_string_or_nil(text),
					to_json_string_or_nil(color),
					to_json_string_or_nil(USE_PANGO and "pango" or nil),
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

---@class Stats<T>
---@field value T
---@field risk number

---@type table?
local statscore

---@return BarSection?
local function net()
	---@type Stats<string>
	local net_combo = table.get_in(statscore, "netfaces", "combo")
	return net_combo and { "󰓢", net_combo.value }
end

---@return BarSection?
local function temp()
	---@type Stats<string>
	local biggest_temp = table.get_in(statscore, "temps", 1)
	return biggest_temp
		and {
			range_icon(biggest_temp.risk, { "󱃃", "󱃃", "󰔏", "󱃂", "󰈸" }),
			biggest_temp.value,
			"(" .. biggest_temp.name .. ")",
		}
end

---@return BarSection?
local function bat()
	---@type Stats<string>, string
	local bat_combo, remain_time =
		table.get_in(statscore, "bats", "combo"), table.get_in(statscore, "bats", "remain_time")
	return bat_combo
		and {
			range_icon(
				bat_combo.risk,
				{ "󰁹", "󰂂", "󰂁", "󰂀", "󰁿", "󰁾", "󰁽", "󰁼", "󰁻", "󰁺" }
				-- { "󰂅", "󰂋", "󰂊", "󰢞", "󰂉", "󰢝", "󰂈", "󰂇", "󰂆", "󰢜" }
			),
			bat_combo.value,
			"󱎫",
			remain_time,
		}
end

---@return BarSection?
local function cpu()
	---@type Stats<string>
	local cpu_load = table.get_in(statscore, "cpu_load")
	return cpu_load and { "󰍛", cpu_load.value }
end

---@return BarSection?
local function mem()
	---@type Stats<string>
	local ram, swap = table.get_in(statscore, "ram"), table.get_in(statscore, "swap")
	return ram and swap and { "󰛇", ram.value, "+", swap.value }
end

---@return BarSection?
local function disk()
	---@type Stats<string>
	local rootfs = table.get_in(statscore, "fs", "/")
	return rootfs and { "󰋊", rootfs.value }
end

---@type integer?
local brightness_val
---@return BarSection?
local function brightness()
	return brightness_val and { range_icon(brightness_val / 100, { "󰃞", "󰃟", "󰃠" }), brightness_val .. "%" }
end

---@type integer?, boolean?
local volume_val, volume_is_muted
---@return BarSection?
local function volume()
	return volume_val
		and {
			volume_is_muted and "󰝟" or range_icon(volume_val / 100, { "󰕿", "󰖀", "󰕾" }),
			volume_val .. "%",
		}
end

---@type integer?
local updates_count
---@return BarSection?
local function updates()
	return updates_count and updates_count > 0 and { "󰑐", tostring(updates_count) } or nil
end

---@return BarSection?
local function clock()
	return { "󰃭", os.date("%d %b  ·  %H:%M:%S") }
end

------------
--- main ---
------------

bar_start()
while true do
	updates_count = (function()
		local file = io.open("/tmp/update_checker_count", "r")
		if not file then
			return
		end

		---@type integer
		local count = file:read("*n")

		file:close()

		return count
	end)()

	volume_val, volume_is_muted = (function()
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

		---@type integer, boolean
		local val, is_muted =
			vol_pipe:read("*a"):match("Volume:%s*[-%w]+:%s*[^/]+%s*/%s*(%d+)%%"),
			mute_pipe:read("*a"):match("Mute: (%w+)") == "yes"

		vol_pipe:close()
		mute_pipe:close()

		return val, is_muted
	end)()

	brightness_val = (function()
		local brightness_pipe = io.popen("brightnessctl i")
		if not brightness_pipe then
			return
		end

		---@type integer
		local val = brightness_pipe:read("*a"):match(".+%s*Current brightness:%s*%d+%s*%((%d+)%%%)")

		brightness_pipe:close()

		return val
	end)()

	statscore = (function()
		local path = "/dev/shm/statscore.lua"
		local env = {}

		local get_statscore, err
		if setfenv then
			get_statscore, err = loadfile(path)
			get_statscore = get_statscore and setfenv(get_statscore, env)
		else
			get_statscore, err = loadfile(path, "t", env)
		end
		if not get_statscore then
			return nil, "Loading file failed: " .. err
		end

		local ok, res = pcall(get_statscore)
		if not ok then
			return nil, "Executing file failed: " .. tostring(res)
		end

		return res
	end)()

	bar_flush({
		{ net() },
		{ temp() },
		{ bat() },
		{ cpu(), mem(), disk() },
		{ brightness(), volume(), updates(), clock() },
	})
	posix.sleep(1)
end
