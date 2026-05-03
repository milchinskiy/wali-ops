#!/bin/sh
set -eu
. "${TEST_LIB:?}"

setup_sandbox

make_fake_command dinitctl <<'FAKE'
if [ "$#" -eq 3 ] && [ "$1" = "--quiet" ] && [ "$2" = "is-started" ]; then
	case $3 in
		running) exit 0 ;;
		*) exit 1 ;;
	esac
fi
exit 0
FAKE

make_fake_command sv <<'FAKE'
if [ "$#" -eq 2 ] && [ "$1" = "status" ]; then
	case $2 in
		*/running)
			printf '%s\n' "run: $2: (pid 123) 10s"
			exit 0
			;;
		*)
			printf '%s\n' "down: $2: 10s"
			exit 1
			;;
	esac
fi
exit 0
FAKE

service_dir=$TEST_SANDBOX/runit-services
mkdir -p "$service_dir/running" "$service_dir/stopped"

{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "dinit-start-running",
			module = "ops.service.dinit.start",
			args = { service = "running" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'dinitctl [--quiet] [is-started] [running]'
assert_command_not_logged 'dinitctl [start] [running]'

reset_command_log
{
	manifest_header
	cat <<'MANIFEST'
		{
			id = "dinit-start-stopped",
			module = "ops.service.dinit.start",
			args = { service = "stopped" },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged 'dinitctl [--quiet] [is-started] [stopped]'
assert_command_logged 'dinitctl [start] [stopped]'

reset_command_log
{
	manifest_header
	cat <<MANIFEST
		{
			id = "runit-start-running",
			module = "ops.service.runit.start",
			args = { service = "running", service_dir = $(lua_quote "$service_dir") },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged "sv [status] [$service_dir/running]"
assert_command_not_logged "sv [up] [$service_dir/running]"

reset_command_log
{
	manifest_header
	cat <<MANIFEST
		{
			id = "runit-start-stopped",
			module = "ops.service.runit.start",
			args = { service = "stopped", service_dir = $(lua_quote "$service_dir") },
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_logged "sv [status] [$service_dir/stopped]"
assert_command_logged "sv [up] [$service_dir/stopped]"
