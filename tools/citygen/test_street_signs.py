"""Street name signs; run python -m unittest discover -s tools/citygen -p test_street_signs.py.

Synthetic streets only: no downloaded data needed.
"""
import unittest

import numpy as np
import shapely
from shapely.geometry import box

import markings
import street_signs
from common import PROP_STREET_SIGN, STREET_SIGN_BLADE, STREET_SIGN_OVERHEAD, STREET_SIGN_POST
from test_roads import _cross

# Name ids: the wide east-west street's segments (0, 1), the narrow one's (2, 3).
WIDE, NARROW = 1500, 7
NAMES = np.array([WIDE, WIDE, NARROW, NARROW], dtype=np.int32)
WIDTHS = np.zeros(2000)
WIDTHS[WIDE] = 3.6
WIDTHS[NARROW] = 20.0


def _road():
    """The two streets' roadbeds: 14 m and 11 m wide."""
    road = shapely.union(box(-100, -7, 100, 7), box(-5.5, -100, 5.5, 100))
    shapely.prepare(road)
    return road


class SignText(unittest.TestCase):
    def test_city_sign_style(self):
        self.assertEqual(street_signs.sign_text("W 42 ST"), "W 42 St")
        self.assertEqual(street_signs.sign_text("LEXINGTON AVE"), "Lexington Av")
        self.assertEqual(street_signs.sign_text("AVE N"), "Av N")
        self.assertEqual(street_signs.sign_text("BCH 116 ST"), "Beach 116 St")
        self.assertEqual(street_signs.sign_text("ST MARKS PL"), "St Marks Pl")
        self.assertEqual(street_signs.sign_text("AVE OF THE AMERICAS"), "Av of the Americas")
        self.assertEqual(street_signs.sign_text("MCDONALD AVE"), "McDonald Av")
        self.assertEqual(street_signs.sign_text("O'BRIEN PL"), "O'Brien Pl")
        self.assertEqual(street_signs.sign_text("WILKES-BARRE ST"), "Wilkes-Barre St")

    def test_ramps_and_connectors_get_none(self):
        self.assertIsNone(street_signs.sign_text("BRONX RVR PKWY SB EN WEBSTER AVE"))
        self.assertIsNone(street_signs.sign_text("CONNECTOR ROAD TO NORTHERN BL EB"))
        self.assertIsNone(street_signs.sign_text(""))


class Corners(unittest.TestCase):
    def setUp(self):
        self.data = _cross()
        self.signs = street_signs.corner_signs(self.data, NAMES, WIDTHS, np.arange(4), (-50, -50, 50, 50), _road())

    def test_two_posts_at_opposite_corners_off_the_road(self):
        en = self.signs["en"]
        self.assertEqual(len(en), 4)  # two posts, two blades each
        posts = np.unique(np.round(en, 3), axis=0)
        self.assertEqual(len(posts), 2)
        np.testing.assert_allclose(posts[0], -posts[1], atol=1e-6)  # diagonally opposite
        for e, n in posts:
            self.assertFalse(shapely.contains_xy(_road(), e, n))
            self.assertLess(abs(e) - 5.5, 2.0)  # at the corner, not down the block
            self.assertLess(abs(n) - 7.0, 2.0)

    def test_blades_name_and_run_along_their_streets(self):
        s = self.signs
        variant = s["tone"] % 4
        name = (s["tone"] // 4) * 1024 + s["trunk"].astype(int)
        self.assertTrue(np.all(s["type"] == PROP_STREET_SIGN))
        self.assertEqual(sorted(variant), [STREET_SIGN_POST] * 2 + [STREET_SIGN_BLADE] * 2)
        # The wider street on top; each blade along its street (+x east-west, north-south).
        np.testing.assert_array_equal(name[variant == STREET_SIGN_BLADE], [WIDE, WIDE])
        np.testing.assert_array_equal(name[variant == STREET_SIGN_POST], [NARROW, NARROW])
        along = np.abs(np.sin(s["yaw"]))
        np.testing.assert_allclose(along[name == WIDE], 0.0, atol=1e-6)
        np.testing.assert_allclose(along[name == NARROW], 1.0, atol=1e-6)
        self.assertTrue(np.all(s["height"][variant == STREET_SIGN_BLADE] > s["height"][variant == STREET_SIGN_POST]))
        # Long names are squeezed onto the longest blade.
        np.testing.assert_allclose(s["width"][name == NARROW], street_signs.BLADE_LENGTH[1])

    def test_a_street_meeting_itself_gets_none(self):
        same = np.full(4, WIDE, dtype=np.int32)
        signs = street_signs.corner_signs(self.data, same, WIDTHS, np.arange(4), (-50, -50, 50, 50), _road())
        self.assertEqual(len(signs["en"]), 0)


class MastArms(unittest.TestCase):
    def test_signals_name_the_street_ahead(self):
        data = _cross()
        points, facing, _, ends = markings.signals(data, np.arange(4), (-50, -50, 50, 50), _road())
        self.assertGreater(len(points), 0)
        cross = street_signs.cross_streets(data, NAMES, np.arange(4), ends)
        for (k, _), name in zip(ends, cross):
            self.assertEqual(name, NARROW if NAMES[k] == WIDE else WIDE)
        signs = street_signs.overhead_signs(points, facing, cross, WIDTHS)
        self.assertTrue(np.all(signs["tone"] % 4 == STREET_SIGN_OVERHEAD))
        # Out over the road, and back on its pole.
        for e, n in signs["en"]:
            self.assertTrue(shapely.contains_xy(_road(), e, n))
        np.testing.assert_allclose(street_signs.arm_poles(signs["en"], signs["yaw"]), points, atol=1e-9)


if __name__ == "__main__":
    unittest.main()
