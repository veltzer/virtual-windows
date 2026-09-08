# Windows 11 VM on Linux (KVM/QEMU)

Scripts that create, run, and remove a Windows 11 virtual machine with
libvirt. The VM runs the Windows 11 Enterprise evaluation from the Microsoft
Evaluation Center: free, no product key, and it stops working 90 days after
installation (delete the VM and create it again when that happens). Everything is driven from `config.sh`; the defaults there match the
VM this was developed on (8 GB RAM, 4 vCPUs, 128 GB qcow2 disk, UEFI Secure
Boot, emulated TPM 2.0).

## Scripts

| Script                 | What it does                                                         |
|------------------------|----------------------------------------------------------------------|
| `install_prereqs.sh`   | Installs QEMU, libvirt, virt-manager, virtinst, OVMF, swtpm, xmlstarlet, curl, poppler-utils, pass; adds you to the `libvirt` group |
| `download_iso.sh`      | Downloads the Windows 11 Enterprise evaluation ISO, checks it against Microsoft's published SHA-256 and pins that in `config.sh`. `--print-url` only shows the link |
| `download_virtio.sh`   | Same for the VirtIO guest driver ISO (required by create/start), using the SHA-256 recorded in the virtio-win RPM header |
| `verify_iso.sh`        | Checks both ISOs against the SHA-256 values pinned in `config.sh`   |
| `rpm_file_sha256.py`   | Helper: reads a packaged file's SHA-256 from an RPM header           |
| `create_vm.sh`         | Defines the VM with `virt-install` and boots it from the ISO. `--dry-run` prints the XML instead |
| `start_vm.sh`          | Starts the VM if needed and opens its console. `--fix` only repairs the ISO ownership and definition (attaches the VirtIO CD-ROM if missing) |
| `stop_vm.sh`           | Clean ACPI shutdown; `--force` kills the VM                          |
| `delete_vm.sh`         | Removes the VM, its disk, NVRAM and TPM state. `--yes` skips the prompt |
| `show_credentials.sh`  | Prints the Windows account details from pass(1)                      |

Every setting in `config.sh` can be overridden from the environment, for
example `VM_NAME=win11-test ./create_vm.sh --dry-run`.

## Prerequisites

- CPU with hardware virtualization (Intel VT-x or AMD-V) enabled in the BIOS
- 8 GB of RAM to spare for the VM
- Disk space for the ISO (about 7 GB) plus the VM disk (grows up to `VM_DISK_GB`)

```bash
./install_prereqs.sh
```

Log out and back in if the script added you to the `libvirt` group.

## Step 1: Download the Windows 11 ISO

```bash
./download_iso.sh
```

The script resolves the Evaluation Center's download link for the language
in `config.sh`, downloads the Windows 11 Enterprise evaluation ISO into
`iso.gi/` (a directory the shared `.gitignore` ignores), and checks it
against the SHA-256 in Microsoft's hash PDF. A
partial download resumes on the next run. `--print-url` only prints the
resolved link and the published hash.

The expected checksums live in `config.sh` (`ISO_SHA256`,
`VIRTIO_ISO_SHA256`). They are pins: a download script only rewrites its pin
after it has fetched and verified a newer build, and says so. Microsoft
refreshes the evaluation ISO behind the same link every few months; the copy
on disk never changes, and `--print-url` shows whether a newer build exists.

The Evaluation Center uses fixed links with no session handshake or rate
limit, unlike the consumer Windows 11 download page. To pick another
language, open https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise,
copy the `linkid` of that language's "64-bit edition" link into `ISO_FWLINK`
and set `ISO_LANGUAGE` accordingly.

To check both ISOs by hand later:

```bash
./verify_iso.sh
```

Fetch the VirtIO drivers. `create_vm.sh` attaches the ISO as a second CD-ROM,
and both `create_vm.sh` and `start_vm.sh` refuse to run without it. The
download site publishes no checksum for the ISO, so the script reads the
ISO's SHA-256 from the header of the RPM that packages the same file:

```bash
./download_virtio.sh
```

## Step 2: Store the Windows account details in pass(1)

The scripts never keep passwords in this directory. `show_credentials.sh`
reads these entries:

```
vms/windows/user
vms/windows/password
vms/windows/security/first-pet-name
vms/windows/security/first-school-name
vms/windows/security/childhood-nickname
```

Create them with `pass insert vms/windows/user` and so on.

## Step 3: Create the VM and install Windows

