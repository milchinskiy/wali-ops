require("compat")
local lib = require("wali.builtin.lib")

local function validate_non_empty(value, field)
	if value == nil or value == "" or value:match("%S") == nil then
		return lib.validation_error(field .. " must not be empty")
	end
	if value:find("%c") ~= nil then
		return lib.validation_error(field .. " must not contain control characters")
	end
	return nil
end

local function command_detail(program, argv)
	if argv == nil or #argv == 0 then
		return program
	end
	return program .. " " .. table.concat(argv, " ")
end

local function checked(ctx, program, argv, timeout)
	local output = ctx.host.cmd.exec({ program = program, args = argv or {}, timeout = timeout })
	lib.assert_command_ok(output, command_detail(program, argv))
	return output
end

return {
	name = "wget download",
	description = "Download a URL to a file with wget.",
	requires = { command = "wget" },

	schema = {
		type = "object",
		required = true,
		props = {
			url = { type = "string", required = true },
			dest = { type = "string", required = true },
			parents = { type = "boolean", default = false },
			replace = { type = "boolean", default = true },
			timeout = { type = "string" },
			mode = lib.schema.mode(),
			owner = lib.schema.owner(),
		},
	},

	validate = function(ctx, args)
		local err = validate_non_empty(args.url, "url")
		if err ~= nil then
			return err
		end
		err = lib.validate_absolute_path(ctx, args.dest, "dest")
		if err ~= nil then
			return err
		end
		return lib.validate_mode_owner(args)
	end,

	apply = function(ctx, args)
		if not args.replace and ctx.host.fs.exists(args.dest) then
			return lib.skip("destination already exists and replace is false: " .. args.dest)
		end

		local result = lib.result.apply()
		local parent = ctx.host.path.parent(args.dest)
		if args.parents then
			result:merge(ctx.host.fs.create_dir(parent, { recursive = true }))
		end

		local tmp = ctx.host.fs.mktemp({ parent_dir = parent, prefix = ".wali-wget-" })
		local ok, err = pcall(function()
			checked(ctx, "wget", { "--output-document", tmp, "--", args.url }, args.timeout)
			result:merge(ctx.host.fs.rename(tmp, args.dest, { replace = true }))
			lib.apply_mode_owner(ctx, result, args.dest, args)
		end)
		if not ok then
			pcall(function()
				ctx.host.fs.remove_file(tmp)
			end)
			error(err)
		end
		return result:message("downloaded file"):data({ url = args.url, dest = args.dest }):build()
	end,
}
