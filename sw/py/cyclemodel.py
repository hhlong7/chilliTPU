"""Cycle-level model of the partitioned systolic array (Milestone 1).

Assumptions (keep in sync with results/cyclemodel.md):
  - Weight-stationary array, ROWS x COLS, 1 cycle per PE hop (D4).
  - Tiling: N tiles outer, K tiles inner, all M rows streamed per pass (D3).
  - Baseline (paper): weight load and compute are serialized.
  - Shadow weights: the next pass's weights load while the current pass streams.
  - Partitions only resize between passes, never mid-pass.
  - v1 counts free columns only (contiguity ignored).
"""
from __future__ import annotations

import sys
from dataclasses import dataclass
from spec import COLS, ROWS
from math import ceil
import heapq
from collections import deque

@dataclass(frozen=True)
class Layer:
    """One matmul Y[M,N] = X[M,K] @ W[K,N] (convs already lowered with im2col)."""
    name: str
    M: int
    K: int
    N: int

    @property
    def macs(self) -> int:
        return self.M * self.K * self.N


@dataclass
class Network:
    name: str
    layers: list[Layer]
    arrival: int = 0          # cycle the network becomes ready


def lenet5(batch: int = 1) -> list[Layer]:
    """LeNet-5 after im2col. Confirm the architecture with quantize.py."""
    return [
        Layer("conv1", 784 * batch, 25, 6),     # 1->6, 5x5, 28x28 out
        Layer("conv2", 100 * batch, 150, 16),   # 6->16, 5x5, 10x10 out
        Layer("fc1", batch, 400, 120),
        Layer("fc2", batch, 120, 84),
        Layer("fc3", batch, 84, 10),
    ]


def passes(layer: Layer, w: int, rows: int = ROWS) -> list[tuple[int, int, int]]:
    """Every pass of a layer on a partition of width w, in D3 order.

    Returns (k0, n0, w_eff) for each pass: N tiles outer, K tiles inner.
    """
    out = []
    for n0 in range(0, layer.N, w):
        w_eff = min(w, layer.N - n0)
        for k0 in range(0, layer.K, rows):
            out.append((k0, n0, w_eff))
    return out


def pass_phases(M: int, w_eff: int, rows: int = ROWS) -> tuple[int, int, int]:
    """(load, stream, drain) cycles for one pass, baseline (no shadow weights).

    load   = rows               weights shift down each column
    stream = M                  one X row enters per cycle (this is what holds the feed)
    drain  = rows + w_eff - 1   last result: skew down rows, across w_eff columns
    """
    return rows, M, rows + w_eff - 1


def layer_cycles(layer: Layer, w: int, shadow: bool = False, rows: int = ROWS) -> int:
    """Cycles to run one layer alone on a partition of width w.

    Baseline: every pass pays load + stream + drain, one after another.
    Shadow:   the next pass's weights load during the current stream, and the
              swap ripples down with the data, so passes run back to back.
              Pass 0 pays the full load, pass i pays max(0, rows - previous stream),
              and only the last pass pays its drain.
    """
    t = 0
    prev_stream = None
    plist = passes(layer, w, rows)
    for _, _, w_eff in plist:
        load, stream, drain = pass_phases(layer.M, w_eff, rows)
        if not shadow:
            t += load + stream + drain
        else:
            t += (load if prev_stream is None else max(0, load - prev_stream)) + stream
        prev_stream = stream
    if shadow:
        t += pass_phases(layer.M, plist[-1][2], rows)[2]
    return t


def utilization(macs: int, cycles: int, rows: int = ROWS, cols: int = COLS) -> float:
    """Useful MACs / (array size x cycles)."""
    return macs / (rows * cols * cycles)


def run_sequential(networks: list[Network], shadow: bool = False) -> dict:
    """One network at a time on the full array, in arrival order."""
    t = 0
    finish = {}
    total_macs = 0
    for net in sorted(networks, key=lambda n: n.arrival):
        t = max(t, net.arrival)
        for layer in net.layers:
            t += layer_cycles(layer, COLS, shadow)
            total_macs += layer.macs
        finish[net.name] = t
    return {
        "makespan": t,
        "latency": {n.name: finish[n.name] - n.arrival for n in networks},
        "util": utilization(total_macs, t),
    }


