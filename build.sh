#!/bin/bash
#
# Compile script for Mimir kernel
# Copyright (C) 2026 Vhmit.

# Colors
NC='\033[0m'
RED='\033[0;31m'
LRD='\033[1;31m'
LGR='\033[1;32m'
YLW='\033[0;33m'

# Trap for Ctrl+C
handle_interrupt() {
    echo -e "\n${YLW}Build interrupted by user. Exiting...${NC}"
    if [ ! -z "$GITHUB_ENV" ]; then
        DIFF=$SECONDS
        TIME_INT="$((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)"
        echo "BUILD_DURATION=$TIME_INT" >> "$GITHUB_ENV"
    fi
    exit 130
}
trap handle_interrupt SIGINT

# Device
DEVICE="$1"
ZIP_FLAG="$2"

# Output usage help
if [ -z "$DEVICE" ]; then
  echo -e "${RED}Error: No device specified!${NC}"
  echo -e "Usage: ./build.sh <device_name> [-z]"
  echo -e "Example: ./build.sh device (just compiles)"
  echo -e "Example: ./build.sh device -z (compiles and generates the zip file.)"
  exit 1
fi

# Dependency Check
check_deps() {
    echo -e "${YLW}########### Checking Dependencies ############${NC}"
    local deps=("zip" "curl" "git" "make" "python3" "sha256sum" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}Error: $dep is not installed. Please install it to continue.${NC}"
            exit 1
        fi
    done

    # Check for 'python' command (needed for the GCC wrapper)
    if ! command -v python &> /dev/null; then
        echo -e "${YLW}Warning: 'python' command not found. Creating local symlink to python3...${NC}"
        mkdir -p "/tmp/bin"
        ln -sf "$(command -v python3)" "/tmp/bin/python"
        export PATH="/tmp/bin:$PATH"
    fi
    echo -e "${LGR}Dependencies: OK!${NC}"
}

# Date
TM=$(date '+%Y%m%d-%H%M')

kernel_dir="${PWD}"
objdir="${kernel_dir}/out"
anykernel=$HOME/anykernel
toolchain_dir="${kernel_dir}/gcc"
kernel_name="Mimir"
zip_name="$kernel_name-${DEVICE}-${TM}.zip"
LOG_FILE="${PWD}/build_log.txt"

# Export current branch name to GitHub Actions
if [ ! -z "$GITHUB_ENV" ]; then
    echo "BUILD_BRANCH=${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD)}" >> "$GITHUB_ENV"
fi

# Compiler Setup (GCC)
export PATH="$toolchain_dir/bin:$PATH"
if ! [ -d "$toolchain_dir" ]; then
    echo "GCC not found! Cloning to $toolchain_dir..."
    if ! git clone --depth=1 --single-branch -b 4.9.x-2015 https://github.com/Vhmit/platform_prebuilts_gcc "$toolchain_dir"; then
        echo "Cloning failed! Aborting..."
        exit 1
    fi
fi

echo -e "${LGR}######### Compiler Version #########${NC}"
GCC_FULL=$($toolchain_dir/bin/aarch64-linux-android-gcc --version 2>&1 | head -n 1)
GCC_FINAL=$(echo "$GCC_FULL" | sed 's/^[^(]*//')
[ -z "$GCC_FINAL" ] && GCC_FINAL="$GCC_FULL"
echo -e "${YLW}Using: ${GCC_FINAL}${NC}"
[ ! -z "$GITHUB_ENV" ] && echo "TOOLCHAIN_VERSION=$GCC_FINAL" >> "$GITHUB_ENV"

# Exports
export CONFIG_FILE="${DEVICE}_defconfig"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_HOST=viktor
export KBUILD_BUILD_USER=vhmit
export CROSS_COMPILE="${toolchain_dir}/bin/aarch64-linux-android-"
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export CC="${toolchain_dir}/bin/aarch64-linux-android-gcc"

clean_all() {
    echo -e "${YLW}########### Cleaning Output Directory ############${NC}"
    rm -rf "${objdir}" "$LOG_FILE" *.zip
}

make_defconfig() {
    SECONDS=0
    echo -e "${LGR}########### Generating Defconfig ############${NC}"
    # English: Ensure the config file exists before trying to make
    if [ ! -f "arch/arm64/configs/${DEVICE}_defconfig" ]; then
        echo -e "${RED}Error: ${DEVICE}_defconfig not found!${NC}"
        exit 1
    fi
    make -s O="${objdir}" ARCH=$ARCH CC=$CC CROSS_COMPILE=$CROSS_COMPILE CROSS_COMPILE_ARM32=$CROSS_COMPILE_ARM32 ${DEVICE}_defconfig -j$(nproc --all)
}

