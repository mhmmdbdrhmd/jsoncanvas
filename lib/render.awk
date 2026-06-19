# render.awk — compose ONE character-cell framebuffer for the node-link canvas.
#
# It is the "GPU": bash hands it the camera + the small set of nodes/edges that
# might be on screen, and awk rasterizes them into a grid of terminal cells in a
# single pass. Cost is bounded by what's on screen, never by file size.
#
# Input lines, fields separated by \x1f (unit separator):
#   C  camX camY zoom cols rows
#   N  wx wy ww wh depth nrows row0 row1 ...           small content box
#   B  wx wy ww wh depth winStart nrows row0 row1 ...  WINDOWED box (huge list):
#        box reserves full world height wh; only rows winStart..winStart+nrows-1
#        are supplied, drawn at world-y = wy+1+winStart+k (virtualized list).
#   E  x1 y1 x2 y2                                      edge, parent handle->child
#
# Each rowK: first char is a flag ('0' field, '1' handle), rest is display text.
# Handle rows get a ● on the right border; the matching edge ends in a ▶ arrow.
#
# World coords are "cells at zoom 1": screen = round((world - cam) * zoom).
# Semantic-zoom LOD per node from PROJECTED width:
#   pw<4 -> single block (minimap)   pw<6||ph<3 -> filled bar   else box+text

BEGIN {
  SEP = sprintf("%c", 31); FS = SEP
  ESC = sprintf("%c", 27)
  COLS = 80; ROWS = 24; camX = 0; camY = 0; zoom = 1
  PN = split("39 45 51 48 84 154 220 214 208 205 171 99", PAL, " ")
  EDGECOL = 250; ARROWCOL = 45; HANDLECOL = 45; TEXTCOL = 253; FOCUSCOL = 226
  DASH="\xe2\x94\x80"; PIPE="\xe2\x94\x82"
  TL="\xe2\x94\x8c"; TR="\xe2\x94\x90"; BL="\xe2\x94\x94"; BR="\xe2\x94\x98"
  ARR_R="\xe2\x96\xb6"; ARR_L="\xe2\x97\x80"; DOT="\xe2\x97\x8f"
  BLK="\xe2\x96\x88"; SHD="\xe2\x96\x93"
  nN = 0; nE = 0; nB = 0; nP = 0
  PANELW = 0      # width of the left tree panel (0 = none); divider sits at col PANELW
  XCLIP = 0       # canvas draws only at x >= XCLIP (kept clear of the panel)
}

function rnd(x) { return (x >= 0) ? int(x + 0.5) : -int(-x + 0.5) }
# canvas cell write — clipped to the canvas region [XCLIP, COLS)
function setcell(x, y, c, col) {
  if (x < XCLIP || x >= COLS || y < 0 || y >= ROWS) return
  ch[y, x] = c; cl[y, x] = col
}
# panel cell write — bypasses XCLIP so it can paint the left region
function panelcell(x, y, c, col) {
  if (x < 0 || x >= COLS || y < 0 || y >= ROWS) return
  ch[y, x] = c; cl[y, x] = col
}
function paneltext(x0, y, txt, w, col,   c2) {
  for (c2 = 0; c2 < length(txt) && c2 < w; c2++) panelcell(x0 + c2, y, substr(txt, c2 + 1, 1), col)
}
# clamped span drawers (loop bounds are clipped to the screen so a box that is
# millions of world-rows tall only ever iterates over visible cells)
function hline(y, xa, xb, c, col,   x) {
  if (y < 0 || y >= ROWS) return
  if (xa > xb) { x = xa; xa = xb; xb = x }
  if (xa < XCLIP) xa = XCLIP; if (xb > COLS - 1) xb = COLS - 1
  for (x = xa; x <= xb; x++) { ch[y, x] = c; cl[y, x] = col }
}
function vline(x, ya, yb, c, col,   y) {
  if (x < XCLIP || x >= COLS) return
  if (ya > yb) { y = ya; ya = yb; yb = y }
  if (ya < 0) ya = 0; if (yb > ROWS - 1) yb = ROWS - 1
  for (y = ya; y <= yb; y++) { ch[y, x] = c; cl[y, x] = col }
}
function fillrect(x0, y0, x1, y1, c, col,   xx, yy) {
  if (x0 < XCLIP) x0 = XCLIP; if (y0 < 0) y0 = 0
  if (x1 > COLS - 1) x1 = COLS - 1; if (y1 > ROWS - 1) y1 = ROWS - 1
  for (yy = y0; yy <= y1; yy++) for (xx = x0; xx <= x1; xx++) { ch[yy, xx] = c; cl[yy, xx] = col }
}
function puttext(x0, ty, txt, inw, tcol,   c2) {
  if (tcol == "") tcol = TEXTCOL
  if (length(txt) > inw) txt = substr(txt, 1, inw)
  for (c2 = 1; c2 <= length(txt); c2++) setcell(x0 + c2, ty, substr(txt, c2, 1), tcol)
}

