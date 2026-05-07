#!/bin/sh

set -eu
. "${TEST_LIB:?}"

setup_sandbox

make_fake_command dpkg-query <<'FAKE'
if [ "$#" -eq 3 ] && [ "$1" = "-W" ]; then
	case $3 in
		installed)
			printf '%s' 'install ok installed'
			exit 0
			;;
		absent)
			exit 1
			;;
	esac
fi
exit 64
FAKE

make_fake_command apt-get <<'FAKE'
exit 0
FAKE

{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "remove-mixed",
			module = "ops.pkg.apt.remove",
			args = { packages = { "installed", "absent" }, purge = true, autoremove = true },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'apt-get [purge] [-y] [--] [installed]'
assert_command_logged 'apt-get [autoremove] [-y]'
assert_command_not_logged 'apt-get [purge] [-y] [--] [absent]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "remove-absent",
			module = "ops.pkg.apt.remove",
			args = { packages = { "absent" } },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'dpkg-query [-W] [-f=${Status}] [absent]'
assert_command_not_logged 'apt-get [remove]'
assert_command_not_logged 'apt-get [purge]'
