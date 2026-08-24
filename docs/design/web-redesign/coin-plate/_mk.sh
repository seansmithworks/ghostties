#!/bin/bash
# mk <file> <tag> <name> <defs-file> <layer-file> <tech> <cost> <risk> <note>
mk () {
  local out=$1 tag=$2 name=$3 defs=$4 layer=$5 tech=$6 cost=$7 risk=$8 note=$9
  { 
    printf '%s\n' '<!doctype html>' '<html>' '<head>' '  <meta charset="utf-8">' '  <script src="./support.js"></script>' '</head>' '<body>' '<x-dc>' '<helmet>'
    printf '%s\n' '  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wght@400;500;600;800;900&family=DM+Mono:wght@300;400;500&display=swap">'
    printf '%s\n' '  <style>'
    cat _plate.css
    [ -s "$defs" ] && cat "$defs"
    printf '%s\n' '  </style>' '</helmet>' '<div class="wrap">'
    printf '  <div class="hd"><div class="tag">%s</div><div class="nm">%s</div></div>\n' "$tag" "$name"
    printf '%s\n' '  <div class="stagebox"><div class="plate">'
    cat _plate.html
    [ -s "$layer" ] && cat "$layer"
    printf '%s\n' '  </div></div>'
    printf '%s\n' '  <div class="meta">'
    printf '    <div class="row"><span class="k">HOW</span><span class="v">%s</span></div>\n' "$tech"
    printf '    <div class="row"><span class="k">COST</span><span class="v">%s</span></div>\n' "$cost"
    printf '    <div class="row"><span class="k">RISK</span><span class="v">%s</span></div>\n' "$risk"
    printf '    <div class="row"><span class="k">VERDICT</span><span class="v">%s</span></div>\n' "$note"
    printf '%s\n' '  </div>' '</div>' '</x-dc>' '</body>' '</html>'
  } > "$out"
  echo "wrote $out $(wc -c < "$out")"
}
