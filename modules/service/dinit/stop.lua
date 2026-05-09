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
return {
	name = "dinit stop",
	description = "Stop a dinit service when it is started.",
	requires = { command = "dinitctl" },

	schema = {
		type = "object",
		required = true,
		props = {
			service = { type = "string", required = true },
			timeout = { type = "string" },
		},
	},

	validate = function(_, args)
		return validate_service_name(args.service, "service")
	end,

	apply = function(ctx, args)
		if not exec(ctx, "dinitctl", { "--quiet", "is-started", args.service }, args.timeout).ok then
			return command_result(
				"unchanged",
				"dinitctl stop " .. args.service,
				"service is already inactive",
				{ service = args.service, action = "stop" }
			)
		end
		local argv = { "stop", args.service }
		checked(ctx, "dinitctl", argv, args.timeout)
		return command_result(
			"updated",
			command_detail("dinitctl", argv),
			"dinit command completed",
			{ service = args.service, action = "stop" }
		)
	end,
}
