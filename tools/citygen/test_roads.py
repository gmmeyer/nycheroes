"""Road placement regressions; run python -m unittest discover -s tools/citygen -p test_roads.py.

Synthetic streets only: no downloaded data needed.
"""
import unittest
from unittest import mock

import numpy as np
import shapely
from shapely.geometry import LineString, box, mapping

import markings
import overpasses
import traffic


def _feature(line, trafdir, lanes, width_ft):
    return {"geometry": mapping(line), "properties": {
        "from_level_code": "13", "to_level_code": "13", "rw_type": 1, "trafdir": trafdir,
        "number_travel_lanes": lanes, "number_park_lanes": 0, "streetwidth": width_ft, "status": "2"}}


def _cross():
    """A 14 m wide two-way street (east-west) crossing a 11 m wide one-way one."""
    wide = [LineString([(-100, 0), (0, 0)]), LineString([(0, 0), (100, 0)])]
    narrow = [LineString([(0, -100), (0, 0)]), LineString([(0, 0), (0, 100)])]
    features = [_feature(line, "TW", 2, 46) for line in wide] + [_feature(line, "FT", 2, 36) for line in narrow]
    with mock.patch.object(markings, "load_features", lambda name: features), \
            mock.patch.object(markings, "project", lambda geoms: geoms):
        return markings.prepare()


class Setbacks(unittest.TestCase):
    def test_setback_is_the_crossing_streets_half_width(self):
        data = _cross()
        # Ends at the node: the wide street's (0 and 1) clear the narrow street's
        # 5.5 m half width, the narrow one's (2 and 3) the wide street's 7 m.
        np.testing.assert_allclose(data["setback"][0, 1], 5.49 + markings.CROSSWALK_SETBACK, atol=0.02)
        np.testing.assert_allclose(data["setback"][1, 0], 5.49 + markings.CROSSWALK_SETBACK, atol=0.02)
        np.testing.assert_allclose(data["setback"][2, 1], 7.01 + markings.CROSSWALK_SETBACK, atol=0.02)
        np.testing.assert_allclose(data["setback"][3, 0], 7.01 + markings.CROSSWALK_SETBACK, atol=0.02)

    def test_crosswalks_start_at_the_crossing_curb(self):
        data = _cross()
        road = shapely.union_all([LineString(line).buffer(half, cap_style="flat")
                                  for line, half in zip(data["lines"], (7.01, 7.01, 5.49, 5.49))])
        crosswalks = markings.quads(data, np.arange(4), (-200, -200, 200, 200), road)[markings.GROUND_MARKING_CROSSWALK][0]
        along_wide = [q for q in crosswalks if abs(q.mean(axis=0)[1]) < 1.0]  # across the wide street
        nearest = min(abs(q[:, 0]).min() for q in along_wide)
        self.assertAlmostEqual(nearest, 5.49 + markings.CROSSWALK_SETBACK, delta=0.05)


class LaneBends(unittest.TestCase):
    def test_lanes_get_points_on_the_ground_grid(self):
        line = np.array([[3.0, 3.0], [47.0, 3.0], [47.0, 25.0]])
        cut = traffic._grid_cuts(line, 20.0)
        np.testing.assert_allclose(cut[:, 0][:4], [3.0, 20.0, 40.0, 47.0])
        np.testing.assert_allclose(cut[-2:], [[47.0, 20.0], [47.0, 25.0]])
        self.assertEqual(len(cut), 6)

    def test_points_on_the_grid_are_not_doubled(self):
        line = np.array([[0.0, 0.0], [40.0, 0.0]])
        np.testing.assert_allclose(traffic._grid_cuts(line, 20.0), [[0, 0], [20, 0], [40, 0]])


def _slab(x0, x1, y0, y1, half=6.0):
    """Deck top triangles (Godot space) over x0..x1 east, -half..half north,
    rising from y0 to y1."""
    a, b = [x0, y0, half], [x1, y1, half]
    c, d = [x1, y1, -half], [x0, y0, -half]
    return np.array([[a, b, c], [a, c, d]], dtype=np.float64)


class _Network:
    """Just what road_height and _tracked ask of an overpasses.Network: one
    segment, at its own height `own` everywhere."""
    def __init__(self, own, raised, rw=overpasses.BRIDGE):
        self.own, self.raised = own, np.array([raised])
        self.under = np.array([False])
        self.data = {"rw": np.array([rw])}

    def along(self, k, en):
        return np.full(len(en), self.own)


class DeckHeights(unittest.TestCase):
    # Land west of x = 100, water east of it.
    land = box(-1000.0, -100.0, 100.0, 100.0)

    def surface(self, *slabs):
        return overpasses.DeckSurface({}, 0, 0, tris=[np.concatenate(slabs)])

    def test_street_level_bridge_keeps_off_a_deck_overhead_and_follows_its_own(self):
        # Another road's deck 30 m up over x 20..60; the bridge's own deck
        # climbs from the street at x 70 to 6 m at the water and holds over it.
        surface = self.surface(_slab(20, 60, 30, 30), _slab(70, 100, 2, 6), _slab(100, 200, 6, 6))
        en = np.column_stack([np.arange(0.0, 201.0, 5.0), np.zeros(41)])
        y = overpasses._tracked(_Network(2.0, raised=False), surface, 0, en, self.land)
        self.assertTrue(np.all(y[(en[:, 0] >= 20) & (en[:, 0] <= 60)] < 3.0))
        np.testing.assert_allclose(y[en[:, 0] == 85.0], 4.0, atol=0.1)
        np.testing.assert_allclose(y[en[:, 0] >= 100], 6.0, atol=0.1)
        self.assertLess(np.abs(np.diff(y)).max(), 2.0)

    def test_raised_road_on_land_keeps_off_another_deck(self):
        en = np.column_stack([np.arange(10.0, 60.0, 5.0), np.zeros(10)])
        network = _Network(10.0, raised=True, rw=overpasses.RAMP)
        y, found = overpasses.road_height(network, self.surface(_slab(0, 80, 25, 25)), 0, en, self.land)
        np.testing.assert_allclose(y, 10.0)
        self.assertFalse(found.any())
        y, found = overpasses.road_height(network, self.surface(_slab(0, 80, 11, 11)), 0, en, self.land)
        np.testing.assert_allclose(y, 11.0)
        self.assertTrue(found.all())

    def test_raised_road_over_the_water_takes_the_deck(self):
        en = np.column_stack([np.arange(120.0, 180.0, 5.0), np.zeros(12)])
        network = _Network(10.0, raised=True)
        y, found = overpasses.road_height(network, self.surface(_slab(100, 200, 25, 25)), 0, en, self.land)
        np.testing.assert_allclose(y, 25.0)
        self.assertTrue(found.all())


if __name__ == "__main__":
    unittest.main()
