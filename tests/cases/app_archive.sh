#!/bin/sh

set -eu
. "${TEST_LIB:?}"

setup_sandbox

make_fake_command tar <<'FAKE'
case "$1" in
	-C)
		cwd=$2
		shift 2
		case "$1" in
			-czf|-cf|-cjf|-cJf)
				out=$2
				member=$3
				[ -n "$out" ] || exit 64
				[ -n "$member" ] || exit 64
				printf 'tar-archive cwd=%s member=%s\n' "$cwd" "$member" >"$out"
				exit 0
				;;
			-k)
				shift
				;;
		esac
		case "$1" in
			-xzf|-xf|-xjf|-xJf)
				archive=$2
				mkdir -p "$cwd"
				printf 'extracted:%s\n' "$archive" >"$cwd/tar-file.txt"
				exit 0
				;;
		esac
		;;
	-tzf|-tf|-tjf|-tJf)
		case "$2" in
			*unsafe*)
				printf '../evil\n'
				;;
			*)
				printf './payload/file.txt\n'
				;;
		esac
		exit 0
		;;
esac
exit 64
FAKE

make_fake_command zip <<'FAKE'
out=
member=
while [ "$#" -gt 0 ]; do
	case $1 in
		-q|-r)
			shift
			continue
			;;
		*)
			if [ -z "$out" ]; then
				out=$1
			else
				member=$1
			fi
			;;
	esac
	shift || true
done
[ -n "$out" ] || exit 64
[ -n "$member" ] || exit 64
printf 'zip-archive cwd=%s member=%s\n' "$(pwd)" "$member" >"$out"
FAKE

make_fake_command unzip <<'FAKE'
case "$1" in
	-Z1)
		case "$2" in
			*unsafe*)
				printf '/absolute\n'
				;;
			*)
				printf 'payload/file.txt\n'
				;;
		esac
		exit 0
		;;
	-q)
		mode=$2
		archive=$3
		[ "$4" = "-d" ] || exit 64
		dest=$5
		mkdir -p "$dest"
		printf 'unzipped:%s:%s\n' "$mode" "$archive" >"$dest/zip-file.txt"
		exit 0
		;;
esac
exit 64
FAKE

src_dir=$TEST_SANDBOX/src-tree
mkdir -p "$src_dir"
printf 'payload\n' >"$src_dir/file.txt"
archive_path=$TEST_SANDBOX/out/payload.tar.gz
{
	manifest_header
	cat <<MANIFEST
		{
			id = "archive-tar-gz",
			module = "ops.app.archive",
			args = {
				src = $(lua_quote "$src_dir"),
				dest = $(lua_quote "$archive_path"),
				parents = true,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_file_contains "$archive_path" "tar-archive cwd=$TEST_SANDBOX member=./src-tree"
assert_command_logged 'tar [-C]'
assert_command_logged '[-czf]'

reset_command_log
{
	manifest_header
	cat <<MANIFEST
		{
			id = "archive-keep-existing",
			module = "ops.app.archive",
			args = {
				src = $(lua_quote "$src_dir"),
				dest = $(lua_quote "$archive_path"),
				replace = false,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_command_not_logged 'tar ['
assert_file_contains "$archive_path" 'tar-archive'

zip_path=$TEST_SANDBOX/out/payload.zip
{
	manifest_header
	cat <<MANIFEST
		{
			id = "archive-zip",
			module = "ops.app.archive",
			args = {
				src = $(lua_quote "$src_dir"),
				dest = $(lua_quote "$zip_path"),
				parents = true,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_file_contains "$zip_path" "zip-archive cwd=$TEST_SANDBOX member=./src-tree"
assert_command_logged 'zip [-q] [-r]'
if find "$TEST_SANDBOX/out" -name '.wali-archive-*' -print | grep . >/dev/null 2>&1; then
	printf '%s\n' 'archive creation left a temporary directory behind' >&2
	find "$TEST_SANDBOX/out" -name '.wali-archive-*' -print >&2
	exit 1
fi

tar_dest=$TEST_SANDBOX/extracted/tar
{
	manifest_header
	cat <<MANIFEST
		{
			id = "unarchive-tar-gz",
			module = "ops.app.unarchive",
			args = {
				src = $(lua_quote "$archive_path"),
				dest = $(lua_quote "$tar_dest"),
				parents = true,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_file_contains "$tar_dest/tar-file.txt" "extracted:$archive_path"
assert_command_logged 'tar [-tzf]'
assert_command_logged 'tar [-C]'
assert_command_logged '[-xzf]'

zip_dest=$TEST_SANDBOX/extracted/zip
{
	manifest_header
	cat <<MANIFEST
		{
			id = "unarchive-zip-no-replace",
			module = "ops.app.unarchive",
			args = {
				src = $(lua_quote "$zip_path"),
				dest = $(lua_quote "$zip_dest"),
				parents = true,
				replace = false,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply
assert_file_contains "$zip_dest/zip-file.txt" "unzipped:-n:$zip_path"
assert_command_logged 'unzip [-Z1]'
assert_command_logged 'unzip [-q] [-n]'

unsafe_archive=$TEST_SANDBOX/out/unsafe.tar.gz
printf 'fake\n' >"$unsafe_archive"
{
	manifest_header
	cat <<MANIFEST
		{
			id = "unarchive-rejects-traversal",
			module = "ops.app.unarchive",
			args = {
				src = $(lua_quote "$unsafe_archive"),
				dest = $(lua_quote "$TEST_SANDBOX/extracted/unsafe"),
				parents = true,
			},
		},
MANIFEST
	manifest_footer
} >"$TEST_MANIFEST"

run_wali_apply_failure
assert_output_contains 'archive member escapes destination'
assert_not_exists "$TEST_SANDBOX/evil"
