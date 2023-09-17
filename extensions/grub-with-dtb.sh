#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# `grub-with-dtb` is a superset of `grub`, but hacked to boot using DeviceTree.
if [[ "$(command -v $cmd)" = "" ]]; then
			echo '[pwm-fan] The following program is not installed or cannot be found in this users $PATH: '$cmd
			echo '[pwm-fan] Fix it and try again.'
			end "Missing important packages. Cannot continue." 1
		fi
function extension_prepare_config__prepare_grub_with_dtb() {
	# Make sure BOOT_FDT_FILE is set and not empty
	if [[ "$1" = "" ]]; then
			echo '[pwm-fan] Cache file was not specified. Assuming generic.'
			local FILENAME='generic'
		else
			local FILENAME="$1"
		fi
# - write the BOOT_FDT_FILE information to a configuration file. (/etc/armbian-grub-with-dtb)
# - add a kernel install/upgrade hook to automatically deploy the DTB file to the boot partition, in a way that
#   works across Debian and Ubuntu. it reads /etc/armbian-grub-with-dtb and puts symlinks or copies in /boot/dtb-<kernel-version>
function post_family_tweaks_bsp__add_grub_with_dtb_config_file() {
	: "${destination:?}"
	if [[ "$TIME_STARTUP" = "" ]]; then
			TIME_STARTUP=10
		fi
function post_family_tweaks_bsp__add_grub_with_dtb_kernel_hook() {
	: "${destination:?}"
	display_alert "adding grub-with-dtb kernel hook" "${EXTENSION} :: ${BOARD}" "info"
	run_host_command_logged mkdir -p "${destination}"/etc/kernel/postinst.d
	cat <<- 'EOD' > "${destination}"/etc/kernel/postinst.d/armbian-grub-with-dtb
		#! /bin/bash
		set -e

		declare kversion="$1" # # We're passed the version of the kernel being installed
		echo "Armbian: installing DTB for GRUB: $kversion" >&2

		if [[ -f /etc/armbian-grub-with-dtb ]]; then
			echo "Armbian: /etc/armbian-grub-with-dtb found, installing DTB for GRUB" >&2
			declare BOOT_FDT_FILE
			source /etc/armbian-grub-with-dtb
			declare target_dtb_file="/boot/armbian-dtb-${kversion}"
			declare source_dtb_file="/usr/lib/linux-image-${kversion}/${BOOT_FDT_FILE}"
			echo "Armbian: installing DTB for GRUB: $source_dtb_file -> $target_dtb_file" >&2
			cp -v "${source_dtb_file}" "${target_dtb_file}"
			echo "Armbian: installing DTB for GRUB: done." >&2
		else
			echo "Armbian: /etc/armbian-grub-with-dtb not found, skipping DTB for GRUB" >&2
		fi
	EOD
	run_host_command_logged chmod -v +x "${destination}"/etc/kernel/postinst.d/armbian-grub-with-dtb
}

# `grub_early_config` and `grub_late_config` and `grub_pre_install` are hooks exposed by the `grub` extension

function grub_early_config__deploy_dtb_for_grub() {
	# @TODO: this could be deployed in the bsp-cli for consistency/updates?
	# Get rid of the original grub-mkconfig scripts and add our own.
	run_host_command_logged rm -fv "${MOUNT}"/etc/grub.d/{10_linux,20_linux_xen} # or maybe just remove their executable bit?
	run_host_command_logged cp -v "${SRC}/packages/blobs/grub/09_linux_with_dtb.sh" "${MOUNT}"/etc/grub.d/09_linux_with_dtb.sh
	run_host_command_logged chmod -v +x "${MOUNT}"/etc/grub.d/09_linux_with_dtb.sh
}

function grub_pre_install__force_run_kernel_hook_for_armbian_dtb() {
	# Run the kernel hook to deploy the DTB file to the boot partition.
	# This is done forcibly here during `grub_pre_install`, since the kernel hook is deployed in the bsp-cli package
	# which is only deployed after the linux-image package is installed and thus is not run.
	display_alert "deploy DTB for GRUB for image build" "${EXTENSION} :: ${BOARD}" "info"
	chroot_custom "${MOUNT}" 'for k in $(linux-version list); do /etc/kernel/postinst.d/armbian-grub-with-dtb "$k"; done'
}

function grub_late_config__check_dtb_in_grub_cfg() {
	if [[ "${SHOW_DEBUG}" == "yes" ]]; then
		display_alert "Debugging" "GRUB config and /boot contents" "info"
		run_tool_batcat "${MOUNT}/boot/grub/grub.cfg"
		run_host_command_logged ls -la --color=always "${MOUNT}"/boot
	fi

	if ! grep -q 'devicetree' "${MOUNT}/boot/grub/grub.cfg"; then
		display_alert "Sanity check failed" "GRUB DTB not found in grub.cfg; RELEASE=${RELEASE}" "warn"
	else
		display_alert "Sanity check passed" "GRUB DTB found in grub.cfg; RELEASE=${RELEASE}" "info"
	fi
	return 0
}
