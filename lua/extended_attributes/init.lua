local attrs = require("extended_attributes.attrs")

local M = {}


-- Config values
M.attribute_prefix = "#"

-- Config functions
M.get_file_attrs = attrs.get_file_attrs
M.set_file_attrs = attrs.set_file_attrs
M.buf_lines_marshal_attrs = attrs.buf_lines_marshal_attrs
M.unmarshal_attrs = attrs.unmarshal_attrs


---Edit the extended attributes of the provided file. This function should probably not
---be modified/overwritten by users.
---@param filepath string The path to the file to modify the extended attributes of.
M._edit_file_attrs = function(filepath)
	local ok, current_attrs = pcall(M.get_file_attrs, M, filepath)
	if not ok then
		return
	end

	-- Create a buffer with the extended attributes
	local temp_file_path = vim.fn.tempname()
	vim.api.nvim_command("e " .. temp_file_path)

	local bufno = vim.api.nvim_get_current_buf()

	vim.bo[bufno].bufhidden = 'wipe'
	vim.bo[bufno].swapfile = false

	vim.api.nvim_buf_set_lines(bufno, 0, -1, false, M.buf_lines_marshal_attrs(M, current_attrs))
	vim.api.nvim_buf_call(bufno, function()
		vim.api.nvim_command("silent write")
	end)

	-- Create a write hook for the buffer to set the extended attributes
	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = temp_file_path,
		callback = function()
			local lines = vim.fn.readfile(temp_file_path)
			local new_attrs = M.unmarshal_attrs(M, lines)
			M.set_file_attrs(M, filepath, current_attrs, new_attrs)
		end
	})
end


M.setup = function(setup_opts)
	-- Apply user configuration
	if setup_opts then
		for key, value in pairs(setup_opts) do
			if M[key] ~= nil then
				M[key] = value
			end
		end
	end

	-- Create user command for editing extended attributes
	vim.api.nvim_create_user_command("Xattrs",
		function(opts)
			local filepath = opts.args ~= "" and opts.args or vim.api.nvim_buf_get_name(0)
			M._edit_file_attrs(filepath)
		end,
		{ nargs = "?" }
	)
end

return M
