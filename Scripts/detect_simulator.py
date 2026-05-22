#!/usr/bin/env python3
"""Pick an available iOS Simulator name (prefers iPhone 17)."""

from __future__ import annotations

import json
import subprocess
import sys

PREFERRED = "iPhone 17"


def main() -> int:
    preferred = sys.argv[1] if len(sys.argv) > 1 else PREFERRED
    data = json.loads(
        subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "available", "-j"],
            text=True,
        )
    )
    exact: list[str] = []
    partial: list[str] = []
    fallback: list[str] = []
    for runtime, devices in data.get("devices", {}).items():
        if "iOS" not in runtime:
            continue
        for device in devices:
            if not device.get("isAvailable", True):
                continue
            name = device.get("name", "")
            if not name:
                continue
            fallback.append(name)
            if name == preferred:
                exact.append(name)
            elif preferred in name:
                partial.append(name)
    if not exact and not partial and not fallback:
        print("No available iOS Simulator found.", file=sys.stderr)
        return 1
    pick = exact[0] if exact else (partial[0] if partial else fallback[0])
    print(pick)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
