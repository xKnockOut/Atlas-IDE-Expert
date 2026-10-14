unit Atlas.Common.Index.SymbolIndex;

// Threadsicherer Symbolindex im Speicher. Schlüssel sind Unit-Namen und
// Dateinamen ohne Groß-/Kleinschreibung; Symbolnamen und Vorfahren werden
// beim Hinzufügen einer Unit in Nachschlagetabellen eingetragen.
//
// Speicherbudget (#185): Zeichenketten kommen in einen Pool. Übersteigt der
// geschätzte Bedarf das Budget, werden zuerst die Verwendungen ausgelagert
// (#492; sie bleiben im Cache auf der Platte), dann Bibliotheks-Units, danach
// Projekt-Units kompakt gehalten (nur interface-Symbole).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Memory;

type
  /// <summary>Filter für Locations; const, damit nicht jedes Symbol kopiert wird.</summary>
  TIndexSymbolFilter = reference to function(const ASymbol: TIndexSymbol): Boolean;

  TSymbolIndex = class(TInterfacedObject, ISymbolIndex)
  private
    FLock: TCriticalSection;
    // Dateiname (groß) → Unit
    FFiles: TDictionary<string, TUnitIndex>;
    // Unit-Name (groß) → Dateiname (groß)
    FUnitFiles: TDictionary<string, string>;
    FSymbolCount: Integer;
    FPool: TStringPool;
    FBytes: Int64;
    FBudget: Int64;
    FCompactCount: Integer;
    FOffloadedCount: Integer;
    FGeneration: Int64;
    procedure AddLocked(const AKey: string; const AUnit: TUnitIndex);
    procedure ShrinkLocked;
    function Locations(const AFilter: TIndexSymbolFilter): TArray<TSymbolLocation>;
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
    function MemoryBytes: Int64;
    function CompactCount: Integer;
    function OffloadedCount: Integer;
    procedure SetBudget(ABytes: Int64);
    function Budget: Int64;
    function Generation: Int64;
  end;

implementation

uses
  Atlas.Common.Index.NameIndex;

var
  // Jeder Index beginnt mit eigener Generation, damit ein neuer Index an derselben Adresse
  // nie für den alten gehalten wird (#617).
  IndexSerial: Int64;

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
  FGeneration := TInterlocked.Increment(IndexSerial) shl 32;
  FLock := TCriticalSection.Create;
  FFiles := TDictionary<string, TUnitIndex>.Create;
  FUnitFiles := TDictionary<string, string>.Create;
  FPool := TStringPool.Create;
end;

destructor TSymbolIndex.Destroy;
begin
  // Namensindex der Import-Vorschläge (#617) hält sonst unsere Units fest.
  TImportNames.Forget(Self);
  FPool.Free;
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
  Dec(FBytes, TIndexMemory.UnitBytes(Existing));
  if Existing.Compact then
    Dec(FCompactCount);
  if Existing.UsagesOffloaded then
    Dec(FOffloadedCount);
  FFiles.Remove(AFileKey);
  Inc(FGeneration);
  if FUnitFiles.TryGetValue(UpperCase(Existing.UnitName), UnitFile) and (UnitFile = AFileKey) then
    FUnitFiles.Remove(UpperCase(Existing.UnitName));
end;

procedure TSymbolIndex.AddLocked(const AKey: string; const AUnit: TUnitIndex);
begin
  FFiles.Add(AKey, AUnit);
  Inc(FGeneration);
  FUnitFiles.AddOrSetValue(UpperCase(AUnit.UnitName), AKey);
  Inc(FSymbolCount, Length(AUnit.Symbols));
  Inc(FBytes, TIndexMemory.UnitBytes(AUnit));
  if AUnit.Compact then
    Inc(FCompactCount);
  if AUnit.UsagesOffloaded then
    Inc(FOffloadedCount);
end;

procedure TSymbolIndex.ShrinkLocked;
var
  Pass: Integer;
  Keys: TArray<string>;
  Key: string;
  Existing: TUnitIndex;
