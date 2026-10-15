unit Atlas.Common.Index.SymbolIndex;

// Threadsicherer Symbolindex im Speicher. Schlüssel sind Unit-Namen und
// Dateinamen ohne Groß-/Kleinschreibung; Symbolnamen und Vorfahren werden
// beim Hinzufügen einer Unit in Nachschlagetabellen eingetragen.
//
// Nachschlagetabellen (Diagnoselog 15.10.2026): FindSymbols und Descendants
// liefen früher über alle Symbole aller Units. Mit eingelesener Bibliothek
// (über 5000 Units) kostete jeder Aufruf mehrere Zehntel Sekunden; Prüfregeln
// rufen ihn je Methode und Vorfahr auf, eine Datei brauchte so 30 s bis über
// 200 s. Jetzt verweist je Name (und je Vorfahr ohne Unit-Präfix) eine Liste
// auf Platz der Unit und Position des Symbols. Ersetzte oder entfernte Units
// lassen ihre Verweise als tot zurück (Platz ohne Datei); überwiegen die
// toten, werden die Tabellen neu aufgebaut.
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
  TSymbolIndex = class(TInterfacedObject, ISymbolIndex)
  private type
    /// <summary>Verweis auf ein Symbol: Platz der Unit (FSlotKeys) und Position in ihren Symbolen.</summary>
    TSymbolRef = record
      Slot: Integer;
      Position: Integer;
    end;
    TSymbolRefs = TList<TSymbolRef>;
    TSymbolTable = TObjectDictionary<string, TSymbolRefs>;
  public const
    /// <summary>Ab so vielen toten Verweisen (und mehr tot als lebend) werden die Tabellen neu gebaut.</summary>
    RebuildDeadRefs = 4096;
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
    // Name (groß) → Verweise; Vorfahr ohne Unit-Präfix und Typargumente (groß) → Verweise.
    FByName: TSymbolTable;
    FByAncestor: TSymbolTable;
    // Platz → Dateischlüssel ('' = Unit ersetzt oder entfernt) und Zahl seiner Verweise.
    FSlotKeys: TList<string>;
    FSlotRefs: TList<Integer>;
    // Dateischlüssel → aktueller Platz.
    FFileSlots: TDictionary<string, Integer>;
    FLiveRefs: Integer;
    FDeadRefs: Integer;
    procedure AddLocked(const AKey: string; const AUnit: TUnitIndex);
    procedure ShrinkLocked;
    procedure RemoveFileLocked(const AFileKey: string);
    procedure AddRefsLocked(const AKey: string; const AUnit: TUnitIndex);
    procedure DropRefsLocked(const AKey: string);
    /// <summary>Baut die Tabellen neu, wenn die toten Verweise überwiegen.</summary>
    procedure CleanRefsLocked;
    function LocationsLocked(ATable: TSymbolTable; const AKey: string): TArray<TSymbolLocation>;
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
  System.StrUtils,
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
  FByName := TSymbolTable.Create([doOwnsValues]);
  FByAncestor := TSymbolTable.Create([doOwnsValues]);
  FSlotKeys := TList<string>.Create;
  FSlotRefs := TList<Integer>.Create;
  FFileSlots := TDictionary<string, Integer>.Create;
end;

destructor TSymbolIndex.Destroy;
begin
  // Namensindex der Import-Vorschläge (#617) hält sonst unsere Units fest.
  TImportNames.Forget(Self);
  FFileSlots.Free;
  FSlotRefs.Free;
  FSlotKeys.Free;
  FByAncestor.Free;
  FByName.Free;
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
  DropRefsLocked(AFileKey);
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
  AddRefsLocked(AKey, AUnit);
end;

procedure AddRef(ATable: TObjectDictionary<string, TList<TSymbolIndex.TSymbolRef>>; const AKey: string;
  ASlot, APosition: Integer);
var
  Refs: TList<TSymbolIndex.TSymbolRef>;
  Ref: TSymbolIndex.TSymbolRef;
begin
  if not ATable.TryGetValue(AKey, Refs) then
  begin
    Refs := TList<TSymbolIndex.TSymbolRef>.Create;
    ATable.Add(AKey, Refs);
  end;
  Ref.Slot := ASlot;
  Ref.Position := APosition;
  Refs.Add(Ref);
end;

procedure TSymbolIndex.AddRefsLocked(const AKey: string; const AUnit: TUnitIndex);
var
  Slot, Position, AncestorPos, Count: Integer;
  Keys: TArray<string>;
  Key: string;
