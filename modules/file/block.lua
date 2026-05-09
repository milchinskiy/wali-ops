require("compat")
local lib = require("wali.builtin.lib")

local function validate_non_empty(value, field)
	if value == nil or value == "" or value:match("%S") == nil then
		return lib.validation_error(field .. " must not be empty")
	end
	return nil
end

local function validate_single_line(value, field)
	local err = validate_non_empty(value, field)
	if err ~= nil then
		return err
	end
	if value:find("\n", 1, true) ~= nil or value:find("\r", 1, true) ~= nil then
		return lib.validation_error(field .. " must be a single line")
	end
	return nil
end

local function marker_lines(args)
	local prefix = args.comment_prefix
	return prefix .. " BEGIN " .. args.marker, prefix .. " END " .. args.marker
end

local function normalize_content(content)
	if content == "" then
		return ""
	end
	if content:sub(-1) == "\n" then
		return content
	end
	return content .. "\n"
end

local function build_block(args)
	local begin_marker, end_marker = marker_lines(args)
	return begin_marker .. "\n" .. normalize_content(args.content) .. end_marker .. "\n"
end

local function append_block(content, block)
	if content == "" then
		return block
	end
	if content:sub(-1) == "\n" then
		return content .. block
	end
	return content .. "\n" .. block
end

local function find_marker_lines(content, begin_marker, end_marker)
	local markers = {}
	local index = 1

	while index <= #content do
		local start_pos = index
		local newline = content:find("\n", index, true)
		local line
		local end_pos
		if newline ~= nil then
			line = content:sub(index, newline - 1)
			end_pos = newline
			index = newline + 1
		else
			line = content:sub(index)
			end_pos = #content
			index = #content + 1
		end

		if line == begin_marker then
			table.insert(markers, { kind = "begin", start_pos = start_pos, end_pos = end_pos })
		elseif line == end_marker then
			table.insert(markers, { kind = "end", start_pos = start_pos, end_pos = end_pos })
		end
	end

	return markers
end

local function replace_managed_block(content, block, begin_marker, end_marker)
	local markers = find_marker_lines(content, begin_marker, end_marker)
	if #markers == 0 then
		return append_block(content, block), 0
	end
	if #markers ~= 2 or markers[1].kind ~= "begin" or markers[2].kind ~= "end" then
		error("managed block markers are incomplete, reversed, nested, or duplicated")
	end

	local existing = content:sub(markers[1].start_pos, markers[2].end_pos)
	if existing == block then
		return content, 1
	end

	return content:sub(1, markers[1].start_pos - 1) .. block .. content:sub(markers[2].end_pos + 1), 1
end

return {
	name = "file block",
	description = "Manage one marked text block.",

	schema = {
		type = "object",
		required = true,
		props = {
			path = { type = "string", required = true },
			marker = { type = "string", required = true },
			content = { type = "string", required = true },
			comment_prefix = { type = "string", default = "#" },
			create = { type = "boolean", default = true },
			parents = { type = "boolean", default = false },
			mode = lib.schema.mode(),
			owner = lib.schema.owner(),
		},
	},

	validate = function(ctx, args)
		local err = lib.validate_absolute_path(ctx, args.path, "path")
		if err ~= nil then
			return err
		end
		err = validate_single_line(args.marker, "marker")
		if err ~= nil then
			return err
		end
		err = validate_single_line(args.comment_prefix, "comment_prefix")
		if err ~= nil then
			return err
		end
		local begin_marker, end_marker = marker_lines(args)
		if args.content:find(begin_marker, 1, true) ~= nil or args.content:find(end_marker, 1, true) ~= nil then
			return lib.validation_error("content must not contain generated block marker lines")
		end
		return lib.validate_mode_owner(args)
	end,

	apply = function(ctx, args)
		local block = build_block(args)
		local current = ctx.host.fs.stat(args.path)
		if current == nil then
			if not args.create then
				error("file does not exist and create is false: " .. args.path)
			end
			return ctx.host.fs.write(args.path, block, lib.write_file_opts(args))
		end
		if current.kind ~= "file" then
			error("path must be a regular file: " .. args.path)
		end

		local begin_marker, end_marker = marker_lines(args)
		local content = ctx.host.fs.read_text(args.path)
		local updated, existing_blocks = replace_managed_block(content, block, begin_marker, end_marker)
		if updated == content then
			local result = lib.result.apply():unchanged(args.path, "managed block already matches")
			lib.apply_mode_owner(ctx, result, args.path, args)
			return result:data({ marker = args.marker, blocks = existing_blocks }):build()
		end

		local result = lib.result.apply()
		result:merge(ctx.host.fs.write(
			args.path,
			updated,
			lib.write_file_opts({
				parents = false,
				replace = true,
				mode = args.mode,
				owner = args.owner,
			})
		))
		return result:data({ marker = args.marker, blocks = 1 }):build()
	end,
}
