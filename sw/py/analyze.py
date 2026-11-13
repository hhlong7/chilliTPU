"""Turn sim logs, board UART logs, and Vivado reports into tables for the report.

golden.py and vecgen.py prove the hardware computes the right answer.
cyclemodel.py predicts how fast it should be and which design is worth building.
analyze.py puts the prediction next to what the board actually measured.

Rule: every table column is labeled MEASURED or ESTIMATED (PROJECT_PLAN.md section 8).

Usage (from the repo root):
    python3 sw/py/analyze.py                 # or `make report` -> results/report.md
    python3 sw/py/analyze.py --stdout        # print instead of writing

Inputs (all optional; missing ones show as "-" and are listed under "Missing"):
  build/<tb>/*.log                 UVM logs from `make sim` (PASS/FAIL lines)
  results/board/*.log              board UART captures. The firmware prints one line per run:
                                       RESULT design=<sequential|equal|proportional> workload=<name> cycles=<n> pass=<0|1>
                                   (design matches CTRL.MODE 0/1/2; workload names are WORKLOADS below)
  results/vivado/*utilization*.rpt Vivado report_utilization output, one per build. The file
                                   name should contain the array size, e.g. util_12x12.rpt
  results/vivado/*timing*.rpt      Vivado report_timing_summary output (WNS)
  results/accuracy_*.md            written by train.py (linked, not parsed)
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import cyclemodel as cm

REPO = Path(__file__).resolve().parents[2]
DESIGNS = ("sequential", "equal", "proportional")   # CTRL.MODE 0, 1, 2

# Standard workloads: the firmware runs exactly these, all networks arriving at cycle 0.
WORKLOADS = {
    "2x_lenet5":       ["lenet5", "lenet5"],
    "lenet5+mnist_fc": ["lenet5", "mnist_fc"],
    "cifar+mnist_fc":  ["cifar_cnn", "mnist_fc"],
    "4_mixed":         ["lenet5", "mnist_fc", "cifar_cnn", "mnist_fc"],
}

RESULT_RE = re.compile(r"RESULT\s+(.*)")
UTIL_ROWS = {"Slice LUTs": "LUT", "Slice Registers": "FF", "Block RAM Tile": "BRAM", "DSPs": "DSP"}


# --------------------------------------------------------------------------- estimates
def networks_for(workload: str) -> list[cm.Network]:
    return [cm.Network(f"t{i}_{m}", cm.MODEL_ZOO[m]()) for i, m in enumerate(WORKLOADS[workload])]


def estimate(workload: str, design: str, feed: str, shadow: bool) -> int:
    nets = networks_for(workload)
    if design == "sequential":
        return cm.run_sequential(nets, shadow)["makespan"]
    return cm.simulate(nets, design, feed, shadow)["makespan"]


# --------------------------------------------------------------------------- measured inputs
def parse_sim_logs(build: Path) -> dict[str, tuple[int, int]]:
    """tb -> (passed, failed) from the newest `make sim` logs."""
    out = {}
    for tb_dir in sorted(p for p in build.glob("*") if p.is_dir()):
        logs = list(tb_dir.glob("*.log"))
        logs = [p for p in logs if p.name != "build.log"]
        if not logs:
            continue
        passed = sum(1 for p in logs if re.search(r"^PASS ", p.read_text(errors="replace"), re.M))
        out[tb_dir.name] = (passed, len(logs) - passed)
    return out


def parse_board_logs(board: Path) -> dict[tuple[str, str], dict]:
    """(design, workload) -> {cycles, pass}; the last line wins if a run is repeated."""
    out = {}
    for p in sorted(board.glob("*.log")):
        for line in p.read_text(errors="replace").splitlines():
            m = RESULT_RE.search(line)
            if not m:
                continue
            kv = dict(tok.split("=", 1) for tok in m.group(1).split() if "=" in tok)
            try:
                out[(kv["design"], kv["workload"])] = {"cycles": int(kv["cycles"]), "pass": kv.get("pass") == "1"}
            except (KeyError, ValueError):
                print(f"analyze.py: skipping malformed line in {p.name}: {line.strip()}", file=sys.stderr)
    return out


def parse_utilization(path: Path) -> dict[str, tuple[float, float]]:
    """resource -> (used, util%) from a Vivado report_utilization table."""
    out = {}
    for line in path.read_text(errors="replace").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 5 and cells[0] in UTIL_ROWS and UTIL_ROWS[cells[0]] not in out:
            try:
                out[UTIL_ROWS[cells[0]]] = (float(cells[1]), float(cells[-1].lstrip("<")))
            except ValueError:
                pass
    return out


def parse_wns(path: Path) -> float | None:
    lines = path.read_text(errors="replace").splitlines()
    for i, line in enumerate(lines):
        if "WNS(ns)" in line:
            for nxt in lines[i + 1:i + 4]:
                m = re.match(r"\s*(-?\d+\.\d+)", nxt)
                if m:
                    return float(m.group(1))
    return None


def size_of(path: Path) -> str:
    m = re.search(r"(\d+)x(\d+)", path.name)
    return f"{m.group(1)}x{m.group(2)}" if m else path.stem


# --------------------------------------------------------------------------- report
def fmt(v, spec="{:,}") -> str:
    return "-" if v is None else spec.format(v)


def build_report(root: Path) -> str:
    build, board_dir, viv = root / "build", root / "results" / "board", root / "results" / "vivado"
    sim = parse_sim_logs(build) if build.exists() else {}
    board = parse_board_logs(board_dir) if board_dir.exists() else {}
    missing = []
    out = ["# chilliTPU results", "",
           "Generated by `python3 sw/py/analyze.py`. Columns say MEASURED (board, sim, Vivado) or ",
           "ESTIMATED (cyclemodel.py). Never compare the two without saying which is which.", ""]

    # 1. cycles: estimated vs measured
    out += ["## Cycles per workload", "",
            "The per-partition feed + shadow column is the design we build; MEASURED / EST compares against it. ",
            "Shared feed without shadow weights is the paper-faithful baseline.", "",
            "| Workload | Design | ESTIMATED shared feed, no shadow | ESTIMATED per-partition feed + shadow | MEASURED board | MEASURED / EST | Board check |",
            "|---|---|---|---|---|---|---|"]
    for wl in WORKLOADS:
        for d in DESIGNS:
            est_a = estimate(wl, d, "A", False)
            est_b = estimate(wl, d, "B", True)
            meas = board.get((d, wl))
            ratio = f"{meas['cycles'] / est_b:.2f}" if meas else "-"
            check = "-" if not meas else ("PASS" if meas["pass"] else "**FAIL**")
            out.append(f"| {wl} | {d} | {est_a:,} | {est_b:,} | {fmt(meas and meas['cycles'])} | {ratio} | {check} |")
    out.append("")
    if not board:
        missing.append("board UART logs in results/board/*.log (RESULT lines)")

    # 2. speedups (relative to sequential, same column type only)
    out += ["## Speedup over sequential", "", "| Workload | Design | ESTIMATED (per-partition feed + shadow) | MEASURED |", "|---|---|---|---|"]
    for wl in WORKLOADS:
        base_e = estimate(wl, "sequential", "B", True)
        base_m = board.get(("sequential", wl))
        for d in DESIGNS[1:]:
            e = base_e / estimate(wl, d, "B", True)
            m = board.get((d, wl))
            ms = f"{base_m['cycles'] / m['cycles']:.2f}x" if (m and base_m) else "-"
            out.append(f"| {wl} | {d} | {e:.2f}x | {ms} |")
    out.append("")

    # 3. FPGA resources
    out += ["## FPGA resources and timing (MEASURED, Vivado)", ""]
    utils = sorted(viv.glob("*utilization*.rpt")) + sorted(viv.glob("*util_*.rpt")) if viv.exists() else []
    utils = list(dict.fromkeys(utils))
    if utils:
        timings = {size_of(p): parse_wns(p) for p in viv.glob("*timing*.rpt")}
        out += ["| Build | LUT | FF | BRAM | DSP | WNS (ns) |", "|---|---|---|---|---|---|"]
        for p in utils:
            u = parse_utilization(p)
            cell = lambda k: f"{u[k][0]:g} ({u[k][1]:g}%)" if k in u else "-"
            out.append(f"| {size_of(p)} | {cell('LUT')} | {cell('FF')} | {cell('BRAM')} | {cell('DSP')} | "
                       f"{fmt(timings.get(size_of(p)), '{:.3f}')} |")
    else:
        out.append("No Vivado reports yet.")
        missing.append("Vivado reports in results/vivado/ (report_utilization, report_timing_summary)")
    out.append("")

    # 4. verification
    out += ["## Verification (MEASURED, simulation)", ""]
    if sim:
        out += ["| Testbench | Tests passed | Tests failed |", "|---|---|---|"]
        out += [f"| {tb} | {p} | {f} |" for tb, (p, f) in sim.items()]
    else:
        out.append("No sim logs yet (run `make sim`).")
        missing.append("sim logs in build/<tb>/ (run make sim)")
    out.append("")

    # 5. accuracy
    acc = sorted((root / "results").glob("accuracy_*.md"))
    out += ["## Accuracy (MEASURED in software)", ""]
    out += [f"- [{p.stem}]({p.name})" for p in acc] or ["None yet (run `python3 sw/py/train.py --model lenet5`)."]
    out.append("")

    if missing:
        out += ["## Missing inputs", ""] + [f"- {m}" for m in missing] + [""]
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Build results/report.md from logs and reports.")
    ap.add_argument("--root", type=Path, default=REPO)
    ap.add_argument("--stdout", action="store_true")
    args = ap.parse_args(argv)
    text = build_report(args.root)
    if args.stdout:
        print(text)
    else:
        path = args.root / "results" / "report.md"
        path.write_text(text)
        print(f"analyze.py: wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
