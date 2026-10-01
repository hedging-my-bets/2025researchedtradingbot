from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", ".venv", "venv", "__pycache__", "node_modules"}
SKIP_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".h5", ".onnx", ".ex5", ".zip", ".pdf", ".csv"}
SELF = Path(__file__).resolve()

PATTERNS = [
    re.compile(r"""(?i)\b(api[_-]?key|access[_-]?token|auth[_-]?token|secret)\s*=\s*["'][A-Za-z0-9_\-]{16,}["']"""),
    re.compile(r"""(?i)\b(bearer)\s+[A-Za-z0-9_\-.]{24,}"""),
]

def iter_text_files(root: Path):
    for path in root.rglob("*"):
        if not path.is_file() or path.resolve() == SELF:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix.lower() in SKIP_SUFFIXES:
            continue
        if path.stat().st_size > 1_000_000:
            continue
        yield path

def main() -> int:
    hits = []
    for path in iter_text_files(ROOT):
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for line_no, line in enumerate(text.splitlines(), start=1):
            if any(p.search(line) for p in PATTERNS):
                hits.append((path.relative_to(ROOT), line_no))
    if hits:
        for path, line_no in hits:
            print(f"potential credential: {path}:{line_no}")
        return 1
    print("OK: no obvious hard-coded credentials found in text sources.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
