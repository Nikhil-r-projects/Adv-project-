// ============================================================================
// File: rtl/ntt/butterfly.sv
// Module: butterfly
// Author: Person 1 — NTT Architecture Engineer
// Project: Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM
//
// Description:
//   Performs the Cooley-Tukey (CT) radix-2 butterfly operation defined in
//   FIPS 203 Section 4.3 (Algorithm 9):
//       t     = (b_in * zeta_in) mod Q
//       a_out = (a_in + t) mod Q
//       b_out = (a_in - t) mod Q
//
// Submodules Instantiated:
//   - mod_mul: Modular multiplier (Person 2 interface)
//   - mod_add: Modular adder      (Person 2 interface)
//   - mod_sub: Modular subtractor (Person 2 interface)
//
// Timing & Latency:
//   - Assumes mod_mul has 1 clock cycle latency (valid_in -> valid_out = 1 cycle).
//   - Pipelining: a_in is delayed by 1 clock cycle to align with mod_mul output t.
//   - Parameter REGISTER_OUTPUT:
//       0: Combinational add/sub after multiplier (total latency = 1 cycle).
//       1: Registered add/sub outputs (total latency = 2 cycles).
//   - valid_out pulses high when a_out and b_out are valid.
//
// Reset / Control Convention:
//   - Synchronous active-high reset (rst).
// ============================================================================

`timescale 1ns / 1ps

module butterfly #(
    parameter int Q               = 3329,
    parameter int WIDTH           = 12,
    parameter bit REGISTER_OUTPUT = 1'b0
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

    // ------------------------------------------------------------------------
    // Internal Signals & Pipeline Registers
    // ------------------------------------------------------------------------
    logic [WIDTH-1:0] a_pipe;
    logic             mul_valid_out;
    logic [WIDTH-1:0] t_mul;

    logic [WIDTH-1:0] add_res;
    logic [WIDTH-1:0] sub_res;
    logic             add_valid_out;
    logic             sub_valid_out;

    // Delay a_in by 1 clock cycle to match mod_mul latency
    always_ff @(posedge clk) begin
        if (rst) begin
            a_pipe <= '0;
        end else if (valid_in) begin
            a_pipe <= a_in;
        end
    end

    // ------------------------------------------------------------------------
    // Modular Multiplier Instance: t = (b_in * zeta_in) mod Q
    // ------------------------------------------------------------------------
    mod_mul #(
        .Q    (Q),
        .WIDTH(WIDTH)
    ) u_mod_mul (
        .clk      (clk),
        .rst      (rst),
        .valid_in (valid_in),
        .a        (b_in),
        .b        (zeta_in),
        .valid_out(mul_valid_out),
        .result   (t_mul)
    );

    // ------------------------------------------------------------------------
    // Modular Adder Instance: a_out = (a_pipe + t_mul) mod Q
    // ------------------------------------------------------------------------
    mod_add #(
        .Q    (Q),
        .WIDTH(WIDTH)
    ) u_mod_add (
        .clk      (clk),
        .rst      (rst),
        .valid_in (mul_valid_out),
        .a        (a_pipe),
        .b        (t_mul),
        .valid_out(add_valid_out),
        .result   (add_res)
    );

    // ------------------------------------------------------------------------
    // Modular Subtractor Instance: b_out = (a_pipe - t_mul) mod Q
    // ------------------------------------------------------------------------
    mod_sub #(
        .Q    (Q),
        .WIDTH(WIDTH)
    ) u_mod_sub (
        .clk      (clk),
        .rst      (rst),
        .valid_in (mul_valid_out),
        .a        (a_pipe),
        .b        (t_mul),
        .valid_out(sub_valid_out),
        .result   (sub_res)
    );

    // ------------------------------------------------------------------------
    // Output Stage Selection
    // ------------------------------------------------------------------------
    generate
        if (REGISTER_OUTPUT) begin : g_reg_out
            always_ff @(posedge clk) begin
                if (rst) begin
                    valid_out <= 1'b0;
                    a_out     <= '0;
                    b_out     <= '0;
                end else begin
                    valid_out <= mul_valid_out;
                    if (mul_valid_out) begin
                        a_out <= add_res;
                        b_out <= sub_res;
                    end
                end
            end
        end else begin : g_comb_out
            assign valid_out = mul_valid_out;
            assign a_out     = add_res;
            assign b_out     = sub_res;
        end
    endgenerate

endmodule
