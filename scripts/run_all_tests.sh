#!/usr/bin/env bash
# ============================================================================
# ML-KEM NTT Accelerator — Automated Hierarchical Simulation Script (Linux/Bash)
# Runs all testbenches: Butterfly -> Memory -> Twiddle ROM -> Controller -> Core
# ============================================================================

set -e

XVLOG="xvlog"
XELAB="xelab"
XSIM="xsim"

echo "============================================================================"
echo "  ML-KEM NTT ACCELERATOR — HIERARCHICAL VERIFICATION SUITE"
echo "============================================================================"

# Step 1: Butterfly Testbench
echo ""
echo "[TEST 1/5] Compiling and Running butterfly_tb..."
$XVLOG -sv rtl/ntt/butterfly.sv tb/stubs/mod_mul.sv tb/stubs/mod_add.sv tb/stubs/mod_sub.sv tb/ntt/butterfly_tb.sv
$XELAB -debug typical butterfly_tb -s butterfly_sim
$XSIM butterfly_sim -R

# Step 2: Memory Testbench
echo ""
echo "[TEST 2/5] Compiling and Running memory_tb..."
$XVLOG -sv rtl/ntt/ntt_memory.sv tb/ntt/memory_tb.sv
$XELAB -debug typical memory_tb -s memory_sim
$XSIM memory_sim -R

# Step 3: Twiddle ROM Testbench
echo ""
echo "[TEST 3/5] Compiling and Running twiddle_rom_tb..."
$XVLOG -sv rtl/ntt/twiddle_rom.sv tb/ntt/twiddle_rom_tb.sv
$XELAB -debug typical twiddle_rom_tb -s twiddle_rom_sim
$XSIM twiddle_rom_sim -R

# Step 4: Controller Testbench
echo ""
echo "[TEST 4/5] Compiling and Running ntt_controller_tb..."
$XVLOG -sv rtl/ntt/ntt_controller.sv tb/ntt/ntt_controller_tb.sv
$XELAB -debug typical ntt_controller_tb -s controller_sim
$XSIM controller_sim -R

# Step 5: Full NTT Core Testbench
echo ""
echo "[TEST 5/5] Compiling and Running ntt_core_tb..."
$XVLOG -sv rtl/ntt/butterfly.sv rtl/ntt/ntt_memory.sv rtl/ntt/twiddle_rom.sv rtl/ntt/ntt_controller.sv rtl/ntt/ntt_core.sv tb/stubs/mod_mul.sv tb/stubs/mod_add.sv tb/stubs/mod_sub.sv tb/ntt/ntt_core_tb.sv
$XELAB -debug typical ntt_core_tb -s core_sim
$XSIM core_sim -R

echo ""
echo "============================================================================"
echo "  ALL 5 VERIFICATION SUITES PASSED SUCCESSFULLY!"
echo "  Waveform output available: ntt_core.vcd"
echo "============================================================================"
