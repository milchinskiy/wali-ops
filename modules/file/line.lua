local lib = require("wali.builtin.lib")

local function validate_non_empty(value, field)
	if value == nil or value == "" or value:match("%S") == nil then
		return lib.validation_error(field .. " must not be empty")
	end
	return nil
end

local function line_present(content, line)
	local text = content
	if text:sub(-1) ~= "\n" then
		text = text .. "\n"
	end
	return ("\n" .. text):find("\n" .. line .. "\n", 1, true) ~= nil
end

local function append_line(content, line)
	if content == "" then
		return line .. "\n"
	end
	if content:sub(-1) == "\n" then
		return content .. line .. "\n"
	end
	return content .. "\n" .. line .. "\n"
end

return {
	name = "file line",
	description = "Append an exact line to a UTF-8 text file when it is missing.",

	schema = {
		type = "object",
		required = true,
		props = {
			path = { type = "string", required = true },
			line = { type = "string", required = true },
			create = { type = "boolean", default = true },
			create_parents = { type = "boolean", default = false },
			mode = lib.schema.mode(),
			owner = lib.schema.owner(),
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
		return lib.validate_mode_owner(args)
	end,

	apply = function(ctx, args)
		local current = ctx.host.fs.stat(args.path)
		if current == nil then
			if not args.create then
				error("file does not exist and create is false: " .. args.path)
			end
			return ctx.host.fs.write(args.path, args.line .. "\n", lib.write_file_opts(args))
		end
		if current.kind ~= "file" then
			error("path must be a regular file: " .. args.path)
		end

		local content = ctx.host.fs.read_text(args.path)
		if line_present(content, args.line) then
			local result = lib.result.apply():unchanged(args.path, "line already exists")
			lib.apply_mode_owner(ctx, result, args.path, args)
			return result:build()
		end

		return ctx.host.fs.write(
			args.path,
			append_line(content, args.line),
			lib.write_file_opts({
				create_parents = false,
				replace = true,
				mode = args.mode,
				owner = args.owner,
			})
		)
	end,
}
