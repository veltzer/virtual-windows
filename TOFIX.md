# TOFIX

Findings from a code scan on 2026-10-04.

## Medium

- `download_virtio.sh:36-41,57-58` - the VirtIO ISO's "published" SHA-256 is read from an RPM header fetched over HTTPS from the same fedorapeople.org directory as the ISO, with no check of the RPM's GPG signature, and whenever it differs from `VIRTIO_ISO_SHA256` the pin in `config.sh` is silently replaced. So the check only catches transfer corruption; a tampered server would serve a matching RPM header and the script would re-pin to it. Either verify the RPM header signature (the signature header already parsed by `rpm_file_sha256.py:57`) against the virtio-win/Fedora key, or refuse to re-pin automatically and ask the user to confirm the new hash.
- `rpm_file_sha256.py:21-65` - a hand-written RPM header parser that guards the VirtIO download, with no tests at all (`pytest` is in `pyproject.toml:10` but there is no test file and no `[processor.pytest]`). Add a `tests/` test that builds a minimal lead + signature header + main header in memory and checks `read_header`/`strings` and the suffix lookup (including the truncated-data and missing-tag error paths), and wire up `[processor.pytest]`.

## Low

- `rpm_file_sha256.py:59-60` - a header without `BASENAMES`/`FILEDIGESTS` raises a bare `KeyError` traceback instead of the script's `error: ...` messages; check for the tags and `sys.exit` with a clear message.
- `delete_vm.sh:31-32` - `virsh vol-delete "${VM_DISK}"` only works when the disk lives in a libvirt storage pool; with `VM_DISK` overridden to a path outside a pool (which `config.sh:22` allows) it fails after the domain is already undefined, leaving the disk behind. Use `virsh undefine ... --remove-all-storage` or fall back to `rm` for non-pool paths.
- `install_prereqs.sh:11` - uses `apt install`, whose CLI apt itself warns is not stable for scripts; use `apt-get install -y`.
- `hints.txt:1` - a one-line note that duplicates the "Console tips" in `README.md:132-133`; delete it.
