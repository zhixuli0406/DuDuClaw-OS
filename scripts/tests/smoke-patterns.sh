#!/usr/bin/env bash
# Checks release-os.sh's smoke-test log matchers (SMOKE_LOGIN_RE,
# SMOKE_DIED_RE) against the fixtures in fixtures/smoke/. No Docker, no
# QEMU: it reads the two assignments straight out of release-os.sh and runs
# `grep -E` on each fixture line, the same way the smoke loop does inside the
# builder.
#
#   scripts/tests/smoke-patterns.sh       # exit 0 = all cases pass
#
# Fails closed: if either assignment cannot be found, that is a failure, not
# a skip.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../release-os.sh"
fixtures="$here/fixtures/smoke"

assignments="$(grep -E "^SMOKE_(LOGIN|DIED)_RE='" "$script" || true)"
if [[ "$(printf '%s\n' "$assignments" | grep -c .)" -ne 2 ]]; then
    echo "FAIL: expected exactly one SMOKE_LOGIN_RE= and one SMOKE_DIED_RE= line in $script" >&2
    exit 1
fi
eval "$assignments"

fail=0 total=0
# check <regex> <fixture> <want: match|nomatch>
check() {
    local re="$1" file="$2" want="$3" line got
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        total=$((total + 1))
        if printf '%s\n' "$line" | grep -qE -- "$re"; then got=match; else got=nomatch; fi
        if [[ "$got" != "$want" ]]; then
            fail=$((fail + 1))
            echo "FAIL ($(basename "$file"), want $want, got $got): $line" >&2
        fi
    done < "$file"
}

check "$SMOKE_DIED_RE"  "$fixtures/died.log"     match
check "$SMOKE_DIED_RE"  "$fixtures/harmless.log" nomatch
check "$SMOKE_LOGIN_RE" "$fixtures/login.log"    match
# A login line must never be mistaken for a death, and vice versa.
check "$SMOKE_DIED_RE"  "$fixtures/login.log"    nomatch
check "$SMOKE_LOGIN_RE" "$fixtures/died.log"     nomatch

if [[ $fail -ne 0 ]]; then
    echo "smoke-patterns: $fail of $total cases failed" >&2
    exit 1
fi
echo "smoke-patterns: all $total cases passed"
