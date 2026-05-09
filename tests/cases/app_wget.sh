#!/bin/sh

set -eu
. "${TEST_LIB:?}"

setup_sandbox

make_fake_command wget <<'FAKE'
out=
url=
while [ "$#" -gt 0 ]; do
	case $1 in
		--output-document)
			shift
			out=$1
			;;
		--)
			shift
			url=${1:-}
			break
			;;
	esac
	shift || true
done
[ -n "$out" ] || exit 64
case $url in
	*fail*)
		exit 8
		;;
	*)
		printf 'downloaded:%s\n' "$url" >"$out"
		exit 0
		;;
esac
FAKE

dest=$TEST_SANDBOX/downloads/file.txt
{
	manifest_header
	cat <<MANIFEST
		{
			id = "wget-download",
			module = "ops.app.wget",
			args = {
				url = "https://example.invalid/file.txt",
				dest = $(lua_quote "$dest"),
				parents = true,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_file_contains "$dest" 'downloaded:https://example.invalid/file.txt'
assert_command_logged 'wget [--output-document]'
assert_command_logged '[--] [https://example.invalid/file.txt]'

reset_command_log
{
	manifest_header
	cat <<MANIFEST
		{
			id = "wget-keep-existing",
			module = "ops.app.wget",
			args = {
				url = "https://example.invalid/other.txt",
				dest = $(lua_quote "$dest"),
				replace = false,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_not_logged 'wget ['
assert_file_contains "$dest" 'downloaded:https://example.invalid/file.txt'

fail_dest=$TEST_SANDBOX/downloads/fail.txt
{
	manifest_header
	cat <<MANIFEST
		{
			id = "wget-failure-cleans-temp",
			module = "ops.app.wget",
			args = {
				url = "https://example.invalid/fail.txt",
				dest = $(lua_quote "$fail_dest"),
				parents = true,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply_failure
assert_not_exists "$fail_dest"
if find "$TEST_SANDBOX/downloads" -name '.wali-wget-*' -print | grep . >/dev/null 2>&1; then
	printf '%s\n' 'wget failure left a temporary file behind' >&2
	find "$TEST_SANDBOX/downloads" -name '.wali-wget-*' -print >&2
	exit 1
fi
