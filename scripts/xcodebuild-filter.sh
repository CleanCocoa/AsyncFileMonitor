#!/usr/bin/env bash

# XcodeBuild Output Filter
# Based on: https://gist.github.com/ryanashcraft/21da95cf279736bc799249d6d884afd2
# Filters xcodebuild output to highlight errors and reduce noise

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

# Track if we're in an error block
IN_ERROR=0
ERROR_BUFFER=""

while IFS= read -r line; do
    # Skip common noise
    if [[ "$line" =~ ^(Building|Linking|Copying|Processing|Touch|Create|Write|Ld|CodeSign|GenerateDSYMFile|CreateBuildDirectory|CreateUniversalBinary|CompileSwift|SwiftCompile|Ditto|Strip|SetOwnerAndGroup|SetMode|Validate|RegisterWithLaunchServices|cd|export|/usr/bin|/Applications/Xcode) ]]; then
        continue
    fi
    
    # Skip empty lines and whitespace
    if [[ -z "${line// }" ]]; then
        continue
    fi
    
    # Detect and highlight errors
    if [[ "$line" =~ error:|ERROR:|fatal\ error: ]]; then
        echo -e "${RED}${BOLD}✗ ERROR${NC}"
        echo -e "${RED}$line${NC}"
        IN_ERROR=1
        ERROR_BUFFER=""
        continue
    fi
    
    # Detect and highlight warnings
    if [[ "$line" =~ warning:|WARNING: ]]; then
        echo -e "${YELLOW}${BOLD}⚠ WARNING${NC}"
        echo -e "${YELLOW}$line${NC}"
        continue
    fi
    
    # Detect compilation file references (file:line:column)
    if [[ "$line" =~ ^(/[^:]+):([0-9]+):([0-9]+): ]]; then
        if [[ $IN_ERROR -eq 1 ]]; then
            echo -e "${CYAN}$line${NC}"
        else
            echo -e "${BLUE}$line${NC}"
        fi
        continue
    fi
    
    # Show note lines following errors
    if [[ "$line" =~ ^[[:space:]]*note: ]] && [[ $IN_ERROR -eq 1 ]]; then
        echo -e "${MAGENTA}$line${NC}"
        continue
    fi
    
    # Show code context (lines starting with digits and |)
    if [[ "$line" =~ ^[[:space:]]*[0-9]+[[:space:]]*\| ]] && [[ $IN_ERROR -eq 1 ]]; then
        echo "$line"
        continue
    fi
    
    # Show pointer lines (^ and ~ characters)
    if [[ "$line" =~ ^[[:space:]]*[\^~]+ ]] && [[ $IN_ERROR -eq 1 ]]; then
        echo -e "${RED}$line${NC}"
        continue
    fi
    
    # Detect successful operations
    if [[ "$line" =~ "Build succeeded" ]] || [[ "$line" =~ "** BUILD SUCCEEDED **" ]]; then
        echo -e "${GREEN}${BOLD}✓ BUILD SUCCEEDED${NC}"
        IN_ERROR=0
        continue
    fi
    
    if [[ "$line" =~ "Build failed" ]] || [[ "$line" =~ "** BUILD FAILED **" ]]; then
        echo -e "${RED}${BOLD}✗ BUILD FAILED${NC}"
        IN_ERROR=0
        continue
    fi
    
    # Detect test results
    if [[ "$line" =~ "Test Suite.*passed" ]]; then
        echo -e "${GREEN}$line${NC}"
        continue
    fi
    
    if [[ "$line" =~ "Test Suite.*failed" ]]; then
        echo -e "${RED}$line${NC}"
        continue
    fi
    
    # Handle continuation of error context
    if [[ $IN_ERROR -eq 1 ]]; then
        # If we hit a line that looks like a new command, reset error state
        if [[ "$line" =~ ^[A-Z] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
            IN_ERROR=0
        else
            echo "$line"
            continue
        fi
    fi
    
    # Show target/scheme info
    if [[ "$line" =~ "=== BUILD TARGET" ]] || [[ "$line" =~ "=== ANALYZE TARGET" ]]; then
        echo -e "${BOLD}$line${NC}"
        continue
    fi
    
    # Default: skip the line (reduce noise)
done