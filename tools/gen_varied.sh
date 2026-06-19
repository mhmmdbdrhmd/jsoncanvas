#!/usr/bin/env bash
# Generate a large, EXTREMELY DEEPLY NESTED, heterogeneous JSON file.
# Each record is a spine of nested objects of VARYING depth (6..30 levels) — no two
# records share a shape: some levels carry small arrays, some carry flags, some
# records bury a nested array big enough to itself virtualize. This exercises deep
# drilling (`e` expand-all), the tree outline, and nested virtualization — not just
# one giant flat list.
# Usage: tools/gen_varied.sh [out.json] [count]   (default varied.json, 1,000,000)
set -eu
out="${1:-varied.json}"
n="${2:-1000000}"

gawk -v n="$n" 'BEGIN{
  split("alice bob carol dave erin frank grace heidi ivan judy", NAMES, " ")
  split("admin editor viewer guest owner", ROLES, " ")
  split("red green blue amber violet", TAGS, " ")
  split("alpha beta gamma delta epsilon zeta eta theta", WORDS, " ")
  printf "{\"meta\":{\"count\":%d,\"note\":\"deeply-nested\",\"schema\":{\"version\":4,\"maxDepth\":30}},\"records\":[", n
  for (i = 0; i < n; i++) {
    if (i) printf ","
    rec(i)
  }
  printf "]}\n"
}
function nm(i){ return NAMES[(i % 10) + 1] }
function wd(i){ return WORDS[(i % 8) + 1] }
# one nested spine of `depth` objects under repeated key "child", heterogeneous
# per level, then a leaf object; returns the number of OPEN braces to close.
function rec(i,   depth, j, t, k, opens) {
  depth = 6 + (i % 25)                       # 6 .. 30 levels deep, varies per record
  printf "{\"id\":%d,\"name\":\"%s\",\"depth\":%d", i, nm(i), depth
  opens = 1                                   # the record object itself
  for (j = 0; j < depth; j++) {
    printf ",\"child\":{\"level\":%d,\"kind\":\"%s\"", j, wd(i + j)
    opens++
    # heterogeneity: sprinkle different shapes at different levels
    if ((i + j) % 3 == 0) {                   # a small tags array
      k = (i + j) % 5
      printf ",\"tags\":["
      for (t = 0; t < k; t++) { if (t) printf ","; printf "\"%s\"", TAGS[(t % 5) + 1] }
      printf "]"
    }
    if ((i + j) % 4 == 1) printf ",\"active\":%s", ((i + j) % 2 ? "true" : "false")
    if ((i + j) % 5 == 2) printf ",\"score\":%d.%02d", (i + j) % 100, (i * 7 + j) % 100
    # every 7th record buries a nested array LARGE enough (up to 30 > MAXROWS=14) to
    # itself virtualize, partway down the spine.
    if (i % 7 == 0 && j == 3) {
      k = 16 + (i % 16)
      printf ",\"history\":["
      for (t = 0; t < k; t++) { if (t) printf ","; printf "{\"ts\":%d,\"ev\":\"e%d\"}", 1700000000 + t, t }
      printf "]"
    }
  }
  # leaf at the bottom of the spine
  printf ",\"leaf\":{\"final\":true,\"value\":%d,\"by\":\"%s\"}", i, nm(i + 1)
  for (j = 0; j < opens; j++) printf "}"
}' > "$out"

printf 'wrote %s: %s bytes, %d records (deeply nested, depth 6-30, heterogeneous)\n' \
  "$out" "$(wc -c < "$out")" "$n"
