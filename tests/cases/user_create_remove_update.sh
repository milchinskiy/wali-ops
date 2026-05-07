#!/bin/sh

set -eu
. "${TEST_LIB:?}"

setup_sandbox

make_fake_command getent <<'FAKE'
if [ "$#" -eq 2 ] && [ "$1" = "passwd" ]; then
	case $2 in
		existing)
			printf '%s\n' 'existing:x:1000:1000:Existing User:/home/existing:/bin/sh'
			exit 0
			;;
		absent)
			exit 2
			;;
	esac
fi
exit 64
FAKE

make_fake_command useradd <<'FAKE'
exit 0
FAKE

make_fake_command userdel <<'FAKE'
exit 0
FAKE

make_fake_command usermod <<'FAKE'
exit 0
FAKE

{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "create-existing",
			module = "ops.user.create",
			args = { name = "existing" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'getent [passwd] [existing]'
assert_command_not_logged 'useradd ['

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "create-absent",
			module = "ops.user.create",
			args = {
				name = "absent",
				uid = 2001,
				group = "staff",
				groups = { "wheel", "adm" },
				home = "/home/absent",
				create_home = true,
				shell = "/bin/sh",
				comment = "Absent User",
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'getent [passwd] [absent]'
assert_command_logged 'useradd [--uid] [2001] [--gid] [staff] [--groups] [wheel,adm] [--home-dir] [/home/absent] [--create-home] [--shell] [/bin/sh] [--comment] [Absent User] [absent]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "remove-absent",
			module = "ops.user.remove",
			args = { name = "absent" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'getent [passwd] [absent]'
assert_command_not_logged 'userdel ['

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "remove-existing",
			module = "ops.user.remove",
			args = { name = "existing", force = true, remove_home = true },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'userdel [--force] [--remove] [existing]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "update-existing",
			module = "ops.user.update",
			args = { name = "existing", groups = { "wheel" }, append_groups = true, shell = "/bin/zsh" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'usermod [--append] [--groups] [wheel] [--shell] [/bin/zsh] [existing]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "update-requires-option",
			module = "ops.user.update",
			args = { name = "existing" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply_failure
assert_output_contains "at least one user update option is required"
assert_command_not_logged 'usermod ['
