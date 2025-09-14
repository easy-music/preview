#!/usr/bin/env bash
[ -e "$f" ] || continue
base=$(basename "$f" .yaml)
svc=$(echo "$base" | sed -E 's/(.*)\.v.*/\1/')
ver=$(echo "$base" | sed -E 's/.*\.v(.*)/v\1/')


# convert OpenAPI -> markdown via widdershins
markdown="$TMP_DIR/${base}.md"
echo "Generating $markdown from $f"
widdershins "$f" -o "$markdown"


# post-process: inject front-matter via jinja2 (python script)
outdir="$OUT_DIR/$svc"
mkdir -p "$outdir"
outpath="$outdir/$ver.md"


python3 - <<PY
import sys, json, os, datetime, jinja2
spec_path = "$f"
md_path = "$markdown"
template_path = "$TEMPLATE"
out_path = "$outpath"


# Load minimal metadata from filename (you can extend to parse OpenAPI.info)
base = os.path.basename(spec_path).replace('.yaml','')
service = base.split('.',1)[0]
version = 'v' + base.split('.v')[-1]


with open(md_path,'r',encoding='utf-8') as fh:
body = fh.read()


with open(template_path,'r',encoding='utf-8') as fh:
tpl = jinja2.Template(fh.read())


fm = {
'title': f"{service} API - {version}",
'service': service,
'version': version,
'status': 'draft',
'created_by': 'ci',
'created_at': datetime.datetime.utcnow().isoformat()+'Z',
'changelog': '- auto-generated from OpenAPI'
}


out = tpl.render(frontmatter=fm, content=body)
with open(out_path,'w',encoding='utf-8') as fh:
fh.write(out)
print('Wrote', out_path)
PY


done


# cleanup
rm -rf "$TMP_DIR"


echo "Done. Generated docs in $OUT_DIR"