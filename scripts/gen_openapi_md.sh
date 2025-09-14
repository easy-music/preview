#!/usr/bin/env bash
set -euo pipefail

SPEC_DIR="specs/openapi"
OUT_DIR="docs/api"
TMP_DIR=".tmp_api_docs"
TEMPLATE="templates/api_doc_template.j2"

mkdir -p "$OUT_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# support .yaml and .yml
shopt -s nullglob
files=("$SPEC_DIR"/*.yaml "$SPEC_DIR"/*.yml)
shopt -u nullglob

if [ ${#files[@]} -eq 0 ]; then
  echo "No OpenAPI specs found in $SPEC_DIR — nothing to do."
  exit 0
fi

for f in "${files[@]}"; do
  echo "Processing spec: $f"
  base="$(basename "$f")"
  base_noext="${base%.*}"
  # service and version extraction: expects name like service.v1 or service.v1.2
  if [[ "$base_noext" =~ \.v ]]; then
    svc="${base_noext%%.v*}"
    ver="v${base_noext##*.v}"
  else
    svc="$base_noext"
    ver="v1"
  fi

  markdown="$TMP_DIR/${base_noext}.md"
  outdir="$OUT_DIR/$svc"
  mkdir -p "$outdir"
  outpath="$outdir/$ver.md"

  echo "  -> generating markdown with widdershins -> $markdown"
  widdershins "$f" -o "$markdown"

  echo "  -> wrapping with template -> $outpath"
  python3 - "$f" "$markdown" "$TEMPLATE" "$outpath" <<'PY'
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
base_noext = os.path.splitext(base)[0]
if '.v' in base_noext:
    service = base_noext.split('.v',1)[0]
    version = 'v' + base_noext.split('.v',1)[1]
else:
    service = base_noext
    version = 'v1'

# derive created_at deterministically from git last commit touching the spec
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
    'title': f"{service} API - {version}",
    'service': service,
    'version': version,
    'status': 'draft',
    'created_by': 'ci',
    'created_at': created_at_val,
    'changelog': '- auto-generated from OpenAPI'
}

out = tpl.render(frontmatter=fm, content=body)

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w', encoding='utf-8') as fh:
    fh.write(out)

print("Wrote", out_path)
PY

done

# cleanup
rm -rf "$TMP_DIR"
echo "Done. Generated docs in $OUT_DIR"
