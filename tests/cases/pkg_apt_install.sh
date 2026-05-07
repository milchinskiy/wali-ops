#!/bin/sh

set -eu
. "${TEST_LIB:?}"

setup_sandbox

make_fake_command dpkg-query <<'FAKE'
if [ "$#" -eq 3 ] && [ "$1" = "-W" ]; then
	case $3 in
		present)
			printf '%s' 'install ok installed'
			exit 0
			;;
		missing)
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
			id = "install-mixed",
			module = "ops.pkg.apt.install",
			args = { packages = { "present", "missing" }, no_install_recommends = true },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'dpkg-query [-W] [-f=${Status}] [present]'
assert_command_logged 'dpkg-query [-W] [-f=${Status}] [missing]'
assert_command_logged 'apt-get [install] [-y] [--no-install-recommends] [--] [missing]'
assert_command_not_logged 'apt-get [install] [-y] [--no-install-recommends] [--] [present]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "install-present",
			module = "ops.pkg.apt.install",
			args = { packages = { "present" } },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'dpkg-query [-W] [-f=${Status}] [present]'
assert_command_not_logged 'apt-get [install]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "reject-option-like-package",
			module = "ops.pkg.apt.install",
			args = { packages = { "-bad" } },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply_failure
assert_output_contains "must not start with '-'"
assert_command_not_logged 'apt-get [install]'
