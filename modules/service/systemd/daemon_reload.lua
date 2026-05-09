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

return {
	name = "systemd daemon reload",
	description = "Reload systemd manager configuration with systemctl daemon-reload.",
	requires = { command = "systemctl" },

	schema = {
		type = "object",
		required = true,
		props = { timeout = { type = "string" } },
	},

	apply = function(ctx, args)
		local argv = { "daemon-reload" }
		checked(ctx, "systemctl", argv, args.timeout)
		return command_result(
			"updated",
			command_detail("systemctl", argv),
			"systemd daemon reloaded",
			{ action = "daemon_reload" }
		)
	end,
}
