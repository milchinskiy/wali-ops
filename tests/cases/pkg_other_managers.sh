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

{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "apk-install",
			module = "ops.pkg.apk.install",
			args = { packages = { "apk-present", "apk-missing" } },
		},
		{
			id = "pacman-install",
			module = "ops.pkg.pacman.install",
			args = { packages = { "pacman-present", "pacman-missing" }, refresh = true },
		},
		{
			id = "xbps-install",
			module = "ops.pkg.xbps.install",
			args = { packages = { "xbps-present", "xbps-missing" }, sync = true },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'apk [info] [-e] [apk-present]'
assert_command_logged 'apk [info] [-e] [apk-missing]'
assert_command_logged 'apk [add] [apk-missing]'
assert_command_not_logged 'apk [add] [apk-present]'
assert_command_logged 'pacman [-Q] [pacman-present]'
assert_command_logged 'pacman [-Q] [pacman-missing]'
assert_command_logged 'pacman [-Sy] [--noconfirm] [--needed] [pacman-missing]'
assert_command_not_logged 'pacman [-Sy] [--noconfirm] [--needed] [pacman-present]'
assert_command_logged 'xbps-query [xbps-present]'
assert_command_logged 'xbps-query [xbps-missing]'
assert_command_logged 'xbps-install [-y] [-S] [xbps-missing]'
assert_command_not_logged 'xbps-install [-y] [-S] [xbps-present]'