# --------------------------------------------------------------------------- self-test
def selftest() -> None:
    """Reference numbers from the hand derivation (baseline, w = 12, batch 1)."""
    expect = {"conv1": 2439, "conv2": 3406, "fc1": 12240, "fc2": 2520, "fc3": 238}
    for layer in lenet5(1):
        got = layer_cycles(layer, COLS)
        assert got == expect[layer.name], f"{layer.name}: got {got}, expected {expect[layer.name]}"
    assert len(passes(Layer("x", 1, 25, 6), 12)) == 3
    assert len(passes(Layer("x", 100, 150, 16), 12)) == 26

    one = run_sequential([Network("lenet", lenet5(1))])
    assert one["makespan"] == 20843, one["makespan"]

    two = run_sequential([Network("a", lenet5(1), 0), Network("b", lenet5(1), 5000)])
    assert two["makespan"] == 2 * 20843                 # b waits for a
    assert two["latency"]["b"] == 2 * 20843 - 5000

    late = run_sequential([Network("a", lenet5(1), 0), Network("b", lenet5(1), 30000)])
    assert late["makespan"] == 30000 + 20843            # idle gap before b

    # shadow weights can only help
    for layer in lenet5(1):
        assert layer_cycles(layer, COLS, shadow=True) <= layer_cycles(layer, COLS)
    print("cyclemodel selftest: PASS")


# --------------------------------------------------------------------------- part 2: multi-tenant event loop
ALLOWED_WIDTHS = (2, 3, 4, 6, 8, 12)   # partition widths the hardware supports (must include COLS)


def snap_down(w: int, allowed: tuple[int, ...] = ALLOWED_WIDTHS) -> int:
    """Largest allowed width <= w (0 if none fits)."""
    fits = [a for a in allowed if a <= w]
    return max(fits) if fits else 0


class Tenant:
    """One network's progress through its layers."""

    def __init__(self, idx: int, net: Network):
        self.idx = idx
        self.net = net
        self.layer_idx = 0
        self.n_done = 0            # output columns of the current layer already finished
        self.width = 0             # columns currently held (0 = none)
        self.started = False       # has arrived and asked for columns
        self.finish: int | None = None

    @property
    def done(self) -> bool:
        return self.layer_idx >= len(self.net.layers)

    @property
    def layer(self) -> Layer:
        return self.net.layers[self.layer_idx]

    def n_remaining(self) -> int:
        return self.layer.N - self.n_done

    def remaining_macs(self) -> int:
        if self.done:
            return 0
        cur = self.layer
        later = self.net.layers[self.layer_idx + 1:]
        return cur.M * cur.K * (cur.N - self.n_done) + sum(l.macs for l in later)


# ---- policies: target width for one tenant, given everyone who is active
def _active(sim: "Sim") -> list[Tenant]:
    return [t for t in sim.tenants if t.started and not t.done]


def target_sequential(sim: "Sim", t: Tenant) -> int:
    """Whole array to the earliest-arriving unfinished network, nothing to the rest."""
    head = min(_active(sim), key=lambda x: (x.net.arrival, x.idx))
    return COLS if t is head else 0


