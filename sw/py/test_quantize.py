"""Tests for quantize.py's export layout and INT8 forward pass. No PyTorch needed.

Run from the repo root:
    python -m unittest discover -s sw/py -v
"""
import unittest

import numpy as np

from golden import maxpool2d, requantize
from quantize import QuantizedLayer, int8_forward, weight_to_kn
from test_golden import SEED, ref_conv_acc, ref_matmul


def make_layer(name, kind, w_torch, bias, relu, **geom):
    return QuantizedLayer(name=name, kind=kind, weight_int8=weight_to_kn(w_torch), bias_int32=bias,
                          input_step=1.0, weight_step=1.0, output_step=1.0, scale=700, shift=17,
                          real_multiplier=0.0, multiplier_error=0.0, relu=relu, **geom)


class TestWeightLayout(unittest.TestCase):

    def test_linear_is_transposed(self):
        w = np.arange(6).reshape(2, 3)           # torch Linear(3 -> 2): [out, in]
        self.assertEqual(weight_to_kn(w).tolist(), [[0, 3], [1, 4], [2, 5]])

    def test_linear_matches_torch_semantics(self):
        rng = np.random.default_rng(SEED)
        x = rng.integers(-128, 128, (4, 10))
        w = rng.integers(-128, 128, (3, 10))     # y = x @ w.T in torch
        self.assertEqual((x @ weight_to_kn(w)).tolist(), (x @ w.T).tolist())

    def test_conv_shape(self):
        self.assertEqual(weight_to_kn(np.zeros((16, 6, 5, 5))).shape, (150, 16))


class TestInt8Forward(unittest.TestCase):

    def test_tiny_lenet_vs_loop_reference(self):
        # conv(1->2, 3x3) -> pool -> conv(2->3, 3x3, pad 1) -> pool -> fc(12 -> 4)
        rng = np.random.default_rng(SEED)
        w1 = rng.integers(-128, 128, (2, 1, 3, 3), dtype=np.int8)
        w2 = rng.integers(-128, 128, (3, 2, 3, 3), dtype=np.int8)
        w3 = rng.integers(-128, 128, (4, 12), dtype=np.int8)
        b1, b2, b3 = (rng.integers(-3000, 3000, n).astype(np.int32) for n in (2, 3, 4))
        layers = [make_layer("conv1", "conv2d", w1, b1, True, kernel=(3, 3), pool=2),
                  make_layer("conv2", "conv2d", w2, b2, True, kernel=(3, 3), padding=1, pool=2),
                  make_layer("fc1", "linear", w3, b3, False)]
        x = rng.integers(-128, 128, (2, 1, 10, 10), dtype=np.int8)

        def ref_conv(x, w, b, pad):
            acc = np.array(ref_conv_acc(x.tolist(), w.tolist(), 1, pad))
            B, N, Ho, Wo = acc.shape
            q = requantize(acc.transpose(0, 2, 3, 1).reshape(-1, N), b, 700, 17, True)
            return q.reshape(B, Ho, Wo, N).transpose(0, 3, 1, 2)

        h = maxpool2d(ref_conv(x, w1, b1, 0))         # 8x8 -> 4x4
        h = maxpool2d(ref_conv(h, w2, b2, 1))         # 4x4 -> 2x2, 3 channels = 12 features
        flat = h.reshape(2, -1).tolist()              # NCHW flatten, same as torch.flatten(1)
        exp = requantize(np.array(ref_matmul(flat, w3.T.tolist())), b3, 700, 17, False)
        self.assertEqual(int8_forward(layers, x).tolist(), exp.tolist())


if __name__ == "__main__":
    unittest.main(verbosity=2)
