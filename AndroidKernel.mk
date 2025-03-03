#Android makefile to build kernel as a part of Android Build
PERL		= perl

KERNEL_TARGET := $(strip $(INSTALLED_KERNEL_TARGET))
ifeq ($(KERNEL_TARGET),)
INSTALLED_KERNEL_TARGET := $(PRODUCT_OUT)/kernel
endif

INSTALLED_KERNEL_VM_TARGET := $(PRODUCT_OUT)/kernel_vm

TARGET_KERNEL_MAKE_ENV := $(strip $(TARGET_KERNEL_MAKE_ENV))
ifeq ($(TARGET_KERNEL_MAKE_ENV),)
KERNEL_MAKE_ENV :=
else
KERNEL_MAKE_ENV := $(TARGET_KERNEL_MAKE_ENV)
endif

TARGET_KERNEL_ARCH := $(strip $(TARGET_KERNEL_ARCH))
ifeq ($(TARGET_KERNEL_ARCH),)
KERNEL_ARCH := arm
else
KERNEL_ARCH := $(TARGET_KERNEL_ARCH)
endif

TARGET_KERNEL_HEADER_ARCH := $(strip $(TARGET_KERNEL_HEADER_ARCH))
ifeq ($(TARGET_KERNEL_HEADER_ARCH),)
KERNEL_HEADER_ARCH := $(KERNEL_ARCH)
else
$(warning Forcing kernel header generation only for '$(TARGET_KERNEL_HEADER_ARCH)')
KERNEL_HEADER_ARCH := $(TARGET_KERNEL_HEADER_ARCH)
endif

# Force 32-bit binder IPC for 64bit kernel with 32bit userspace
ifeq ($(KERNEL_ARCH),arm64)
ifeq ($(TARGET_ARCH),arm)
KERNEL_CONFIG_OVERRIDE := CONFIG_ANDROID_BINDER_IPC_32BIT=y
endif
endif

TARGET_KERNEL_CROSS_COMPILE_PREFIX := $(strip $(TARGET_KERNEL_CROSS_COMPILE_PREFIX))
ifeq ($(TARGET_KERNEL_CROSS_COMPILE_PREFIX),)
KERNEL_CROSS_COMPILE := arm-eabi-
else
KERNEL_CROSS_COMPILE := $(TARGET_KERNEL_CROSS_COMPILE_PREFIX)
endif

ifeq ($(KERNEL_LLVM_SUPPORT), true)
  ifeq ($(KERNEL_SD_LLVM_SUPPORT), true)  #Using sd-llvm compiler
    ifeq ($(shell echo $(SDCLANG_PATH) | head -c 1),/)
       KERNEL_LLVM_BIN := $(SDCLANG_PATH)/clang
    else
       KERNEL_LLVM_BIN := $(shell pwd)/$(SDCLANG_PATH)/clang
    endif
    $(warning "Using sdllvm" $(KERNEL_LLVM_BIN))
  else
     KERNEL_LLVM_BIN := $(shell pwd)/$(CLANG) #Using aosp-llvm compiler
    $(warning "Using aosp-llvm" $(KERNEL_LLVM_BIN))
  endif
endif

ifeq ($(TARGET_PREBUILT_KERNEL),)

KERNEL_GCC_NOANDROID_CHK := $(shell (echo "int main() {return 0;}" | $(KERNEL_CROSS_COMPILE)gcc -E -mno-android - > /dev/null 2>&1 ; echo $$?))

real_cc :=
ifeq ($(KERNEL_LLVM_SUPPORT),true)
  ifeq ($(KERNEL_ARCH), arm64)
    real_cc := CC=$(KERNEL_LLVM_BIN) CLANG_TRIPLE=aarch64-linux-gnu-
  else
    real_cc := CC=$(KERNEL_LLVM_BIN) CLANG_TRIPLE=arm-linux-gnueabihf
  endif
else
ifeq ($(strip $(KERNEL_GCC_NOANDROID_CHK)),0)
KERNEL_CFLAGS := KCFLAGS=-mno-android
endif
endif

mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
current_dir := $(notdir $(patsubst %/,%,$(dir $(mkfile_path))))
TARGET_KERNEL := msm-$(TARGET_KERNEL_VERSION)
ifeq ($(TARGET_KERNEL),$(current_dir))
    # New style, kernel/msm-version
    BUILD_ROOT_LOC := ../../
    TARGET_KERNEL_SOURCE := kernel/$(TARGET_KERNEL)
    KERNEL_OUT := $(TARGET_OUT_INTERMEDIATES)/kernel/$(TARGET_KERNEL)
    KERNEL_SYMLINK := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ
    KERNEL_USR := $(KERNEL_SYMLINK)/usr
    KERNEL_VM_OUT := $(TARGET_OUT_INTERMEDIATES)/kernel_vm/$(TARGET_KERNEL)
    KERNEL_VM_SYMLINK := $(TARGET_OUT_INTERMEDIATES)/KERNEL_VM_OBJ
    KERNEL_VM_USR := $(KERNEL_VM_SYMLINK)/usr
else
    # Legacy style, kernel source directly under kernel
    KERNEL_LEGACY_DIR := true
    BUILD_ROOT_LOC := ../
    TARGET_KERNEL_SOURCE := kernel
    KERNEL_OUT := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ
    KERNEL_VM_OUT := $(TARGET_OUT_INTERMEDIATES)/KERNEL_VM_OBJ
endif

KERNEL_CONFIG := $(KERNEL_OUT)/.config

ifeq ($(KERNEL_DEFCONFIG)$(wildcard $(KERNEL_CONFIG)),)
$(error Kernel configuration not defined, cannot build kernel)
else

ifeq ($(TARGET_USES_UNCOMPRESSED_KERNEL),true)
$(info Using uncompressed kernel)
TARGET_PREBUILT_INT_KERNEL_ := arch/$(KERNEL_ARCH)/boot/Image
else
ifeq ($(KERNEL_ARCH),arm64)
TARGET_PREBUILT_INT_KERNEL_ := arch/$(KERNEL_ARCH)/boot/Image.gz
else
TARGET_PREBUILT_INT_KERNEL_ := arch/$(KERNEL_ARCH)/boot/zImage
endif
endif

ifeq ($(TARGET_KERNEL_APPEND_DTB), true)
$(info Using appended DTB)
TARGET_PREBUILT_INT_KERNEL_ := $(TARGET_PREBUILT_INT_KERNEL_)-dtb
else
$(info Using DTB Image)
INSTALLED_DTBIMAGE_TARGET := $(PRODUCT_OUT)/dtb.img
endif

