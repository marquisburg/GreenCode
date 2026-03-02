@echo off
REM Build GreenCode compiler (MethASM -> assembly -> exe)
REM Requires: MethASM compiler built (bin\methasm.exe), NASM, GCC

set METHASM=..\bin\methasm.exe
set NASM=nasm
set GCC=gcc

if not exist %METHASM% (
    echo Error: MethASM compiler not found at %METHASM%
    echo Run ..\build.bat first to build the MethASM compiler.
    exit /b 1
)

echo Compiling GreenCode compiler (MethASM -> assembly)...
%METHASM% compiler.masm -o compiler.s
if %ERRORLEVEL% NEQ 0 (
    echo MethASM compilation failed.
    exit /b 1
)

echo Assembling...
%NASM% -f win64 compiler.s -o compiler.o
if %ERRORLEVEL% NEQ 0 (
    echo NASM assembly failed.
    exit /b 1
)

echo Compiling masm_entry...
%GCC% -c ..\src\runtime\masm_entry.c -o masm_entry.o
if %ERRORLEVEL% NEQ 0 (
    echo masm_entry compilation failed.
    exit /b 1
)

echo Compiling GC runtime...
%GCC% -c ..\src\runtime\gc.c -o gc.o
if %ERRORLEVEL% NEQ 0 (
    echo GC compilation failed.
    exit /b 1
)

echo Linking...
%GCC% -nostartfiles compiler.o masm_entry.o gc.o -o greencode.exe -lkernel32 -lshell32
if %ERRORLEVEL% NEQ 0 (
    echo Linking failed.
    exit /b 1
)

echo Build successful! greencode.exe created.
echo.
echo Usage: greencode.exe input.gc [-o output.masm]
