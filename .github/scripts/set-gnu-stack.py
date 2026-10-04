# Sets the PT_GNU_STACK p_memsz of an ELF64 little-endian binary (musl reads it as the default thread stack size).
import struct, sys
path, size = sys.argv[1], int(sys.argv[2])
b = bytearray(open(path, 'rb').read())
assert b[:4] == b'\x7fELF' and b[4] == 2 and b[5] == 1
phoff, = struct.unpack_from('<Q', b, 0x20)
phentsize, phnum = struct.unpack_from('<HH', b, 0x36)
for i in range(phnum):
    off = phoff + i * phentsize
    p_type, = struct.unpack_from('<I', b, off)
    if p_type == 0x6474e551:
        old, = struct.unpack_from('<Q', b, off + 40)
        struct.pack_into('<Q', b, off + 40, size)
        open(path, 'wb').write(b)
        print(f"PT_GNU_STACK p_memsz {old} -> {size}")
        break
else:
    sys.exit("no PT_GNU_STACK header")
