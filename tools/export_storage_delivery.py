"""Export verified storage sources, reports and a board-test bundle; stdlib only.

Run regressions and TD -Physical first. Never accesses a physical SD card.
"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT.parent / 'output'
REPORTS = ROOT / 'docs/reports/storage'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_inputs(path):
    hashes = json.loads(path.read_text(encoding='utf-8-sig'))
    for name, expected in hashes.items():
        if digest(ROOT / name) != expected:
            raise RuntimeError(f'Build/test inputs changed: {name}; rerun verification')
    return hashes


def test_bmp():
    # 640x480 BGR24, bottom-up; red top / blue bottom / white left marker.
    width, height = 640, 480
    payload = bytearray()
    rgb_sum = 0
    for y in reversed(range(height)):
        for x in range(width):
            rgb = (255, 255, 255) if x < 8 else ((255, 0, 0) if y < 240 else (0, 0, 255))
            r, g, b = rgb
            payload.extend((b, g, r))
            rgb_sum = (rgb_sum + (r << 16) + (g << 8) + b) & 0xffffffff
    header = struct.pack('<2sIHHI', b'BM', 54 + len(payload), 0, 0, 54)
    header += struct.pack('<IiiHHIIiiII', 40, width, height, 1, 24, 0, len(payload), 0, 0, 0, 0)
    return header + payload, rgb_sum


def main():
    td = ROOT / 'build/td'
    sim = ROOT / 'build/storage'
    sources = verify_inputs(td / 'source_hashes.json')
    physical_sources = verify_inputs(td / 'physical_source_hashes.json')
    if physical_sources != sources:
        raise RuntimeError('Synthesis and physical build used different inputs; rerun TD -Physical')
    test_sources = verify_inputs(sim / 'source_hashes.json')
    suites = {}
    for name in ['bmp_stream_decoder', 'fat32_bmp_reader', 'sd_spi_reader',
                 'storage_pipeline', 'hx4s20c_storage_bringup']:
        log = (sim / f'{name}.log').read_text(errors='replace')
        match = re.search(rf'PASS {name}: (\d+)', log)
        if not match or re.search(r'\*\* (Fatal|Error):', log):
            raise RuntimeError(f'Simulation not passed: {name}')
        suites[name] = int(match[1])
    build_log = (td / 'storage_build.log').read_text(errors='replace')
    pnr_log = (td / 'storage_pnr.log').read_text(errors='replace')
    if 'PASS_TD_SYNTHESIS' not in build_log or 'PASS_TD_PNR:' not in pnr_log:
        raise RuntimeError('TD synthesis/physical build not passed')
    physical = td / 'storage'
    timing = (physical / 'Storage_Bringup_phy.ts').read_text()
    setup = float(re.search(r'SWNS:\s*([-+\d.]+)ns', timing)[1])
    hold = float(re.search(r'HWNS:\s*([-+\d.]+)ns', timing)[1])
    if setup < 0 or hold < 0:
        raise RuntimeError('Negative routed timing slack')
    bit = physical / 'Storage_Bringup.bit'
    area = (physical / 'Storage_Bringup_phy.area').read_text()
    lut = int(re.search(r'^#lut\s+(\d+)', area, re.M)[1])
    regs = int(re.search(r'^#reg\s+(\d+)', area, re.M)[1])
    REPORTS.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for suffix in ['phy.area', 'phy.ts', 'pr.timing']:
        shutil.copy2(physical / f'Storage_Bringup_{suffix}', REPORTS)
    shutil.copy2(bit, OUT / bit.name)
    bmp, rgb_sum = test_bmp()
    (OUT / 'TEST640.BMP').write_bytes(bmp)
    manifest = {
        'tool': 'Tang Dynasty V6.2.168116', 'device': 'EG4S20BG256',
        'top': 'hx4s20c_storage_bringup', 'clock_mhz': 50,
        'setup_wns_ns': setup, 'hold_wns_ns': hold, 'lut': lut, 'registers': regs,
        'test_cases': suites, 'total_test_cases': sum(suites.values()),
        'board_tested': False, 'external_io_timing_verified': False,
        'bitstream_sha256': digest(bit), 'source_sha256': sources,
        'simulation_input_sha256': test_sources,
        'reports_sha256': {p.name: digest(p) for p in sorted(REPORTS.iterdir())
                           if p.suffix in {'.area', '.ts', '.timing'}},
        'test_bmp': {'file': 'TEST640.BMP', 'width': 640, 'height': 480, 'bpp': 24,
                     'rgb_sum_hex': f'{rgb_sum:08X}', 'sha256': digest(OUT / 'TEST640.BMP')},
    }
    encoded = json.dumps(manifest, indent=2, ensure_ascii=False) + '\n'
    (REPORTS / 'storage_build_manifest.json').write_text(encoded, encoding='utf-8')
    (OUT / 'storage_build_manifest.json').write_text(encoded, encoding='utf-8')
    files = {ROOT / n for n in sources} | {ROOT / n for n in test_sources}
    files.update([ROOT / 'README.md', ROOT / '.gitignore', ROOT / '.gitattributes', Path(__file__).resolve()])
    files.update(ROOT.glob('docs/*storage*.md'))
    files.update([ROOT / 'docs/td_validation.md', ROOT / 'docs/hx4s20c_board_integration.md'])
    files.update(REPORTS.iterdir())
    with zipfile.ZipFile(OUT / 'storage_delivery.zip', 'w', zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(files):
            bundle.write(path, path.relative_to(ROOT).as_posix())
        for name in ['Storage_Bringup.bit', 'TEST640.BMP', 'storage_build_manifest.json']:
            bundle.write(OUT / name, name)
    print(f'PASS exported {sum(suites.values())} cases, LUT={lut}, setup={setup}, hold={hold}')
    print(OUT / 'storage_delivery.zip')


if __name__ == '__main__':
    main()
