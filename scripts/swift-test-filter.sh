#!/usr/bin/env bash

# Swift Test Output Filter
# Filters swift test output to focus on failures and important information

set -o pipefail

# ANSI color codes
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Statistics
TESTS_RUN=0
TESTS_FAILED=0
ISSUES_FOUND=0
CURRENT_FAILING_TEST=""
IN_FAILURE_CONTEXT=0
EXECUTED_TESTS=0

while IFS= read -r line; do
    # Test run summary - check first to ensure we never filter these out
    # Success case with known issues - new Swift Testing format: "􀢄  Test run with X tests passed after Y seconds with Z known issue."
    if [[ "$line" =~ 􀢄.*Test[[:space:]]+run[[:space:]]+with.*passed[[:space:]]+after.*seconds.*with.*known[[:space:]]+issue ]]; then
        echo
        echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
        echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED (with expected known issues)${NC}"
        echo -e "${YELLOW}$line${NC}"
        echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
        continue
    fi
    # Success case - matches the actual format: "􁁛  Test run with X tests passed after Y seconds."
    if [[ "$line" =~ 􁁛.*Test[[:space:]]+run[[:space:]]+with.*passed[[:space:]]+after.*seconds ]]; then
        echo
        echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
        echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
        # Show the actual test count if we captured it, otherwise show the line as-is
        if [[ $EXECUTED_TESTS -gt 0 ]]; then
            echo -e "${GREEN}􁁛  Test run with ${EXECUTED_TESTS} tests passed after ${line##*after}${NC}"
        else
            echo -e "${GREEN}$line${NC}"
        fi
        echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
        continue
    fi
    
    # Failure case
    if [[ "$line" =~ Test[[:space:]]+run.*with[[:space:]]+[0-9]+[[:space:]]+tests.*failed.*after.*seconds.*with[[:space:]]+[0-9]+[[:space:]]+issue ]]; then
        echo
        echo -e "${RED}${BOLD}════════════════════════════════════════${NC}"
        echo -e "${RED}${BOLD}TEST RUN FAILED${NC}"
        echo -e "${RED}$line${NC}"
        echo -e "${RED}Failed tests: ${TESTS_FAILED}${NC}"
        echo -e "${RED}${BOLD}════════════════════════════════════════${NC}"
        continue
    fi

    # Skip "Test started" lines for passing tests
    if [[ "$line" =~ ^[[:space:]]*􀟈[[:space:]]+Test.*started\. ]]; then
        continue
    fi
    
    # Skip "Suite started" lines
    if [[ "$line" =~ ^[[:space:]]*􀟈[[:space:]]+Suite.*started\. ]]; then
        continue
    fi
    
    # Test passed with known issues - show these as they're important
    if [[ "$line" =~ ^[[:space:]]*􀢄[[:space:]]+Test.*passed.*after.*seconds.*with.*known[[:space:]]+issue ]]; then
        echo -e "${YELLOW}$line${NC}"
        ((TESTS_RUN++))
        continue
    fi
    
    # Skip successful test lines but count them
    if [[ "$line" =~ ^[[:space:]]*􁁛[[:space:]]+Test.*passed.*after.*seconds\. ]]; then
        ((TESTS_RUN++))
        continue
    fi
    
    # Extract executed test count from "All tests" summary line
    if [[ "$line" =~ Test[[:space:]]+Suite[[:space:]]+\'All[[:space:]]+tests\'[[:space:]]+passed ]] || [[ "$line" =~ Test[[:space:]]+Suite[[:space:]]+\'All[[:space:]]+tests\'[[:space:]]+failed ]]; then
        # Read the next line which contains the actual count
        if IFS= read -r next_line; then
            if [[ "$next_line" =~ Executed[[:space:]]+([0-9]+)[[:space:]]+test ]]; then
                EXECUTED_TESTS="${BASH_REMATCH[1]}"
            fi
            # Don't output these lines as we'll show them in the summary
        fi
        continue
    fi
    
    # Also capture from other "Executed X tests" lines
    if [[ "$line" =~ Executed[[:space:]]+([0-9]+)[[:space:]]+tests?,.*with[[:space:]]+([0-9]+)[[:space:]]+failures? ]]; then
        EXECUTED_TESTS="${BASH_REMATCH[1]}"
        ACTUAL_FAILURES="${BASH_REMATCH[2]}"
        continue
    fi
    
    # Skip successful suite lines
    if [[ "$line" =~ ^[[:space:]]*􁁛[[:space:]]+Suite.*passed.*after.*seconds\. ]]; then
        continue
    fi
    
    # Handle known issues - show them with different formatting than failures
    if [[ "$line" =~ ^[[:space:]]*􀢄[[:space:]]+Test[[:space:]]+\"([^\"]+)\".*recorded[[:space:]]+a[[:space:]]+known[[:space:]]+issue[[:space:]]+at[[:space:]]+([^:]+):([0-9]+):([0-9]+): ]]; then
        TEST_NAME="${BASH_REMATCH[1]}"
        FILE="${BASH_REMATCH[2]}"
        LINE="${BASH_REMATCH[3]}"
        COL="${BASH_REMATCH[4]}"
        
        if [[ "$CURRENT_FAILING_TEST" != "$TEST_NAME" ]]; then
            echo
            echo -e "${YELLOW}${BOLD}ℹ Known Issue: ${TEST_NAME}${NC}"
            CURRENT_FAILING_TEST="$TEST_NAME"
        fi
        
        echo -e "  ${CYAN}${FILE}:${LINE}:${COL}${NC}"
        ((ISSUES_FOUND++))
        IN_FAILURE_CONTEXT=1
        continue
    fi
    
    # Highlight test failures with detailed info
    if [[ "$line" =~ ^[[:space:]]*􀢄[[:space:]]+Test[[:space:]]+([^[:space:]]+\(\)).*recorded.*issue.*at[[:space:]]+([^:]+):([0-9]+):([0-9]+):[[:space:]]*(.*) ]]; then
        TEST_NAME="${BASH_REMATCH[1]}"
        FILE="${BASH_REMATCH[2]}"
        LINE="${BASH_REMATCH[3]}"
        COL="${BASH_REMATCH[4]}"
        MESSAGE="${BASH_REMATCH[5]}"
        
        if [[ "$CURRENT_FAILING_TEST" != "$TEST_NAME" ]]; then
            echo
            echo -e "${RED}${BOLD}✗ Test Failed: ${TEST_NAME}${NC}"
            CURRENT_FAILING_TEST="$TEST_NAME"
            ((TESTS_FAILED++))
        fi
        
        echo -e "  ${CYAN}${FILE}:${LINE}:${COL}${NC}"
        echo -e "  ${RED}${MESSAGE}${NC}"
        ((ISSUES_FOUND++))
        IN_FAILURE_CONTEXT=1
        continue
    fi
    
    # Show test failure summary
    if [[ "$line" =~ ^[[:space:]]*􀢄[[:space:]]+Test[[:space:]]+([^[:space:]]+\(\)).*failed.*after.*seconds.*with.*([0-9]+).*issue ]]; then
        TEST_NAME="${BASH_REMATCH[1]}"
        ISSUE_COUNT="${BASH_REMATCH[2]}"
        
        if [[ "$CURRENT_FAILING_TEST" != "$TEST_NAME" ]]; then
            echo
            echo -e "${RED}${BOLD}✗ Test Failed: ${TEST_NAME}${NC}"
            echo -e "  ${YELLOW}${ISSUE_COUNT} issue(s)${NC}"
            ((TESTS_FAILED++))
        fi
        CURRENT_FAILING_TEST=""
        IN_FAILURE_CONTEXT=0
        continue
    fi
    
    # Show suite failures
    if [[ "$line" =~ ^[[:space:]]*􀢄[[:space:]]+Suite[[:space:]]+\"([^\"]+)\".*failed.*after.*seconds.*with.*([0-9]+).*issue ]]; then
        SUITE_NAME="${BASH_REMATCH[1]}"
        ISSUE_COUNT="${BASH_REMATCH[2]}"
        echo
        echo -e "${RED}${BOLD}✗ Suite Failed: ${SUITE_NAME}${NC}"
        echo -e "  ${YELLOW}Total issues in suite: ${ISSUE_COUNT}${NC}"
        continue
    fi
    
    # Show context lines after failures (code snippets)
    if [[ "$line" =~ ^[[:space:]]*􀄵[[:space:]]*//.* ]] && [[ $IN_FAILURE_CONTEXT -eq 1 ]]; then
        echo -e "  ${MAGENTA}$line${NC}"
        continue
    fi
    
    # Compilation errors
    if [[ "$line" =~ error:|ERROR:|fatal\ error: ]]; then
        echo -e "${RED}${BOLD}✗ COMPILATION ERROR${NC}"
        echo -e "${RED}$line${NC}"
        continue
    fi
    
    # File:line:column references in errors
    if [[ "$line" =~ ^(/[^:]+):([0-9]+):([0-9]+): ]]; then
        echo -e "${CYAN}$line${NC}"
        continue
    fi
    
    
    # Build/compilation messages
    if [[ "$line" =~ "Building for debugging" ]] || [[ "$line" =~ "Build complete!" ]]; then
        echo -e "${BLUE}$line${NC}"
        continue
    fi
    
    # Planning/linking messages (show briefly)
    if [[ "$line" =~ "Planning build" ]] || [[ "$line" =~ "Linking" ]]; then
        echo -e "${CYAN}$line${NC}"
        continue
    fi
    
    # Fatal errors (e.g., fatalError calls in code)
    if [[ "$line" =~ "Fatal error:" ]]; then
        echo -e "${RED}${BOLD}✗ FATAL ERROR${NC}"
        echo -e "${RED}$line${NC}"
        continue
    fi
    
    # Skip other noise
    if [[ "$line" =~ ^[[:space:]]*\[.*\].*(Write|Compiling|Emitting|Building) ]]; then
        continue
    fi
    
    # Skip empty lines
    if [[ -z "${line// }" ]]; then
        continue
    fi
    
    # Default: skip to reduce noise
done