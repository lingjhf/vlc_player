"""Protect the waveform verifier against silence and frequency aliasing."""
from pathlib import Path
import sys
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
from reference_audio import compare_reference_audio


class ReferenceAudioTest(unittest.TestCase):
    def test_matches_delayed_scaled_audio(self):
        rng = np.random.default_rng(8)
        reference = rng.normal(0, .1, 48000 * 4)
        recording = reference[48000:48000 * 3] * .4
        samples = np.column_stack((recording, recording))
        result = compare_reference_audio(reference, samples)
        self.assertTrue(result['passed'])
        self.assertAlmostEqual(result['offset_seconds'], 1.5, places=5)

    def test_rejects_frequency_that_aliases_after_decimation(self):
        time = np.arange(48000 * 3) / 48000
        reference = np.sin(2 * np.pi * 12530 * time)
        recording = np.sin(2 * np.pi * 530 * time[:48000 * 2])
        # Both become identical if the 48 kHz arrays are naively sampled at
        # every fourth point; they are different sounds at the original rate.
        np.testing.assert_allclose(reference[:len(recording):4], recording[::4], atol=1e-10)
        samples = np.column_stack((recording, recording))
        self.assertFalse(compare_reference_audio(reference, samples)['passed'])

    def test_rejects_silence_and_nonfinite_input(self):
        rng = np.random.default_rng(9)
        reference = rng.normal(0, .1, 48000 * 3)
        silence = np.zeros((48000 * 2, 2))
        self.assertFalse(compare_reference_audio(reference, silence)['passed'])
        silence[48000, 0] = np.nan
        with self.assertRaises(ValueError):
            compare_reference_audio(reference, silence)


if __name__ == '__main__':
    unittest.main()
