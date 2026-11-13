"""Tests for golden.py against independent pure-Python reference implementations.

Run from the repo root:
    python -m unittest discover -s sw/py -v
or directly:
    python sw/py/test_golden.py

The references below use unbounded Python ints and exact Fractions, so they
share no arithmetic tricks (int64 casts, >> rounding) with golden.py.
Random cases use fixed seeds; a failure message includes the seed and case.
"""
import math
import unittest
from fractions import Fraction

import numpy as np

from golden import conv2d, im2col, layer, matmul_int8, maxpool2d, requantize

SEED = 20261112


# ---------------- Reference models (slow, obviously correct) ----------------

def ref_matmul(x, w):
    M, K = len(x), len(x[0])
    N = len(w[0])
    return [[sum(int(x[m][k]) * int(w[k][n]) for k in range(K)) for n in range(N)] for m in range(M)]


def ref_requant_one(a, b, scale, shift, relu):
    s = int(a) + int(b)
    if relu:
        s = max(s, 0)
    q = math.floor(Fraction(s * scale, 2 ** shift) + Fraction(1, 2))   # round half up
    return max(-128, min(127, q))


def ref_requantize(acc, bias, scale, shift, relu):
    return [[ref_requant_one(a, bias[n], scale, shift, relu) for n, a in enumerate(row)] for row in acc]


def ref_conv_acc(x, w_torch, stride, padding):
    """Direct conv, no im2col: x [B][C][H][W], w_torch [N][C][kh][kw] -> acc [B][N][Ho][Wo]."""
    B, C, H, W = len(x), len(x[0]), len(x[0][0]), len(x[0][0][0])
    N, kh, kw = len(w_torch), len(w_torch[0][0]), len(w_torch[0][0][0])
    Ho, Wo = (H + 2 * padding - kh) // stride + 1, (W + 2 * padding - kw) // stride + 1

    def px(b, c, y, xx):
        y, xx = y - padding, xx - padding
        return x[b][c][y][xx] if 0 <= y < H and 0 <= xx < W else 0

    return [[[[sum(px(b, c, oy * stride + i, ox * stride + j) * w_torch[n][c][i][j]
                   for c in range(C) for i in range(kh) for j in range(kw))
               for ox in range(Wo)] for oy in range(Ho)] for n in range(N)] for b in range(B)]


def i8(rows):
    return np.array(rows, dtype=np.int8)


def i32(rows):
    return np.array(rows, dtype=np.int32)


# ---------------- matmul_int8 ----------------

class TestMatmul(unittest.TestCase):

    def test_random_vs_reference(self):
        rng = np.random.default_rng(SEED)
        # includes sizes that are not multiples of 12, K > ROWS, N > COLS
        for M, K, N in [(1, 1, 1), (5, 12, 12), (7, 30, 17), (3, 100, 25), (13, 25, 1), (1, 144, 40)]:
            with self.subTest(seed=SEED, M=M, K=K, N=N):
                x = rng.integers(-128, 128, (M, K), dtype=np.int8)
                w = rng.integers(-128, 128, (K, N), dtype=np.int8)
                y = matmul_int8(x, w)
                self.assertEqual(y.dtype, np.int32)
                self.assertEqual(y.shape, (M, N))
                self.assertEqual(y.tolist(), ref_matmul(x.tolist(), w.tolist()))

    def test_extremes_do_not_wrap(self):
        # NumPy's own int8 @ int8 wraps this to 0; the golden model must not.
        x = np.full((2, 12), -128, np.int8)
        w = np.full((12, 3), -128, np.int8)
        self.assertTrue((matmul_int8(x, w) == 12 * 128 * 128).all())
        # most negative product
        self.assertEqual(matmul_int8(i8([[-128]]), i8([[127]])).item(), -16256)
        self.assertEqual(matmul_int8(i8([[127]]), i8([[127]])).item(), 16129)

    def test_zeros(self):
        y = matmul_int8(np.zeros((3, 5), np.int8), np.zeros((5, 4), np.int8))
        self.assertEqual(y.tolist(), [[0] * 4] * 3)

    def test_accepts_wider_int_dtypes(self):
        x = np.array([[1, -2], [3, 4]], dtype=np.int64)
        w = [[5, 6], [-7, 8]]
        self.assertEqual(matmul_int8(x, w).tolist(), [[19, -10], [-13, 50]])

    def test_largest_legal_sum(self):
        # K * (-128)(-128) just under INT32 max: K = 131071 -> 2147467264
        K = (2 ** 31 - 1) // (128 * 128)
        y = matmul_int8(np.full((1, K), -128, np.int8), np.full((K, 1), -128, np.int8))
        self.assertEqual(y.item(), K * 16384)

    def test_rejects_bad_inputs(self):
        cases = {
            "inner dims":   (np.zeros((2, 3), np.int8), np.zeros((4, 3), np.int8), ValueError),
            "x not 2-D":    (np.zeros(3, np.int8), np.zeros((3, 1), np.int8), ValueError),
            "x above 127":  (np.array([[128]]), i8([[1]]), ValueError),
            "w below -128": (i8([[1]]), np.array([[-129]]), ValueError),
            "float input":  (np.array([[1.0]]), i8([[1]]), TypeError),
        }
        for name, (x, w, err) in cases.items():
            with self.subTest(name):
                with self.assertRaises(err):
                    matmul_int8(x, w)

    def test_rejects_int32_overflow(self):
        K = (2 ** 31 - 1) // (128 * 128) + 1
        with self.assertRaises(ValueError):
            matmul_int8(np.full((1, K), -128, np.int8), np.full((K, 1), -128, np.int8))


