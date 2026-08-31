#!/bin/bash

# Enhanced ELF Alignment Checker for Android 16KB Page Size Compatibility
# This script checks if your app's native libraries are compatible with 16KB page size devices
# as required by Google Play starting November 1st, 2025 for apps targeting Android 15+

# ============================================================================
# NDK Configuration - UPDATE THIS PATH FOR YOUR SYSTEM
# ============================================================================
# For Windows with Android Studio, typical paths are:
# - C:\Users\YourUsername\AppData\Local\Android\Sdk\ndk\29.0.14206865
# - Or use ANDROID_NDK_HOME if set: ${ANDROID_NDK_HOME}
#
# Auto-detect NDK path or set manually:
if [ -n "$ANDROID_NDK_HOME" ]; then
  NDK_PATH="$ANDROID_NDK_HOME"
elif [ -d "$HOME/AppData/Local/Android/Sdk/ndk/29.0.14206865" ]; then
  NDK_PATH="$HOME/AppData/Local/Android/Sdk/ndk/29.0.14206865"
elif [ -d "/c/Users/$USER/AppData/Local/Android/Sdk/ndk/29.0.14206865" ]; then
  NDK_PATH="/c/Users/$USER/AppData/Local/Android/Sdk/ndk/29.0.14206865"
else
  # Fallback: Try to find any NDK installation
  ANDROID_HOME="${ANDROID_HOME:-$HOME/AppData/Local/Android/Sdk}"
  if [ -d "$ANDROID_HOME/ndk" ]; then
    # Get the latest NDK version
    NDK_PATH=$(find "$ANDROID_HOME/ndk" -maxdepth 1 -type d | sort -V | tail -1)
  fi
fi

# NDK toolchain binaries (will be set based on architecture)
OBJDUMP=""

progname="${0##*/}"
progname="${progname%.sh}"

# Color codes and formatting - detect if colors are supported
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1 && [[ $(tput colors) -ge 8 ]]; then
  RED="\033[31m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  BLUE="\033[34m"
  CYAN="\033[36m"
  PURPLE="\033[35m"
  BOLD="\033[1m"
  DIM="\033[2m"
  ENDCOLOR="\033[0m"
  USE_COLORS=true
else
  # No color support - use plain text
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  CYAN=""
  PURPLE=""
  BOLD=""
  DIM=""
  ENDCOLOR=""
  USE_COLORS=false
fi

# Unicode symbols with fallbacks
if [[ $USE_COLORS == true ]]; then
  CHECK_MARK="✓"
  CROSS_MARK="✗"
  WARNING_MARK="⚠"
  INFO_MARK="ℹ"
  ROCKET="🚀"
  GEAR="⚙"
  PACKAGE="📦"
  DOCUMENT="📄"
  ALERT="🚨"
  PARTY="🎉"
  TOOLS="🔧"
  BOOKS="📚"
  ARROW="▶"
else
  CHECK_MARK="[OK]"
  CROSS_MARK="[X]"
  WARNING_MARK="[!]"
  INFO_MARK="[i]"
  ROCKET="[>]"
  GEAR="[*]"
  PACKAGE="[P]"
  DOCUMENT="[D]"
  ALERT="[!]"
  PARTY="[*]"
  TOOLS="[T]"
  BOOKS="[B]"
  ARROW=">"
fi

# Enhanced formatting functions
print_banner() {
  local title="$1"
  local subtitle="$2"
  local width=88

  echo
  printf "%*s\n" $width | tr ' ' '═'

  # Main title
  local title_len=${#title}
  local title_padding=$(( (width - title_len - 4) / 2 ))
  printf "║${BOLD}${BLUE}%*s %s %*s${ENDCOLOR}║\n" \
    $title_padding "" "$title" $title_padding ""

  # Subtitle if provided
  if [[ -n "$subtitle" ]]; then
    local subtitle_len=${#subtitle}
    local subtitle_padding=$(( (width - subtitle_len - 4) / 2 ))
    printf "║${DIM}%*s %s %*s${ENDCOLOR}║\n" \
      $subtitle_padding "" "$subtitle" $subtitle_padding ""
  fi

  printf "%*s\n" $width | tr ' ' '═'
  echo
}

print_section() {
  local icon="$1"
  local title="$2"
  local description="$3"

  echo
  echo -e "${BOLD}${BLUE}$icon $title${ENDCOLOR}"
  if [[ -n "$description" ]]; then
    echo -e "${DIM}$description${ENDCOLOR}"
  fi
  printf "${BLUE}%*s${ENDCOLOR}\n" 80 | tr ' ' '─'
}

print_status() {
  local status="$1"
  local message="$2"
  local detail="$3"

  case $status in
    "success")
      printf "  ${GREEN}${CHECK_MARK}${ENDCOLOR} %s" "$message"
      ;;
    "error")
      printf "  ${RED}${CROSS_MARK}${ENDCOLOR} %s" "$message"
      ;;
    "warning")
      printf "  ${YELLOW}${WARNING_MARK}${ENDCOLOR} %s" "$message"
      ;;
    "info")
      printf "  ${CYAN}${INFO_MARK}${ENDCOLOR} %s" "$message"
      ;;
    "processing")
      printf "  ${PURPLE}${GEAR}${ENDCOLOR} %s" "$message"
      ;;
  esac

  if [[ -n "$detail" ]]; then
    printf "\n    ${DIM}%s${ENDCOLOR}" "$detail"
  fi
  echo
}

