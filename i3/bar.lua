table.unpack = table.unpack or unpack
table.pack = table.pack or function(...)
	return { n = select("#", ...), ... }
end
local posix = require("posix")
local socket = require("posix.sys.socket")

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

---@class Pipe
---@field _fd integer
---@field _buf string[]
Pipe = {}
Pipe.__index = Pipe

---@param path string
---@return Pipe
function Pipe:new_of_unix_socket(path)
	local fd = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM, 0) or -1
	socket.connect(fd, { family = socket.AF_UNIX, path = path })

	posix.fcntl.fcntl(fd, posix.fcntl.F_SETFL, posix.fcntl.fcntl(fd, posix.fcntl.F_GETFL) + posix.fcntl.O_NONBLOCK)

	---@type Pipe
	local s = setmetatable({}, self)
	s._buf = {}
	s._fd = fd
	function s._close()
		posix.unistd.close(fd)
		return false -- assuming socket should not disconnect normally
	end
	return s
end

---@param cmd string
---@return Pipe
function Pipe:new_of_cmd(cmd)
	local ppipe = posix.popen({ "sh", "-c", cmd }, "r")
	local fd = ppipe.fd

	posix.fcntl.fcntl(fd, posix.fcntl.F_SETFL, posix.fcntl.fcntl(fd, posix.fcntl.F_GETFL) + posix.fcntl.O_NONBLOCK)

	---@type Pipe
	local s = setmetatable({}, self)
	s._buf = {}
	s._fd = fd
	function s._close()
		local reason, code = posix.pclose(ppipe)
		return reason == "exited" and code == 0
	end
	return s
end

---@param line string
---@return (any)...
function Pipe:transform(line)
	return line
end

---@return {[integer]: any, n: integer}? data_table list, containing data returned by the pipe's `_transform` function, or `nil` if unavailable
---@return "eof"|"again"|string? err status indicator (in case reading was unsuccessful) or error message
function Pipe:read()
	while true do
		---@type string
		local str, err, errno = posix.unistd.read(self._fd, 4096)
		if not str then
			return nil, (errno == posix.errno.EAGAIN or errno == posix.errno.EWOULDBLOCK) and "again" or err
		end
		if str == "" then
			return nil, "eof"
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
			return nil, "again"
		end
	end
end

---@return boolean
function Pipe:_close()
	return true
end

--- pipe poll ---

---@param pipes Pipe[]
---@param timeout number? - in seconds
---@return {[Pipe]: boolean}
local function poll_pipes(pipes, timeout)
	---@type table
	local fds = {}
	for _, pipe in pairs(pipes) do
		fds[pipe._fd] = { events = { IN = true, HUP = true, ERR = true, NVAL = true }, pipe = pipe }
	end

	---@type {[Pipe]: boolean}
	local nonempty_pipes = {}

	local count = posix.poll.poll(fds, timeout and timeout * 1000)
	if count > 0 then
		for _, info in pairs(fds) do
			nonempty_pipes[info.pipe] = info.revents.IN or info.revents.HUP or info.revents.ERR or info.revents.NVAL
		end
	end

	return nonempty_pipes
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

---@param args table
---@return SectionContent
function Section:content(args)
	-- if format returns `nil`, set to empty to replace the old value
	return self:format(table.unpack(args, nil, args.n)) or {}
end

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

	---@type {[integer]: Pipe}, integer[]
	local pipes, periods = {}, {}
	for _, group in pairs(sections) do
		for _, section in pairs(group) do
			local source = section.source
			if type(source) ~= "number" then
				pipes[#pipes + 1] = source
			else
				periods[#periods + 1] = source
			end
		end
	end

	local time = os.time()

	---@type SectionContent[][]
	local contents = {}
	for i, group in ipairs(sections) do
		contents[i] = {}
		for j, section in ipairs(group) do
			local source = section.source

			---@type any
			local data
			if type(source) ~= "number" then
				data = {}
			else
				data = { time }
			end

			contents[i][j] = section:content(data)
		end
	end

	while true do
		time = os.time()

		-- TODO probably will crash from passing math.huge (a float) to poll() when no periodic sections are set up
		local closest_rem_time = math.huge
		for _, period in pairs(periods) do
			local rem_time = period - time % period
			if rem_time < closest_rem_time then
				closest_rem_time = rem_time
			end
		end

		---@type {[Pipe]: boolean}, {[Pipe]: boolean}
		local nonempty_pipes, crashed_pipes = poll_pipes(pipes, closest_rem_time), {}

		local pipe_datas = {}
		for i, pipe in pairs(pipes) do
			if nonempty_pipes[pipe] then
				local data, err = pipe:read()
				if data then
					pipe_datas[pipe] = data or pipe_datas[pipe]
				elseif err == "again" then
				else
					local closed_successfully = pipe:_close()
					pipes[i] = nil

					crashed_pipes[pipe] = err ~= "eof" or not closed_successfully
				end
			end
		end

		time = os.time()

		for i, group in ipairs(sections) do
			for j, section in ipairs(group) do
				local source = section.source

				---@type any
				local data
				if type(source) ~= "number" then
					if nonempty_pipes[source] then
						data = pipe_datas[source]
					end
				elseif time % source == 0 then
					data = { time }
				end

				if data then
					contents[i][j] = section:content(data)
				end

				if crashed_pipes[source] then
					contents[i][j][#contents[i][j] + 1] = "[crashed]"
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
	local volume, mute = line:match("^(%d+)%s*(%w+)$")
	return volume, mute and mute == "yes"
end

local brightness_pipe = Pipe:new_of_cmd([[
	script -qc "udevadm monitor --udev --subsystem-match=backlight" /dev/null | while read -r _; do
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

local text = Section:new(Pipe:new_of_cmd("echo hello world"))
function text:format(line)
	return { line }
end

return bar_run({
	{ text },
	{ net },
	{ temp },
	{ bat },
	{ cpu, mem, disk },
	{ brightness, volume, updates_count, clock },
})
