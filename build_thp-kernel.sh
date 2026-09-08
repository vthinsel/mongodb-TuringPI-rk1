#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Build custom RK1 kernel 5.10.160-rockchip-thp1 with Transparent Huge Pages
#
# Platform:
#   Turing Machines RK1 / RK3588
#   Ubuntu 22.04 Jammy
#
# Stock kernel:
#   5.10.160-rockchip
#
# Custom kernel:
#   5.10.160-rockchip-thp1
#
# Source package:
#   linux-rockchip-5.10 5.10.160-37
#
# Main change:
#   CONFIG_TRANSPARENT_HUGEPAGE=y
#
# This automatically selects:
#   CONFIG_COMPACTION=y
#
# Resulting packages:
#   linux-image-5.10.160-rockchip-thp1_5.10.160-37_arm64.deb
#   linux-headers-5.10.160-rockchip-thp1_5.10.160-37_arm64.deb
###############################################################################

CUSTOM_SUFFIX="thp1"
BASE_VERSION="5.10.160"
DEBIAN_REVISION="37"

SOURCE_PACKAGE="linux-rockchip-5.10"
SOURCE_DIR_NAME="linux-rockchip-5.10-${BASE_VERSION}"
KERNEL_RELEASE="${BASE_VERSION}-rockchip-${CUSTOM_SUFFIX}"

WORKDIR="${HOME}/kernel-backup"
DOWNLOAD_DIR="${WORKDIR}/source-download"
BUILD_PARENT="${WORKDIR}/source"

echo "============================================================"
echo " RK1 custom kernel builder"
echo " Target kernel: ${KERNEL_RELEASE}"
echo "============================================================"

###############################################################################
# 1. Basic checks
###############################################################################

echo
echo "== System =="

uname -a

ARCH="$(dpkg --print-architecture)"

if [[ "${ARCH}" != "arm64" ]]; then
    echo "ERROR: expected arm64, got ${ARCH}"
    exit 1
fi

MODEL="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"

echo "Machine: ${MODEL}"

if [[ "${MODEL}" != "Turing Machines RK1" ]]; then
    echo "WARNING: this script was validated on a Turing Machines RK1."
fi

CURRENT_KERNEL="$(uname -r)"

echo "Current kernel: ${CURRENT_KERNEL}"

###############################################################################
# 2. Install build dependencies
###############################################################################

echo
echo "== Installing build dependencies =="

sudo apt update

sudo apt install -y \
    build-essential \
    bc \
    rsync \
    kmod \
    cpio \
    u-boot-tools \
    bison \
    flex \
    libssl-dev \
    python3 \
    python-is-python3 \
    dpkg-dev \
    devscripts \
    fakeroot

###############################################################################
# 3. Prepare directories
###############################################################################

echo
echo "== Preparing directories =="

mkdir -p "${DOWNLOAD_DIR}"
mkdir -p "${BUILD_PARENT}"

cd "${DOWNLOAD_DIR}"

###############################################################################
# 4. Download exact source package
#
# Prerequisite:
# deb-src must be enabled for Joshua Riek's Rockchip PPA.
#
# The source we used was:
#
# linux-rockchip-5.10_5.10.160-37.dsc
# linux-rockchip-5.10_5.10.160-37.tar.xz
###############################################################################

echo
echo "== Downloading source package =="

apt-get source --download-only \
    "${SOURCE_PACKAGE}=${BASE_VERSION}-${DEBIAN_REVISION}"

DSC_FILE="${SOURCE_PACKAGE}_${BASE_VERSION}-${DEBIAN_REVISION}.dsc"

if [[ ! -f "${DSC_FILE}" ]]; then
    echo "ERROR: ${DSC_FILE} not found."
    echo
    echo "Make sure deb-src is enabled for the Rockchip PPA."
    exit 1
fi

###############################################################################
# 5. Extract source
###############################################################################

echo
echo "== Extracting source =="

cd "${BUILD_PARENT}"

if [[ -d "${SOURCE_DIR_NAME}" ]]; then
    echo "Existing source directory found:"
    echo "  ${BUILD_PARENT}/${SOURCE_DIR_NAME}"
    echo
    echo "Refusing to overwrite it."
    exit 1
fi

dpkg-source -x "${DOWNLOAD_DIR}/${DSC_FILE}"

cd "${BUILD_PARENT}/${SOURCE_DIR_NAME}"

###############################################################################
# 6. Verify Debian source version
###############################################################################

echo
echo "== Debian source version =="

PACKAGE_VERSION="$(dpkg-parsechangelog -SVersion)"