print_subsection() {
  local title="$1"
  echo
  echo -e "  ${BOLD}${PURPLE}${ARROW} $title${ENDCOLOR}"
  printf "  ${PURPLE}%*s${ENDCOLOR}\n" 50 | tr ' ' '┈'
}

print_table_header() {
  echo
  local line1="┌$(printf '─%.0s' {1..29})┬$(printf '─%.0s' {1..18})┬$(printf '─%.0s' {1..15})┬$(printf '─%.0s' {1..13})┐"
  local line2="│ $(printf '%-27s' 'Library') │ $(printf '%-16s' 'Architecture') │ $(printf '%-13s' 'Alignment') │ $(printf '%-11s' 'Status') │"
  local line3="├$(printf '─%.0s' {1..29})┼$(printf '─%.0s' {1..18})┼$(printf '─%.0s' {1..15})┼$(printf '─%.0s' {1..13})┤"

  echo -e "${CYAN}$line1${ENDCOLOR}"
  echo -e "${BOLD}${CYAN}$line2${ENDCOLOR}"
  echo -e "${CYAN}$line3${ENDCOLOR}"
}

print_table_row() {
  local lib="$1"
  local arch="$2"
  local alignment="$3"
  local status="$4"
  local is_critical="$5"

  local status_symbol
  local status_color
  local status_text

  if [[ $status == "ALIGNED" ]]; then
    status_symbol="$CHECK_MARK"
    status_color="$GREEN"
    status_text="PASS"
  else
    status_symbol="$CROSS_MARK"
    if [[ $is_critical == "true" ]]; then
      status_color="$RED"
      status_text="FAIL"
    else
      status_color="$YELLOW"
      status_text="WARN"
    fi
  fi

  # Truncate library name if too long
  local display_lib="$lib"
  if [[ ${#lib} -gt 27 ]]; then
    display_lib="${lib:0:24}..."
  fi

  printf "${CYAN}│${ENDCOLOR} %-27s ${CYAN}│${ENDCOLOR} %-16s ${CYAN}│${ENDCOLOR} %-13s ${CYAN}│${ENDCOLOR} ${status_color}%s %-7s${ENDCOLOR} ${CYAN}│${ENDCOLOR}\n" \
    "$display_lib" "$arch" "$alignment" "$status_symbol" "$status_text"

  if [[ $is_critical == "true" && $status == "UNALIGNED" ]]; then
    printf "${CYAN}│${ENDCOLOR} ${RED}%-75s${ENDCOLOR} ${CYAN}│${ENDCOLOR}\n" "  ${ALERT} CRITICAL: Required for Google Play compliance!"
  fi
}

print_table_footer() {
  local line="└$(printf '─%.0s' {1..29})┴$(printf '─%.0s' {1..18})┴$(printf '─%.0s' {1..15})┴$(printf '─%.0s' {1..13})┘"
  echo -e "${CYAN}$line${ENDCOLOR}"
  echo
}

print_summary_box() {
  local title="$1"
  local status="$2" # success, warning, error
  shift 2
  local lines=("$@")

  local box_color
  local title_color
  case $status in
    "success") box_color="$GREEN"; title_color="$GREEN" ;;
    "warning") box_color="$YELLOW"; title_color="$YELLOW" ;;
    "error") box_color="$RED"; title_color="$RED" ;;
    *) box_color="$BLUE"; title_color="$BLUE" ;;
  esac

  local width=78
  echo
  printf "${box_color}┌%*s┐${ENDCOLOR}\n" $((width-2)) | tr ' ' '─'

  # Title
  local title_len=${#title}
  local title_padding=$(( (width - title_len - 4) / 2 ))
  printf "${box_color}│${ENDCOLOR}${BOLD}${title_color}%*s %s %*s${ENDCOLOR}${box_color}│${ENDCOLOR}\n" \
    $title_padding "" "$title" $title_padding ""

  printf "${box_color}├%*s┤${ENDCOLOR}\n" $((width-2)) | tr ' ' '─'

  # Content lines
  for line in "${lines[@]}"; do
    printf "${box_color}│${ENDCOLOR} %-*s ${box_color}│${ENDCOLOR}\n" $((width-4)) "$line"
  done

  printf "${box_color}└%*s┘${ENDCOLOR}\n" $((width-2)) | tr ' ' '─'
  echo
}

