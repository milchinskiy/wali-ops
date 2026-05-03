#!/bin/sh
set -eu
. "${TEST_LIB:?}"

setup_sandbox
line_file=$TEST_SANDBOX/nested/lines.txt

{
	manifest_header
	cat <<MANIFEST
		{
			id = "append-line",
			module = "ops.file.line",
			args = {
				path = $(lua_quote "$line_file"),
				line = "hello world",
				create_parents = true,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
run_wali_apply
count=$(grep -c '^hello world$' "$line_file")
assert_eq 1 "$count"

{
	manifest_header
	cat <<MANIFEST
		{
			id = "reject-multiline",
			module = "ops.file.line",
			args = { path = $(lua_quote "$line_file"), line = "bad\nline" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply_failure
assert_output_contains "line must be a single line"

replace_file=$TEST_SANDBOX/replace.txt
printf '%s\n' 'one one one' >"$replace_file"
{
	manifest_header
	cat <<MANIFEST
		{
			id = "replace-first",
			module = "ops.file.replace",
			args = {
				path = $(lua_quote "$replace_file"),
				find = "one",
				replace = "two",
				all = false,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
expected=$TEST_SANDBOX/expected-replace.txt
printf '%s\n' 'two one one' >"$expected"
cmp -s "$expected" "$replace_file" || {
	printf '%s\n' 'unexpected file.replace result' >&2
	cat "$replace_file" >&2
	exit 1
}

run_wali_apply
cmp -s "$expected" "$replace_file" || fail "file.replace second apply changed content unexpectedly"
