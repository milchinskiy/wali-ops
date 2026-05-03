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

local function command_result(kind, detail, message, data)
	return lib.result.apply():command(kind, detail):message(message):data(data):build()
end

local function validate_service_name(name, field)
	field = field or "service"
	if name == nil or name == "" or name:match("%S") == nil then
		return lib.validation_error(field .. " must not be empty")
	end
	if name:find("%c") ~= nil then
		return lib.validation_error(field .. " must not contain control characters")
	end
	if name:find("%s") ~= nil then
		return lib.validation_error(field .. " must not contain whitespace")
	end
	if name:sub(1, 1) == "-" then
		return lib.validation_error(field .. " must not start with '-'")
	end
	if name:find("/", 1, true) ~= nil then
		return lib.validation_error(field .. " must not contain '/'")
	end
	return nil
end

local function target(ctx, args)
	return ctx.host.path.join(args.service_dir, args.service)
end

local function validate_runit_service(ctx, args)
	local err = validate_service_name(args.service, "service")
	if err ~= nil then
		return err
	end
	return lib.validate_absolute_path(ctx, args.service_dir, "service_dir")
end

return {
	name = "runit restart",
	description = "Restart a runit service with sv restart.",
	requires = { command = "sv" },

	schema = {
		type = "object",
		required = true,
		props = {
			service = { type = "string", required = true },
			service_dir = { type = "string", default = "/var/service" },
			timeout = { type = "string" },
		},
	},

	validate = validate_runit_service,

	apply = function(ctx, args)
		local path = target(ctx, args)
		local argv = { "restart", path }
		checked(ctx, "sv", argv, args.timeout)
		return command_result(
			"updated",
			command_detail("sv", argv),
			"runit command completed",
			{ service = args.service, path = path, action = "restart" }
		)
	end,
}