cleanup_trap() {
  if [ -n "${tmp}" -a -d "${tmp}" ]; then
    print_status "processing" "Cleaning up temporary files..."
    rm -rf "${tmp}"
  fi
  exit $1
}

usage() {
  print_banner "Android 16KB Page Size Compatibility Checker" "Google Play Compliance Tool"

  echo -e "${BOLD}DESCRIPTION:${ENDCOLOR}"
  echo "  This tool verifies that your Android app's native libraries are compatible"
  echo "  with 16KB page size devices, as required by Google Play starting November 1st, 2025."
  echo

  echo -e "${BOLD}USAGE:${ENDCOLOR}"
  echo -e "  ${GREEN}$progname${ENDCOLOR} ${CYAN}[input-path|input-APK|input-APEX]${ENDCOLOR}"
  echo

  echo -e "${BOLD}EXAMPLES:${ENDCOLOR}"
  echo -e "  ${DIM}# Check an APK file${ENDCOLOR}"
  echo -e "  $progname ${CYAN}app/build/outputs/apk/release/app-release.apk${ENDCOLOR}"
  echo
  echo -e "  ${DIM}# Check a directory of native libraries${ENDCOLOR}"
  echo -e "  $progname ${CYAN}/path/to/native/libs/${ENDCOLOR}"
  echo

  echo -e "${BOLD}WHAT THIS TOOL CHECKS:${ENDCOLOR}"
  echo -e "  ${CHECK_MARK} APK zip-alignment for 16KB boundaries (requires build-tools 35.0.0+)"
  echo -e "  ${CHECK_MARK} ELF segment alignment in native libraries (arm64-v8a and x86_64)"
  echo -e "  ${CHECK_MARK} Compliance with Android 16KB page size requirements"
  echo

  echo -e "${BOLD}RESULT MEANINGS:${ENDCOLOR}"
  echo -e "  ${GREEN}${CHECK_MARK} PASS${ENDCOLOR}  - Library is compatible with 16KB page sizes (2**14 or higher)"
  echo -e "  ${RED}${CROSS_MARK} FAIL${ENDCOLOR}  - Library needs recompilation with 16KB ELF alignment"
  echo -e "  ${YELLOW}${WARNING_MARK} WARN${ENDCOLOR}  - Non-critical architecture but should be fixed"
  echo
}

