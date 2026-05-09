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

local function validate_package_name(name, field)
	field = field or "package"
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
	return nil
end

local function validate_packages(packages, required)
	if packages == nil then
		if required == false then
			return nil
		end
		return lib.validation_error("packages is required")
	end
	if #packages == 0 then
		return lib.validation_error("packages must not be empty")
	end
	for index, name in ipairs(packages) do
		local err = validate_package_name(name, "packages[" .. tostring(index) .. "]")
		if err ~= nil then
			return err
		end
	end
	return nil
end

local function is_installed(ctx, name, timeout)
	return exec(ctx, "apk", { "info", "-e", name }, timeout).ok
end

return {
	name = "apk remove",
	description = "Remove one or more Alpine packages with apk when installed.",
	requires = { command = "apk" },

	schema = {
		type = "object",
		required = true,
		props = {
			packages = { type = "list", items = { type = "string" }, required = true },
			timeout = { type = "string" },
		},
	},

	validate = function(_, args)
		return validate_packages(args.packages, true)
	end,

	apply = function(ctx, args)
		local installed = {}
		for _, name in ipairs(args.packages) do
			if is_installed(ctx, name, args.timeout) then
				table.insert(installed, name)
			end
		end
		if #installed == 0 then
			return command_result("unchanged", "apk del", "all packages are already absent", args.packages, "remove")
		end
		local argv = { "del" }
		for _, name in ipairs(installed) do
			table.insert(argv, name)
		end
		checked(ctx, "apk", argv, args.timeout)
		return command_result("updated", command_detail("apk", argv), "removed packages", installed, "remove")
	end,
}