echo "Version: ${PACKAGE_VERSION}"

if [[ "${PACKAGE_VERSION}" != "${BASE_VERSION}-${DEBIAN_REVISION}" ]]; then
    echo "ERROR: unexpected package version."
    exit 1
fi

###############################################################################
# 7. Backup important packaging/config files
###############################################################################

echo
echo "== Backing up original files =="

cp arch/arm64/configs/rockchip_linux_defconfig \
   arch/arm64/configs/rockchip_linux_defconfig.orig

cp debian/rules \
   debian/rules.orig

cp debian/control \
   debian/control.orig

cp debian/changelog \
   debian/changelog.orig

###############################################################################
# 8. Enable Transparent Huge Pages
###############################################################################

echo
echo "== Enabling CONFIG_TRANSPARENT_HUGEPAGE =="

CONFIG_FILE="arch/arm64/configs/rockchip_linux_defconfig"

if grep -q '^# CONFIG_TRANSPARENT_HUGEPAGE is not set$' "${CONFIG_FILE}"; then

    sed -i \
        's/^# CONFIG_TRANSPARENT_HUGEPAGE is not set$/CONFIG_TRANSPARENT_HUGEPAGE=y/' \
        "${CONFIG_FILE}"

elif grep -q '^CONFIG_TRANSPARENT_HUGEPAGE=y$' "${CONFIG_FILE}"; then

    echo "CONFIG_TRANSPARENT_HUGEPAGE already enabled."

else

    echo "ERROR: unexpected THP configuration state."
    grep -n 'TRANSPARENT_HUGEPAGE' "${CONFIG_FILE}" || true
    exit 1

fi

echo
echo "Defconfig modification:"

diff -u \
    arch/arm64/configs/rockchip_linux_defconfig.orig \
    arch/arm64/configs/rockchip_linux_defconfig || true

###############################################################################
# 9. Give the kernel a distinct KERNELRELEASE
#
# Stock:
#   5.10.160-rockchip
#
# Custom:
#   5.10.160-rockchip-thp1
#
# This is essential.
#
# Merely changing the .deb version is NOT sufficient because otherwise
# /lib/modules/5.10.160-rockchip and /boot/vmlinuz-5.10.160-rockchip
# would collide with the stock kernel.
###############################################################################

echo
echo "== Changing KERNELRELEASE =="

sed -i \
    "s/KERNELRELEASE=\$(KDEB_PKGVERSION)-rockchip/KERNELRELEASE=\$(KDEB_PKGVERSION)-rockchip-${CUSTOM_SUFFIX}/g" \
    debian/rules

echo
echo "KERNELRELEASE references:"

grep -n 'KERNELRELEASE' debian/rules

COUNT="$(grep -c "KERNELRELEASE=\$(KDEB_PKGVERSION)-rockchip-${CUSTOM_SUFFIX}" debian/rules)"

if [[ "${COUNT}" -ne 2 ]]; then
    echo "ERROR: expected exactly two modified KERNELRELEASE entries."
    exit 1
fi

###############################################################################
# 10. Rename Debian binary packages
#
# intdeb-pkg derives package names from KERNELRELEASE.
# debian/control must therefore declare the matching package names.
###############################################################################

echo
echo "== Renaming binary Debian packages =="

sed -i \
    "s/^Package: linux-image-${BASE_VERSION}-rockchip$/Package: linux-image-${BASE_VERSION}-rockchip-${CUSTOM_SUFFIX}/" \
    debian/control

sed -i \
    "s/^Package: linux-headers-${BASE_VERSION}-rockchip$/Package: linux-headers-${BASE_VERSION}-rockchip-${CUSTOM_SUFFIX}/" \
    debian/control

echo
echo "Packages declared in debian/control:"

grep '^Package:' debian/control

###############################################################################
# 11. Generate kernel .config from Rockchip defconfig
###############################################################################

echo
echo "== Generating kernel configuration =="

make rockchip_linux_defconfig ARCH=arm64

###############################################################################
# 12. Validate THP Kconfig resolution
###############################################################################

echo
echo "== Validating kernel configuration =="

grep -E \
    '^CONFIG_(HAVE_ARCH_TRANSPARENT_HUGEPAGE|COMPACTION|TRANSPARENT_HUGEPAGE|TRANSPARENT_HUGEPAGE_ALWAYS|HUGETLBFS|HUGETLB_PAGE)=' \
    .config