compile() {
    echo -e "${LGR}########### Compiling kernel ############${NC}"
    local TEMP_LOG=$(mktemp)
    set -o pipefail
    make -j$(nproc --all) O="${objdir}" ARCH=${ARCH} CC=${CC} CROSS_COMPILE=$CROSS_COMPILE CROSS_COMPILE_ARM32=$CROSS_COMPILE_ARM32 KCFLAGS="-fno-use-linker-plugin" HOSTCFLAGS="-fcommon" 2>&1 | tee "$TEMP_LOG"

    local exit_status=$?
    set +o pipefail

    # Captures the error status for manual handling if necessary.
    if [ $exit_status -ne 0 ]; then
        [ $exit_status -eq 130 ] && exit 130
        echo -e "${RED}Error: Compilation failed! Generating log...${NC}"
        mv "$TEMP_LOG" "$LOG_FILE"
        RESPONSE=$(curl -s -F "content=@$LOG_FILE" https://bin.cyberknight777.dev)
        if [[ "$RESPONSE" == *"bin.cyberknight777.dev"* ]]; then
            echo -e "${YLW}Rustbin Log: ${LGR}${RESPONSE}${NC}"
            [ ! -z "$GITHUB_ENV" ] && echo "ERROR_LOG_URL=$RESPONSE" >> "$GITHUB_ENV"
            rm -f "$LOG_FILE"
        else
            echo -e "${RED}Upload Failed! Check the build_log.txt locally.${NC}"
        fi
        exit $exit_status
    else
        rm -f "$TEMP_LOG"
        echo -e "${LGR}Kernel compiled successfully!${NC}"
    fi
}

completion() {
        LOCAL_BOOT="${objdir}/arch/arm64/boot"
    if [[ -f "${LOCAL_BOOT}/Image.gz-dtb" ]]; then
        echo -e "${LGR}######### Packaging AnyKernel3 #########${NC}"
        rm -rf "$anykernel"
        git clone --depth=1 --single-branch https://github.com/Vhmit/AnyKernel3.git -b "${DEVICE}-q" "$anykernel"
        cp -f "${LOCAL_BOOT}/Image.gz-dtb" "$anykernel/"
        cd "$anykernel" || exit 1
        zip -r9 AnyKernel.zip * -x .git README.md *placeholder
        cp AnyKernel.zip "$kernel_dir/$zip_name"
        cd "$kernel_dir" || exit 1
        rm -rf "$anykernel"

        echo -e "${LGR}#############################################${NC}"
        echo -e "${LGR}####### Kernel packaged successfully! #######${NC}"
        echo -e "${LGR}#############################################${NC}"

	# Generation SHA256
        echo -e "${YLW}Generating SHA256 checksum...${NC}"
        SHA256=$(sha256sum "$zip_name" | awk '{print $1}')
        [ ! -z "$GITHUB_ENV" ] && echo "ZIP_SHA256=$SHA256" >> "$GITHUB_ENV"

        # Upload to Gofile
        if [ "$UPLOAD_TARGET" != "github" ]; then
            echo -e "${YLW}Checking Gofile status...${NC}"
            SERVER=$(curl -s https://api.gofile.io/servers | jq -r '.data.servers[0].name // "store1"')
            [ ! -z "$GITHUB_ENV" ] && echo "GOFILE_SERVER=$SERVER" >> "$GITHUB_ENV"
            echo -e "${YLW}Uploading ZIP to ${SERVER}...${NC}"
            RESPONSE=$(curl -# -L -F "file=@$zip_name" "https://${SERVER}.gofile.io/contents/uploadfile")

            # Validation
            if echo "$RESPONSE" | jq -e '.status == "ok"' >/dev/null 2>&1; then
                DOWNLOAD_LINK=$(echo "$RESPONSE" | jq -r '.data.downloadPage')
                echo -e "${LGR}Download Link: ${NC}${DOWNLOAD_LINK}"
                echo -e "${YLW}SHA256 Checksum: ${NC}${SHA256}"
                [ ! -z "$GITHUB_ENV" ] && echo "ZIP_DOWNLOAD_LINK=$DOWNLOAD_LINK" >> "$GITHUB_ENV"
            else
                echo -e "${RED}Upload failed!${NC}"
                [ ! -z "$GITHUB_ENV" ] && echo "ZIP_DOWNLOAD_LINK=" >> "$GITHUB_ENV"
            fi
        else
            echo -e "${LGR}Target is GitHub Release. Skipping Gofile upload...${NC}"
        fi
    fi
}

# Execution
check_deps
clean_all
SECONDS=0
make_defconfig
compile

# Time build
DIFF=$SECONDS
BUILD_TIME="$((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)"
[ ! -z "$GITHUB_ENV" ] && echo "BUILD_DURATION=$BUILD_TIME" >> "$GITHUB_ENV"

# Only run completion (AnyKernel3) if the -z flag is present
if [ -f "${objdir}/arch/arm64/boot/Image.gz-dtb" ]; then
    if [ "$ZIP_FLAG" == "-z" ]; then
        completion
    else
        echo -e "\n${YLW}Info: Flag -z not detected. Compilation finished without generating ZIP.${NC}"
        echo -e "The generated files are located in: ${objdir}/arch/arm64/boot/"
    fi

    echo -e "\n${LGR}-------------------------------------------------------"
    echo -e "Completed successfully in: $BUILD_TIME"
    echo -e "-------------------------------------------------------${NC}"
else
    echo -e "\n${RED}#############################################${NC}"
    echo -e "${RED}######## Kernel compilation failed! ########${NC}"
    echo -e "Elapsed time: $BUILD_TIME"
    echo -e "${RED}#############################################${NC}"
    exit 1
fi

cd "${kernel_dir}" || exit 1