def target_equal(sim: "Sim", t: Tenant) -> int:
    """Paper: COLS / n_tenants for everyone (a lone tenant gets the whole array)."""
    n = len(_active(sim))
    return max(snap_down(COLS // n), ALLOWED_WIDTHS[0])


def target_proportional(sim: "Sim", t: Tenant) -> int:
    """Ours: min(N_remaining, share by remaining MACs), snapped; leftover columns go to
    whoever they save the most passes for."""
    act = _active(sim)
    total = sum(x.remaining_macs() for x in act)
    tgt = {}
    for x in act:
        share = COLS * x.remaining_macs() / total
        tgt[x.idx] = max(snap_down(min(x.n_remaining(), int(share))), ALLOWED_WIDTHS[0])
    leftover = COLS - sum(tgt.values())
    # hand out leftovers: biggest pass reduction first
    while leftover > 0:
        best, best_gain = None, 0
        for x in act:
            cur = tgt[x.idx]
            bigger = [a for a in ALLOWED_WIDTHS if cur < a <= cur + leftover]
            if not bigger:
                continue
            nxt = min(bigger)
            gain = ceil(x.n_remaining() / cur) - ceil(x.n_remaining() / nxt)
            if gain > best_gain:
                best, best_gain = (x, nxt), gain
        if best is None:
            break
        x, nxt = best
        leftover -= nxt - tgt[x.idx]
        tgt[x.idx] = nxt
    return tgt[t.idx]


POLICIES = {"sequential": target_sequential, "equal": target_equal, "proportional": target_proportional}


# ---- event-driven simulator
class Sim:
    """Discrete-event model of several networks sharing the array.

    feed = "A": one shared feed port; only one tenant streams inputs at a time (FIFO).
    feed = "B": per-partition feed injection; every partition streams independently.
    Partitions change only at N-tile boundaries (never mid-pass).
    """

    def __init__(self, networks: list[Network], policy: str, feed: str = "A", shadow: bool = False):
        assert feed in ("A", "B")
        self.tenants = [Tenant(i, n) for i, n in enumerate(networks)]
        self.target = POLICIES[policy]
        self.feed, self.shadow = feed, shadow
        self.now = 0
        self.free = COLS
        self._heap: list = []
        self._seq = 0
        self._procs = {t.idx: self._process(t) for t in self.tenants}
        self._waiting: list[Tenant] = []               # blocked on column allocation
        self._feed_busy = False
        self._feed_queue: deque = deque()              # (tenant idx, M) waiting for the feed
        # stats
        self.macs = 0
        self.feed_busy_cycles = 0
        self.col_cycles = 0                            # integral of columns allocated over time
        self._col_mark = 0

    # -- scheduling helpers
    def _at(self, time: int, kind: str, idx: int, value=None) -> None:
        heapq.heappush(self._heap, (time, self._seq, kind, idx, value))
        self._seq += 1

    def _account_cols(self) -> None:
        self.col_cycles += (self.now - self._col_mark) * (COLS - self.free)
        self._col_mark = self.now

    def _resume(self, idx: int, value=None) -> None:
        """Send value into a tenant's process and handle what it asks for next."""
        t = self.tenants[idx]
        try:
            req = self._procs[idx].send(value)
        except StopIteration:
            t.finish = self.now
            self._grant()                  # finishing frees targets for everyone else
            return
        kind = req[0]
        if kind == "delay":
            self._at(self.now + req[1], "wake", idx)
        elif kind == "until":
            self._at(max(self.now, req[1]), "wake", idx)
        elif kind == "stream":
            M = req[1]
            if self.feed == "B":
                self._at(self.now + M, "wake", idx, self.now)
            elif not self._feed_busy:
                self._start_stream(idx, M)
            else:
                self._feed_queue.append((idx, M))
        elif kind == "alloc":
            t.started = True
            self._waiting.append(t)
            self._grant()
        elif kind == "release":
            self._account_cols()
            self.free += t.width
            t.width = 0
            self._at(self.now, "wake", idx)
            self._grant()
        else:
            raise ValueError(req)

    def _start_stream(self, idx: int, M: int) -> None:
        assert not self._feed_busy, "shared feed held by two tenants"
        self._feed_busy = True
        self.feed_busy_cycles += M
        self._at(self.now + M, "feed_done", idx, self.now)

    def _grant(self) -> None:
        """Give free columns to waiting tenants, earliest arrival first."""
        for t in sorted(self._waiting, key=lambda x: (x.net.arrival, x.idx)):
            if t.done:
                continue
            w = snap_down(min(self.target(self, t), self.free))
            if w > 0:
                self._account_cols()
                self.free -= w
                t.width = w
                self._waiting.remove(t)
                assert 0 <= self.free <= COLS, "partitions exceed the array width"
                self._at(self.now, "wake", t.idx, w)

    def _keep_width(self, t: Tenant) -> bool:
        """At an N-tile boundary: does the policy let t keep its current columns?"""
        tgt = self.target(self, t)
        if tgt == t.width:
            return True
        if tgt > t.width:                       # wants to grow: only worth it if columns are free
            return snap_down(min(tgt, t.width + self.free)) == t.width
        # wants to shrink: only worth the drain + reload if someone is waiting for columns
        return not self._waiting

    # -- one tenant's life, as a generator of requests
    def _process(self, t: Tenant):
        yield ("until", t.net.arrival)
        while not t.done:
            w = yield ("alloc",)
            last_stream_start = None            # shadow pipeline restarts after every allocation
            while True:
                L = t.layer
                w_eff = min(w, t.n_remaining())
                for _ in range(ceil(L.K / ROWS)):
                    if self.shadow and last_stream_start is not None:
                        yield ("until", last_stream_start + ROWS)   # load hidden behind the last stream
                    else:
                        yield ("delay", ROWS)                       # full weight load
                    last_stream_start = yield ("stream", L.M)
                    if not self.shadow:
                        yield ("delay", ROWS + w_eff - 1)           # drain every pass
                self.macs += L.M * L.K * w_eff
                t.n_done += w_eff
                layer_done = t.n_done >= L.N
                if layer_done:
                    t.layer_idx += 1
                    t.n_done = 0
                if not layer_done and self._keep_width(t):
                    continue                                        # next N tile, same columns
                if self.shadow:
                    yield ("delay", ROWS + w_eff - 1)               # drain before giving columns back
                break
            yield ("release",)

    # -- main loop
    def run(self) -> dict:
        for t in self.tenants:
            self._resume(t.idx)
        while self._heap:
            time, _, kind, idx, value = heapq.heappop(self._heap)
            self.now = time
            if kind == "feed_done":
                self._feed_busy = False
                if self._feed_queue:                                # FIFO: next waiter gets the feed
                    nidx, nM = self._feed_queue.popleft()
                    self._start_stream(nidx, nM)
                self._resume(idx, value)
            else:
                self._resume(idx, value)
        assert all(t.done for t in self.tenants), "simulation ended with unfinished networks"
        self._account_cols()
        makespan = max(t.finish for t in self.tenants)
        return {
            "makespan": makespan,
            "latency": {t.net.name: t.finish - t.net.arrival for t in self.tenants},
            "util": utilization(self.macs, makespan),
            "feed_busy": self.feed_busy_cycles / makespan if self.feed == "A" else None,  # shared feed only
            "cols_in_use": self.col_cycles / (COLS * makespan),
        }


def simulate(networks: list[Network], policy: str, feed: str = "A", shadow: bool = False) -> dict:
    return Sim(networks, policy, feed, shadow).run()


def selftest_part2() -> None:
    """Checks for the multi-tenant simulator."""
    for shadow in (False, True):
        ref = run_sequential([Network("lenet", lenet5(1))], shadow)["makespan"]
        # 1 tenant: every policy and feed mode must equal the sequential formula
        for policy in POLICIES:
            for feed in ("A", "B"):
                got = simulate([Network("lenet", lenet5(1))], policy, feed, shadow)["makespan"]
                assert got == ref, f"1 tenant {policy}/{feed}/shadow={shadow}: {got} != {ref}"
        # sequential policy in the simulator must match run_sequential for several networks
        nets = [Network("a", lenet5(1), 0), Network("b", lenet5(1), 5000), Network("c", lenet5(2), 7000)]
        want = run_sequential(nets, shadow)["makespan"]
        for feed in ("A", "B"):
            got = simulate(nets, "sequential", feed, shadow)["makespan"]
            assert got == want, f"sequential sim {feed}/shadow={shadow}: {got} != {want}"
        # per-partition feed is never slower than the shared feed
        for policy in ("equal", "proportional"):
            a = simulate(nets, policy, "A", shadow)["makespan"]
            b = simulate(nets, policy, "B", shadow)["makespan"]
            assert b <= a, f"{policy}/shadow={shadow}: feed B {b} slower than A {a}"
    # MACs are conserved
    nets = [Network("a", lenet5(1), 0), Network("b", lenet5(4), 100)]
    total = sum(l.macs for n in nets for l in n.layers)
    for policy in POLICIES:
        s = Sim(nets, policy, "A")
        s.run()
        assert s.macs == total, f"{policy}: MACs {s.macs} != {total}"
    print("cyclemodel selftest part 2: PASS")


# --------------------------------------------------------------------------- entry point
def main() -> int:
    if "--selftest" in sys.argv:
        selftest()
        selftest_part2()
        return 0
    for shadow in (False, True):
        r = run_sequential([Network("lenet", lenet5(1))], shadow=shadow)
        print(f"sequential LeNet-5, shadow={shadow}: {r['makespan']} cycles, util {r['util']:.1%}")
    return 0


if __name__ == "__main__":
    sys.exit(main())