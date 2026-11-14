@echo off
rem Builds the Axon Tutorial, doc\tutorial\axon-tutorial.pdf.
rem
rem 1. Runs tools\gen_tutorial.py, which checks that the code in the tutorial's
rem    help pages (help\tutorial*.md) runs as shown, with Win64\Release\axon.exe
rem    (build it first: build.cmd Release), and writes doc\tutorial\lessons.
rem 2. Runs latexmk (MiKTeX or TeX Live) to make the PDF.
rem
rem Works from any current directory.

setlocal EnableDelayedExpansion
set "ROOT=%~dp0.."
set "TUTORIAL=%ROOT%\doc\tutorial"

python "%ROOT%\tools\gen_tutorial.py"
if errorlevel 1 (
  echo build_tutorial: fix the lessons first.
  exit /b 1
)

rem latexmk needs Perl; without it, three pdflatex runs settle the contents
rem and cross-references.
pushd "%TUTORIAL%"
set "RESULT=0"
where perl > nul 2> nul
if not errorlevel 1 (
  latexmk -pdf -interaction=nonstopmode -halt-on-error axon-tutorial.tex
  if errorlevel 1 set "RESULT=1"
) else (
  for /l %%N in (1,1,3) do (
    if "!RESULT!"=="0" (
      pdflatex -interaction=nonstopmode -halt-on-error axon-tutorial.tex > nul
      if errorlevel 1 set "RESULT=1"
    )
  )
)
popd
if not "%RESULT%"=="0" (
  echo build_tutorial: LaTeX failed; see doc\tutorial\axon-tutorial.log.
  exit /b 1
)
echo Built doc\tutorial\axon-tutorial.pdf
endlocal
