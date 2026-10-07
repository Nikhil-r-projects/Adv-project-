@echo off
REM ============================================================================
REM ML-KEM NTT Accelerator — Automated Hierarchical Simulation Script (Windows)
REM Runs all testbenches: Butterfly -> Memory -> Twiddle ROM -> Controller -> Core
REM ============================================================================

set VIVADO_BIN=C:\Xilinx\Vivado\2018.3\bin
set XVLOG=%VIVADO_BIN%\xvlog.bat
set XELAB=%VIVADO_BIN%\xelab.bat
set XSIM=%VIVADO_BIN%\xsim.bat

echo ============================================================================
echo   ML-KEM NTT ACCELERATOR — HIERARCHICAL VERIFICATION SUITE
echo ============================================================================

REM Step 1: Butterfly Testbench
echo.
echo [TEST 1/5] Compiling and Running butterfly_tb...
call %XVLOG% -sv rtl/ntt/butterfly.sv tb/stubs/mod_mul.sv tb/stubs/mod_add.sv tb/stubs/mod_sub.sv tb/ntt/butterfly_tb.sv > nul
if errorlevel 1 goto fail
call %XELAB% -debug typical butterfly_tb -s butterfly_sim > nul
if errorlevel 1 goto fail
call %XSIM% butterfly_sim -R
if errorlevel 1 goto fail

REM Step 2: Memory Testbench
echo.
echo [TEST 2/5] Compiling and Running memory_tb...
call %XVLOG% -sv rtl/ntt/ntt_memory.sv tb/ntt/memory_tb.sv > nul
if errorlevel 1 goto fail
call %XELAB% -debug typical memory_tb -s memory_sim > nul
if errorlevel 1 goto fail
call %XSIM% memory_sim -R
if errorlevel 1 goto fail

REM Step 3: Twiddle ROM Testbench
echo.
echo [TEST 3/5] Compiling and Running twiddle_rom_tb...
call %XVLOG% -sv rtl/ntt/twiddle_rom.sv tb/ntt/twiddle_rom_tb.sv > nul
if errorlevel 1 goto fail
call %XELAB% -debug typical twiddle_rom_tb -s twiddle_rom_sim > nul
if errorlevel 1 goto fail
call %XSIM% twiddle_rom_sim -R
if errorlevel 1 goto fail

REM Step 4: Controller Testbench
echo.
echo [TEST 4/5] Compiling and Running ntt_controller_tb...
call %XVLOG% -sv rtl/ntt/ntt_controller.sv tb/ntt/ntt_controller_tb.sv > nul
if errorlevel 1 goto fail
call %XELAB% -debug typical ntt_controller_tb -s controller_sim > nul
if errorlevel 1 goto fail
call %XSIM% controller_sim -R
if errorlevel 1 goto fail

REM Step 5: Full NTT Core Testbench
echo.
echo [TEST 5/5] Compiling and Running ntt_core_tb...
call %XVLOG% -sv rtl/ntt/butterfly.sv rtl/ntt/ntt_memory.sv rtl/ntt/twiddle_rom.sv rtl/ntt/ntt_controller.sv rtl/ntt/ntt_core.sv tb/stubs/mod_mul.sv tb/stubs/mod_add.sv tb/stubs/mod_sub.sv tb/ntt/ntt_core_tb.sv > nul
if errorlevel 1 goto fail
call %XELAB% -debug typical ntt_core_tb -s core_sim > nul
if errorlevel 1 goto fail
call %XSIM% core_sim -R
if errorlevel 1 goto fail

echo.
echo ============================================================================
echo   ALL 5 VERIFICATION SUITES PASSED SUCCESSFULLY!
echo   Waveform output available: ntt_core.vcd
echo ============================================================================
exit /b 0

:fail
echo.
echo [FATAL ERROR] Simulation failed during execution!
exit /b 1
