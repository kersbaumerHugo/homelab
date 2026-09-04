#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

ok() {
  printf 'OK   %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

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

printf '== Required documentation files ==\n'
for file in "${required_files[@]}"; do
  if [[ -s "$file" ]]; then
    ok "$file"
  else
    fail "$file is missing or empty"
  fi
done

printf '\n== Markdown relative links ==\n'
python3 - <<'PY' || exit_code=$?
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
            errors.append(f"{file.relative_to(root)} -> {target} escapes repository root")
            continue

        if not resolved.exists():
            errors.append(f"{file.relative_to(root)} -> {target}")

if errors:
    print("Broken relative Markdown links:")
    for err in errors:
        print(f"  - {err}")
    sys.exit(1)

print("All relative Markdown links resolve.")
PY
link_status=${exit_code:-0}
if (( link_status == 0 )); then
  ok "relative Markdown links"
else
  fail "relative Markdown links"
fi

printf '\n== ADR naming and headings ==\n'
python3 - <<'PY' || exit_code=$?
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
adr_status=${exit_code:-0}
if (( adr_status == 0 )); then
  ok "ADR naming and headings"
else
  fail "ADR naming and headings"
fi

printf '\n== Markdown files are non-empty ==\n'
empty_files=0
while IFS= read -r file; do
  if [[ ! -s "$file" ]]; then
    fail "$file is empty"
    empty_files=$((empty_files + 1))
  fi
done < <(find README.md CONTRIBUTING.md docs inventory -type f -name '*.md' -print 2>/dev/null | sort)

if (( empty_files == 0 )); then
  ok "all Markdown files are non-empty"
fi

printf '\n== Accidental Python bytecode ==\n'
if find . -type d -name '__pycache__' -o -type f -name '*.pyc' | grep -q .; then
  fail "Python bytecode/cache files exist in the working tree"
else
  ok "no Python bytecode/cache files found"
fi

printf '\n== Documentation validation result ==\n'
if (( failures > 0 )); then
  printf 'Documentation validation failed with %d issue(s).\n' "$failures" >&2
  exit 1
fi

printf 'Documentation validation successful.\n'
