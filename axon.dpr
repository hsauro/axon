program axon;

{ Axon interpreter entry point. All work happens in Axon.Cli. }

{$APPTYPE CONSOLE}

uses
  Axon.Version in 'src\Axon.Version.pas',
  Axon.Errors in 'src\Axon.Errors.pas',
  Axon.Platform in 'src\Axon.Platform.pas',
  Axon.Source in 'src\Axon.Source.pas',
  Axon.Tokens in 'src\Axon.Tokens.pas',
  Axon.Lexer in 'src\Axon.Lexer.pas',
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
