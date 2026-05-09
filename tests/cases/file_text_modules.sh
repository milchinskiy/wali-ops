#!/bin/sh

set -eu
. "${TEST_LIB:?}"

setup_sandbox

remove_file=$TEST_SANDBOX/remove-lines.txt
cat >"$remove_file" <<'TEXT'
keep
remove
remove
keep
TEXT

{
	manifest_header
	cat <<MANIFEST
		{
			id = "remove-lines",
			module = "ops.file.remove_line",
			args = {
				path = $(lua_quote "$remove_file"),
				line = "remove",
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_file_not_contains "$remove_file" "remove"
run_wali_apply
assert_file_not_contains "$remove_file" "remove"

remove_first_file=$TEST_SANDBOX/remove-first.txt
cat >"$remove_first_file" <<'TEXT'
target
target
target
TEXT

{
	manifest_header
	cat <<MANIFEST
		{
			id = "remove-first-line",
			module = "ops.file.remove_line",
			args = {
				path = $(lua_quote "$remove_first_file"),
				line = "target",
				all = false,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
count=$(grep -c '^target$' "$remove_first_file")
assert_eq 2 "$count"

missing_remove=$TEST_SANDBOX/missing-remove.txt
{
	manifest_header
	cat <<MANIFEST
		{
			id = "remove-missing-file",
			module = "ops.file.remove_line",
			args = {
				path = $(lua_quote "$missing_remove"),
				line = "target",
				missing_ok = false,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply_failure
assert_output_contains "file does not exist"

block_file=$TEST_SANDBOX/nested/block.conf
{
	manifest_header
	cat <<MANIFEST
		{
			id = "manage-block",
			module = "ops.file.block",
			args = {
				path = $(lua_quote "$block_file"),
				marker = "wali demo",
				content = [[alpha
beta]],
				parents = true,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
expected_block=$TEST_SANDBOX/expected-block.txt
cat >"$expected_block" <<'TEXT'
# BEGIN wali demo
alpha
beta
# END wali demo
TEXT
cmp -s "$expected_block" "$block_file" || {
	printf '%s\n' 'unexpected file.block create result' >&2
	cat "$block_file" >&2
	exit 1
}
run_wali_apply
cmp -s "$expected_block" "$block_file" || fail "file.block second apply changed content unexpectedly"

{
	manifest_header
	cat <<MANIFEST
		{
			id = "update-block",
			module = "ops.file.block",
			args = {
				path = $(lua_quote "$block_file"),
				marker = "wali demo",
				content = [[gamma]],
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_file_contains "$block_file" "gamma"
assert_file_not_contains "$block_file" "alpha"

bad_block=$TEST_SANDBOX/bad-block.conf
cat >"$bad_block" <<'TEXT'
# END broken
TEXT
{
	manifest_header
	cat <<MANIFEST
		{
			id = "bad-block",
			module = "ops.file.block",
			args = {
				path = $(lua_quote "$bad_block"),
				marker = "broken",
				content = "x",
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply_failure
assert_output_contains "managed block markers"

key_file=$TEST_SANDBOX/nested/settings.conf
{
	manifest_header
	cat <<MANIFEST
		{
			id = "add-key-value",
			module = "ops.file.key_value",
			args = {
				path = $(lua_quote "$key_file"),
				key = "Port",
				value = "22",
				parents = true,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_file_contains "$key_file" "Port=22"
run_wali_apply
count=$(grep -c '^Port=22$' "$key_file")
assert_eq 1 "$count"

{
	manifest_header
	cat <<MANIFEST
		{
			id = "update-key-value",
			module = "ops.file.key_value",
			args = {
				path = $(lua_quote "$key_file"),
				key = "Port",
				value = "2222",
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_file_contains "$key_file" "Port=2222"
if grep -Fx -- "Port=22" "$key_file" >/dev/null 2>&1; then
	fail "file.key_value kept stale exact Port=22 line"
fi

space_key_file=$TEST_SANDBOX/sshd.conf
cat >"$space_key_file" <<'TEXT'
# PermitRootLogin yes
PermitRootLogin yes
TEXT
{
	manifest_header
	cat <<MANIFEST
		{
			id = "space-key-value",
			module = "ops.file.key_value",
			args = {
				path = $(lua_quote "$space_key_file"),
				key = "PermitRootLogin",
				value = "no",
				separator = " ",
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_file_contains "$space_key_file" "# PermitRootLogin yes"
assert_file_contains "$space_key_file" "PermitRootLogin no"
if grep -Fx -- "PermitRootLogin yes" "$space_key_file" >/dev/null 2>&1; then
	fail "file.key_value kept stale exact PermitRootLogin line"
fi

duplicate_key_file=$TEST_SANDBOX/duplicate.conf
cat >"$duplicate_key_file" <<'TEXT'
Port=22
Port=2222
TEXT
{
	manifest_header
	cat <<MANIFEST
		{
			id = "duplicate-key-value",
			module = "ops.file.key_value",
			args = {
				path = $(lua_quote "$duplicate_key_file"),
				key = "Port",
				value = "2022",
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply_failure
assert_output_contains "duplicate key found"
