# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Sillyw0rld
"""Read-only generator data roots, independent of cwd and frozen module layout."""
from pathlib import Path
import sys

ROOT = Path(sys._MEIPASS) if getattr(sys, 'frozen', False) else Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'tools'