{
  if ($1 == "C") { camX=$2+0; camY=$3+0; zoom=$4+0; COLS=$5+0; ROWS=$6+0; PANELW=$7+0; next }
  if ($1 == "P") { nP++; Prow[nP]=$2+0; Pstyle[nP]=$3+0; Ptext[nP]=$4; next }
  if ($1 == "N") {
    nN++; Nwx[nN]=$2+0; Nwy[nN]=$3+0; Nww[nN]=$4+0; Nwh[nN]=$5+0
    Ndepth[nN]=$6+0; Nnr[nN]=$7+0
    for (k = 0; k < Nnr[nN]; k++) Nrow[nN, k] = $(8 + k)
    next
  }
  if ($1 == "B") {
    nB++; Bwx[nB]=$2+0; Bwy[nB]=$3+0; Bww[nB]=$4+0; Bwh[nB]=$5+0
    Bdep[nB]=$6+0; Bws[nB]=$7+0; Bfocus[nB]=$8+0; Bnr[nB]=$9+0
    for (k = 0; k < Bnr[nB]; k++) Brow[nB, k] = $(10 + k)
    next
  }
  if ($1 == "E") { nE++; Ex1[nE]=$2+0; Ey1[nE]=$3+0; Ex2[nE]=$4+0; Ey2[nE]=$5+0; Ebx[nE]=$6+0; next }
}

