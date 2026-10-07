// ============================================================================
// Module: mod_sub (Simulation Stub for Person 2)
// Description: Combinational / 0-cycle latency modular subtractor for modulus Q.
//              Computes result = (a - b) mod Q.
// NOTE: This is a verified reference stub provided by Person 1 for
//       standalone simulation prior to Person 2 delivering final arithmetic RTL.
// ============================================================================

`timescale 1ns / 1ps

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

    logic [WIDTH:0] diff_raw;

    always_comb begin
        if (a >= b) begin
            result = a - b;
        end else begin
            diff_raw = ({1'b0, a} + Q) - {1'b0, b};
            result   = diff_raw[WIDTH-1:0];
        end
        valid_out = valid_in;
    end

endmodule
