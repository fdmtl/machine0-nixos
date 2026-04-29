#
# mkMotd — build a styled login banner.
#
# { title, body ? [], docsUrl ? null, width ? null } → string
#
#   title   — bold white header text
#   body    — list of strings; "" = blank separator, "$ cmd" = styled command
#   docsUrl — underlined OSC 8 clickable hyperlink, prefixed with "Docs: "
#   width   — box interior columns; null = auto (longest visible line + 6)
#
{ title, body ? [], docsUrl ? null, width ? null }:
let
  # ── ANSI escape sequences ──────────────────────────────
  esc = builtins.fromJSON ''"\u001b"'';
  bel = builtins.fromJSON ''"\u0007"'';
  dc  = "${esc}[2;36m";    # dim cyan — borders
  bw  = "${esc}[1;97m";    # bold white — title
  bc  = "${esc}[1;36m";    # bold cyan — commands
  b   = "${esc}[1m";       # bold — dollar sign
  ul  = "${esc}[4m";       # underline — links
  r   = "${esc}[0m";       # reset
  osc = "${esc}]8;;";      # OSC 8 hyperlink opener

  # ── Helpers ────────────────────────────────────────────
  repeat = c: n:
    builtins.concatStringsSep "" (builtins.genList (_: c) n);
  spaces = repeat " ";

  # Visual width — replace known multi-byte chars with single-byte stand-ins
  # so builtins.stringLength returns the column count.
  visWidth = s: builtins.stringLength (
    builtins.replaceStrings [ "—" "·" "☤" ] [ "-" "." "X" ] s
  );

  # Process one body line into a { plain; styled; } pair.
  processLine = line:
    if line == "" then
      { plain = ""; styled = ""; }
    else if builtins.substring 0 2 line == "$ " then
      let cmd = builtins.substring 2 (builtins.stringLength line - 2) line;
      in { plain = line; styled = b + "$" + r + " " + bc + cmd + r; }
    else
      { plain = line; styled = line; };

  # ── Content entries ────────────────────────────────────
  blank = { plain = ""; styled = ""; };

  titleEntry = { plain = title; styled = "${bw}${title}${r}"; };

  bodyEntries = map processLine body;

  docsEntry = {
    plain  = "Docs: ${docsUrl}";
    styled = "Docs: ${osc}${docsUrl}${bel}${ul}${docsUrl}${r}${osc}${bel}";
  };

  contentBelow = bodyEntries
    ++ (if docsUrl != null then [ docsEntry ] else []);

  allEntries = [ blank titleEntry ]
    ++ (if contentBelow != [] then [ blank ] ++ contentBelow else [])
    ++ [ blank ];

  # ── Width calculation ──────────────────────────────────
  pad = 3;
  maxVis = builtins.foldl'
    (acc: e: let w = visWidth e.plain; in if w > acc then w else acc)
    0
    allEntries;
  w = if width != null then width else maxVis + pad + pad;

  # ── Rendering ──────────────────────────────────────────
  renderRow = entry:
    let rp = spaces (w - pad - visWidth entry.plain);
    in "    ${dc}│${r}${spaces pad}${entry.styled}${rp}${dc}│${r}";

  top = "    ${dc}╭${repeat "─" w}╮${r}";
  bot = "    ${dc}╰${repeat "─" w}╯${r}";

  rows = map renderRow allEntries;
in
builtins.concatStringsSep "\n" ([ "" top ] ++ rows ++ [ bot "" ""])
