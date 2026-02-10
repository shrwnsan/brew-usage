#!/bin/bash
# Quick syntax check before committing

echo "Checking bash syntax..."

# Main script
if bash -n ./brew-usage; then
    echo "✓ brew-usage: OK"
else
    echo "✗ brew-usage: SYNTAX ERROR"
    exit 1
fi

# Lib scripts
for script in lib/*.sh; do
    if bash -n "$script"; then
        echo "✓ $script: OK"
    else
        echo "✗ $script: SYNTAX ERROR"
        exit 1
    fi
done

echo "All checks passed!"
