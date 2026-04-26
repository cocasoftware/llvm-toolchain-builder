#!/usr/bin/env bash
# COCA Toolchain — Launcher that uses bundled Python
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLED_PY="$SCRIPT_DIR/tools/python/python3"

if [ -x "$BUNDLED_PY" ]; then
    exec "$BUNDLED_PY" "$SCRIPT_DIR/setup.py" "$@"
else
    echo "[WARN] Bundled Python not found, falling back to system python" >&2
    exec python3 "$SCRIPT_DIR/setup.py" "$@"
fi
