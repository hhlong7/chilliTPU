"""INT8 quantization of the demo networks (MNIST FC, LeNet-5, small CIFAR-10 CNN).

Needs PyTorch (not in requirements.txt by default). Produces INT8 weights, INT32
biases, and per-layer scale/shift that the golden model and hardware use.
Status: SKELETON.
"""
import sys


def main() -> int:
    print("quantize.py: not implemented yet", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
