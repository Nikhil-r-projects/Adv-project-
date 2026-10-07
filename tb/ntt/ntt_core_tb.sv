// ============================================================================
// File: tb/ntt/ntt_core_tb.sv
// Testbench: ntt_core_tb
// Author: Person 1 — NTT Architecture Engineer
// Project: Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM
//
// Description:
//   Self-checking verification testbench for ntt_core.sv.
//   Verifies the complete 256-point ML-KEM NTT accelerator against NIST FIPS 203
//   golden reference test vectors:
//     - Test 1: All-zero vector
//     - Test 2: Single impulse at index 0
//     - Test 3: Single impulse at index 128
//     - Test 4: Linear ramp vector
//     - Test 5: Alternating maximum boundary vector
//     - Tests 6..15: 10 Pseudorandom vectors (seed = 12345)
//
// Features:
//   - Cycle-accurate latency measurement (start -> done)
//   - Coefficient-by-coefficient error diagnosis with exact mismatch indices
//   - Protocol assertions (busy duration, 1-cycle done pulse, coefficients < Q)
//   - Waveform dump to VCD for inspection in GTKWave / Vivado
// ============================================================================

`timescale 1ns / 1ps

module ntt_core_tb;

    localparam int Q          = 3329;
    localparam int WIDTH      = 12;
    localparam int N          = 256;
    localparam int NUM_STAGES = 7;
    localparam time CLK_PERIOD = 10ns;

    // Signals
    logic             clk;
    logic             rst;

    logic             start;
    logic             busy;
    logic             done;

    logic             load_valid;
    logic [7:0]       load_addr;
    logic [WIDTH-1:0] load_data;
    logic             load_ready;

    logic [7:0]       read_addr;
    logic [WIDTH-1:0] read_data;

    // Test tracking
    int vector_pass_count  = 0;
    int vector_fail_count  = 0;
    int total_latency_measured = 0;

    // Storage for vector files
    logic [WIDTH-1:0] input_vec    [N-1:0];
    logic [WIDTH-1:0] expected_vec [N-1:0];
    logic [WIDTH-1:0] actual_vec   [N-1:0];

    // Instantiate DUT
    ntt_core #(
        .Q         (Q),
        .WIDTH     (WIDTH),
        .N         (N),
        .NUM_STAGES(NUM_STAGES)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .busy      (busy),
        .done      (done),
        .load_valid(load_valid),
        .load_addr (load_addr),
        .load_data (load_data),
        .load_ready(load_ready),
        .read_addr (read_addr),
        .read_data (read_data)
    );

    // Clock Generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Waveform Dump
    initial begin
        $dumpfile("ntt_core.vcd");
        $dumpvars(0, ntt_core_tb);
    end

    // Task to run one test vector
    task automatic run_test_vector(
        input string in_filename,
        input string exp_filename,
        input string test_desc
    );
        int cycle_timer;
        int mismatch_count;
        int first_mismatch_idx;

        $display("--------------------------------------------------");
        $display("[RUNNING] %s", test_desc);
        $display("          Input: %s", in_filename);
        $display("          Expected: %s", exp_filename);

        // Load files from disk
        $readmemh(in_filename, input_vec);
        $readmemh(exp_filename, expected_vec);

        // Wait until load_ready
        while (!load_ready) @(posedge clk);

        // 1. Stream 256 coefficients into memory
        for (int i = 0; i < N; i++) begin
            @(posedge clk);
            load_valid <= 1'b1;
            load_addr  <= 8'(i);
            load_data  <= input_vec[i];
        end

        // Deassert load_valid
        @(posedge clk);
        load_valid <= 1'b0;
        load_addr  <= '0;
        load_data  <= '0;

        // 2. Trigger NTT Execution
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // Verify busy asserted
        #1;
        if (!busy) begin
            $display("[ERROR] Core did not assert 'busy' upon start!");
        end

        // 3. Measure latency until done
        cycle_timer = 0;
        while (!done) begin
            @(posedge clk);
            cycle_timer++;
            if (cycle_timer > 10000) begin
                $display("[FATAL] Watchdog timeout waiting for done pulse!");
                $finish;
            end
        end

        total_latency_measured = cycle_timer;
        $display("[INFO] Done asserted! Execution latency = %0d clock cycles (%0.2f us @ 100MHz)",
                 cycle_timer, (cycle_timer * 10.0) / 1000.0);

        // Verify done is a 1-cycle pulse
        @(posedge clk);
        #1;
        if (done !== 1'b0) begin
            $display("[ERROR] 'done' signal was not a 1-cycle pulse!");
        end
        if (busy !== 1'b0) begin
            $display("[ERROR] 'busy' signal did not deassert after done!");
        end

        // 4. Read out all 256 coefficients and compare against expected
        mismatch_count = 0;
        first_mismatch_idx = -1;

        for (int j = 0; j < N; j++) begin
            @(posedge clk);
            read_addr <= 8'(j);
            @(posedge clk); // synchronous read latency
            #1;
            actual_vec[j] = read_data;

            // Range assertion: coefficient must be strictly < Q
            if (read_data >= Q) begin
                $display("[ERROR] Out-of-range coefficient at [%0d]: %0d >= Q (%0d)", j, read_data, Q);
                mismatch_count++;
            end

            if (read_data !== expected_vec[j]) begin
                if (mismatch_count < 5) begin
                    $display("       Mismatch at index [%0d]: Expected 0x%03X (%0d), Got 0x%03X (%0d)",
                             j, expected_vec[j], expected_vec[j], read_data, read_data);
                end
                if (first_mismatch_idx == -1) first_mismatch_idx = j;
                mismatch_count++;
            end
        end

        // Evaluate Vector Result
        if (mismatch_count == 0) begin
            $display("[PASS] %s — All 256 coefficients matched golden reference!", test_desc);
            vector_pass_count++;
        end else begin
            $display("[FAIL] %s — %0d / 256 mismatches! First mismatch at index [%0d]",
                     test_desc, mismatch_count, first_mismatch_idx);
            vector_fail_count++;
        end
    endtask

    // Main Test Sequence
    initial begin
        $display("==================================================");
        $display("Starting ntt_core_tb Full System Verification...");
        $display("==================================================");

        // Reset Sequence
        rst        = 1'b1;
        start      = 1'b0;
        load_valid = 1'b0;
        load_addr  = '0;
        load_data  = '0;
        read_addr  = '0;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // Run Test Vectors 0..14
        run_test_vector("vectors/vec_000_all_zeros_in.hex",
                        "vectors/vec_000_all_zeros_exp.hex",
                        "Vector 0: All Zeros");

        run_test_vector("vectors/vec_001_impulse_0_in.hex",
                        "vectors/vec_001_impulse_0_exp.hex",
                        "Vector 1: Impulse at Index 0");

        run_test_vector("vectors/vec_002_impulse_128_in.hex",
                        "vectors/vec_002_impulse_128_exp.hex",
                        "Vector 2: Impulse at Index 128");

        run_test_vector("vectors/vec_003_linear_ramp_in.hex",
                        "vectors/vec_003_linear_ramp_exp.hex",
                        "Vector 3: Deterministic Linear Ramp");

        run_test_vector("vectors/vec_004_alternating_max_in.hex",
                        "vectors/vec_004_alternating_max_exp.hex",
                        "Vector 4: Alternating Maximum Boundary");

        // 10 Random Vectors
        run_test_vector("vectors/vec_005_random_in.hex",
                        "vectors/vec_005_random_exp.hex",
                        "Vector 5: Pseudorandom Vector 1 (seed=12345)");

        run_test_vector("vectors/vec_006_random_in.hex",
                        "vectors/vec_006_random_exp.hex",
                        "Vector 6: Pseudorandom Vector 2");

        run_test_vector("vectors/vec_007_random_in.hex",
                        "vectors/vec_007_random_exp.hex",
                        "Vector 7: Pseudorandom Vector 3");

        run_test_vector("vectors/vec_008_random_in.hex",
                        "vectors/vec_008_random_exp.hex",
                        "Vector 8: Pseudorandom Vector 4");

        run_test_vector("vectors/vec_009_random_in.hex",
                        "vectors/vec_009_random_exp.hex",
                        "Vector 9: Pseudorandom Vector 5");

        run_test_vector("vectors/vec_010_random_in.hex",
                        "vectors/vec_010_random_exp.hex",
                        "Vector 10: Pseudorandom Vector 6");

        run_test_vector("vectors/vec_011_random_in.hex",
                        "vectors/vec_011_random_exp.hex",
                        "Vector 11: Pseudorandom Vector 7");

        run_test_vector("vectors/vec_012_random_in.hex",
                        "vectors/vec_012_random_exp.hex",
                        "Vector 12: Pseudorandom Vector 8");

        run_test_vector("vectors/vec_013_random_in.hex",
                        "vectors/vec_013_random_exp.hex",
                        "Vector 13: Pseudorandom Vector 9");

        run_test_vector("vectors/vec_014_random_in.hex",
                        "vectors/vec_014_random_exp.hex",
                        "Vector 14: Pseudorandom Vector 10");

        // Final Summary
        $display("==================================================");
        $display("ntt_core_tb Final Summary:");
        $display("  Total Vectors Tested: %0d", vector_pass_count + vector_fail_count);
        $display("  Passed:               %0d", vector_pass_count);
        $display("  Failed:               %0d", vector_fail_count);
        $display("  Measured NTT Latency: %0d clock cycles", total_latency_measured);
        $display("==================================================");

        if (vector_fail_count == 0) begin
            $display(">> FULL 256-POINT ML-KEM NTT TEST PASSED <<");
        end else begin
            $display(">> FULL 256-POINT ML-KEM NTT TEST FAILED <<");
            $fatal(1, "Full NTT verification encountered errors!");
        end

        $finish;
    end

endmodule
