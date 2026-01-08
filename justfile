# MiniWhisper CLI Workflow

scheme := "MiniWhisper"
dest := "platform=macOS,arch=arm64"
derived_data := ".build/DerivedData"
app_path := derived_data / "Build/Products/Debug" / scheme + ".app"
xcb := "xcbeautify -q --disable-colored-output --disable-logging"

# === App Targets ===

# Build the app (strict: warnings as errors, full concurrency checks)
build:
    xcodebuild -scheme {{scheme}} \
        -destination '{{dest}}' \
        -derivedDataPath {{derived_data}} \
        OTHER_SWIFT_FLAGS="-strict-concurrency=complete" \
        GCC_TREAT_WARNINGS_AS_ERRORS=YES \
        SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
        build | {{xcb}}

# Build without strict checks (faster iteration)
build-quick:
    xcodebuild -scheme {{scheme}} \
        -destination '{{dest}}' \
        -derivedDataPath {{derived_data}} \
        build | {{xcb}}

# Build and run the app
run: build
    open {{app_path}}

# Run app tests
test:
    xcodebuild -scheme {{scheme}} \
        -destination '{{dest}}' \
        -derivedDataPath {{derived_data}} \
        test | {{xcb}}

# === Package Targets (fast, no Xcode overhead) ===

# Build all local packages
build-packages:
    #!/usr/bin/env bash
    for pkg in Packages/*/; do
        echo "Building $pkg..."
        swift build --package-path "$pkg" || exit 1
    done

# Test all local packages
test-packages:
    #!/usr/bin/env bash
    for pkg in Packages/*/; do
        echo "Testing $pkg..."
        swift test --package-path "$pkg" || exit 1
    done

# === Code Quality ===

# Format all Swift code
format:
    swift format --recursive --in-place MiniWhisper/ Packages/

# Check formatting (CI)
format-check:
    swift format --recursive MiniWhisper/ Packages/ 2>&1 | grep -q "would be reformatted" && exit 1 || exit 0

# === Maintenance ===

# Reset microphone permission (will prompt again on next launch)
reset-permissions:
    tccutil reset Microphone com.thurstonsand.MiniWhisper

# Build and run with fresh permissions
run-fresh: reset-permissions run

# Remove build artifacts
clean:
    rm -rf {{derived_data}}
    rm -rf .build
    for pkg in Packages/*/; do swift package --package-path "$pkg" clean; done
