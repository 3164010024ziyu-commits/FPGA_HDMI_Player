"""Generate reproducible sparse FAT32/BMP simulation fixtures; stdlib only.
The filesystem has 70,000 clusters (actually FAT32), not a mislabelled FAT16 BPB.
This writes test files only; it never opens a physical card or drive.
"""
from pathlib import Path
import struct

OUT = Path(__file__).resolve().parents[1] / 'tb' / 'storage' / 'vectors'
LBAS = [0, 2048, 2080, 2680, 3280, 3281, 3283, 3287, 3284]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sectors = {lba: bytearray(512) for lba in LBAS}
    mbr, bpb = sectors[0], sectors[2048]
    mbr[450] = 0x0C
    struct.pack_into('<II', mbr, 454, 2048, 71232)
    mbr[510:512] = b'\x55\xaa'
    bpb[:3] = b'\xeb\x58\x90'
    struct.pack_into('<H', bpb, 11, 512)
    bpb[13] = 1
    struct.pack_into('<H', bpb, 14, 32)
    bpb[16] = 2
    struct.pack_into('<III', bpb, 28, 2048, 71232, 600)
    struct.pack_into('<I', bpb, 44, 2)
    bpb[510:512] = b'\x55\xaa'
    for lba in [2080, 2680]:
        for c, nxt in {0: 0x0FFFFFF8, 1: 0xFFFFFFFF, 2: 3, 3: 0x0FFFFFFF,
                       5: 9, 9: 6, 6: 0x0FFFFFFF}.items():
            struct.pack_into('<I', sectors[lba], 4*c, nxt)
    width, height, stride = 17, 23, 52
    bmp = bytearray(54 + stride*height)
    struct.pack_into('<2sIHHI', bmp, 0, b'BM', len(bmp), 0, 0, 54)
    struct.pack_into('<IiiHHII', bmp, 14, 40, width, height, 1, 24, 0, stride*height)
    for y in range(height):
        for x in range(width):
            bmp[54+y*stride+x*3:54+y*stride+x*3+3] = bytes((0x30+y, x, 0x80+y+x))
    for i, lba in enumerate([3283, 3287, 3284]):
        chunk = bmp[i*512:(i+1)*512]
        sectors[lba][:len(chunk)] = chunk
    for i in range(16):
        sectors[3280][i*32:i*32+11] = b'IGNORE  TXT'
        sectors[3280][i*32+11] = 0x0F
    for i, name, attr in [(2, b'\xe5ELETED BMP', 0x20),
                          (3, b'FOLDER  BMP', 0x10),
                          (4, b'IGNORE  TXT', 0x20),
                          (5, b'VOLUME  BMP', 0x08)]:
        sectors[3280][i*32:i*32+11] = name
        sectors[3280][i*32+11] = attr
    for lba, name in [(3280, b'FIRST   BMP'), (3281, b'SECOND  BMP')]:
        entry = sectors[lba]
        entry[:11] = name
        entry[11] = 0x20
        struct.pack_into('<H', entry, 26, 5)
        struct.pack_into('<I', entry, 28, len(bmp))
    (OUT / 'card.hex').write_text(''.join(f'{b:02x}\n' for lba in LBAS for b in sectors[lba]), encoding='ascii')
    (OUT / 'image.hex').write_text(''.join(f'{b:02x}\n' for b in bmp), encoding='ascii')
    print(f'Generated {len(LBAS)} sparse sectors; BMP {width}x{height}, {len(bmp)} bytes; chain 5->9->6')


if __name__ == '__main__':
    main()
