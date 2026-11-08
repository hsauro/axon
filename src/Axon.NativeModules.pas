unit Axon.NativeModules;

(* Core modules written in Delphi, such as io and graphics.

   `import m` searches for m.sci first (reference, "Modules"); when no file is
   found, a native module of that name is used. Each native module registers
   a procedure that defines its functions, all of which are exported, and a
   docstring for help. *)

interface

uses
  System.SysUtils,
  Axon.Values;

type
  TModuleDefiner = procedure(const Define: TProc<string, TAxValue>);

procedure RegisterNativeModule(const Name: string; Definer: TModuleDefiner;
  const Doc: TArray<string>);

function FindNativeModule(const Name: string; out Definer: TModuleDefiner;
  out Doc: TArray<string>): Boolean;

{ A built-in function value. MaxArgs = -1 means no limit. }
function BuiltinValue(const Name: string; Fn: TBuiltinFn; MinArgs, MaxArgs: Integer): TAxValue;

implementation

uses
  System.Generics.Collections;

type
  TEntry = record
    Definer: TModuleDefiner;
    Doc: TArray<string>;
  end;

var
  Registry: TDictionary<string, TEntry>;

procedure RegisterNativeModule(const Name: string; Definer: TModuleDefiner;
  const Doc: TArray<string>);
var
  E: TEntry;
begin
  if Registry = nil then
    Registry := TDictionary<string, TEntry>.Create;
  E.Definer := Definer;
  E.Doc := Doc;
  Registry.AddOrSetValue(Name, E);
end;

function FindNativeModule(const Name: string; out Definer: TModuleDefiner;
  out Doc: TArray<string>): Boolean;
var
  E: TEntry;
begin
  Result := (Registry <> nil) and Registry.TryGetValue(Name, E);
  if Result then
  begin
    Definer := E.Definer;
    Doc := E.Doc;
  end;
end;

function BuiltinValue(const Name: string; Fn: TBuiltinFn; MinArgs, MaxArgs: Integer): TAxValue;
var
  B: TBuiltinObj;
begin
  B := TBuiltinObj.Create;
  B.Name := Name;
  B.Fn := Fn;
  B.MinArgs := MinArgs;
  B.MaxArgs := MaxArgs;
  Result := NothingValue;
  Result.Kind := vkBuiltin;
  Result.Obj := B;
end;

initialization

finalization
  Registry.Free;

end.
