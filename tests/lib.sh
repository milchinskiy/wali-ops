# POSIX test helpers for wali-ops.
# shellcheck shell=sh

: "${WALI_OPS_ROOT:?WALI_OPS_ROOT is required}"
: "${WALI_BIN:=wali}"

TEST_SANDBOX=
TEST_FAKE_BIN=
TEST_COMMAND_LOG=
TEST_STDOUT=
TEST_STDERR=
TEST_MANIFEST=
TEST_PATH=

fail() {
	printf '%s\n' "error: $*" >&2
	exit 1
}

lua_quote() {
	printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

setup_sandbox() {
	base=${TMPDIR:-/tmp}
	TEST_SANDBOX=$(mktemp -d "${base%/}/wali-ops-test.XXXXXX") || exit 1
	TEST_FAKE_BIN=$TEST_SANDBOX/bin
	TEST_COMMAND_LOG=$TEST_SANDBOX/commands.log
	TEST_STDOUT=$TEST_SANDBOX/stdout.log
	TEST_STDERR=$TEST_SANDBOX/stderr.log
	TEST_MANIFEST=$TEST_SANDBOX/manifest.lua
	mkdir -p "$TEST_FAKE_BIN"
	: >"$TEST_COMMAND_LOG"
	TEST_PATH=$TEST_FAKE_BIN:$PATH
	export TEST_SANDBOX TEST_FAKE_BIN TEST_COMMAND_LOG TEST_STDOUT TEST_STDERR TEST_MANIFEST TEST_PATH
	trap cleanup_sandbox EXIT HUP INT TERM
}

cleanup_sandbox() {
	if [ -n "${TEST_SANDBOX:-}" ] && [ -d "$TEST_SANDBOX" ]; then
		rm -rf "$TEST_SANDBOX"
	fi
}

reset_command_log() {
	: >"$TEST_COMMAND_LOG"
}

write_manifest() {
	cat >"$TEST_MANIFEST"
}

manifest_header() {
	cat <<MANIFESTEOF
return {
	hosts = {
		{ id = "localhost", transport = "local" },
	},
	modules = {
		{ namespace = "ops", path = $(lua_quote "$WALI_OPS_ROOT/modules") },
	},
	tasks = {
MANIFESTEOF
}

manifest_footer() {
	cat <<'MANIFESTEOF'
	},
}
MANIFESTEOF
}

run_wali_apply() {
	NO_COLOR=1 PATH="$TEST_PATH" "$WALI_BIN" --json apply "$TEST_MANIFEST" >"$TEST_STDOUT" 2>"$TEST_STDERR" || {
		printf '%s\n' "wali apply failed" >&2
		printf '%s\n' "--- stdout ---" >&2
		cat "$TEST_STDOUT" >&2 || true
		printf '%s\n' "--- stderr ---" >&2
		cat "$TEST_STDERR" >&2 || true
		exit 1
	}
}

run_wali_apply_failure() {
	if NO_COLOR=1 PATH="$TEST_PATH" "$WALI_BIN" --json apply "$TEST_MANIFEST" >"$TEST_STDOUT" 2>"$TEST_STDERR"; then
		printf '%s\n' "wali apply succeeded unexpectedly" >&2
		printf '%s\n' "--- stdout ---" >&2
		cat "$TEST_STDOUT" >&2 || true
		printf '%s\n' "--- stderr ---" >&2
		cat "$TEST_STDERR" >&2 || true
		exit 1
	fi
}

make_fake_command() {
	name=$1
	path=$TEST_FAKE_BIN/$name
	{
		printf '%s\n' '#!/bin/sh'
		printf '%s\n' 'set -eu'
		printf '%s\n' "__wali_ops_cmd='$name'"
		cat <<'FAKEEOF'
printf '%s' "$__wali_ops_cmd" >>"${TEST_COMMAND_LOG:?}"
for __wali_ops_arg do
	printf ' [%s]' "$__wali_ops_arg" >>"${TEST_COMMAND_LOG:?}"
done
printf '\n' >>"${TEST_COMMAND_LOG:?}"
FAKEEOF
		cat
	} >"$path"
	chmod +x "$path"
}

assert_file_contains() {
	file=$1
	needle=$2
	[ -f "$file" ] || fail "expected file to exist: $file"
	grep -F -- "$needle" "$file" >/dev/null 2>&1 || {
		printf '%s\n' "file did not contain expected text: $needle" >&2
		printf '%s\n' "--- $file ---" >&2
		cat "$file" >&2 || true
		exit 1
	}
}

assert_file_not_contains() {
	file=$1
	needle=$2
	if [ -f "$file" ] && grep -F -- "$needle" "$file" >/dev/null 2>&1; then
		printf '%s\n' "file contained unexpected text: $needle" >&2
		printf '%s\n' "--- $file ---" >&2
		cat "$file" >&2 || true
		exit 1
	fi
}

assert_command_logged() {
	assert_file_contains "$TEST_COMMAND_LOG" "$1"
}

assert_command_not_logged() {
	assert_file_not_contains "$TEST_COMMAND_LOG" "$1"
}

assert_output_contains() {
	needle=$1
	if ! { grep -F -- "$needle" "$TEST_STDOUT" >/dev/null 2>&1 || grep -F -- "$needle" "$TEST_STDERR" >/dev/null 2>&1; }; then
		printf '%s\n' "wali output did not contain expected text: $needle" >&2
		printf '%s\n' "--- stdout ---" >&2
		cat "$TEST_STDOUT" >&2 || true
		printf '%s\n' "--- stderr ---" >&2
		cat "$TEST_STDERR" >&2 || true
		exit 1
	fi
}

assert_eq() {
	expected=$1
	actual=$2
	if [ "$expected" != "$actual" ]; then
		printf '%s\n' "expected: $expected" >&2
		printf '%s\n' "actual:   $actual" >&2
		exit 1
	fi
}

assert_exists() {
	[ -e "$1" ] || fail "expected path to exist: $1"
}

assert_not_exists() {
	[ ! -e "$1" ] || fail "expected path not to exist: $1"
}
