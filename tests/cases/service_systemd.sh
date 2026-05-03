#!/bin/sh
set -eu
. "${TEST_LIB:?}"

setup_sandbox

make_fake_command systemctl <<'FAKE'
if [ "$#" -eq 3 ] && [ "$1" = "is-active" ] && [ "$2" = "--quiet" ]; then
	case $3 in
		active.service) exit 0 ;;
		*) exit 3 ;;
	esac
fi
if [ "$#" -eq 3 ] && [ "$1" = "is-enabled" ] && [ "$2" = "--quiet" ]; then
	case $3 in
		enabled.service) exit 0 ;;
		*) exit 1 ;;
	esac
fi
exit 0
FAKE

{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "start-active",
			module = "ops.service.systemd.start",
			args = { unit = "active.service" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'systemctl [is-active] [--quiet] [active.service]'
assert_command_not_logged 'systemctl [start] [active.service]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "start-inactive",
			module = "ops.service.systemd.start",
			args = { unit = "inactive.service" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'systemctl [is-active] [--quiet] [inactive.service]'
assert_command_logged 'systemctl [start] [inactive.service]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "enable-enabled",
			module = "ops.service.systemd.enable",
			args = { unit = "enabled.service" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'systemctl [is-enabled] [--quiet] [enabled.service]'
assert_command_not_logged 'systemctl [enable] [enabled.service]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "enable-disabled",
			module = "ops.service.systemd.enable",
			args = { unit = "disabled.service" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'systemctl [is-enabled] [--quiet] [disabled.service]'
assert_command_logged 'systemctl [enable] [disabled.service]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "reject-option-like-unit",
			module = "ops.service.systemd.start",
			args = { unit = "-bad.service" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply_failure
assert_output_contains "must not start with '-'"
assert_command_not_logged 'systemctl [start]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "reject-slash-unit",
			module = "ops.service.systemd.start",
			args = { unit = "bad/unit.service" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply_failure
assert_output_contains "must not contain '/'"
assert_command_not_logged 'systemctl [start]'