# Enhanced dependency checking
check_dependencies() {
  print_section "$GEAR" "Dependency Check" "Verifying required tools are available"

  local missing_tools=()
  local available_tools=()

  # First, try to set up NDK objdump if NDK path is available
  if [ -n "$NDK_PATH" ] && [ -d "$NDK_PATH" ]; then
    print_status "success" "Android NDK detected" "$NDK_PATH"
    
    # Try to find llvm-objdump in the NDK
    if [ -f "$NDK_PATH/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-objdump.exe" ]; then
      OBJDUMP="$NDK_PATH/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-objdump.exe"
      print_status "success" "Using NDK llvm-objdump" "$OBJDUMP"
    elif [ -f "$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump" ]; then
      OBJDUMP="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump"
      print_status "success" "Using NDK llvm-objdump" "$OBJDUMP"
    elif [ -f "$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-objdump" ]; then
      OBJDUMP="$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-objdump"
      print_status "success" "Using NDK llvm-objdump" "$OBJDUMP"
    fi
  fi

  # If NDK objdump not found, fall back to system objdump
  if [ -z "$OBJDUMP" ]; then
    if command -v objdump >/dev/null 2>&1; then
      OBJDUMP="objdump"
      print_status "warning" "Using system objdump (NDK version recommended)" "$(which objdump)"
    fi
  fi

  # Check other required tools
  local tools=("unzip" "file")
  for tool in "${tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      available_tools+=("$tool")
      print_status "success" "$tool" "$(which "$tool")"
    else
      missing_tools+=("$tool")
      print_status "error" "$tool not found"
    fi
  done

  # Check if we have objdump (either NDK or system)
  if [ -z "$OBJDUMP" ]; then
    print_status "error" "objdump not found"
    print_status "info" "Solution 1: Set ANDROID_NDK_HOME environment variable to your NDK path"
    print_status "info" "Solution 2: Install system objdump (binutils package)"
    print_status "info" "Recommended: Use Android NDK's llvm-objdump for accurate results"
    exit 1
  fi

  if [ ${#missing_tools[@]} -gt 0 ]; then
    echo
    print_subsection "Installation Instructions"
    for tool in "${missing_tools[@]}"; do
      case $tool in
        unzip)
          print_status "info" "Install unzip:" "Usually pre-installed on most systems"
          print_status "info" "" "Git Bash on Windows: comes with Git for Windows"
          print_status "info" "" "Linux: sudo apt-get install unzip"
          ;;
        file)
          print_status "info" "Install file:" "Usually pre-installed on most systems"
          print_status "info" "" "Git Bash on Windows: comes with Git for Windows"
          print_status "info" "" "Linux: sudo apt-get install file"
          ;;
      esac
      echo
    done
    exit 1
  fi

  print_status "success" "All dependencies satisfied" "$((${#available_tools[@]} + 1)) tools available"
}

# Validate input arguments
if [ ${#} -ne 1 ]; then
  usage
  exit 1
fi

case ${1} in
  --help | -h | -\?)
    usage
    exit 0
    ;;
  *)
    dir="${1}"
    ;;
esac

# Validate input file/directory
if ! [ -f "${dir}" -o -d "${dir}" ]; then
  print_status "error" "Invalid input: ${dir}"
  echo "  Please provide a valid APK file, APEX file, or directory containing native libraries."
  exit 1
fi

# Check dependencies before proceeding
check_dependencies

