# ML-KEM NTT Accelerator — Architecture Specification

**Author:** Person 1 — NTT Architecture Engineer  
**Project:** Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM  
**Specification Reference:** NIST FIPS 203 (Module-Lattice-Based Key-Encapsulation Mechanism Standard)  

---

## 1. What is ML-KEM?

**ML-KEM** (Module-Lattice-Based Key-Encapsulation Mechanism), originally submitted to the NIST Post-Quantum Cryptography (PQC) Standardization process as **CRYSTALS-Kyber**, is a standardized post-quantum cryptographic scheme (FIPS 203). Its mathematical security is based on the hardness of the Module Learning With Errors (M-LWE) problem over module lattices, which is believed to be resistant to attacks by both classical and large-scale quantum computers.

In ML-KEM, cryptographic operations (key generation, encapsulation, and decapsulation) manipulate vectors and matrices of polynomials in the quotient ring:
$$\mathcal{R}_q = \mathbb{Z}_q[X] / (X^{256} + 1)$$

---

## 2. Why is the NTT Used?

The most computationally demanding operation in lattice-based cryptography is **polynomial multiplication** modulo $X^{256} + 1$ over $\mathbb{Z}_q$.
* **Schoolbook multiplication:** Requires $\mathcal{O}(N^2) = 256^2 = 65,536$ modular multiplications and additions.
* **Karatsuba multiplication:** Reduces complexity to $\mathcal{O}(N^{1.58}) \approx 6,500$ multiplications, which remains too slow and resource-heavy for high-throughput FPGA hardware.
* **Number Theoretic Transform (NTT):** A discrete Fourier transform defined over a finite field $\mathbb{Z}_q$ rather than the complex numbers $\mathbb{C}$. By transforming polynomials into the NTT (evaluation) domain:
  $$\hat{\mathbf{a}} = \text{NTT}(\mathbf{a}), \quad \hat{\mathbf{b}} = \text{NTT}(\mathbf{b})$$
  multiplication becomes **point-wise (or degree-1 modular) multiplication** requiring only $\mathcal{O}(N)$ operations!
* Converting to and from the NTT domain takes $\mathcal{O}(N \log N)$ operations using the Fast Fourier Transform (FFT) butterfly structure. For $N=256$, this reduces the multiplication complexity by over **20×** compared to schoolbook multiplication.

---

## 3. What is a Polynomial in ML-KEM?

A polynomial $f(X) \in \mathcal{R}_q$ is a degree-255 polynomial with integer coefficients:
$$f(X) = \sum_{i=0}^{255} f_i X^i = f_0 + f_1 X + f_2 X^2 + \dots + f_{255} X^{255}$$
where each coefficient $f_i$ is an integer in the ring $\mathbb{Z}_q$, meaning $0 \le f_i < q$.

Polynomial addition is performed coefficient-wise:
$$(f + g)_i = (f_i + g_i) \pmod q$$
Polynomial multiplication is performed modulo the polynomial modulus $X^{256} + 1$:
$$f(X) \cdot g(X) \pmod{X^{256} + 1}$$
When the degree reaches or exceeds 256, terms wrap around with a sign flip ($X^{256} \equiv -1$), which is known as **negacyclic convolution**.

---

## 4. Why $N = 256$?

$N = 256$ was selected by the designers of Kyber/ML-KEM to balance:
1. **Security:** A ring dimension of 256 provides sufficient entropy when scaled across module ranks $k \in \{2, 3, 4\}$ for NIST Security Categories 1, 3, and 5 (ML-KEM-512, ML-KEM-768, ML-KEM-1024).
2. **Efficiency:** $N = 2^8$ is a power of two, enabling highly efficient radix-2 divide-and-conquer Cooley-Tukey butterfly networks without padding or fractional stages.
3. **Hardware Alignment:** 256 words of 12-bit storage fit comfortably into a single 18Kb Block RAM on Xilinx and Intel FPGAs.

---

## 5. Why $q = 3329$?

The prime modulus $q = 3329$ satisfies several critical properties:
1. **Bit width:** $3329 < 2^{12} = 4096$, meaning each coefficient fits into exactly 12 unsigned bits. This permits high packing efficiency in 16-bit registers and BRAMs.
2. **Roots of Unity:** Notice the prime factorization of $q - 1$:
   $$q - 1 = 3328 = 2^8 \times 13 = 256 \times 13$$
   Because $2^8 \mid (q - 1)$, the field $\mathbb{Z}_{3329}$ contains a primitive 256-th root of unity:
   $$\psi = 17 \implies 17^{128} \equiv -1 \pmod{3329}, \quad 17^{256} \equiv 1 \pmod{3329}$$
