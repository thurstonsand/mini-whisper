# MiniWhisper CLI Workflow

scheme := "MiniWhisper"
dest := "platform=macOS"
derived_data := ".build/DerivedData"
app_path := derived_data / "Build/Products/Debug" / scheme + ".app"

# === App Targets ===

# Build the app
build:
    xcodebuild -scheme {{scheme}} \
        -destination '{{dest}}' \
        -derivedDataPath {{derived_data}} \
        build

# Build and run the app
run: build
    open {{app_path}}

# Run app tests
test:
    xcodebuild -scheme {{scheme}} \
        -destination '{{dest}}' \
        -derivedDataPath {{derived_data}} \
        test

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

# Remove build artifacts
clean:
    rm -rf {{derived_data}}
    rm -rf .build
    for pkg in Packages/*/; do swift package --package-path "$pkg" clean; done

# === Strict Build ===

# Build with strict compiler warnings
build-strict:
    xcodebuild -scheme {{scheme}} \
        -destination '{{dest}}' \
        -derivedDataPath {{derived_data}} \
        OTHER_SWIFT_FLAGS="-strict-concurrency=complete" \
        GCC_TREAT_WARNINGS_AS_ERRORS=YES \
        SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
        build
