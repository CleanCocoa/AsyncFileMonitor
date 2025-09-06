# Release and distribution tasks for AsyncFileMonitor
# Cross-platform builds, Docker, and release artifacts

# Linux build artifacts
linux_files = release/watch_linux-amd64-$(version).tar.bz2 release/watch_linux-arm64-$(version).tar.bz2

# Build Linux binaries using Docker
$(linux_files) &:
	docker buildx build --quiet --platform linux/amd64,linux/arm64 --tag asyncfilemonitor/watch --target export --output=./release/ .
	tar --create --bzip2 --file release/watch_linux-amd64-$(version).tar.bz2 --directory release/linux_amd64 watch
	tar --create --bzip2 --file release/watch_linux-arm64-$(version).tar.bz2 --directory release/linux_arm64 watch

# macOS universal binary build
.build/$(version)/arm64-apple-macosx/release/watch:
	swift build --quiet --scratch-path .build/$(version) --configuration release --triple arm64-apple-macosx

.build/$(version)/x86_64-apple-macosx/release/watch:
	swift build --quiet --scratch-path .build/$(version) --configuration release --triple x86_64-apple-macosx

release/macos-universal-$(version)/watch: .build/$(version)/arm64-apple-macosx/release/watch .build/$(version)/x86_64-apple-macosx/release/watch
	mkdir -p release/macos-universal-$(version)
	lipo -create -output release/macos-universal-$(version)/watch .build/$(version)/{arm64,x86_64}-apple-macosx/release/watch

release/watch_macos-universal-$(version).tar.bz2: release/macos-universal-$(version)/watch
	tar --create --bzip2 --file release/watch_macos-universal-$(version).tar.bz2 --directory release/macos-universal-$(version) watch

.PHONY: release
release: $(linux_files) release/watch_macos-universal-$(version).tar.bz2

.PHONY: test-linux
test-linux:
	docker run --rm -v $(PWD):/workspace -w /workspace swift:6.1.0 /bin/bash -c "apt-get update && apt-get install -y libuv1-dev && swift test --filter AsyncFileMonitorLinuxTests"

.PHONY: docker-test
docker-test:
	docker buildx build --progress=plain --platform linux/amd64 --target build .

.PHONY: clean-release
clean-release:
	rm -rf release/*.tar.bz2 release/linux_* release/macos* release/watch*