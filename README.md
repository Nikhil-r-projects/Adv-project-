# Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM

[![Status](https://img.shields.io/badge/Verification-PASS%20(15%2F15)-brightgreen.svg)]()
[![FPGA](https://img.shields.io/badge/Target-Xilinx%20Artix--7-blue.svg)]()
[![Standard](https://img.shields.io/badge/Spec-NIST%20FIPS%20203-orange.svg)]()

This repository contains **Person 1's complete portion** (NTT Architecture and Datapath Integration) of a 3-person engineering research project implementing a hardware-accelerated **256-point Number Theoretic Transform (NTT)** for post-quantum **ML-KEM (formerly CRYSTALS-Kyber)**.

---

## 1. Project Overview

* **Algorithm:** Number Theoretic Transform (NTT), FIPS 203 Section 4.3 (Algorithm 9)
* **Transform Length ($N$):** 256 coefficients
* **Modulus ($Q$):** 3329 (12-bit unsigned representation)
* **Root of Unity:** $\psi = 17$ ($17^{128} \equiv -1 \pmod{3329}$)
* **Number of Stages:** 7 stages ($len \in \{128, 64, 32, 16, 8, 4, 2\}$)
* **Butterflies per Stage:** 128 radix-2 Cooley-Tukey butterflies
* **Total Operations:** 896 butterfly computations
* **Architecture:** In-place computation with True Dual-Port BRAM and dedicated ROM
* **Total Latency:** 3,585 clock cycles (35.85 $\mu$s @ 100 MHz)

---

## 2. Repository Structure

```
mlkem-ntt-fpga/
├── rtl/
│   └── ntt/
│       ├── butterfly.sv        # Cooley-Tukey butterfly datapath
│       ├── ntt_memory.sv       # True Dual-Port 256x12-bit coefficient memory
│       ├── twiddle_rom.sv      # FIPS 203 verified 128-constant twiddle ROM
│       ├── ntt_controller.sv   # FSM sequencer & address generation engine
│       └── ntt_core.sv         # Top-level integrated NTT core
│
├── tb/
│   ├── ntt/
│   │   ├── butterfly_tb.sv     # Unit testbench for butterfly datapath (110 tests)
│   │   ├── memory_tb.sv        # Unit testbench for coefficient memory (458 checks)
│   │   ├── twiddle_rom_tb.sv   # Mathematical check of all 128 twiddle factors
│   │   ├── ntt_controller_tb.sv# FSM & 896 butterfly address verification
│   │   └── ntt_core_tb.sv      # Full-system testbench against Python golden vectors
│   └── stubs/
│       ├── mod_mul.sv          # 1-cycle registered multiplier simulation stub
│       ├── mod_add.sv          # Combinational modular adder simulation stub
│       └── mod_sub.sv          # Combinational modular subtractor simulation stub
│
├── python/
│   └── reference/
│       └── mlkem_ntt_ref.py    # Independent Python golden reference model
│
├── vectors/                    # 15 pre-generated golden test vectors (.hex)
│
├── scripts/
│   ├── run_all_tests.bat       # 1-click Windows verification script
│   ├── run_all_tests.sh        # 1-click Linux verification script
│   ├── constraints.xdc         # Timing constraint (100 MHz clock)
│   └── synth.tcl               # Vivado FPGA synthesis script
│
├── docs/
│   ├── architecture.md         # In-depth theory, mathematics, and microarchitecture
│   ├── interface.md            # Frozen interfaces for Person 2 arithmetic integration
│   ├── verification.md         # Detailed test coverage and verification matrix
│   ├── results.md              # Actual FPGA utilization and timing numbers
│   ├── utilization_synth.rpt   # Vivado post-synthesis utilization report
│   └── timing_synth.rpt        # Vivado timing summary report
│
└── README.md
```

---

## 3. Architecture Block Diagram

```
                 +-----------------------------------------+
                 |                ntt_core                 |
                 |                                         |
                 |   +----------------+                    |
   start ------->|   | ntt_controller |                    |
   busy <--------|   +-------+--------+                    |
   done <--------|           |                             |
                 |           | ctrl signals                |
                 |           v                             |
                 |   +----------------+   rdata_a, rdata_b |
   load_data --->|   |   ntt_memory   |------------------->|---+
   load_addr --->|   |  (256 x 12-bit |<-------------------|   |
   load_valid -->|   |   TDP RAM)     |   wdata_a, wdata_b |   |
   read_data <---|   +----------------+                    |   |
                 |                                         |   v
                 |   +----------------+      zeta          | +-----------+
                 |   |  twiddle_rom   |------------------->| | butterfly |
                 |   | (FIPS 203 ROM) |                    | +-----------+
                 |   +----------------+                    |
                 +-----------------------------------------+
```

---

## 4. Integration with Person 2 (Arithmetic Modules)

Person 2 provides the final arithmetic RTL. The interfaces are frozen and documented in [`docs/interface.md`](docs/interface.md).

* `mod_mul`: Registered modular multiplier (`(a * b) mod Q`), latency = 1 cycle.
* `mod_add`: Modular adder (`(a + b) mod Q`), latency = 0 or 1 cycle.
* `mod_sub`: Modular subtractor (`(a - b) mod Q`), latency = 0 or 1 cycle.

---

## 5. How to Simulate

### Prerequisites
* **Simulator:** Vivado Simulator (`xvlog`, `xelab`, `xsim`) or any standard SystemVerilog simulator.
* **Python:** Python 3.8+ (for golden reference model).

### Automated One-Click Verification (Windows)
Run from the repository root:
```cmd
scripts\run_all_tests.bat
```

### Automated One-Click Verification (Linux)
```bash
chmod +x scripts/run_all_tests.sh
./scripts/run_all_tests.sh
```

### Running the Python Golden Model & Generating Test Vectors
```bash
python python/reference/mlkem_ntt_ref.py
```

---

## 6. Waveform Inspection

When `ntt_core_tb` runs, it generates `ntt_core.vcd`. To view the waveforms:
```bash
gtkwave ntt_core.vcd
```
Or open within Vivado Simulator:
```cmd
xsim core_sim -gui
```

Inspect key signals:
* `clk`, `rst`, `start`, `busy`, `done`
* `u_controller/stage_q`, `u_controller/bfly_q`
* `u_controller/mem_addr_a`, `u_controller/mem_addr_b`, `u_controller/twiddle_addr`
* `u_butterfly/a_in`, `u_butterfly/b_in`, `u_butterfly/zeta_in`
* `u_butterfly/a_out`, `u_butterfly/b_out`, `u_butterfly/valid_out`

---

## 7. How to Synthesize for FPGA

To run Out-Of-Context synthesis targeting a Xilinx Artix-7 FPGA (`xc7a100tcsg324-1`):
```cmd
vivado -mode batch -source scripts/synth.tcl -nojournal -nolog
```
This generates the post-synthesis utilization report in `docs/utilization_synth.rpt` and the timing report in `docs/timing_synth.rpt`.

---

## 8. Synthesis Results Summary

Target: **Xilinx Artix-7 (`xc7a100tcsg324-1`)**

| Resource | Used | Available | Utilization |
| :--- | :--- | :--- | :--- |
| **Slice LUTs** | **373** | 63,400 | **0.59%** |
| **Slice Registers** | **40** | 126,800 | **0.03%** |
| **Block RAM (RAMB18E1)** | **1** | 270 | **0.37%** |
| **DSP Slices (DSP48E1)** | **1** | 240 | **0.42%** |

---

## 9. Verification Status

| Testbench | Description | Result |
| :--- | :--- | :--- |
| `butterfly_tb.sv` | 110 unit tests on arithmetic datapath | **PASS** |
| `memory_tb.sv` | 458 checks on True Dual-Port memory | **PASS** |
| `twiddle_rom_tb.sv` | 231 checks on 128 FIPS 203 constants | **PASS** |
| `ntt_controller_tb.sv` | 896 butterfly sequence checks | **PASS** |
| `ntt_core_tb.sv` | 15 test vectors ($3,840$ coefficients) | **PASS** |
