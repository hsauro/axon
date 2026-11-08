unit Axon.Source;

{ Loading Axon source files: UTF-8, optional BOM, .sci or .txt extension. }

interface

function IsSourceFileName(const FileName: string): Boolean;

{ Reads a source file as UTF-8, dropping a leading BOM. Raises EInOutError if
  the file cannot be read, and a SyntaxError if it is not valid UTF-8. }
function LoadSourceFile(const FileName: string): string;

{ Reads any text file as UTF-8 (used for expected-output files). }
function LoadUtf8File(const FileName: string): string;

implementation

uses
  System.SysUtils, System.IOUtils,
  Axon.Errors;

function IsSourceFileName(const FileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result := (Ext = '.sci') or (Ext = '.txt');
end;

function LoadUtf8File(const FileName: string): string;
var
  Bytes: TBytes;
  Start: Integer;
begin
  Bytes := TFile.ReadAllBytes(FileName);
  Start := 0;
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Start := 3;
  Result := TEncoding.UTF8.GetString(Bytes, Start, Length(Bytes) - Start);
end;

function LoadSourceFile(const FileName: string): string;
begin
  try
    Result := LoadUtf8File(FileName);
  except
    on EEncodingError do
      raise EAxonError.Create(SyntaxError,
        Format('%s is not valid UTF-8 text', [FileName.Replace('', '/')]));
  end;
end;

end.
