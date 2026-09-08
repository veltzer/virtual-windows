#!/bin/bash -eu
# Start the Windows VM (if needed) and open its console in virt-manager.
#
# Also keeps libvirt from taking ownership of the install ISO: the VM lives in
# the system instance, which runs QEMU as libvirt-qemu:kvm. With libvirt's
# default dynamic_ownership=1 every image attached to the VM is chowned to that
# user at boot, so an ISO in a home directory ends up owned by libvirt-qemu.
# Marking the ISO's <source> with <seclabel model='dac' relabel='no'/> tells
# libvirt to leave the ownership alone; QEMU can still open it because the ISO
# is world-readable and attached read-only. create_vm.sh sets this up, but the
# check below repairs a VM that was defined some other way.
#
# Usage: ./start_vm.sh        start the VM and open its console
#        ./start_vm.sh --fix  only repair ownership and the VM definition
#                             (cdrom paths, VirtIO cdrom, seclabels)
set -euo pipefail
# shellcheck source=config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

if ! vm_exists; then
	echo "error: VM '${VM_NAME}' does not exist; run ./create_vm.sh first" >&2
	exit 1
fi
# The VM definition references the VirtIO ISO as a cdrom; libvirt refuses to
# start a domain whose media is missing, so fail early with a clear message.
require_virtio_iso

# 1. Take the ISOs back if a previous start relabelled them.
owner="$(id -un):$(id -gn)"
for iso in "${ISO}" "${VIRTIO_ISO}"; do
	if [[ -e "${iso}" && "$(stat -c %U:%G "${iso}")" != "${owner}" ]]; then
		echo "${iso} owned by $(stat -c %U:%G "${iso}"), chowning back to ${owner}"
		sudo chown "${owner}" "${iso}"
	fi
done

# 2. Point the cdroms at the configured ISOs if the files moved since the VM
#    was defined (e.g. into iso.gi/). libvirt refuses to start a domain whose
#    media is missing, and the attach step below would otherwise add a second
#    VirtIO cdrom next to the stale one. Matched by file name.
xml="$(virsh -c "${LIBVIRT_URI}" dumpxml --inactive "${VM_NAME}")"
changed=0
for iso in "${ISO}" "${VIRTIO_ISO}"; do
	while read -r stale; do
		[[ -z "${stale}" || "${stale}" == "${iso}" ]] && continue
		echo "Repointing cdrom ${stale} to ${iso} in the ${VM_NAME} definition"
		xml="$(xmlstarlet ed -u "/domain/devices/disk[@device='cdrom']/source[@file='${stale}']/@file" -v "${iso}" <<<"${xml}")"
		changed=1
	done < <(xmlstarlet sel -t -m "/domain/devices/disk[@device='cdrom']/source[substring(@file, string-length(@file) - string-length('/$(basename "${iso}")') + 1) = '/$(basename "${iso}")']" -v @file -n <<<"${xml}")
done
if ((changed)); then
	virsh -c "${LIBVIRT_URI}" define /dev/stdin <<<"${xml}"
	xml="$(virsh -c "${LIBVIRT_URI}" dumpxml --inactive "${VM_NAME}")"
fi

# 3. Attach the VirtIO ISO as a cdrom if the VM was defined without it
#    (e.g. created before download_virtio.sh was run). Persistent only: a
#    running VM picks it up on its next boot.
if [[ "$(xmlstarlet sel -t -v "count(/domain/devices/disk[@device='cdrom']/source[@file='${VIRTIO_ISO}'])" <<<"${xml}")" == 0 ]]; then
	# First unused SATA target name after the ones already defined.
	for target in sd{c..z}; do
		[[ "$(xmlstarlet sel -t -v "count(/domain/devices/disk/target[@dev='${target}'])" <<<"${xml}")" == 0 ]] && break
	done
	echo "Attaching VirtIO driver ISO ${VIRTIO_ISO} to ${VM_NAME} as ${target}"
	virsh -c "${LIBVIRT_URI}" attach-disk "${VM_NAME}" "${VIRTIO_ISO}" "${target}" \
		--config --type cdrom --targetbus sata --mode readonly
	xml="$(virsh -c "${LIBVIRT_URI}" dumpxml --inactive "${VM_NAME}")"
fi

# 4. Make sure the VM definition tells libvirt not to relabel the ISOs.
#    Idempotent: only redefines the domain when a seclabel is missing.
changed=0
for iso in "${ISO}" "${VIRTIO_ISO}"; do
	src_xpath="/domain/devices/disk[@device='cdrom']/source[@file='${iso}']"
	if [[ "$(xmlstarlet sel -t -v "count(${src_xpath})" <<<"${xml}")" != 0 ]] &&
		[[ "$(xmlstarlet sel -t -v "count(${src_xpath}/seclabel[@model='dac'][@relabel='no'])" <<<"${xml}")" == 0 ]]; then
		echo "Adding <seclabel model='dac' relabel='no'/> to ${iso} in the ${VM_NAME} definition"
		xml="$(xmlstarlet ed \
			-s "${src_xpath}" -t elem -n seclabel \
			-i "${src_xpath}/seclabel[not(@model)]" -t attr -n model -v dac \
			-i "${src_xpath}/seclabel[not(@relabel)]" -t attr -n relabel -v no \
			<<<"${xml}")"
		changed=1
	fi
done
if ((changed)); then
	virsh -c "${LIBVIRT_URI}" define /dev/stdin <<<"${xml}"
fi

[[ "${1:-}" == "--fix" ]] && exit 0

# 5. Start the VM (if needed) and open its console.
if [[ "$(vm_state)" != "running" ]]; then
	virsh -c "${LIBVIRT_URI}" start "${VM_NAME}"
fi
exec /usr/bin/python3 "$(command -v virt-manager)" --connect "${LIBVIRT_URI}" --show-domain-console "${VM_NAME}"
