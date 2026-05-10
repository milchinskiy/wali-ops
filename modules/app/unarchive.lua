require("compat")
local lib = require("wali.builtin.lib")
local archive = require("_internals.archive")

local function validate_args(ctx, args)
	local err = lib.validate_absolute_path(ctx, args.src, "src")
	if err ~= nil then
		return err
	end
	err = lib.validate_absolute_path(ctx, args.dest, "dest")
	if err ~= nil then
		return err
	end
	err = archive.validate_not_root(ctx, args.src, "src", "extract")
	if err ~= nil then
		return err
	end
	err = archive.validate_not_root(ctx, args.dest, "dest", "extract into")
	if err ~= nil then
		return err
	end
	err = archive.validate_format(args.format, args.src, "src")
	if err ~= nil then
		return err
	end

	local format = archive.normalize_format(args.format, args.src, "src")
	return archive.validate_command(ctx, archive.command_for_unarchive(format))
end

local function tar_extract(ctx, args, format)
	local argv = { "-C", args.dest }
	if not args.replace then
		table.insert(argv, "-k")
	end
	table.insert(argv, archive.tar_extract_flags(format))
	table.insert(argv, args.src)
	archive.checked(ctx, "tar", argv, args.timeout)
end

local function zip_extract(ctx, args)
	local overwrite = "-o"
	if not args.replace then
		overwrite = "-n"
	end
	archive.checked(ctx, "unzip", { "-q", overwrite, args.src, "-d", args.dest }, args.timeout)
end

return {
	name = "unarchive",
	description = "Extract a tar or zip archive into a target-host directory.",

	schema = {
		type = "object",
		required = true,
		props = {
			src = { type = "string", required = true },
			dest = { type = "string", required = true },
			format = {
				type = "enum",
				values = { "auto", "tar", "tar.gz", "tgz", "tar.bz2", "tbz2", "tbz", "tar.xz", "txz", "zip" },
				default = "auto",
			},
			parents = { type = "boolean", default = false },
			replace = { type = "boolean", default = true },
			timeout = { type = "string" },
		},
	},

	validate = validate_args,

	apply = function(ctx, args)
		local src_meta = ctx.host.fs.stat(args.src)
		if src_meta == nil then
			error("src does not exist: " .. args.src)
		end
		if src_meta.kind ~= "file" then
			error("src must be a regular file: " .. args.src)
		end

		local dest_meta = ctx.host.fs.stat(args.dest)
		if dest_meta ~= nil and dest_meta.kind ~= "dir" then
			error("dest must be a directory: " .. args.dest)
		end

		local result = lib.result.apply()
		if dest_meta == nil then
			result:merge(ctx.host.fs.create_dir(args.dest, { recursive = args.parents }))
		end

		local format = archive.normalize_format(args.format, args.src, "src")
		archive.assert_safe_archive_members(ctx, args.src, format, args.timeout)
		if format == "zip" then
			zip_extract(ctx, args)
		else
			tar_extract(ctx, args, format)
		end

		local detail = archive.command_for_unarchive(format) .. " extract " .. args.src
		return result
			:command("updated", detail)
			:message("extracted archive")
			:data(archive.archive_data(args.src, args.dest, format))
			:build()
	end,
}
