local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local conf = require('telescope.config').values


--[[
-- TODO: Handle multi line extended attributes, as they get b64 encoded.
-- Solution: Just use "attr" instead of "getfattr" and "setfattr"
--
-- TODO: Search files for attributes
--]]

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


---Get the extended attributes for the given file/filepath.
---@param file string
---@return string[] | nil
local function get_xattrs(file)
	local handle = io.popen('getfattr -d ' .. file .. ' 2>/dev/null')
	if handle == nil then
		vim.notify("Could not get metadata on file \"" .. file .. "\".", vim.log.levels.ERROR)
		return nil
	end

	local result = handle:read("*a")
	handle:close()

	if result == "" then
		vim.notify("No extended attributes found.", vim.log.levels.INFO)
		return nil
	end

	return vim.split(result, "\n")
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
	file = file or vim.fn.expand('%:p')
	local xattrs = get_xattrs(file)
	if xattrs == nil then
		return
	end

	local temp_file_path = vim.fn.tempname()
	vim.api.nvim_command("e " .. temp_file_path)

	local bufno = vim.api.nvim_get_current_buf()

	vim.bo[bufno].bufhidden = 'wipe'
	vim.bo[bufno].swapfile = false

	vim.api.nvim_buf_set_lines(bufno, 0, -1, false, xattrs)
	vim.api.nvim_buf_call(bufno, function()
		vim.api.nvim_command("silent write")
	end)

	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = temp_file_path,
		callback = function()
			local lines = vim.fn.readfile(temp_file_path)
			local content = table.concat(lines, "\n")

			local attrs = M._parse_xattrs(content)
			print(vim.inspect(attrs))
			M._set_xattrs(file, attrs)
		end
	})
end

M.edit_xattrs()

return M
