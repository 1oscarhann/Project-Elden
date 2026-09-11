#!/usr/bin/env bash
# Runs the GUT suite headless. Set GODOT to your binary if it isn't on PATH.
set -euo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")"

"$GODOT" --headless --path . --import >/dev/null
exec "$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit
