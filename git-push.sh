#!/bin/bash

# Default commit message
COMMIT_MSG="Update changes"

# Use provided commit message if exists
if [ ! -z "$1" ]; then
    COMMIT_MSG="$1"
fi

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: Not in a git repository"
    exit 1
fi

# Add all changes
git add .

# Commit changes
git commit -m "$COMMIT_MSG"

# Push to remote
if ! git push; then
    echo "Error: Failed to push changes"
    exit 1
fi

echo "Successfully pushed changes to remote repository"
