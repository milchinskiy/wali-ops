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
	name = "runit disable",
	description = "Disable a runit service by removing service_dir/name symlink.",

	schema = {
		type = "object",
		required = true,
		props = {
			name = { type = "string", required = true },
			service_dir = { type = "string", default = "/var/service" },
		},
	},

	validate = function(ctx, args)
		local err = validate_link_name(args.name)
		if err ~= nil then
			return err
		end
		return lib.validate_absolute_path(ctx, args.service_dir, "service_dir")
	end,

	apply = function(ctx, args)
		local link = ctx.host.path.join(args.service_dir, args.name)
		local current = ctx.host.fs.lstat(link)
		if current == nil then
			return lib.result
				.apply()
				:unchanged(link, "service is already disabled")
				:data({ service = args.name, link = link })
				:build()
		end
		if current.kind ~= "symlink" then
			error("refusing to remove non-symlink service entry: " .. link)
		end
		return ctx.host.fs.remove_file(link)
	end,
}
