// ============================================================================
// File: tb/ntt/ntt_controller_tb.sv
// Testbench: ntt_controller_tb
// Author: Person 1 — NTT Architecture Engineer
// Project: Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM
//
// Description:
//   Self-checking verification testbench for ntt_controller.sv.
//   Verifies:
//     - Clean reset and idle state behavior
//     - Start assertion and busy flag behavior
//     - Exact progression through all 7 stages (0 to 6)
//     - Execution of all 896 butterflies without skip or duplication
//     - Exactness of all 896 (mem_addr_a, mem_addr_b, twiddle_addr) triplets
//     - 1-cycle done pulse upon completion and return to IDLE
// ============================================================================

`timescale 1ns / 1ps

module ntt_controller_tb;

    localparam int NUM_STAGES = 7;
    localparam int ADDR_WIDTH = 8;
    localparam time CLK_PERIOD = 10ns;

    logic                  clk;
    logic                  rst;
    logic                  start;
    logic                  busy;
    logic                  done;

    logic [ADDR_WIDTH-1:0] mem_addr_a;
    logic [ADDR_WIDTH-1:0] mem_addr_b;
    logic                  mem_we;
    logic [6:0]            twiddle_addr;

    logic                  bfly_valid_in;
    logic                  bfly_valid_out;

    logic [2:0]            stage_out;
    logic [6:0]            bfly_cnt_out;

    int error_count   = 0;
    int bfly_observed = 0;
    int cycle_count   = 0;

    // Golden model precalculated sequence of 896 triplets: (a, b, twiddle)
    typedef struct {
        int addr_a;
        int addr_b;
        int twiddle;
        int stage;
        int bfly_idx;
    } bfly_record_t;

    bfly_record_t golden_seq [896];

    // Instantiate DUT
    ntt_controller #(
        .NUM_STAGES(NUM_STAGES),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .busy          (busy),
        .done          (done),
        .mem_addr_a    (mem_addr_a),
        .mem_addr_b    (mem_addr_b),
        .mem_we        (mem_we),
        .twiddle_addr  (twiddle_addr),
        .bfly_valid_in (bfly_valid_in),
        .bfly_valid_out(bfly_valid_out),
        .stage_out     (stage_out),
        .bfly_cnt_out  (bfly_cnt_out)
    );

    // Clock Generation
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Butterfly response simulation (1-cycle registered latency)
    always_ff @(posedge clk) begin
        if (rst) begin
            bfly_valid_out <= 1'b0;
        end else begin
            bfly_valid_out <= bfly_valid_in;
        end
    end

    // Precalculate golden sequence using FIPS 203 algorithm
    initial begin
        int seq_idx = 0;
        int k_val   = 1;
        for (int s = 0; s < 7; s++) begin
            int len_val = 128 >> s;
            for (int start_val = 0; start_val < 256; start_val += 2 * len_val) begin
                int z_idx = k_val++;
                for (int j = start_val; j < start_val + len_val; j++) begin
                    golden_seq[seq_idx].addr_a    = j;
                    golden_seq[seq_idx].addr_b    = j + len_val;
                    golden_seq[seq_idx].twiddle   = z_idx;
                    golden_seq[seq_idx].stage     = s;
                    golden_seq[seq_idx].bfly_idx  = seq_idx % 128;
                    seq_idx++;
                end
            end
        end
    end

    // Main Test Sequence
    initial begin
        $display("==================================================");
        $display("Starting ntt_controller_tb verification...");
        $display("==================================================");

        // Reset
        rst   = 1'b1;
        start = 1'b0;
        repeat (3) @(posedge clk);
        rst   = 1'b0;
        @(posedge clk);

        // Verify IDLE state
        if (busy !== 1'b0 || done !== 1'b0) begin
            $display("[FAIL] Controller not in IDLE after reset! busy=%b, done=%b", busy, done);
            error_count++;
        end

        // Pulse start
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // Monitor execution and verify every butterfly during write state
        fork
            // Monitor process
            begin
                while (!done) begin
                    @(posedge clk);
                    cycle_count++;

                    // Whenever write enable is asserted, verify the completed butterfly
                    if (mem_we) begin
                        if (bfly_observed >= 896) begin
                            $display("[FAIL] More than 896 write operations observed!");
                            error_count++;
                        end else begin
                            bfly_record_t exp;
                            exp = golden_seq[bfly_observed];

                            if (mem_addr_a !== exp.addr_a ||
                                mem_addr_b !== exp.addr_b ||
                                twiddle_addr !== exp.twiddle ||
                                stage_out !== exp.stage ||
                                bfly_cnt_out !== exp.bfly_idx) begin
                                $display("[FAIL] Mismatch at butterfly %0d:", bfly_observed);
                                $display("       Expected: stage=%0d bfly=%0d addr_a=%0d addr_b=%0d twiddle=%0d",
                                         exp.stage, exp.bfly_idx, exp.addr_a, exp.addr_b, exp.twiddle);
                                $display("       Observed: stage=%0d bfly=%0d addr_a=%0d addr_b=%0d twiddle=%0d",
                                         stage_out, bfly_cnt_out, mem_addr_a, mem_addr_b, twiddle_addr);
                                error_count++;
                            end
                            bfly_observed++;
                        end
                    end
                end
            end

            // Timeout watchdog process (4000 cycles max)
            begin
                repeat (4000) @(posedge clk);
                if (!done) begin
                    $display("[FATAL] Controller execution timed out!");
                    error_count++;
                    $finish;
                end
            end
        join_any

        // Wait for done edge and check done pulse duration
        if (done !== 1'b1) begin
            @(posedge done);
        end
        $display("[INFO] Done pulse received at cycle %0d! Total butterflies verified = %0d",
                 cycle_count, bfly_observed);

        // Check done pulse is exactly 1 cycle
        @(posedge clk);
        #1;
        if (done !== 1'b0) begin
            $display("[FAIL] Done signal did not deassert after 1 cycle!");
            error_count++;
        end
        if (busy !== 1'b0) begin
            $display("[FAIL] Busy signal remained high after done!");
            error_count++;
        end

        // Check butterfly count
        if (bfly_observed !== 896) begin
            $display("[FAIL] Expected exactly 896 butterflies, but observed %0d!", bfly_observed);
            error_count++;
        end

        // Summary
        $display("==================================================");
        $display("ntt_controller_tb Summary: Butterflies = %0d/896, Errors = %0d",
                 bfly_observed, error_count);
        $display("==================================================");

        if (error_count == 0) begin
            $display(">> NTT CONTROLLER TEST PASSED <<");
        end else begin
            $display(">> NTT CONTROLLER TEST FAILED <<");
            $fatal(1, "Controller verification encountered errors!");
        end

        $finish;
    end

endmodule
