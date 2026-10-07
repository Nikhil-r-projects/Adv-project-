// ============================================================================
// File: rtl/ntt/ntt_core.sv
// Module: ntt_core
// Author: Person 1 — NTT Architecture Engineer
// Project: Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM
//
// Description:
//   Top-level integration core of the 256-point ML-KEM NTT accelerator.
//   Integrates:
//     - ntt_controller: FSM sequencer and address generator
//     - ntt_memory: True Dual-Port 256 x 12-bit coefficient memory
//     - butterfly: Cooley-Tukey radix-2 arithmetic datapath
//     - twiddle_rom: NIST FIPS 203 verified twiddle factor ROM
//
// Host Interface:
//   - Load Port: load_valid, load_addr, load_data, load_ready
//   - Control:   start, busy, done (1-cycle pulse)
//   - Read Port: read_addr, read_data
//
// Operation Protocol:
//   1. Assert rst for >= 1 cycle.
//   2. While load_ready == 1, assert load_valid to write 256 coefficients.
//   3. Pulse start = 1 for 1 cycle.
//   4. busy stays 1 while core processes the 7 stages (896 butterflies).
//   5. done pulses 1 for 1 cycle, busy drops to 0.
//   6. Assert read_addr [0..255] to read out NTT-transformed coefficients.
// ============================================================================

`timescale 1ns / 1ps

module ntt_core #(
    parameter int Q          = 3329,
    parameter int WIDTH      = 12,
    parameter int N          = 256,
    parameter int NUM_STAGES = 7,
    parameter int ADDR_WIDTH = 8
)(
    input  logic                  clk,
    input  logic                  rst,

    // Execution Control
    input  logic                  start,
    output logic                  busy,
    output logic                  done,

    // Host Load Interface
    input  logic                  load_valid,
    input  logic [ADDR_WIDTH-1:0] load_addr,
    input  logic [WIDTH-1:0]      load_data,
    output logic                  load_ready,

    // Host Read Interface
    input  logic [ADDR_WIDTH-1:0] read_addr,
    output logic [WIDTH-1:0]      read_data
);

    // ------------------------------------------------------------------------
    // Internal Interconnect Signals
    // ------------------------------------------------------------------------
    // Controller signals
    logic                  ctrl_busy;
    logic                  ctrl_done;
    logic [ADDR_WIDTH-1:0] ctrl_mem_addr_a;
    logic [ADDR_WIDTH-1:0] ctrl_mem_addr_b;
    logic                  ctrl_mem_we;
    logic [6:0]            ctrl_twiddle_addr;
    logic                  ctrl_bfly_valid_in;
    logic [2:0]            ctrl_stage;
    logic [6:0]            ctrl_bfly_cnt;

    // Memory signals
    logic                  mem_we_a;
    logic [ADDR_WIDTH-1:0] mem_addr_a;
    logic [WIDTH-1:0]      mem_wdata_a;
    logic [WIDTH-1:0]      mem_rdata_a;

    logic                  mem_we_b;
    logic [ADDR_WIDTH-1:0] mem_addr_b;
    logic [WIDTH-1:0]      mem_wdata_b;
    logic [WIDTH-1:0]      mem_rdata_b;

    // Butterfly signals
    logic                  bfly_valid_out;
    logic [WIDTH-1:0]      bfly_a_out;
    logic [WIDTH-1:0]      bfly_b_out;

    // Twiddle ROM output
    logic [WIDTH-1:0]      rom_zeta;

    // ------------------------------------------------------------------------
    // Top-Level Control & Status Routing
    // ------------------------------------------------------------------------
    assign busy       = ctrl_busy;
    assign done       = ctrl_done;
    assign load_ready = ~ctrl_busy;
    assign read_data  = mem_rdata_a; // Read port mapped to Port A rdata

    // ------------------------------------------------------------------------
    // Memory Port Multiplexing (Host vs Controller)
    // ------------------------------------------------------------------------
    always_comb begin
        if (ctrl_busy) begin
            // Internal NTT Execution mode
            mem_we_a    = ctrl_mem_we;
            mem_addr_a  = ctrl_mem_addr_a;
            mem_wdata_a = bfly_a_out;

            mem_we_b    = ctrl_mem_we;
            mem_addr_b  = ctrl_mem_addr_b;
            mem_wdata_b = bfly_b_out;
        end else begin
            // Host Access mode (Idle)
            // Port A serves Host Write (load) and Host Read
            mem_we_a    = load_valid;
            mem_addr_a  = load_valid ? load_addr : read_addr;
            mem_wdata_a = load_data;

            // Port B idle during host mode
            mem_we_b    = 1'b0;
            mem_addr_b  = '0;
            mem_wdata_b = '0;
        end
    end

    // ------------------------------------------------------------------------
    // Module Instances
    // ------------------------------------------------------------------------

    // 1. Controller Instance
    ntt_controller #(
        .NUM_STAGES(NUM_STAGES),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_controller (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .busy          (ctrl_busy),
        .done          (ctrl_done),
        .mem_addr_a    (ctrl_mem_addr_a),
        .mem_addr_b    (ctrl_mem_addr_b),
        .mem_we        (ctrl_mem_we),
        .twiddle_addr  (ctrl_twiddle_addr),
        .bfly_valid_in (ctrl_bfly_valid_in),
        .bfly_valid_out(bfly_valid_out),
        .stage_out     (ctrl_stage),
        .bfly_cnt_out  (ctrl_bfly_cnt)
    );

    // 2. Memory Instance (True Dual-Port RAM)
    ntt_memory #(
        .WIDTH     (WIDTH),
        .DEPTH     (N),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_memory (
        .clk    (clk),
        .we_a   (mem_we_a),
        .addr_a (mem_addr_a),
        .wdata_a(mem_wdata_a),
        .rdata_a(mem_rdata_a),
        .we_b   (mem_we_b),
        .addr_b (mem_addr_b),
        .wdata_b(mem_wdata_b),
        .rdata_b(mem_rdata_b)
    );

    // 3. Twiddle ROM Instance
    twiddle_rom #(
        .WIDTH     (WIDTH),
        .DEPTH     (128),
        .ADDR_WIDTH(7)
    ) u_twiddle_rom (
        .addr(ctrl_twiddle_addr),
        .zeta(rom_zeta)
    );

    // 4. Butterfly Datapath Instance
    butterfly #(
        .Q              (Q),
        .WIDTH          (WIDTH),
        .REGISTER_OUTPUT(1'b0)
    ) u_butterfly (
        .clk      (clk),
        .rst      (rst),
        .valid_in (ctrl_bfly_valid_in),
        .a_in     (mem_rdata_a),
        .b_in     (mem_rdata_b),
        .zeta_in  (rom_zeta),
        .valid_out(bfly_valid_out),
        .a_out    (bfly_a_out),
        .b_out    (bfly_b_out)
    );

endmodule
