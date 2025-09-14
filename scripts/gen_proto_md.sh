#!/usr/bin/env bash
set -euo pipefail


SPEC_DIR="specs/proto"
OUT_DIR="docs/api"
TEMPLATE="templates/api_doc_template.j2"


mkdir -p "$OUT_DIR"


for f in "$SPEC_DIR"/*.proto; do
[ -e "$f" ] || continue
base=$(basename "$f" .proto)
svc=$(echo "$base" | sed -E 's/(.*)_service.*/\1/')
ver="v1"
outdir="$OUT_DIR/$svc" && mkdir -p "$outdir"
outpath="$outdir/$ver.md"


# protoc-gen-doc (https://github.com/pseudomuto/protoc-gen-doc) -> markdown
protoc --doc_out=./ --doc_opt=markdown,"${base}.md" -I."$SPEC_DIR" "$f"


# wrap with template
python3 - <<PY
import sys, os, datetime, jinja2
mdfile = "${base}.md"
with open(mdfile,'r',encoding='utf-8') as fh:
body = fh.read()


with open("${TEMPLATE}",'r',encoding='utf-8') as fh:
tpl = jinja2.Template(fh.read())


fm = {
'title': f"{svc} gRPC API - {ver}",
'service': svc,
'version': ver,
'status': 'draft',
'created_by': 'ci',
'created_at': datetime.datetime.utcnow().isoformat()+'Z',
'changelog': '- auto-generated from proto'
}
out = tpl.render(frontmatter=fm, content=body)
with open("${outpath}",'w',encoding='utf-8') as fh:
fh.write(out)
print('Wrote', "${outpath}")


# cleanup temporary file
os.remove(mdfile)
PY


done


echo "Done proto -> md"