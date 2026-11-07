unit Axon.Native.Lapack;

{ LAPACK (shipped inside OpenBLAS): solve, eig, svd, qr, lu, chol.

  Bound through Delphi `external` declarations (with `delayed`, so the
  interpreter starts even when the library is absent). The declarations are
  added in M10, the milestone that first uses them; this unit fixes the
  library name per platform. }

interface

const
{$IFDEF MSWINDOWS}
  LibraryName = 'libopenblas.dll';
{$ENDIF}
{$IFDEF MACOS}
  LibraryName = 'libopenblas.dylib';
{$ENDIF}
{$IFDEF LINUX}
  LibraryName = 'libopenblas.so.0';
{$ENDIF}

implementation

end.
