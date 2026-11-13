"""Tests for scripts/gen_regs.py and analyze.py parsers. No PyTorch, no Vivado needed.

Run from the repo root:
    python -m unittest discover -s sw/py -v
"""
import importlib.util
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

import analyze

REPO = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("gen_regs", REPO / "scripts" / "gen_regs.py")
gen_regs = importlib.util.module_from_spec(_spec)
sys.modules["gen_regs"] = gen_regs   # dataclasses need the module registered
_spec.loader.exec_module(gen_regs)

GOOD = """
meta: {name: dnn, data_width: 32, addr_width: 12, version: 3}
registers:
  - name: CTRL
    offset: 0x000
    access: rw
    fields:
      - {name: START, bits: "0"}
      - {name: MODE, bits: "3:2"}
  - name: CYCLES
    offset: 0x008
    access: ro
    fields:
      - {name: COUNT, bits: "31:0"}
"""


class TestGenRegs(unittest.TestCase):

    def load(self, text):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "r.yaml"
            p.write_text(textwrap.dedent(text))
            return gen_regs.load(p)

    def test_good_map(self):
        meta, regs = self.load(GOOD)
        self.assertEqual([r.name for r in regs], ["CTRL", "CYCLES"])
        mode = regs[0].fields[1]
        self.assertEqual((mode.lsb, mode.width, mode.mask), (2, 2, 0xC))
        self.assertIn("CTRL_MODE_MASK = 32'h0000000C", gen_regs.gen_sv(meta, regs))
        self.assertIn("#define DNN_CYCLES_ADDR 0x008u", gen_regs.gen_c(meta, regs))
        ns = {}
        exec(gen_regs.gen_py(meta, regs), ns)
        self.assertEqual(ns["REGS"]["CTRL"], (0, "rw", {"START": (0, 1), "MODE": (2, 2)}))

    def test_rejects_bad_maps(self):
        bad = {
            "misaligned":   GOOD.replace("0x008", "0x006"),
            "duplicate":    GOOD.replace("0x008", "0x000"),
            "overlap":      GOOD.replace('bits: "3:2"', 'bits: "1:0"'),
            "too wide":     GOOD.replace('"31:0"', '"32:0"'),
            "bad access":   GOOD.replace("access: ro", "access: rx"),
            "out of range": GOOD.replace("0x008", "0x1000"),
        }
        for name, text in bad.items():
            with self.subTest(name):
                with self.assertRaises(gen_regs.RegmapError):
                    self.load(text)

    def test_real_regmap_is_valid(self):
        self.assertEqual(gen_regs.main(["--check"]), 0)


class TestAnalyze(unittest.TestCase):

    def test_board_log(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "run.log").write_text(
                "boot...\nRESULT design=equal workload=2x_lenet5 cycles=18000 pass=1\n"
                "RESULT design=sequential workload=2x_lenet5 cycles=20500 pass=0\nRESULT garbage\n")
            got = analyze.parse_board_logs(Path(d))
        self.assertEqual(got[("equal", "2x_lenet5")], {"cycles": 18000, "pass": True})
        self.assertFalse(got[("sequential", "2x_lenet5")]["pass"])

    def test_vivado_reports(self):
        util = textwrap.dedent("""\
            | Slice LUTs              | 12345 |     0 |          0 |     53200 | 23.20 |
            | Slice Registers         |  9000 |     0 |          0 |    106400 |  8.46 |
            | Block RAM Tile          |    20 |     0 |          0 |       140 | 14.29 |
            | DSPs                    |   148 |     0 |          0 |       220 | 67.27 |
            """)
        timing = "    WNS(ns)      TNS(ns)\n    -------      -------\n      0.412        0.000\n"
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "util_12x12.rpt").write_text(util)
            (Path(d) / "timing_12x12.rpt").write_text(timing)
            u = analyze.parse_utilization(Path(d) / "util_12x12.rpt")
            self.assertEqual(u["DSP"], (148.0, 67.27))
            self.assertEqual(analyze.parse_wns(Path(d) / "timing_12x12.rpt"), 0.412)
            self.assertEqual(analyze.size_of(Path(d) / "util_12x12.rpt"), "12x12")

    def test_report_labels_every_number(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "results").mkdir()
            text = analyze.build_report(Path(d))
        for header in [l for l in text.splitlines() if l.startswith("| Workload")]:
            cols = header.strip("|").split("|")[2:]
            for c in cols:
                self.assertTrue(any(w in c for w in ("ESTIMATED", "MEASURED", "Board check")), c)


if __name__ == "__main__":
    unittest.main(verbosity=2)
