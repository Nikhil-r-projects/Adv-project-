#!/usr/bin/env python3
"""
File: python/reference/mlkem_ntt_ref.py
Author: Person 1 — NTT Architecture Engineer
Project: Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM

Description:
  Independent golden reference model for the 256-point Number Theoretic
  Transform (NTT) specified in NIST FIPS 203 Section 4.3 (Algorithm 9).

Mathematical Specification:
  - Modulus: Q = 3329
  - Transform Length: N = 256
  - Twiddle Factors: zetas[k] = 17^(BitRev_7(k)) mod 3329 for k in [0..127]
  - Loop Schedule:
      len = 128 down to 2 by factors of 2 (7 stages: len = 128, 64, 32, 16, 8, 4, 2)
      for start = 0 to 256 step 2*len:
        zeta = zetas[k++]
        for j = start to start + len - 1:
          t = (zeta * f[j + len]) mod Q
          f[j + len] = (f[j] - t) mod Q
          f[j]       = (f[j] + t) mod Q

This script:
  1. Computes the golden NTT.
  2. Generates test vectors (all-zero, impulse, deterministic, and 10 random vectors).
  3. Writes input and expected output vectors into vectors/ directory.
"""

import os
import random

Q = 3329
N = 256

def bitrev7(n: int) -> int:
    """Computes 7-bit bit reversal of integer n."""
    r = 0
    for _ in range(7):
        r = (r << 1) | (n & 1)
        n >>= 1
    return r

def get_fips203_zetas():
    """Generates the 128 twiddle factors from FIPS 203 Section 4.3 Table 2."""
    return [pow(17, bitrev7(k), Q) for k in range(128)]

ZETAS = get_fips203_zetas()

def ntt_fips203(poly):
    """
    Computes in-place FIPS 203 Algorithm 9 forward NTT on a 256-element array.
    Returns a new list containing transformed coefficients in range [0, Q-1].
    """
    assert len(poly) == N, f"Polynomial must have {N} coefficients"
    f = [x % Q for x in poly]
    k = 1
    length = 128
    while length >= 2:
        for start in range(0, N, 2 * length):
            zeta = ZETAS[k]
            k += 1
            for j in range(start, start + length):
                t = (zeta * f[j + length]) % Q
                f[j + length] = (f[j] - t + Q) % Q
                f[j] = (f[j] + t) % Q
        length //= 2
    return f

def write_vector(filepath, poly):
    """Writes 256 coefficients as hexadecimal strings (one per line)."""
    with open(filepath, 'w') as fh:
        for val in poly:
            fh.write(f"{val:03X}\n")

def generate_all_vectors(output_dir="vectors", num_random=10, seed=12345):
    """Generates all standard and random test vectors."""
    os.makedirs(output_dir, exist_ok=True)
    random.seed(seed)

    vectors = []

    # Vector 0: All zeros
    v0_in = [0] * N
    vectors.append(("vec_000_all_zeros", v0_in))

    # Vector 1: Single impulse at index 0
    v1_in = [0] * N
    v1_in[0] = 1
    vectors.append(("vec_001_impulse_0", v1_in))

    # Vector 2: Single impulse at index 128
    v2_in = [0] * N
    v2_in[128] = 1
    vectors.append(("vec_002_impulse_128", v2_in))

    # Vector 3: Deterministic linear ramp
    v3_in = [i % Q for i in range(N)]
    vectors.append(("vec_003_linear_ramp", v3_in))

    # Vector 4: Alternating maximum values (Q-1 = 3328)
    v4_in = [3328 if i % 2 == 0 else 0 for i in range(N)]
    vectors.append(("vec_004_alternating_max", v4_in))

    # Vectors 5..14: 10 Pseudorandom vectors (seed = 12345)
    for idx in range(num_random):
        v_rand = [random.randint(0, Q - 1) for _ in range(N)]
        vectors.append((f"vec_{idx+5:03d}_random", v_rand))

    manifest_path = os.path.join(output_dir, "manifest.txt")
    with open(manifest_path, 'w') as mfh:
        for name, in_poly in vectors:
            out_poly = ntt_fips203(in_poly)
            in_file  = os.path.join(output_dir, f"{name}_in.hex")
            out_file = os.path.join(output_dir, f"{name}_exp.hex")
            write_vector(in_file, in_poly)
            write_vector(out_file, out_poly)
            mfh.write(f"{name},{in_file},{out_file}\n")
            print(f"Generated {name}: input -> {in_file}, expected -> {out_file}")

    print(f"\nSuccessfully generated {len(vectors)} test vector pairs in '{output_dir}'.")

if __name__ == "__main__":
    generate_all_vectors()
