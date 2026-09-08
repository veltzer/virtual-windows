#!/bin/bash -eu
# Install KVM/QEMU, libvirt, virt-manager and the tools the other scripts use,
# then make sure the current user may talk to the libvirt system instance.
set -euo pipefail

if ! grep -qE 'vmx|svm' /proc/cpuinfo; then
	echo "error: CPU has no hardware virtualization (VT-x/AMD-V); enable it in the BIOS" >&2
	exit 1
fi

sudo apt install -y \
	qemu-system-x86 \
	libvirt-daemon-system \
	virt-manager \
	virtinst \
	ovmf \
	swtpm-tools \
	xmlstarlet \
	curl \
	poppler-utils \
	pass

if ! id -nG | tr ' ' '\n' | grep -qx libvirt; then
	sudo usermod -aG libvirt "${USER}"
	echo "added ${USER} to the libvirt group; log out and back in for it to take effect"
fi

if [[ ! -e /dev/kvm ]]; then
	echo "warning: /dev/kvm is missing; the VM will run without KVM acceleration" >&2
fi

echo "prerequisites installed"
