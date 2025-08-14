@echo off
REM === Go to your project folder ===
cd /d "C:\Users\golan\Desktop\חיפוש עבודה\Projects\verilog-cache-project"

echo.
echo [1/3] Compiling...
iverilog -g2012 -o sim.vvp src\cpu_translator.sv testbench\core_translator_tb.sv
if errorlevel 1 (echo **ERROR**: compile failed & pause & exit /b 1)

echo.
echo [2/3] Running simulation...
vvp sim.vvp
if errorlevel 1 (echo **ERROR**: simulation failed & pause & exit /b 1)

echo.
echo [3/3] Opening GTKWave...
if exist cpu_translator_min.gtkw (
    gtkwave waves.vcd cpu_translator_min.gtkw
) else (
    echo **WARNING**: Layout file not found, opening VCD only...
    gtkwave waves.vcd
)

echo.
pause