3. **Incomplete NTT:** However, $2^9 = 512 \nmid (q - 1)$, and $17$ is not a quadratic residue modulo $3329$. Therefore, a primitive 512-th root of unity (which would require $\sqrt{17} \pmod{3329}$) does not exist in $\mathbb{Z}_{3329}$.
   Consequently, the polynomial $X^{256} + 1$ factorizes over $\mathbb{Z}_{3329}$ into **128 quadratic polynomials** of degree 2:
   $$X^{256} + 1 = \prod_{i=0}^{127} (X^2 - \zeta^{2i+1})$$
   rather than 256 linear polynomials.
   This is why the official FIPS 203 specification defines an **incomplete 7-stage NTT** ($len = 128$ down to $len = 2$).

---

## 6. What is a Butterfly Operation?

In fast transform algorithms, a "butterfly" is the basic computational unit that combines two smaller sub-transforms into a larger one. For a radix-2 Cooley-Tukey NTT, it takes two coefficients $(a, b)$ and a twiddle factor $\zeta$ to produce two updated coefficients $(a', b')$.

```
   a_in ------------------(+)---------------> a_out = (a + b*zeta) mod Q
                           ^
   b_in -----| * zeta |----+
                           v
             --------------(-)---------------> b_out = (a - b*zeta) mod Q
```

---

## 7. How the Butterfly Works (FIPS 203 Cooley-Tukey)

In FIPS 203 Algorithm 9, the butterfly operation computes:
1. Intermediate modular product:
   $$t = (b_{\text{in}} \times \zeta_{\text{in}}) \pmod Q$$
2. Modular sum:
   $$a_{\text{out}} = (a_{\text{in}} + t) \pmod Q$$
3. Modular difference:
   $$b_{\text{out}} = (a_{\text{in}} - t) \pmod Q$$

### Arithmetic Pipeline
* The multiplier `mod_mul` takes 1 clock cycle to register and reduce the 24-bit product $(b_{\text{in}} \times \zeta_{\text{in}})$.
* In parallel, operand $a_{\text{in}}$ is registered into an internal delay register `a_pipe` to align with $t$.
* On the following clock edge, `mod_add` and `mod_sub` compute $(a_{\text{pipe}} + t)$ and $(a_{\text{pipe}} - t)$.
* Total butterfly execution latency: **1 clock cycle**.

---

## 8. Memory Architecture (`ntt_memory.sv`)

The accelerator employs a **True Dual-Port (TDP) RAM** configuration storing 256 12-bit words ($256 \times 12$ bits):
* **Port A:** Used to read coefficient $a$ and write back updated coefficient $a'$.
* **Port B:** Used to read coefficient $b$ and write back updated coefficient $b'$.

```
                 +-------------------------------+
  mem_addr_a --->| Port A (Read addr_a / Write A)|<--- wdata_a (a_out)
  rdata_a (a) <--|                               |
                 |      ntt_memory (256x12)      |
  mem_addr_b --->| Port B (Read addr_b / Write B)|<--- wdata_b (b_out)
  rdata_b (b) <--|                               |
                 +-------------------------------+
```

Because both ports operate independently, each butterfly requires:
* 1 simultaneous dual read (Port A reads $a$, Port B reads $b$)
* 1 simultaneous dual write (Port A writes $a'$, Port B writes $b'$)
This avoids port contention and guarantees in-place storage.

---

## 9. Twiddle Factor Storage (`twiddle_rom.sv`)

Twiddle factors are stored in a dedicated combinational look-up table containing the 128 constants defined in FIPS 203 Table 2:
$$\zeta[k] = 17^{\text{BitRev}_7(k)} \pmod{3329}, \quad k \in [0, 127]$$

### Twiddle Address Schedule
* **Stage 0 ($len=128$):** Uses $\zeta[1] = 1729$ across all 128 butterflies.
* **Stage 1 ($len=64$):** Uses $\zeta[2] = 2580$ for block 0, $\zeta[3] = 3289$ for block 1.
* **Stage 2 ($len=32$):** Uses $\zeta[4..7]$.
* **Stage 3 ($len=16$):** Uses $\zeta[8..15]$.
* **Stage 4 ($len=8$):** Uses $\zeta[16..31]$.
* **Stage 5 ($len=4$):** Uses $\zeta[32..63]$.
* **Stage 6 ($len=2$):** Uses $\zeta[64..127]$.

The ROM is combinational (0-cycle read latency), ensuring $\zeta$ is immediately available when memory read data arrives.

---

## 10. How the Controller Works (`ntt_controller.sv`)

The controller is a deterministic Finite State Machine (FSM) managing butterfly sequencing and stage progression:

