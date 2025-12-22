#!/bin/bash
# Build script for Boojy Audio iOS
# This script builds the Rust engine for iOS and prepares it for Flutter

set -e

echo "🔨 Building Boojy Audio for iOS..."

# Navigate to engine directory
cd "$(dirname "$0")/engine"

# Build for iOS device (arm64)
echo "📱 Building for iOS device (aarch64-apple-ios)..."
cargo build --release --target aarch64-apple-ios --no-default-features --features mobile

# Build for iOS simulator (arm64 - Apple Silicon)
echo "💻 Building for iOS simulator (aarch64-apple-ios-sim)..."
cargo build --release --target aarch64-apple-ios-sim --no-default-features --features mobile

# Create Frameworks directory if it doesn't exist
mkdir -p ../ui/ios/Frameworks

# Copy the static libraries
echo "📦 Copying static libraries..."
cp target/aarch64-apple-ios/release/libengine.a ../ui/ios/Frameworks/libengine_device.a
cp target/aarch64-apple-ios-sim/release/libengine.a ../ui/ios/Frameworks/libengine_simulator.a

# Create a universal (fat) library for both device and simulator
# Note: This only works for different architectures. Since both are arm64,
# we'll keep them separate and let Xcode choose the right one.
echo "✅ iOS libraries built successfully!"
echo ""
echo "Libraries created:"
echo "  - ui/ios/Frameworks/libengine_device.a (for real iOS devices)"
echo "  - ui/ios/Frameworks/libengine_simulator.a (for iOS Simulator)"
echo ""
echo "Next steps:"
echo "  1. Add the library to your Xcode project"
echo "  2. Run 'cd ui && flutter build ios' to build the Flutter app"
echo ""

# Return to root directory
cd ..

echo "🎉 Build complete!"
