#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
: "${WALI_BIN:=wali}"

if ! command -v "$WALI_BIN" >/dev/null 2>&1; then
	printf '%s\n' "error: wali binary not found; set WALI_BIN=/path/to/wali" >&2
	exit 127
fi

if [ "$#" -eq 0 ]; then
	set -- "$ROOT"/tests/cases/*.sh
fi

passed=0
failed=0

for case_file do
	case $case_file in
		/*) path=$case_file ;;
		*) path=$ROOT/$case_file ;;
	esac
	name=$(basename "$path" .sh)
	printf '%s ... ' "$name"
	if WALI_OPS_ROOT=$ROOT WALI_BIN=$WALI_BIN TEST_LIB=$ROOT/tests/lib.sh sh "$path"; then
		printf '%s\n' ok
		passed=$((passed + 1))
	else
		printf '%s\n' FAIL
		failed=$((failed + 1))
	fi
done

printf '%s\n' "passed: $passed"
if [ "$failed" -ne 0 ]; then
	printf '%s\n' "failed: $failed" >&2
	exit 1
fi
