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

local function group_exists(ctx, name, timeout)
	return exec(ctx, "getent", { "group", name }, timeout).ok
end

return {
	name = "group remove",
	description = "Remove a local group with groupdel when it exists.",
	requires = { all = { { command = "getent" }, { command = "groupdel" } } },

	schema = {
		type = "object",
		required = true,
		props = {
			name = { type = "string", required = true },
			timeout = { type = "string" },
		},
	},

	validate = function(_, args)
		return validate_name(args.name, "name")
	end,

	apply = function(ctx, args)
		if not group_exists(ctx, args.name, args.timeout) then
			return lib.result
				.apply()
				:command("unchanged", "groupdel " .. args.name)
				:message("group is already absent")
				:data({ group = args.name })
				:build()
		end
		local argv = { args.name }
		checked(ctx, "groupdel", argv, args.timeout)
		return lib.result
			.apply()
			:command("updated", command_detail("groupdel", argv))
			:message("removed group")
			:data({ group = args.name })
			:build()
	end,
}
