# Neovim extended attributes

A convenient way to add, modify, and remove [extended attributes](https://en.wikipedia.org/wiki/Extended_file_attributes) on files while using Neovim.
This is great for saving persistent notes or data associated with a file, which can then be accessed through standard file system tooling.


## ⚡️ Requirements

- Most likely an XFS file system
- The [attr](https://man7.org/linux/man-pages/man1/attr.1.html) executable installed and available within your $PATH


## 📦 Installation

Install the plugin with your preferred package manager:


### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "sam-hobson/extended_attributes.nvim",
  opts = {}, -- for default options, refer to the configuration section for custom setup.
  cmd = "Xattrs",
  keys = {
    {
      "<leader>X",
      "<cmd>Xattrs<cr>",
      desc = "Edit extended attributes",
    },
  },
}
```


## 🚀 Usage

extended_attributes.nvim is used to modify the extended attributes on files.
Executing `Xattrs` will open a temporary buffer for the current or specified file,
where extended attributes can be modified, created, and deleted.

Eg:
`:Xattrs <optional filename>`

Buffer:
```
# attr: my first attribute
This is the value of the attribute

# attr: This is my second attribute
#
# newline
This is my second attribute value

newline
```

Result:
```sh
$ attr example_file -l
Attribute "my first attribute" has a 34 byte value for example_file
Attribute "This is my second attribute

newline" has a 42 byte value for example_file

$ attr example_file -g "my first attribute"
Attribute "my first attribute" had a 34 byte value for example_file:
This is the value of the attribute

$ attr example_file -g "This is my second attribute

newline"
Attribute "This is my second attribute

newline" had a 42 byte value for example_file:
This is my second attribute value

newline
```


## ⚙️ Configuration

The default settings applied to the plugin are:
```lua
require("extended_attributes").setup({
	attribute_prefix = "#",  -- The prefix of attribute name/key sections. (Non-empty)
	attribute_keyword = "attr:",  -- The string that denotes the start of an attribute name/key. (Non-empty)
	max_key_size = 256,  -- The maximum number of bytes for a attribute name/key on your file system. (Greater than 0, or nil for infinite)
	max_value_size = 65536,  -- The maximum number of bytes for a attribute value on your file system. (Greater than 0, or nil for infinite)
	oversized_strategy = "truncate",  -- The strategy used when the length of a key/value exceeds the maximum allowed size. ("truncate" or "halt")
})
```


extended_attributes.nvim is highly configurable, and can be modified to suit your needs.

| Function                                                      | Description                                                                                         |
|---------------------------------------------------------------|-----------------------------------------------------------------------------------------------------|
| `get_file_attrs(opts, filepath)`                              | Retrieves extended attributes of a file and returns them in key-value pairs.                        |
| `set_file_attrs(opts, filepath, previous_attrs, new_attrs)`   | Sets new extended attributes on a file, using previous attributes as reference.                     |
| `buf_lines_marshal_attrs(opts, attrs)`                        | Converts attribute data into a format suitable for buffer line display. (table of lines to display) |
| `unmarshal_attrs(opts, content)`                              | Extracts and interprets attributes from the content.                                                |


For example:
```lua
require("extended_attributes").setup({
	attribute_prefix = "#",
	attribute_keyword = "attr:",
	max_key_size = 256,
	max_value_size = 65536,
	oversized_strategy = "truncate",
	get_file_attrs = function(opts, filepath)
		local attr_list_cmd = 'attr -l "' .. (filepath) .. '"'
		local handle1 = io.popen(attr_list_cmd)

		local attr_list_result = handle1:read("*a")
		handle1:close()

		local attrs = {}
		for name in attr_list_result:gmatch('Attribute%s+"(.-)"') do
			local attr_get_cmd = 'attr -g "' .. name .. '" "' .. filepath .. '"'
			local handle2 = io.popen(attr_get_cmd)

			local data = handle2:read("*a")
			handle2:close()

			local attribute, value = data:match('Attribute%s+"(.-)"%s+had%sa%s%d+%sbyte%svalue%sfor%s.-:%s*(.-)%s*$')
			attrs[attribute] = value
		end

		return attrs
	end,
	set_file_attrs = function(opts, filepath, previous_attrs, new_attrs)
		-- Update all attributes that have been changed
		for key, value in pairs(new_attrs) do
			local cmd = 'setfattr -n "' .. key .. '" -v "' .. value .. '" "' .. filepath .. '"'
			os.execute(cmd)
		end
	end,
})
```
IMPORTANT NOTE: The above code is an example and is not intended to be functional.


## Contributing
This is the first Neovim plugin I've written so feel free to give any and all feedback, and report any issues that come up.
Feature requests are also welcome!
