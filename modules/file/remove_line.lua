local lib = require("wali.builtin.lib")

local function validate_non_empty(value, field)
	if value == nil or value == "" or value:match("%S") == nil then
		return lib.validation_error(field .. " must not be empty")
	end
	return nil
end

local function remove_matching_lines(content, line, remove_all)
	local out = {}
	local index = 1
	local removed = 0

	while index <= #content do
		local newline = content:find("\n", index, true)
		local current
		local has_newline
		if newline ~= nil then
			current = content:sub(index, newline - 1)
			has_newline = true
			index = newline + 1
		else
			current = content:sub(index)
			has_newline = false
			index = #content + 1
		end

		if current == line and (remove_all or removed == 0) then
			removed = removed + 1
		else
			table.insert(out, current)
			if has_newline then
				table.insert(out, "\n")
			end
		end
	end

	return table.concat(out), removed
end

return {
	name = "file remove line",
	description = "Remove exact line occurrences.",

	schema = {
		type = "object",
		required = true,
		props = {
			path = { type = "string", required = true },
			line = { type = "string", required = true },
			all = { type = "boolean", default = true },
			missing_ok = { type = "boolean", default = true },
		},
	},

	validate = function(ctx, args)
		local err = lib.validate_absolute_path(ctx, args.path, "path")
		if err ~= nil then
			return err
		end
		err = validate_non_empty(args.line, "line")
		if err ~= nil then
			return err
		end
		if args.line:find("\n", 1, true) ~= nil or args.line:find("\r", 1, true) ~= nil then
			return lib.validation_error("line must be a single line")
		end
		return nil
	end,

	apply = function(ctx, args)
		local current = ctx.host.fs.stat(args.path)
		if current == nil then
			if not args.missing_ok then
				error("file does not exist: " .. args.path)
			end
			return lib.result
				.apply()
				:unchanged(args.path, "file does not exist")
				:data({ removals = 0 })
				:build()
		end
		if current.kind ~= "file" then
			error("path must be a regular file: " .. args.path)
		end

		local content = ctx.host.fs.read_text(args.path)
		local updated, removed = remove_matching_lines(content, args.line, args.all)
		if removed == 0 then
			return lib.result.apply():unchanged(args.path, "line not found"):data({ removals = 0 }):build()
		end

		local result = lib.result.apply()
		result:merge(ctx.host.fs.write(
			args.path,
			updated,
			lib.write_file_opts({
				create_parents = false,
				replace = true,
			})
		))
		return result:data({ removals = removed }):build()
	end,
}
