"""Record loopback audio and preserve capture-integrity warnings."""

import threading
import warnings


_capture_lock = threading.Lock()


def record_loopback(loopback, warning_category, *, samplerate, numframes, channels):
    # Warning filters are process-global. Only one capture may own the filter.
    with _capture_lock, warnings.catch_warnings(record=True) as captured:
        warnings.simplefilter('always', warning_category)
        data = loopback.record(samplerate=samplerate, numframes=numframes,
                               channels=channels)
        discontinuities = sum('data discontinuity in recording' in str(w.message)
                              for w in captured)
        other_warnings = [str(w.message) for w in captured
                          if 'data discontinuity in recording' not in str(w.message)]
    return data, discontinuities, other_warnings


def apply_capture_integrity(report, discontinuities):
    report['capture_discontinuities'] = discontinuities
    if discontinuities:
        report['passed'] = False
        report['capture_error'] = 'Windows loopback reported discontinuities'
    return report
