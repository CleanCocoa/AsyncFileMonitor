.PHONY: format build test clean

format:
	swift format --in-place --recursive --parallel ./Sources ./Tests

build:
	swift build

test:
	swift test 2>&1 | ./scripts/swift-test-filter.sh

clean:
	swift package clean
