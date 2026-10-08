unit BDLsp.Common.Index.SymbolIndex;

// Threadsicherer Symbolindex im Speicher. Schlüssel sind Unit-Namen und
// Dateinamen ohne Groß-/Kleinschreibung; Symbolnamen und Vorfahren werden
// beim Hinzufügen einer Unit in Nachschlagetabellen eingetragen.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  BDLsp.Common.Index.Contract;

type
  TSymbolIndex = class(TInterfacedObject, ISymbolIndex)
  private
    FLock: TCriticalSection;
    // Dateiname (groß) → Unit
    FFiles: TDictionary<string, TUnitIndex>;
    // Unit-Name (groß) → Dateiname (groß)
    FUnitFiles: TDictionary<string, string>;
    FSymbolCount: Integer;
    function Locations(const AFilter: TFunc<TIndexSymbol, Boolean>): TArray<TSymbolLocation>;
    procedure RemoveFileLocked(const AFileKey: string);
  public
    constructor Create;
    destructor Destroy; override;
    { ISymbolIndex }
    procedure AddUnit(const AUnit: TUnitIndex);
    procedure RemoveFile(const AFileName: string);
    function FindUnit(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
    function FindFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    function FindSymbols(const AName: string): TArray<TSymbolLocation>;
    function Descendants(const ATypeName: string): TArray<TSymbolLocation>;
    function Units: TArray<TUnitIndex>;
    function UnitCount: Integer;
    function SymbolCount: Integer;
  end;

implementation

function LastPart(const AName: string): string;
var
  Dot: Integer;
begin
  // Unit.TFoo und TFoo<T> auf TFoo zurückführen.
  Result := AName;
  Dot := Pos('<', Result);
  if Dot > 0 then
    Result := Copy(Result, 1, Dot - 1);
  Dot := LastDelimiter('.', Result);
  if Dot > 0 then
    Result := Copy(Result, Dot + 1, MaxInt);
end;

{ TSymbolIndex }

constructor TSymbolIndex.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FFiles := TDictionary<string, TUnitIndex>.Create;
  FUnitFiles := TDictionary<string, string>.Create;
end;

destructor TSymbolIndex.Destroy;
begin
  FUnitFiles.Free;
  FFiles.Free;
  FLock.Free;
  inherited;
end;

procedure TSymbolIndex.RemoveFileLocked(const AFileKey: string);
var
  Existing: TUnitIndex;
  UnitFile: string;
begin
  if not FFiles.TryGetValue(AFileKey, Existing) then
    Exit;
  Dec(FSymbolCount, Length(Existing.Symbols));
  FFiles.Remove(AFileKey);
  if FUnitFiles.TryGetValue(UpperCase(Existing.UnitName), UnitFile) and (UnitFile = AFileKey) then
    FUnitFiles.Remove(UpperCase(Existing.UnitName));
end;

procedure TSymbolIndex.AddUnit(const AUnit: TUnitIndex);
var
  Key: string;
begin
  Key := AnsiUpperCase(AUnit.FileName);
  FLock.Enter;
  try
    RemoveFileLocked(Key);
    FFiles.Add(Key, AUnit);
    FUnitFiles.AddOrSetValue(UpperCase(AUnit.UnitName), Key);
    Inc(FSymbolCount, Length(AUnit.Symbols));
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.RemoveFile(const AFileName: string);
begin
  FLock.Enter;
  try
    RemoveFileLocked(AnsiUpperCase(AFileName));
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.FindUnit(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
var
  FileKey: string;
begin
  FLock.Enter;
  try
    Result := FUnitFiles.TryGetValue(UpperCase(AUnitName), FileKey) and FFiles.TryGetValue(FileKey, AUnit);
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.FindFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
begin
  FLock.Enter;
  try
    Result := FFiles.TryGetValue(AnsiUpperCase(AFileName), AUnit);
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.Locations(const AFilter: TFunc<TIndexSymbol, Boolean>): TArray<TSymbolLocation>;
var
  Found: TList<TSymbolLocation>;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Location: TSymbolLocation;
begin
  Found := TList<TSymbolLocation>.Create;
  try
    FLock.Enter;
    try
      for UnitIndex in FFiles.Values do
        for Symbol in UnitIndex.Symbols do
          if AFilter(Symbol) then
          begin
            Location.UnitName := UnitIndex.UnitName;
            Location.FileName := UnitIndex.FileName;
            Location.Symbol := Symbol;
            Found.Add(Location);
          end;
    finally
      FLock.Leave;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

function TSymbolIndex.FindSymbols(const AName: string): TArray<TSymbolLocation>;
var
  Name: string;
begin
  Name := AName;
  Result := Locations(
    function(ASymbol: TIndexSymbol): Boolean
    begin
      Result := SameText(ASymbol.Name, Name);
    end);
end;

function TSymbolIndex.Descendants(const ATypeName: string): TArray<TSymbolLocation>;
var
  Name: string;
begin
  Name := LastPart(ATypeName);
  Result := Locations(
    function(ASymbol: TIndexSymbol): Boolean
    var
      Ancestor: string;
    begin
      for Ancestor in ASymbol.Ancestors do
        if SameText(LastPart(Ancestor), Name) then
          Exit(True);
      Result := False;
    end);
end;

function TSymbolIndex.Units: TArray<TUnitIndex>;
begin
  FLock.Enter;
  try
    Result := FFiles.Values.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.UnitCount: Integer;
begin
  FLock.Enter;
  try
    Result := FFiles.Count;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.SymbolCount: Integer;
begin
  FLock.Enter;
  try
    Result := FSymbolCount;
  finally
    FLock.Leave;
  end;
end;

end.
