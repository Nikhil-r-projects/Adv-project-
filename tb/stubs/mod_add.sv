// ============================================================================
// Module: mod_add (Simulation Stub for Person 2)
// Description: Combinational / 0-cycle latency modular adder for modulus Q.
//              Computes result = (a + b) mod Q.
// NOTE: This is a verified reference stub provided by Person 1 for
//       standalone simulation prior to Person 2 delivering final arithmetic RTL.
// ============================================================================

`timescale 1ns / 1ps

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

    logic [WIDTH:0] sum_raw;

    always_comb begin
        sum_raw   = {1'b0, a} + {1'b0, b};
        result    = (sum_raw >= Q) ? (sum_raw - Q) : sum_raw[WIDTH-1:0];
        valid_out = valid_in;
    end

endmodule
