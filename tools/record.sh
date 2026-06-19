#!/usr/bin/env bash
# Record a scripted terminal demo of canvas as an asciinema .cast, then render a .gif.
#
#   tools/record.sh [FILE] [OUT_BASENAME]
#     FILE          json to open        (default: varied.json)
#     OUT_BASENAME  output path w/o ext  (default: docs/img/demo)
#
# Drives the REAL interactive canvas inside an xterm with xdotool, so the demo shows
# genuine pan / zoom / semantic-zoom LOD / goto / drill-in / expand-all. The session is
# recorded with asciinema (-> OUT.cast) and rendered to a gif with agg if present:
#   agg --speed 1.5 OUT.cast OUT.gif
#
# Requires: asciinema, xterm, xdotool on an X11 display (and agg for the gif).
# Tip: build the on-disk index first so the deep goto is instant:  ./canvas FILE --index
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="${1:-varied.json}"
OUT="${2:-$REPO/docs/img/demo}"
CAST="$OUT.cast"; GIF="$OUT.gif"
TITLE="CANVASREC"
COLS=118; ROWS=34; FONTPT=13

for c in asciinema xterm xdotool; do command -v "$c" >/dev/null || { echo "need $c" >&2; exit 1; }; done

old=$(xdotool search --name "^${TITLE}\$" 2>/dev/null | head -1)
[ -n "$old" ] && xdotool windowkill "$old" 2>/dev/null

xterm -T "$TITLE" -geometry "${COLS}x${ROWS}" -bg black -fg gray90 \
      -fa 'DejaVu Sans Mono' -fs "$FONTPT" \
      -e bash -lc "cd '$REPO'; CANVAS_NOFONT=1 asciinema rec --overwrite -c './canvas $FILE' '$CAST'" &

WID=""
for _ in $(seq 1 50); do WID=$(xdotool search --name "^${TITLE}\$" 2>/dev/null | head -1); [ -n "$WID" ] && break; sleep 0.2; done
[ -z "$WID" ] && { echo "xterm window never appeared" >&2; exit 1; }
sleep 3   # canvas builds the model + draws the first frame

k(){ xdotool key  --window "$WID" --delay 60 "$@"; }
t(){ xdotool type --window "$WID" --delay 70 "$@"; }
rep(){ local n=$1 d=$2 key=$3; while [ "$n" -gt 0 ]; do xdotool key --window "$WID" "$key"; sleep "$d"; n=$((n-1)); done; }

sleep 1.2
# --- bring the records box into view, then drill into the huge list ---
k Left; sleep .5; k Left; sleep .5; k Up; sleep 1.0
k Return; sleep 1.8
# --- goto deep into the array: records[99999] (instant with a prebuilt index) ---
k g; sleep .6; t 'records[99999]'; sleep .6; k Return; sleep 2.0
# --- expand-all: the whole 30-level nested spine of element 99999 ---
k e; sleep 2.2
# --- pan left back to the start (the element root) ---
rep 10 .16 Left; sleep 1.0
# --- zoom to 0.40x (three steps up from the expand-all fit) ---
k plus; sleep .5; k plus; sleep .5; k plus; sleep 1.0
# --- sweep right across the spine to the last (deepest) child ---
rep 80 .055 Right; sleep 1.6
# --- toggle the tree outline off and back on ---
k t; sleep 1.2; k t; sleep 1.2
# --- quit (canvas exits -> asciinema saves the cast -> xterm closes) ---
k q; sleep 1.0
for _ in $(seq 1 25); do xdotool search --name "^${TITLE}\$" >/dev/null 2>&1 || break; sleep 0.3; done

echo "wrote $CAST"
if command -v agg >/dev/null; then
  mkdir -p "$(dirname "$GIF")"
  agg --speed 1.5 --idle-time-limit 1.2 --theme monokai --font-size 16 "$CAST" "$GIF" && echo "wrote $GIF"
else
  echo "agg not found — render with: agg --speed 1.5 '$CAST' '$GIF'"
fi
