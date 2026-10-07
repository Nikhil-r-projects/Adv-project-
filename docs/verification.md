# ML-KEM NTT Accelerator — Verification Report

**Author:** Person 1 — NTT Architecture Engineer  
**Project:** Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM  
**Verification Tool:** Vivado Simulator 2018.3 (`xvlog`, `xelab`, `xsim`)  
**Status:** All Tests Executed and Verified PASS  

---

## 1. Verification Strategy & Hierarchy

The verification plan follows a bottom-up hierarchical methodology across all five architecture modules and top-level integration:

```
Level 1: Datapath Arithmetic (butterfly_tb.sv)
    └── Cooley-Tukey butterfly operations, wraparound, bounds, 100 random cases.
Level 2: Memory Subsystem (memory_tb.sv)
    └── True Dual-Port RAM concurrent reads, writes, boundary addresses 0 and 255.
Level 3: Twiddle Factor Storage (twiddle_rom_tb.sv)
    └── Mathematical verification of all 128 constants against 17^(BitRev_7(k)) mod 3329.
Level 4: Sequencing & Addressing (ntt_controller_tb.sv)
    └── 896 butterfly address triplets, stage progression, 1-cycle done pulse.
Level 5: Full Core Integration (ntt_core_tb.sv)
    └── End-to-end verification across 15 test vectors against Python golden model.
```

---

## 2. Test Execution Details

### 2.1. Butterfly Verification (`butterfly_tb.sv`)
* **Purpose:** Verify Cooley-Tukey butterfly datapath: $t = (b \cdot \zeta) \pmod Q$, $a_{\text{new}} = (a + t) \pmod Q$, $b_{\text{new}} = (a - t) \pmod Q$.
* **Tests Executed:**
  * `TC1`: All-zero inputs ($a=0, b=0, \zeta=0$)
  * `TC2`: Zero twiddle factor ($\zeta=0$)
  * `TC3`: Identity twiddle factor ($\zeta=1$)
  * `TC4`: Equal operands ($a=b$)
  * `TC5`: Subtraction modular wraparound ($a < t$)
  * `TC6`: Addition modular wraparound ($a + t \ge Q$)
  * `TC7`: Maximum boundary values ($a = b = \zeta = Q - 1 = 3328$)
  * `TC8`: Near-boundary values ($a = 3327, b = 3328, \zeta = 1729$)
  * `TC9`: Realistic ML-KEM twiddle factor ($\zeta = 1729$)
  * `TC10`: Realistic ML-KEM twiddle factor ($\zeta = 2580$)
  * `TC_RAND_0..99`: 100 pseudorandom cases over $[0, Q-1]$.
* **Outcome:** 110/110 tests passed (0 errors).

### 2.2. Memory Verification (`memory_tb.sv`)
* **Purpose:** Verify True Dual-Port 256×12-bit coefficient memory.
* **Tests Executed:**
  * `TC1`: Full dual-port concurrent write to all 256 addresses (Port A [0..127], Port B [128..255]).
  * `TC2`: Full dual-port readback and comparison against shadow array.
  * `TC3`: Simultaneous access to boundary addresses 0 and 255.
  * `TC4`: 100 random dual-port read/write operations.
* **Outcome:** 458/458 operations passed (0 errors).

### 2.3. Twiddle ROM Verification (`twiddle_rom_tb.sv`)
* **Purpose:** Verify that ROM entries exactly match FIPS 203 Section 4.3 Table 2.
* **Tests Executed:**
  * `TC1`: Exhaustive check of all 128 ROM addresses against an independent testbench mathematical function computing $17^{\text{BitRev}_7(k)} \pmod{3329}$.
  * `TC2`: Explicit boundary check for $\zeta[0]=1$, $\zeta[1]=1729$, and $\zeta[127]=2154$.
  * `TC3`: 100 random address lookups.
* **Outcome:** 231/231 checks passed (0 errors).

### 2.4. Controller Verification (`ntt_controller_tb.sv`)
* **Purpose:** Verify FSM state transitions, counter progression, and address generation.
* **Tests Executed:**
  * IDLE and reset verification.
  * Assertion of `busy` upon `start`.
  * Tracking of all 896 butterfly operations through stages 0 to 6.
  * Cycle-by-cycle comparison of `(mem_addr_a, mem_addr_b, twiddle_addr)` against golden FIPS 203 sequence.
  * Verification that no butterfly was skipped or duplicated.
  * Detection of 1-cycle `done` pulse and return to IDLE.
* **Outcome:** 896/896 butterflies verified (0 errors).

### 2.5. Full NTT Core Verification (`ntt_core_tb.sv`)
* **Purpose:** Full integration testing against Python golden reference (`mlkem_ntt_ref.py`).
* **Test Vectors:**
  1. `vec_000_all_zeros`: All 256 coefficients are 0.
  2. `vec_001_impulse_0`: Single non-zero coefficient $f[0] = 1$.
  3. `vec_002_impulse_128`: Single non-zero coefficient $f[128] = 1$.
  4. `vec_003_linear_ramp`: Linear ramp $f[i] = i \pmod{3329}$.
  5. `vec_004_alternating_max`: Alternating 3328 and 0.
  6. `vec_005_random`: Pseudorandom vector 1 (seed = 12345).
  7. `vec_006_random`: Pseudorandom vector 2.
  8. `vec_007_random`: Pseudorandom vector 3.
  9. `vec_008_random`: Pseudorandom vector 4.
  10. `vec_009_random`: Pseudorandom vector 5.
  11. `vec_010_random`: Pseudorandom vector 6.
  12. `vec_011_random`: Pseudorandom vector 7.
  13. `vec_012_random`: Pseudorandom vector 8.
  14. `vec_013_random`: Pseudorandom vector 9.
  15. `vec_014_random`: Pseudorandom vector 10.
* **Outcome:** 15/15 vectors passed (0 mismatches across $15 \times 256 = 3,840$ coefficients).
* **Measured Latency:** 3,585 clock cycles per NTT transform.

---

## 3. Final Verification Matrix

| Test Suite / Test Name | Module Under Test | Vectors / Checks | Result | Execution Tool |
| :--- | :--- | :--- | :--- | :--- |
| **Butterfly Test** (`butterfly_tb`) | `butterfly.sv` | 110 cases | **PASS** | Vivado Simulator 2018.3 |
| **Memory Test** (`memory_tb`) | `ntt_memory.sv` | 458 operations | **PASS** | Vivado Simulator 2018.3 |
| **Twiddle ROM Test** (`twiddle_rom_tb`) | `twiddle_rom.sv` | 231 checks | **PASS** | Vivado Simulator 2018.3 |
| **Controller Test** (`ntt_controller_tb`) | `ntt_controller.sv` | 896 operations | **PASS** | Vivado Simulator 2018.3 |
| **Vector 0: All Zeros** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 1: Impulse @ 0** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 2: Impulse @ 128** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 3: Linear Ramp** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 4: Alternating Max** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 5: Random 1** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 6: Random 2** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 7: Random 3** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 8: Random 4** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 9: Random 5** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 10: Random 6** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 11: Random 7** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 12: Random 8** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 13: Random 9** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Vector 14: Random 10** | `ntt_core.sv` | 256 coefficients | **PASS** | Vivado Simulator 2018.3 |
| **Complete System NTT** | `ntt_core.sv` | 15 / 15 vectors | **PASS** | Vivado Simulator 2018.3 |
