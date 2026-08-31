#!/bin/bash
# Quick Setup Script for 16KB Compliance Checker
# Run this script once to set up your environment

echo "==================================================================="
echo "  16KB Page Size Compliance Checker - Setup"
echo "==================================================================="
echo ""

# Detect Android SDK location
if [ -d "$HOME/AppData/Local/Android/Sdk" ]; then
  ANDROID_SDK="$HOME/AppData/Local/Android/Sdk"
elif [ -d "/c/Users/$USER/AppData/Local/Android/Sdk" ]; then
  ANDROID_SDK="/c/Users/$USER/AppData/Local/Android/Sdk"
else
  echo "❌ Android SDK not found in default location"
  echo "   Please set ANDROID_HOME manually"
  exit 1
fi

echo "✓ Found Android SDK: $ANDROID_SDK"

# Look for NDK r29
NDK_DIR="$ANDROID_SDK/ndk/29.0.14206865"
if [ -d "$NDK_DIR" ]; then
  echo "✓ Found NDK r29: $NDK_DIR"
else
  echo "⚠ NDK r29 not found at: $NDK_DIR"
  echo ""
  echo "Looking for other NDK versions..."
  
  if [ -d "$ANDROID_SDK/ndk" ]; then
    echo "Available NDK versions:"
    ls -1 "$ANDROID_SDK/ndk" 2>/dev/null
    
    # Use the latest available
    LATEST_NDK=$(find "$ANDROID_SDK/ndk" -maxdepth 1 -type d | sort -V | tail -1)
    if [ -n "$LATEST_NDK" ] && [ "$LATEST_NDK" != "$ANDROID_SDK/ndk" ]; then
      echo ""
      echo "Using latest NDK: $LATEST_NDK"
      NDK_DIR="$LATEST_NDK"
    fi
  else
    echo ""
    echo "❌ No NDK installations found!"
    echo "   Please install NDK r29 from Android Studio:"
    echo "   Tools → SDK Manager → SDK Tools → NDK (Side by side)"
    exit 1
  fi
fi

# Set environment variable for current session
export ANDROID_NDK_HOME="$NDK_DIR"

echo ""
echo "==================================================================="
echo "  Environment Setup Complete"
echo "==================================================================="
echo ""
echo "ANDROID_NDK_HOME = $ANDROID_NDK_HOME"
echo ""
echo "To make this permanent, add to your ~/.bashrc:"
echo "  export ANDROID_NDK_HOME=\"$NDK_DIR\""
echo ""
echo "==================================================================="
echo "  Next Steps"
echo "==================================================================="
echo ""
echo "1. Make the checker script executable:"
echo "   chmod +x check_elf_alignment.sh"
echo ""
echo "2. Build your release APK:"
echo "   cd android && ./gradlew assembleRelease"
echo ""
echo "3. Run the compliance check:"
echo "   ./check_elf_alignment.sh build/app/outputs/apk/release/app-release.apk"
echo ""
