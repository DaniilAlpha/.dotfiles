------------------
--- formatters ---
------------------

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

--------------
--- config ---
--------------

--- pipes ---

local updates_count_pipe = Pipe:new_of_cmd([[
	get-updates-count() { cat /tmp/update_checker_count; }

	get-updates-count
	inotifyd echo /tmp/update_checker_count:w | while read -r _; do 
		get-updates-count
	done
	exit 1
]])
---@return integer?
function updates_count_pipe:transform(line)
	return tonumber(line)
end

local volume_pipe = Pipe:new_of_cmd([[
	get-volume-and-muted() {
		volume=$(pactl get-sink-volume @DEFAULT_SINK@ | cut -F5)
		mute=$(pactl get-sink-mute @DEFAULT_SINK@)
		echo ${volume%%%} ${mute##Mute: }
	}

	get-volume-and-muted
	pactl subscribe | while read -r line; do
		[ "${line#*on sink}" != "$line" ] && get-volume-and-muted
	done
]])
---@return integer?, boolean?
function volume_pipe:transform(line)
	---@type string?, string?
	local volume_str, mute = line:match("^(%d+)%s*(%w+)$")
	return tonumber(volume_str), mute and mute == "yes"
end

local brightness_pipe = Pipe:new_of_cmd([[
	script -qc "udevadm monitor --udev --subsystem-match=backlight" /dev/null < /dev/null | while read -r _; do
		echo $(( 100 * $(brightnessctl g) / $(brightnessctl m) ))
	done
]])
---@return integer?
function brightness_pipe:transform(line)
	return tonumber(line)
end

local statscore_pipe = Pipe:new_of_unix_socket("/run/user/10000/statscore.sock")
---@return table?, string?
function statscore_pipe:transform(line)
	local env = {}

	---@type function?, string?
	local get, err
	if setfenv then
		get, err = loadstring(line)
		get = get and setfenv(get, env)
	else
		get, err = load(line, nil, nil, env)
	end
	if not get then
		return nil, err
	end

	local ok, res = pcall(get)
	if not ok then
		return nil, res
	end
	---@cast res table

	return res
end

--- sections ---

local clock = Section:new(60)
---@param time integer
function clock:format(time)
	return { "󰃭", os.date("%d %b · %H:%M", time) }
end

local updates_count = Section:new(updates_count_pipe)
---@param value integer?
function updates_count:format(value)
	return value and (value > 0 or nil) and { "󰑐", tostring(value) }
end

local volume = Section:new(volume_pipe)
---@param value integer?
---@param is_muted boolean?
function volume:format(value, is_muted)
	return value and { is_muted and "󰝟" or rank_strs(value / 100, { "󰕿", "󰖀", "󰕾" }), value .. "%" }
end

local brightness = Section:new(brightness_pipe)
---@param value integer?
function brightness:format(value)
	return value and { rank_strs(value / 100, { "󰃞", "󰃟", "󰃠" }), value .. "%" }
end

---@class Stats<T>
---@field value T
---@field risk number

local disk = Section:new(statscore_pipe)
---@param statscore table?
function disk:format(statscore, _)
	---@type Stats<integer>?
	local rootfs = table.get_in(statscore, "fs", "/")
	return rootfs
		and {
			color = rank_strs(rootfs.risk, RISK_COLORS),

			"󰋊",
			tostring_si(rootfs.value, "B", 1024),
		}
end

local mem = Section:new(statscore_pipe)
---@param statscore table?
function mem:format(statscore, _)
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

local cpu = Section:new(statscore_pipe)
---@param statscore table?
function cpu:format(statscore, _)
	---@type Stats<number>?
	local cpu_load = table.get_in(statscore, "cpu_load")
	return cpu_load
		and {
			color = rank_strs(cpu_load.risk, RISK_COLORS),

			"󰍛",
			string.format("%.2f", cpu_load.value),
		}
end

local bat = Section:new(statscore_pipe)
---@param statscore table?
function bat:format(statscore, _)
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

local temp = Section:new(statscore_pipe)
---@param statscore table?
function temp:format(statscore, _)
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

local net = Section:new(statscore_pipe)
---@param statscore table?
function net:format(statscore, _)
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

local text = Section:new(Pipe:new_of_cmd("echo hello, $(whoami)"))
function text:format(line)
	return { line }
end

return {
	{ text },
	{ net },
	{ temp },
	{ bat },
	{ cpu, mem, disk },
	{ brightness, volume, updates_count, clock },
}
