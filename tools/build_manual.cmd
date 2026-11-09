@echo off
rem Builds the Axon User Manual, doc\manual\axon-manual.pdf.
rem
rem 1. Runs every script in doc\manual\examples with Win64\Release\axon.exe
rem    (build it first: build.cmd Release). The plotting examples write their
rem    figures into doc\manual\figures. AXON_SHOW_DIR keeps any figure a script
rem    shows out of the image viewer.
rem 2. Runs latexmk (MiKTeX or TeX Live) to make the PDF.
rem
rem Works from any current directory.

setlocal EnableDelayedExpansion
set "ROOT=%~dp0.."
set "MANUAL=%ROOT%\doc\manual"
set "AXON=%ROOT%\Win64\Release\axon.exe"

if not exist "%AXON%" (
  echo build_manual: %AXON% not found; run build.cmd Release first.
  exit /b 1
)

if not exist "%MANUAL%\figures" mkdir "%MANUAL%\figures"
set "AXON_SHOW_DIR=%TEMP%\axon-manual-figures"
if not exist "%AXON_SHOW_DIR%" mkdir "%AXON_SHOW_DIR%"

pushd "%MANUAL%\examples"
for %%F in (*.sci) do (
  echo Running %%F
  "%AXON%" "%%F" > nul
  if errorlevel 1 (
    echo build_manual: %%F failed.
    popd
    exit /b 1
  )
)
popd
rmdir /s /q "%AXON_SHOW_DIR%" 2> nul

rem latexmk needs Perl; without it, three pdflatex runs settle the contents
rem and cross-references.
pushd "%MANUAL%"
set "RESULT=0"
where perl > nul 2> nul
if not errorlevel 1 (
  latexmk -pdf -interaction=nonstopmode -halt-on-error axon-manual.tex
  if errorlevel 1 set "RESULT=1"
) else (
  for /l %%N in (1,1,3) do (
    if "!RESULT!"=="0" (
      pdflatex -interaction=nonstopmode -halt-on-error axon-manual.tex > nul
      if errorlevel 1 set "RESULT=1"
    )
  )
)
popd
if not "%RESULT%"=="0" (
  echo build_manual: LaTeX failed; see doc\manual\axon-manual.log.
  exit /b 1
)
echo Built doc\manual\axon-manual.pdf
endlocal