END {
  XCLIP = (PANELW > 0) ? PANELW + 1 : 0    # keep the canvas right of the panel divider

  # ---- edges first, so boxes paint over them ----
  for (e = 1; e <= nE; e++) {
    x1 = rnd((Ex1[e]-camX)*zoom); y1 = rnd((Ey1[e]-camY)*zoom)
    x2 = rnd((Ex2[e]-camX)*zoom); y2 = rnd((Ey2[e]-camY)*zoom)
    if ((x1 < 0 && x2 < 0) || (x1 >= COLS && x2 >= COLS)) continue
    if ((y1 < 0 && y2 < 0) || (y1 >= ROWS && y2 >= ROWS)) continue
    mx = rnd((Ebx[e] - camX) * zoom)           # per-edge vertical channel (staggered)
    if (mx <= x1) mx = x1 + 1
    if (mx >= x2) mx = x2 - 1
    if (mx <= x1) mx = x1 + 1
    hline(y1, x1, mx, DASH, EDGECOL)
    vline(mx, y1, y2, PIPE, EDGECOL)
    hline(y2, mx, x2, DASH, EDGECOL)
    if (y2 > y1)      { setcell(mx, y1, TR, EDGECOL); setcell(mx, y2, BL, EDGECOL) }
    else if (y2 < y1) { setcell(mx, y1, BR, EDGECOL); setcell(mx, y2, TL, EDGECOL) }
    ax = (x2 >= mx) ? x2 - 1 : x2 + 1
    setcell(ax, y2, (x2 >= mx ? ARR_R : ARR_L), ARROWCOL)
  }

  # ---- small content boxes ----
  for (n = 1; n <= nN; n++) {
    col = PAL[(Ndepth[n] % PN) + 1]
    pw = rnd(Nww[n]*zoom); ph = rnd(Nwh[n]*zoom)
    if (pw < 1) pw = 1; if (ph < 1) ph = 1
    x0 = rnd((Nwx[n]-camX)*zoom); y0 = rnd((Nwy[n]-camY)*zoom)
    x1 = x0 + pw - 1; y1 = y0 + ph - 1
    if (x1 < 0 || x0 >= COLS || y1 < 0 || y0 >= ROWS) continue
    # sub-text LOD: fill the projected rect (not a single corner pixel) so the box
    # is visible AND edges that target its centre always land inside it.
    if (pw < 4 || ph < 2) { fillrect(x0, y0, x1, y1, BLK, col); continue }
    if (pw < 6 || ph < 3) { fillrect(x0, y0, x1, y1, SHD, col); continue }
    setcell(x0, y0, TL, col); setcell(x1, y0, TR, col)
    setcell(x0, y1, BL, col); setcell(x1, y1, BR, col)
    hline(y0, x0+1, x1-1, DASH, col); hline(y1, x0+1, x1-1, DASH, col)
    vline(x0, y0+1, y1-1, PIPE, col); vline(x1, y0+1, y1-1, PIPE, col)
    inw = x1 - x0 - 1; capr = y1 - y0 - 1
    show = (Nnr[n] < capr) ? Nnr[n] : capr
    for (k = 0; k < show; k++) {
      row = Nrow[n, k]; flag = substr(row, 1, 1); txt = substr(row, 2)
      if (k == show - 1 && show < Nnr[n]) txt = "\xe2\x80\xa6 more"
      puttext(x0, y0 + 1 + k, txt, inw)
      if (flag == "1") setcell(x1, y0 + 1 + k, DOT, HANDLECOL)
    }
  }

  # ---- windowed (virtualized) boxes ----
  for (b = 1; b <= nB; b++) {
    col = PAL[(Bdep[b] % PN) + 1]
    pw = rnd(Bww[b]*zoom); ph = rnd(Bwh[b]*zoom)
    if (pw < 1) pw = 1; if (ph < 1) ph = 1
    x0 = rnd((Bwx[b]-camX)*zoom); y0 = rnd((Bwy[b]-camY)*zoom)
    x1 = x0 + pw - 1; y1 = y0 + ph - 1
    if (x1 < 0 || x0 >= COLS) continue
    if (y1 < 0 || y0 >= ROWS) continue
    if (pw < 6) { fillrect(x0, y0, x1, y1, SHD, col); continue }
    setcell(x0, y0, TL, col); setcell(x1, y0, TR, col)
    setcell(x0, y1, BL, col); setcell(x1, y1, BR, col)
    hline(y0, x0+1, x1-1, DASH, col); hline(y1, x0+1, x1-1, DASH, col)
    vline(x0, y0+1, y1-1, PIPE, col); vline(x1, y0+1, y1-1, PIPE, col)
    inw = x1 - x0 - 1
    for (k = 0; k < Bnr[b]; k++) {
      ry = rnd((Bwy[b] + 1 + Bws[b] + k - camY) * zoom)
      if (ry <= y0 || ry >= y1) continue
      row = Brow[b, k]; flag = substr(row, 1, 1); txt = substr(row, 2)
      foc = (Bws[b] + k == Bfocus[b])
      puttext(x0, ry, txt, inw, (foc ? FOCUSCOL : TEXTCOL))
      if (foc) setcell(x0, ry, ARR_R, FOCUSCOL)
      if (flag == "1") setcell(x1, ry, DOT, HANDLECOL)
    }
  }

  # ---- tree side panel (fixed, camera-independent) drawn on top, left of divider ----
  if (PANELW > 0) {
    for (r = 0; r < ROWS; r++) { ch[r, PANELW] = PIPE; cl[r, PANELW] = EDGECOL }
    for (p = 1; p <= nP; p++) {
      pcol = (Pstyle[p] == 1) ? FOCUSCOL : (Pstyle[p] == 2) ? 45 : (Pstyle[p] == 3) ? 220 : 250
      paneltext(0, Prow[p], Ptext[p], PANELW, pcol)
    }
  }

  # ---- emit ----
  out = ""
  for (r = 0; r < ROWS; r++) {
    cur = -1; line = ""
    for (c = 0; c < COLS; c++) {
      g = ((r, c) in ch) ? ch[r, c] : " "
      k = ((r, c) in cl) ? cl[r, c] : 0
      if (g == " ") k = 0
      if (k != cur) { line = line (k == 0 ? ESC "[0m" : ESC "[38;5;" k "m"); cur = k }
      line = line g
    }
    out = out line ESC "[0m"
    if (r < ROWS - 1) out = out "\n"
  }
  printf "%s", out
}
