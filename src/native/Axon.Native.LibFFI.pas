unit Axon.Native.LibFFI;

{ libffi: foreign calls and closures (trampolines for `callback`).

  Bound through Delphi `external` declarations (with `delayed`, so the
  interpreter starts even when the library is absent). The declarations are
  added in M9, the milestone that first uses them; this unit fixes the
  library name per platform. }

interface

const
{$IFDEF MSWINDOWS}
  LibraryName = 'libffi-8.dll';
{$ENDIF}
{$IFDEF MACOS}
  LibraryName = 'libffi.8.dylib';
{$ENDIF}
{$IFDEF LINUX}
  LibraryName = 'libffi.so.8';
{$ENDIF}

implementation

end.
