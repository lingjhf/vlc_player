"""Ensure a loopback glitch invalidates even a matching recording."""
from pathlib import Path
import sys
import unittest
import warnings

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tool'))
from windows_audio_capture import apply_capture_integrity, record_loopback


class LoopbackWarning(RuntimeWarning):
    pass


class FakeLoopback:
    def __init__(self, glitch):
        self.glitch = glitch

    def record(self, *, samplerate, numframes, channels):
        if self.glitch:
            warnings.warn('data discontinuity in recording', LoopbackWarning)
            warnings.warn('data discontinuity in recording', LoopbackWarning)
            warnings.warn('another capture warning', LoopbackWarning)
        return (samplerate, numframes, channels)


class WindowsAudioCaptureTest(unittest.TestCase):
    def test_discontinuity_rejects_otherwise_passing_capture(self):
        for glitch, expected_count in ((False, 0), (True, 2)):
            with self.subTest(glitch=glitch):
                data, count, other = record_loopback(
                    FakeLoopback(glitch), LoopbackWarning,
                    samplerate=48000, numframes=96000, channels=2)
                self.assertEqual(data, (48000, 96000, 2))
                self.assertEqual(count, expected_count)
                self.assertEqual(other, ['another capture warning'] if glitch else [])
                report = apply_capture_integrity({'passed': True}, count)
                self.assertEqual(report['passed'], not glitch)
                self.assertEqual(report['capture_discontinuities'], expected_count)


if __name__ == '__main__':
    unittest.main()
