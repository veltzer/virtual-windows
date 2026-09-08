#!/usr/bin/env python3
"""Print the SHA-256 that an RPM's header records for one of its files.

Usage: rpm_file_sha256.py RPM_FILE FILE_SUFFIX

RPM_FILE may be truncated: only the lead, signature header and main header
are read, so the first megabyte of a package fetched with an HTTP range
request is enough. FILE_SUFFIX selects the packaged file (e.g. ".iso");
symlinks carry no digest and are skipped.
"""
import struct
import sys

RPM_LEAD_MAGIC = b"\xed\xab\xee\xdb"
HEADER_MAGIC = b"\x8e\xad\xe8"
LEAD_SIZE = 96
TAG_FILEDIGESTS = 1035
TAG_BASENAMES = 1117


def read_header(data, offset):
    """Return ({tag: (type, offset, count)}, end_offset) for the header at offset."""
    if data[offset:offset + 3] != HEADER_MAGIC:
        sys.exit(f"error: no RPM header at byte {offset}")
    n_index, store_size = struct.unpack(">II", data[offset + 8:offset + 16])
    index = offset + 16
    store = index + 16 * n_index
    if store + store_size > len(data):
        sys.exit("error: RPM header is longer than the data provided")
    tags = {}
    for i in range(n_index):
        tag, typ, off, count = struct.unpack(">IIII", data[index + 16 * i:index + 16 * i + 16])
        tags[tag] = (typ, store + off, count)
    return tags, store + store_size


def strings(data, entry):
    _, off, count = entry
    out = []
    for _ in range(count):
        end = data.index(b"\0", off)
        out.append(data[off:end].decode())
        off = end + 1
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    path, suffix = sys.argv[1:]
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != RPM_LEAD_MAGIC:
        sys.exit(f"error: {path} is not an RPM package")
    _, sig_end = read_header(data, LEAD_SIZE)
    tags, _ = read_header(data, (sig_end + 7) // 8 * 8)  # main header is 8-byte aligned
    basenames = strings(data, tags[TAG_BASENAMES])
    digests = strings(data, tags[TAG_FILEDIGESTS])
    for base, digest in zip(basenames, digests):
        if base.endswith(suffix) and digest:
            print(digest)
            return
    sys.exit(f"error: no file ending in {suffix} with a digest in {path}")


if __name__ == "__main__":
    main()
