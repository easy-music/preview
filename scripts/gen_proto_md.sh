#!/usr/bin/env bash
set -euo pipefail

SPEC_DIR="specs/proto"
OUT_DIR="docs/api"
TMP_DIR=".tmp_proto_docs"
TEMPLATE="templates/api_doc_template.j2"

mkdir -p "$OUT_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

shopt -s nullglob
files=("$SPEC_DIR"/*.proto)
shopt -u nullglob

if [ ${#files[@]} -eq 0 ]; then
  echo "No proto files found in $SPEC_DIR — nothing to do."
  exit 0
fi

for f in "${files[@]}"; do
  echo "Processing proto: $f"
  base="$(basename "$f" .proto)"
  # derive service name (convention: <service>_service.proto or <service>.proto)
  svc="$base"
  svc="${svc%_service}"   # remove trailing _service if present
  ver="v1"
  outdir="$OUT_DIR/$svc"
  mkdir -p "$outdir"
  outpath="$outdir/$ver.md"

  # generate markdown into TMP_DIR using protoc-gen-doc
  echo "  -> protoc generating markdown into $TMP_DIR"
  protoc --doc_out="$TMP_DIR" --doc_opt=markdown,"${base}.md" -I"$SPEC_DIR" "$f"

  tmp_md="$TMP_DIR/${base}.md"
  if [ ! -f "$tmp_md" ]; then
    echo "Error: expected protoc output $tmp_md not found"
    exit 1
  fi

  echo "  -> wrapping with template -> $outpath"
  python3 - "$f" "$tmp_md" "$TEMPLATE" "$outpath" <<'PY'
import sys, os, datetime
try:
    import jinja2
except Exception as e:
    sys.stderr.write("Missing Python dependency jinja2: pip install jinja2\n")
    raise

spec_path = sys.argv[1]
md_path = sys.argv[2]
template_path = sys.argv[3]
out_path = sys.argv[4]

base = os.path.basename(spec_path)
service = os.path.splitext(base)[0]
if service.endswith('_service'):
    service = service[:-8]
version = 'v1'

with open(md_path, 'r', encoding='utf-8') as fh:
    body = fh.read()

with open(template_path, 'r', encoding='utf-8') as fh:
    tpl = jinja2.Template(fh.read())

fm = {
    'title': f"{service} gRPC API - {version}",
    'service': service,
    'version': version,
    'status': 'draft',
    'created_by': 'ci',
    'created_at': datetime.datetime.utcnow().isoformat() + 'Z',
    'changelog': '- auto-generated from proto'
}

out = tpl.render(frontmatter=fm, content=body)

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w', encoding='utf-8') as fh:
    fh.write(out)

print("Wrote", out_path)
PY

  # cleanup tmp file for this proto
  rm -f "$tmp_md"
done

rm -rf "$TMP_DIR"
echo "Done proto -> md"
