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

local function has_change(args)
	return args.uid ~= nil
		or args.group ~= nil
		or args.groups ~= nil
		or args.home ~= nil
		or args.shell ~= nil
		or args.comment ~= nil
		or args.lock == true
		or args.unlock == true
end

local function validate_args(ctx, args)
	local err = validate_name(args.name, "name")
	if err ~= nil then
		return err
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
	if args.append_groups and args.groups == nil then
		return lib.validation_error("append_groups requires groups")
	end
	if args.home ~= nil then
		err = lib.validate_absolute_path(ctx, args.home, "home")
		if err ~= nil then
			return err
		end
	end
	if args.move_home and args.home == nil then
		return lib.validation_error("move_home requires home")
	end
	if args.shell ~= nil then
		err = lib.validate_absolute_path(ctx, args.shell, "shell")
		if err ~= nil then
			return err
		end
	end
	if args.lock and args.unlock then
		return lib.validation_error("lock and unlock are mutually exclusive")
	end
	if not has_change(args) then
		return lib.validation_error("at least one user update option is required")
	end
	return nil
end

local function build_argv(args)
	local argv = {}
	if args.uid ~= nil then
		table.insert(argv, "--uid")
		table.insert(argv, tostring(args.uid))
	end
	if args.group ~= nil then
		table.insert(argv, "--gid")
		table.insert(argv, args.group)
	end
	if args.groups ~= nil then
		if args.append_groups then
			table.insert(argv, "--append")
		end
		table.insert(argv, "--groups")
		table.insert(argv, table.concat(args.groups, ","))
	end
	if args.home ~= nil then
		table.insert(argv, "--home")
		table.insert(argv, args.home)
		if args.move_home then
			table.insert(argv, "--move-home")
		end
	end
	if args.shell ~= nil then
		table.insert(argv, "--shell")
		table.insert(argv, args.shell)
	end
	if args.comment ~= nil then
		table.insert(argv, "--comment")
		table.insert(argv, args.comment)
	end
	if args.lock then
		table.insert(argv, "--lock")
	end
	if args.unlock then
		table.insert(argv, "--unlock")
	end
	table.insert(argv, args.name)
	return argv
end

return {
	name = "user update",
	description = "Update a local user account with usermod.",
	requires = { all = { { command = "getent" }, { command = "usermod" } } },

	schema = {
		type = "object",
		required = true,
		props = {
			name = { type = "string", required = true },
			uid = { type = "integer" },
			group = { type = "string" },
			groups = { type = "list", items = { type = "string" } },
			append_groups = { type = "boolean", default = false },
			home = { type = "string" },
			move_home = { type = "boolean", default = false },
			shell = { type = "string" },
			comment = { type = "string" },
			lock = { type = "boolean", default = false },
			unlock = { type = "boolean", default = false },
			timeout = { type = "string" },
		},
	},

	validate = validate_args,

	apply = function(ctx, args)
		if not user_exists(ctx, args.name, args.timeout) then
			error("user does not exist: " .. args.name)
		end
		local argv = build_argv(args)
		checked(ctx, "usermod", argv, args.timeout)
		return lib.result
			.apply()
			:command("updated", command_detail("usermod", argv))
			:message("updated user")
			:data({ user = args.name })
			:build()
	end,
}
