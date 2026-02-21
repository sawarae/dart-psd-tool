#!/usr/bin/env python3
"""Create test PSD files for blend mode testing.

Generates 81 minimal PSD files (27 blend modes x 3 overlay patterns)
with correct binary structure so psd-tools can composite the layers.

Bug fix from original: channel data must be written in the order matching
channel IDs (Alpha, R, G, B for IDs -1, 0, 1, 2), not RGBA array order.
"""

import struct
import os
import numpy as np
from PIL import Image

BLEND_MODE_KEYS = {
    'Normal':       b'norm',
    'Dissolve':     b'diss',
    'Darken':       b'dark',
    'Multiply':     b'mul ',
    'ColorBurn':    b'idiv',
    'LinearBurn':   b'lbrn',
    'DarkerColor':  b'dkCl',
    'Lighten':      b'lite',
    'Screen':       b'scrn',
    'ColorDodge':   b'div ',
    'LinearDodge':  b'lddg',
    'LighterColor': b'lgCl',
    'Overlay':      b'over',
    'SoftLight':    b'sLit',
    'HardLight':    b'hLit',
    'VividLight':   b'vLit',
    'LinearLight':  b'lLit',
    'PinLight':     b'pLit',
    'HardMix':      b'hMix',
    'Difference':   b'diff',
    'Exclusion':    b'smud',
    'Subtract':     b'fsub',
    'Divide':       b'fdiv',
    'Hue':          b'hue ',
    'Saturation':   b'sat ',
    'Color':        b'colr',
    'Luminosity':   b'lum ',
}


def create_test_images(out_dir):
    """Create test source images (256x256 RGBA)."""
    w, h = 256, 256

    # Base: horizontal gradient red-to-blue, full alpha
    base = np.zeros((h, w, 4), dtype=np.uint8)
    for x in range(w):
        t = x / 255.0
        base[:, x, 0] = int(255 * (1 - t))  # R: 255 -> 0
        base[:, x, 1] = 0                    # G: 0
        base[:, x, 2] = int(255 * t)         # B: 0 -> 255
        base[:, x, 3] = 255                  # A: fully opaque
    Image.fromarray(base).save(os.path.join(out_dir, '_base.png'))

    # Overlay circle: white radial gradient on transparent background
    circle = np.zeros((h, w, 4), dtype=np.uint8)
    cx, cy = w // 2, h // 2
    max_r = min(cx, cy)
    for y in range(h):
        for x in range(w):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if d < max_r:
                t = 1.0 - d / max_r
                circle[y, x] = [255, 255, 255, int(255 * t)]
    Image.fromarray(circle).save(os.path.join(out_dir, '_overlay_circle.png'))

    # Overlay color: vertical gradient green-to-yellow, alpha=180
    color = np.zeros((h, w, 4), dtype=np.uint8)
    for y in range(h):
        t = y / 255.0
        color[y, :, 0] = int(255 * t)  # R: 0 -> 255
        color[y, :, 1] = 255           # G: always 255
        color[y, :, 2] = 0             # B: 0
        color[y, :, 3] = 180           # A: constant 180
    Image.fromarray(color).save(os.path.join(out_dir, '_overlay_color.png'))

    # Overlay alpha: mid-tone orange-to-teal with alpha gradient 10-250.
    # Tests alpha compositing edge cases (near-zero and near-full alpha)
    # and provides non-trivial RGB values across all 3 channels.
    alpha_ov = np.zeros((h, w, 4), dtype=np.uint8)
    for y in range(h):
        for x in range(w):
            tx = x / 255.0
            ty = y / 255.0
            alpha_ov[y, x, 0] = int(200 * (1 - tx) + 50 * tx)   # R: 200 -> 50
            alpha_ov[y, x, 1] = int(100 * (1 - ty) + 180 * ty)  # G: 100 -> 180
            alpha_ov[y, x, 2] = int(50 * (1 - tx) + 200 * tx)   # B: 50 -> 200
            alpha_ov[y, x, 3] = int(10 + 240 * ty)               # A: 10 -> 250
    Image.fromarray(alpha_ov).save(os.path.join(out_dir, '_overlay_alpha.png'))

    return base, circle, color, alpha_ov


