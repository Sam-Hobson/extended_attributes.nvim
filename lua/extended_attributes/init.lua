local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local conf = require('telescope.config').values


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


local function get_xattr()
	local file = vim.fn.expand('%:p')

	local handle = io.popen('getfattr -d ' .. file .. ' 2>/dev/null')
	local result = handle:read("*a")
	handle:close()

	if result == "" then
		print("No extended attributes found.")
	else
		-- Display the result in a preview window
		vim.cmd('new')
		vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(result, '\n'))
	end
end


local function set_xattr()
	local attr_name = vim.fn.input("Attribute name: ")
	local attr_value = vim.fn.input("Attribute value: ")
	local file = vim.fn.expand('%:p')

	local cmd = 'setfattr -n ' .. attr_name .. ' -v ' .. attr_value .. ' ' .. file
	local result = os.execute(cmd)

	if result == 0 then
		print("Extended attribute set successfully.")
	else
		print("Failed to set extended attribute.")
	end
end




local M = {}

M.setup = function(opts)
end

set_xattr()
get_xattr()


-- search_extended_attributes({
-- 	attribute_name = "user.type",
-- 	attribute_value = "main",
-- })

return M
