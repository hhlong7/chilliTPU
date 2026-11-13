"""Tests for vecgen.py: hex round trip, case contents, and network cases. No PyTorch needed.

Run from the repo root:
    python -m unittest discover -s sw/py -v
"""
import tempfile
import unittest
from pathlib import Path

import numpy as np

import golden
import vecgen
from quantize import QuantizedLayer, export_layers, int8_forward, weight_to_kn
from test_golden import SEED


class TestHex(unittest.TestCase):

    def test_round_trip_and_format(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "v.hex"
            vals = np.array([[-128, -1, 0], [1, 127, 5]])
            vecgen.write_hex(p, vals, 8)
            self.assertEqual(p.read_text().split(), ["80", "FF", "00", "01", "7F", "05"])
            self.assertEqual(vecgen.read_hex(p, 8, (2, 3)).tolist(), vals.tolist())
            big = np.array([-2 ** 31, -1, 2 ** 31 - 1])
            vecgen.write_hex(p, big, 32)
            self.assertEqual(p.read_text().split(), ["80000000", "FFFFFFFF", "7FFFFFFF"])
            self.assertEqual(vecgen.read_hex(p, 32).tolist(), big.tolist())


class TestCases(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.tmp.name)
        cls.rc = vecgen.main(["--out", str(cls.root)])

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_every_layer_case_matches_golden(self):
        self.assertEqual(self.rc, 0)
        dirs = sorted((self.root / "layer").iterdir()) + sorted((self.root / "systolic_array").iterdir())
        self.assertGreater(len(dirs), 20)
        for d in dirs:
            with self.subTest(case=d.name):
                c = vecgen.load_case(d)
                m = c["meta"]
                acc = golden.matmul_int8(c["x"], c["w"])
                self.assertEqual(c["acc_expected"].tolist(), acc.tolist())
                y = golden.requantize(acc, c["bias"], m["scale"], m["shift"], m["relu"])
                self.assertEqual(c["y_expected"].tolist(), y.tolist())
                meta_txt = dict(line.split("=", 1) for line in (d / "meta.txt").read_text().split())
                self.assertEqual(int(meta_txt["K"]), m["K"])

    def test_out_stage_cases(self):
        for d in sorted((self.root / "out_stage").iterdir()):
            with self.subTest(case=d.name):
                c = vecgen.load_case(d)
                m = c["meta"]
                y = golden.requantize(c["acc"], c["bias"], m["scale"], m["shift"], m["relu"])
                self.assertEqual(c["y_expected"].tolist(), y.tolist())

    def test_required_edge_cases_present(self):
        names = {p.name for p in (self.root / "layer").iterdir()}
        for need in ("extreme_min_min", "zeros", "k_gt_rows_n_gt_cols", "k_not_multiple", "n_multi_tile"):
            self.assertIn(need, names)

    def test_deterministic(self):
        with tempfile.TemporaryDirectory() as d:
            vecgen.main(["--out", d, "--only", "layer"])
            for p in (Path(d) / "layer").rglob("*.hex"):
                self.assertEqual(p.read_bytes(), (self.root / p.relative_to(d)).read_bytes(), str(p))


class TestNetworkCases(unittest.TestCase):

    def test_chain_matches_int8_forward(self):
        rng = np.random.default_rng(SEED)

        def L(name, kind, w, n, relu, **g):
            return QuantizedLayer(name=name, kind=kind, weight_int8=weight_to_kn(w),
                                  bias_int32=rng.integers(-3000, 3000, n).astype(np.int32),
                                  input_step=1.0, weight_step=1.0, output_step=1.0, scale=900, shift=17,
                                  real_multiplier=0.0, multiplier_error=0.0, relu=relu, **g)

        layers = [L("conv1", "conv2d", rng.integers(-128, 128, (3, 1, 3, 3), dtype=np.int8), 3, True,
                    kernel=(3, 3), pool=2),
                  L("conv2", "conv2d", rng.integers(-128, 128, (4, 3, 3, 3), dtype=np.int8), 4, True,
                    kernel=(3, 3), padding=1, pool=2),
                  L("fc1", "linear", rng.integers(-128, 128, (5, 16), dtype=np.int8), 5, False)]
        x = rng.random((3, 1, 10, 10)).astype(np.float32)
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            export_layers(layers, d / "model", "tiny", 1 / 127)
            np.savez(d / "img.npz", x=x, y=np.array([1, 2, 3]))
            cases = vecgen.network_cases(d / "model", d / "img.npz", n_images=3)
        exp = int8_forward(layers, np.clip(np.rint(x * 127), -128, 127).astype(np.int8))
        self.assertEqual([c.name for c in cases], ["00_conv1", "01_conv2", "02_fc1", "result"])
        self.assertEqual(cases[-1].arrays["y_expected"].tolist(), exp.tolist())
        self.assertEqual(cases[0].meta["M"], 3 * 8 * 8)        # im2col rows: batch x 8 x 8
        self.assertEqual(cases[2].meta["K"], 16)               # 4 channels x 2 x 2 after pool


if __name__ == "__main__":
    unittest.main(verbosity=2)