grep -q '^CONFIG_HAVE_ARCH_TRANSPARENT_HUGEPAGE=y$' .config
grep -q '^CONFIG_COMPACTION=y$' .config
grep -q '^CONFIG_TRANSPARENT_HUGEPAGE=y$' .config
grep -q '^CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y$' .config
grep -q '^CONFIG_HUGETLBFS=y$' .config
grep -q '^CONFIG_HUGETLB_PAGE=y$' .config

echo
echo "THP configuration validated."

###############################################################################
# 13. Build Debian packages
###############################################################################

echo
echo "== Building kernel =="

BUILD_LOG="${WORKDIR}/kernel-build-${CUSTOM_SUFFIX}.log"

DEB_BUILD_OPTIONS="parallel=$(nproc)" \
dpkg-buildpackage -b -uc -us 2>&1 | tee "${BUILD_LOG}"

###############################################################################
# 14. Locate generated packages
###############################################################################

cd "${BUILD_PARENT}"

IMAGE_DEB="linux-image-${KERNEL_RELEASE}_${BASE_VERSION}-${DEBIAN_REVISION}_arm64.deb"
HEADERS_DEB="linux-headers-${KERNEL_RELEASE}_${BASE_VERSION}-${DEBIAN_REVISION}_arm64.deb"

echo
echo "== Generated packages =="

ls -lh "${IMAGE_DEB}" "${HEADERS_DEB}"

###############################################################################
# 15. Validate Debian package metadata
###############################################################################

echo
echo "== Package metadata =="

for pkg in "${HEADERS_DEB}" "${IMAGE_DEB}"; do
    echo
    echo "===== ${pkg} ====="

    dpkg-deb -f "${pkg}" \
        Package \
        Version \
        Architecture
done

###############################################################################
# 16. Extract kernel package for offline verification
###############################################################################

echo
echo "== Verifying kernel inside .deb =="

VERIFY_DIR="${WORKDIR}/verify-${CUSTOM_SUFFIX}"

rm -rf "${VERIFY_DIR}"
mkdir -p "${VERIFY_DIR}"

dpkg-deb -x "${IMAGE_DEB}" "${VERIFY_DIR}"

CUSTOM_CONFIG="${VERIFY_DIR}/boot/config-${KERNEL_RELEASE}"
CUSTOM_KERNEL="${VERIFY_DIR}/boot/vmlinuz-${KERNEL_RELEASE}"

if [[ ! -f "${CUSTOM_CONFIG}" ]]; then
    echo "ERROR: kernel config missing from package."
    exit 1
fi

if [[ ! -f "${CUSTOM_KERNEL}" ]]; then
    echo "ERROR: kernel image missing from package."
    exit 1
fi

echo
echo "Kernel configuration from generated package:"

grep -E \
    '^CONFIG_(COMPACTION|TRANSPARENT_HUGEPAGE|TRANSPARENT_HUGEPAGE_ALWAYS)=' \
    "${CUSTOM_CONFIG}"

###############################################################################
# 17. Verify kernel release embedded in Image
###############################################################################

echo
echo "== Verifying embedded kernel version =="

strings "${CUSTOM_KERNEL}" | \
    grep -m1 "${KERNEL_RELEASE}" || {
        echo "ERROR: custom kernel release not found in kernel image."
        exit 1
    }

###############################################################################
# 18. Display hashes
###############################################################################

echo
echo "== Package SHA256 =="

sha256sum "${IMAGE_DEB}" "${HEADERS_DEB}"

###############################################################################
# 19. Final summary
###############################################################################

echo
echo "============================================================"
echo " BUILD SUCCESSFUL"
echo "============================================================"
echo
echo "Kernel:"
echo "  ${KERNEL_RELEASE}"
echo
echo "Packages:"
echo "  ${BUILD_PARENT}/${IMAGE_DEB}"
echo "  ${BUILD_PARENT}/${HEADERS_DEB}"
echo
echo "Build log:"
echo "  ${BUILD_LOG}"
echo
echo "THP configuration:"
grep -E \
    '^CONFIG_(COMPACTION|TRANSPARENT_HUGEPAGE|TRANSPARENT_HUGEPAGE_ALWAYS)=' \
    "${CUSTOM_CONFIG}"

echo
echo "IMPORTANT:"
echo "This script builds the kernel but does NOT install it."
echo
echo "Before installation, preserve the currently bootable RK1 files from:"
echo "  /boot/firmware/vmlinuz"
echo "  /boot/firmware/initrd.img"
echo "  /boot/firmware/rk3588-turing-rk1.dtb"
echo "  /boot/firmware/boot.cmd"
echo "  /boot/firmware/boot.scr"
echo
echo "============================================================"