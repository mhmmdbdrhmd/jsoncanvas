#!/usr/bin/env bash
# Dev-loop harness: drive the REAL interactive canvas in an xterm and screenshot it.
#   loop.sh start [cols rows fontpt]   launch canvas in a titled xterm, save its window id
#   loop.sh key  KEY...                send real keystrokes (xdotool names) to that window
#   loop.sh type STRING                type literal text
#   loop.sh shot NAME                  capture the window to tools/shots/NAME.png
#   loop.sh stop                       close the xterm
# Uses a titled window (CANVASLOOP) so we can re-find it across separate invocations.
set -u
# project root = parent of this tools/ directory (resolved relative to this script,
# so the harness works from any clone location)
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TITLE="CANVASLOOP"
WIDF="/tmp/canvasloop.wid"
SHOTS="$REPO/tools/shots"
FILE="${CANVAS_FILE:-big.json}"

ERRLOG="/tmp/canvas.err"
find_wid() { xdotool search --name "^${TITLE}\$" 2>/dev/null | head -1; }
# re-resolve the live window every call; if canvas died, the window is gone and we
# fail loudly instead of capturing some other window.
live_wid() { local w; w=$(find_wid); [ -z "$w" ] && { echo "ERR: CANVASLOOP window gone (canvas exited). stderr:" >&2; tail -3 "$ERRLOG" >&2 2>/dev/null; return 1; }; printf '%s' "$w"; }

case "${1:-}" in
  start)
    cols="${2:-150}"; rows="${3:-44}"; fpt="${4:-7}"
    old=$(find_wid); [ -n "$old" ] && xdotool windowkill "$old" 2>/dev/null
    mkdir -p "$SHOTS"; : > "$ERRLOG"
    xterm -T "$TITLE" -geometry "${cols}x${rows}" \
          -fa 'DejaVu Sans Mono' -fs "$fpt" \
          -bg black -fg white \
          -xrm 'xterm*allowSendEvents:true' \
          -e bash -c "cd '$REPO' && exec env CANVAS_NOFONT=1 CANVAS_DEBUG='${CANVAS_DEBUG:-}' ./canvas '$FILE' 2>'$ERRLOG'" &
    # wait for the window to appear
    wid=""; for _ in $(seq 1 50); do wid=$(find_wid); [ -n "$wid" ] && break; sleep 0.1; done
    [ -z "$wid" ] && { echo "ERR: xterm window never appeared"; exit 1; }
    echo "$wid" > "$WIDF"
    sleep 1.2   # let canvas build its model + draw first frame
    xdotool windowactivate --sync "$wid" 2>/dev/null
    echo "started wid=$wid ${cols}x${rows} fpt=$fpt file=$FILE"
    ;;
  key)
    shift; wid=$(live_wid) || exit 1
    xdotool windowactivate --sync "$wid" 2>/dev/null
    for k in "$@"; do xdotool key --window "$wid" --clearmodifiers "$k"; sleep 0.12; done
    sleep 0.5
    echo "sent: $*"
    ;;
  type)
    shift; wid=$(live_wid) || exit 1
    xdotool windowactivate --sync "$wid" 2>/dev/null
    xdotool type --window "$wid" "$*"; sleep 0.4
    echo "typed: $*"
    ;;
  wheel)
    dir="${2:-down}"; n="${3:-3}"; wid=$(live_wid) || exit 1
    xdotool windowactivate --sync "$wid" 2>/dev/null
    xdotool windowraise "$wid" 2>/dev/null
    eval "$(xdotool getwindowgeometry --shell "$wid")"
    b=4; [ "$dir" = down ] && b=5
    xdotool mousemove --window "$wid" $(( WIDTH / 2 )) $(( HEIGHT / 2 ))
    for _ in $(seq 1 "$n"); do xdotool click --window "$wid" "$b"; sleep 0.06; done
    sleep 0.3; echo "wheel $dir x$n over wid=$wid (geom ${WIDTH}x${HEIGHT}+${X}+${Y})"
    ;;
  shot)
    name="${2:-shot}"; wid=$(live_wid) || exit 1
    xdotool windowactivate --sync "$wid" 2>/dev/null
    xdotool windowraise "$wid" 2>/dev/null
    sleep 0.3
    import -window "$wid" "$SHOTS/${name}.png" 2>/tmp/imp.err \
      && echo "shot -> $SHOTS/${name}.png $(identify -format '%wx%h' "$SHOTS/${name}.png" 2>/dev/null)" \
      || { echo "shot FAILED"; cat /tmp/imp.err; exit 1; }
    ;;
  stop)
    wid=$(cat "$WIDF" 2>/dev/null); [ -n "$wid" ] && xdotool windowkill "$wid" 2>/dev/null
    rm -f "$WIDF"; echo "stopped"
    ;;
  *) echo "usage: loop.sh {start|key|type|shot|stop}"; exit 1 ;;
esac