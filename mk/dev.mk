# Development tasks for AsyncFileMonitor
# Local building, testing, formatting, and documentation

.PHONY: build
build:
	swift build

.PHONY: test
test:
	swift test 2>&1 | ./scripts/swift-test-filter.sh

.PHONY: test-integration
test-integration:
	./scripts/test-watch.sh

.PHONY: format
format:
	swift format --in-place --recursive --parallel ./Sources ./Tests

.PHONY: lint
lint:
	swift format lint --recursive --parallel --strict ./Sources ./Tests


.PHONY: clean-dev
clean-dev:
	swift package clean

.PHONY: docs
docs:
	swift package --disable-sandbox generate-documentation --target AsyncFileMonitor

.PHONY: docs-preview
docs-preview:
	swift package --disable-sandbox preview-documentation --target AsyncFileMonitor

.PHONY: docs-static
docs-static:
	swift package --allow-writing-to-directory docs/ \
		--disable-sandbox generate-documentation \
		--target AsyncFileMonitor \
		--disable-indexing \
		--transform-for-static-hosting \
		--output-path docs/