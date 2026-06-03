table.unpack = table.unpack or unpack
local posix = require("posix")

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

------------
--- core ---
------------

--- pipe ---

---@alias PosixFile table

---@class Pipe
---@field file PosixFile
Pipe = {}

---@param file PosixFile
---@return Pipe
function Pipe:new(file)
	posix.fcntl.fcntl(
		file.fd,
		posix.fcntl.F_SETFL,
		posix.fcntl.fcntl(file.fd, posix.fcntl.F_GETFL) + posix.fcntl.O_NONBLOCK
	)

	---@type Pipe
	local s = setmetatable({}, self)
	s.file = file
	return s
end

---@param line string
---@return (any)...
function Pipe:transform(line)
	return line
end

--- pipe poll ---

---@class PipePoll
---@field _fds table
PipePoll = {}

---@param pipes Pipe[]
---@return PipePoll
function PipePoll:new(pipes)
	---@type table
	local fds = {}
	for _, pipe in pairs(pipes) do
		fds[pipe.file.fd] = { pipe = pipe, events = { IN = true }, revents = { IN = false } }
	end

	---@type PipePoll
	local s = setmetatable({}, self)
	s._fds = fds
	return s
end

---@param timeout number? - in seconds
---@return {[Pipe]: boolean}
function PipePoll:__call(timeout)
	local pipes = {}

	local count = posix.poll.poll(self._fds, timeout and timeout * 1000)
	if count > 0 then
		for _, info in pairs(self._fds) do
			if info.revents.IN then
				pipes[info.pipe] = true
			end
		end
	end

	return pipes
end

