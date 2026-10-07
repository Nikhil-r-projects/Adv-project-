// ============================================================================
// Module: mod_mul (Simulation Stub for Person 2)
// Description: Registered modular multiplier for modulus Q.
//              Computes result = (a * b) mod Q with 1 clock cycle latency.
// NOTE: This is a verified reference stub provided by Person 1 for
//       standalone simulation prior to Person 2 delivering final arithmetic RTL.
// ============================================================================

`timescale 1ns / 1ps

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

    // 24-bit intermediate product
    logic [2*WIDTH-1:0] prod_comb;
    logic [WIDTH-1:0]   rem_comb;

    always_comb begin
        prod_comb = a * b;
        rem_comb  = prod_comb % Q;
    end

    // 1-cycle registered output
    always_ff @(posedge clk) begin
        if (rst) begin
            valid_out <= 1'b0;
            result    <= '0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                result <= rem_comb;
            end else begin
                result <= '0;
            end
        end
    end

endmodule
