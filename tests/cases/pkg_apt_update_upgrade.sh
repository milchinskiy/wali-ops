#!/bin/sh

set -eu
. "${TEST_LIB:?}"

setup_sandbox

make_fake_command apt-get <<'FAKE'
exit 0
FAKE

{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "apt-update",
			module = "ops.pkg.apt.update",
			args = {},
		},
		{
			id = "apt-upgrade-all",
			module = "ops.pkg.apt.upgrade",
			args = {},
		},
		{
			id = "apt-upgrade-packages",
			module = "ops.pkg.apt.upgrade",
			args = { packages = { "curl", "nginx" } },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'apt-get [update]'
assert_command_logged 'apt-get [upgrade] [-y]'
assert_command_logged 'apt-get [install] [--only-upgrade] [-y] [--] [curl] [nginx]'
