local Pipe = require("pipe")
local Section = require("section")

------

local Bar = {}
Bar.__index = Bar

---@param id string
---@param text string
---@param color string?
---@param do_show_sep boolean?
---@return string
local function section_render_tojson(id, text, color, do_show_sep)
	---@param s string?
	---@return string
	local function string_or_nil_tojson(s)
		return s and string.format("%q", s):gsub("\\\n", "\\n"):gsub("\\9", "\\t"):gsub("\\13", "\\r"):gsub("\\%d+", "")
			or "null"
	end

	return string.format(
		'{"name": %s, "full_text": %s, "color": %s, "markup": %s, "separator_block_width": %d, "separator": %s}',
		string_or_nil_tojson(id),
		string_or_nil_tojson(text),
		string_or_nil_tojson(color),
		string_or_nil_tojson((USE_PANGO or nil) and "pango"),
		do_show_sep and GROUP_SEP_WIDTH or SEP_WIDTH,
		do_show_sep and "true" or "false"
	)
end

---@param sections Section[][]
function Bar.run(sections)
	io.write('{"version": 1, "click_events": true}', "\n")
	io.write("[", "\n")
	io.flush()

	-- io.stdin:setvbuf("line")
	local inputs_pipe = Pipe:new(0)
	---@return {i: integer, j: integer}
	function inputs_pipe:transform(line)
		io.stderr:write(line, "\n")
		---@type string?, string?
		local i_str, j_str = line:match('"name":%s*"(%d+),(%d+)"')
		return { i = tonumber(i_str), j = tonumber(j_str) }
	end

	---@type {[integer]: Pipe}, integer[]
	local pipes, periods = { inputs_pipe }, {}
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
		local nonempty_pipes, crashed_pipes = Pipe.poll(pipes, closest_rem_time), {}

		local pipe_datas = {}
		for i, pipe in pairs(pipes) do
			if nonempty_pipes[pipe] then
				local data, err = pipe:read()
				if data then
					pipe_datas[pipe] = data
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

		if nonempty_pipes[inputs_pipe] and pipe_datas[inputs_pipe] then
			local inputs_pipe_data = pipe_datas[inputs_pipe]
			local event = table.unpack(inputs_pipe_data, nil, inputs_pipe_data.n)
			local xyzzy = table.get_in(contents, tonumber(event.i), tonumber(event.j))
			if xyzzy then
				xyzzy.color = "#00FFFF"
			end
		end

		---@type {id: string, text: string, color: string?, do_show_sep?: boolean}[]
		local renders = {}
		for i, group in ipairs(contents) do
			for j, content in ipairs(group) do
				renders[#renders + 1] = content
					and (#content > 0 or nil)
					and {
						id = i .. "," .. j,
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
			jsons[#jsons + 1] = section_render_tojson(render.id, render.text, render.color, render.do_show_sep)
		end
		io.write("[" .. table.concat(jsons, ",") .. "],", "\n")
		io.flush()
	end
end

return Bar
