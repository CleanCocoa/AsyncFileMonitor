# AsyncFileMonitor - Cross-platform file monitoring with Swift
# Main Makefile that includes modular build components

SHELL=/bin/bash -o pipefail

# Configuration
prefix ?= /usr/local
bindir = $(prefix)/bin
version := $(shell git describe --tags 2>/dev/null || echo "dev")

# Include modular makefiles
include mk/dev.mk
include mk/release.mk

# Combined targets that span multiple modules
.PHONY: clean
clean: clean-dev clean-release

.PHONY: test-all
test-all: test test-integration test-linux

# Default target
.PHONY: all
all: build

# Help target
.PHONY: help
help:
	@echo "AsyncFileMonitor Build System"
	@echo ""
	@echo "Development targets:"
	@echo "  build            Build for current platform"
	@echo "  test             Run Swift tests"
	@echo "  test-integration Run watch CLI integration tests"
	@echo "  format           Format code"
	@echo "  lint             Lint code"
	@echo "  docs             Generate documentation"
	@echo ""
	@echo "Release targets:"
	@echo "  release          Build cross-platform release artifacts"
	@echo "  test-linux       Test Linux build in Docker"
	@echo "  docker-test      Test Docker build"
	@echo ""
	@echo "Combined targets:"
	@echo "  clean            Clean all build artifacts"
	@echo "  test-all         Run all tests"
	@echo "  help             Show this help"
