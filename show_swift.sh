#!/usr/bin/env bash
# show_swift.sh
# Collects all .swift files and writes them to a single text file with
# two blank lines before each header. Prints a total line count at the end.
# Usage:
#   ./show_swift.sh                 # writes to swift_output.txt
#   ./show_swift.sh --output out.txt

set -euo pipefail

# -------- settings --------
output_file="swift_output.txt"
if [[ "${1:-}" == "--output" && -n "${2:-}" ]]; then
  output_file="$2"
  shift 2
fi
# --------------------------

# Redirect all stdout to the output file
exec > "$output_file"

total_lines=0

# Find .swift files, skipping common build/vendor dirs; handle spaces via -print0
# Remove the -path/-prune blocks if you want to include everything.
find_cmd=(
  find .
  -path "./.git" -prune -o
  -path "./.build" -prune -o
  -path "./build" -prune -o
  -path "./DerivedData" -prune -o
  -path "./Pods" -prune -o
  -path "./Carthage" -prune -o
  -path "./.swiftpm" -prune -o
  -type f -name "*.swift" -print0
)

# Iterate in a way that preserves spaces/newlines in filenames
while IFS= read -r -d '' file; do
  printf "\n\n===== File: %s =====\n" "$file"
  cat "$file"
  # wc can emit leading spaces; trim with tr
  file_lines=$(wc -l < "$file" | tr -d ' ')
  total_lines=$(( total_lines + file_lines ))
done < <("${find_cmd[@]}" | sort -z)

echo
echo "Total lines of Swift code displayed: $total_lines"
