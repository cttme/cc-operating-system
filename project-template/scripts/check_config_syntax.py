#!/usr/bin/env python
"""Config syntax check — PostToolUse hook.

After an Edit/Write, take the file path; if it's JSON/YAML/TOML, validate
its syntax. Failures go to stderr (non-blocking; visibility only).

Invocation: stdin receives a tool_input JSON (Claude Code hook protocol).
"""
from __future__ import annotations

import json
import os
import sys


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0  # if the input cannot be parsed, silently pass

    path = data.get("tool_input", {}).get("file_path", "") or data.get("tool_input", {}).get("path", "")
    if not path or not os.path.exists(path):
        return 0

    ext = os.path.splitext(path)[1].lower()

    if ext == ".json":
        try:
            with open(path, encoding="utf-8") as f:
                json.load(f)
        except Exception as e:
            print(f"CONFIG SYNTAX [JSON] ERROR: {path}: {e}", file=sys.stderr)
            return 0  # non-blocking, warning only

    elif ext in (".yaml", ".yml"):
        try:
            import yaml

            with open(path, encoding="utf-8") as f:
                yaml.safe_load(f)
        except ImportError:
            return 0  # pyyaml not installed, skip
        except Exception as e:
            print(f"CONFIG SYNTAX [YAML] ERROR: {path}: {e}", file=sys.stderr)
            return 0

    elif ext == ".toml":
        try:
            import tomllib

            with open(path, "rb") as f:
                tomllib.load(f)
        except Exception as e:
            print(f"CONFIG SYNTAX [TOML] ERROR: {path}: {e}", file=sys.stderr)
            return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