# Creating a dtb.img once the kernel is compiled if TARGET_KERNEL_APPEND_DTB is set to be false
$(INSTALLED_DTBIMAGE_TARGET): $(INSTALLED_KERNEL_TARGET)
	cat $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/dts/qcom/*.dtb > $@

KERNEL_HEADERS_INSTALL := $(KERNEL_OUT)/usr
KERNEL_MODULES_INSTALL ?= system
KERNEL_MODULES_OUT ?= $(PRODUCT_OUT)/$(KERNEL_MODULES_INSTALL)/lib/modules

TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/$(TARGET_PREBUILT_INT_KERNEL_)
TARGET_PREBUILT_KERNEL := $(TARGET_PREBUILT_INT_KERNEL)

KERNEL_VM_CONFIG := $(KERNEL_VM_OUT)/.config
KERNEL_VM_HEADERS_INSTALL := $(KERNEL_VM_OUT)/usr
TARGET_PREBUILT_INT_KERNEL_VM := $(KERNEL_VM_OUT)/$(TARGET_PREBUILT_INT_KERNEL_)
TARGET_PREBUILT_KERNEL_VM := $(TARGET_PREBUILT_INT_KERNEL_VM)

define mv-modules
mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.dep`;\
if [ "$$mdpath" != "" ];then\
mpath=`dirname $$mdpath`;\
ko=`find $$mpath/kernel -type f -name *.ko`;\
for i in $$ko; do mv $$i $(KERNEL_MODULES_OUT)/; done;\
fi
endef

define clean-module-folder
mdpath=`find $(KERNEL_MODULES_OUT) -type f -name modules.dep`;\
if [ "$$mdpath" != "" ];then\
mpath=`dirname $$mdpath`; rm -rf $$mpath;\
fi
endef

$(TARGET_PREBUILT_INT_KERNEL_VM): ;

ifneq ($(KERNEL_LEGACY_DIR),true)
$(KERNEL_USR): $(KERNEL_HEADERS_INSTALL)
	rm -rf $(KERNEL_SYMLINK)
	ln -s kernel/$(TARGET_KERNEL) $(KERNEL_SYMLINK)

$(TARGET_PREBUILT_INT_KERNEL): $(KERNEL_USR)

ifneq ($(KERNEL_VM_DEFCONFIG),)
$(KERNEL_VM_USR): $(KERNEL_VM_HEADERS_INSTALL)
	rm -rf $(KERNEL_VM_SYMLINK);
	ln -s kernel_vm/$(TARGET_KERNEL) $(KERNEL_VM_SYMLINK);

$(TARGET_PREBUILT_INT_KERNEL_VM): $(KERNEL_VM_USR)
endif
endif

ifneq ($(KERNEL_VM_DEFCONFIG),)
$(KERNEL_VM_OUT):
	mkdir -p $(KERNEL_VM_OUT);

$(KERNEL_VM_CONFIG): $(KERNEL_VM_OUT)
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_VM_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_VM_DEFCONFIG);
	if [ ! -z "$(KERNEL_CONFIG_OVERRIDE)" ]; then \
		echo "Overriding kernel config with '$(KERNEL_CONFIG_OVERRIDE)'"; \
		echo $(KERNEL_CONFIG_OVERRIDE) >> $(KERNEL_VM_OUT)/.config; \
		$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_VM_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) oldconfig; fi;

$(TARGET_PREBUILT_INT_KERNEL_VM): $(KERNEL_VM_OUT) $(KERNEL_VM_HEADERS_INSTALL)
	echo "Building vm kernel...";
	rm -rf $(KERNEL_VM_OUT)/arch/$(KERNEL_ARCH)/boot/dts;
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_VM_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_CFLAGS);

$(KERNEL_VM_HEADERS_INSTALL): $(KERNEL_VM_OUT)
	rm -f $(BUILD_ROOT_LOC)$(KERNEL_VM_CONFIG);
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_VM_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_HEADER_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_VM_DEFCONFIG);
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_VM_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_HEADER_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) headers_install;
	if [ -d "$(KERNEL_VM_HEADERS_INSTALL)/include/bringup_headers" ]; then \
		cp -Rf  $(KERNEL_VM_HEADERS_INSTALL)/include/bringup_headers/* $(KERNEL_VM_HEADERS_INSTALL)/include/ ; fi ;
	if [ ! -z "$(KERNEL_CONFIG_OVERRIDE)" ]; then \
		echo $(KERNEL_CONFIG_OVERRIDE) >> $(KERNEL_VM_OUT)/.config; \
		$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_VM_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) oldconfig; fi;
endif

include $(TARGET_KERNEL_SOURCE)/defconfig.mk

KERNEL_HEADER_DEFCONFIG := $(strip $(KERNEL_HEADER_DEFCONFIG))
ifeq ($(KERNEL_HEADER_DEFCONFIG),)
KERNEL_HEADER_DEFCONFIG := $(TARGET_DEFCONFIG)
endif

# Make the kernel config
#   $1 output dir
#   $2 kernel config filepath
#   $3 defconfig
#   $4 kernel source
#   $5 kernel make env
#   $6 kernel architecture
#   $7 cross compile sub-command
#   $8 make command
define do-kernel-config
	( cp $(3) $(2) && $(8) -C $(4) O=$(1) $(5) ARCH=$(6) CROSS_COMPILE=$(7) defoldconfig ) || ( rm -f $(2) && false )
endef

$(KERNEL_OUT):
	mkdir -p $(KERNEL_OUT)

$(KERNEL_CONFIG): $(KERNEL_OUT) $(TARGET_DEFCONFIG)
	$(call do-kernel-config,$(BUILD_ROOT_LOC)$(KERNEL_OUT),$@,$(TARGET_DEFCONFIG),$(TARGET_KERNEL_SOURCE),$(KERNEL_MAKE_ENV),$(KERNEL_ARCH),$(KERNEL_CROSS_COMPILE),$(MAKE))
	$(hide) if [ ! -z "$(KERNEL_CONFIG_OVERRIDE)" ]; then \
			echo "Overriding kernel config with '$(KERNEL_CONFIG_OVERRIDE)'"; \
			echo $(KERNEL_CONFIG_OVERRIDE) >> $(KERNEL_OUT)/.config; \
			$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) oldconfig; fi

ifeq ($(TARGET_KERNEL_APPEND_DTB), true)
TARGET_PREBUILT_INT_KERNEL_IMAGE := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/Image
$(TARGET_PREBUILT_INT_KERNEL_IMAGE): $(KERNEL_USR)
$(TARGET_PREBUILT_INT_KERNEL_IMAGE): $(KERNEL_OUT) $(KERNEL_CONFIG) $(KERNEL_HEADERS_INSTALL)
	$(hide) echo "Building kernel modules..."
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_CFLAGS) Image
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_CFLAGS) modules
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) INSTALL_MOD_PATH=$(BUILD_ROOT_LOC)../$(KERNEL_MODULES_INSTALL) INSTALL_MOD_STRIP=1 $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) modules_install
	$(mv-modules)
	$(clean-module-folder)

$(TARGET_PREBUILT_INT_KERNEL): $(TARGET_PREBUILT_INT_KERNEL_IMAGE)
	$(hide) echo "Building kernel..."
	$(hide) rm -rf $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/dts
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_CFLAGS)
else
TARGET_PREBUILT_INT_KERNEL_IMAGE := $(TARGET_PREBUILT_INT_KERNEL)
$(TARGET_PREBUILT_INT_KERNEL): $(KERNEL_OUT) $(KERNEL_HEADERS_INSTALL)
	$(hide) echo "Building kernel..."
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_CFLAGS)
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) $(KERNEL_CFLAGS) modules
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) INSTALL_MOD_PATH=$(BUILD_ROOT_LOC)../$(KERNEL_MODULES_INSTALL) INSTALL_MOD_STRIP=1 $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) modules_install
	$(mv-modules)
	$(clean-module-folder)
endif

$(KERNEL_HEADERS_INSTALL): $(KERNEL_OUT) $(KERNEL_CONFIG)
	$(hide) if [ ! -z "$(KERNEL_HEADER_DEFCONFIG)" ]; then \
			rm -f $(BUILD_ROOT_LOC)$(KERNEL_CONFIG); \
			$(call do-kernel-config,$(BUILD_ROOT_LOC)$(KERNEL_OUT),$(KERNEL_CONFIG),$(KERNEL_HEADER_DEFCONFIG),$(TARGET_KERNEL_SOURCE),$(KERNEL_MAKE_ENV),$(KERNEL_ARCH),$(KERNEL_CROSS_COMPILE),$(MAKE));\
			$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_HEADER_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) headers_install;\
			if [ -d "$(KERNEL_HEADERS_INSTALL)/include/bringup_headers" ]; then \
				cp -Rf  $(KERNEL_HEADERS_INSTALL)/include/bringup_headers/* $(KERNEL_HEADERS_INSTALL)/include/ ;\
			fi ;\
			fi
	$(hide) if [ "$(KERNEL_HEADER_DEFCONFIG)" != "$(KERNEL_DEFCONFIG)" ]; then \
			echo "Used a different defconfig for header generation"; \
			rm -f $(BUILD_ROOT_LOC)$(KERNEL_CONFIG); \
			$(call do-kernel-config,$(BUILD_ROOT_LOC)$(KERNEL_OUT),$(KERNEL_CONFIG),$(TARGET_DEFCONFIG),$(TARGET_KERNEL_SOURCE),$(KERNEL_MAKE_ENV),$(KERNEL_ARCH),$(KERNEL_CROSS_COMPILE),$(MAKE)); fi
	$(hide) if [ ! -z "$(KERNEL_CONFIG_OVERRIDE)" ]; then \
			echo "Overriding kernel config with '$(KERNEL_CONFIG_OVERRIDE)'"; \
			echo $(KERNEL_CONFIG_OVERRIDE) >> $(KERNEL_OUT)/.config; \
			$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) oldconfig; fi

.PHONY: kerneltags
kerneltags: $(KERNEL_OUT) $(KERNEL_CONFIG)
	$(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) tags

.PHONY: kernelconfig
kernelconfig: $(KERNEL_OUT) $(KERNEL_CONFIG)
	env KCONFIG_NOTIMESTAMP=true \
	     $(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) menuconfig
	env KCONFIG_NOTIMESTAMP=true \
	     $(MAKE) -C $(TARGET_KERNEL_SOURCE) O=$(BUILD_ROOT_LOC)$(KERNEL_OUT) $(KERNEL_MAKE_ENV) ARCH=$(KERNEL_ARCH) CROSS_COMPILE=$(KERNEL_CROSS_COMPILE) $(real_cc) savedefconfig
	cp $(KERNEL_OUT)/defconfig $(TARGET_KERNEL_SOURCE)/arch/$(KERNEL_ARCH)/configs/$(KERNEL_DEFCONFIG)

endif
endif
