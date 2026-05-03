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

replace_first_file=$TEST_SANDBOX/replace-first.txt
printf '%s\n' 'one one one' >"$replace_first_file"
{
	manifest_header
	cat <<MANIFEST
		{
			id = "replace-first",
			module = "ops.file.replace",
			args = {
				path = $(lua_quote "$replace_first_file"),
				find = "one",
				replace = "two",
				all = false,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
expected=$TEST_SANDBOX/expected-replace-first.txt
printf '%s\n' 'two one one' >"$expected"
cmp -s "$expected" "$replace_first_file" || {
	printf '%s\n' 'unexpected file.replace all=false result' >&2
	cat "$replace_first_file" >&2
	exit 1
}

replace_all_file=$TEST_SANDBOX/replace-all.txt
printf '%s\n' 'one one one' >"$replace_all_file"
{
	manifest_header
	cat <<MANIFEST
		{
			id = "replace-all",
			module = "ops.file.replace",
			args = {
				path = $(lua_quote "$replace_all_file"),
				find = "one",
				replace = "two",
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
expected_all=$TEST_SANDBOX/expected-replace-all.txt
printf '%s\n' 'two two two' >"$expected_all"
cmp -s "$expected_all" "$replace_all_file" || {
	printf '%s\n' 'unexpected file.replace all=true result' >&2
	cat "$replace_all_file" >&2
	exit 1
}

run_wali_apply
cmp -s "$expected_all" "$replace_all_file" || fail "file.replace all=true second apply changed content unexpectedly"
