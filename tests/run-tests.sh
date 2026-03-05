#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACGEM_BIN="$ROOT_DIR/pacgem"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  if [[ "$expected" != "$actual" ]]; then
    fail "$msg (expected: '$expected', actual: '$actual')"
  fi
}

run_test_passthrough_args() {
  local tmp
  tmp="$(mktemp -d)"

  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/pacman" <<'PACMAN'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${TEST_PACMAN_ARGS_FILE}"
exit "${TEST_PACMAN_EXIT:-0}"
PACMAN
  chmod +x "$tmp/bin/pacman"

  export PATH="$tmp/bin:$PATH"
  export TEST_PACMAN_ARGS_FILE="$tmp/pacman_args"
  export TEST_PACMAN_EXIT=0

  if [[ ! -x "$PACGEM_BIN" ]]; then
    fail "pacgem executable not found at $PACGEM_BIN"
  fi

  "$PACGEM_BIN" -Syu --noconfirm >/dev/null 2>&1
  local status=$?

  assert_eq "0" "$status" "pacgem should exit 0 when pacman succeeds"
  assert_eq "-Syu --noconfirm" "$(cat "$tmp/pacman_args")" "pacgem must pass all args to pacman unchanged"
  rm -rf "$tmp"
}

run_test_error_prompt_and_gemini_payload() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/pacman" <<'PACMAN'
#!/usr/bin/env bash
echo "error: failed to prepare transaction (could not satisfy dependencies)" >&2
echo "error: dependency cycle detected" >&2
exit 1
PACMAN
  chmod +x "$tmp/bin/pacman"

  cat > "$tmp/bin/gemini" <<'GEMINI'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${TEST_GEMINI_ARGS_FILE}"
cat > "${TEST_GEMINI_INPUT_FILE}"
exit 0
GEMINI
  chmod +x "$tmp/bin/gemini"

  export PATH="$tmp/bin:$PATH"
  export TEST_GEMINI_ARGS_FILE="$tmp/gemini_args"
  export TEST_GEMINI_INPUT_FILE="$tmp/gemini_input"
  export PACGEM_NO_TERMINAL=1

  set +e
  local output
  output="$(printf 'y\n' | "$PACGEM_BIN" -Syu 2>&1)"
  local status=$?
  set -e

  assert_eq "1" "$status" "pacgem should return pacman's non-zero exit code"
  [[ "$output" == *"Would you like to send the error to Gemini? [y/n]"* ]] || fail "expected Gemini prompt after pacman failure"
  [[ "$(cat "$tmp/gemini_args")" == *"--yolo"* ]] || fail "gemini should be invoked with --yolo"
  [[ "$(cat "$tmp/gemini_input")" == *"Please fix the errors with my Arch Linux's pacman."* ]] || fail "gemini payload missing fixed instruction preamble"
  [[ "$(cat "$tmp/gemini_input")" == *"This happened while running -Syu"* ]] || fail "gemini payload missing command context"
  [[ "$(cat "$tmp/gemini_input")" == *"error: failed to prepare transaction"* ]] || fail "gemini payload missing pacman error output"
  rm -rf "$tmp"
}

run_test_context_uses_flags_only() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/pacman" <<'PACMAN'
#!/usr/bin/env bash
echo "error: target not found: imaginary-package" >&2
exit 1
PACMAN
  chmod +x "$tmp/bin/pacman"

  cat > "$tmp/bin/gemini" <<'GEMINI'
#!/usr/bin/env bash
cat > "${TEST_GEMINI_INPUT_FILE}"
exit 0
GEMINI
  chmod +x "$tmp/bin/gemini"

  export PATH="$tmp/bin:$PATH"
  export TEST_GEMINI_INPUT_FILE="$tmp/gemini_input"
  export PACGEM_NO_TERMINAL=1

  set +e
  printf 'y\n' | "$PACGEM_BIN" -S imaginary-package >/dev/null 2>&1
  local status=$?
  set -e

  assert_eq "1" "$status" "pacgem should return non-zero for failing pacman command"
  local context_line
  context_line="$(grep -F "This happened while running" "$tmp/gemini_input" || true)"
  [[ "$context_line" == *"This happened while running -S"* ]] || fail "command context should include -S flag"
  [[ "$context_line" != *"imaginary-package"* ]] || fail "command context should not include non-flag package arguments"
  rm -rf "$tmp"
}

run_test_decline_skips_gemini() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/pacman" <<'PACMAN'
#!/usr/bin/env bash
echo "error: failed to synchronize all databases" >&2
exit 1
PACMAN
  chmod +x "$tmp/bin/pacman"

  cat > "$tmp/bin/gemini" <<'GEMINI'
#!/usr/bin/env bash
touch "${TEST_GEMINI_CALLED_FILE}"
exit 0
GEMINI
  chmod +x "$tmp/bin/gemini"

  export PATH="$tmp/bin:$PATH"
  export TEST_GEMINI_CALLED_FILE="$tmp/gemini_called"
  export PACGEM_NO_TERMINAL=1

  set +e
  printf 'n\n' | "$PACGEM_BIN" -Syu >/dev/null 2>&1
  local status=$?
  set -e

  assert_eq "1" "$status" "declining prompt should still return pacman failure status"
  [[ ! -f "$tmp/gemini_called" ]] || fail "gemini should not be called when user declines"
  rm -rf "$tmp"
}

run_test_yes_without_gemini_binary() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/bin"

  cat > "$tmp/bin/pacman" <<'PACMAN'
#!/usr/bin/env bash
echo "error: keyring is not writable" >&2
exit 1
PACMAN
  chmod +x "$tmp/bin/pacman"

  export PATH="$tmp/bin:$PATH"
  export PACGEM_NO_TERMINAL=1
  export PACGEM_GEMINI_BIN="gemini-does-not-exist"

  set +e
  local output
  output="$(printf 'y\n' | "$PACGEM_BIN" -Syu 2>&1)"
  local status=$?
  set -e

  assert_eq "1" "$status" "missing gemini should not change pacman failure status"
  [[ "$output" == *"gemini command not found"* ]] || fail "should show missing gemini guidance when user selects yes"
  unset PACGEM_GEMINI_BIN
  rm -rf "$tmp"
}

main() {
  run_test_passthrough_args
  run_test_error_prompt_and_gemini_payload
  run_test_context_uses_flags_only
  run_test_decline_skips_gemini
  run_test_yes_without_gemini_binary
  echo "PASS: run_test_passthrough_args"
  echo "PASS: run_test_error_prompt_and_gemini_payload"
  echo "PASS: run_test_context_uses_flags_only"
  echo "PASS: run_test_decline_skips_gemini"
  echo "PASS: run_test_yes_without_gemini_binary"
  echo "All tests passed."
}

main "$@"
