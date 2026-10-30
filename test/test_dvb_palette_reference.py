"""Checks that the palette verifier rejects wrong colors and transparency."""
from pathlib import Path
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
from dvb_palette_reference import compare_palette_reference


class PaletteReferenceTest(unittest.TestCase):
    def test_each_band_is_checked(self):
        # The first band has the same color as the background: it models a
        # transparent entry rather than an opaque color.
        colors = [(64, 64, 64), (112, 48, 48), (48, 112, 48), (112, 112, 48),
                  (32, 32, 32), (255, 0, 0), (0, 255, 0), (0, 0, 255),
                  (127, 127, 127), (255, 255, 255)]
        image = np.full((576, 720, 3), 64, dtype=np.uint8)
        for i, color in enumerate(colors):
            image[400:480, 180 + i * 36:180 + (i + 1) * 36] = color
        reference = Image.fromarray(image)
        screen = reference.crop((720 * .08, 576 * .58, 720 * .92, 576 * .98))
        screen = screen.resize((378, 144), Image.Resampling.BILINEAR)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'reference.png'
            reference.save(path)
            entry = {'subtitle_reference': str(path), 'palette_rect': [180, 400, 360, 80],
                     'palette_bands': len(colors)}
            self.assertTrue(compare_palette_reference(screen, entry)['palette_reference_passed'])
            for i in range(len(colors)):
                changed = np.array(screen).copy()
                x = 180 + (i + .5) * 36
                sx = round((x / 720 - .08) / .84 * (screen.width - 1))
                sy = round((440 / 576 - .58) / .40 * (screen.height - 1))
                patch = changed[sy-2:sy+3, sx-2:sx+3]
                patch[:] = 0 if patch.mean() > 127 else 255
                with self.subTest(band=i):
                    self.assertFalse(compare_palette_reference(
                        Image.fromarray(changed), entry)['palette_reference_passed'])

    def test_rejects_region_outside_capture(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'reference.png'
            Image.new('RGB', (720, 576), 'black').save(path)
            entry = {'subtitle_reference': str(path), 'palette_rect': [0, 0, 20, 20],
                     'palette_bands': 1}
            with self.assertRaises(ValueError):
                compare_palette_reference(Image.new('RGB', (378, 144)), entry)

    def test_rejects_empty_palette(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'reference.png'
            Image.new('RGB', (720, 576), 'black').save(path)
            entry = {'subtitle_reference': str(path), 'palette_rect': [180, 400, 360, 80],
                     'palette_bands': 1, 'palette_rows': 1}
            for key in ('palette_bands', 'palette_rows'):
                with self.subTest(key=key), self.assertRaises(ValueError):
                    compare_palette_reference(Image.new('RGB', (378, 144)),
                                              {**entry, key: 0})

    def test_every_grid_cell_is_checked(self):
        image = np.full((576, 720, 3), 64, dtype=np.uint8)
        for index in range(256):
            row, column = divmod(index, 16)
            color = (64, 64, 64) if index == 0 else (
                (index * 53) % 256, (index * 97) % 256, (index * 193) % 256)
            image[350 + row * 12:350 + (row + 1) * 12,
                  80 + column * 35:80 + (column + 1) * 35] = color
        reference = Image.fromarray(image)
        screen = reference.crop((720 * .08, 576 * .58, 720 * .92, 576 * .98))
        screen = screen.resize((378, 144), Image.Resampling.BILINEAR)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'grid.png'
            reference.save(path)
            entry = {'subtitle_reference': str(path), 'palette_rect': [80, 350, 560, 192],
                     'palette_bands': 16, 'palette_rows': 16}
            self.assertTrue(compare_palette_reference(screen, entry)['palette_reference_passed'])
            for index in range(256):
                row, column = divmod(index, 16)
                x = 80 + (column + .5) * 35
                y = 350 + (row + .5) * 12
                sx = round((x / 720 - .08) / .84 * (screen.width - 1))
                sy = round((y / 576 - .58) / .40 * (screen.height - 1))
                changed = np.array(screen).copy()
                patch = changed[sy-2:sy+3, sx-2:sx+3]
                patch[:] = 0 if patch.mean() > 127 else 255
                with self.subTest(index=index):
                    self.assertFalse(compare_palette_reference(
                        Image.fromarray(changed), entry)['palette_reference_passed'])


if __name__ == '__main__':
    unittest.main()
