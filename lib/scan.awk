# scan.awk — emit the DIRECT children of a JSON container, reading only the
# small slice handed to it on stdin (the whole slice is one record, RS=NUL).
#
# Modes:
#   default      : slice begins at (or before) the container's opening { or [.
#   -v cont=1     : slice begins partway through a container, just after a child
#                   or comma; -v isobj=1/0 says whether the container is object.
# Other vars:
#   -v maxitems=N : stop after N children (0 = unlimited).
#
# Fields are separated by \x1f (unit separator), which never appears in text
# JSON and, being non-whitespace, survives `IFS read` without empty-field
# collapsing. One line per child:
#   type  key  eoff  valoff  vallen  partial  preview
#     type    = object | array | string | scalar
#     key     = object member name (empty for arrays)
#     eoff    = 0-based offset of the ELEMENT start (key for objects, value for
#               arrays), RELATIVE to slice start. Use this to resume scanning.
#     valoff  = 0-based offset of the VALUE, RELATIVE to slice start. Use this
#               to descend into the child.
#     vallen  = byte length of the value
#     partial = 1 if the value's container did not close inside the slice
#     preview = first 40 bytes of the value
# Plus one final marker line:
#   @  resume  closed
#     resume  = 0-based offset to start the next slice (RELATIVE to this slice)
#     closed  = 1 if the container's own closing bracket was reached (no more)

BEGIN {
  RS = "\0"
  SEP = sprintf("%c", 31)        # \x1f field separator
  OFS = SEP
  if (maxitems == "") maxitems = 0
  if (cont == "") cont = 0
  if (isobj == "") isobj = 0
}

function isws(ch) { return (ch == " " || ch == "\t" || ch == "\r" || ch == "\n") }

{
  s = $0; L = length(s); i = 1

  if (!cont) {
    while (i <= L && isws(substr(s, i, 1))) i++
    open = substr(s, i, 1)
    if (open != "{" && open != "[") { print "@", 0, 0; exit }
    isobj = (open == "{"); i++
  }

  cnt = 0; closed = 0
  while (i <= L) {
    while (i <= L) { c = substr(s, i, 1); if (isws(c) || c == ",") i++; else break }
    if (i > L) break
    c = substr(s, i, 1)
    if (c == "}" || c == "]") { closed = 1; break }

    estart = i
    keytext = ""
    if (isobj) {
      if (c != "\"") break
      ks = i + 1; j = ks
      while (j <= L) { d = substr(s, j, 1); if (d == "\\") j += 2; else if (d == "\"") break; else j++ }
      keytext = substr(s, ks, j - ks)
      i = j + 1
      while (i <= L) { d = substr(s, i, 1); if (isws(d) || d == ":") i++; else break }
    }

    vs = i; vc = substr(s, i, 1); type = ""; partial = 0
    if (vc == "\"") {
      type = "string"; j = i + 1
      while (j <= L) { d = substr(s, j, 1); if (d == "\\") j += 2; else if (d == "\"") break; else j++ }
      ve = j; i = j + 1
    } else if (vc == "{" || vc == "[") {
      type = (vc == "{") ? "object" : "array"
      depth = 1; j = i + 1; instr = 0
      while (j <= L && depth > 0) {
        d = substr(s, j, 1)
        if (instr) { if (d == "\\") j += 2; else { if (d == "\"") instr = 0; j++ } }
        else if (d == "\"") { instr = 1; j++ }
        else if (d == "{" || d == "[") { depth++; j++ }
        else if (d == "}" || d == "]") { depth--; j++ }
        else j++
      }
      ve = j - 1; i = j
      if (depth > 0) partial = 1
    } else {
      type = "scalar"; j = i
      while (j <= L) { d = substr(s, j, 1); if (d == "," || d == "}" || d == "]" || isws(d)) break; j++ }
      ve = j - 1; i = j
    }

    vallen = ve - vs + 1; valoff = vs - 1
    plen = (vallen > 40) ? 40 : vallen
    prev = substr(s, vs, plen)
    gsub(/[\t\r\n]/, " ", prev);    gsub(SEP, " ", prev)
    gsub(/[\t\r\n]/, " ", keytext); gsub(SEP, " ", keytext)
    print type, keytext, estart - 1, valoff, vallen, partial, prev

    cnt++
    if (maxitems > 0 && cnt >= maxitems) break
  }

  print "@", (i - 1 < 0 ? 0 : i - 1), closed
}
