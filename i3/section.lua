---@class SectionContent
---@field color string?
---@field [integer] string

---@class Section
---@field source number|Pipe
local Section = {}
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

return Section
