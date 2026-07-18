#!/usr/bin/env zsh
# Lucid Pre-Commit Hook
# Runs lint and simulation checks before each commit

echo "=== Lucid Pre-Commit Hook ==="

# Lint RTL
echo "→ Linting RTL..."
make lint 2>/dev/null
if [ $? -ne 0 ]; then
    echo "✗ Lint failed. Aborting commit."
    exit 1
fi
echo "✓ Lint passed"

# Check for unstaged changes in RTL
STAGED_RTL=$(git diff --cached --name-only -- '*.sv')
if [ -n "$STAGED_RTL" ]; then
    echo "→ Running Icarus simulation for staged RTL..."
    make sim-icarus 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "✗ Simulation failed. Aborting commit."
        exit 1
    fi
    echo "✓ Simulation passed"
fi

echo "=== Pre-commit hook complete ==="
exit 0
