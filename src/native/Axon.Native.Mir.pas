unit Axon.Native.Mir;

{ MIR: in-process JIT compiler.

  Bound through Delphi `external` declarations (with `delayed`, so the
  interpreter starts even when the library is absent). The declarations are
  added in L2, the milestone that first uses them; this unit fixes the
  library name per platform. }

interface

const
{$IFDEF MSWINDOWS}
  LibraryName = 'mir.dll';
{$ENDIF}
{$IFDEF MACOS}
  LibraryName = 'libmir.dylib';
{$ENDIF}
{$IFDEF LINUX}
  LibraryName = 'libmir.so';
{$ENDIF}

implementation

end.