```
  +------+
  | IDLE | <-----------------------------+
  +------+                               |
     | (start = 1)                       |
     v                                   |
  +------+                               |
  | READ | (Present addr_a, addr_b)      |
  +------+                               |
     | (1 cycle BRAM read)               |
     v                                   |
  +------+                               |
  | CALC | (Pulse bfly_valid_in)         |
  +------+                               |
     | (bfly_valid_out = 1)              |
     v                                   |
  +-------+ (Assert mem_we)              |
  | WRITE |------------------------------+ (Next butterfly / stage)
  +-------+
     | (Stage 6, Butterfly 127 complete)
     v
  +------+
  | DONE | (1-cycle done pulse, busy = 0)
  +------+
```

---

## 11. How the Stages Operate

For each stage $s \in [0..6]$:
* Stride length: $len = 128 \gg s$.
* Number of blocks: $2^s$.
* Butterflies per block: $len$.
* Total butterflies per stage: $2^s \times len = 128$.

### Address Generation Formulas
For butterfly index $i \in [0..127]$:
$$\text{block\_idx} = i \gg (7 - s)$$
$$\text{offset} = i \ \& \ (len - 1)$$
$$\text{start} = \text{block\_idx} \ll (8 - s)$$
$$\text{addr}_A = \text{start} \ | \ \text{offset}$$
$$\text{addr}_B = \text{addr}_A + len$$
$$\text{twiddle\_addr} = (1 \ll s) \ | \ \text{block\_idx}$$

### Concrete Example:
* **Stage 0 ($s=0$, $len=128$):**
  * Butterfly 0: Pair $(0, 128)$, $\zeta = \text{zetas}[1] = 1729$
  * Butterfly 1: Pair $(1, 129)$, $\zeta = \text{zetas}[1] = 1729$
  * Butterfly 127: Pair $(127, 255)$, $\zeta = \text{zetas}[1] = 1729$
* **Stage 1 ($s=1$, $len=64$):**
  * Butterfly 0: Pair $(0, 64)$, $\zeta = \text{zetas}[2] = 2580$
  * Butterfly 63: Pair $(63, 127)$, $\zeta = \text{zetas}[2] = 2580$
  * Butterfly 64: Pair $(128, 192)$, $\zeta = \text{zetas}[3] = 3289$
  * Butterfly 127: Pair $(191, 255)$, $\zeta = \text{zetas}[3] = 3289$

---

## 12. Complete Data Flow

```
 Host Load (load_valid, load_data)
      │
      ▼
┌────────────┐   Read (rdata_a, rdata_b)   ┌───────────┐
│ ntt_memory │ ──────────────────────────► │ butterfly │
│ (256x12)   │ ◄────────────────────────── │  datapath │
└────────────┘   Write (wdata_a, wdata_b)  └───────────┘
      ▲                                          ▲
      │                                          │
┌────────────┐                                   │
│    ntt     │ ───────── twiddle_addr ───► ┌─────────────┐
│ controller │                             │ twiddle_rom │
└────────────┘                             └─────────────┘
      │
      ▼
 Host Read (read_addr, read_data)
```

---

## 13. Latency & Performance Breakdown

* **Butterflies per stage:** 128
* **Stages:** 7
* **Total butterflies:** $128 \times 7 = 896$
* **Cycles per butterfly:**
  * 1 cycle: Memory Read address setup
  * 1 cycle: Memory read data available & butterfly calculation
  * 1 cycle: Memory write back & counter advance
  * **3 cycles / butterfly**
* **Total execution latency:**
  $$\text{Latency} = 896 \times 3 + 2 \text{ (FSM entry/exit)} = 3585 \text{ clock cycles}$$
* At $100\text{ MHz}$ ($10\text{ ns}$ clock):
  $$\text{Execution Time} = 3585 \times 10\text{ ns} = 35.85\ \mu\text{s}$$
* **Throughput:**
  $$\text{Throughput} = \frac{100 \times 10^6}{3585} \approx 27,894 \text{ NTT transforms/second}$$

---

## 14. FPGA Implementation Considerations

1. **Block RAM Mapping:** $256 \times 12$ bits easily fits in a single Xilinx 18Kb Block RAM (`RAMB18E1`).
2. **DSP Slice Usage:** The $12 \times 12$-bit multiplication maps to a single DSP48E1 slice.
3. **Control Overhead:** The entire FSM and address generator consume only ~117 LUTs and 40 Flip-Flops.
4. **Modularity:** Arithmetic modules (`mod_mul`, `mod_add`, `mod_sub`) are fully decoupled for seamless integration with Person 2's optimized implementations.
