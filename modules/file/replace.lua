local lib = require("wali.builtin.lib")

local function validate_non_empty(value, field)
	if value == nil or value == "" or value:match("%S") == nil then
		return lib.validation_error(field .. " must not be empty")
	end
	return nil
end

local function plain_replace(content, needle, replacement, replace_all)
	local out = {}
	local index = 1
	local count = 0
	while true do
		local start_pos, end_pos = content:find(needle, index, true)
		if start_pos == nil then
			table.insert(out, content:sub(index))
			break
		end
		table.insert(out, content:sub(index, start_pos - 1))
		table.insert(out, replacement)
		count = count + 1
		index = end_pos + 1
		if not replace_all then
			table.insert(out, content:sub(index))
			break
		end
	end
	return table.concat(out), count
end

return {
	name = "file replace",
	description = "Replace literal text in a UTF-8 text file.",

	schema = {
		type = "object",
		required = true,
		props = {
			path = { type = "string", required = true },
			find = { type = "string", required = true },
			replace = { type = "string", required = true },
			all = { type = "boolean", default = true },
			mode = lib.schema.mode(),
			owner = lib.schema.owner(),
		},
	},

	validate = function(ctx, args)
		local err = lib.validate_absolute_path(ctx, args.path, "path")
		if err ~= nil then
			return err
		end
		err = validate_non_empty(args.find, "find")
		if err ~= nil then
			return err
		end
		return lib.validate_mode_owner(args)
	end,

	apply = function(ctx, args)
		local current = ctx.host.fs.stat(args.path)
		if current == nil then
			error("file does not exist: " .. args.path)
		end
		if current.kind ~= "file" then
			error("path must be a regular file: " .. args.path)
		end

		local content = ctx.host.fs.read_text(args.path)
		local updated, count = plain_replace(content, args.find, args.replace, args.all)
		if count == 0 then
			local result = lib.result.apply():unchanged(args.path, "text not found"):data({ replacements = 0 })
			lib.apply_mode_owner(ctx, result, args.path, args)
			return result:build()
		end

		local result = lib.result.apply()
		result:merge(ctx.host.fs.write(
			args.path,
			updated,
			lib.write_file_opts({
				create_parents = false,
				replace = true,
				mode = args.mode,
				owner = args.owner,
			})
		))
		return result:data({ replacements = count }):build()
	end,
}
