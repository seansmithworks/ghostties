#!/usr/bin/env bash
# Asserts a built .app bundle contains no DialKit code.
# Usage: assert-no-dialkit.sh <path-to-.app>
set -euo pipefail

app_path="${1:-}"

if [[ -z "$app_path" ]]; then
    echo "error: usage: $0 <path-to-.app>" >&2
    exit 1
fi

if [[ ! -d "$app_path" ]]; then
    echo "error: bundle not found at $app_path" >&2
    exit 1
fi

for tool in nm strings file; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required tool '$tool' not found on PATH" >&2
        exit 1
    fi
done
if ! xcrun --find swift-demangle >/dev/null 2>&1; then
    echo "error: required tool 'xcrun swift-demangle' not found" >&2
    exit 1
fi

executable="$app_path/Contents/MacOS/ghostty"
if [[ ! -f "$executable" ]]; then
    echo "error: executable not found at $executable" >&2
    exit 1
fi

macho_files=()
while IFS= read -r -d '' f; do
    if file "$f" | grep -q "Mach-O"; then
        macho_files+=("$f")
    fi
done < <(find "$app_path" -type f -print0)

if [[ ${#macho_files[@]} -eq 0 ]]; then
    echo "error: no Mach-O files found under $app_path" >&2
    exit 1
fi

# Counts matches of $2 in $1. grep -c exits 1 for "zero matches", which is
# not an error and must map to a count of 0; any other non-zero exit status
# (e.g. 2 for a real grep error) is propagated as a failure.
count_matches() {
    local input="$1" pattern="$2" count status
    if count=$(grep -c "$pattern" <<<"$input"); then
        status=0
    else
        status=$?
    fi
    if [[ "$status" -eq 0 || "$status" -eq 1 ]]; then
        [[ "$status" -eq 1 ]] && count=0
        printf '%s' "$count"
        return 0
    fi
    return "$status"
}

failed=0
for f in "${macho_files[@]}"; do
    if ! nm_output=$(nm -m "$f" 2>&1); then
        echo "error: nm failed on $f: $nm_output" >&2
        exit 1
    fi

    if ! demangled=$(printf '%s\n' "$nm_output" | xcrun swift-demangle 2>&1); then
        echo "error: xcrun swift-demangle failed on $f: $demangled" >&2
        exit 1
    fi

    if ! strings_output=$(strings -a "$f" 2>&1); then
        echo "error: strings failed on $f: $strings_output" >&2
        exit 1
    fi

    raw_symbol_count=$(count_matches "$nm_output" "DialKit")
    demangled_symbol_count=$(count_matches "$demangled" "DialKit")
    string_count=$(count_matches "$strings_output" "Delete Current Preset")

    if [[ "$raw_symbol_count" -ne 0 || "$demangled_symbol_count" -ne 0 || "$string_count" -ne 0 ]]; then
        echo "error: DialKit found in $f (raw symbols: $raw_symbol_count, demangled symbols: $demangled_symbol_count, strings: $string_count)" >&2
        failed=1
    fi
done

if [[ "$failed" -ne 0 ]]; then
    exit 1
fi

echo "OK: no DialKit found in ${#macho_files[@]} Mach-O file(s) under $app_path"
