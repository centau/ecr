#!/usr/bin/env bash
# Type-level test runner for ecr's public type surface.
# usage: ./run.sh [path-to-luau-analyze]
set -uo pipefail
cd "$(dirname "$0")"

ANALYZE="${1:-luau-analyze}"
command -v "$ANALYZE" >/dev/null 2>&1 || { echo "cannot find $ANALYZE"; exit 127; }

FAILURES=0
TOTAL=0
PASSED=0

COLOR_WHITE='\033[37;1m'
COLOR_GREEN='\033[32;1m'
COLOR_RED='\033[31;1m'
COLOR_GRAY='\033[30;1m'
COLOR_RESET='\033[0m'

print_case() {
    local status=$1 name=$2
    local color=$COLOR_GREEN
    [ "$status" = PASS ] || color=$COLOR_RED
    printf '%b%s%b%b│%b %b%s%b\n' "$color" "$status" "$COLOR_RESET" "$COLOR_GRAY" "$COLOR_RESET" "$COLOR_GRAY" "$name" "$COLOR_RESET"
}

pass_case() {
    TOTAL=$((TOTAL + 1))
    PASSED=$((PASSED + 1))
    print_case PASS "$1"
}

fail_case() {
    TOTAL=$((TOTAL + 1))
    FAILURES=$((FAILURES + 1))
    print_case FAIL "$1"
}

# ecr.luau is imported directly. Its implementation diagnostics are reported
# at src/ecr.luau locations; this suite checks only consumer fixture locations.
printf '%btypechecking%b\n' "$COLOR_WHITE" "$COLOR_RESET"
OUT=$("$ANALYZE" --solver=new tests.luau 2>&1 | grep -E '^\./tests\.luau\([0-9]+,.*(TypeError|SyntaxError)' || true)
if [ -n "$OUT" ]; then
    fail_case "typechecks"
    printf '%s\n' "$OUT" | sed 's/^/  /'
else
    pass_case "typechecks"
fi

OUT=$("$ANALYZE" --solver=new errors.luau 2>&1)

mapfile -t GOT < <(echo "$OUT" | grep -E 'TypeError|SyntaxError' | grep -oE '^\./errors\.luau\([0-9]+,' | grep -oE '[0-9]+' | sort -un)
mapfile -t WANT < <(grep -nE '^[^-]*--[[:space:]]*@error' errors.luau | cut -d: -f1 | sort -un)

in_list() { local n=$1; shift; for x in "$@"; do [ "$x" = "$n" ] && return 0; done; return 1; }

for w in "${WANT[@]}"; do
    if in_list "$w" "${GOT[@]}"; then
        pass_case "fails typechecking ($w)"
    else
        fail_case "fails typechecking ($w)"
        sed -n "${w}p" errors.luau | sed 's/^/          /'
    fi
done

for g in "${GOT[@]}"; do
    if ! in_list "$g" "${WANT[@]}"; then
        fail_case "unexpected type error ($g)"
        echo "$OUT" | grep "errors.luau($g," | sed 's/^/          /'
    fi
done

printf '\n%b%d/%d test cases passed.%b\n' "$COLOR_GRAY" "$PASSED" "$TOTAL" "$COLOR_RESET"
if [ "$FAILURES" -eq 0 ]; then
    printf '%b0 fails%b\n' "$COLOR_GREEN" "$COLOR_RESET"
else
    printf '%b%d fail%s%b\n' "$COLOR_RED" "$FAILURES" "$([ "$FAILURES" -eq 1 ] && echo '' || echo 's')" "$COLOR_RESET"
    exit 1
fi
