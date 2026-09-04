#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
  "README.md"
  "CONTRIBUTING.md"
  "docs/README.md"
  "docs/documentation-status.md"
  "docs/architecture/README.md"
  "docs/architecture/overview.md"
  "docs/architecture/network.md"
  "docs/architecture/compute.md"
  "docs/architecture/storage.md"
  "docs/architecture/observability.md"
  "docs/architecture/backup-and-recovery.md"
  "docs/operations/README.md"
  "docs/operations/current-state.md"
  "docs/operations/reliability.md"
  "docs/operations/security.md"
  "docs/operations/known-risks.md"
  "docs/operations/roadmap.md"
  "docs/runbooks/README.md"
  "docs/runbooks/boot-and-shutdown.md"
  "docs/runbooks/monitoring-deploy.md"
  "docs/runbooks/monitoring-rollback.md"
  "docs/runbooks/mon01-backup-restore.md"
  "docs/runbooks/troubleshooting.md"
  "docs/runbooks/disaster-recovery.md"
  "docs/adr/README.md"
  "docs/adr/0001-disable-openipmi.md"
  "docs/adr/0002-git-as-source-of-truth.md"
  "docs/adr/0003-monitoring-in-mon01.md"
  "docs/adr/0004-observability-stack.md"
  "docs/adr/0005-local-backup-strategy.md"
  "docs/adr/0006-guest-startup-ordering.md"
  "docs/adr/0007-off-host-backup-deferred.md"
  "inventory/README.md"
  "inventory/opnsense.md"
  "inventory/pve01.md"
  "inventory/mon01.md"
)

usage() {
  cat <<'EOF'
Usage:
  ./scripts/validate-docs.sh [check ...]

Checks:
  structure  Required files and non-empty Markdown files
  links      Relative Markdown link validation
  adr        ADR filename/heading consistency
  hygiene    Accidental Python bytecode/cache detection
  all        Run all checks (default)

Examples:
  ./scripts/validate-docs.sh
  ./scripts/validate-docs.sh links
  ./scripts/validate-docs.sh structure adr
EOF
}

check_structure() {
  local failures=0

  echo "==> Checking required documentation files"

  for file in "${required_files[@]}"; do
    if [[ -s "$file" ]]; then
      printf 'OK   %s\n' "$file"
    else
      printf 'FAIL %s is missing or empty\n' "$file" >&2
      failures=$((failures + 1))
    fi
  done

  echo "==> Checking Markdown files are non-empty"

  while IFS= read -r file; do
    if [[ ! -s "$file" ]]; then
      printf 'FAIL %s is empty\n' "$file" >&2
      failures=$((failures + 1))
    fi
  done < <(
    find README.md CONTRIBUTING.md docs inventory \
      -type f \
      -name '*.md' \
      -print 2>/dev/null \
    | sort
  )

  if (( failures > 0 )); then
    echo "Documentation structure validation failed with $failures issue(s)." >&2
    return 1
  fi

  echo "PASS: documentation structure"
}

check_links() {
  echo "==> Checking Markdown relative links"

  python3 - <<'PY'
from pathlib import Path
import re
import sys

root = Path.cwd()
files = [root / "README.md", root / "CONTRIBUTING.md"]
files += sorted((root / "docs").rglob("*.md"))
files += sorted((root / "inventory").rglob("*.md"))

pattern = re.compile(r'!?\[[^\]]*\]\(([^)]+)\)')
errors = []

for file in files:
    text = file.read_text(encoding="utf-8")

    for target in pattern.findall(text):
        target = target.strip()

        if not target:
            continue

        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue

        path_part = target.split("#", 1)[0]

        if not path_part:
            continue

        resolved = (file.parent / path_part).resolve()

        try:
            resolved.relative_to(root.resolve())
        except ValueError:
            errors.append(
                f"{file.relative_to(root)} -> "
                f"{target} escapes repository root"
            )
            continue

        if not resolved.exists():
            errors.append(f"{file.relative_to(root)} -> {target}")

if errors:
    print("Broken relative Markdown links:")

    for error in errors:
        print(f"  - {error}")

    sys.exit(1)

print("All relative Markdown links resolve.")
PY

  echo "PASS: documentation links"
}

check_adr() {
  echo "==> Checking ADR naming and headings"

  python3 - <<'PY'
from pathlib import Path
import re
import sys

adr_dir = Path("docs/adr")
errors = []

for path in sorted(adr_dir.glob("[0-9][0-9][0-9][0-9]-*.md")):
    match = re.match(r"^(\d{4})-", path.name)

    if not match:
        errors.append(f"{path}: invalid ADR filename")
        continue

    number = match.group(1)
    first_line = path.read_text(encoding="utf-8").splitlines()[0].strip()

    if not re.match(rf"^# ADR {number}\b", first_line):
        errors.append(
            f"{path}: first heading should start with '# ADR {number}' "
            f"(found: {first_line!r})"
        )

if errors:
    for error in errors:
        print(error)

    sys.exit(1)

print("ADR filenames and headings are consistent.")
PY

  echo "PASS: ADR consistency"
}

check_hygiene() {
  echo "==> Checking accidental Python bytecode"

  if find . \
      \( -type d -name '__pycache__' -o -type f -name '*.pyc' \) \
      -print \
      | grep -q .; then
    echo "Python bytecode/cache files exist in the working tree" >&2
    return 1
  fi

  echo "PASS: repository hygiene"
}

run_check() {
  case "$1" in
    structure)
      check_structure
      ;;
    links)
      check_links
      ;;
    adr)
      check_adr
      ;;
    hygiene)
      check_hygiene
      ;;
    all)
      check_structure
      check_links
      check_adr
      check_hygiene
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "Unknown documentation check: $1" >&2
      usage >&2
      return 2
      ;;
  esac
}

if (($# == 0)); then
  set -- all
fi

for check in "$@"; do
  run_check "$check"
done

echo
echo "Documentation validation successful."
