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
	err = archive.validate_not_root(ctx, args.src, "src", "archive")
	if err ~= nil then
		return err
	end
	err = archive.validate_not_root(ctx, args.dest, "dest", "write archive to")
	if err ~= nil then
		return err
	end
	err = archive.validate_format(args.format, args.dest, "dest")
	if err ~= nil then
		return err
	end
	err = lib.validate_mode_owner(args)
	if err ~= nil then
		return err
	end

	local format = archive.normalize_format(args.format, args.dest, "dest")
	return archive.validate_command(ctx, archive.command_for_archive(format))
end

local function tar_archive(ctx, args, format, tmp)
	local src = ctx.host.path.normalize(args.src)
	local parent = ctx.host.path.parent(src)
	local base = ctx.host.path.basename(src)
	archive.checked(
		ctx,
		"tar",
		{ "-C", parent, archive.tar_create_flags(format), tmp, archive.member_arg(base) },
		args.timeout
	)
end

local function zip_archive(ctx, args, tmp)
	local src = ctx.host.path.normalize(args.src)
	local parent = ctx.host.path.parent(src)
	local base = ctx.host.path.basename(src)
	archive.checked(ctx, "zip", { "-q", "-r", tmp, archive.member_arg(base) }, args.timeout, parent)
end

return {
	name = "archive",
	description = "Create a tar or zip archive from one target-host path.",

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
			mode = lib.schema.mode(),
			owner = lib.schema.owner(),
		},
	},

	validate = validate_args,

	apply = function(ctx, args)
		if not args.replace and ctx.host.fs.exists(args.dest) then
			return lib.skip("destination already exists and replace is false: " .. args.dest)
		end

		local src_meta = ctx.host.fs.stat(args.src)
		if src_meta == nil then
			error("src does not exist: " .. args.src)
		end
		if src_meta.kind ~= "file" and src_meta.kind ~= "dir" and src_meta.kind ~= "symlink" then
			error("src must be a file, directory, or symlink: " .. args.src)
		end

		local normalized_src = ctx.host.path.normalize(args.src)
		local normalized_dest = ctx.host.path.normalize(args.dest)
		if normalized_src == normalized_dest then
			error("src and dest must be different paths")
		end
		if src_meta.kind == "dir" and ctx.host.path.strip_prefix(normalized_src, normalized_dest) ~= nil then
			error("archive destination must not be inside src directory")
		end

		local format = archive.normalize_format(args.format, args.dest, "dest")
		local result = lib.result.apply()
		local dest_parent = ctx.host.path.parent(args.dest)
		if args.parents then
			result:merge(ctx.host.fs.create_dir(dest_parent, { recursive = true }))
		end

		local tmp_dir = ctx.host.fs.mktemp({ parent_dir = dest_parent, prefix = ".wali-archive-", kind = "dir" })
		local tmp = ctx.host.path.join(tmp_dir, "archive")
		local ok, err = pcall(function()
			if format == "zip" then
				zip_archive(ctx, args, tmp)
			else
				tar_archive(ctx, args, format, tmp)
			end
			result:merge(ctx.host.fs.rename(tmp, args.dest, { replace = true }))
			lib.apply_mode_owner(ctx, result, args.dest, args)
		end)
		pcall(function()
			ctx.host.fs.remove_dir(tmp_dir, { recursive = true })
		end)
		if not ok then
			error(err)
		end

		return result:message("created archive"):data(archive.archive_data(args.src, args.dest, format)):build()
	end,
}
