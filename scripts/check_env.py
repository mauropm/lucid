#!/usr/bin/env python3
"""
Lucid Environment Check
Verifies that all required tools are installed and functional.
"""

import subprocess
import sys
import shutil

REQUIRED = [
    'verilator',
    'iverilog',
    'make',
    'python3',
]

OPTIONAL = [
    'gtkwave',
    'yosys',
    'nextpnr-gowin',
    'openFPGALoader',
]


def check_tool(name, version_flag='--version'):
    path = shutil.which(name)
    if path is None:
        return False, 'not found'

    try:
        result = subprocess.run(
            [name, version_flag],
            capture_output=True, text=True, timeout=5
        )
        version = result.stdout.strip().split('\n')[0][:60]
        return True, version
    except Exception as e:
        return True, str(e)


def main():
    print("Lucid Environment Check")
    print("======================")
    print()

    all_ok = True

    print("Required Tools:")
    for tool in REQUIRED:
        found, info = check_tool(tool)
        status = '✓' if found else '✗'
        print(f"  {status} {tool}: {info}")
        if not found:
            all_ok = False

    print()
    print("Optional Tools:")
    for tool in OPTIONAL:
        found, info = check_tool(tool)
        status = '✓' if found else '○'
        print(f"  {status} {tool}: {info}")

    print()
    if all_ok:
        print("All required tools are available.")
    else:
        print("Some required tools are missing. See docs/architecture/developer-guide.md for installation instructions.")
        sys.exit(1)


if __name__ == '__main__':
    main()