# ---------------- requantize ----------------

class TestRequantize(unittest.TestCase):

    def test_random_vs_reference(self):
        rng = np.random.default_rng(SEED)
        for case in range(2000):
            M, N = int(rng.integers(1, 6)), int(rng.integers(1, 14))
            lim = 2 ** 31 if rng.random() < 0.3 else 2 ** 15   # mix full-range and realistic values
            acc = rng.integers(-lim, lim, (M, N)).astype(np.int32)
            bias = rng.integers(-lim, lim, N).astype(np.int32)
            scale = int(rng.integers(0, 2 ** 16))
            shift = int(rng.integers(0, 32))
            relu = bool(rng.integers(2))
            y = requantize(acc, bias, scale, shift, relu)
            exp = ref_requantize(acc.tolist(), bias.tolist(), scale, shift, relu)
            self.assertEqual(y.dtype, np.int8)
            self.assertEqual(y.tolist(), exp,
                             f"seed={SEED} case={case} scale={scale} shift={shift} relu={relu}")

    def test_ties_round_toward_plus_inf(self):
        # value / 2 with shift=1: 2.5 -> 3, -2.5 -> -2, 1.5 -> 2, -1.5 -> -1, 0.5 -> 1, -0.5 -> 0
        acc = i32([[5, -5, 3, -3, 1, -1]])
        y = requantize(acc, np.zeros(6, np.int32), scale=1, shift=1, relu=False)
        self.assertEqual(y.tolist(), [[3, -2, 2, -1, 1, 0]])

    def test_non_tie_rounding(self):
        # shift=2 divides by 4: 5/4=1.25 -> 1, 7/4=1.75 -> 2, -5/4 -> -1, -7/4 -> -2
        y = requantize(i32([[5, 7, -5, -7]]), np.zeros(4, np.int32), scale=1, shift=2, relu=False)
        self.assertEqual(y.tolist(), [[1, 2, -1, -2]])

    def test_relu(self):
        acc = i32([[-100, -1, 0, 1, 100]])
        b = np.zeros(5, np.int32)
        self.assertEqual(requantize(acc, b, 1, 0, relu=True).tolist(), [[0, 0, 0, 1, 100]])
        self.assertEqual(requantize(acc, b, 1, 0, relu=False).tolist(), [[-100, -1, 0, 1, 100]])

    def test_relu_applies_after_bias(self):
        # acc is negative but acc + bias is positive -> survives ReLU
        y = requantize(i32([[-10, -10]]), i32([15, 5]), scale=1, shift=0, relu=True)
        self.assertEqual(y.tolist(), [[5, 0]])

    def test_bias_is_per_column(self):
        acc = i32([[0, 0, 0], [10, 10, 10]])
        y = requantize(acc, i32([1, 2, 3]), scale=1, shift=0, relu=False)
        self.assertEqual(y.tolist(), [[1, 2, 3], [11, 12, 13]])

    def test_saturation(self):
        acc = i32([[-1000, -129, -128, 127, 128, 1000]])
        y = requantize(acc, np.zeros(6, np.int32), scale=1, shift=0, relu=False)
        self.assertEqual(y.tolist(), [[-128, -128, -128, 127, 127, 127]])

    def test_shift_zero_skips_rounding(self):
        y = requantize(i32([[3]]), i32([0]), scale=40, shift=0, relu=False)
        self.assertEqual(y.item(), 120)

    def test_scale_zero(self):
        y = requantize(i32([[99999, -99999]]), i32([7, 7]), scale=0, shift=5, relu=False)
        self.assertEqual(y.tolist(), [[0, 0]])

    def test_sum_is_33_bit_no_wrap(self):
        # INT32 max + INT32 max would wrap negative in 32 bits
        y = requantize(i32([[2 ** 31 - 1]]), i32([2 ** 31 - 1]), scale=1, shift=31, relu=False)
        self.assertEqual(y.item(), 2)
        y = requantize(i32([[-2 ** 31]]), i32([-2 ** 31]), scale=1, shift=31, relu=False)
        self.assertEqual(y.item(), -2)

    def test_worst_case_product(self):
        # |(acc + bias) * scale| ~ 2**48: must not overflow int64 math
        y = requantize(i32([[-2 ** 31]]), i32([-2 ** 31]), scale=65535, shift=31, relu=False)
        self.assertEqual(y.item(), -128)
        y = requantize(i32([[2 ** 31 - 1]]), i32([2 ** 31 - 1]), scale=65535, shift=31, relu=False)
        self.assertEqual(y.item(), 127)

    def test_numpy_int_params(self):
        y = requantize(i32([[6]]), i32([0]), scale=np.uint16(3), shift=np.int64(1), relu=False)
        self.assertEqual(y.item(), 9)

    def test_rejects_bad_inputs(self):
        z11, b1 = np.zeros((1, 1), np.int32), np.zeros(1, np.int32)
        cases = {
            "bias wrong length": (np.zeros((2, 3), np.int32), np.zeros(4, np.int32), 1, 0, ValueError),
            "bias 2-D":          (z11, np.zeros((1, 1), np.int32), 1, 0, ValueError),
            "acc not 2-D":       (np.zeros(3, np.int32), np.zeros(3, np.int32), 1, 0, ValueError),
            "acc above INT32":   (np.array([[2 ** 31]]), b1, 1, 0, ValueError),
            "bias below INT32":  (z11, np.array([-2 ** 31 - 1]), 1, 0, ValueError),
            "float acc":         (np.array([[1.0]]), b1, 1, 0, TypeError),
            "scale negative":    (z11, b1, -1, 0, ValueError),
            "scale too big":     (z11, b1, 65536, 0, ValueError),
            "shift negative":    (z11, b1, 1, -1, ValueError),
            "shift too big":     (z11, b1, 1, 32, ValueError),
        }
        for name, (acc, bias, scale, shift, err) in cases.items():
            with self.subTest(name):
                with self.assertRaises(err):
                    requantize(acc, bias, scale, shift, relu=False)


