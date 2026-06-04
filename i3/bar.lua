table.unpack = table.unpack or unpack
table.pack = table.pack or function(...)
	return { n = select("#", ...), ... }
end
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
---@field _file PosixFile
---@field _buf string[]
Pipe = {}
Pipe.__index = Pipe

---@param file PosixFile|string
---@return Pipe
function Pipe:new(file)
	if type(file) == "string" then
		file = posix.popen({ "sh", "-c", file }, "r")
	end

	posix.fcntl.fcntl(
		file.fd,
		posix.fcntl.F_SETFL,
		posix.fcntl.fcntl(file.fd, posix.fcntl.F_GETFL) + posix.fcntl.O_NONBLOCK
	)

	---@type Pipe
	local s = setmetatable({}, self)
	s._file = file
	s._buf = {}
	return s
end

---@param line string
---@return (any)...
function Pipe:transform(line)
	return line
end

---@return {[integer]: any, n: integer}? data_table list, containing data returned by the pipe's `_transform` function, or `nil` if unavailable
---@return string? err error message in case of some failure (except EWOULDBLOCK)
function Pipe:read()
	while true do
		---@type string
		local str, err, errno = posix.unistd.read(self._file.fd, 4096)
		if not str then
			return nil, (errno ~= posix.errno.EWOULDBLOCK or nil) and err
		end

		local linebreak_start, linebreak_end = str:find("%s*\n%s*")
		if linebreak_start and linebreak_end then
			local old_buf
			old_buf, self._buf = self._buf, {}

			old_buf[#old_buf + 1], self._buf[#self._buf + 1] =
				str:sub(1, linebreak_start - 1), str:sub(linebreak_end + 1, -1)

			return table.pack(self:transform(table.concat(old_buf)))
		else
			self._buf[#self._buf + 1] = str
		end
	end
end

--- pipe poll ---

---@param pipes Pipe[]
---@param timeout number? - in seconds
---@return {[Pipe]: boolean}, {[Pipe]: boolean}
local function poll_pipes(pipes, timeout)
	---@type table
	local fds = {}
	for _, pipe in pairs(pipes) do
		fds[pipe._file.fd] = { pipe = pipe, events = { IN = true, HUP = true, ERR = true, NVAL = true }, revents = {} }
	end

	---@type {[Pipe]: boolean}, {[Pipe]: boolean}
	local nonempty_pipes, dead_pipes = {}, {}

	local count = posix.poll.poll(fds, timeout and timeout * 1000)
	if count > 0 then
		for _, info in pairs(fds) do
			if info.revents.ERR or info.revents.NVAL then
				dead_pipes[info.pipe] = true
			elseif info.revents.IN then
				nonempty_pipes[info.pipe] = true
			elseif info.revents.HUP then
				dead_pipes[info.pipe] = true
			end
		end
	end

	return nonempty_pipes, dead_pipes
end

--- section ---

---@class SectionContent
---@field color string?
---@field [integer] string

---@class Section
---@field source number|Pipe
Section = {}
Section.__index = Section

---@param source number|Pipe
---@return Section
function Section:new(source)
	local s = setmetatable({}, self)
	s.source = source
	return s
end

---@vararg any
---@return SectionContent?
function Section:format(...) end

---@param text string
---@param color string?
---@param do_show_sep boolean?
---@return string
local function section_render_tojson(text, color, do_show_sep)
	---@param s string?
	---@return string
	local function string_or_nil_tojson(s)
		return s and string.format("%q", s):gsub("\\\n", "\\n"):gsub("\\9", "\\t"):gsub("\\13", "\\r"):gsub("\\%d+", "")
			or "null"
	end

	return string.format(
		'{"full_text": %s, "color": %s, "markup": %s, "separator_block_width": %d, "separator": %s}',
		string_or_nil_tojson(text),
		string_or_nil_tojson(color),
		string_or_nil_tojson((USE_PANGO or nil) and "pango"),
		do_show_sep and GROUP_SEP_WIDTH or SEP_WIDTH,
		do_show_sep and "true" or "false"
	)
end

--- bar ---

---@param sections Section[][]
local function bar_run(sections)
	io.write('{"version": 1, "click_events": true}', "\n")
	io.write("[", "\n")
	io.flush()

	---@type {[integer]: Pipe}
	local pipes = {}
	for _, group in pairs(sections) do
		for _, section in pairs(group) do
			local source = section.source
			if type(source) ~= "number" then
				pipes[#pipes + 1] = source
			end
		end
	end

	---@type SectionContent[][]
	local contents = {}
	while true do
		local nonempty_pipes, dead_pipes = poll_pipes(pipes, 1) -- TODO wait until the closest time source

		local pipe_datas = {}
		for i, pipe in pipes do
			if dead_pipes[pipe] then
				pipes[i] = nil
			elseif nonempty_pipes[pipe] then
				pipe_datas[pipe] = pipe:read() or pipe_datas[pipe]
			end
		end

		for i, group in ipairs(sections) do
			for j, section in ipairs(group) do
				---@type any
				local data

				local source = section.source
				if type(source) ~= "number" then
					if nonempty_pipes[source] then
						data = pipe_datas[source]
					end
				elseif os.time() % source == 0 then
					data = os.time()
					data = { data }
				end

				-- TODO implement default values (e.g. for clock - just pass the current time, not caring if it's a multiple of seconds, for pipe sections - nil instead of data (though will need to handle multiple args))

				local content = data and section:format(table.unpack(data, nil, data.n))

				-- we must set those to truthy, so nothing is skipped by `ipairs`
				contents[i] = contents[i] or {}
				contents[i][j] = content or contents[i][j] or {}

				-- TODO temporary to serve as an indicator when i crash the pipe unexpectadly
				if dead_pipes[source] then
					contents[i][j][1] = "[crashed]" .. (contents[i][j][1] or "")
					contents[i][j].color = "#FF00FF"
				end
			end
		end

		---@type {text: string, color: string?, do_show_sep?: boolean}[]
		local renders = {}
		for _, group in ipairs(contents) do
			for _, content in ipairs(group) do
				renders[#renders + 1] = content
					and (#content > 0 or nil)
					and {
						text = DEFAULT_PREFIX .. table.concat(content, " ") .. DEFAULT_POSTFIX,
						color = content.color and content.color:match("^#%x%x%x%x%x%x%x?%x?$"),
					}
			end
			if #renders > 0 then
				renders[#renders].do_show_sep = true
			end
		end

		---@type string[]
		local jsons = {}
		for _, render in ipairs(renders) do
			jsons[#jsons + 1] = section_render_tojson(render.text, render.color, render.do_show_sep)
		end
		io.write("[" .. table.concat(jsons, ",") .. "],", "\n")
		io.flush()
	end
end

--------------
--- config ---
--------------

--- pipes ---

local updates_count_pipe = Pipe:new([[
	function get-updates-count {
		cat /tmp/update_checker_count;
	}

	get-updates-count
	inotifyd echo /tmp/update_checker_count:w | while read -r _; do 
		get-updates-count
	done
]])
function updates_count_pipe:transform(line)
	return tonumber(line)
end

local volume_pipe = Pipe:new([[
	function get-volume-and-muted {
		volume=$(pactl get-sink-volume @DEFAULT_SINK@ | cut -F5)
		mute=$(pactl get-sink-mute @DEFAULT_SINK@)
		echo ${volume%%%} ${mute##Mute: }
	}

	get-volume-and-muted
	pactl subscribe | while read -r line; do
		[ "${line#*on sink}" != "$line" ] && get-volume-and-muted
	done
]])
function volume_pipe:transform(line)
	local volume, mute = line:match("^(%d+)%s*(%w+)$")
	return volume, mute == "yes"
end

local brightness_pipe = Pipe:new([[
	script -qc "udevadm monitor --udev --subsystem-match=backlight" /dev/null | while read -r _; do
		echo $(( 100 * $(brightnessctl g) / $(brightnessctl m) ))
	done
]])
function brightness_pipe:transform(line)
	return tonumber(line)
end

local statscore_pipe = Pipe:new([[
	while :; do 
		cat /run/user/10000/statscore.lua && printf "\n"
		inotifyd echo /run/user/10000/statscore.lua:x
	done
]])
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
function clock:format(time)
	return time and { "󰃭", os.date("%d %b · %H:%M", time) }
end

local updates_count = Section:new(updates_count_pipe)
function updates_count:format(value)
	return value and (value > 0 or nil) and { "󰑐", tostring(value) }
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
