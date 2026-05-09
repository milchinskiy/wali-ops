require("compat")
local lib = require("wali.builtin.lib")

local function command_detail(program, argv)
	if argv == nil or #argv == 0 then
		return program
	end
	return program .. " " .. table.concat(argv, " ")
end

local function exec(ctx, program, argv, timeout)
	return ctx.host.cmd.exec({ program = program, args = argv or {}, timeout = timeout })
end

local function checked(ctx, program, argv, timeout)
	local output = exec(ctx, program, argv, timeout)
	lib.assert_command_ok(output, command_detail(program, argv))
	return output
end

local function validate_name(value, field)
	field = field or "name"
	if value == nil or value == "" or value:match("%S") == nil then
		return lib.validation_error(field .. " must not be empty")
	end
	if value:find("%c") ~= nil then
		return lib.validation_error(field .. " must not contain control characters")
	end
	if value:find("%s") ~= nil then
		return lib.validation_error(field .. " must not contain whitespace")
	end
	if value:sub(1, 1) == "-" then
		return lib.validation_error(field .. " must not start with '-'")
	end
	if value:find(":", 1, true) ~= nil then
		return lib.validation_error(field .. " must not contain ':'")
	end
	if value:find("/", 1, true) ~= nil then
		return lib.validation_error(field .. " must not contain '/'")
	end
	return nil
end

local function user_exists(ctx, name, timeout)
	return exec(ctx, "getent", { "passwd", name }, timeout).ok
end

return {
	name = "user remove",
	description = "Remove a local user account with userdel when it exists.",
	requires = { all = { { command = "getent" }, { command = "userdel" } } },

	schema = {
		type = "object",
		required = true,
		props = {
			name = { type = "string", required = true },
			remove_home = { type = "boolean", default = false },
			force = { type = "boolean", default = false },
			timeout = { type = "string" },
		},
	},

	validate = function(_, args)
		return validate_name(args.name, "name")
	end,

	apply = function(ctx, args)
		if not user_exists(ctx, args.name, args.timeout) then
			return lib.result
				.apply()
				:command("unchanged", "userdel " .. args.name)
				:message("user is already absent")
				:data({ user = args.name })
				:build()
		end
		local argv = {}
		if args.force then
			table.insert(argv, "--force")
		end
		if args.remove_home then
			table.insert(argv, "--remove")
		end
		table.insert(argv, args.name)
		checked(ctx, "userdel", argv, args.timeout)
		return lib.result
			.apply()
			:command("updated", command_detail("userdel", argv))
			:message("removed user")
			:data({ user = args.name })
			:build()
	end,
}
