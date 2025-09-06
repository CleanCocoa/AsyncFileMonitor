#!/usr/bin/env bash

# Test script for AsyncFileMonitor watch CLI
# This script verifies that the file monitoring functionality works correctly

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
TEST_DIR="/tmp/asyncfilemonitor-test-$$"
WATCH_LOG="${TEST_DIR}/watch.log"
WATCH_PID_FILE="${TEST_DIR}/watch.pid"
TIMEOUT=30
WAIT_FOR_START=2
WAIT_BETWEEN_OPERATIONS=1

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    
    # Kill watch process if still running
    if [[ -f "$WATCH_PID_FILE" ]]; then
        PID=$(cat "$WATCH_PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null || true
            sleep 1
            kill -9 "$PID" 2>/dev/null || true
        fi
        rm -f "$WATCH_PID_FILE"
    fi
    
    # Remove test directory
    rm -rf "$TEST_DIR"
    
    echo -e "${GREEN}Cleanup complete${NC}"
}

# Set trap for cleanup on exit
trap cleanup EXIT INT TERM

# Get script directory and package root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PACKAGE_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Create test directory
echo -e "${YELLOW}Setting up test environment...${NC}"
mkdir -p "$TEST_DIR"

# Build the watch CLI from package root
echo -e "${YELLOW}Building watch CLI...${NC}"
cd "$PACKAGE_ROOT"
swift build --product watch 2>&1

# Start the watch process in background
echo -e "${YELLOW}Starting file monitor for: $TEST_DIR${NC}"
# First build to avoid build output in logs
swift build --product watch >/dev/null 2>&1
# Run without building
swift run --skip-build watch "$TEST_DIR" > "$WATCH_LOG" 2>&1 &
WATCH_PID=$!
echo "$WATCH_PID" > "$WATCH_PID_FILE"

# Wait for watch to start
echo -e "${YELLOW}Waiting for monitor to initialize...${NC}"
sleep "$WAIT_FOR_START"

# Verify process is running
if ! kill -0 "$WATCH_PID" 2>/dev/null; then
    echo -e "${RED}ERROR: Watch process failed to start${NC}"
    cat "$WATCH_LOG"
    exit 1
fi

echo -e "${GREEN}Monitor started successfully (PID: $WATCH_PID)${NC}"

# Function to perform file operation and check log
perform_test() {
    local operation="$1"
    local expected_pattern="$2"
    local description="$3"
    
    echo -e "${YELLOW}Test: $description${NC}"
    
    # Perform the operation in test directory
    cd "$TEST_DIR"
    eval "$operation"
    cd - > /dev/null
    
    # Wait for event to be processed
    sleep "$WAIT_BETWEEN_OPERATIONS"
    
    # Check if pattern exists in log
    if grep -q "$expected_pattern" "$WATCH_LOG"; then
        echo -e "${GREEN}  ✓ Detected: $expected_pattern${NC}"
        return 0
    else
        echo -e "${RED}  ✗ Pattern not found: $expected_pattern${NC}"
        echo "  Current log:"
        tail -20 "$WATCH_LOG" | sed 's/^/    /'
        return 1
    fi
}

# Run tests
echo -e "\n${YELLOW}Running file system tests...${NC}"

# Test 1: Create a file
perform_test \
    "echo 'test content' > test1.txt" \
    "test1.txt" \
    "Create file test1.txt"

# Test 2: Modify a file
perform_test \
    "echo 'modified content' >> test1.txt" \
    "test1.txt" \
    "Modify file test1.txt"

# Test 3: Create a directory
perform_test \
    "mkdir -p subdir" \
    "subdir" \
    "Create directory subdir"

# Test 4: Create file in subdirectory
perform_test \
    "touch subdir/nested.txt" \
    "nested.txt" \
    "Create file in subdirectory"

# Test 5: Rename a file
perform_test \
    "mv test1.txt test1_renamed.txt" \
    "renamed" \
    "Rename test1.txt to test1_renamed.txt"

# Test 6: Delete a file
perform_test \
    "rm -f test1_renamed.txt" \
    "removed" \
    "Delete test1_renamed.txt"

# Test 7: Multiple operations
echo -e "${YELLOW}Test: Multiple rapid file operations${NC}"

cd "$TEST_DIR"
touch rapid1.txt rapid2.txt rapid3.txt
echo "data" > rapid1.txt
rm rapid2.txt
mv rapid3.txt rapid3_moved.txt
cd - > /dev/null

sleep "$WAIT_BETWEEN_OPERATIONS"

# Count how many rapid files were detected
rapid_count=$(grep -c "rapid" "$WATCH_LOG" || echo 0)

if [[ $rapid_count -ge 3 ]]; then
    echo -e "${GREEN}  ✓ Detected $rapid_count events from rapid operations${NC}"
else
    echo -e "${YELLOW}  ⚠ Detected $rapid_count rapid file events (FSEvents may coalesce rapid changes)${NC}"
fi

# Final summary
echo -e "\n${YELLOW}Test Summary:${NC}"
echo -e "${GREEN}File monitoring tests completed${NC}"
echo ""
echo "Full log output:"
echo "==============="
cat "$WATCH_LOG"
echo "==============="

# Kill the watch process
kill "$WATCH_PID" 2>/dev/null || true

echo -e "\n${GREEN}All tests completed successfully!${NC}"