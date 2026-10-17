@echo off
rem Fuehrt die DUnitX-Tests ohne geoeffnete IDE aus (#415).
rem Vorher Atlas.Tests fuer Win64 bauen (Projektgruppe Atlas.groupproj oder
rem pwsh Tools\Build-Test.ps1).
rem
rem   Tests\Tests.bat                    Funktionstests ohne Benchmarks
rem   Tests\Tests.bat benchmark          nur die Benchmarks (Kategorie Benchmark, #409)
rem   Tests\Tests.bat alle               Funktionstests und Benchmarks
rem   Tests\Tests.bat funktion Release   andere Konfiguration (Vorgabe Debug)
rem
rem Ergebnis als NUnit-XML in Output\Win64\<Konfiguration>\dunitx-<Art>.xml.
rem Exit-Code 0 = alles gruen, sonst der Exit-Code von Atlas.Tests.exe.
setlocal
set "ART=%~1"
if "%ART%"=="" set "ART=funktion"
set "KONFIG=%~2"
if "%KONFIG%"=="" set "KONFIG=Debug"
set "AUSGABE=%~dp0..\Output\Win64\%KONFIG%"
set "EXE=%AUSGABE%\Bin\Atlas.Tests.exe"
if not exist "%EXE%" (
  echo Atlas.Tests.exe fehlt: %EXE%
  echo Erst Atlas.Tests fuer Win64 in der Konfiguration %KONFIG% bauen.
  exit /b 3
)
set "FILTER="
if /i "%ART%"=="funktion" set "FILTER=--exclude:Benchmark"
if /i "%ART%"=="benchmark" set "FILTER=--include:Benchmark"
if /i not "%ART%"=="alle" if "%FILTER%"=="" (
  echo Unbekannte Art "%ART%": funktion, benchmark oder alle.
  exit /b 3
)
"%EXE%" %FILTER% --exitbehavior:Continue --xmlfile:"%AUSGABE%\dunitx-%ART%.xml"
exit /b %ERRORLEVEL%
