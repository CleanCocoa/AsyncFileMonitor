.PHONY: format build test clean docs docs-preview docs-static

format:
	swift format --in-place --recursive --parallel ./Sources ./Tests

build:
	swift build

# --no-parallel: the teardown tests assert against FileSystemEventStream.liveCount, which is
# process-wide. Suite-level .serialized orders tests within a suite but not across suites, so a
# concurrently running suite can hold streams live and make those assertions false-pass (or, as
# the counter drops mid-test, spuriously fail). Costs ~50s against ~5s parallel.
test:
	swift test --no-parallel 2>&1 | ./scripts/swift-test-filter.sh

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
