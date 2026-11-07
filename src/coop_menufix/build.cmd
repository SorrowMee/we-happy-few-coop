@echo off
rem Builds CoopMenuFix (UE4SS C++ mod loaded as Mods\CoopMenuFix\dlls\main.dll) with MSVC x64.
rem MinHook 1.3.4 (third_party, BSD-2-Clause) is compiled in. Output: mod\Mods\CoopMenuFix\dlls\main.dll
setlocal
where cl >nul 2>nul
if not errorlevel 1 goto build
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto novs
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if not defined VSDIR goto novs
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1

:build
set "HERE=%~dp0"
set "MH=%HERE%..\..\third_party\minhook-1.3.4"
set "OUT=%HERE%..\..\mod\Mods\CoopMenuFix\dlls"
set "OBJ=%HERE%obj"
if not exist "%OUT%" mkdir "%OUT%"
if not exist "%OBJ%" mkdir "%OBJ%"
cl /nologo /O2 /W4 /MT /LD /I"%MH%\include" ^
  "%HERE%coop_menufix.c" "%MH%\src\buffer.c" "%MH%\src\hook.c" "%MH%\src\trampoline.c" "%MH%\src\hde\hde64.c" ^
  /Fo"%OBJ%\\" /Fe"%OUT%\main.dll" /link /NOLOGO || exit /b 1
echo built %OUT%\main.dll
exit /b 0

:novs
echo MSVC not found: install Visual Studio 2022 Build Tools with the "Desktop development with C++" workload.
exit /b 1
