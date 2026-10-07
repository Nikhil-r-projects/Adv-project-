// ============================================================================
// File: tb/ntt/butterfly_tb.sv
// Testbench: butterfly_tb
// Author: Person 1 — NTT Architecture Engineer
// Project: Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM
//
// Description:
//   Self-checking verification testbench for butterfly.sv.
//   Verifies Cooley-Tukey butterfly arithmetic:
//       t_exp = (b * zeta) mod Q
//       a_exp = (a + t_exp) mod Q
//       b_exp = (a - t_exp) mod Q
//   Covers corner cases, wraparound, boundary values (Q-1), and 100+ random cases.
// ============================================================================

`timescale 1ns / 1ps

module butterfly_tb;

    localparam int Q     = 3329;
    localparam int WIDTH = 12;
    localparam time CLK_PERIOD = 10ns;

    // Clock and Reset
    logic             clk;
    logic             rst;

    // DUT Signals
    logic             valid_in;
    logic [WIDTH-1:0] a_in;
    logic [WIDTH-1:0] b_in;
    logic [WIDTH-1:0] zeta_in;

    logic             valid_out;
    logic [WIDTH-1:0] a_out;
    logic [WIDTH-1:0] b_out;

    // Scoreboard / Test State
    int pass_count  = 0;
    int error_count = 0;
    int test_num    = 0;

    // Instantiate DUT
    butterfly #(
        .Q              (Q),
        .WIDTH          (WIDTH),
        .REGISTER_OUTPUT(1'b0)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .valid_in (valid_in),
        .a_in     (a_in),
        .b_in     (b_in),
        .zeta_in  (zeta_in),
        .valid_out(valid_out),
        .a_out    (a_out),
        .b_out    (b_out)
    );

    // Clock Generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Task to apply a stimulus and check result 1 cycle later
    task automatic check_butterfly(
        input [WIDTH-1:0] a_val,
        input [WIDTH-1:0] b_val,
        input [WIDTH-1:0] z_val,
        input string      test_name
    );
        logic [WIDTH-1:0] exp_t;
        logic [WIDTH-1:0] exp_a;
        logic [WIDTH-1:0] exp_b;
        longint full_t;
        longint full_a;
        longint full_b;

        // Golden model computation
        full_t = (longint'(b_val) * longint'(z_val)) % Q;
        exp_t  = full_t[WIDTH-1:0];

        full_a = (longint'(a_val) + full_t) % Q;
        exp_a  = full_a[WIDTH-1:0];

        full_b = (longint'(a_val) + Q - full_t) % Q;
        exp_b  = full_b[WIDTH-1:0];

        // Apply input on clock edge
        @(posedge clk);
        valid_in <= 1'b1;
        a_in     <= a_val;
        b_in     <= b_val;
        zeta_in  <= z_val;

        // Next clock edge: DUT registers input, valid_in cleared
        @(posedge clk);
        valid_in <= 1'b0;
        a_in     <= '0;
        b_in     <= '0;
        zeta_in  <= '0;

        // Next clock edge: 1 cycle latency elapsed, outputs are valid
        // Sample just before or after the clock edge
        #1; // small delta after clock edge to inspect registered output
        if (!valid_out) begin
            $display("[FAIL] %s: valid_out was not asserted on expected cycle!", test_name);
            error_count++;
        end else begin
            if (a_out !== exp_a || b_out !== exp_b) begin
                $display("[FAIL] %s: Inputs (a=%0d, b=%0d, zeta=%0d)", test_name, a_val, b_val, z_val);
                $display("       Expected (a_out=%0d, b_out=%0d), Got (a_out=%0d, b_out=%0d)",
                         exp_a, exp_b, a_out, b_out);
                error_count++;
            end else begin
                pass_count++;
            end
        end
        test_num++;
    endtask

    // Main Test Sequence
    initial begin
        $display("==================================================");
        $display("Starting butterfly_tb verification...");
        $display("==================================================");

        // Reset
        rst      = 1'b1;
        valid_in = 1'b0;
        a_in     = '0;
        b_in     = '0;
        zeta_in  = '0;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // Test 1: All zeros
        check_butterfly(12'd0, 12'd0, 12'd0, "TC1: All Zeros");

        // Test 2: Zeta zero
        check_butterfly(12'd1000, 12'd2000, 12'd0, "TC2: Zeta=0");

        // Test 3: Identity multiplier (zeta = 1)
        check_butterfly(12'd500, 12'd300, 12'd1, "TC3: Zeta=1");

        // Test 4: Equal inputs
        check_butterfly(12'd1234, 12'd1234, 12'd1, "TC4: Equal inputs");

        // Test 5: Subtraction wraparound (a < t)
        // a = 100, b = 1, zeta = 500 -> t = 500. b_out = (100 - 500) mod 3329 = 2929
        check_butterfly(12'd100, 12'd1, 12'd500, "TC5: Subtraction Wraparound");

        // Test 6: Addition wraparound (a + t >= Q)
        // a = 3000, b = 1, zeta = 500 -> t = 500. a_out = (3000 + 500) mod 3329 = 171
        check_butterfly(12'd3000, 12'd1, 12'd500, "TC6: Addition Wraparound");

        // Test 7: Maximum valid values (Q-1 = 3328)
        check_butterfly(12'd3328, 12'd3328, 12'd3328, "TC7: Maximum boundary values");

        // Test 8: Near Q boundaries
        check_butterfly(12'd3327, 12'd3328, 12'd1729, "TC8: Near Q boundary");

        // Test 9: Realistic ML-KEM values (zeta = 1729 from FIPS 203)
        check_butterfly(12'd123, 12'd456, 12'd1729, "TC9: ML-KEM twiddle 1729");
        check_butterfly(12'd1000, 12'd2000, 12'd2580, "TC10: ML-KEM twiddle 2580");

        // Test 11..110: 100 Random test cases with deterministic seed
        for (int i = 0; i < 100; i++) begin
            logic [WIDTH-1:0] rand_a;
            logic [WIDTH-1:0] rand_b;
            logic [WIDTH-1:0] rand_z;
            rand_a = $urandom_range(0, Q - 1);
            rand_b = $urandom_range(0, Q - 1);
            rand_z = $urandom_range(0, Q - 1);
            check_butterfly(rand_a, rand_b, rand_z, $sformatf("TC_RAND_%0d", i));
        end

        // Final Report
        $display("==================================================");
        $display("butterfly_tb Summary: Total Tests = %0d, Passed = %0d, Failed = %0d",
                 test_num, pass_count, error_count);
        $display("==================================================");

        if (error_count == 0) begin
            $display(">> BUTTERFLY TEST PASSED <<");
        end else begin
            $display(">> BUTTERFLY TEST FAILED <<");
            $fatal(1, "Butterfly verification encountered errors!");
        end

        $finish;
    end

endmodule
