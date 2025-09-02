.PHONY: format build test clean docs docs-preview docs-static

format:
	swift format --in-place --recursive --parallel ./Sources ./Tests

build:
	swift build

test:
	swift test 2>&1 | ./scripts/swift-test-filter.sh

clean:
	swift package clean

docs:
	swift package --disable-sandbox generate-documentation --target AsyncFileMonitor

docs-preview:
	swift package --disable-sandbox preview-documentation --target AsyncFileMonitor

docs-static:
	swift package --allow-writing-to-directory docs/ \
		--disable-sandbox generate-documentation \
		--target AsyncFileMonitor \
		--disable-indexing \
		--transform-for-static-hosting \
		--output-path docs/
