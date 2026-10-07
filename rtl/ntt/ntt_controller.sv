// ============================================================================
// File: rtl/ntt/ntt_controller.sv
// Module: ntt_controller
// Author: Person 1 — NTT Architecture Engineer
// Project: Configurable FPGA-Based NTT Accelerator for Post-Quantum ML-KEM
//
// Description:
//   FSM and address-generation engine for the 256-point ML-KEM NTT.
//   Orchestrates memory reads, butterfly computation, memory writes,
//   butterfly indexing, and stage transitions across 7 stages (896 operations).
//
// Address Generation Algorithm (Cooley-Tukey FIPS 203 Section 4.3):
//   At stage s (s in 0..6):
//     len          = 128 >> s
//     block_idx    = bfly_cnt >> (7 - s)
//     offset       = bfly_cnt & (len - 1)
//     start_idx    = block_idx << (8 - s)
//     mem_addr_a   = start_idx + offset
//     mem_addr_b   = mem_addr_a + len
//     twiddle_addr = (1 << s) + block_idx
//
// FSM States:
//   - STATE_IDLE:  Wait for start signal.
//   - STATE_READ:  Present addresses to TDP RAM and twiddle ROM (1 cycle read).
//   - STATE_CALC:  Assert bfly_valid_in, wait for bfly_valid_out.
//   - STATE_WRITE: Assert mem_we to write updated pair back to memory; advance counters.
//   - STATE_DONE:  Pulse done for 1 cycle, return to IDLE.
// ============================================================================

`timescale 1ns / 1ps

module ntt_controller #(
    parameter int NUM_STAGES = 7,
    parameter int ADDR_WIDTH = 8
)(
    input  logic                  clk,
    input  logic                  rst,

    // Control Handshake
    input  logic                  start,
    output logic                  busy,
    output logic                  done,

    // Memory Addressing & Control
    output logic [ADDR_WIDTH-1:0] mem_addr_a,
    output logic [ADDR_WIDTH-1:0] mem_addr_b,
    output logic                  mem_we,

    // Twiddle ROM Addressing
    output logic [6:0]            twiddle_addr,

    // Butterfly Datapath Handshake
    output logic                  bfly_valid_in,
    input  logic                  bfly_valid_out,

    // Status / Telemetry
    output logic [2:0]            stage_out,
    output logic [6:0]            bfly_cnt_out
);

    // ------------------------------------------------------------------------
    // FSM State Encoding
    // ------------------------------------------------------------------------
    typedef enum logic [2:0] {
        STATE_IDLE  = 3'd0,
        STATE_READ  = 3'd1,
        STATE_CALC  = 3'd2,
        STATE_WRITE = 3'd3,
        STATE_DONE  = 3'd4
    } state_t;

    state_t state_q, state_d;

    // Counters
    logic [2:0] stage_q, stage_d;
    logic [6:0] bfly_q,  bfly_d;

    assign stage_out    = stage_q;
    assign bfly_cnt_out = bfly_q;

    // ------------------------------------------------------------------------
    // Combinational Address Generation Logic
    // ------------------------------------------------------------------------
    logic [7:0] len_val;
    logic [6:0] block_idx;
    logic [7:0] offset_val;
    logic [7:0] start_idx;

    always_comb begin
        len_val      = 8'd128 >> stage_q;
        block_idx    = bfly_q >> (7 - stage_q);
        offset_val   = {1'b0, bfly_q} & (len_val - 8'd1);
        start_idx    = block_idx << (8 - stage_q);

        mem_addr_a   = start_idx | offset_val;
        mem_addr_b   = mem_addr_a + len_val;
        twiddle_addr = (7'd1 << stage_q) | block_idx;
    end

    // ------------------------------------------------------------------------
    // FSM Combinational Next-State and Output Logic
    // ------------------------------------------------------------------------
    always_comb begin
        state_d       = state_q;
        stage_d       = stage_q;
        bfly_d        = bfly_q;
        busy          = 1'b1;
        done          = 1'b0;
        mem_we        = 1'b0;
        bfly_valid_in = 1'b0;

        case (state_q)
            STATE_IDLE: begin
                busy = 1'b0;
                if (start) begin
                    busy    = 1'b1;
                    stage_d = 3'd0;
                    bfly_d  = 7'd0;
                    state_d = STATE_READ;
                end
            end

            STATE_READ: begin
                // 1 clock cycle to present read addresses to synchronous TDP RAM
                state_d = STATE_CALC;
            end

            STATE_CALC: begin
                // Trigger butterfly computation with valid memory read data
                bfly_valid_in = 1'b1;
                if (bfly_valid_out) begin
                    state_d = STATE_WRITE;
                end
            end

            STATE_WRITE: begin
                // Assert write enable for 1 cycle to store a_out, b_out
                mem_we = 1'b1;

                // Advance butterfly / stage counters
                if (bfly_q == 7'd127) begin
                    bfly_d = 7'd0;
                    if (stage_q == (NUM_STAGES - 1)) begin
                        state_d = STATE_DONE;
                    end else begin
                        stage_d = stage_q + 1'b1;
                        state_d = STATE_READ;
                    end
                end else begin
                    bfly_d  = bfly_q + 1'b1;
                    state_d = STATE_READ;
                end
            end

            STATE_DONE: begin
                busy    = 1'b0;
                done    = 1'b1; // 1-cycle completion pulse
                state_d = STATE_IDLE;
            end

            default: state_d = STATE_IDLE;
        endcase
    end

    // ------------------------------------------------------------------------
    // Sequential State Register
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state_q <= STATE_IDLE;
            stage_q <= 3'd0;
            bfly_q  <= 7'd0;
        end else begin
            state_q <= state_d;
            stage_q <= stage_d;
            bfly_q  <= bfly_d;
        end
    end

endmodule
