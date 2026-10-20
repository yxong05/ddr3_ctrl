#!/bin/sh
# Run from any directory. Build outside the source tree and fail on test errors.
set -eu
cd "$(dirname "$0")"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/ddr3-tests.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT HUP INT TERM
run_test() {
  name=$1
  shift
  iverilog -g2012 -s "tb_$name" -o "$build_dir/$name.vvp" "$@"
  vvp -n "$build_dir/$name.vvp" > "$build_dir/$name.log"
  cat "$build_dir/$name.log"
  if ! grep -q 'RESULT: PASS' "$build_dir/$name.log" || grep -q 'RESULT: FAIL' "$build_dir/$name.log"; then
    exit 1
  fi
}
for t in req fsm flow maint cmd_out rd_tag wr_data; do
  run_test "$t" "tb_$t.v" "../rtl/ddr3_$t.v"
done
iverilog -g2012 -Wall -s ddr3_ctrl -o "$build_dir/top.vvp" ../rtl/*.v
