#!/bin/sh
set -eu
. "${TEST_LIB:?}"

setup_sandbox
source_dir=$TEST_SANDBOX/source-sv
service_dir=$TEST_SANDBOX/service
mkdir -p "$source_dir/demo" "$service_dir"

{
	manifest_header
	cat <<MANIFEST
		{
			id = "enable-demo",
			module = "ops.service.runit.enable",
			args = {
				name = "demo",
				source_dir = $(lua_quote "$source_dir"),
				service_dir = $(lua_quote "$service_dir"),
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
[ -L "$service_dir/demo" ] || fail "expected runit enable to create a symlink"
assert_eq "$source_dir/demo" "$(readlink "$service_dir/demo")"

run_wali_apply
[ -L "$service_dir/demo" ] || fail "expected runit enable to stay idempotent"
assert_eq "$source_dir/demo" "$(readlink "$service_dir/demo")"

{
	manifest_header
	cat <<MANIFEST
		{
			id = "disable-demo",
			module = "ops.service.runit.disable",
			args = { name = "demo", service_dir = $(lua_quote "$service_dir") },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_not_exists "$service_dir/demo"

run_wali_apply
assert_not_exists "$service_dir/demo"

printf '%s\n' 'not a symlink' >"$service_dir/demo"
{
	manifest_header
	cat <<MANIFEST
		{
			id = "enable-refuses-existing-entry",
			module = "ops.service.runit.enable",
			args = {
				name = "demo",
				source_dir = $(lua_quote "$source_dir"),
				service_dir = $(lua_quote "$service_dir"),
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply_failure
assert_output_contains "not the expected symlink"
