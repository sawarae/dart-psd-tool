#!/usr/bin/env python3
"""Composite PSD test files using psd-tools and save reference PNGs.

Requires: pip install psd-tools Pillow numpy
"""

import os
import json
import hashlib
import numpy as np
import psd_tools
from PIL import Image


def composite_psd(psd_path):
    """Open a PSD and composite all layers using psd-tools.

    force=True ensures psd-tools actually composites layers with its blend
    mode implementations, rather than returning the stored merged preview.
    """
    psd = psd_tools.PSDImage.open(psd_path)
    return psd.composite(force=True)


def image_stats(img):
    """Compute pixel statistics for a PIL Image."""
    arr = np.array(img)
    if arr.ndim == 2:
        arr = arr[:, :, np.newaxis]
    stats = {}
    channels = ['r', 'g', 'b', 'a'] if arr.shape[2] == 4 else ['r', 'g', 'b']
    for i, ch in enumerate(channels):
        ch_data = arr[:, :, i].astype(float)
        stats[f'mean_{ch}'] = round(float(np.mean(ch_data)), 1)
        stats[f'min_{ch}'] = int(np.min(ch_data))
        stats[f'max_{ch}'] = int(np.max(ch_data))
    # Count unique pixel values (as RGBA tuples)
    flat = arr.reshape(-1, arr.shape[2])
    stats['unique_pixels'] = len(set(map(tuple, flat)))
    return stats


def file_hash(path):
    """SHA256 of a file."""
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8192), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    base_dir = os.path.join(os.path.dirname(__file__), '..', 'output')
    psd_dir = os.path.join(base_dir, 'psd')
    results_dir = os.path.join(base_dir, 'results')
    os.makedirs(results_dir, exist_ok=True)

    if not os.path.isdir(psd_dir):
        print(f'Error: PSD directory not found: {psd_dir}')
        print('Run create_test_psd.py first.')
        return

    # Find all PSD files (exclude source images)
    psd_files = sorted(f for f in os.listdir(psd_dir) if f.endswith('.psd'))
    if not psd_files:
        print('No PSD files found.')
        return

    print(f'Found {len(psd_files)} PSD files')
    print(f'psd-tools version: {psd_tools.__version__}\n')

    report = {
        'psd_tools_version': psd_tools.__version__,
        'results': {},
    }

    # Also load base image for comparison
    base_path = os.path.join(psd_dir, '_base.png')
    base_hash = file_hash(base_path) if os.path.exists(base_path) else None
    identical_to_base = 0

    for fname in psd_files:
        psd_path = os.path.join(psd_dir, fname)
        out_name = fname.replace('.psd', '.png')
        out_path = os.path.join(results_dir, out_name)

        try:
            img = composite_psd(psd_path)
            img.save(out_path)

            stats = image_stats(img)
            h = file_hash(out_path)
            is_same_as_base = (h == base_hash) if base_hash else False
            if is_same_as_base:
                identical_to_base += 1

            report['results'][out_name] = {
                'status': 'ok',
                'identical_to_base': is_same_as_base,
                'hash': h[:16],
                **stats,
            }
            marker = ' [SAME AS BASE!]' if is_same_as_base else ''
            print(f'  OK  {out_name} ({stats["unique_pixels"]} unique px){marker}')

        except Exception as e:
            report['results'][out_name] = {
                'status': 'error',
                'error': str(e),
            }
            print(f'  ERR {out_name}: {e}')

    # Summary
    total = len(psd_files)
    ok = sum(1 for r in report['results'].values() if r['status'] == 'ok')
    err = total - ok
    print(f'\n--- Summary ---')
    print(f'Total: {total}, OK: {ok}, Errors: {err}')
    print(f'Identical to base: {identical_to_base}/{ok}')
    if identical_to_base == ok and ok > 1:
        print('WARNING: All results identical to base — blend modes NOT applied!')
    elif identical_to_base <= 1:
        print('GOOD: References show different blend mode results.')

    # Save report
    report_path = os.path.join(results_dir, 'report.json')
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)
    print(f'\nReport saved to {report_path}')


if __name__ == '__main__':
    main()