# ---------------- im2col / conv2d / maxpool2d ----------------

class TestConv(unittest.TestCase):

    def test_im2col_layout(self):
        # 1 image, 2 channels, 3x3, 2x2 kernel: first row is the top-left patch, (c, i, j) order
        x = np.arange(18, dtype=np.int8).reshape(1, 2, 3, 3)
        X = im2col(x, 2, 2)
        self.assertEqual(X.shape, (4, 8))
        self.assertEqual(X[0].tolist(), [0, 1, 3, 4, 9, 10, 12, 13])
        self.assertEqual(X[3].tolist(), [4, 5, 7, 8, 13, 14, 16, 17])   # (oy, ox) = (1, 1)

    def test_padding_is_zero(self):
        X = im2col(np.full((1, 1, 2, 2), 5, np.int8), 3, 3, padding=1)
        self.assertEqual(X.shape, (4, 9))
        self.assertEqual(X[0].tolist(), [0, 0, 0, 0, 5, 5, 0, 5, 5])

    def test_conv_vs_direct_reference(self):
        # im2col @ weight.reshape(N, -1).T must equal a direct conv on the PyTorch layout
        rng = np.random.default_rng(SEED)
        for B, C, H, W, N, k, stride, pad in [(1, 1, 28, 28, 6, 5, 1, 0), (2, 6, 12, 12, 16, 5, 1, 0),
                                              (2, 3, 8, 8, 4, 3, 1, 1), (1, 2, 7, 9, 3, 3, 2, 1)]:
            with self.subTest(B=B, C=C, H=H, W=W, N=N, k=k, stride=stride, pad=pad):
                x = rng.integers(-128, 128, (B, C, H, W), dtype=np.int8)
                wt = rng.integers(-128, 128, (N, C, k, k), dtype=np.int8)
                bias = rng.integers(-5000, 5000, N).astype(np.int32)
                y = conv2d(x, wt.reshape(N, -1).T, bias, scale=1000, shift=16, relu=True,
                           kh=k, kw=k, stride=stride, padding=pad)
                acc = ref_conv_acc(x.tolist(), wt.tolist(), stride, pad)
                exp = [[[[ref_requant_one(a, bias[n], 1000, 16, True) for a in row] for row in ch]
                        for n, ch in enumerate(img)] for img in acc]
                self.assertEqual(y.tolist(), exp)

    def test_maxpool(self):
        x = i8([[[[1, -5, 2, 0, 9], [3, 4, -1, 7, 9], [-8, -9, 0, 0, 9]]]])   # 3x5 -> 1x2, edges dropped
        self.assertEqual(maxpool2d(x).tolist(), [[[[4, 7]]]])

    def test_maxpool_commutes_with_requantize(self):
        # why pooling INT8 outputs on the Arm side is exact
        rng = np.random.default_rng(SEED)
        acc = rng.integers(-2 ** 20, 2 ** 20, (8, 6)).astype(np.int32)
        bias = rng.integers(-1000, 1000, 6).astype(np.int32)
        q = requantize(acc, bias, 300, 14, True)
        pooled_q = maxpool2d(q.T.reshape(1, 6, 2, 4))
        pooled_acc = (acc.T.reshape(1, 6, 2, 4).reshape(1, 6, 1, 2, 2, 2).max(axis=(3, 5)))
        req = requantize(pooled_acc.transpose(0, 2, 3, 1).reshape(-1, 6), bias, 300, 14, True)
        self.assertEqual(pooled_q.transpose(0, 2, 3, 1).reshape(-1, 6).tolist(), req.tolist())

    def test_rejects_bad_inputs(self):
        with self.assertRaises(ValueError):
            im2col(np.zeros((2, 3), np.int8), 1, 1)
        with self.assertRaises(ValueError):
            im2col(np.zeros((1, 1, 2, 2), np.int8), 3, 3)
        with self.assertRaises(ValueError):
            im2col(np.full((1, 1, 2, 2), 200), 1, 1)
        with self.assertRaises(ValueError):
            maxpool2d(np.zeros((1, 1, 1, 1), np.int8))


# ---------------- layer (end to end) ----------------

class TestLayer(unittest.TestCase):

    def test_random_vs_reference(self):
        rng = np.random.default_rng(SEED)
        for M, K, N, relu in [(4, 30, 17, True), (1, 12, 12, False), (9, 50, 3, True), (2, 7, 25, False)]:
            with self.subTest(seed=SEED, M=M, K=K, N=N, relu=relu):
                x = rng.integers(-128, 128, (M, K), dtype=np.int8)
                w = rng.integers(-128, 128, (K, N), dtype=np.int8)
                bias = rng.integers(-5000, 5000, N).astype(np.int32)
                scale, shift = int(rng.integers(1, 2 ** 16)), int(rng.integers(10, 24))
                y = layer(x, w, bias, scale, shift, relu)
                acc = ref_matmul(x.tolist(), w.tolist())
                self.assertEqual(y.tolist(), ref_requantize(acc, bias.tolist(), scale, shift, relu))


if __name__ == "__main__":
    unittest.main(verbosity=2)
