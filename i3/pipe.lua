local perrno = require("posix.errno")
local punistd = require("posix.unistd")
local pfcntl = require("posix.fcntl")
local ppoll = require("posix.poll")
local pwait = require("posix.sys.wait")
local psocket = require("posix.sys.socket")

--- pipe ---

---@class Pipe
---@field _fd integer
---@field _buf string[]
local Pipe = {}
Pipe.__index = Pipe

---@param fd integer
---@return Pipe
function Pipe:new(fd)
	if fd >= 0 then
		pfcntl.fcntl(fd, pfcntl.F_SETFL, bit.bor(pfcntl.fcntl(fd, pfcntl.F_GETFL), pfcntl.O_NONBLOCK))
	end

	local s = setmetatable({}, self)
	s._buf = {}
	s._fd = fd
	return s
end

---@param path string
---@return Pipe
function Pipe:new_of_unix_socket(path)
	local sock = psocket.socket(psocket.AF_UNIX, psocket.SOCK_STREAM, 0)
	if sock then
		psocket.connect(sock, { family = psocket.AF_UNIX, path = path })
	end

	local s = Pipe:new(sock or -1)
	if sock then
		function s._close()
			punistd.close(sock)
		end
	end
	return s
end

---@param cmd string
---@param shell string? a shell name or path, defaults to `/bin/sh`
---@return Pipe
function Pipe:new_of_cmd(cmd, shell)
	shell = shell or "/bin/sh"

	---@alias PosixPipe {fd: integer, pid: integer}
	---@param exe string
	---@vararg string
	---@return PosixPipe?, string?
	local function popen(exe, ...)
		local r_fd, w_fd = punistd.pipe()
		if not r_fd then
			return nil, w_fd
		end

		local pid, err = punistd.fork()
		if not pid then
			punistd.close(r_fd)
			punistd.close(w_fd)
			return nil, err
		end

		if pid == 0 then
			punistd.close(r_fd)

			local devnull_r_fd, devnull_w_fd =
				pfcntl.open("/dev/null", pfcntl.O_RDONLY), pfcntl.open("/dev/null", pfcntl.O_WRONLY)
			if not devnull_r_fd or not devnull_w_fd then
				os.exit(-2)
			end

			punistd.dup2(devnull_r_fd, 0)
			punistd.close(devnull_r_fd)

			punistd.dup2(w_fd, 1)
			punistd.close(w_fd)

			punistd.dup2(devnull_w_fd, 2)
			punistd.close(devnull_w_fd)

			punistd.execp(exe, { ... })
			os.exit(-1)
		else
			punistd.close(w_fd)

			return { fd = r_fd, pid = pid }
		end
	end
	---@param pipe PosixPipe
	---@return string?, integer?
	local function pclose(pipe)
		punistd.close(pipe.fd)
		local _, reason, code = pwait.wait(pipe.pid)
		return reason, code
	end

	local ppipe = popen(shell, "-c", cmd)

	local s = Pipe:new(ppipe and ppipe.fd or -1)
	if ppipe then
		function s._close()
			local reason, code = pclose(ppipe)
			-- it's still ok if the pipe has closed yet the process exited successfully
			return reason == "exited" and code == 0
		end
	end
	return s
end

---@return boolean?
function Pipe:_close() end

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
		local str, err, errno = punistd.read(self._fd, 4096)
		if not str then
			return nil, (errno == perrno.EAGAIN or errno == perrno.EWOULDBLOCK) and "again" or err
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

---@param selves Pipe[]
---@param timeout number? seconds
---@return {[Pipe]: boolean}
function Pipe.poll(selves, timeout)
	---@type table
	local fds = {}
	for _, pipe in pairs(selves) do
		fds[pipe._fd] = { events = { IN = true, HUP = true, ERR = true, NVAL = true }, pipe = pipe }
	end

	---@type {[Pipe]: boolean}
	local nonempty_pipes = {}
	local count = ppoll.poll(fds, timeout and timeout * 1000)
	if count > 0 then
		for _, info in pairs(fds) do
			nonempty_pipes[info.pipe] = info.revents.IN or info.revents.HUP or info.revents.ERR or info.revents.NVAL
		end
	end

	return nonempty_pipes
end

return Pipe
