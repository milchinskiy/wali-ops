require("compat")
local lib = require("wali.builtin.lib")

local M = {}

local FORMAT_ALIASES = {
	["auto"] = "auto",
	["tar"] = "tar",
	["tar.gz"] = "tar.gz",
	["tgz"] = "tar.gz",
	["tar.bz2"] = "tar.bz2",
	["tbz"] = "tar.bz2",
	["tbz2"] = "tar.bz2",
	["tar.xz"] = "tar.xz",
	["txz"] = "tar.xz",
	["zip"] = "zip",
}

local FORMAT_SUFFIXES = {
	{ suffix = ".tar.gz", format = "tar.gz" },
	{ suffix = ".tgz", format = "tar.gz" },
	{ suffix = ".tar.bz2", format = "tar.bz2" },
	{ suffix = ".tbz2", format = "tar.bz2" },
	{ suffix = ".tbz", format = "tar.bz2" },
	{ suffix = ".tar.xz", format = "tar.xz" },
	{ suffix = ".txz", format = "tar.xz" },
	{ suffix = ".tar", format = "tar" },
	{ suffix = ".zip", format = "zip" },
}

local TAR_CREATE_FLAGS = {
	["tar"] = "-cf",
	["tar.gz"] = "-czf",
	["tar.bz2"] = "-cjf",
	["tar.xz"] = "-cJf",
}

local TAR_LIST_FLAGS = {
	["tar"] = "-tf",
	["tar.gz"] = "-tzf",
	["tar.bz2"] = "-tjf",
	["tar.xz"] = "-tJf",
}

local TAR_EXTRACT_FLAGS = {
	["tar"] = "-xf",
	["tar.gz"] = "-xzf",
	["tar.bz2"] = "-xjf",
	["tar.xz"] = "-xJf",
}

local function ends_with(value, suffix)
	return #value >= #suffix and value:sub(#value - #suffix + 1) == suffix
end

local function detect_format_from_path(path)
	local lowered = path:lower()
	for _, item in ipairs(FORMAT_SUFFIXES) do
		if ends_with(lowered, item.suffix) then
			return item.format
		end
	end
	return nil
end

function M.normalize_format(value, path, path_field)
	local raw = value or "auto"
	local normalized = FORMAT_ALIASES[raw]
	if normalized == nil then
		return nil, "format must be one of auto, tar, tar.gz, tgz, tar.bz2, tbz2, tbz, tar.xz, txz, zip"
	end
	if normalized ~= "auto" then
		return normalized, nil
	end

	local detected = detect_format_from_path(path)
	if detected == nil then
		return nil,
			"could not detect archive format from " .. (path_field or "path") .. " extension; set format explicitly"
	end
	return detected, nil
end

function M.validate_format(value, path, path_field)
	local _, err = M.normalize_format(value, path, path_field)
	if err ~= nil then
		return lib.validation_error(err)
	end
	return nil
end

function M.command_for_archive(format)
	if format == "zip" then
		return "zip"
	end
	return "tar"
end

function M.command_for_unarchive(format)
	if format == "zip" then
		return "unzip"
	end
	return "tar"
end

function M.validate_command(ctx, command)
	if ctx.host.facts.which(command) == nil then
		return lib.validation_error("required command not found: " .. command)
	end
	return nil
end

function M.command_detail(program, argv)
	if argv == nil or #argv == 0 then
		return program
	end
	return program .. " " .. table.concat(argv, " ")
end

function M.exec(ctx, program, argv, timeout, cwd)
	return ctx.host.cmd.exec({
		program = program,
		args = argv or {},
		timeout = timeout,
		cwd = cwd,
	})
end

function M.checked(ctx, program, argv, timeout, cwd)
	local output = M.exec(ctx, program, argv, timeout, cwd)
	lib.assert_command_ok(output, M.command_detail(program, argv))
	return output
end

function M.tar_create_flags(format)
	return TAR_CREATE_FLAGS[format]
end

function M.tar_list_flags(format)
	return TAR_LIST_FLAGS[format]
end

function M.tar_extract_flags(format)
	return TAR_EXTRACT_FLAGS[format]
end

function M.member_arg(name)
	return "./" .. name
end

function M.validate_not_root(ctx, path, field, action)
	local normalized = ctx.host.path.normalize(path)
	if normalized == "/" then
		return lib.validation_error("refusing to " .. action .. " / as " .. field)
	end
	return nil
end

local function unsafe_member_reason(name)
	if name == nil or name == "" then
		return "archive contains an empty member path"
	end
	if name:find("%c") ~= nil then
		return "archive member contains control characters: " .. name
	end
	if name:sub(1, 1) == "/" then
		return "archive member is absolute: " .. name
	end

	local trimmed = name
	while trimmed:sub(1, 2) == "./" do
		trimmed = trimmed:sub(3)
	end
	if trimmed == ".." or trimmed:sub(1, 3) == "../" then
		return "archive member escapes destination: " .. name
	end
	if trimmed:find("/../", 1, true) ~= nil or trimmed:sub(-3) == "/.." then
		return "archive member escapes destination: " .. name
	end
	return nil
end

local function each_line(text, callback)
	if text == nil or text == "" then
		return
	end

	local pos = 1
	while pos <= #text do
		local next_newline = text:find("\n", pos, true)
		local line
		if next_newline == nil then
			line = text:sub(pos)
			pos = #text + 1
		else
			line = text:sub(pos, next_newline - 1)
			pos = next_newline + 1
		end

		if line:sub(-1) == "\r" then
			line = line:sub(1, -2)
		end
		callback(line)
	end
end

function M.assert_safe_archive_members(ctx, src, format, timeout)
	local output
	if format == "zip" then
		output = M.checked(ctx, "unzip", { "-Z1", src }, timeout)
	else
		output = M.checked(ctx, "tar", { M.tar_list_flags(format), src }, timeout)
	end

	each_line(output.stdout or output.output or "", function(name)
		local reason = unsafe_member_reason(name)
		if reason ~= nil then
			error(reason)
		end
	end)
end

function M.archive_data(src, dest, format)
	return { src = src, dest = dest, format = format }
end

return M