begin
  Slot := FSlotKeys.Add(AKey);
  FSlotRefs.Add(0);
  FFileSlots.AddOrSetValue(AKey, Slot);
  Count := 0;
  // Zugriff über den Index, damit die Symbol-Records nicht kopiert werden.
  for Position := 0 to High(AUnit.Symbols) do
  begin
    AddRef(FByName, UpperCase(AUnit.Symbols[Position].Name), Slot, Position);
    Inc(Count);
    // Je Symbol jeden Vorfahren nur einmal (class(TFoo, IFoo) mit Unit.TFoo und TFoo<T>).
    Keys := nil;
    for AncestorPos := 0 to High(AUnit.Symbols[Position].Ancestors) do
    begin
      Key := UpperCase(LastPart(AUnit.Symbols[Position].Ancestors[AncestorPos]));
      if (Key = '') or (IndexStr(Key, Keys) >= 0) then
        Continue;
      Keys := Keys + [Key];
      AddRef(FByAncestor, Key, Slot, Position);
      Inc(Count);
    end;
  end;
  FSlotRefs[Slot] := Count;
  Inc(FLiveRefs, Count);
end;

procedure TSymbolIndex.DropRefsLocked(const AKey: string);
var
  Slot: Integer;
begin
  if not FFileSlots.TryGetValue(AKey, Slot) then
    Exit;
  FFileSlots.Remove(AKey);
  FSlotKeys[Slot] := '';
  Dec(FLiveRefs, FSlotRefs[Slot]);
  Inc(FDeadRefs, FSlotRefs[Slot]);
  FSlotRefs[Slot] := 0;
end;

procedure TSymbolIndex.CleanRefsLocked;
var
  Pair: TPair<string, TUnitIndex>;
begin
  if (FDeadRefs < RebuildDeadRefs) or (FDeadRefs <= FLiveRefs) then
    Exit;
  FByName.Clear;
  FByAncestor.Clear;
  FSlotKeys.Clear;
  FSlotRefs.Clear;
  FFileSlots.Clear;
  FLiveRefs := 0;
  FDeadRefs := 0;
  for Pair in FFiles do
    AddRefsLocked(Pair.Key, Pair.Value);
end;

function TSymbolIndex.LocationsLocked(ATable: TSymbolTable; const AKey: string): TArray<TSymbolLocation>;
var
  Refs: TSymbolRefs;
  Found: TList<TSymbolLocation>;
  Index, LastSlot: Integer;
  Ref: TSymbolRef;
  FileKey: string;
  Owner: TUnitIndex;
  Known: Boolean;
  Location: TSymbolLocation;
begin
  Result := nil;
  if not ATable.TryGetValue(AKey, Refs) then
    Exit;
  Found := TList<TSymbolLocation>.Create;
  try
    LastSlot := -1;
    Known := False;
    for Index := 0 to Refs.Count - 1 do
    begin
      Ref := Refs[Index];
      // Verweise einer Unit stehen beieinander: die Unit nur beim Wechsel des Platzes nachschlagen.
      if Ref.Slot <> LastSlot then
      begin
        LastSlot := Ref.Slot;
        FileKey := FSlotKeys[Ref.Slot];
        Known := (FileKey <> '') and FFiles.TryGetValue(FileKey, Owner);
      end;
      if not Known or (Ref.Position > High(Owner.Symbols)) then
        Continue;
      Location.UnitName := Owner.UnitName;
      Location.FileName := Owner.SymbolFile(Owner.Symbols[Ref.Position]);
      Location.Symbol := Owner.Symbols[Ref.Position];
      Found.Add(Location);
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
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
    CleanRefsLocked;
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.RemoveFile(const AFileName: string);
begin
  FLock.Enter;
  try
    RemoveFileLocked(AnsiUpperCase(AFileName));
    CleanRefsLocked;
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

function TSymbolIndex.FindSymbols(const AName: string): TArray<TSymbolLocation>;
begin
  FLock.Enter;
  try
    Result := LocationsLocked(FByName, UpperCase(AName));
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.Descendants(const ATypeName: string): TArray<TSymbolLocation>;
var
  Key: string;
begin
  Key := UpperCase(LastPart(ATypeName));
  if Key = '' then
    Exit(nil);
  FLock.Enter;
  try
    Result := LocationsLocked(FByAncestor, Key);
  finally
    FLock.Leave;
  end;
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
    CleanRefsLocked;
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
