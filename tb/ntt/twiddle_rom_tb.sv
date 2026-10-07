// ============================================================================
// File: tb/ntt/twiddle_rom_tb.sv
// Testbench: twiddle_rom_tb
// Author: Person 1 — NTT Architecture Engineer
// Project: Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM
//
// Description:
//   Self-checking verification testbench for twiddle_rom.sv.
//   Independently calculates expected twiddle constants using mathematical
//   definition: zetas[k] = 17^(BitRev_7(k)) mod 3329.
//   Compares all 128 ROM addresses, first/last boundary values, and random
//   lookups against the independently computed mathematical table.
// ============================================================================

`timescale 1ns / 1ps

module twiddle_rom_tb;

    localparam int WIDTH      = 12;
    localparam int DEPTH      = 128;
    localparam int ADDR_WIDTH = 7;
    localparam int Q          = 3329;
    localparam int ROOT       = 17;

    logic [ADDR_WIDTH-1:0] addr;
    logic [WIDTH-1:0]      zeta;

    int pass_count  = 0;
    int error_count = 0;

    // Instantiate DUT
    twiddle_rom #(
        .WIDTH     (WIDTH),
        .DEPTH     (DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .addr(addr),
        .zeta(zeta)
    );

    // Function to calculate 7-bit bit reversal
    function automatic int bitrev7(input int val);
        int rev = 0;
        for (int i = 0; i < 7; i++) begin
            rev = (rev << 1) | (val & 1);
            val = val >> 1;
        end
        return rev;
    endfunction

    // Function to calculate modular exponentiation: (base^exp) mod mod_val
    function automatic int mod_exp(input int base_val, input int exp_val, input int mod_val);
        longint res = 1;
        longint b   = base_val % mod_val;
        int e       = exp_val;
        while (e > 0) begin
            if (e & 1) begin
                res = (res * b) % mod_val;
            end
            b = (b * b) % mod_val;
            e = e >> 1;
        end
        return int'(res);
    endfunction

    // Function to compute expected zeta value from mathematical definition
    function automatic logic [WIDTH-1:0] get_expected_zeta(input int k);
        int exponent;
        int val;
        exponent = bitrev7(k);
        val      = mod_exp(ROOT, exponent, Q);
        return val[WIDTH-1:0];
    endfunction

    initial begin
        logic [WIDTH-1:0] expected_zeta;

        $display("==================================================");
        $display("Starting twiddle_rom_tb verification...");
        $display("==================================================");

        // --------------------------------------------------------------------
        // Test 1: Exhaustive check of all 128 ROM entries against mathematical model
        // --------------------------------------------------------------------
        $display("[INFO] TC1: Exhaustive verification of all 128 addresses...");
        for (int i = 0; i < DEPTH; i++) begin
            addr = i[ADDR_WIDTH-1:0];
            #1; // combinational propagation
            expected_zeta = get_expected_zeta(i);

            if (zeta !== expected_zeta) begin
                $display("[FAIL] Twiddle mismatch at addr %0d: Expected %0d, Got %0d",
                         i, expected_zeta, zeta);
                error_count++;
            end else begin
                pass_count++;
            end
        end

        // --------------------------------------------------------------------
        // Test 2: Boundary check for first and last constants
        // --------------------------------------------------------------------
        $display("[INFO] TC2: Verifying first constant (addr 0 and 1) and last constant (addr 127)...");
        addr = 7'd0; #1;
        if (zeta !== 12'd1) begin
            $display("[FAIL] Addr 0 expected 1, got %0d", zeta);
            error_count++;
        end else pass_count++;

        addr = 7'd1; #1;
        if (zeta !== 12'd1729) begin
            $display("[FAIL] Addr 1 expected 1729, got %0d", zeta);
            error_count++;
        end else pass_count++;

        addr = 7'd127; #1;
        if (zeta !== 12'd2154) begin
            $display("[FAIL] Addr 127 expected 2154, got %0d", zeta);
            error_count++;
        end else pass_count++;

        // --------------------------------------------------------------------
        // Test 3: Random access verification
        // --------------------------------------------------------------------
        $display("[INFO] TC3: 100 Random address lookups...");
        for (int k = 0; k < 100; k++) begin
            int rand_addr = $urandom_range(0, DEPTH - 1);
            addr = rand_addr[ADDR_WIDTH-1:0];
            #1;
            expected_zeta = get_expected_zeta(rand_addr);

            if (zeta !== expected_zeta) begin
                $display("[FAIL] Random lookup mismatch at %0d: Expected %0d, Got %0d",
                         rand_addr, expected_zeta, zeta);
                error_count++;
            end else begin
                pass_count++;
            end
        end

        // Summary
        $display("==================================================");
        $display("twiddle_rom_tb Summary: Total Checks = %0d, Passed = %0d, Failed = %0d",
                 pass_count + error_count, pass_count, error_count);
        $display("==================================================");

        if (error_count == 0) begin
            $display(">> TWIDDLE ROM TEST PASSED <<");
        end else begin
            $display(">> TWIDDLE ROM TEST FAILED <<");
            $fatal(1, "Twiddle ROM verification encountered errors!");
        end

        $finish;
    end

endmodule
