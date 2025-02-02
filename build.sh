#!/bin/bash
#
# Compile script for Supra kernel
# Copyright (C) 2020-2025 Adithya R. and Contributors

SECONDS=0 # builtin bash timer
SUPPORTED_DEVICES=(channel ocean river)

if [[ -n "$1" && " ${SUPPORTED_DEVICES[@]} " =~ " $1 " ]]; then
    DEVICE="$1"
    echo -e "\nDevice selected: $DEVICE"
else
    echo -e "\nSelect the device to compile:"
    select DEVICE in "${SUPPORTED_DEVICES[@]}"; do
        if [[ " ${SUPPORTED_DEVICES[@]} " =~ " ${DEVICE} " ]]; then
            break
        else
            echo -e "\nInvalid option. Please choose again."
        fi
    done
fi

ZIPNAME="Supra-${DEVICE}-$(date '+%Y%m%d-%H%M').zip"
TC_DIR="$(pwd)/tc/clang-r522817"
AK3_DIR="$(pwd)/android/AnyKernel3"
DEFCONFIG="${DEVICE}_defconfig"

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
	ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8).zip"
fi

export PATH="$TC_DIR/bin:$PATH"

if ! [ -d "$TC_DIR" ]; then
	echo "AOSP clang not found! Cloning to $TC_DIR..."
	if ! git clone --depth=1 -b 18 https://gitlab.com/ThankYouMario/android_prebuilts_clang-standalone "$TC_DIR"; then
		echo "Cloning failed! Aborting..."
		exit 1
	fi
fi

if [[ $2 = "-r" || $2 = "--regen" ]]; then
	make O=out ARCH=arm64 $DEFCONFIG savedefconfig
	cp out/defconfig arch/arm64/configs/$DEFCONFIG
	echo -e "\nDefconfig successfully regenerated at $DEFCONFIG"
	exit
fi

if [[ $2 = "-rf" || $2 = "--regen-full" ]]; then
	make O=out ARCH=arm64 $DEFCONFIG
	cp out/.config arch/arm64/configs/$DEFCONFIG
	echo -e "\nFull defconfig successfully regenerated at $DEFCONFIG"
	exit
fi

if [[ $2 = "-c" || $2 = "--clean" ]]; then
	rm -rf out
fi

mkdir -p out
make O=out ARCH=arm64 $DEFCONFIG

echo -e "\nStarting compilation...\n"
make -j$(nproc --all) O=out ARCH=arm64 CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- LLVM=1 LLVM_IAS=1 Image.gz

kernel="out/arch/arm64/boot/Image.gz"

if [ -f "$kernel" ]; then
	echo -e "\nKernel compiled successfully! Preparing zip...\n"
	if [ -d "$AK3_DIR" ]; then
		cp -r $AK3_DIR AnyKernel3
	elif ! git clone -q https://github.com/Bomb-Projects/AnyKernel3 -b $DEVICE; then
		echo -e "\nAnyKernel3 repo not found locally and failed to clone from GitHub! Aborting..."
		exit 1
	fi
	cp $kernel AnyKernel3
	rm -rf out/arch/arm64/boot
	cd AnyKernel3
	git checkout $DEVICE &> /dev/null
	zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
	cd ..
	rm -rf AnyKernel3
	echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)!"
	echo "Zip: $ZIPNAME"
else
	echo -e "\nCompilation failed!"
	exit 1
fi
