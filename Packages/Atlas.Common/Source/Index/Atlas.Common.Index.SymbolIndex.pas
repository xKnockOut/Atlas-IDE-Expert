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
// geschätzte Bedarf das Budget, werden zuerst Bibliotheks-Units kompakt
// gehalten (nur interface-Symbole, ohne Verwendungen), dann die Verwendungen
// der Projekt-Units ausgelagert (#492; sie bleiben im Cache auf der Platte),
// zuletzt Projekt-Units kompakt gehalten. Die Verwendungen der Projekt-Units
// gehen erst nach den Bibliotheken: Ohne sie lesen projektweite Regeln
// (unused-public-member) jede Datei der Gruppe, und der Prüflauf staut sich
// (Abbrüche in 2.0-stable). MemoryParts teilt
// die Schätzung für das Fenster „Atlas-Server“ (#1356) in Projekt, Bibliothek
// und Verwendungen; die Anteile laufen beim Hinzufügen und Entfernen mit.
//
// Heißer Pfad: Units liefert einen Schnappschuss, der bis zur nächsten Änderung gilt,
// statt bei jedem Aufruf alle Units zu kopieren; UnavailableUnits nur die Units mit nicht geltenden
// Zweigen. Das Einordnen der Zeichenketten in den Pool läuft außerhalb der Index-Sperre unter einer
// eigenen, damit Leser nicht auf das Einlesen großer Units warten.
//
// Unit-Aliase: FindUnit führt einen Alias (WinTypes → Winapi.Windows) auf seine
// Unit, wenn es keine Unit dieses Namens gibt. Die Vorgaben von Delphi gelten
// immer, AddUnitAliases ergänzt die Aliase der geladenen Projekte.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Memory,
  Atlas.Common.Index.UsageCounts;

