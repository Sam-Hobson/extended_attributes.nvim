local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local conf = require('telescope.config').values


--[[
-- TODO: Handle multi line extended attributes, as they get b64 encoded.
-- Solution: Just use "attr" instead of "getfattr" and "setfattr"
--
-- TODO: Search files for attributes
--]]

local function table_to_list(tbl)
	local result = {}
	-- Iterate through each key-value pair in the table
	for key, value in pairs(tbl) do
		local entry = string.format('"%s"="%s"', key, tostring(value))
		table.insert(result, entry)
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
	for name in attr_list_result:gmatch("Attribute \"(.-)\"") do
		local attr_get_cmd = "attr -g \"" .. name .. "\" \"" .. filepath .. "\"" .. " 2>/dev/null"
		local handle2 = io.popen(attr_get_cmd)
		if handle2 == nil then
			vim.notify("Could not check value of extended attribute " .. name, vim.log.levels.ERROR)
			return
		end

		_ = handle2:read("*l") -- Skip the first line of output
		local value = handle2:read("*a")
		handle2:close()

		-- Remove the last byte from the result
		if (#value > 0) and (value:sub(-1) == "\n") then
			value = value:sub(1, -2)
		end

		attrs[name] = value
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

M.setup = function(opts)
end

---comment
---@param content string
---@return table
M._parse_xattrs = function(content)
	local attributes = {}

	for key, value in content:gmatch('user%.(%w+)%s*=%s*"(.-[^\\])"') do
		attributes[key] = value
	end

	return attributes
end

M.edit_xattrs = function(file)
	local xattrs = get_xattrs(file)
	if xattrs == nil then
		return
	end

	local temp_file_path = vim.fn.tempname()
	vim.api.nvim_command("e " .. temp_file_path)

	local bufno = vim.api.nvim_get_current_buf()

	vim.bo[bufno].bufhidden = 'wipe'
	vim.bo[bufno].swapfile = false

	vim.api.nvim_buf_set_lines(bufno, 0, -1, false, table_to_list(xattrs))
	vim.api.nvim_buf_call(bufno, function()
		vim.api.nvim_command("silent write")
	end)

	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = temp_file_path,
		callback = function()
			-- local lines = vim.fn.readfile(temp_file_path)
			-- local content = table.concat(lines, "\n")
			--
			-- local attrs = M._parse_xattrs(content)
			-- print(vim.inspect(attrs))
			-- M._set_xattrs(file, attrs)
		end
	})
end

M.edit_xattrs(vim.fn.expand("%:p"))

return M
