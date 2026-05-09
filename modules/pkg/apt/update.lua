require("compat")
local lib = require("wali.builtin.lib")

local function command_detail(program, argv)
	if argv == nil or #argv == 0 then
		return program
	end
	return program .. " " .. table.concat(argv, " ")
end

local function exec(ctx, program, argv, timeout, env)
	return ctx.host.cmd.exec({
		program = program,
		args = argv or {},
		timeout = timeout,
		env = env,
	})
end

local function checked(ctx, program, argv, timeout, env)
	local output = exec(ctx, program, argv, timeout, env)
	lib.assert_command_ok(output, command_detail(program, argv))
	return output
end

local function command_result(kind, detail, message, packages, action)
	local copied = {}
	for _, name in ipairs(packages or {}) do
		table.insert(copied, name)
	end
	return lib.result
		.apply()
		:command(kind, detail)
		:message(message)
		:data({ action = action, packages = copied })
		:build()
end

local env = { DEBIAN_FRONTEND = "noninteractive" }

return {
	name = "apt update",
	description = "Update Debian package indexes with apt-get update.",
	requires = { command = "apt-get" },

	schema = {
		type = "object",
		required = true,
		props = { timeout = { type = "string" } },
	},

	apply = function(ctx, args)
		local argv = { "update" }
		checked(ctx, "apt-get", argv, args.timeout, env)
		return command_result("updated", command_detail("apt-get", argv), "updated package indexes", {}, "update")
	end,
}
