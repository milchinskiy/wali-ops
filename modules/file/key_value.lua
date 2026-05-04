local lib = require("wali.builtin.lib")

local function validate_non_empty(value, field)
	if value == nil or value == "" or value:match("%S") == nil then
		return lib.validation_error(field .. " must not be empty")
	end
	return nil
end

local function validate_single_line(value, field, allow_empty)
	if allow_empty ~= true then
		local err = validate_non_empty(value, field)
		if err ~= nil then
			return err
		end
	elseif value == nil then
		return lib.validation_error(field .. " is required")
	end
	if value:find("\n", 1, true) ~= nil or value:find("\r", 1, true) ~= nil then
		return lib.validation_error(field .. " must be a single line")
	end
	return nil
end

local function trim(value)
	return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function starts_with(value, prefix)
	return value:sub(1, #prefix) == prefix
end

local function is_comment(line, comment_prefix)
	if comment_prefix == nil or comment_prefix == "" then
		return false
	end
	return starts_with(trim(line), comment_prefix)
end

local function line_matches_key(line, key, separator, comment_prefix)
	if is_comment(line, comment_prefix) then
		return false
	end

	local rest = line:gsub("^%s+", "")
	if rest:sub(1, #key) ~= key then
		return false
	end

	local after_key = rest:sub(#key + 1)
	if separator == "=" then
		return after_key:match("^%s*=") ~= nil
	end
	return after_key:match("^%s+") ~= nil
end

local function desired_line(args)
	if args.separator == "=" then
		return args.key .. "=" .. args.value
	end
	return args.key .. " " .. args.value
end

local function append_line(content, line)
	if content == "" then
		return line .. "\n"
	end
	if content:sub(-1) == "\n" then
		return content .. line .. "\n"
	end
	return content .. "\n" .. line .. "\n"
end

local function replace_or_append(content, args)
	local wanted = desired_line(args)
	local out = {}
	local index = 1
	local matches = 0
	local unchanged = false

	while index <= #content do
		local newline = content:find("\n", index, true)
		local line
		local has_newline
		if newline ~= nil then
			line = content:sub(index, newline - 1)
			has_newline = true
			index = newline + 1
		else
			line = content:sub(index)
			has_newline = false
			index = #content + 1
		end

		if line_matches_key(line, args.key, args.separator, args.comment_prefix) then
			matches = matches + 1
			if matches == 1 then
				if line == wanted then
					unchanged = true
				end
				table.insert(out, wanted)
			else
				error("duplicate key found: " .. args.key)
			end
		else
			table.insert(out, line)
		end
		if has_newline then
			table.insert(out, "\n")
		end
	end

	if matches == 0 then
		return append_line(content, wanted), "added"
	end
	if unchanged then
		return content, "unchanged"
	end
	return table.concat(out), "updated"
end

return {
	name = "file key value",
	description = "Set one simple key/value line.",

	schema = {
		type = "object",
		required = true,
		props = {
			path = { type = "string", required = true },
			key = { type = "string", required = true },
			value = { type = "string", required = true },
			separator = { type = "string", default = "=" },
			comment_prefix = { type = "string", default = "#" },
			create = { type = "boolean", default = true },
			create_parents = { type = "boolean", default = false },
			mode = lib.schema.mode(),
			owner = lib.schema.owner(),
		},
	},

	validate = function(ctx, args)
		local err = lib.validate_absolute_path(ctx, args.path, "path")
		if err ~= nil then
			return err
		end
		err = validate_single_line(args.key, "key")
		if err ~= nil then
			return err
		end
		err = validate_single_line(args.value, "value", true)
		if err ~= nil then
			return err
		end
		if args.separator ~= "=" and args.separator ~= " " then
			return lib.validation_error("separator must be '=' or ' '")
		end
		err = validate_single_line(args.comment_prefix, "comment_prefix", true)
		if err ~= nil then
			return err
		end
		if args.separator == "=" and args.key:find("=", 1, true) ~= nil then
			return lib.validation_error("key must not contain '='")
		end
		if args.key:find("%s") ~= nil then
			return lib.validation_error("key must not contain whitespace")
		end
		return lib.validate_mode_owner(args)
	end,

	apply = function(ctx, args)
		local current = ctx.host.fs.stat(args.path)
		if current == nil then
			if not args.create then
				error("file does not exist and create is false: " .. args.path)
			end
			return ctx.host.fs.write(args.path, desired_line(args) .. "\n", lib.write_file_opts(args))
		end
		if current.kind ~= "file" then
			error("path must be a regular file: " .. args.path)
		end

		local content = ctx.host.fs.read_text(args.path)
		local updated, action = replace_or_append(content, args)
		if action == "unchanged" then
			local result = lib.result.apply():unchanged(args.path, "key/value already matches")
			lib.apply_mode_owner(ctx, result, args.path, args)
			return result:data({ key = args.key, action = action }):build()
		end

		local result = lib.result.apply()
		result:merge(ctx.host.fs.write(
			args.path,
			updated,
			lib.write_file_opts({
				create_parents = false,
				replace = true,
				mode = args.mode,
				owner = args.owner,
			})
		))
		return result:data({ key = args.key, action = action }):build()
	end,
}
