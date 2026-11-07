unit Axon.Native.SparseSolver;

{ Sparse direct solver (KLU from SuiteSparse; UMFPACK is the alternative).

  Bound through Delphi `external` declarations (with `delayed`, so the
  interpreter starts even when the library is absent). The declarations are
  added in M11, the milestone that first uses them; this unit fixes the
  library name per platform. }

interface

const
{$IFDEF MSWINDOWS}
  LibraryName = 'klu.dll';
{$ENDIF}
{$IFDEF MACOS}
  LibraryName = 'libklu.dylib';
{$ENDIF}
{$IFDEF LINUX}
  LibraryName = 'libklu.so.2';
{$ENDIF}

implementation

end.
