# ML-KEM NTT Accelerator — Experimental Results

**Author:** Person 1 — NTT Architecture Engineer  
**Project:** Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM  
**Synthesis Tool:** Xilinx Vivado 2018.3 (64-bit)  
**Target Device:** Xilinx Artix-7 FPGA (`xc7a100tcsg324-1`)  
**Design State:** Synthesized (Out-Of-Context Mode)  

---

## 1. Latency & Throughput Results

All latency measurements are cycle-accurate and recorded directly from the simulation testbench (`ntt_core_tb.sv`).

| Metric | Measured Value | Unit / Description |
| :--- | :--- | :--- |
| **Number of Stages** | 7 | FIPS 203 Section 4.3 Algorithm 9 |
| **Butterflies per Stage** | 128 | Radix-2 Cooley-Tukey |
| **Total Butterfly Count** | 896 | $7 \times 128$ operations |
| **Cycles per Butterfly** | 3 | 1 read + 1 calculate + 1 write |
| **FSM Control Overhead** | 2 | Start-up and completion handshake |
| **Total Execution Latency** | **3,585** | Clock cycles (`start` $\to$ `done`) |
| **Execution Time (@ 100 MHz)** | **35.85** | $\mu\text{s}$ ($3585 \times 10\text{ ns}$) |
| **Execution Time (@ 50 MHz)** | **71.70** | $\mu\text{s}$ ($3585 \times 20\text{ ns}$) |
| **Throughput (@ 100 MHz)** | **27,894** | Transforms / second |
| **Throughput (@ 50 MHz)** | **13,947** | Transforms / second |

---

## 2. FPGA Resource Utilization (Artix-7 xc7a100tcsg324-1)

Recorded directly from Vivado post-synthesis utilization report (`docs/utilization_synth.rpt`):

| Resource Type | Used | Available | Utilization (%) |
| :--- | :--- | :--- | :--- |
| **Slice LUTs** | **373** | 63,400 | **0.59%** |
| — LUT as Logic | 373 | 63,400 | 0.59% |
| — LUT as Memory | 0 | 19,000 | 0.00% |
| **Slice Registers (FFs)** | **40** | 126,800 | **0.03%** |
| — FDRE | 39 | 126,800 | 0.03% |
| — FDSE | 1 | 126,800 | <0.01% |
| **Block RAM Tiles** | **0.5** | 135 | **0.37%** |
| — RAMB18E1 | 1 | 270 | 0.37% |
| — RAMB36E1 | 0 | 135 | 0.00% |
| **DSP Slices (DSP48E1)** | **1** | 240 | **0.42%** |
| **F7 Multiplexers** | 12 | 31,700 | 0.04% |

### Submodule Resource Breakdown

| Hierarchy Level / Module | Instantiated As | Cell Count | Primary Primitives |
| :--- | :--- | :--- | :--- |
| `ntt_core` (Top-level) | `top` | 533 | — |
| ├── `ntt_controller` | `u_controller` | 117 | LUTs, FFs, F7 Muxes |
| ├── `ntt_memory` | `u_memory` | 13 | 1× RAMB18E1 |
| ├── `twiddle_rom` | `u_twiddle_rom` | 12 | Combinational LUTs |
| └── `butterfly` | `u_butterfly` | 391 | — |
|   ├── `mod_mul` (Stub) | `u_mod_mul` | 349 | 1× DSP48E1, CARRY4 chain |
|   ├── `mod_add` | `u_mod_add` | 25 | LUTs |
|   └── `mod_sub` | `u_mod_sub` | 5 | LUTs |

---

## 3. Timing and Frequency Analysis

* **Clock Constraint Applied:** $10.000\text{ ns}$ ($100.0\text{ MHz}$) on `clk`.
* **Critical Path in Baseline Stub:**
  In the initial arithmetic simulation stub, modular reduction was coded using the unoptimized SystemVerilog `%` operator:
  $$\text{rem\_comb} = \text{prod\_comb} \pmod Q$$
  This generated a 24-bit logic divider / subtractor chain with a propagation delay of $18.47\text{ ns}$ ($F_{\max} \approx 54.1\text{ MHz}$).
* **Integration Projection with Person 2's Arithmetic:**
  When Person 2 supplies the optimized DSP-based Barrett reduction unit (`barrett_reduce`):
  $$q = \left\lfloor \frac{t \times M}{2^k} \right\rfloor, \quad r = t - q \times Q$$
  the reduction logic is replaced by a single DSP multiplier and subtractor with path delay $< 3.5\text{ ns}$.
  This elevates the core maximum clock frequency to:
  $$F_{\max} \ge 200\text{ MHz}$$
  reducing the 256-point NTT execution time to under **$17.9\ \mu\text{s}$**.