local read_line_nonblock = (function()
	---@type string[][]
	local bufs = {}

	---@param fd PosixFile
	---@return string?
	return function(fd)
		local buf = bufs[fd] or {}

		---@type string?
		local res

		---@type string
		local str = posix.unistd.read(fd, 4096)
		if not str then
			return
		end

		local newline_pos = str:find("\n")
		if newline_pos then
			local rem
			buf[#buf + 1], rem = str:sub(1, newline_pos - 1), str:sub(newline_pos + 1, -1)
			res = table.concat(buf, nil)
			buf = { rem }
		else
			buf[#buf + 1] = str
		end

		bufs[fd] = buf
		return res
	end
end)()

--- section ---

---@alias SectionRender {[integer]: string, color: string?}

---@class Section
---@field source number|Pipe
Section = {}

---@param source number|Pipe
---@return Section
function Section:new(source)
	local s = setmetatable({}, self)
	s.source = source
	return s
end

---@vararg any
---@return SectionRender?
function Section:format(...) end

---@param text string
---@param color string?
---@param do_show_sep boolean?
---@return string
local function section_render_to_json(text, color, do_show_sep)
	---@param s string?
	---@return string
	local function string_or_nil_to_json(s)
		return s and string.format("%q", s):gsub("\\\n", "\\n") or "null"
	end

	return string.format(
		'{"full_text": %s, "color": %s, "markup": %s, "separator_block_width": %d, "separator": %s}',
		string_or_nil_to_json(text),
		string_or_nil_to_json(color),
		string_or_nil_to_json(USE_PANGO and "pango" or nil),
		do_show_sep and GROUP_SEP_WIDTH or SEP_WIDTH,
		do_show_sep and "true" or "false"
	)
end

--- bar ---

---@param groups Section[][]
local function bar_run(groups)
	io.write('{"version": 1, "click_events": true}', "\n")
	io.write("[", "\n")
	io.flush()

	local pipes = {}
	for _, group in pairs(groups) do
		for _, section in pairs(group) do
			if type(section.source) ~= "number" then
				pipes[#pipes + 1] = section.source
			end
		end
	end
	local pipe_poll = PipePoll:new(pipes)

	---@type SectionRender[][]
	local rendered_groups = {}
	while true do
		local nonempty_pipes = pipe_poll(1) -- TODO wait until the closest time source

		for i, group in pairs(groups) do
			for j, section in pairs(group) do
				---@type any
				local data

				local source = section.source
				if type(source) ~= "number" then
					if nonempty_pipes[source] then
						-- TODO!!
						local line = read_line_nonblock(source.file.fd)
						data = line and { source:transform(line) }
					end
				elseif os.time() % source == 0 then
					data = os.time()
					data = { data }
				end

				rendered_groups[i] = rendered_groups[i] or {}
				if data then
					rendered_groups[i][j] = section.format(table.unpack(data)) or {}
				else
					rendered_groups[i][j] = rendered_groups[i][j] or {}
				end
			end
		end

		local json_sections = {}
		for _, group in pairs(rendered_groups) do
			for j, section in pairs(group) do
				local text = #section > 0 and table.concat(section, " ") or nil
				text = text and DEFAULT_PREFIX .. text .. DEFAULT_POSTFIX

				---@type string?
				local color = section.color and section.color:match("^#%x%x%x%x%x%x%x?%x?$")

				json_sections[#json_sections + 1] = text and section_render_to_json(text, color, j == #group)
			end
		end
		io.write("[" .. table.concat(json_sections, ",") .. "],", "\r\n")
		io.flush()
	end
end

--------------
--- config ---
--------------

--- pipes ---

local updates_count_pipe = Pipe:new(posix.popen({
	"sh",
	"-c",
	[[
	function get-updates-count {
		cat /tmp/update_checker_count;
	}

	get-updates-count
  inotifywait -qm -eclose_write /tmp/update_checker_count | while read -r _; do 
		get-updates-count
  done
  ]],
}, "r"))
function updates_count_pipe:transform(line)
	return tonumber(line)
end

local volume_pipe = Pipe:new(posix.popen({
	"sh",
	"-c",
	[[
	function get-volume-and-muted {
      volume=$(pactl get-sink-volume @DEFAULT_SINK@ | cut -F5)
      mute=$(pactl get-sink-mute @DEFAULT_SINK@)
      echo ${volume%%%} ${mute##Mute: }
	}

	get-volume-and-muted
  pactl subscribe | while read -r line; do
    [ "${line#*on sink}" != "$line" ] && get-volume-and-muted
  done
  ]],
}, "r"))
function volume_pipe:transform(line)
	local volume, mute = line:match("^(%d+)%s*(%w+)$")
	return volume, mute == "yes"
end

local brightness_pipe = Pipe:new(posix.popen({
	"sh",
	"-c",
	[[
  script -qc "udevadm monitor --udev --subsystem=backlight" /dev/null | while read -r _; do
    echo $(( 100 * $(brightnessctl g) / $(brightnessctl m) ))
  done
  ]],
}, "r"))
function brightness_pipe:transform(line)
	return tonumber(line)
end

local statscore_pipe = Pipe:new(posix.popen({
	"sh",
	"-c",
	[[
  while :; do 
    cat /run/user/10000/statscore.lua && echo 
		sleep 4
  done
  ]],
}, "r"))
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

local clock = Section:new(10)
function clock:format(time)
	return time and { "󰃭", os.date("%d %b  ·  %H:%M", time) }
end

local updates_count = Section:new(updates_count_pipe)
function updates_count:format(value)
	return value and value > 0 and { "󰑐", tostring(value) } or nil
end

local volume = Section:new(volume_pipe)
function volume:format(value, is_muted)
	return value and { is_muted and "󰝟" or rank_strs(value / 100, { "󰕿", "󰖀", "󰕾" }), value .. "%" }
end

local brightness = Section:new(brightness_pipe)
function brightness:format(value)
	return value and { rank_strs(value / 100, { "󰃞", "󰃟", "󰃠" }), value .. "%" }
end

---@class Stats<T>
---@field value T
---@field risk number

local disk = Section:new(statscore_pipe)
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

return bar_run({
	{ net },
	{ temp },
	{ bat },
	{ cpu, mem, disk },
	{ brightness, volume, updates_count, clock },
})
