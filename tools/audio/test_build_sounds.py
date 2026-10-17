"""DSP regressions: python -m unittest discover -s tools/audio -p 'test_*.py'.

Set FFMPEG to also check the shipped Vorbis files after encoding/decoding.
"""

import os
import subprocess
import unittest

import numpy as np

import build_sounds as sounds


class ProcessingTests(unittest.TestCase):
    def test_stereo_filter_preserves_channel_separation(self):
        t = np.arange(8000) / 8000
        stereo = np.column_stack((np.sin(2 * np.pi * 200 * t), np.zeros_like(t)))
        filtered = sounds.spectral(stereo, 8000, lambda f: sounds.lowpass(f, 1000))
        self.assertEqual(filtered.shape, stereo.shape)
        np.testing.assert_array_equal(filtered[:, 1], 0)
        self.assertGreater(np.std(filtered[:, 0]), 0.6)

    def test_stereo_loop_uses_shared_edit_points_and_gain(self):
        rng = np.random.default_rng(17)
        left = rng.normal(size=48000)
        stereo = np.column_stack((left, left * 0.25))
        loop = sounds.make_loop(stereo, 8000, 4.0, start=2000, crossfade=1.0)
        self.assertEqual(loop.shape, (32000, 2))
        np.testing.assert_allclose(loop[:, 1], loop[:, 0] * 0.25)

    def test_correlated_crossfade_does_not_swell(self):
        t = np.arange(48000) / 8000
        signal = np.sin(2 * np.pi * 200 * t)
        loop = sounds.make_loop(signal, 8000, 4.0, start=0, crossfade=1.0)
        np.testing.assert_allclose(loop, signal[:len(loop)], atol=1e-10)

    def test_stereo_analysis_keeps_out_of_phase_energy(self):
        signal = np.ones((8000, 2))
        signal[:, 1] *= -1
        np.testing.assert_allclose(sounds.loudness_track(signal, 8000), 0, atol=1e-7)

    def test_fades_handle_short_stereo_clips(self):
        result = sounds.fades(np.ones((20, 2)), 8000)
        self.assertEqual(result.shape, (20, 2))
        np.testing.assert_array_equal(result[[0, -1]], 0)
        self.assertTrue(np.isfinite(result).all())


@unittest.skipUnless(os.environ.get("FFMPEG"), "Set FFMPEG for encoded asset checks")
class EncodedSoundsTests(unittest.TestCase):
    def decode(self, name, channels=1):
        raw = subprocess.run(
            [os.environ["FFMPEG"], "-v", "error", "-i", str(sounds.OUT / (name + ".ogg")),
             "-ac", str(channels), "-ar", "32000", "-f", "f32le", "-"],
            capture_output=True, check=True,
        ).stdout
        return np.frombuffer(raw, np.float32).reshape(-1, channels)

    def test_loop_boundaries_have_no_outlier_click(self):
        for name in ("train_rumble", "air_low", "air_high", "speed_loop", "amb_wind", "engine",
                     "amb_traffic_day", "amb_traffic_night", "amb_city_far", "amb_times_square"):
            with self.subTest(sound=name):
                x = self.decode(name)[:, 0]
                self.assertTrue(np.isfinite(x).all())
                self.assertLess(np.max(np.abs(x)), 1.0)
                normal_step = np.percentile(np.abs(np.diff(x)), 99)
                self.assertLess(abs(x[-1] - x[0]), 3.0 * normal_step)

    def test_beds_keep_stereo_and_longer_loops(self):
        for name in ("amb_traffic_day", "amb_traffic_night", "amb_city_far", "amb_times_square", "amb_birds", "amb_crickets"):
            with self.subTest(sound=name):
                x = self.decode(name, channels=2)
                self.assertGreaterEqual(len(x) / 32000, 11.9)
                self.assertGreater(np.sqrt(np.mean((x[:, 0] - x[:, 1]) ** 2)), 0.005)
                self.assertLess(np.max(np.abs(x)), 1.0)


if __name__ == "__main__":
    unittest.main()
