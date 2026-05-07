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
	if value:find(",", 1, true) ~= nil then
		return lib.validation_error(field .. " must not contain ','")
	end
	return nil
end

local function group_exists(ctx, name, timeout)
	return exec(ctx, "getent", { "group", name }, timeout).ok
end

local function validate_args(_, args)
	local err = validate_name(args.name, "name")
	if err ~= nil then
		return err
	end
	if args.gid ~= nil and args.gid < 0 then
		return lib.validation_error("gid must be zero or greater")
	end
	return nil
end

local function build_argv(args)
	local argv = {}
	if args.system then
		table.insert(argv, "--system")
	end
	if args.gid ~= nil then
		table.insert(argv, "--gid")
		table.insert(argv, tostring(args.gid))
	end
	table.insert(argv, args.name)
	return argv
end

return {
	name = "group create",
	description = "Create a local group with groupadd when it does not already exist.",
	requires = { all = { { command = "getent" }, { command = "groupadd" } } },

	schema = {
		type = "object",
		required = true,
		props = {
			name = { type = "string", required = true },
			gid = { type = "integer" },
			system = { type = "boolean", default = false },
			timeout = { type = "string" },
		},
	},

	validate = validate_args,

	apply = function(ctx, args)
		if group_exists(ctx, args.name, args.timeout) then
			return lib.result
				.apply()
				:command("unchanged", "groupadd " .. args.name)
				:message("group already exists")
				:data({ group = args.name })
				:build()
		end
		local argv = build_argv(args)
		checked(ctx, "groupadd", argv, args.timeout)
		return lib.result
			.apply()
			:command("updated", command_detail("groupadd", argv))
			:message("created group")
			:data({ group = args.name })
			:build()
	end,
}