type
  /// <summary>Nachschlagetabellen des Symbolindex: je Name und je Vorfahr Verweise auf Platz der Unit und Position
  /// des Symbols. Nicht threadsicher; TSymbolIndex nutzt sie unter seiner Sperre.</summary>
  TSymbolRefTables = class
  private type
    /// <summary>Verweis auf ein Symbol: Platz der Unit (FSlotKeys) und Position in ihren Symbolen.</summary>
    TSymbolRef = record
      Slot: Integer;
      Position: Integer;
    end;
    TSymbolRefs = TList<TSymbolRef>;
    TSymbolTable = TObjectDictionary<string, TSymbolRefs>;
    /// <summary>Was die Suche nach Namen von der Unit eines Platzes braucht. FFiles.TryGetValue kopierte je
    /// Wechsel den ganzen TUnitIndex samt verwalteter Felder; die Symbole teilt sich dieser Eintrag mit ihm
    /// (dynamisches Array, nur gezählt).</summary>
    TSlotUnit = record
      Known: Boolean;
      UnitName: string;
      FileName: string;
      Symbols: TArray<TIndexSymbol>;
    end;
  private
    // Name (groß) → Verweise; Vorfahr ohne Unit-Präfix und Typargumente (groß) → Verweise.
    FByName: TSymbolTable;
    FByAncestor: TSymbolTable;
    // Platz → Dateischlüssel ('' = Unit ersetzt oder entfernt) und Zahl seiner Verweise.
    FSlotKeys: TList<string>;
    FSlotRefs: TList<Integer>;
    // Platz → Unit für die Suche (Known = False, wenn ersetzt oder entfernt); parallel zu FSlotKeys.
    FSlotUnits: TList<TSlotUnit>;
    // Dateischlüssel → aktueller Platz.
    FFileSlots: TDictionary<string, Integer>;
    FLiveRefs: Integer;
    FDeadRefs: Integer;
    class procedure AddRef(ATable: TSymbolTable; const AKey: string; ASlot, APosition: Integer); static;
    function Locations(ATable: TSymbolTable; const AKey: string): TArray<TSymbolLocation>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    /// <summary>Trägt die Symbole von AUnit (Dateischlüssel AKey) auf einem neuen Platz ein.</summary>
    procedure Add(const AKey: string; const AUnit: TUnitIndex);
    /// <summary>Macht die Verweise der Unit AKey tot.</summary>
    procedure Drop(const AKey: string);
    function ByName(const AKey: string): TArray<TSymbolLocation>;
    function ByAncestor(const AKey: string): TArray<TSymbolLocation>;
    function HasName(const AKey: string; const AMatch: TSymbolMatch): Boolean;
    property LiveRefs: Integer read FLiveRefs;
    property DeadRefs: Integer read FDeadRefs;
  end;

  /// <summary>Zählerstände des Symbolindex: Symbole, geschätzte Bytes samt Anteilen (#1356: Verwendungen aller Units,
  /// Bibliotheks-Units ohne Verwendungen), kompakte Units und Units mit ausgelagerten Verwendungen.</summary>
  TSymbolIndexTotals = record
    SymbolCount: Integer;
    Bytes: Int64;
    UsageBytes: Int64;
    LibraryBytes: Int64;
    CompactCount: Integer;
    OffloadedCount: Integer;
    /// <summary>Zählt AUnit hinzu (ASign = 1) oder heraus (ASign = -1).</summary>
    procedure Count(const AUnit: TUnitIndex; ASign: Integer);
    /// <summary>Liegen die Bytes über dem Budget ABudget (0 = unbegrenzt)?</summary>
    function OverBudget(ABudget: Int64): Boolean;
  end;

  TSymbolIndex = class(TInterfacedObject, ISymbolIndex)
  public const
    /// <summary>Ab so vielen toten Verweisen (und mehr tot als lebend) werden die Tabellen neu gebaut.</summary>
    cRebuildDeadRefs = 4096;
  private
    FLock: TCriticalSection;
    // Ergebnis von Units bis zur nächsten Änderung an FFiles; nil = neu aufbauen. Jede Änderung leert es,
    // damit ersetzte Units nicht im Schnappschuss weiterleben.
    FUnitsSnapshot: TArray<TUnitIndex>;
    // Dateischlüssel der Units mit Unavailable (#476).
    FUnavailable: TDictionary<string, Boolean>;
    // Dateiname (groß) → Unit
    FFiles: TDictionary<string, TUnitIndex>;
    // Unit-Name (groß) → Dateiname (groß)
    FUnitFiles: TDictionary<string, string>;
    // Zählerstände und Speicherschätzung aller abgelegten Units.
    FTotals: TSymbolIndexTotals;
    FPool: TStringPool;
    FBudget: Int64;
    // Dateischlüssel der Units, die sich noch verkleinern lassen (nicht kompakt oder mit
    // Verwendungen); ShrinkLocked läuft nur über sie statt bei jeder Unit über alle.
    FShrinkable: TDictionary<string, Boolean>;
    FGeneration: Int64;
    FRefs: TSymbolRefTables;
    // Stellen je Name in den Projekt-Units (#2109); nur AddUnit und RemoveFile schreiben sie fort.
    FUsageCounts: TIndexUsageCounts;
    // Unit-Aliase (Vorgaben von Delphi und die der Projekte). Unter FLock.
    FAliases: TArray<TPair<string, string>>;
    procedure AddLocked(const AKey: string; const AUnit: TUnitIndex);
    procedure ShrinkLocked;
    /// <summary>Verkleinert die Unit AKey im Durchgang APass: 0 Bibliothek kompakt halten, 1 Verwendungen der
    /// Projekt-Units auslagern, 2 Projekt-Units kompakt halten.</summary>
    procedure ShrinkUnitLocked(APass: Integer; const AKey: string);
    procedure RemoveFileLocked(const AFileKey: string);
    /// <summary>Baut die Tabellen neu, wenn die toten Verweise überwiegen.</summary>
    procedure CleanRefsLocked;
  public
    constructor Create;
    destructor Destroy; override;
    { ISymbolIndex }
    procedure AddUnit(const AUnit: TUnitIndex);
    procedure RemoveFile(const AFileName: string);
    function FindUnit(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
    procedure AddUnitAliases(const AAliases: TArray<TPair<string, string>>);
    function FindFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    function FindSymbols(const AName: string): TArray<TSymbolLocation>;
    function HasSymbol(const AName: string; const AMatch: TSymbolMatch): Boolean;
    function Descendants(const ATypeName: string): TArray<TSymbolLocation>;
    function Units: TArray<TUnitIndex>;
    function UnavailableUnits: TArray<TUnitIndex>;
    function UnitCount: Integer;
    function SymbolCount: Integer;
    function MemoryBytes: Int64;
    function MemoryParts: TIndexMemoryParts;
    function CompactCount: Integer;
    function OffloadedCount: Integer;
    procedure SetBudget(ABytes: Int64);
    function Budget: Int64;
    function Generation: Int64;
    function UsageCount(const AName: string): Integer;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Projects.UnitAliases,
  Atlas.Common.Index.NameIndex;

var
  // Jeder Index beginnt mit eigener Generation, damit ein neuer Index an derselben Adresse
  // nie für den alten gehalten wird (#617).
  IndexSerial: Int64;

function LastPart(const AName: string): string;
var
  mDot: Integer;
begin
  // Unit.TFoo und TFoo<T> auf TFoo zurückführen.
  Result := AName;
  mDot := Pos('<', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, 1, mDot - 1);
  end;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

{ TSymbolIndex }

constructor TSymbolIndex.Create;
begin
  inherited Create;
  FGeneration := TInterlocked.Increment(IndexSerial) shl 32;
  FLock := TCriticalSection.Create;
  FUnavailable := TDictionary<string, Boolean>.Create;
  FFiles := TDictionary<string, TUnitIndex>.Create;
  FUnitFiles := TDictionary<string, string>.Create;
  FPool := TStringPool.Create;
  FRefs := TSymbolRefTables.Create;
  FShrinkable := TDictionary<string, Boolean>.Create;
  FUsageCounts := TIndexUsageCounts.Create;
  FAliases := TUnitAliases.Defaults;
end;

destructor TSymbolIndex.Destroy;
begin
  // Namensindex der Import-Vorschläge (#617) hält sonst unsere Units fest.
  TImportNames.Forget(Self);
  FUsageCounts.Free;
  FShrinkable.Free;
  FRefs.Free;
  FPool.Free;
  FUnitFiles.Free;
  FFiles.Free;
  FUnavailable.Free;
  FLock.Free;
  inherited;
end;

procedure TSymbolIndex.RemoveFileLocked(const AFileKey: string);
var
  mExisting: TUnitIndex;
  mUnitFile: string;
begin
  if not FFiles.TryGetValue(AFileKey, mExisting) then
  begin
    Exit;
  end;
  FTotals.Count(mExisting, -1);
  FFiles.Remove(AFileKey);
  FUnitsSnapshot := nil;
  FUnavailable.Remove(AFileKey);
  FShrinkable.Remove(AFileKey);
  FRefs.Drop(AFileKey);
  Inc(FGeneration);
  if FUnitFiles.TryGetValue(UpperCase(mExisting.UnitName), mUnitFile) and (mUnitFile = AFileKey) then
  begin
    FUnitFiles.Remove(UpperCase(mExisting.UnitName));
  end;
end;

procedure TSymbolIndex.AddLocked(const AKey: string; const AUnit: TUnitIndex);
var
  mStored: TUnitIndex;
begin
  // Jede abgelegte Fassung bekommt ihre eigene Namenstabelle (Diagnoselog 15.10.2026); FindUnit und
  // FindFile geben sie mit, die Namensauflösung sucht darüber statt linear.
  mStored := AUnit;
  mStored.PrepareNames;
  FFiles.Add(AKey, mStored);
  FUnitsSnapshot := nil;
  if Length(AUnit.Unavailable) > 0 then
  begin
    FUnavailable.AddOrSetValue(AKey, True);
  end;
  Inc(FGeneration);
  FUnitFiles.AddOrSetValue(UpperCase(AUnit.UnitName), AKey);
  FTotals.Count(AUnit, 1);
  if not AUnit.Compact or (Length(AUnit.Usages) > 0) then
  begin
    FShrinkable.AddOrSetValue(AKey, True);
  end;
  FRefs.Add(AKey, AUnit);
end;

{ TSymbolIndexTotals }

procedure TSymbolIndexTotals.Count(const AUnit: TUnitIndex; ASign: Integer);
begin
  Inc(SymbolCount, ASign * Length(AUnit.Symbols));
  Inc(Bytes, ASign * TIndexMemory.UnitBytes(AUnit));
  Inc(UsageBytes, ASign * TIndexMemory.UsageBytes(AUnit));
  if AUnit.Library_ then
  begin
    Inc(LibraryBytes, ASign * (TIndexMemory.UnitBytes(AUnit) - TIndexMemory.UsageBytes(AUnit)));
  end;
  if AUnit.Compact then
  begin
    Inc(CompactCount, ASign);
  end;
  if AUnit.UsagesOffloaded then
  begin
    Inc(OffloadedCount, ASign);
  end;
end;

{ TSymbolRefTables }

constructor TSymbolRefTables.Create;
begin
  inherited Create;
  FByName := TSymbolTable.Create([doOwnsValues]);
  FByAncestor := TSymbolTable.Create([doOwnsValues]);
  FSlotKeys := TList<string>.Create;
  FSlotRefs := TList<Integer>.Create;
  FSlotUnits := TList<TSlotUnit>.Create;
  FFileSlots := TDictionary<string, Integer>.Create;
end;

destructor TSymbolRefTables.Destroy;
begin
  FFileSlots.Free;
  FSlotUnits.Free;
  FSlotRefs.Free;
  FSlotKeys.Free;
  FByAncestor.Free;
  FByName.Free;
  inherited;
end;

procedure TSymbolRefTables.Clear;
begin
  FByName.Clear;
  FByAncestor.Clear;
  FSlotKeys.Clear;
  FSlotRefs.Clear;
  FSlotUnits.Clear;
  FFileSlots.Clear;
  FLiveRefs := 0;
  FDeadRefs := 0;
end;

class procedure TSymbolRefTables.AddRef(ATable: TSymbolTable; const AKey: string; ASlot, APosition: Integer);
var
  mRefs: TSymbolRefs;
  mRef: TSymbolRef;
begin
  if not ATable.TryGetValue(AKey, mRefs) then
  begin
    mRefs := TSymbolRefs.Create;
    ATable.Add(AKey, mRefs);
  end;
  mRef.Slot := ASlot;
  mRef.Position := APosition;
  mRefs.Add(mRef);
end;

/// <summary>Vorfahren eines Symbols ohne Unit-Präfix und Typargumente (groß), jeden einmal (class(TFoo, IFoo) mit
/// Unit.TFoo und TFoo&lt;T&gt;).</summary>
function AncestorKeys(const ASymbol: TIndexSymbol): TArray<string>;
var
  mIndex: Integer;
  mKey: string;
begin
  Result := nil;
  for mIndex := 0 to High(ASymbol.Ancestors) do
  begin
    mKey := UpperCase(LastPart(ASymbol.Ancestors[mIndex]));
    if (mKey <> '') and (IndexStr(mKey, Result) < 0) then
    begin
      Result := Result + [mKey];
    end;
  end;
end;

procedure TSymbolRefTables.Add(const AKey: string; const AUnit: TUnitIndex);
var
  mSlot, mPosition, mCount: Integer;
  mKey: string;
  mSlotUnit: TSlotUnit;
begin
  mSlot := FSlotKeys.Add(AKey);
  FSlotRefs.Add(0);
  mSlotUnit.Known := True;
  mSlotUnit.UnitName := AUnit.UnitName;
  mSlotUnit.FileName := AUnit.FileName;
  mSlotUnit.Symbols := AUnit.Symbols;
  FSlotUnits.Add(mSlotUnit);
  FFileSlots.AddOrSetValue(AKey, mSlot);
  mCount := 0;
  // Zugriff über den Index, damit die Symbol-Records nicht kopiert werden.
  for mPosition := 0 to High(AUnit.Symbols) do
  begin
    AddRef(FByName, UpperCase(AUnit.Symbols[mPosition].Name), mSlot, mPosition);
    Inc(mCount);
    for mKey in AncestorKeys(AUnit.Symbols[mPosition]) do
    begin
      AddRef(FByAncestor, mKey, mSlot, mPosition);
      Inc(mCount);
    end;
  end;
  FSlotRefs[mSlot] := mCount;
  Inc(FLiveRefs, mCount);
end;

procedure TSymbolRefTables.Drop(const AKey: string);
var
  mSlot: Integer;
begin
  if not FFileSlots.TryGetValue(AKey, mSlot) then
  begin
    Exit;
  end;
  FFileSlots.Remove(AKey);
  FSlotKeys[mSlot] := '';
  FSlotUnits[mSlot] := Default(TSlotUnit);
  Dec(FLiveRefs, FSlotRefs[mSlot]);
  Inc(FDeadRefs, FSlotRefs[mSlot]);
  FSlotRefs[mSlot] := 0;
end;

function TSymbolRefTables.Locations(ATable: TSymbolTable; const AKey: string): TArray<TSymbolLocation>;
var
  mRefs: TSymbolRefs;
  mIndex, mCount, mLastSlot: Integer;
  mRef: TSymbolRef;
  mOwner: TSlotUnit;
begin
  Result := nil;
  if not ATable.TryGetValue(AKey, mRefs) then
  begin
    Exit;
  end;
  // Direkt ins Ergebnis statt über eine Liste und ToArray: jedes Symbol ist ein großer Record mit verwalteten
  // Feldern, häufige Namen (Create, Count) haben Tausende Verweise, und die Regeln fragen je Bezeichner.
  SetLength(Result, mRefs.Count);
  mCount := 0;
  mLastSlot := -1;
  mOwner := Default(TSlotUnit);
  for mIndex := 0 to mRefs.Count - 1 do
  begin
    mRef := mRefs[mIndex];
    // Verweise einer Unit stehen beieinander: den Platz nur beim Wechsel lesen.
    if mRef.Slot <> mLastSlot then
    begin
      mLastSlot := mRef.Slot;
      mOwner := FSlotUnits[mRef.Slot];
    end;
    if not mOwner.Known or (mRef.Position > High(mOwner.Symbols)) then
    begin
      Continue;
    end;
    Result[mCount].UnitName := mOwner.UnitName;
    Result[mCount].FileName := mOwner.Symbols[mRef.Position].FileName;
    if Result[mCount].FileName = '' then
    begin
      Result[mCount].FileName := mOwner.FileName;
    end;
    Result[mCount].Symbol := mOwner.Symbols[mRef.Position];
    Inc(mCount);
  end;
  SetLength(Result, mCount);
end;

function TSymbolRefTables.ByName(const AKey: string): TArray<TSymbolLocation>;
begin
  Result := Locations(FByName, AKey);
end;

function TSymbolRefTables.ByAncestor(const AKey: string): TArray<TSymbolLocation>;
begin
  Result := Locations(FByAncestor, AKey);
end;

function TSymbolRefTables.HasName(const AKey: string; const AMatch: TSymbolMatch): Boolean;
var
  mRefs: TSymbolRefs;
  mIndex, mLastSlot: Integer;
  mRef: TSymbolRef;
  mOwner: TSlotUnit;
begin
  Result := False;
  if not FByName.TryGetValue(AKey, mRefs) then
  begin
    Exit;
  end;
  mLastSlot := -1;
  mOwner := Default(TSlotUnit);
  for mIndex := 0 to mRefs.Count - 1 do
  begin
    mRef := mRefs[mIndex];
    // Wie Locations: der Eintrag des Platzes, nicht der ganze TUnitIndex aus FFiles.
    if mRef.Slot <> mLastSlot then
    begin
      mLastSlot := mRef.Slot;
      mOwner := FSlotUnits[mRef.Slot];
    end;
    if mOwner.Known and (mRef.Position <= High(mOwner.Symbols)) and AMatch(mOwner.Symbols[mRef.Position]) then
    begin
      Exit(True);
    end;
  end;
end;

{ TSymbolIndex: Nachschlagetabellen und Budget }

procedure TSymbolIndex.CleanRefsLocked;
var
  mPair: TPair<string, TUnitIndex>;
begin
  if (FRefs.DeadRefs < cRebuildDeadRefs) or (FRefs.DeadRefs <= FRefs.LiveRefs) then
  begin
    Exit;
  end;
  FRefs.Clear;
  for mPair in FFiles do
  begin
    FRefs.Add(mPair.Key, mPair.Value);
  end;
end;

function TSymbolIndexTotals.OverBudget(ABudget: Int64): Boolean;
begin
  Result := (ABudget > 0) and (Bytes > ABudget);
end;

procedure TSymbolIndex.ShrinkUnitLocked(APass: Integer; const AKey: string);
var
  mExisting: TUnitIndex;
begin
  if not FFiles.TryGetValue(AKey, mExisting) then
  begin
    Exit;
  end;
  if APass = 1 then
  begin
    if Length(mExisting.Usages) > 0 then
    begin
      RemoveFileLocked(AKey);
      AddLocked(AKey, TIndexMemory.WithoutUsages(mExisting));
    end;
  end
  else if not mExisting.Compact and ((APass = 2) or mExisting.Library_) then
  begin
    RemoveFileLocked(AKey);
    AddLocked(AKey, TIndexMemory.Compacted(TIndexMemory.WithoutUsages(mExisting)));
  end;
end;

procedure TSymbolIndex.ShrinkLocked;
var
  mPass: Integer;
  mKey: string;
begin
  // Erst Bibliotheken kompakt halten, dann die Verwendungen der Projekt-Units auslagern (#492), dann
  // Projekt-Units kompakt halten; jeweils nur bis das Budget wieder reicht. Ohne Überschreitung nichts kopieren:
  // AddUnit ruft
  // das bei jeder Unit auf.
  if not FTotals.OverBudget(FBudget) or (FShrinkable.Count = 0) then
  begin
    Exit;
  end;
  for mPass := 0 to 2 do
  begin
    for mKey in FShrinkable.Keys.ToArray do
    begin
      if not FTotals.OverBudget(FBudget) then
      begin
        Exit;
      end;
      ShrinkUnitLocked(mPass, mKey);
    end;
  end;
end;

procedure TSymbolIndex.AddUnit(const AUnit: TUnitIndex);
var
  mKey: string;
  mPooled: TUnitIndex;
begin
  mKey := AnsiUpperCase(AUnit.FileName);
  mPooled := AUnit;
  // Eigene Kopie der Arrays, damit der Pool die Einträge des Aufrufers nicht ändert. Kopieren und Einordnen
  // in den Pool außerhalb von FLock: Leser warten sonst auf jede große Unit. Zwei
  // gleichzeitige Aufrufe für dieselbe Datei können sich dadurch überholen; das Ergebnis ist dann wie bei
  // umgekehrter Aufrufreihenfolge. Der Index-Builder liest jede Datei nur aus einem Thread.
  mPooled.InterfaceUses := Copy(AUnit.InterfaceUses);
  mPooled.ImplementationUses := Copy(AUnit.ImplementationUses);
  mPooled.Symbols := Copy(AUnit.Symbols);
  // Der Pool sperrt selbst, nicht unter FLock.
  FPool.InternUnit(mPooled);
  FLock.Enter;
  try
    RemoveFileLocked(mKey);
    AddLocked(mKey, mPooled);
    // Vor ShrinkLocked: Danach können die Verwendungen schon ausgelagert sein.
    FUsageCounts.Replace(mKey, mPooled);
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
    FUsageCounts.Remove(AnsiUpperCase(AFileName));
    CleanRefsLocked;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.FindUnit(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
var
  mFileKey, mTarget: string;
begin
  FLock.Enter;
  try
    Result := FUnitFiles.TryGetValue(UpperCase(AUnitName), mFileKey) and FFiles.TryGetValue(mFileKey, AUnit);
    // Wie dcc: uses WinTypes lädt Winapi.Windows. Eine Unit, die selbst so heißt, geht vor.
    if not Result and TUnitAliases.Target(FAliases, AUnitName, mTarget) then
    begin
      Result := FUnitFiles.TryGetValue(UpperCase(mTarget), mFileKey) and FFiles.TryGetValue(mFileKey, AUnit);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.AddUnitAliases(const AAliases: TArray<TPair<string, string>>);
begin
  FLock.Enter;
  try
    // Die neuen zuerst: Ein Projekt kann einen Alias der Vorgaben anders belegen.
    FAliases := TUnitAliases.Merge(AAliases, FAliases);
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
    Result := FRefs.ByName(UpperCase(AName));
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.HasSymbol(const AName: string; const AMatch: TSymbolMatch): Boolean;
begin
  FLock.Enter;
  try
    Result := FRefs.HasName(UpperCase(AName), AMatch);
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.Descendants(const ATypeName: string): TArray<TSymbolLocation>;
var
  mKey: string;
begin
  mKey := UpperCase(LastPart(ATypeName));
  if mKey = '' then
  begin
    Exit(nil);
  end;
  FLock.Enter;
  try
    Result := FRefs.ByAncestor(mKey);
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.Units: TArray<TUnitIndex>;
begin
  FLock.Enter;
  try
    // Schnappschuss bis zur nächsten Änderung; dynamische Arrays sind referenzgezählt.
    if FUnitsSnapshot = nil then
    begin
      FUnitsSnapshot := FFiles.Values.ToArray;
    end;
    Result := FUnitsSnapshot;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.UnavailableUnits: TArray<TUnitIndex>;
var
  mKey: string;
  mFound: TList<TUnitIndex>;
  mUnitIndex: TUnitIndex;
begin
  mFound := TList<TUnitIndex>.Create;
  try
    FLock.Enter;
    try
      for mKey in FUnavailable.Keys do
      begin
        if FFiles.TryGetValue(mKey, mUnitIndex) then
        begin
          mFound.Add(mUnitIndex);
        end;
      end;
    finally
      FLock.Leave;
    end;
    Result := mFound.ToArray;
  finally
    mFound.Free;
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

function TSymbolIndex.UsageCount(const AName: string): Integer;
begin
  FLock.Enter;
  try
    Result := FUsageCounts.Count(AName);
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
    Result := FTotals.Bytes;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.MemoryParts: TIndexMemoryParts;
begin
  FLock.Enter;
  try
    Result.UsageBytes := FTotals.UsageBytes;
    Result.LibraryBytes := FTotals.LibraryBytes;
    Result.ProjectBytes := FTotals.Bytes - FTotals.UsageBytes - FTotals.LibraryBytes;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.CompactCount: Integer;
begin
  FLock.Enter;
  try
    Result := FTotals.CompactCount;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.OffloadedCount: Integer;
begin
  FLock.Enter;
  try
    Result := FTotals.OffloadedCount;
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
    Result := FTotals.SymbolCount;
  finally
    FLock.Leave;
  end;
end;

end.
