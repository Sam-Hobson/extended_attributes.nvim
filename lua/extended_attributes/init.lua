local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local conf = require('telescope.config').values


--[[
-- TODO: Handle multi line extended attributes, as they get b64 encoded.
-- Solution: Just use "attr" instead of "getfattr" and "setfattr"
--
-- TODO: Search files for attributes
--]]

local function attr_table_to_lines(tbl, attribute_prefix)
	attribute_prefix = attribute_prefix or "---"

	local result = {}
	-- Iterate through each key-value pair in the table
	for key, value in pairs(tbl) do
		local first_line_key = true

		for line in key:gmatch("([^\n]*\n?)") do
			-- At the end of the line
			if line == "" then
				break
			end

			-- Remove new line
			if line:sub(-1) == "\n" then
				line = line:sub(1, -2)
			end

			if first_line_key then
				table.insert(result, string.format("%s attr: %s", attribute_prefix, line))
			else
				table.insert(result, string.format("%s %s", attribute_prefix, line))
			end

			first_line_key = false
		end

		for line in value:gmatch("([^\n]*\n?)") do
			-- At the end of the line
			if line == "" then
				break
			end

			-- Remove new line
			if line:sub(-1) == "\n" then
				line = line:sub(1, -2)
			end

			table.insert(result, line)
		end

		table.insert(result, "")
	end

	return result
end

local search_extended_attributes = function(opts)
	if opts == nil then
		return nil
	end

	local search_path = opts.search_path or '.'
	local attribute_name = opts.attribute_name
	local attribute_value = opts.attribute_value

	local cmd = string.format(
		"find %s -type f -exec sh -c 'getfattr -n %s --only-values \"$1\" 2>/dev/null | grep -q \"%s\" && echo \"$1\"' _ {} \\;",
		search_path, attribute_name, attribute_value
	)

	-- Start a Telescope picker
	pickers.new(opts, {
		prompt_title = "Search Files with Extended Attributes",
		finder = finders.new_job(function(prompt)
			return { 'bash', '-c', cmd }
		end, opts.entry_maker or conf.file_entry_maker),
		sorter = conf.generic_sorter(opts),
	}):find()
end

local function get_xattrs(filepath)
	local attr_list_cmd = "attr -l \"" .. (filepath) .. "\"" .. " 2>/dev/null"
	local handle1 = io.popen(attr_list_cmd)
	if handle1 == nil then
		vim.notify("Could not check extended attributes of file " .. filepath, vim.log.levels.ERROR)
		return
	end

	local attr_list_result = handle1:read("*a")
	handle1:close()

	local attrs = {}
	for name in attr_list_result:gmatch('Attribute%s+"(.-)"') do
		local attr_get_cmd = "attr -g \"" .. name .. "\" \"" .. filepath .. "\"" .. " 2>/dev/null"
		local handle2 = io.popen(attr_get_cmd)
		if handle2 == nil then
			vim.notify("Could not check value of extended attribute " .. name, vim.log.levels.ERROR)
			return
		end

		local data = handle2:read("*a")
		handle2:close()

		local attribute, value = data:match('Attribute%s+"(.-)"%s+had%sa%s%d+%sbyte%svalue%sfor%s.-:%s*(.-)%s*$')

		if attribute then
			attrs[attribute] = value
		end
	end

	return attrs
end

local M = {}

---comment
---@param file string
---@param attrs table
M._set_xattrs = function(file, attrs)
	for key, value in pairs(attrs) do
		local cmd = 'setfattr -n user.' .. key .. ' -v "' .. value .. '" "' .. file .. '"'
		local result = os.execute(cmd)

		-- TODO: Handle result
	end
end

---comment
---@param content string[]
---@return table
M._parse_xattrs = function(content, attribute_prefix)
	-- Escape all special characters in the attribute_prefix
	local escaped_attribute_prefix = attribute_prefix:gsub("([%.%-%*%+%?%^%$%[%]%(%)%\\])", "%%%1")

	local result = {}
	local key_builder = {}
	local value_builder = {}
	local in_key = false

	for _, line in ipairs(content) do
		-- Parse key
		if in_key then
			if line:sub(1, #attribute_prefix) == attribute_prefix then
				table.insert(key_builder, line:match("^" .. escaped_attribute_prefix .. "%s*(%S*)%s*"))
				goto continue
			else
				in_key = false
			end
		end

		-- Found key
		local key_prefix = line:match("^" .. escaped_attribute_prefix .. "%s*attr:%s*(%S+)%s*")
		if key_prefix ~= nil then
			-- We have a previously created key-value pair
			if #key_builder > 0 then
				result[table.concat(key_builder, "\n")] = table.concat(value_builder, "\n")
				key_builder = {}
				value_builder = {}
			end

			table.insert(key_builder, key_prefix)
			in_key = true
			goto continue
		end

		-- Deal with value, if there is no key, skip
		if #key_builder == 0 then
			goto continue
		end

		table.insert(value_builder, line)

		::continue::
	end

	if #key_builder > 0 then
		result[table.concat(key_builder, "\n")] = table.concat(value_builder, "\n")
	end

	return result
end

---comment
---@param file string
---@return string
M.xattrs_buffer = function(file)
	local xattrs = get_xattrs(file)
	if xattrs == nil then
		return ""
	end

	local temp_file_path = vim.fn.tempname()
	vim.api.nvim_command("e " .. temp_file_path)

	local bufno = vim.api.nvim_get_current_buf()

	vim.bo[bufno].bufhidden = 'wipe'
	vim.bo[bufno].swapfile = false

	vim.api.nvim_buf_set_lines(bufno, 0, -1, false, attr_table_to_lines(xattrs))
	vim.api.nvim_buf_call(bufno, function()
		vim.api.nvim_command("silent write")
	end)

	return temp_file_path
end

M.xattrs_buffer_write_hook = function(filepath, xattrs_buffer_parser)
	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = filepath,
		callback = function()
			local lines = vim.fn.readfile(filepath)
			local attrs = xattrs_buffer_parser(lines, "---")
			-- M._set_xattrs(file, attrs)
		end
	})
end

local buf = M.xattrs_buffer(vim.fn.expand("%:p"))
M.xattrs_buffer_write_hook(buf, M._parse_xattrs)

return M
