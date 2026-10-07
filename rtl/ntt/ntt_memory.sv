// ============================================================================
// File: rtl/ntt/ntt_memory.sv
// Module: ntt_memory
// Author: Person 1 — NTT Architecture Engineer
// Project: Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM
//
// Description:
//   True Dual-Port (TDP) RAM storing 256 polynomial coefficients (256 x 12-bit).
//   Allows simultaneous 2-point read (addr_a, addr_b) or simultaneous
//   2-point write (wdata_a -> addr_a, wdata_b -> addr_b) during butterfly
//   computations.
//
// Hardware Architecture & Synthesis Mapping:
//   - Inferred as synchronous Block RAM (or Distributed RAM) by FPGA synthesis tools.
//   - Read-first synchronous behavior: rdata is registered with 1-cycle latency.
//   - Synthesizable RTL without unsynthesizable file I/O ($readmemh is kept in TB).
//
// Parameters:
//   - WIDTH: Coefficient bit width (default: 12)
//   - DEPTH: Number of coefficients (default: 256)
//   - ADDR_WIDTH: Address bit width ($clog2(DEPTH) = 8)
// ============================================================================

`timescale 1ns / 1ps

module ntt_memory #(
    parameter int WIDTH      = 12,
    parameter int DEPTH      = 256,
    parameter int ADDR_WIDTH = 8
)(
    input  logic                  clk,

    // ------------------------------------------------------------------------
    // Port A: Coefficient A Read/Write
    // ------------------------------------------------------------------------
    input  logic                  we_a,
    input  logic [ADDR_WIDTH-1:0] addr_a,
    input  logic [WIDTH-1:0]      wdata_a,
    output logic [WIDTH-1:0]      rdata_a,

    // ------------------------------------------------------------------------
    // Port B: Coefficient B Read/Write
    // ------------------------------------------------------------------------
    input  logic                  we_b,
    input  logic [ADDR_WIDTH-1:0] addr_b,
    input  logic [WIDTH-1:0]      wdata_b,
    output logic [WIDTH-1:0]      rdata_b
);

    // RAM array declaration
    (* ram_style = "block" *) logic [WIDTH-1:0] mem [DEPTH-1:0];

    // Port A Synchronous Process
    always_ff @(posedge clk) begin
        if (we_a) begin
            mem[addr_a] <= wdata_a;
        end
        rdata_a <= mem[addr_a];
    end

    // Port B Synchronous Process
    always_ff @(posedge clk) begin
        if (we_b) begin
            mem[addr_b] <= wdata_b;
        end
        rdata_b <= mem[addr_b];
    end

endmodule
