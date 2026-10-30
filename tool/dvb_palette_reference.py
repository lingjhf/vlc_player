"""Compare displayed DVB color bands with an independently decoded frame."""

from PIL import Image
import numpy as np


def compare_palette_reference(screen, entry):
    """Compare the center of every known color band, including transparency."""
    reference = Image.open(entry['subtitle_reference']).convert('RGB')
    width, height = reference.size
    left, top, rect_width, rect_height = entry['palette_rect']
    count = entry['palette_bands']
    rows = entry.get('palette_rows', 1)
    if (count <= 0 or rows <= 0 or count * rows > 4096 or rect_width <= 0 or
            rect_height <= 0 or left < 0 or top < 0 or left + rect_width > width or
            top + rect_height > height):
        raise ValueError('Invalid palette reference geometry')
    actual = np.asarray(screen, dtype=np.int16)
    expected = np.asarray(reference, dtype=np.int16)
    errors = []
    for row in range(rows):
        for index in range(count):
            x = left + (index + .5) * rect_width / count
            y = top + (row + .5) * rect_height / rows
            sx = round((x / width - .08) / .84 * (screen.width - 1))
            sy = round((y / height - .58) / .40 * (screen.height - 1))
            if not 2 <= sx < screen.width - 2 or not 2 <= sy < screen.height - 2:
                raise ValueError('Palette band is outside the captured video region')
            sample = actual[sy-2:sy+3, sx-2:sx+3].mean(axis=(0, 1))
            reference_pixel = expected[round(y), round(x)]
            errors.append(float(np.abs(sample - reference_pixel).max()))
    return {'palette_band_errors': [round(value, 2) for value in errors],
            'palette_reference_passed': all(value <= 25 for value in errors)}
