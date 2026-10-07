# ML-KEM NTT Accelerator — Interface Specification

**Author:** Person 1 — NTT Architecture Engineer  
**Project:** Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM  
**Target:** Xilinx / Synthesizable SystemVerilog  
**Document Status:** Frozen / Baselined (Phase 1)

---

## 1. Overview & System Parameters

This document defines the frozen hardware interfaces between Person 1's architecture modules (`ntt_core`, `ntt_controller`, `ntt_memory`, `twiddle_rom`, `butterfly`) and Person 2's arithmetic modules (`mod_mul`, `mod_add`, `mod_sub`).

### System Constants
* **$N = 256$**: Number of polynomial coefficients.
* **$Q = 3329$**: ML-KEM prime modulus ($3329 < 2^{12}$).
* **$\text{WIDTH} = 12$**: Coefficient bit-width (unsigned integer in $[0, Q-1]$).
* **$\text{NUM\_STAGES} = 7$**: FIPS 203 ML-KEM NTT stages ($len \in \{128, 64, 32, 16, 8, 4, 2\}$).
* **$\text{BFLIES\_PER\_STAGE} = 128$**: 128 radix-2 butterflies per stage.
* **$\text{TOTAL\_BUTTERFLIES} = 7 \times 128 = 896$**.

---

## 2. Person 2 Arithmetic Module Interfaces

Person 2 is responsible for supplying the modular arithmetic modules. Person 1 implements the butterfly datapath and controller around this frozen specification.

### 2.1. Modular Multiplier (`mod_mul`)
Computes $result = (a \times b) \pmod Q$.

```systemverilog
module mod_mul #(
    parameter int Q     = 3329,
    parameter int WIDTH = 12
)(
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 valid_in,
    input  logic [WIDTH-1:0]     a,
    input  logic [WIDTH-1:0]     b,
    output logic                 valid_out,
    output logic [WIDTH-1:0]     result
);
```
* **Inputs:**
  * `clk`: System clock.
  * `rst`: Synchronous active-high reset.
  * `valid_in`: Asserted when operands `a` and `b` are valid.
  * `a`, `b`: Unsigned operands in $[0, Q-1]$.
* **Outputs:**
  * `valid_out`: Asserted when `result` is valid.
  * `result`: $(a \times b) \pmod Q$, reduced into $[0, Q-1]$.
* **Timing & Latency:**
  * Baseline latency: 1 clock cycle (registered reduction).
  * Combinational (0-cycle) or multi-cycle implementations are supported through `valid_in`/`valid_out` pipelining.

### 2.2. Modular Adder (`mod_add`)
Computes $result = (a + b) \pmod Q$.

```systemverilog
module mod_add #(
    parameter int Q     = 3329,
    parameter int WIDTH = 12
)(
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 valid_in,
    input  logic [WIDTH-1:0]     a,
    input  logic [WIDTH-1:0]     b,
    output logic                 valid_out,
    output logic [WIDTH-1:0]     result
);
```
* **Operation:** If $a + b \ge Q$, subtract $Q$. Result is strictly in $[0, Q-1]$.
* **Timing & Latency:** Combinational (0 cycles) or 1-cycle registered.

### 2.3. Modular Subtractor (`mod_sub`)
Computes $result = (a - b) \pmod Q$.

```systemverilog
module mod_sub #(
    parameter int Q     = 3329,
    parameter int WIDTH = 12
)(
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 valid_in,
    input  logic [WIDTH-1:0]     a,
    input  logic [WIDTH-1:0]     b,
    output logic                 valid_out,
    output logic [WIDTH-1:0]     result
);
```
* **Operation:** If $a < b$, add $Q$. Result is strictly in $[0, Q-1]$.
* **Timing & Latency:** Combinational (0 cycles) or 1-cycle registered.

---

## 3. Architecture Modules (Person 1)

### 3.1. Cooley-Tukey Butterfly (`butterfly.sv`)
Performs the core FIPS 203 / ML-KEM butterfly operation:
$$t = (b_{\text{in}} \times \zeta_{\text{in}}) \pmod Q$$
$$a_{\text{out}} = (a_{\text{in}} + t) \pmod Q$$
$$b_{\text{out}} = (a_{\text{in}} - t) \pmod Q$$

