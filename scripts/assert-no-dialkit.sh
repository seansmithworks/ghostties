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

failed=0
for f in "${macho_files[@]}"; do
    symbol_count=$(nm -m "$f" 2>/dev/null | xcrun swift-demangle | grep -c DialKit || true)
    string_count=$(strings -a "$f" | grep -c "Delete Current Preset" || true)

    if [[ "$symbol_count" -ne 0 || "$string_count" -ne 0 ]]; then
        echo "error: DialKit found in $f (symbols: $symbol_count, strings: $string_count)" >&2
        failed=1
    fi
done

if [[ "$failed" -ne 0 ]]; then
    exit 1
fi

echo "OK: no DialKit found in ${#macho_files[@]} Mach-O file(s) under $app_path"
