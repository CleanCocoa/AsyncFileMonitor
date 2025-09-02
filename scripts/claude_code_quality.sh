#!/bin/bash

# Claude Code Quality Hook Script
# Automatically formats Swift files after modifications
# This script is designed to be used as a PostToolUse hook in Claude Code

set -euo pipefail

# Read JSON input from stdin
INPUT=$(cat)

# Extract hook event name and tool name
HOOK_EVENT_NAME=$(echo "$INPUT" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('hook_event_name', ''))" 2>/dev/null || echo "")
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('tool_name', ''))" 2>/dev/null || echo "")

# Only process PostToolUse events for file modification tools
if [ "$HOOK_EVENT_NAME" != "PostToolUse" ]; then
    exit 0
fi

# Check if this is a file modification tool
case "$TOOL_NAME" in
    Write|Edit|MultiEdit|NotebookEdit)
        ;;
    *)
        # Not a file modification tool, exit silently
        exit 0
        ;;
esac

# Extract file path from tool input
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tool_input = data.get('tool_input', {})
    file_path = tool_input.get('file_path', '')
    print(file_path)
except:
    pass
" 2>/dev/null || echo "")

# If no file path found, exit silently
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# Check if the file is a Swift file
if [[ ! "$FILE_PATH" =~ \.swift$ ]]; then
    exit 0
fi

# Check if the file exists
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Check if swift format is available
if ! command -v swift &> /dev/null; then
    echo "⚠️  swift is not available" >&2
    exit 0  # Non-blocking, just inform
fi

# Check if swift format subcommand exists
if ! swift format --version &> /dev/null; then
    echo "⚠️  swift format is not available. Make sure you have a recent Swift toolchain." >&2
    exit 0  # Non-blocking, just inform
fi

# Format the file in-place
swift format --in-place "$FILE_PATH" 2>/dev/null || {
    echo "⚠️  Failed to format $FILE_PATH" >&2
    exit 0  # Non-blocking
}

# Report success (shown in transcript mode with Ctrl-R)
echo "✓ Formatted $(basename "$FILE_PATH")"

exit 0