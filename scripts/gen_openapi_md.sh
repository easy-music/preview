#!/usr/bin/env bash
set -euo pipefail

SPEC_DIR="specs/openapi"
OUT_DIR="docs/api"
TMP_DIR=".tmp_api_docs"
TEMPLATE="templates/api_doc_template.j2"

mkdir -p "$OUT_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# collect files (supports .yaml and .yml). nullglob prevents literal pattern when no files.
shopt -s nullglob
files=("$SPEC_DIR"/*.yaml "$SPEC_DIR"/*.yml)
shopt -u nullglob

if [ ${#files[@]} -eq 0 ]; then
  echo "No OpenAPI specs found in $SPEC_DIR — nothing to do."
  exit 0
fi

for f in "${files[@]}"; do
  echo "Processing spec: $f"
  # basename without extension (.yaml or .yml)
  base="$(basename "$f")"
  base="${base%.*}"   # strips last extension
  # expected name format: <service>.v<major>[...], e.g. tracks-service.v1
  svc="${base%%.v*}"
  # if basename didn't contain .v, fall back to full name as service and v1 as version
  if [[ "$base" == "$svc" ]]; then
    ver="v1"
  else
    ver="v${base##*.v}"
  fi

  markdown="$TMP_DIR/${base}.md"
  outdir="$OUT_DIR/$svc"
  mkdir -p "$outdir"
  outpath="$outdir/$ver.md"

  echo "  -> generating markdown with widdershins -> $markdown"
  widdershins "$f" -o "$markdown"

  echo "  -> wrapping with template -> $outpath"
  python3 - "$f" "$markdown" "$TEMPLATE" "$outpath" <<'PY'
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

# derive service/version from spec filename if possible
base = os.path.basename(spec_path)
base_noext = os.path.splitext(base)[0]
service = base_noext.split('.v',1)[0]
if '.v' in base_noext:
    version = 'v' + base_noext.split('.v',1)[1]
else:
    version = 'v1'

with open(md_path, 'r', encoding='utf-8') as fh:
    body = fh.read()

with open(template_path, 'r', encoding='utf-8') as fh:
    tpl = jinja2.Template(fh.read())

fm = {
    'title': f"{service} API - {version}",
    'service': service,
    'version': version,
    'status': 'draft',
    'created_by': 'ci',
    'created_at': datetime.datetime.utcnow().isoformat() + 'Z',
    'changelog': '- auto-generated from OpenAPI'
}

out = tpl.render(frontmatter=fm, content=body)

# ensure output dir exists
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w', encoding='utf-8') as fh:
    fh.write(out)

print("Wrote", out_path)
PY

done

# cleanup
rm -rf "$TMP_DIR"
echo "Done. Generated docs in $OUT_DIR"