```bash
./create_vm.sh
```

This defines the VM, boots it from the ISO, and opens the console in
virt-manager. Windows setup is interactive:

1. Press a key when the console says "Press any key to boot from CD or DVD"
2. Follow the installer prompts. The evaluation ISO contains only
   **Windows 11 Enterprise**, so there is no edition list and no product key
   prompt. The evaluation is activated automatically for 90 days.
3. Accept the license and choose **Custom: Install Windows only**
4. Select the virtual disk and let the installer run. The VM reboots several
   times; if it boots back into the installer, pick the disk from the boot
   menu or just close the installer window.
5. In the first-run wizard create a **local account**. Disconnect the VM's
   network (virt-manager: View > Details > NIC > untick Active) to skip the
   Microsoft-account sign-in. Run `./show_credentials.sh` for the user name,
   password, and the answers to the three security questions.

After the first boot open the VirtIO CD-ROM in Explorer inside Windows and
run `virtio-win-guest-tools.exe`. It installs the VirtIO drivers, the QEMU
guest agent (clean shutdowns from `stop_vm.sh`) and the SPICE guest tools
(clipboard sharing, automatic screen resizing).

## Day to day

```bash
./start_vm.sh   # boot and open the console
./stop_vm.sh    # clean shutdown
./delete_vm.sh  # wipe it and start over with create_vm.sh
```

Console tips:

- In full-screen mode move the mouse to the top centre of the screen to reveal
  the virt-manager toolbar (leave full screen, send keys, and so on).
- `start_vm.sh` runs virt-manager under `/usr/bin/python3` on purpose: with a
  venv first on `PATH`, virt-manager picks up that interpreter and fails with
  `No module named 'gi'`. The same applies to `virt-install`. If you run
  either tool by hand, `deactivate` the venv first.

## Inside Windows: Visual Studio and Copilot

1. In Edge open https://visualstudio.microsoft.com/ and download
   **Visual Studio Community**
2. Run the installer and pick the workloads you need (".NET desktop
   development", "Desktop development with C++", ...)
3. In Visual Studio go to **Extensions > Manage Extensions**, search for
   **GitHub Copilot**, install it, and restart Visual Studio
4. Sign in with a GitHub account that has a Copilot subscription or trial

## How the VM is built

`create_vm.sh` reproduces a configuration that is known to install and boot:

- Machine type q35 with `host-passthrough` CPU
- OVMF firmware with Secure Boot enabled and no enrolled keys
  (`OVMF_CODE_4M.secboot.fd`; plain UEFI without Secure Boot fails the
  Windows 11 hardware check)
- Emulated TPM 2.0 (`tpm-tis` backed by swtpm)
- qcow2 disk on a SATA bus with `discard=unmap`
- Install ISO and VirtIO driver ISO on read-only SATA CD-ROMs with
  `<seclabel model='dac' relabel='no'/>`. Without it libvirt's dynamic
  ownership chowns the ISOs in your home directory to `libvirt-qemu` on every
  boot. `start_vm.sh` repairs both the ownership and the definition if a VM
  was created some other way.
- NAT network (`default`) with an e1000e NIC, SPICE graphics, VGA video

## Troubleshooting

- **Permission denied starting the VM**: make sure `groups` lists `libvirt`;
  otherwise run `./install_prereqs.sh` and log out and back in.
- **"This PC can't run Windows 11"**: the VM lacks Secure Boot or a TPM.
  Delete it and recreate it with `create_vm.sh`, which sets both.
- **Poor performance**: check `ls -l /dev/kvm` exists, give the VM more
  RAM or CPUs in `config.sh`, and install the VirtIO drivers.
- **No network in the VM**: `virsh -c qemu:///system net-list` should show
  `default` active; start it with `virsh -c qemu:///system net-start default`.
- **ISO owned by libvirt-qemu**: run `./start_vm.sh --fix`.
- **VirtIO driver ISO not found**: run `./download_virtio.sh`; the VM cannot be
  created or started without it.
- **`download_iso.sh` says the link resolved to an unexpected file**:
  Microsoft changed the Evaluation Center links; look up the current
  `linkid` for your language as described in Step 1 and update `config.sh`.
- **Windows shuts down every hour**: the 90-day evaluation has expired. Run
  `./delete_vm.sh` and `./create_vm.sh` to install it again.
- **VM created before the VirtIO ISO was downloaded**: `./start_vm.sh` (or
  `--fix`) attaches it as a second CD-ROM on the next start.
