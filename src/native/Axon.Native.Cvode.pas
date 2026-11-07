unit Axon.Native.Cvode;

{ SUNDIALS CVODE: the BDF solver behind ode.solve.

  Bound through Delphi `external` declarations (with `delayed`, so the
  interpreter starts even when the library is absent). The declarations are
  added in M13, the milestone that first uses them; this unit fixes the
  library name per platform. }

interface

const
{$IFDEF MSWINDOWS}
  LibraryName = 'sundials_cvode.dll';
{$ENDIF}
{$IFDEF MACOS}
  LibraryName = 'libsundials_cvode.dylib';
{$ENDIF}
{$IFDEF LINUX}
  LibraryName = 'libsundials_cvode.so';
{$ENDIF}

implementation

end.