print_banner "ANALYSIS IN PROGRESS" "Checking 16KB Page Size Compatibility"

print_status "processing" "Target: $(basename "${dir}")"
print_status "info" "Compliance Deadline: November 1st, 2025"
print_status "info" "Requirement: Apps targeting Android 15+ must support 16KB pages"

# APK Processing
if [[ "${dir}" == *.apk ]]; then
  trap 'cleanup_trap' EXIT

  print_section "$PACKAGE" "APK Analysis" "Processing Android Package file"

  # Enhanced zipalign check
  if command -v zipalign >/dev/null 2>&1; then
    if { zipalign --help 2>&1 | grep -q "\-P <pagesize_kb>"; }; then
      print_status "processing" "Checking APK zip-alignment for 16KB boundaries..."

      zip_result=$(zipalign -v -c -P 16 4 "${dir}" 2>&1)
      zip_exit_code=$?

      if [ $zip_exit_code -eq 0 ]; then
        print_status "success" "APK zip-alignment verification passed"
      else
        print_status "error" "APK zip-alignment verification failed"
        echo "    ${DIM}Details:${ENDCOLOR}"
        echo "$zip_result" | grep -E 'lib/arm64-v8a|lib/x86_64|Verification|would be' | sed 's/^/      /' || echo "      $zip_result"
      fi
    else
      print_status "warning" "zipalign version doesn't support 16KB alignment checks"
      print_status "info" "Solution: Update to Android SDK build-tools 35.0.0+"
      echo "    ${DIM}Update via Android Studio → SDK Manager → SDK Tools${ENDCOLOR}"
      echo "    ${DIM}Or run: sdkmanager \"build-tools;35.0.0\"${ENDCOLOR}"
    fi
  else
    print_status "warning" "zipalign not found in PATH"
    print_status "info" "Ensure Android SDK build-tools are installed and in PATH"
  fi

  # Extract APK
  dir_filename=$(basename "${dir}")
  tmp=$(mktemp -d -t "${dir_filename%.apk}_out_XXXXX")

  if [ ! -d "${tmp}" ]; then
    print_status "error" "Failed to create temporary directory"
    exit 1
  fi

  print_status "processing" "Extracting native libraries from APK..."
  if ! unzip -q "${dir}" "lib/*" -d "${tmp}" 2>/dev/null; then
    print_summary_box "NO NATIVE LIBRARIES FOUND" "success" \
      "${PARTY} Your app contains only Java/Kotlin code!" \
      "" \
      "${CHECK_MARK} Apps without native libraries automatically support 16KB devices" \
      "${CHECK_MARK} No additional changes required for Google Play compliance" \
      "${CHECK_MARK} You're all set for the November 1st, 2025 deadline!"
    cleanup_trap 0
  fi

  dir="${tmp}"
fi

# APEX Processing
if [[ "${dir}" == *.apex ]]; then
  trap 'cleanup_trap' EXIT

  print_section "$DOCUMENT" "APEX Analysis" "Processing Android Pony EXpress file"

  if ! command -v deapexer >/dev/null 2>&1; then
    print_status "error" "deapexer tool not found"
    echo "    Please ensure Android SDK tools are properly installed and in your PATH."
    exit 1
  fi

  dir_filename=$(basename "${dir}")
  tmp=$(mktemp -d -t "${dir_filename%.apex}_out_XXXXX")

  if [ ! -d "${tmp}" ]; then
    print_status "error" "Failed to create temporary directory"
    exit 1
  fi

  print_status "processing" "Extracting APEX contents..."
  if ! deapexer extract "${dir}" "${tmp}"; then
    print_status "error" "Failed to extract APEX file"
    cleanup_trap 1
  fi

  dir="${tmp}"
fi

# Track libraries for enhanced summary
unaligned_libs=()
aligned_libs=()
critical_unaligned_libs=()
non_critical_unaligned_libs=()
total_libs=0
critical_libs=0

