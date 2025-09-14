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
  svc="$base"
  svc="${svc%_service}"
  ver="v1"
  outdir="$OUT_DIR/$svc"
  mkdir -p "$outdir"
  outpath="$outdir/$ver.md"

  echo "  -> protoc generating markdown into $TMP_DIR"
  protoc --doc_out="$TMP_DIR" --doc_opt=markdown,"${base}.md" -I"$SPEC_DIR" "$f"

  tmp_md="$TMP_DIR/${base}.md"
  if [ ! -f "$tmp_md" ]; then
    echo "Error: expected protoc output $tmp_md not found"
    exit 1
  fi

  echo "  -> wrapping with template -> $outpath"
  python3 - "$f" "$tmp_md" "$TEMPLATE" "$outpath" <<'PY'
import sys, os, datetime, subprocess
try:
    import jinja2
except Exception:
    print("Missing dependency jinja2. Please pip install jinja2", file=sys.stderr)
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

# created_at from git last commit touching the proto
def last_commit_time(path):
    try:
        out = subprocess.check_output(['git','log','-1','--format=%cI','--', path], stderr=subprocess.DEVNULL)
        s = out.decode().strip()
        if s:
            return s
    except Exception:
        pass
    try:
        ts = os.path.getmtime(path)
        return datetime.datetime.utcfromtimestamp(ts).isoformat() + 'Z'
    except Exception:
        return datetime.datetime.utcnow().isoformat() + 'Z'

created_at_val = last_commit_time(spec_path)

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
    'created_at': created_at_val,
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
