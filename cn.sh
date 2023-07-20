/Library/Developer/CommandLineTools/usr/bin/clang \
-mlittle-endian \
-Wall \
-Wundef \
-Werror=strict-prototypes \
-Wno-trigraphs \
-fno-strict-aliasing \
-fno-common \
-fshort-wchar \
-fno-PIE \
-Werror=implicit-function-declaration \
-Werror=implicit-int \
-Werror=return-type \
-Wno-format-security \
-std=gnu89 \
-Werror=unknown-warning-option \
-Werror=ignored-optimization-argument \
-Wno-psabi \
-fno-asynchronous-unwind-tables \
-fno-unwind-tables \
-fno-delete-null-pointer-checks \
-Wno-frame-address \
-Wno-address-of-packed-member \
-O2 \
-Wframe-larger-than=2048 \
-Wno-gnu \
-Wno-unused-but-set-variable \
-Wno-unused-const-variable \
-fno-omit-frame-pointer \
-fno-optimize-sibling-calls \
-ftrivial-auto-var-init=zero \
-enable-trivial-auto-var-init-zero-knowing-it-will-be-removed-from-clang \
-fno-stack-clash-protection \
-g \
-fno-var-tracking \
-Wdeclaration-after-statement \
-Wvla \
-Wno-pointer-sign \
-Wno-array-bounds \
-fno-strict-overflow \
-fno-stack-check \
-Werror=date-time \
-Werror=incompatible-pointer-types \
-Wno-initializer-overrides \
-Wno-format \
-Wno-sign-compare \
-Wno-format-zero-length \
-Wno-pointer-to-enum-cast \
-Wno-tautological-constant-out-of-range-compare \
-c \
-o cn.out cn.c

# -nostdinc
# -fintegrated-as
# -mgeneral-regs-only
# -DCONFIG_CC_HAS_K_CONSTRAINT=1
# -mbranch-protection=pac-ret+leaf+bti
# -Wa,-march=armv8.5-a
# -DARM64_ASM_ARCH='"armv8.5-a"'
# -DKASAN_SHADOW_SCALE_SHIFT=
# -fstack-protector-strong

# -mno-global-merge


# -mstack-protector-guard=sysreg
# -mstack-protector-guard-reg=sp_el0
# -mstack-protector-guard-offset=1112
# -I./arch/arm64/kvm/hyp/include
# -fno-stack-protector
# -DDISABLE_BRANCH_PROFILING
# -D__KVM_NVHE_HYPERVISOR__
# -D__DISABLE_EXPORTS
# -fsanitize-coverage=trace-pc    
# -DKBUILD_MODFILE='"arch/arm64/kvm/hyp/nvhe/hyp-main.nvhe"'
# -DKBUILD_BASENAME='"hyp_main.nvhe"'
# -DKBUILD_MODNAME='"hyp_main.nvhe"'
# -D__KBUILD_MODNAME=kmod_hyp_main.nvhe \

