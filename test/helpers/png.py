"""Write RGB PNG files using only the Python standard library."""

import struct
import zlib
from pathlib import Path


def write(path, width, height, pixels):
    """Save row-major RGB tuples to a non-interlaced, 8-bit PNG file."""
    def chunk(kind, data):
        # A PNG chunk contains its length, type, payload and CRC.
        checksum = zlib.crc32(kind + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", checksum)

    rows = []
    for y in range(height):
        row = pixels[y * width:(y + 1) * width]
        rgb_bytes = bytes(component for pixel in row for component in pixel)
        rows.append(b"\0" + rgb_bytes)  # Filter type 0: no filtering.

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    image = b"\x89PNG\r\n\x1a\n"
    image += chunk(b"IHDR", header)
    image += chunk(b"IDAT", zlib.compress(b"".join(rows)))
    image += chunk(b"IEND", b"")
    Path(path).write_bytes(image)
