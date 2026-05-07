#!/bin/sh

set -eu
. "${TEST_LIB:?}"

setup_sandbox

make_fake_command apk <<'FAKE'
if [ "$#" -eq 3 ] && [ "$1" = "info" ] && [ "$2" = "-e" ]; then
	case $3 in
		apk-present) exit 0 ;;
		*) exit 1 ;;
	esac
fi
exit 0
FAKE

make_fake_command pacman <<'FAKE'
if [ "$#" -eq 2 ] && [ "$1" = "-Q" ]; then
	case $2 in
		pacman-present) exit 0 ;;
		*) exit 1 ;;
	esac
fi
exit 0
FAKE

make_fake_command xbps-query <<'FAKE'
if [ "$#" -eq 1 ]; then
	case $1 in
		xbps-present) exit 0 ;;
		*) exit 1 ;;
	esac
fi
exit 64
FAKE

make_fake_command xbps-install <<'FAKE'
exit 0
FAKE

make_fake_command xbps-remove <<'FAKE'
exit 0
FAKE

{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "apk-remove",
			module = "ops.pkg.apk.remove",
			args = { packages = { "apk-present", "apk-missing" } },
		},
		{
			id = "pacman-remove",
			module = "ops.pkg.pacman.remove",
			args = { packages = { "pacman-present", "pacman-missing" }, recursive = true, nosave = true },
		},
		{
			id = "xbps-remove",
			module = "ops.pkg.xbps.remove",
			args = { packages = { "xbps-present", "xbps-missing" }, recursive = true },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'apk [del] [apk-present]'
assert_command_not_logged 'apk [del] [apk-missing]'
assert_command_logged 'pacman [-Rs] [--noconfirm] [--nosave] [pacman-present]'
assert_command_not_logged 'pacman [-Rs] [--noconfirm] [--nosave] [pacman-missing]'
assert_command_logged 'xbps-remove [-y] [-R] [xbps-present]'
assert_command_not_logged 'xbps-remove [-y] [-R] [xbps-missing]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "apk-direct-actions",
			module = "ops.pkg.apk.update",
			args = {},
		},
		{
			id = "apk-upgrade",
			module = "ops.pkg.apk.upgrade",
			args = { packages = { "apk-present" }, available = true },
		},
		{
			id = "pacman-update",
			module = "ops.pkg.pacman.update",
			args = {},
		},
		{
			id = "pacman-upgrade-package",
			module = "ops.pkg.pacman.upgrade",
			args = { packages = { "pacman-present" } },
		},
		{
			id = "pacman-upgrade-system",
			module = "ops.pkg.pacman.upgrade",
			args = {},
		},
		{
			id = "xbps-update",
			module = "ops.pkg.xbps.update",
			args = {},
		},
		{
			id = "xbps-upgrade",
			module = "ops.pkg.xbps.upgrade",
			args = { packages = { "xbps-present" }, sync = true },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'apk [update]'
assert_command_logged 'apk [upgrade] [--available] [apk-present]'
assert_command_logged 'pacman [-Sy] [--noconfirm]'
assert_command_logged 'pacman [-S] [--noconfirm] [pacman-present]'
assert_command_logged 'pacman [-Syu] [--noconfirm]'
assert_command_logged 'xbps-install [-S]'
assert_command_logged 'xbps-install [-y] [-u] [-S] [xbps-present]'
