#!/usr/bin/env bash
# Asserts a built .app bundle is not code-coverage instrumented.
# Instrumented binaries link the LLVM profile runtime and write default.profraw
# into the cwd on exit, and embed source paths via coverage mapping.
# Usage: assert-no-coverage.sh <path-to-.app>
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

# grep -c exits 1 for "zero matches"; map that to 0, propagate real errors.
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
    if ! nm_output=$(nm "$f" 2>&1); then
        echo "error: nm failed on $f: $nm_output" >&2
        exit 1
    fi
    if ! strings_output=$(strings -a "$f" 2>&1); then
        echo "error: strings failed on $f: $strings_output" >&2
        exit 1
    fi

    profc_count=$(count_matches "$nm_output" "___profc_")
    profile_env_count=$(count_matches "$strings_output" "LLVM_PROFILE_FILE")

    if [[ "$profc_count" -ne 0 || "$profile_env_count" -ne 0 ]]; then
        echo "error: coverage instrumentation found in $f (___profc_ symbols: $profc_count, LLVM_PROFILE_FILE strings: $profile_env_count)" >&2
        failed=1
    fi
done

if [[ "$failed" -ne 0 ]]; then
    exit 1
fi

echo "OK: no coverage instrumentation found in ${#macho_files[@]} Mach-O file(s) under $app_path"
