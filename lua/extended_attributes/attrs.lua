local M = {}

---Get the given files extended attributes and return them in a key-value table.
---@param opts table The plugin configuration
---@param filepath string The path to the file for which the extended attributes are retrieved.
---@return table attributes The key-value extended attributes for the given file.
M.get_file_attrs = function(opts, filepath)
	local attr_list_cmd = "attr -l \"" .. (filepath) .. "\"" .. " 2>/dev/null"
	local handle1 = io.popen(attr_list_cmd)
	if handle1 == nil then
		local err = string.format("Could not check extended attributes of file %s", filepath)
		vim.notify(err, vim.log.levels.ERROR)
		error("Could not check extended attributes of file")
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
			error("Could not check extended attributes of file")
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

---Set the extended attributes on the given file.
---@param opts table The plugin configuration
---@param filepath string The path to the file for which the extended attributes are set.
---@param previous_attrs table The previous extended attributes applied to the selected file.
---@param new_attrs table Then new extended attributes to be applied to the selected file.
M.set_file_attrs = function(opts, filepath, previous_attrs, new_attrs)
	-- Remove all attributes that have been deleted
	for key, _ in pairs(previous_attrs) do
		if not new_attrs[key] then
			local cmd = 'attr -r "' .. key .. '" "' .. filepath .. '"'

			local result = os.execute(cmd)
			if not result then
				local err = string.format("Could not remove extended attribute %s of file %s", key, filepath)
				vim.notify(err, vim.log.levels.ERROR)
			end
		end
	end

	-- Update all attributes that have been changed
	for key, value in pairs(new_attrs) do
		-- If key or value size exceed max system allow size, then apply strategy
		if opts.max_key_size and opts.max_key_size < #key then
			if opts.oversized_strategy == "halt" then
				error("Key size exceeds maximum key size of " .. opts.max_key_size)
			elseif opts.oversized_strategy == "truncate" then
				key = string.sub(key, 1, opts.max_key_size)
			end
		end
		if opts.max_value_size and opts.max_value_size < #value then
			if opts.oversized_strategy == "halt" then
				error("Value size exceeds maximum key size of " .. opts.max_value_size)
			elseif opts.oversized_strategy == "truncate" then
				value = string.sub(value, 1, opts.max_value_size)
			end
		end

		-- Set the new key-value pair
		local cmd = 'attr -s "' .. key .. '" -V "' .. value .. '" "' .. filepath .. '"'

		local result = os.execute(cmd)
		if not result then
			local err = string.format("Could not set extended attribute %s of file %s", key, filepath)
			vim.notify(err, vim.log.levels.ERROR)
		end
	end
end

---Convert key-value extended attributes into lines in a buffer to be displayed.
---@param opts table The plugin configuration
---@param extended_attributes table The extended attributes key-value pairs.
---@return table buffer-lines
M.buf_lines_marshal_attrs = function(opts, extended_attributes)
	local result = {}
	-- Iterate through each key-value pair in the table
	for key, value in pairs(extended_attributes) do
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
				table.insert(result, string.format("%s %s %s", opts.attribute_prefix, opts.attribute_keyword, line))
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

---Convert buffer content into key-value extended attributes.
---@param opts table The plugin configuration
---@param content table The lines of the extended attributes buffer
---@return table attributes Extended attributes key-value pairs.
M.unmarshal_attrs = function(opts, content)
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
		local key_prefix = line:match("^" .. escaped_attribute_prefix .. "%s*" .. opts.attribute_keyword .. "%s*(.-)%s*$")
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

return M
