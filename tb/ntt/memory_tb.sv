// ============================================================================
// File: tb/ntt/memory_tb.sv
// Testbench: memory_tb
// Author: Person 1 — NTT Architecture Engineer
// Project: Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM
//
// Description:
//   Self-checking verification testbench for ntt_memory.sv.
//   Verifies:
//     - Simultaneous dual-port writes (Port A + Port B)
//     - Simultaneous dual-port reads (Port A + Port B)
//     - Boundary addresses (0, 255)
//     - Exhaustive coverage of all 256 memory locations
//     - Random address access patterns
// ============================================================================

`timescale 1ns / 1ps

module memory_tb;

    localparam int WIDTH      = 12;
    localparam int DEPTH      = 256;
    localparam int ADDR_WIDTH = 8;
    localparam time CLK_PERIOD = 10ns;

    logic                  clk;

    // Port A
    logic                  we_a;
    logic [ADDR_WIDTH-1:0] addr_a;
    logic [WIDTH-1:0]      wdata_a;
    logic [WIDTH-1:0]      rdata_a;

    // Port B
    logic                  we_b;
    logic [ADDR_WIDTH-1:0] addr_b;
    logic [WIDTH-1:0]      wdata_b;
    logic [WIDTH-1:0]      rdata_b;

    // Golden memory array for self-checking
    logic [WIDTH-1:0] shadow_mem [DEPTH-1:0];

    int pass_count  = 0;
    int error_count = 0;

    // Instantiate DUT
    ntt_memory #(
        .WIDTH     (WIDTH),
        .DEPTH     (DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk    (clk),
        .we_a   (we_a),
        .addr_a (addr_a),
        .wdata_a(wdata_a),
        .rdata_a(rdata_a),
        .we_b   (we_b),
        .addr_b (addr_b),
        .wdata_b(wdata_b),
        .rdata_b(rdata_b)
    );

    // Clock generator
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Test sequence
    initial begin
        $display("==================================================");
        $display("Starting memory_tb verification...");
        $display("==================================================");

        // Initialize signals
        we_a    = 1'b0;
        addr_a  = '0;
        wdata_a = '0;
        we_b    = 1'b0;
        addr_b  = '0;
        wdata_b = '0;
        for (int i = 0; i < DEPTH; i++) begin
            shadow_mem[i] = '0;
        end

        repeat (3) @(posedge clk);

        // --------------------------------------------------------------------
        // Test 1: Exhaustive Write of all 256 locations using dual ports
        // --------------------------------------------------------------------
        $display("[INFO] TC1: Writing all 256 locations across Port A and Port B...");
        for (int i = 0; i < 128; i++) begin
            @(posedge clk);
            we_a    <= 1'b1;
            addr_a  <= i;
            wdata_a <= 12'(1000 + i);
            shadow_mem[i] = 12'(1000 + i);

            we_b    <= 1'b1;
            addr_b  <= i + 128;
            wdata_b <= 12'(2000 + i);
            shadow_mem[i + 128] = 12'(2000 + i);
        end

        // Turn off write enables
        @(posedge clk);
        we_a <= 1'b0;
        we_b <= 1'b0;

        // --------------------------------------------------------------------
        // Test 2: Read back all 256 locations and check against shadow memory
        // --------------------------------------------------------------------
        $display("[INFO] TC2: Reading and verifying all 256 locations...");
        for (int i = 0; i < 128; i++) begin
            @(posedge clk);
            addr_a <= i;
            addr_b <= i + 128;

            // Wait 1 cycle for synchronous read latency
            @(posedge clk);
            #1; // sampling delta
            if (rdata_a !== shadow_mem[i]) begin
                $display("[FAIL] Read mismatch Port A at addr %0d: Expected %0d, Got %0d",
                         i, shadow_mem[i], rdata_a);
                error_count++;
            end else begin
                pass_count++;
            end

            if (rdata_b !== shadow_mem[i + 128]) begin
                $display("[FAIL] Read mismatch Port B at addr %0d: Expected %0d, Got %0d",
                         i + 128, shadow_mem[i + 128], rdata_b);
                error_count++;
            end else begin
                pass_count++;
            end
        end

        // --------------------------------------------------------------------
        // Test 3: Boundary addresses (0 and 255) simultaneous read/write
        // --------------------------------------------------------------------
        $display("[INFO] TC3: Boundary testing addr 0 and addr 255...");
        @(posedge clk);
        we_a    <= 1'b1;
        addr_a  <= 8'd0;
        wdata_a <= 12'hAAA;
        shadow_mem[0] = 12'hAAA;

        we_b    <= 1'b1;
        addr_b  <= 8'd255;
        wdata_b <= 12'h555;
        shadow_mem[255] = 12'h555;

        @(posedge clk);
        we_a <= 1'b0;
        we_b <= 1'b0;
        addr_a <= 8'd0;
        addr_b <= 8'd255;

        @(posedge clk);
        #1;
        if (rdata_a !== 12'hAAA) begin
            $display("[FAIL] Addr 0 mismatch: Expected 0xAAA, Got 0x%0h", rdata_a);
            error_count++;
        end else begin
            pass_count++;
        end

        if (rdata_b !== 12'h555) begin
            $display("[FAIL] Addr 255 mismatch: Expected 0x555, Got 0x%0h", rdata_b);
            error_count++;
        end else begin
            pass_count++;
        end

        // --------------------------------------------------------------------
        // Test 4: Random read/write operations
        // --------------------------------------------------------------------
        $display("[INFO] TC4: 100 Random read/write cycles...");
        for (int k = 0; k < 100; k++) begin
            logic [ADDR_WIDTH-1:0] rand_addr_a;
            logic [ADDR_WIDTH-1:0] rand_addr_b;
            logic [WIDTH-1:0]      rand_val_a;
            logic [WIDTH-1:0]      rand_val_b;

            rand_addr_a = $urandom_range(0, 127);
            rand_addr_b = $urandom_range(128, 255);
            rand_val_a  = $urandom_range(0, 3328);
            rand_val_b  = $urandom_range(0, 3328);

            // Write
            @(posedge clk);
            we_a    <= 1'b1;
            addr_a  <= rand_addr_a;
            wdata_a <= rand_val_a;
            shadow_mem[rand_addr_a] = rand_val_a;

            we_b    <= 1'b1;
            addr_b  <= rand_addr_b;
            wdata_b <= rand_val_b;
            shadow_mem[rand_addr_b] = rand_val_b;

            // Read
            @(posedge clk);
            we_a   <= 1'b0;
            we_b   <= 1'b0;
            addr_a <= rand_addr_a;
            addr_b <= rand_addr_b;

            @(posedge clk);
            #1;
            if (rdata_a !== shadow_mem[rand_addr_a]) begin
                $display("[FAIL] Random Port A mismatch at %0d: Expected %0d, Got %0d",
                         rand_addr_a, shadow_mem[rand_addr_a], rdata_a);
                error_count++;
            end else begin
                pass_count++;
            end

            if (rdata_b !== shadow_mem[rand_addr_b]) begin
                $display("[FAIL] Random Port B mismatch at %0d: Expected %0d, Got %0d",
                         rand_addr_b, shadow_mem[rand_addr_b], rdata_b);
                error_count++;
            end else begin
                pass_count++;
            end
        end

        // Summary
        $display("==================================================");
        $display("memory_tb Summary: Passed = %0d, Failed = %0d", pass_count, error_count);
        $display("==================================================");

        if (error_count == 0) begin
            $display(">> MEMORY TEST PASSED <<");
        end else begin
            $display(">> MEMORY TEST FAILED <<");
            $fatal(1, "Memory verification encountered errors!");
        end

        $finish;
    end

endmodule