print_section "$GEAR" "ELF Segment Analysis" "Scanning native libraries for 16KB alignment compliance"

# Find all native libraries
matches="$(find "${dir}" -type f -name '*.so' 2>/dev/null)"
if [ -z "$matches" ]; then
  # Also check for ELF files without .so extension
  matches="$(find "${dir}" -type f -exec file {} \; 2>/dev/null | grep 'ELF' | cut -d: -f1)"
fi

if [ -z "$matches" ]; then
  print_summary_box "NO NATIVE LIBRARIES DETECTED" "success" \
    "${PARTY} Your app uses only Java/Kotlin code!" \
    "" \
    "${CHECK_MARK} No native library alignment issues to worry about" \
    "${CHECK_MARK} Already compatible with 16KB page size devices" \
    "${CHECK_MARK} Ready for Google Play's November 1st, 2025 requirement!"
  cleanup_trap 0
fi

print_status "info" "Found native libraries - analyzing ELF segment alignment..."

print_table_header

IFS=$'\n'
for match in $matches; do
  # Skip non-ELF files and nested packages
  if [[ "${match}" == *".apk" ]]; then
    continue
  fi
  if [[ "${match}" == *".apex" ]]; then
    continue
  fi

  # Verify it's actually an ELF file
  if ! [[ $(file "${match}" 2>/dev/null) == *"ELF"* ]]; then
    continue
  fi

  total_libs=$((total_libs + 1))

  # Determine architecture and criticality
  arch="unknown"
  is_critical="false"
  if [[ "${match}" == *"arm64-v8a"* ]]; then
    arch="arm64-v8a"
    is_critical="true"
    critical_libs=$((critical_libs + 1))
  elif [[ "${match}" == *"x86_64"* ]]; then
    arch="x86_64"
    is_critical="true"
    critical_libs=$((critical_libs + 1))
  elif [[ "${match}" == *"armeabi-v7a"* ]]; then
    arch="armeabi-v7a"
  elif [[ "${match}" == *"x86"* ]]; then
    arch="x86"
  fi

  # Check ELF segment alignment using NDK's objdump
  res="$("$OBJDUMP" -p "${match}" 2>/dev/null | grep LOAD | awk '{ print $NF }' | head -1)"

  if [ -z "$res" ]; then
    print_table_row "$(basename "${match}")" "$arch" "UNKNOWN" "FAILED" "$is_critical"
    continue
  fi

  # Check if alignment meets 16KB requirement (2**14 or higher)
  if [[ $res =~ 2\*\*(1[4-9]|[2-9][0-9]|[1-9][0-9]{2,}) ]]; then
    print_table_row "$(basename "${match}")" "$arch" "$res" "ALIGNED" "$is_critical"
    aligned_libs+=("${match}")
  else
    print_table_row "$(basename "${match}")" "$arch" "$res" "UNALIGNED" "$is_critical"
    unaligned_libs+=("${match}")

    if [[ "$is_critical" == "true" ]]; then
      critical_unaligned_libs+=("${match}")
    else
      non_critical_unaligned_libs+=("${match}")
    fi
  fi
done

print_table_footer

