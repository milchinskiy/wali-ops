#!/bin/sh

set -eu
. "${TEST_LIB:?}"

setup_sandbox

make_fake_command getent <<'FAKE'
if [ "$#" -eq 2 ] && [ "$1" = "group" ]; then
	case $2 in
		existing)
			printf '%s\n' 'existing:x:1000:'
			exit 0
			;;
		absent)
			exit 2
			;;
	esac
fi
exit 64
FAKE

make_fake_command groupadd <<'FAKE'
exit 0
FAKE

make_fake_command groupdel <<'FAKE'
exit 0
FAKE

{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "create-existing",
			module = "ops.group.create",
			args = { name = "existing" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'getent [group] [existing]'
assert_command_not_logged 'groupadd ['

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "create-absent",
			module = "ops.group.create",
			args = { name = "absent", gid = 2000, system = true },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'getent [group] [absent]'
assert_command_logged 'groupadd [--system] [--gid] [2000] [absent]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "remove-absent",
			module = "ops.group.remove",
			args = { name = "absent" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'getent [group] [absent]'
assert_command_not_logged 'groupdel ['

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "remove-existing",
			module = "ops.group.remove",
			args = { name = "existing" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'getent [group] [existing]'
assert_command_logged 'groupdel [existing]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "reject-option-like-group",
			module = "ops.group.create",
			args = { name = "-bad" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply_failure
assert_output_contains "must not start with '-'"
assert_command_not_logged 'groupadd ['
