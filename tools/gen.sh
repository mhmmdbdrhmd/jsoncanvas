#!/usr/bin/env bash
# Generate a large, nested, valid JSON file fast using only coreutils.
# Usage: tools/gen.sh [out.json] [size_mb]
set -eu
out="${1:-big.json}"
mb="${2:-200}"
R='{"id":0,"name":"alice","email":"alice@example.com","active":true,"tags":["a","b","c"],"addr":{"city":"nyc","zip":"10001","geo":{"lat":40.7,"lng":-74.0}}}'
reclen=${#R}
n=$(( mb * 1024 * 1024 / (reclen + 1) ))
{
  printf '{"meta":{"count":%d,"note":"synthetic"},"records":[' "$n"
  yes "$R" | head -n "$n" | paste -sd, -
  printf ']}'
} > "$out"
printf 'wrote %s: %s bytes, %d records\n' "$out" "$(wc -c < "$out")" "$n"
