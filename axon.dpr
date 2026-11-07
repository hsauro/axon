program axon;

{ Axon interpreter entry point. All work happens in Axon.Cli. }

{$APPTYPE CONSOLE}

// The tree-walking evaluator recurses on the native stack for every Axon
// call, so reserve room for MaxCallDepth (10,000) nested calls. This reserves
// address space only; memory is committed as the stack grows.
{$MAXSTACKSIZE $10000000}

uses
  Axon.Version in 'src\Axon.Version.pas',
  Axon.Errors in 'src\Axon.Errors.pas',
  Axon.Platform in 'src\Axon.Platform.pas',
  Axon.Source in 'src\Axon.Source.pas',
  Axon.Tokens in 'src\Axon.Tokens.pas',
  Axon.Lexer in 'src\Axon.Lexer.pas',
  Axon.Ast in 'src\Axon.Ast.pas',
  Axon.Parser in 'src\Axon.Parser.pas',
  Axon.AstDump in 'src\Axon.AstDump.pas',
  Axon.Complex in 'src\Axon.Complex.pas',
  Axon.Values in 'src\Axon.Values.pas',
  Axon.Ops in 'src\Axon.Ops.pas',
  Axon.Builtins in 'src\Axon.Builtins.pas',
  Axon.Interp in 'src\Axon.Interp.pas',
  Axon.Repl in 'src\Axon.Repl.pas',
  Axon.Packages in 'src\Axon.Packages.pas',
  Axon.TestRunner in 'src\Axon.TestRunner.pas',
  Axon.Cli in 'src\Axon.Cli.pas',
  Axon.Native.LibFFI in 'src\native\Axon.Native.LibFFI.pas',
  Axon.Native.Blas in 'src\native\Axon.Native.Blas.pas',
  Axon.Native.Lapack in 'src\native\Axon.Native.Lapack.pas',
  Axon.Native.SparseSolver in 'src\native\Axon.Native.SparseSolver.pas',
  Axon.Native.Cvode in 'src\native\Axon.Native.Cvode.pas',
  Axon.Native.Mir in 'src\native\Axon.Native.Mir.pas';

begin
  ExitCode := RunCli;
end.