begin
  // Erst die Verwendungen auslagern (#492), dann Bibliotheken, dann Projekt-Units kompakt halten;
  // jeweils nur bis das Budget wieder reicht. Ohne Überschreitung nichts kopieren: AddUnit ruft
  // das bei jeder Unit auf.
  if (FBudget <= 0) or (FBytes <= FBudget) or (FCompactCount >= FFiles.Count) then
    Exit;
  for Pass := -1 to 1 do
  begin
    Keys := FFiles.Keys.ToArray;
    for Key in Keys do
    begin
      if (FBudget <= 0) or (FBytes <= FBudget) then
        Exit;
      Existing := FFiles[Key];
      if Pass < 0 then
      begin
        if Length(Existing.Usages) = 0 then
          Continue;
        RemoveFileLocked(Key);
        AddLocked(Key, TIndexMemory.WithoutUsages(Existing));
        Continue;
      end;
      if Existing.Compact or ((Pass = 0) and not Existing.Library_) then
        Continue;
      RemoveFileLocked(Key);
      AddLocked(Key, TIndexMemory.Compacted(TIndexMemory.WithoutUsages(Existing)));
    end;
  end;
end;

procedure TSymbolIndex.AddUnit(const AUnit: TUnitIndex);
var
  Key: string;
  Pooled: TUnitIndex;
begin
  Key := AnsiUpperCase(AUnit.FileName);
  Pooled := AUnit;
  FLock.Enter;
  try
    // Eigene Kopie der Arrays, damit der Pool die Einträge des Aufrufers nicht ändert.
    Pooled.InterfaceUses := Copy(AUnit.InterfaceUses);
    Pooled.ImplementationUses := Copy(AUnit.ImplementationUses);
    Pooled.Symbols := Copy(AUnit.Symbols);
    FPool.InternUnit(Pooled);
    RemoveFileLocked(Key);
    AddLocked(Key, Pooled);
    ShrinkLocked;
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

function TSymbolIndex.Locations(const AFilter: TIndexSymbolFilter): TArray<TSymbolLocation>;
var
  Found: TList<TSymbolLocation>;
  Snapshot: TArray<TUnitIndex>;
  UnitPos, SymbolPos: Integer;
  Location: TSymbolLocation;
begin
  // Nur den Schnappschuss unter der Sperre nehmen (#647): Der Durchlauf über alle
  // Symbole (große Projekte über 500.000) hielt sonst FindUnit und FindFile jeder
  // anderen Anfrage auf, solange Prüfregeln FindSymbols aufrufen. Zugriff über den
  // Index statt for-in, damit die Symbol-Records nicht kopiert werden.
  Snapshot := Units;
  Found := TList<TSymbolLocation>.Create;
  try
    for UnitPos := 0 to High(Snapshot) do
      for SymbolPos := 0 to High(Snapshot[UnitPos].Symbols) do
        if AFilter(Snapshot[UnitPos].Symbols[SymbolPos]) then
        begin
          Location.UnitName := Snapshot[UnitPos].UnitName;
          Location.FileName := Snapshot[UnitPos].SymbolFile(Snapshot[UnitPos].Symbols[SymbolPos]);
          Location.Symbol := Snapshot[UnitPos].Symbols[SymbolPos];
          Found.Add(Location);
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
    function(const ASymbol: TIndexSymbol): Boolean
    begin
      // Länge zuerst: trennt fast alle Symbole ohne Zeichenvergleich aus.
      Result := (Length(ASymbol.Name) = Length(Name)) and SameText(ASymbol.Name, Name);
    end);
end;

function TSymbolIndex.Descendants(const ATypeName: string): TArray<TSymbolLocation>;
var
  Name: string;
begin
  Name := LastPart(ATypeName);
  Result := Locations(
    function(const ASymbol: TIndexSymbol): Boolean
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

function TSymbolIndex.Generation: Int64;
begin
  FLock.Enter;
  try
    Result := FGeneration;
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

function TSymbolIndex.MemoryBytes: Int64;
begin
  FLock.Enter;
  try
    Result := FBytes;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.CompactCount: Integer;
begin
  FLock.Enter;
  try
    Result := FCompactCount;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.OffloadedCount: Integer;
begin
  FLock.Enter;
  try
    Result := FOffloadedCount;
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.SetBudget(ABytes: Int64);
begin
  FLock.Enter;
  try
    FBudget := ABytes;
    ShrinkLocked;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.Budget: Int64;
begin
  FLock.Enter;
  try
    Result := FBudget;
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
