#! /bin/bash

set -eux

setup_export() {
    export KERNEL_PATH=$PWD
    export CLANG_PATH=~/toolchains/neutron-clang
    export PATH=${CLANG_PATH}/bin:${PATH}
    export CLANG_TRIPLE=aarch64-linux-gnu-
    export ARCH=arm64
    export SUBARCH=arm64
    export KERNEL_CONFIG=vendor/lahaina-qgki_defconfig
    export ROM_DLKM=pixelos_dlkm
    export SETUP_KERNELSU=true
    export REPACK_DLKM=false
}

update_kernel() {
    cd $KERNEL_PATH
    git stash
    git pull
}

setup_environment() {
    cd $KERNEL_PATH
    sudo pacman -S zstd tar wget curl base-devel --noconfirm
    wget -O ./lib32-ncurses.pkg.tar.zst https://archlinux.org/packages/multilib/x86_64/lib32-ncurses/download/
    wget -O ./lib32-readline.pkg.tar.zst https://archlinux.org/packages/multilib/x86_64/lib32-readline/download/
    wget -O ./lib32-zlib.pkg.tar.zst https://archlinux.org/packages/multilib/x86_64/lib32-zlib/download/
    sudo pacman -U ./lib32-ncurses.pkg.tar.zst ./lib32-readline.pkg.tar.zst ./lib32-zlib.pkg.tar.zst --noconfirm
    rm ./*.zst
    yay -S lineageos-devel python2-bin --noconfirm
    if [ ! -d $CLANG_PATH ]; then
      mkdir -p $CLANG_PATH
      cd $CLANG_PATH
      bash <(curl -s "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman") -S
    fi
}

setup_kernelsu() {
    cd $KERNEL_PATH
    git submodule init && git submodule update --remote
    cd KernelSU && git pull
    cd $KERNEL_PATH
}

build_kernel() {
    cd $KERNEL_PATH
    make O=out CC="ccache clang" CXX="ccache clang++" ARCH=arm64 CROSS_COMPILE=$CLANG_PATH/bin/aarch64-linux-gnu- CROSS_COMPILE_ARM32=$CLANG_PATH/bin/arm-linux-gnueabi- LD=ld.lld $KERNEL_CONFIG
    # Delete old files
    test -d $KERNEL_PATH/out/arch/arm64/boot && rm -rf $KERNEL_PATH/out/arch/arm64/boot/*
    # Begin compile
    time make O=out CC="ccache clang" CXX="ccache clang++" ARCH=arm64 -j`nproc` CROSS_COMPILE=$CLANG_PATH/bin/aarch64-linux-gnu- CROSS_COMPILE_ARM32=$CLANG_PATH/bin/arm-linux-gnueabi- LD=ld.lld 2>&1 | tee kernel.log
}

repack_vendor_dlkm() {
    cd $KERNEL_PATH
    test -d Guide || git clone -b main https://github.com/natsumerinchan/KernelSU_Oneplus_martini_Guide.git Guide
    cd Guide
    export GITHUB_WORKSPACE=$PWD
    test -d repacker || git clone -b main https://github.com/natsumerinchan/vendor_dlkm_repacker.git repacker
    cd $GITHUB_WORKSPACE/repacker
    test -d vendor_dlkm && rm -rf vendor_dlkm
    cp -r $GITHUB_WORKSPACE/$ROM_DLKM $GITHUB_WORKSPACE/repacker/vendor_dlkm
    # Copy *.ko files from out/
    find $KERNEL_PATH/out/ -name "*.ko" -exec cp \{\} $GITHUB_WORKSPACE/repacker/vendor_dlkm/lib/modules/ \;
    # Rename wlan module
    mv $GITHUB_WORKSPACE/repacker/vendor_dlkm/lib/modules/wlan.ko $GITHUB_WORKSPACE/repacker/vendor_dlkm/lib/modules/qca_cld3_wlan.ko
    # Repack vendor_dlkm.img now
    sudo bash ./repack_dlkm.sh vendor_dlkm
    mv ./vendor_dlkm-ext4.img $KERNEL_PATH/out/arch/arm64/boot/vendor_dlkm.img
}

make_anykernel3_zip() {
    cd $KERNEL_PATH
    test -d $KERNEL_PATH/AnyKernel3 || git clone -b martini https://github.com/natsumerinchan/AnyKernel3-op9rt.git AnyKernel3
    if test -e $KERNEL_PATH/out/arch/arm64/boot/Image && test -d $KERNEL_PATH/AnyKernel3; then
       cd $KERNEL_PATH/AnyKernel3
       cp $KERNEL_PATH/out/arch/arm64/boot/Image $KERNEL_PATH/AnyKernel3
       zip -r Kernel-op9rt.zip *
       # Sign zip file
       java -jar ./tools/zipsigner.jar ./Kernel-op9rt.zip ./Kernel-op9rt-signed.zip
       rm ./Kernel-op9rt.zip ./Image
       mv ./Kernel-op9rt-signed.zip $KERNEL_PATH/out/arch/arm64/boot
       cd $KERNEL_PATH
    fi
}

setup_export

# update_kernel   //Please uncomment if you need it

if test -e $CLANG_PATH/env_is_setup; then
   echo [INFO]Environment have been setup!
else
   setup_environment
   touch $CLANG_PATH/env_is_setup
fi

if test "$SETUP_KERNELSU" == "true"; then
   setup_kernelsu
else
   echo [INFO] KernelSU will not be Compiled
   grep -q "kernelsu" $KERNEL_PATH/drivers/Makefile && sed -i '/kernelsu/d' $KERNEL_PATH/drivers/Makefile
fi

build_kernel

if test "$REPACK_DLKM" == "true"; then
   repack_vendor_dlkm
fi

make_anykernel3_zip
cd $KERNEL_PATH
echo [INFO] Products are put in $KERNEL_PATH/out/arch/arm64/boot
echo [INFO] Done.
