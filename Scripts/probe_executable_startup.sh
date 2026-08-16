#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 || ! -x "$1" ]]; then
  print -u2 "usage: probe_executable_startup.sh /path/to/executable"
  exit 64
fi

EXECUTABLE="$1"
RUNTIME_LOG="$(mktemp /tmp/loopforge-executable-probe.XXXXXX.log)"
RUNTIME_PID=""
RUNTIME_EXITED=0
zmodload zsh/zselect
# Observe the shell-owned job directly. Polling with `ps`, `kill -0`, or a
# helper `sleep` can inspect a rapidly reused PID (including the probe's own
# helper process) instead of the original executable. Between spawn and
# cleanup this shell creates no child except the executable, so CHLD is an
# exact job-lifecycle fact and `zselect` supplies a child-free bounded delay.
TRAPCHLD() {
  RUNTIME_EXITED=1
}
report_early_exit() {
  local child_status=0
  wait "$RUNTIME_PID" || child_status=$?
  print -u2 "Executable exited during startup with status $child_status."
  /bin/cat "$RUNTIME_LOG" >&2
  exit 1
}
cleanup_runtime() {
  if [[ -n "$RUNTIME_PID" ]] && (( ! RUNTIME_EXITED )); then
    kill -TERM "$RUNTIME_PID" 2>/dev/null || true
    for _ in {1..10}; do
      (( RUNTIME_EXITED )) && break
      zselect -t 5 2>/dev/null || true
    done
    (( RUNTIME_EXITED )) || kill -KILL "$RUNTIME_PID" 2>/dev/null || true
  fi
  [[ -z "$RUNTIME_PID" ]] || wait "$RUNTIME_PID" 2>/dev/null || true
  /bin/rm -f "$RUNTIME_LOG"
}
trap cleanup_runtime EXIT INT TERM

"$EXECUTABLE" --loopforge-package-smoke >"$RUNTIME_LOG" 2>&1 &
RUNTIME_PID=$!
for _ in {1..20}; do
  (( RUNTIME_EXITED )) && report_early_exit
  zselect -t 10 2>/dev/null || true
done
(( RUNTIME_EXITED )) && report_early_exit

print "Executable startup probe passed."