# Enhanced Summary Section
if [ ${#unaligned_libs[@]} -gt 0 ]; then
  # Failure case - unaligned libraries found
  summary_lines=(
    "${ALERT} ACTION REQUIRED: Unaligned native libraries detected!"
    ""
    "Analysis Results:"
    "  • Total libraries scanned: $total_libs"
    "  • Critical architectures (64-bit): $critical_libs"
    "  • Libraries aligned: ${#aligned_libs[@]}"
    "  • Libraries UNALIGNED: ${#unaligned_libs[@]}"
  )

  if [ ${#critical_unaligned_libs[@]} -gt 0 ]; then
    summary_lines+=("  • Critical failures: ${#critical_unaligned_libs[@]} (MUST FIX)")
  fi

  if [ ${#non_critical_unaligned_libs[@]} -gt 0 ]; then
    summary_lines+=("  • Non-critical warnings: ${#non_critical_unaligned_libs[@]} (SHOULD FIX)")
  fi

  summary_lines+=("")
  summary_lines+=("Google Play Compliance: FAILED")
  summary_lines+=("Deadline: November 1st, 2025")

  print_summary_box "COMPATIBILITY CHECK FAILED" "error" "${summary_lines[@]}"

  # Detailed library breakdown
  if [ ${#critical_unaligned_libs[@]} -gt 0 ]; then
    print_subsection "Critical Libraries Requiring Immediate Attention"
    for lib in "${critical_unaligned_libs[@]}"; do
      arch_type="64-bit"
      [[ "${lib}" == *"arm64-v8a"* ]] && arch_type="ARM64"
      [[ "${lib}" == *"x86_64"* ]] && arch_type="x86_64"
      print_status "error" "$(basename "$lib")" "$arch_type architecture - Required for Google Play"
    done
  fi

  if [ ${#non_critical_unaligned_libs[@]} -gt 0 ]; then
    print_subsection "Non-Critical Libraries (Recommended to Fix)"
    for lib in "${non_critical_unaligned_libs[@]}"; do
      arch_type="32-bit"
      [[ "${lib}" == *"armeabi-v7a"* ]] && arch_type="ARMv7"
      [[ "${lib}" == *"x86"* ]] && arch_type="x86"
      print_status "warning" "$(basename "$lib")" "$arch_type architecture"
    done
  fi

  # Comprehensive fix instructions
  print_section "$TOOLS" "How to Fix Unaligned Libraries" "Step-by-step guide to achieve 16KB compatibility"

  print_subsection "Step 1: Update Your Build Environment"
  print_status "info" "Android Gradle Plugin (AGP)" "Upgrade to version 8.5.1 or higher"
  print_status "info" "Android NDK" "Update to NDK r27 or higher (r28+ recommended)"
  print_status "info" "Build Tools" "Ensure Android SDK build-tools 35.0.0+ for zipalign"

  print_subsection "Step 2: Configure 16KB ELF Alignment"
  echo
  echo -e "${BOLD}For NDK r28 and newer:${ENDCOLOR}"
  print_status "success" "Automatic Support" "16KB alignment enabled by default - no changes needed!"

  echo
  echo -e "${BOLD}For NDK r27:${ENDCOLOR}"
  print_status "info" "Gradle Configuration" "Add to your app/build.gradle:"
  echo -e "${DIM}    android {"
  echo -e "        defaultConfig {"
  echo -e "            externalNativeBuild {"
  echo -e "                cmake {"
  echo -e "                    arguments '-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON'"
  echo -e "                }"
  echo -e "            }"
  echo -e "        }"
  echo -e "    }${ENDCOLOR}"

  print_status "info" "NDK-Build Configuration" "Add to Application.mk:"
  echo -e "${DIM}    APP_SUPPORT_FLEXIBLE_PAGE_SIZES := true${ENDCOLOR}"

  echo
  echo -e "${BOLD}For NDK r26 and older:${ENDCOLOR}"
  print_status "info" "Manual Linker Flags" "Add to your native build configuration:"
  echo -e "${DIM}    # For Android.mk:"
  echo -e "    LOCAL_LDFLAGS += \"-Wl,-z,max-page-size=16384\""
  echo
  echo -e "    # For CMakeLists.txt:"
  echo -e "    target_link_options(\${CMAKE_PROJECT_NAME} PRIVATE \"-Wl,-z,max-page-size=16384\")${ENDCOLOR}"

  print_subsection "Step 3: Update Library Packaging"
  print_status "info" "AGP 8.5.1+" "Uncompressed libraries used by default (no changes needed)"
  print_status "info" "Older AGP versions" "Add to app/build.gradle:"
  echo -e "${DIM}    android {"
  echo -e "        packagingOptions {"
  echo -e "            jniLibs {"
  echo -e "                useLegacyPackaging = true"
  echo -e "            }"
  echo -e "        }"
  echo -e "    }${ENDCOLOR}"

  print_subsection "Step 4: Build and Verify"
  print_status "processing" "Clean Build" "Run ./gradlew clean"
  print_status "processing" "Rebuild Project" "Run ./gradlew assembleRelease"
  print_status "processing" "Re-run This Script" "Verify all libraries are now aligned"
  print_status "processing" "Test on Device" "Use Android 15 emulator with 16KB system image"

  print_section "$BOOKS" "Additional Resources" "Learn more about 16KB page size support"
  print_status "info" "Official Guide" "https://developer.android.com/guide/practices/page-sizes"
  print_status "info" "NDK Documentation" "https://developer.android.com/ndk/guides/"
  print_status "info" "Testing Guide" "Use 'adb shell getconf PAGE_SIZE' (should return 16384)"
  print_status "info" "Emulator Setup" "Android 15 system images with 16KB page size"

  final_message=""
  if [ ${#critical_unaligned_libs[@]} -gt 0 ]; then
    final_message="CRITICAL: Fix required for Google Play compliance by November 1st, 2025!"
  else
    final_message="Warning: Non-critical issues found - recommended to fix for complete compatibility"
  fi

  print_summary_box "NEXT STEPS" "error" \
    "$final_message" \
    "" \
    "1. Update your build tools and NDK version" \
    "2. Apply the configuration changes above" \
    "3. Clean and rebuild your project" \
    "4. Run this script again to verify fixes" \
    "5. Test thoroughly on 16KB devices/emulator"

  cleanup_trap 1
else
  # Success case - all libraries aligned
  summary_lines=(
    "${PARTY} All native libraries are properly aligned!"
    ""
    "Analysis Results:"
    "  • Total libraries scanned: $total_libs"
    "  • Critical architectures: $critical_libs"
    "  • All libraries: ${#aligned_libs[@]}/${total_libs} ALIGNED"
    ""
    "Google Play Compliance: PASSED ${CHECK_MARK}"
    "Ready for November 1st, 2025 deadline!"
  )

  print_summary_box "COMPATIBILITY CHECK PASSED" "success" "${summary_lines[@]}"

  print_section "$ROCKET" "Next Steps" "Ensure complete 16KB compatibility"

  print_status "success" "Library Alignment" "All ELF segments properly aligned for 16KB pages"
  print_status "info" "Runtime Testing" "Test on Android 15 emulator with 16KB system image"
  print_status "info" "Code Review" "Check for hardcoded PAGE_SIZE dependencies in your code"
  print_status "info" "Third-party SDKs" "Verify all dependencies are 16KB compatible"
  print_status "info" "Zipalign Verification" "Run: zipalign -c -P 16 -v 4 your-app.apk"

  print_subsection "Testing Commands"
  echo -e "${DIM}  # Verify page size on device/emulator${ENDCOLOR}"
  echo -e "${DIM}  adb shell getconf PAGE_SIZE    # Should return: 16384${ENDCOLOR}"
  echo
  echo -e "${DIM}  # Verify APK alignment${ENDCOLOR}"
  echo -e "${DIM}  zipalign -c -P 16 -v 4 app-release.apk${ENDCOLOR}"

  print_summary_box "CONGRATULATIONS!" "success" \
    "${PARTY} Your app is 16KB page size compatible!" \
    "" \
    "${CHECK_MARK} All native libraries meet Google Play requirements" \
    "${CHECK_MARK} Ready for devices with 16KB page sizes" \
    "${CHECK_MARK} Compliant with November 1st, 2025 deadline" \
    "" \
    "Recommendation: Test thoroughly on 16KB environment to ensure" \
    "no runtime issues exist in your application code."
fi

echo
print_status "info" "Analysis completed at $(date)"
echo