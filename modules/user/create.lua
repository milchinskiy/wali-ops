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
	if value:find(",", 1, true) ~= nil then
		return lib.validation_error(field .. " must not contain ','")
	end
	return nil
end

local function user_exists(ctx, name, timeout)
	return exec(ctx, "getent", { "passwd", name }, timeout).ok
end

local function validate_args(ctx, args)
	local err = validate_name(args.name, "name")
	if err ~= nil then
		return err
	end
	if args.uid ~= nil and args.uid < 0 then
		return lib.validation_error("uid must be zero or greater")
	end
	if args.group ~= nil then
		err = validate_name(args.group, "group")
		if err ~= nil then
			return err
		end
	end
	for index, group in ipairs(args.groups or {}) do
		err = validate_name(group, "groups[" .. tostring(index) .. "]")
		if err ~= nil then
			return err
		end
	end
	if args.home ~= nil then
		err = lib.validate_absolute_path(ctx, args.home, "home")
		if err ~= nil then
			return err
		end
	end
	if args.shell ~= nil then
		err = lib.validate_absolute_path(ctx, args.shell, "shell")
		if err ~= nil then
			return err
		end
	end
	return nil
end

local function build_argv(args)
	local argv = {}
	if args.system then
		table.insert(argv, "--system")
	end
	if args.uid ~= nil then
		table.insert(argv, "--uid")
		table.insert(argv, tostring(args.uid))
	end
	if args.group ~= nil then
		table.insert(argv, "--gid")
		table.insert(argv, args.group)
	end
	if args.groups ~= nil and #args.groups > 0 then
		table.insert(argv, "--groups")
		table.insert(argv, table.concat(args.groups, ","))
	end
	if args.home ~= nil then
		table.insert(argv, "--home-dir")
		table.insert(argv, args.home)
	end
	if args.create_home == true then
		table.insert(argv, "--create-home")
	elseif args.create_home == false then
		table.insert(argv, "--no-create-home")
	end
	if args.shell ~= nil then
		table.insert(argv, "--shell")
		table.insert(argv, args.shell)
	end
	if args.comment ~= nil then
		table.insert(argv, "--comment")
		table.insert(argv, args.comment)
	end
	table.insert(argv, args.name)
	return argv
end

return {
	name = "user create",
	description = "Create a local user account with useradd when it does not already exist.",
	requires = { all = { { command = "getent" }, { command = "useradd" } } },

	schema = {
		type = "object",
		required = true,
		props = {
			name = { type = "string", required = true },
			uid = { type = "integer" },
			group = { type = "string" },
			groups = { type = "list", items = { type = "string" } },
			home = { type = "string" },
			create_home = { type = "boolean" },
			shell = { type = "string" },
			comment = { type = "string" },
			system = { type = "boolean", default = false },
			timeout = { type = "string" },
		},
	},

	validate = validate_args,

	apply = function(ctx, args)
		if user_exists(ctx, args.name, args.timeout) then
			return lib.result
				.apply()
				:command("unchanged", "useradd " .. args.name)
				:message("user already exists")
				:data({ user = args.name })
				:build()
		end
		local argv = build_argv(args)
		checked(ctx, "useradd", argv, args.timeout)
		return lib.result
			.apply()
			:command("updated", command_detail("useradd", argv))
			:message("created user")
			:data({ user = args.name })
			:build()
	end,
}
