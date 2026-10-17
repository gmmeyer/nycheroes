"""Geometry regressions; run python -m unittest discover -s tools/citygen -p test_geometry.py.

Small synthetic cases run without the city's downloaded data. With NYC_DATA_DIR
set, the cached building checks also exercise the real landmark footprints.
"""
import unittest

import numpy as np
import shapely
from shapely.geometry import Polygon

import landmarks
import buildings3d
from common import CACHE_DIR, MeshBuilder, triangulate_planar


class PlanarFaces(unittest.TestCase):
    def test_courtyard_walls_face_open_courtyard(self):
        roof = np.array([[0, 0, 10], [10, 0, 10], [10, 10, 10], [0, 10, 10]], float)
        hole = np.array([[2, 2, 10], [2, 8, 10], [8, 8, 10], [8, 2, 10]], float)
        wall = np.array([[2, 2, 0], [2, 8, 0], [2, 8, 10], [2, 2, 10]], float)
        for reverse in (False, True):
            rings = [roof.copy(), hole.copy(), wall[::-1].copy() if reverse else wall.copy()]
            buildings3d._face_outward(rings, [0, 0, 1], np.array([buildings3d.ROOF, buildings3d.WALL]))
            np.testing.assert_allclose(buildings3d.polygon_normal(rings[-1]), [1, 0, 0])

    def check_face(self, xy, holes=(), wall=False):
        def lift(ring):
            p = np.column_stack([ring, np.full(len(ring), 7.0)])
            return p[:, [0, 2, 1]] if wall else p
        rings = [lift(np.asarray(r)) for r in [xy, *holes]]
        tris = triangulate_planar(rings)
        self.assertIsNotNone(tris)
        flat = tris[..., [0, 2] if wall else [0, 1]]
        pieces = [Polygon(t) for t in flat]
        expected = Polygon(xy, holes)
        self.assertLess(shapely.union_all(pieces).symmetric_difference(expected).area, 1e-7)
        self.assertAlmostEqual(sum(t.area for t in pieces), expected.area)

    def test_concave_quad_every_start_and_winding(self):
        # The old 0->2 diagonal crosses outside for two of these starts.
        ring = np.array([[0, 0], [1, 1], [4, 0], [0, 4]], float)
        for start in range(4):
            for reverse in (False, True):
                for wall in (False, True):
                    r = np.roll(ring, start, axis=0)
                    self.check_face(r[::-1] if reverse else r, wall=wall)

    def test_convex_and_courtyard(self):
        self.check_face([[0, 0], [4, 0], [4, 4], [0, 4]])
        self.check_face([[0, 0], [8, 0], [8, 8], [0, 8]],
                        holes=[[[2, 2], [2, 6], [6, 6], [6, 2]]])


class MidtownLandmarks(unittest.TestCase):
    names = ("New York Times Building", "Seagram Building", "Lever House", "MetLife Building")

    def test_models_and_material_routing_at_every_lod(self):
        selected = [lm for lm in landmarks.LANDMARKS if lm.name in self.names]
        self.assertEqual(len(selected), 4)
        for lm in selected:
            bounds = []
            for detail in range(3):
                model, frame = landmarks.build(lm, shapely.box(-60, -30, 62, 35), None, detail)
                pos = np.concatenate(model.pos)
                self.assertTrue(np.isfinite(pos).all(), lm.name)
                self.assertLess(len(pos), 6000, lm.name)
                bounds.append(np.stack([pos.min(axis=(0, 1)), pos.max(axis=(0, 1))]))
                buildings, own, waterfront = MeshBuilder(), MeshBuilder(), MeshBuilder()
                landmarks.place(model, buildings, frame, 12.0, own, waterfront)
                self.assertTrue(own.pos, lm.name)
                self.assertFalse(waterfront.pos, lm.name)
                codes = np.concatenate(model.code).astype(int) % landmarks.FLAG_SCALE
                self.assertTrue(np.isin(codes, range(64)).all())
            np.testing.assert_allclose(bounds[0], bounds[1], atol=0.5, err_msg=lm.name)
            np.testing.assert_allclose(bounds[0], bounds[2], atol=0.5, err_msg=lm.name)

    @unittest.skipUnless((CACHE_DIR / "buildings.pkl").exists(), "city data not available")
    def test_actual_footprints(self):
        import buildings3d
        import prepare
        data, shapes = prepare.load("buildings"), buildings3d.load()
        for lm in landmarks.LANDMARKS:
            if lm.name not in self.names:
                continue
            k = np.flatnonzero(data["bin"] == lm.bins[0])
            self.assertEqual(len(k), 1, lm.name)
            bounds = []
            for detail in range(3):
                model, _ = landmarks.build(lm, data["geoms"][k[0]], shapes.get(lm.bins[0]), detail)
                pos = np.concatenate(model.pos)
                self.assertTrue(np.isfinite(pos).all(), lm.name)
                bounds.append(np.stack([pos.min(axis=(0, 1)), pos.max(axis=(0, 1))]))
            np.testing.assert_allclose(bounds[0], bounds[2], atol=0.5, err_msg=lm.name)


if __name__ == "__main__":
    unittest.main()
