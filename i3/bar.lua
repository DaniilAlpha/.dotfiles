local USE_PANGO = true
local DEFAULT_PREFIX = "<span font_features='tnum'>"
local DEFAULT_POSTFIX = "</span>"

local GROUP_SEP_WIDTH = 30
local SEP_WIDTH = 10

local RISK_COLORS = { nil, nil, nil, nil, nil, nil, nil, nil, "#F27835", "#F23535" }

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
local function rank_strs(frac, icons)
	return icons[math.min(math.ceil((frac + 1e-10) * #icons), #icons)]
end

---@param x number
---@alias SiPrefix ""|"k"|"M"|"G"|"T"
---@param k_mul number
---@return number, SiPrefix
local function optimal_si_prefix(x, k_mul)
	if x ~= x or -math.huge >= x or x >= math.huge then
		return x, ""
	end

	local PREFIXES = { "", "k", "M", "G", "T" }

	local prefix_i = 1
	while math.abs(x) > k_mul do
		x = x / k_mul
		prefix_i = prefix_i + 1
	end

	return x, PREFIXES[math.min(prefix_i, #PREFIXES)]
end

---@param x_in number
---@param char_count integer
---@return string
local function number_tostring_limited(x_in, char_count)
	if x_in ~= x_in or -math.huge >= x_in or x_in >= math.huge then
		return tostring(x_in)
	end

	local x = math.abs(x_in)
	x = x + 0.5 * 10 ^ -(char_count - (x_in < 0 and 1 or 0) - 1 - #tostring(math.floor(x)))

	local s0 = tostring((x_in < 0 and -1 or 1) * math.floor(x))
	char_count = char_count - #s0 - 1
	if char_count > 0 then
		local s1 = tostring(math.floor(x % 1 * 10 ^ char_count))
		char_count = char_count - #s1
		return s0 .. "." .. ("0"):rep(char_count) .. s1
	end
	return s0
end

---@param x number
---@param unit string?
---@param k_mul number?
---@param char_count integer?
---@return string
local function tostring_si(x, unit, k_mul, char_count)
	unit = unit or ""
	k_mul = k_mul or 1000
	char_count = char_count or 5

	if x ~= x then
		return "nan"
	elseif -math.huge >= x or x >= math.huge then
		return x > 0 and "inf" or "-inf"
	else
		local prefix
		x, prefix = optimal_si_prefix(x, k_mul)
		char_count = char_count - (prefix == "" and 0 or 1)

		return number_tostring_limited(x, char_count) .. prefix .. unit
	end
end

-- print(tostring_si(-(1. / 0), "u"))
-- print(tostring_si((1. / 0), "u"))
-- print(tostring_si((0. / 0), "u"))
-- print(tostring_si(0, "u"))
-- print(tostring_si(0.531, "u"))
-- print(tostring_si(0.33, "u"))
-- print(tostring_si(0.5, "u"))
-- print(tostring_si(3, "u"))
-- print(tostring_si(33, "u"))
-- print(tostring_si(840, "u"))
-- print(tostring_si(6577, "u"))
-- print(tostring_si(9949, "u"))
-- print(tostring_si(9950, "u"))
-- print(tostring_si(9994, "u"))
-- print(tostring_si(9999, "u"))
-- print(tostring_si(10000, "u"))
-- print(tostring_si(99499, "u"))
-- print(tostring_si(99998, "u"))
-- print(tostring_si(99999, "u"))
-- print(tostring_si(100000, "u"))
-- print(tostring_si(816333, "u"))
-- print(tostring_si(5131483, "u"))
-- print(tostring_si(-6577, "u"))
-- print(tostring_si(-99999, "u"))
-- print(tostring_si(-816333, "u"))
-- print(tostring_si(-5131483, "u"))

--------------------
--- bar protocol ---
--------------------

---@class BarSection
---@field color string?
---@field [number] string

local function bar_start()
	io.write('{"version": 1, "click_events": true}', "\n")
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

			local color = section.color and section.color:match("^#%x%x%x%x%x%x$")

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
	---@type {[string]: Stats<number>}?
	local netfaces = table.get_in(statscore, "netfaces")
	if not netfaces or not next(netfaces) then
		return
	end

	---@type number, number
	local combo_val, combo_risk = 0, 0
	for _, v in pairs(netfaces) do
		combo_val, combo_risk = combo_val + v.value, combo_risk + v.risk
	end

	return {
		color = rank_strs(combo_risk, RISK_COLORS),

		"󰓢",
		tostring_si(combo_val * 8, "bps"),
	}
end

---@return BarSection?
local function temp()
	---@type {[string]: Stats<number>}?
	local temps = table.get_in(statscore, "temps")
	if not temps then
		return
	end

	local max_temp_name, max_temp = next(temps)
	for k, v in pairs(temps) do
		if max_temp and max_temp.risk < v.risk then
			max_temp_name, max_temp = k, v
		end
	end

	return max_temp
		and {
			color = rank_strs(max_temp.risk, RISK_COLORS),

			rank_strs(max_temp.risk, { "󱃃", "󱃃", "󰔏", "󱃂", "󰈸" }),
			string.format("%d°C", max_temp.value),
			max_temp_name and "(" .. max_temp_name .. ")",
		}
end

---@return BarSection?
local function bat()
	---@alias BatStats Stats<{charge: integer, rate: number}>
	---@type BatStats?, {[string]: BatStats}?
	local combo = table.get_in(statscore, "bat")
	if not combo then
		return
	end

	local is_charging = combo.value.rate >= 0
	local remain_time = (is_charging and (100 - combo.value.charge) or -combo.value.charge) / combo.value.rate

	return {
		color = rank_strs(combo.risk, RISK_COLORS),

		rank_strs(
			combo.risk,
			is_charging and { "󰂅", "󰂋", "󰂊", "󰢞", "󰂉", "󰢝", "󰂈", "󰂇", "󰂆", "󰢜" }
				or { "󰁹", "󰂂", "󰂁", "󰂀", "󰁿", "󰁾", "󰁽", "󰁼", "󰁻", "󰁺" }
		),
		string.format("%d%% %+.2f%%/m", combo.value.charge, combo.value.rate * 60),
		"󱎫",
		-math.huge < remain_time and remain_time < math.huge and os.date("!%H:%M:%S", remain_time) or "forever",
	}
end

---@return BarSection?
local function cpu()
	---@type Stats<number>?
	local cpu_load = table.get_in(statscore, "cpu_load")
	return cpu_load
		and {
			color = rank_strs(cpu_load.risk, RISK_COLORS),

			"󰍛",
			string.format("%.2f", cpu_load.value),
		}
end

---@return BarSection?
local function mem()
	---@type Stats<integer>?, Stats<integer>?
	local ram, swap = table.get_in(statscore, "ram"), table.get_in(statscore, "swap")
	return ram
		and swap
		and {
			color = rank_strs(ram.risk * 0.75 + swap.risk * 0.25, RISK_COLORS),

			"󰛇",
			tostring_si(ram.value, "B", 1024),
			"+",
			tostring_si(swap.value, "B", 1024),
		}
end

---@return BarSection?
local function disk()
	---@type Stats<integer>?
	local rootfs = table.get_in(statscore, "fs", "/")
	return rootfs
		and {
			color = rank_strs(rootfs.risk, RISK_COLORS),

			"󰋊",
			tostring_si(rootfs.value, "B", 1024),
		}
end

---@type integer?
local brightness_val
---@return BarSection?
local function brightness()
	return brightness_val and { rank_strs(brightness_val / 100, { "󰃞", "󰃟", "󰃠" }), brightness_val .. "%" }
end

---@type integer?, boolean?
local volume_val, volume_is_muted
---@return BarSection?
local function volume()
	return volume_val
		and {
			volume_is_muted and "󰝟" or rank_strs(volume_val / 100, { "󰕿", "󰖀", "󰕾" }),
			volume_val .. "%",
		}
end

---@type integer?
local updates_count
---@return BarSection?
local function updates()
	return updates_count and updates_count > 0 and { "󰑐", tostring(updates_count) } or nil
end

---@type integer?
local time
---@return BarSection?
local function clock()
	return time and { "󰃭", os.date("%d %b  ·  %H:%M", time) }
end

------------
--- main ---
------------

---@return integer?
local function get_updates_count()
	local file = io.open("/tmp/update_checker_count", "r")
	if not file then
		return
	end

	---@type integer
	local count = file:read("*n")

	file:close()

	return count
end

---@return integer?, boolean?
local function get_volume_and_muted()
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
	local vol, is_muted =
		vol_pipe:read("*a"):match("Volume:%s*[-%w]+:%s*[^/]+%s*/%s*(%d+)%%"),
		mute_pipe:read("*a"):match("Mute: (%w+)") == "yes"

	vol_pipe:close()
	mute_pipe:close()

	return vol, is_muted
end

---@return integer?
local function get_brightness()
	local brightness_pipe = io.popen("brightnessctl i")
	if not brightness_pipe then
		return
	end

	---@type integer
	local val = brightness_pipe:read("*a"):match(".+%s*Current brightness:%s*%d+%s*%((%d+)%%%)")

	brightness_pipe:close()

	return val
end

---@return table?, string?
local function get_statscore()
	local path = "/dev/shm/statscore.lua"
	local env = {}

	local get, err = loadfile(path, "t", env)
	if setfenv then
		get = get and setfenv(get, env)
	end

	if not get then
		return nil, err
	end

	local ok, res = pcall(get)
	if not ok then
		return nil, res
	end

	return res
end

time = 0
updates_count = get_updates_count()
volume_val, volume_is_muted = get_volume_and_muted()
brightness_val = get_brightness()
statscore = get_statscore()

bar_start()
for line in io.lines() do
	---@cast line string

	if line:find('"event":%s*"clock"') then
		time = os.time()
	elseif line:find('"event":%s*"statscored"') then
		statscore = get_statscore()
	elseif line:find('"event":%s*"update_checker"') then
		updates_count = get_updates_count()
	elseif line:find('"event":%s*"volume"') then
		volume_val, volume_is_muted = get_volume_and_muted()
	elseif line:find('"event":%s*"backlight"') then
		brightness_val = get_brightness()
	end

	bar_flush({
		{ { line } },
		{ net() },
		{ temp() },
		{ bat() },
		{ cpu(), mem(), disk() },
		{ brightness(), volume(), updates(), clock() },
	})
end
