"""Compare a loopback recording to a full-rate decoded reference."""

import numpy as np


def compare_reference_audio(reference, samples, sample_rate=48000, threshold=0.8):
    """Find the best one-window waveform match without aliasing frequencies."""
    reference = np.asarray(reference, dtype=np.float64).reshape(-1).copy()
    samples = np.asarray(samples, dtype=np.float64)
    if samples.ndim != 2 or samples.shape[1] < 1 or sample_rate <= 0:
        raise ValueError('Invalid audio capture')
    observed = samples.mean(axis=1)
    # A two-second capture supplies a one-second middle window. Capture and
    # player startup have independent, unknown latency, so search all offsets.
    observed = observed[len(observed) // 4:len(observed) * 3 // 4].copy()
    if len(observed) < 1000 or len(reference) < len(observed):
        raise ValueError('Reference or capture is too short for audio comparison')
    if not np.isfinite(reference).all() or not np.isfinite(observed).all():
        raise ValueError('Reference or capture contains non-finite samples')
    observed -= observed.mean()
    reference -= reference.mean()
    fft_size = 1 << (len(reference) + len(observed) - 2).bit_length()
    dot = np.fft.irfft(np.fft.rfft(reference, fft_size)
                       * np.conj(np.fft.rfft(observed, fft_size)), fft_size)
    dot = dot[:len(reference) - len(observed) + 1]
    energy = np.concatenate(([0.0], np.cumsum(reference * reference)))
    energy = energy[len(observed):] - energy[:-len(observed)]
    denominator = np.sqrt(np.maximum(energy, 0) * np.sum(observed * observed))
    correlation = np.divide(np.abs(dot), denominator, out=np.zeros_like(dot),
                            where=denominator > 1e-10)
    peak = float(np.max(correlation))
    return {'correlation': round(peak, 4),
            'offset_seconds': round(float(np.argmax(correlation)) / sample_rate, 6),
            'minimum_correlation': threshold, 'passed': peak >= threshold}
