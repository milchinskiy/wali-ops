require("compat")
local lib = require("wali.builtin.lib")

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
	return nil
end

local function validate_link_name(name)
	local err = validate_service_name(name, "name")
	if err ~= nil then
		return err
	end
	if name:find("/", 1, true) ~= nil then
		return lib.validation_error("name must not contain '/'")
	end
	return nil
end

return {
	name = "runit enable",
	description = "Enable a runit service by linking source_dir/name into service_dir.",

	schema = {
		type = "object",
		required = true,
		props = {
			name = { type = "string", required = true },
			source_dir = { type = "string", default = "/etc/sv" },
			service_dir = { type = "string", default = "/var/service" },
		},
	},

	validate = function(ctx, args)
		local err = validate_link_name(args.name)
		if err ~= nil then
			return err
		end
		err = lib.validate_absolute_path(ctx, args.source_dir, "source_dir")
		if err ~= nil then
			return err
		end
		return lib.validate_absolute_path(ctx, args.service_dir, "service_dir")
	end,

	apply = function(ctx, args)
		local source = ctx.host.path.join(args.source_dir, args.name)
		local link = ctx.host.path.join(args.service_dir, args.name)
		local current = ctx.host.fs.lstat(link)
		if current ~= nil and current.kind == "symlink" and ctx.host.fs.read_link(link) == source then
			return lib.result
				.apply()
				:unchanged(link, "service is already enabled")
				:data({ service = args.name, source = source, link = link })
				:build()
		end
		if current ~= nil then
			error("service entry already exists and is not the expected symlink: " .. link)
		end
		return ctx.host.fs.symlink(source, link)
	end,
}
