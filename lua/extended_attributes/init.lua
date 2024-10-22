-- local finders = require('telescope.finders')
-- local pickers = require('telescope.pickers')
-- local conf = require('telescope.config').values


local function attr_table_to_lines(opts, tbl)
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
				table.insert(result, string.format("%s attr: %s", opts.attribute_prefix, line))
			else
				table.insert(result, string.format("%s %s", opts.attribute_prefix, line))
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

-- local search_extended_attributes = function(opts)
-- 	if opts == nil then
-- 		return nil
-- 	end
--
-- 	local search_path = opts.search_path or '.'
-- 	local attribute_name = opts.attribute_name
-- 	local attribute_value = opts.attribute_value
--
-- 	local cmd = string.format(
-- 		"find %s -type f -exec sh -c 'getfattr -n %s --only-values \"$1\" 2>/dev/null | grep -q \"%s\" && echo \"$1\"' _ {} \\;",
-- 		search_path, attribute_name, attribute_value
-- 	)
--
-- 	-- Start a Telescope picker
-- 	pickers.new(opts, {
-- 		prompt_title = "Search Files with Extended Attributes",
-- 		finder = finders.new_job(function(prompt)
-- 			return { 'bash', '-c', cmd }
-- 		end, opts.entry_maker or conf.file_entry_maker),
-- 		sorter = conf.generic_sorter(opts),
-- 	}):find()
-- end

local function get_xattrs(opts, filepath)
	local attr_list_cmd = "attr -l \"" .. (filepath) .. "\"" .. " 2>/dev/null"
	local handle1 = io.popen(attr_list_cmd)
	if handle1 == nil then
		local err = string.format("Could not check extended attributes of file %s", filepath)
		vim.notify(err, vim.log.levels.ERROR)
		return
	end

	local attr_list_result = handle1:read("*a")
	handle1:close()

	local attrs = {}
	for name in attr_list_result:gmatch('Attribute%s+"(.-)"') do
		local attr_get_cmd = "attr -g \"" .. name .. "\" \"" .. filepath .. "\"" .. " 2>/dev/null"
		local handle2 = io.popen(attr_get_cmd)
		if handle2 == nil then
			local err = string.format("Could not check value of extended attribute %s", name)
			vim.notify(err, vim.log.levels.ERROR)
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

local function set_xattrs(opts, file, previous_attrs, current_attrs)
	-- Remove all attributes that have been deleted
	for key, _ in pairs(previous_attrs) do
		if not current_attrs[key] then
			local cmd = 'attr -r "' .. key .. '" "' .. file .. '"'

			local result = os.execute(cmd)
			if not result then
				local err = string.format("Could not remove extended attribute %s of file %s", key, file)
				vim.notify(err, vim.log.levels.ERROR)
			end
		end
	end

	-- Update all attributes that have been changed
	for key, value in pairs(current_attrs) do
		local cmd = 'setfattr -n "user.' .. key .. '" -v "' .. value .. '" "' .. file .. '"'

		local result = os.execute(cmd)
		if not result then
			local err = string.format("Could not set extended attribute %s of file %s", key, file)
			vim.notify(err, vim.log.levels.ERROR)
		end
	end
end

local function parse_xattrs(opts, content)
	-- Escape all special characters in the attribute_prefix
	local escaped_attribute_prefix = opts.attribute_prefix:gsub("([%.%-%*%+%?%^%$%[%]%(%)%\\])", "%%%1")

	local result = {}
	local key_builder = {}
	local value_builder = {}
	local in_key = false

	local function builder_to_string(tbl)
		return table.concat(tbl, "\n"):match("^(.-)%s*$")
	end

	for _, line in ipairs(content) do
		-- Parse key
		if in_key then
			if line:sub(1, #opts.attribute_prefix) == opts.attribute_prefix then
				table.insert(key_builder, line:match("^" .. escaped_attribute_prefix .. "%s*(.-)%s*$"))
				goto continue
			else
				in_key = false
			end
		end

		-- Found key
		local key_prefix = line:match("^" .. escaped_attribute_prefix .. "%s*attr:%s*(.-)%s*$")
		if key_prefix ~= nil then
			-- We have a previously created key-value pair
			if #key_builder > 0 then
				result[builder_to_string(key_builder)] = builder_to_string(value_builder)
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
		result[builder_to_string(key_builder)] = builder_to_string(value_builder)
	end

	return result
end

local M = {
	attribute_prefix = "#"
}

M._xattrs_buffer = function(file, xattrs_getter, buffer_writer)
	local xattrs = xattrs_getter(M, file)
	if xattrs == nil then
		return ""
	end

	local temp_file_path = vim.fn.tempname()
	vim.api.nvim_command("e " .. temp_file_path)

	local bufno = vim.api.nvim_get_current_buf()

	vim.bo[bufno].bufhidden = 'wipe'
	vim.bo[bufno].swapfile = false

	vim.api.nvim_buf_set_lines(bufno, 0, -1, false, buffer_writer(M, xattrs))
	vim.api.nvim_buf_call(bufno, function()
		vim.api.nvim_command("silent write")
	end)

	return temp_file_path
end

M._xattrs_buffer_write_hook = function(filepath, xattrs_buffer_parser, xattrs_writer)
	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = filepath,
		callback = function()
			local lines = vim.fn.readfile(filepath)
			local attrs = xattrs_buffer_parser(M, lines)
			xattrs_writer(M, attrs)
		end
	})
end

M.edit_xattrs = function(filepath)
	local file = filepath or vim.fn.expand("%:p")
	local current_attrs = get_xattrs(M, file)

	-- Create a buffer with the extended attributes
	local buf = M._xattrs_buffer(file, function(_, _) return current_attrs end, attr_table_to_lines)

	-- Create a write hook for the buffer to set the extended attributes
	M._xattrs_buffer_write_hook(buf, parse_xattrs, function(opts, new_attrs)
		set_xattrs(opts, file, current_attrs, new_attrs)
	end)
end

return M