```systemverilog
module butterfly #(
    parameter int Q     = 3329,
    parameter int WIDTH = 12
)(
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 valid_in,
    input  logic [WIDTH-1:0]     a_in,
    input  logic [WIDTH-1:0]     b_in,
    input  logic [WIDTH-1:0]     zeta_in,
    output logic                 valid_out,
    output logic [WIDTH-1:0]     a_out,
    output logic [WIDTH-1:0]     b_out
);
```
* **Internal Structure:** Instantiates `mod_mul`, `mod_add`, and `mod_sub`.
* **Latency:** Matches the latency of `mod_mul` + add/sub pipeline. For 1-cycle registered multiplier and combinational adder/subtractor, total latency is 1 clock cycle.

### 3.2. NTT Memory (`ntt_memory.sv`)
True Dual-Port RAM storing 256 coefficients of 12 bits each.

```systemverilog
module ntt_memory #(
    parameter int WIDTH      = 12,
    parameter int DEPTH      = 256,
    parameter int ADDR_WIDTH = 8
)(
    input  logic                  clk,
    // Port A (Read / Write)
    input  logic                  we_a,
    input  logic [ADDR_WIDTH-1:0] addr_a,
    input  logic [WIDTH-1:0]      wdata_a,
    output logic [WIDTH-1:0]      rdata_a,
    // Port B (Read / Write)
    input  logic                  we_b,
    input  logic [ADDR_WIDTH-1:0] addr_b,
    input  logic [WIDTH-1:0]      wdata_b,
    output logic [WIDTH-1:0]      rdata_b
);
```
* **Timing:** Synchronous read (1-cycle read latency) and synchronous write. Maps directly to FPGA Block RAM (BRAM) primitive.

### 3.3. Twiddle ROM (`twiddle_rom.sv`)
Stores the verified 128 twiddle factors from FIPS 203 Table 2:
$\zeta[k] = 17^{\text{BitRev}_7(k)} \pmod{3329}$.

```systemverilog
module twiddle_rom #(
    parameter int WIDTH      = 12,
    parameter int DEPTH      = 128,
    parameter int ADDR_WIDTH = 7
)(
    input  logic [ADDR_WIDTH-1:0] addr,
    output logic [WIDTH-1:0]      zeta
);
```
* **Timing:** Asynchronous / combinational lookup (0-cycle latency).

### 3.4. NTT Controller (`ntt_controller.sv`)
FSM sequencing memory reads, butterfly computation, memory writes, and stage progression.

```systemverilog
module ntt_controller #(
    parameter int NUM_STAGES = 7,
    parameter int ADDR_WIDTH = 8
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  start,
    output logic                  busy,
    output logic                  done,
    // Memory Addressing
    output logic [ADDR_WIDTH-1:0] mem_addr_a,
    output logic [ADDR_WIDTH-1:0] mem_addr_b,
    output logic                  mem_we,
    // Twiddle Addressing
    output logic [6:0]            twiddle_addr,
    // Butterfly Handshake
    output logic                  bfly_valid_in,
    input  logic                  bfly_valid_out,
    // Status
    output logic [2:0]            stage_out,
    output logic [6:0]            bfly_cnt_out
);
```

### 3.5. Top-Level NTT Core (`ntt_core.sv`)
Integrates controller, memory, butterfly, and twiddle ROM with clean host loading and retrieval interfaces.

```systemverilog
module ntt_core #(
    parameter int Q          = 3329,
    parameter int WIDTH      = 12,
    parameter int N          = 256,
    parameter int NUM_STAGES = 7
)(
    input  logic             clk,
    input  logic             rst,
    // Execution control
    input  logic             start,
    output logic             busy,
    output logic             done,
    // Host Coefficient Load Interface
    input  logic             load_valid,
    input  logic [7:0]       load_addr,
    input  logic [WIDTH-1:0] load_data,
    output logic             load_ready,
    // Host Coefficient Read Interface
    input  logic [7:0]       read_addr,
    output logic [WIDTH-1:0] read_data
);
```
* **Host Control Protocol:**
  1. Hold `rst = 1` for $\ge 1$ cycle.
  2. While `busy == 0` and `load_ready == 1`, assert `load_valid` to stream 256 coefficients into `load_addr` $[0..255]$.
  3. Pulse `start = 1` for 1 cycle.
  4. Core asserts `busy = 1`. Host waits.
  5. Upon completion, core emits a 1-cycle pulse on `done = 1` and drops `busy = 0`.
  6. Host applies `read_addr` $[0..255]$ to inspect the transformed coefficients via `read_data`.
