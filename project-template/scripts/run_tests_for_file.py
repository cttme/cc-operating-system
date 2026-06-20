"""Hook helper: called by the Write/Edit post-tool hooks to run the
pytest suite that covers a single edited Python file.

Finds a matching test file (same basename prefixed with test_, in tests/
or scrapers/tests/) and runs pytest on it. Exits 0 if no matching test
exists or tests pass; exits non-zero if tests fail.

Invocation: python scripts/run_tests_for_file.py <changed_file_path>
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def _locate_test(changed: Path) -> Path | None:
    repo = Path(__file__).resolve().parent.parent
    stem = changed.stem

    # The file itself may already be a test — just run it directly.
    if stem.startswith("test_") and changed.exists():
        return changed

    # Search known test roots
    candidates = [
        repo / "tests" / f"test_{stem}.py",
        repo / "scrapers" / "tests" / f"test_{stem}.py",
    ]
    for c in candidates:
        if c.exists():
            return c
    return None


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        return 0
    changed = Path(argv[1])
    if changed.suffix != ".py":
        return 0
    # If file doesn't exist, nothing to test.
    if not changed.exists():
        return 0
    test_file = _locate_test(changed)
    if test_file is None:
        return 0
    result = subprocess.run(
        ["python", "-m", "pytest", str(test_file), "-q", "--no-header", "-x"],
        capture_output=True,
        timeout=120,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stdout.decode(errors="replace"))
        sys.stderr.write(result.stderr.decode(errors="replace"))
    return result.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv))