def _write_layer_record(buf, name, blend_key, w, h, n_channels, per_channel_len):
    """Write a single layer record to buf."""
    # Bounding rect: top, left, bottom, right
    buf += struct.pack('>iiii', 0, 0, h, w)
    # Number of channels
    buf += struct.pack('>H', n_channels)
    # Channel info: id (2 bytes signed) + data length (4 bytes)
    # Order: alpha=-1, R=0, G=1, B=2
    for ch_id in [-1, 0, 1, 2]:
        buf += struct.pack('>hI', ch_id, per_channel_len)
    # Blend mode
    buf += b'8BIM'
    buf += blend_key
    # Opacity (255 = fully opaque)
    buf += struct.pack('>B', 255)
    # Clipping (0 = base)
    buf += struct.pack('>B', 0)
    # Flags (0 = visible, no protection)
    buf += struct.pack('>B', 0)
    # Filler
    buf += struct.pack('>B', 0)
    # Extra data
    name_bytes = name.encode('ascii')
    pascal_name = struct.pack('>B', len(name_bytes)) + name_bytes
    # Pad Pascal string to multiple of 4 bytes
    while len(pascal_name) % 4 != 0:
        pascal_name += b'\x00'
    extra = bytearray()
    extra += struct.pack('>I', 0)  # Layer mask data length (0 = none)
    extra += struct.pack('>I', 0)  # Blending ranges length (0 = none)
    extra += pascal_name
    buf += struct.pack('>I', len(extra))
    buf += extra
    return buf


def _write_channel_data(buf, img_arr, h, w):
    """Write channel image data in channel ID order: A, R, G, B."""
    # Channel IDs are -1, 0, 1, 2 → array indices 3, 0, 1, 2
    for arr_idx in [3, 0, 1, 2]:
        buf += struct.pack('>H', 0)  # Compression: raw
        buf += img_arr[:, :, arr_idx].tobytes()
    return buf


def write_psd(path, base_arr, overlay_arr, blend_key):
    """Write a minimal 2-layer PSD file.

    Structure:
      Layer 0: Base (Normal blend)
      Layer 1: Overlay (specified blend mode)
    """
    h, w = base_arr.shape[:2]
    n_channels = 4
    per_channel_len = 2 + h * w  # 2 bytes compression + raw pixel data

    buf = bytearray()

    # ── File Header (26 bytes) ──
    buf += b'8BPS'                      # Signature
    buf += struct.pack('>H', 1)         # Version 1
    buf += b'\x00' * 6                  # Reserved
    buf += struct.pack('>H', n_channels)  # Channels
    buf += struct.pack('>II', h, w)     # Height, Width
    buf += struct.pack('>H', 8)         # Bits per channel
    buf += struct.pack('>H', 3)         # Color mode: RGB

    # ── Color Mode Data ──
    buf += struct.pack('>I', 0)

    # ── Image Resources ──
    buf += struct.pack('>I', 0)

    # ── Layer and Mask Information ──
    # Build layer info sub-section
    layer_info = bytearray()
    layer_info += struct.pack('>h', 2)  # Layer count = 2

    # Layer records
    layer_info = _write_layer_record(
        layer_info, 'Base', b'norm', w, h, n_channels, per_channel_len)
    layer_info = _write_layer_record(
        layer_info, 'Overlay', blend_key, w, h, n_channels, per_channel_len)

    # Channel image data (must follow all layer records)
    layer_info = _write_channel_data(layer_info, base_arr, h, w)
    layer_info = _write_channel_data(layer_info, overlay_arr, h, w)

    # Pad layer info to even length
    if len(layer_info) % 2 != 0:
        layer_info += b'\x00'

    # Wrap in layer-and-mask section
    lm_section = bytearray()
    lm_section += struct.pack('>I', len(layer_info))  # Layer info length
    lm_section += layer_info
    lm_section += struct.pack('>I', 0)  # Global layer mask info (empty)

    buf += struct.pack('>I', len(lm_section))  # Section length
    buf += lm_section

    # ── Merged Image Data (preview) ──
    # PSD merged data uses planar order: R, G, B, A
    buf += struct.pack('>H', 0)  # Compression: raw
    for ch_idx in [0, 1, 2, 3]:
        buf += base_arr[:, :, ch_idx].tobytes()

    with open(path, 'wb') as f:
        f.write(buf)


def main():
    out_dir = os.path.join(os.path.dirname(__file__), '..', 'output')
    psd_dir = os.path.join(out_dir, 'psd')
    os.makedirs(psd_dir, exist_ok=True)

    base, circle, color, alpha_ov = create_test_images(psd_dir)

    overlays = {'circle': circle, 'color': color, 'alpha': alpha_ov}
    count = 0
    for mode_name, blend_key in BLEND_MODE_KEYS.items():
        for ov_name, ov_arr in overlays.items():
            fname = f'{mode_name}_{ov_name}.psd'
            write_psd(os.path.join(psd_dir, fname), base, ov_arr, blend_key)
            count += 1
            print(f'  Created {fname}')

    print(f'\nGenerated {count} PSD files in {psd_dir}')


if __name__ == '__main__':
    main()
