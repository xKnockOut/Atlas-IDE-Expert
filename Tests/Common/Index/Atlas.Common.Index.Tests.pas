unit Atlas.Common.Index.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  /// <summary>Dateisystem im Speicher; zählt Lesezugriffe.</summary>
  TMemoryIndexFileSystem = class(TInterfacedObject, IIndexFileSystem)
  private
    FTexts: TDictionary<string, string>;
    FBytes: TDictionary<string, TBytes>;
    FStamps: TDictionary<string, Int64>;
    FReads: Integer;
    FFailReads: Boolean;
    FFailWrites: Boolean;
    FRefuseWrites: Boolean;
    FLocked: TDictionary<string, Boolean>;
    FAfterRead: TProc<string>;
    FBeforeWrite: TProc;
    FBeforeReadText: TProc<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const AFileName, AText: string; AStamp: Int64);
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    function ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
    function WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean; overload;
    /// <summary>Für Tests, die den Grund nicht brauchen.</summary>
    function WriteBytes(const AFileName: string; const ABytes: TBytes): Boolean; overload;
    function TryLockWrite(const AFileName: string): IInterface;
    /// <summary>Gibt eine Sperre aus TryLockWrite frei.</summary>
    procedure Unlock(const AFileName: string);
    procedure Delete(const AFileName: string);
    property Reads: Integer read FReads write FReads;
    /// <summary>ReadBytes bzw. WriteBytes lösen EInOutError aus (Cache nicht lesbar/schreibbar).</summary>
    property FailReads: Boolean read FFailReads write FFailReads;
    property FailWrites: Boolean read FFailWrites write FFailWrites;
    /// <summary>WriteBytes liefert False mit Grund, wie TDiskIndexFileSystem bei einem Fehler.</summary>
    property RefuseWrites: Boolean read FRefuseWrites write FRefuseWrites;
    /// <summary>Nach jedem ReadBytes mit dem Dateinamen, außerhalb der Sperre (ein anderer Schreiber).</summary>
    property AfterRead: TProc<string> read FAfterRead write FAfterRead;
    /// <summary>Läuft vor jedem WriteBytes außerhalb der Sperre, z. B. um ein Schreiben aufzuhalten.</summary>
    property BeforeWrite: TProc read FBeforeWrite write FBeforeWrite;
    /// <summary>Läuft vor jedem ReadText außerhalb der Sperre, z. B. um das Lesen aufzuhalten.</summary>
    property BeforeReadText: TProc<string> read FBeforeReadText write FBeforeReadText;
  end;

  [TestFixture]
  TIndexExtractorTests = class
  public
    [Test]
    procedure ExtractsTypesMembersAndRoutines;
    [Test]
    procedure ExtractsAncestors;
    /// <summary>Typargumente stehen je Vorfahr im Index und überstehen den Cache.</summary>
    [Test]
    procedure ExtractsAncestorArgsOfEveryAncestor;
    [Test]
    procedure ForwardDeclarationGivesWayToFullType;
    [Test]
    procedure ExtractsUsesLists;
    [Test]
    procedure MarksInterfaceSymbols;
    [Test]
    procedure SkipsInactiveBranches;
    [Test]
    procedure ExtractsProgramDeclarations;
    [Test]
    procedure RecordsConditionsAndUnavailableDeclarations;
    /// <summary>Mitglieder in bedingten Teilen eines Klassenrumpfs (#476).</summary>
    [Test]
    procedure RecordsConditionsOfMembers;
    /// <summary>string[N] behält die Länge in der Signatur, der Typname bleibt string (#1036).</summary>
    [Test]
    procedure KeepsShortStringLengthInSignature;
    /// <summary>Routinen nur im implementation-Teil unter einem nicht geltenden Zweig (#476).</summary>
    [Test]
    procedure RecordsUnavailableImplementationRoutines;
  end;

  [TestFixture]
  TSymbolIndexTests = class
  public
    [Test]
    procedure FindsUnitsAndSymbols;
    [Test]
    procedure ReplacesUnitOfSameFile;
    [Test]
    procedure FindsDescendants;
    [Test]
    procedure FindSymbolsMatchesWholeNamesOnly;
    [Test]
    procedure HasSymbolStopsAtFirstMatch;
    [Test]
    procedure LookupsStayCorrectAfterManyReplacements;
    [Test]
    procedure LookupsFollowCompaction;
    [Test]
    procedure DescendantsListSymbolOnce;
    [Test]
    procedure SymbolsNamedUsesTableOfStoredUnit;
    [Test]
    procedure SymbolsNamedFallsBackForChangedSymbols;
    /// <summary>Code-Review P-13: Ohne Änderung liefert Units denselben Schnappschuss (kein Kopieren).</summary>
    [Test]
    procedure UnitsSnapshotReusedWithoutChange;
    [Test]
    procedure UnitsSnapshotRenewedAfterChange;
    /// <summary>Code-Review P-13: UnavailableUnits nur mit Deklarationen aus nicht geltenden Zweigen.</summary>
    [Test]
    procedure UnavailableUnitsOnlyAffected;
    /// <summary>Code-Review P-13: InternUnit außerhalb der Index-Sperre; parallele AddUnit verlieren nichts.</summary>
    [Test]
    procedure AddUnitConcurrentKeepsAllUnits;
  end;

  [TestFixture]
  TIndexCacheTests = class
  public
    [Test]
    procedure RoundTripsUnits;
    [Test]
    procedure RoundTripsSpecialCharactersAndFlags;
    [Test]
    procedure IndexesAndCachesRationale;
    [Test]
    procedure RejectsOtherVersionAndBrokenData;
    [Test]
    procedure ReadsHeadersAndExpandsSymbolsOnDemand;
    [Test]
    procedure SharesEqualStringsAfterLoading;
    [Test]
    procedure RejectsDamagedSymbolBlock;
  end;

  [TestFixture]
  TIndexSchedulerTests = class
  public
    [Test]
    procedure OrdersByStageThenPriority;
    /// <summary>#1356: wartende und laufende Aufbauten mit Wartezeit für das Fenster „Atlas-Server“.</summary>
    [Test]
    procedure QueueCountsWaitingBuilds;
  end;

  [TestFixture]
  TIndexProjectFilesTests = class
  public
    [Test]
    procedure ListsMainSourceAndUnitsOnce;
    [Test]
    procedure CombinesDefinesWithPlatformSymbols;
    [Test]
    procedure ListsPathUnitsOnceWithoutExcluded;
    [Test]
    procedure SharesLibraryAcrossProjectDefines;
  end;

const
  /// <summary>Unit A der Tests (auch Atlas.Common.Index.Builder.Tests).</summary>
  UnitA =
    'unit A;'#10 +
    'interface'#10 +
    'uses System.SysUtils, B;'#10 +
    'type'#10 +
    '  TBase = class'#10 +
    '  end;'#10 +
    '  TFoo = class(TBase, IInterface)'#10 +
    '  private'#10 +
    '    FValue: Integer;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    procedure Run;'#10 +
    '    property Value: Integer read FValue;'#10 +
    '  end;'#10 +
    '  TFarbe = (Rot, Gruen);'#10 +
    'const'#10 +
    '  Max = 10;'#10 +
    'var'#10 +
    '  Global: Integer;'#10 +
    'procedure Hilfe;'#10 +
    'implementation'#10 +
    'uses C;'#10 +
    'procedure Hilfe; begin end;'#10 +
    'constructor TFoo.Create; begin end;'#10 +
    'procedure TFoo.Run; begin end;'#10 +
    'end.';

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Memory,
  Atlas.Common.Index.Cache,
  Atlas.Common.Rationale.Contract,
  Atlas.Common.Index.Builder,
  Atlas.Common.Index.Service,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.Index.ProjectFiles;

function Extract(const AText: string; const ADefines: TArray<string> = nil): TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(AText, 'C:\Projekt\A.pas', ADefines);
end;

function FindSymbol(const AUnit: TUnitIndex; const AQualifiedName: string; out ASymbol: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
  begin
    if SameText(Symbol.QualifiedName, AQualifiedName) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

function Count(const AUnit: TUnitIndex; const AQualifiedName: string): Integer;
var
  Symbol: TIndexSymbol;
begin
  Result := 0;
  for Symbol in AUnit.Symbols do
  begin
    if SameText(Symbol.QualifiedName, AQualifiedName) then
    begin
      Inc(Result);
    end;
  end;
end;

function MakeUnit(const AName, AFileName: string; const ASymbols: array of string;
  const AAncestor: string = ''): TUnitIndex;
var
  I: Integer;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AName;
  Result.FileName := AFileName;
  SetLength(Result.Symbols, Length(ASymbols));
  for I := 0 to High(ASymbols) do
  begin
    Result.Symbols[I] := Default(TIndexSymbol);
    Result.Symbols[I].Name := ASymbols[I];
    Result.Symbols[I].Kind := TIndexSymbolKind.ClassType;
    if AAncestor <> '' then
    begin
      Result.Symbols[I].Ancestors := [AAncestor];
    end;
  end;
end;

{ TMemoryIndexFileSystem }

constructor TMemoryIndexFileSystem.Create;
begin
  inherited Create;
  FTexts := TDictionary<string, string>.Create;
  FBytes := TDictionary<string, TBytes>.Create;
  FStamps := TDictionary<string, Int64>.Create;
  FLocked := TDictionary<string, Boolean>.Create;
end;

destructor TMemoryIndexFileSystem.Destroy;
begin
  FLocked.Free;
  FStamps.Free;
  FBytes.Free;
  FTexts.Free;
  inherited;
end;

procedure TMemoryIndexFileSystem.Put(const AFileName, AText: string; AStamp: Int64);
begin
  FTexts.AddOrSetValue(UpperCase(AFileName), AText);
  FStamps.AddOrSetValue(UpperCase(AFileName), AStamp);
end;

procedure TMemoryIndexFileSystem.Delete(const AFileName: string);
begin
  FTexts.Remove(UpperCase(AFileName));
  FBytes.Remove(UpperCase(AFileName));
  FStamps.Remove(UpperCase(AFileName));
end;

function TMemoryIndexFileSystem.FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
begin
  TMonitor.Enter(Self);
  try
    Result := FStamps.TryGetValue(UpperCase(AFileName), AStamp);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMemoryIndexFileSystem.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  if Assigned(FBeforeReadText) then
  begin
    FBeforeReadText(AFileName);
  end;
  TMonitor.Enter(Self);
  try
    Inc(FReads);
    Result := FTexts.TryGetValue(UpperCase(AFileName), AText);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMemoryIndexFileSystem.WriteText(const AFileName, AText: string): Boolean;
begin
  TMonitor.Enter(Self);
  try
    FTexts.AddOrSetValue(UpperCase(AFileName), AText);
    FStamps.AddOrSetValue(UpperCase(AFileName), 1);
    Result := True;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMemoryIndexFileSystem.ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
var
  After: TProc<string>;
begin
  if FFailReads then
  begin
    raise EInOutError.Create('simuliert');
  end;
  TMonitor.Enter(Self);
  try
    Inc(FReads);
    Result := FBytes.TryGetValue(UpperCase(AFileName), ABytes);
    After := FAfterRead;
  finally
    TMonitor.Exit(Self);
  end;
  if Assigned(After) then
  begin
    After(AFileName);
  end;
end;

function TMemoryIndexFileSystem.WriteBytes(const AFileName: string; const ABytes: TBytes;
  out AError: string): Boolean;
var
  Stamp: Int64;
begin
  AError := '';
  if Assigned(FBeforeWrite) then
  begin
    FBeforeWrite();
  end;
  if FFailWrites then
  begin
    raise EInOutError.Create('simuliert');
  end;
  if FRefuseWrites then
  begin
    AError := 'simuliert';
    Exit(False);
  end;
  TMonitor.Enter(Self);
  try
    FBytes.AddOrSetValue(UpperCase(AFileName), ABytes);
    // Jedes Schreiben ändert den Zeitstempel wie auf der Platte; TSharedCacheWrites erkennt daran fremde
    // Schreiber.
    if not FStamps.TryGetValue(UpperCase(AFileName), Stamp) then
    begin
      Stamp := 0;
    end;
    FStamps.AddOrSetValue(UpperCase(AFileName), Stamp + 1);
    Result := True;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMemoryIndexFileSystem.WriteBytes(const AFileName: string; const ABytes: TBytes): Boolean;
var
  Error: string;
begin
  Result := WriteBytes(AFileName, ABytes, Error);
end;

type
  /// <summary>Sperre aus TMemoryIndexFileSystem.TryLockWrite; gibt beim Freigeben frei.</summary>
  TMemoryWriteLock = class(TInterfacedObject)
  private
    FFiles: TMemoryIndexFileSystem;
    FFileName: string;
  public
    constructor Create(AFiles: TMemoryIndexFileSystem; const AFileName: string);
    destructor Destroy; override;
  end;

constructor TMemoryWriteLock.Create(AFiles: TMemoryIndexFileSystem; const AFileName: string);
begin
  inherited Create;
  FFiles := AFiles;
  FFileName := AFileName;
end;

destructor TMemoryWriteLock.Destroy;
begin
  FFiles.Unlock(FFileName);
  inherited;
end;

function TMemoryIndexFileSystem.TryLockWrite(const AFileName: string): IInterface;
begin
  TMonitor.Enter(Self);
  try
    if FLocked.ContainsKey(UpperCase(AFileName)) then
    begin
      Exit(nil);
    end;
    FLocked.Add(UpperCase(AFileName), True);
  finally
    TMonitor.Exit(Self);
  end;
  Result := TMemoryWriteLock.Create(Self, AFileName);
end;

procedure TMemoryIndexFileSystem.Unlock(const AFileName: string);
begin
  TMonitor.Enter(Self);
  try
    FLocked.Remove(UpperCase(AFileName));
  finally
    TMonitor.Exit(Self);
  end;
end;

{ TIndexExtractorTests }

procedure TIndexExtractorTests.ExtractsTypesMembersAndRoutines;
var
  U: TUnitIndex;
  S: TIndexSymbol;
begin
  U := Extract(UnitA);
  Assert.AreEqual('A', U.UnitName);
  Assert.IsTrue(FindSymbol(U, 'TFoo', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.ClassType);
  Assert.AreEqual(6, S.SelectionRange.StartPos.Line);
  Assert.AreEqual(2, S.SelectionRange.StartPos.Character);
  Assert.IsTrue(FindSymbol(U, 'TFoo.FValue', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.Field);
  Assert.IsTrue(FindSymbol(U, 'TFoo.Value', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.Property_);
  Assert.IsTrue(FindSymbol(U, 'TFoo.Create', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.Constructor_);
  // Deklaration im interface und Rumpf in implementation
  Assert.AreEqual(2, Count(U, 'TFoo.Run'));
  Assert.IsTrue(FindSymbol(U, 'TFarbe.Gruen', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.EnumMember);
  Assert.IsTrue(FindSymbol(U, 'Max', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.Constant);
  Assert.IsTrue(FindSymbol(U, 'Global', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.Variable);
  Assert.AreEqual(2, Count(U, 'Hilfe'));
end;

procedure TIndexExtractorTests.ExtractsAncestors;
var
  U: TUnitIndex;
  S: TIndexSymbol;
begin
  U := Extract(UnitA);
  Assert.IsTrue(FindSymbol(U, 'TFoo', S));
  Assert.AreEqual<NativeInt>(2, Length(S.Ancestors));
  Assert.AreEqual('TBase', S.Ancestors[0]);
  Assert.AreEqual('IInterface', S.Ancestors[1]);
  Assert.IsTrue(FindSymbol(U, 'TBase', S));
  Assert.AreEqual<NativeInt>(0, Length(S.Ancestors));
end;

procedure TIndexExtractorTests.ExtractsAncestorArgsOfEveryAncestor;
const
  Text = 'unit G;'#10'interface'#10'type'#10 +
    '  TVergleich = class(TInterfacedObject, IComparer<TKunde>, IMap<string, TArray<Integer>>)'#10'  end;'#10 +
    '  TListe = class(TObjectList<TKunde>)'#10'  end;'#10 +
    '  TEinfach = class(TObject, IInterface)'#10'  end;'#10 +
    'implementation'#10'end.';
var
  U: TUnitIndex;
  Loaded: TArray<TUnitIndex>;
  S: TIndexSymbol;
begin
  U := Extract(Text);
  Assert.IsTrue(FindSymbol(U, 'TVergleich', S));
  Assert.AreEqual<NativeInt>(3, Length(S.AncestorArgs));
  Assert.AreEqual('', S.AncestorArgs[0]);
  Assert.AreEqual('TKunde', S.AncestorArgs[1]);
  Assert.AreEqual('string,TArray<Integer>', StringReplace(S.AncestorArgs[2], ' ', '', [rfReplaceAll]));
  Assert.IsTrue(FindSymbol(U, 'TListe', S));
  Assert.AreEqual<NativeInt>(1, Length(S.AncestorArgs));
  Assert.AreEqual('TKunde', S.AncestorArgs[0]);
  // Ohne Typargumente bleibt die Liste leer.
  Assert.IsTrue(FindSymbol(U, 'TEinfach', S));
  Assert.AreEqual<NativeInt>(0, Length(S.AncestorArgs));
  Loaded := TIndexCache.Deserialize(TIndexCache.Serialize([U]));
  Assert.IsTrue(FindSymbol(Loaded[0], 'TVergleich', S));
  Assert.AreEqual<NativeInt>(3, Length(S.AncestorArgs));
  Assert.AreEqual('TKunde', S.AncestorArgs[1]);
end;

procedure TIndexExtractorTests.ForwardDeclarationGivesWayToFullType;
var
  U: TUnitIndex;
  S: TIndexSymbol;
begin
  // Wie Data.DB: TDataSource = class; weit oben, die volle Deklaration später.
  U := Extract('unit D;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TDataSource = class;'#10 +
    '  TNurVorwaerts = class;'#10 +
    '  IFeld = interface;'#10 +
    '  TComponent = class end;'#10 +
    '  IFeld = interface end;'#10 +
    '  TDataSource = class(TComponent)'#10 +
    '  type'#10 +
    '    TInnen = class;'#10 +
    '    TInnen = class(TComponent) end;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.');
  Assert.AreEqual(1, Count(U, 'TDataSource'));
  Assert.IsTrue(FindSymbol(U, 'TDataSource', S));
  Assert.AreEqual(8, S.SelectionRange.StartPos.Line);
  Assert.AreEqual<NativeInt>(1, Length(S.Ancestors));
  Assert.AreEqual('TComponent', S.Ancestors[0]);
  Assert.AreEqual(1, Count(U, 'IFeld'));
  Assert.AreEqual(1, Count(U, 'TDataSource.TInnen'));
  Assert.IsTrue(FindSymbol(U, 'TDataSource.TInnen', S));
  Assert.AreEqual(11, S.SelectionRange.StartPos.Line);
  // Ohne volle Deklaration bleibt die Vorwärtsdeklaration stehen.
  Assert.AreEqual(1, Count(U, 'TNurVorwaerts'));
end;

procedure TIndexExtractorTests.ExtractsUsesLists;
var
  U: TUnitIndex;
begin
  U := Extract(UnitA);
  Assert.AreEqual<NativeInt>(2, Length(U.InterfaceUses));
  Assert.AreEqual('System.SysUtils', U.InterfaceUses[0]);
  Assert.AreEqual('B', U.InterfaceUses[1]);
  Assert.AreEqual<NativeInt>(1, Length(U.ImplementationUses));
  Assert.AreEqual('C', U.ImplementationUses[0]);
end;

procedure TIndexExtractorTests.MarksInterfaceSymbols;
var
  U: TUnitIndex;
  S: TIndexSymbol;
  Seen: Boolean;
begin
  U := Extract(UnitA);
  Assert.IsTrue(FindSymbol(U, 'TFoo', S));
  Assert.IsTrue(S.InInterface);
  Seen := False;
  for S in U.Symbols do
  begin
    if (S.QualifiedName = 'TFoo.Run') and not S.InInterface then
    begin
      Seen := True;
    end;
  end;
  Assert.IsTrue(Seen, 'Rumpf in implementation');
end;

procedure TIndexExtractorTests.SkipsInactiveBranches;
const
  Source =
    'unit D;'#13#10 +
    'interface'#13#10 +
    '{$IFDEF MSWINDOWS}'#13#10 +
    'procedure NurWindows;'#13#10 +
    '{$ELSE}'#13#10 +
    'procedure NurAndere;'#13#10 +
    '{$ENDIF}'#13#10 +
    'implementation'#13#10 +
    'end.';
var
  U: TUnitIndex;
  S: TIndexSymbol;
begin
  U := Extract(Source, ['MSWINDOWS']);
  Assert.IsTrue(FindSymbol(U, 'NurWindows', S));
  Assert.AreEqual(3, S.SelectionRange.StartPos.Line);
  Assert.IsFalse(FindSymbol(U, 'NurAndere', S));
  U := Extract(Source, []);
  Assert.IsFalse(FindSymbol(U, 'NurWindows', S));
  Assert.IsTrue(FindSymbol(U, 'NurAndere', S));
  Assert.AreEqual(5, S.SelectionRange.StartPos.Line);
end;

procedure TIndexExtractorTests.RecordsConditionsAndUnavailableDeclarations;
const
  Source =
    'unit Plattform;'#10 +
    'interface'#10 +
    'type'#10 +
    '{$IFDEF WIN64}'#10 +
    '  TNur64 = class end;'#10 +
    '{$ELSE}'#10 +
    '  TNur32 = class end;'#10 +
    '{$ENDIF}'#10 +
    '  TImmer = record end;'#10 +
    '{$IFDEF MSWINDOWS}'#10 +
    'procedure NurWindows;'#10 +
    '{$ENDIF}'#10 +
    'procedure Alt; platform;'#10 +
    'implementation'#10 +
    'procedure NurWindows; begin end;'#10 +
    'procedure Alt; begin end;'#10 +
    'end.';
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
  Conditions, Missing: string;
begin
  U := TIndexExtractor.ExtractText(Source, 'C:\P\Plattform.pas', ['WIN32', 'MSWINDOWS']);
  Conditions := '';
  for Symbol in U.Symbols do
  begin
    if Symbol.Container = '' then
    begin
      Conditions := Conditions + Symbol.Name + '=' + Symbol.Condition + ';';
    end;
  end;
  Assert.Contains(Conditions, 'TNur32=not WIN64;');
  Assert.Contains(Conditions, 'TImmer=;');
  Assert.Contains(Conditions, 'NurWindows=MSWINDOWS;');
  Assert.Contains(Conditions, 'Alt=platform;');
  Assert.DoesNotContain(Conditions, 'TNur64');
  Missing := '';
  for Symbol in U.Unavailable do
  begin
    Missing := Missing + Symbol.Name + '=' + Symbol.Condition + ';';
  end;
  Assert.AreEqual('TNur64=WIN64;', Missing);
  Assert.IsTrue(U.Unavailable[0].InInterface);
  Assert.IsTrue(U.Unavailable[0].Kind = TIndexSymbolKind.ClassType);
end;

procedure TIndexExtractorTests.KeepsShortStringLengthInSignature;
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
  Found: string;
begin
  U := TIndexExtractor.ExtractText('unit Satz;'#10'interface'#10'const'#10'  Laenge = 4;'#10'type'#10 +
    '  TSatz = record'#10'    Kennung: string[8];'#10'    Kurz: string[Laenge];'#10'    Name: string;'#10 +
    '    Liste: TList<string>;'#10'  end;'#10'var'#10'  Global: string [ 5 ];'#10'implementation'#10'end.',
    'Satz.pas', nil);
  Found := '';
  for Symbol in U.Symbols do
  begin
    if Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Variable] then
    begin
      Found := Found + Symbol.Signature + '|' + Symbol.TypeName + #10;
    end;
  end;
  Assert.AreEqual('Kennung: string[8]|string'#10'Kurz: string[Laenge]|string'#10'Name: string|string'#10 +
    'Liste: TList<string>|TList'#10'Global: string[5]|string'#10, Found);
end;

procedure TIndexExtractorTests.RecordsConditionsOfMembers;
const
  Source =
    'unit Mitglieder;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TGeraet = class'#10 +
    '  public'#10 +
    '{$IFDEF WIN64}'#10 +
    '    FHandle64, FExtra: Int64;'#10 +
    '    procedure Nur64;'#10 +
    '    property Groesse64: Int64 read FHandle64;'#10 +
    '{$ELSE}'#10 +
    '    FHandle32: Integer;'#10 +
    '    function Nur32: Integer;'#10 +
    '{$ENDIF}'#10 +
    '    procedure Immer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TGeraet.Nur32; begin end;'#10 +
    'procedure TGeraet.Immer; begin end;'#10 +
    'end.';
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
  Conditions, Missing: string;
begin
  U := TIndexExtractor.ExtractText(Source, 'C:\P\Mitglieder.pas', ['WIN32', 'MSWINDOWS']);
  Conditions := '';
  for Symbol in U.Symbols do
  begin
    if Symbol.Container = 'TGeraet' then
    begin
      Conditions := Conditions + Symbol.Name + '=' + Symbol.Condition + ';';
    end;
  end;
  Assert.Contains(Conditions, 'FHandle32=not WIN64;');
  Assert.Contains(Conditions, 'Nur32=not WIN64;');
  Assert.Contains(Conditions, 'Immer=;');
  Missing := '';
  for Symbol in U.Unavailable do
  begin
    Missing := Missing + Symbol.Container + '.' + Symbol.Name + '=' + Symbol.Condition + ';';
  end;
  Assert.AreEqual('TGeraet.FHandle64=WIN64;TGeraet.FExtra=WIN64;TGeraet.Nur64=WIN64;TGeraet.Groesse64=WIN64;',
    Missing);
  Assert.IsTrue(U.Unavailable[0].Kind = TIndexSymbolKind.Field);
  Assert.IsTrue(U.Unavailable[2].Kind = TIndexSymbolKind.Method);
  Assert.IsTrue(U.Unavailable[3].Kind = TIndexSymbolKind.Property_);
  Assert.AreEqual(15, U.Unavailable[1].SelectionRange.StartPos.Character, 'Spalte des zweiten Felds');
end;

procedure TIndexExtractorTests.RecordsUnavailableImplementationRoutines;
const
  Source =
    'unit Start;'#10 +
    'interface'#10 +
    'implementation'#10 +
    '{$IFDEF FPC}'#10 +
    'procedure ApplyAppIcon;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TFoo.Bar;'#10 +
    'begin'#10 +
    'end;'#10 +
    '{$ENDIF}'#10 +
    'procedure Immer;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
  Missing: string;
begin
  U := TIndexExtractor.ExtractText(Source, 'C:\P\Start.pas', ['WIN32', 'MSWINDOWS']);
  Missing := '';
  for Symbol in U.Unavailable do
  begin
    Missing := Missing + Symbol.Name + '=' + Symbol.Condition + ';';
  end;
  Assert.AreEqual('ApplyAppIcon=FPC;', Missing);
  Assert.IsFalse(U.Unavailable[0].InInterface);
  Assert.IsTrue(U.Unavailable[0].Kind = TIndexSymbolKind.Routine);
end;

procedure TIndexExtractorTests.ExtractsProgramDeclarations;
var
  U: TUnitIndex;
  S: TIndexSymbol;
begin
  U := TIndexExtractor.ExtractText('program P;'#10'uses A in ''A.pas'';'#10'var X: Integer;'#10'begin end.',
    'C:\Projekt\P.dpr', nil);
  Assert.AreEqual('P', U.UnitName);
  Assert.AreEqual<NativeInt>(1, Length(U.ImplementationUses));
  Assert.IsTrue(FindSymbol(U, 'X', S));
  Assert.IsFalse(S.InInterface);
end;

{ TSymbolIndexTests }

procedure TSymbolIndexTests.FindsUnitsAndSymbols;
var
  Index: ISymbolIndex;
  U: TUnitIndex;
  Found: TArray<TSymbolLocation>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['TFoo', 'TBar']));
  Index.AddUnit(MakeUnit('B', 'C:\B.pas', ['TFoo']));
  Assert.IsTrue(Index.FindUnit('a', U));
  Assert.AreEqual('C:\A.pas', U.FileName);
  Assert.IsTrue(Index.FindFile('c:\b.PAS', U));
  Assert.AreEqual('B', U.UnitName);
  Found := Index.FindSymbols('tfoo');
  Assert.AreEqual<NativeInt>(2, Length(Found));
  Assert.AreEqual(2, Index.UnitCount);
  Assert.AreEqual(3, Index.SymbolCount);
  Assert.IsFalse(Index.FindUnit('Z', U));
end;

procedure TSymbolIndexTests.ReplacesUnitOfSameFile;
var
  Index: ISymbolIndex;
  U: TUnitIndex;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['TFoo', 'TBar']));
  Index.AddUnit(MakeUnit('A', 'C:\a.pas', ['TNeu']));
  Assert.AreEqual(1, Index.UnitCount);
  Assert.AreEqual(1, Index.SymbolCount);
  Assert.AreEqual<NativeInt>(0, Length(Index.FindSymbols('TFoo')));
  Index.RemoveFile('C:\A.PAS');
  Assert.AreEqual(0, Index.UnitCount);
  Assert.IsFalse(Index.FindUnit('A', U));
end;

procedure TSymbolIndexTests.FindsDescendants;
var
  Index: ISymbolIndex;
  Found: TArray<TSymbolLocation>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['TBase']));
  Index.AddUnit(MakeUnit('B', 'C:\B.pas', ['TKind'], 'A.TBase'));
  Index.AddUnit(MakeUnit('C', 'C:\C.pas', ['TListe'], 'TList<TBase>'));
  Found := Index.Descendants('TBase');
  Assert.AreEqual<NativeInt>(1, Length(Found));
  Assert.AreEqual('TKind', Found[0].Symbol.Name);
  Assert.AreEqual<NativeInt>(1, Length(Index.Descendants('TList')));
end;

procedure TSymbolIndexTests.FindSymbolsMatchesWholeNamesOnly;
var
  Index: ISymbolIndex;
  Found: TArray<TSymbolLocation>;
begin
  // Vorprüfung über die Länge (#647): gleich lange und längere Namen dürfen nicht treffen.
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['TFooBar', 'TFoo', 'TFo']));
  Index.AddUnit(MakeUnit('B', 'C:\B.pas', ['TBaz', 'TFOO']));
  Found := Index.FindSymbols('tfoo');
  Assert.AreEqual<NativeInt>(2, Length(Found));
  Assert.IsTrue(SameText('TFoo', Found[0].Symbol.Name));
  Assert.IsTrue(SameText('TFoo', Found[1].Symbol.Name));
  Assert.AreEqual<NativeInt>(0, Length(Index.FindSymbols('TFooB')));
end;

procedure TSymbolIndexTests.HasSymbolStopsAtFirstMatch;
var
  Index: ISymbolIndex;
  mCalls: Integer;
  mUnits: string;
begin
  // Ja/Nein-Fragen ohne Fundstellenliste (#1342): dieselben Symbole wie FindSymbols, Ende beim ersten Treffer.
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['TFooBar', 'TFoo']));
  Index.AddUnit(MakeUnit('B', 'C:\B.pas', ['TBaz', 'TFOO']));
  mCalls := 0;
  mUnits := '';
  Assert.IsFalse(Index.HasSymbol('tfoo',
    function(const ASymbol: TIndexSymbol): Boolean
    begin
      Inc(mCalls);
      mUnits := mUnits + ASymbol.Name + ';';
      Result := False;
    end));
  Assert.AreEqual(2, mCalls, 'alle gleichnamigen Symbole');
  Assert.AreEqual('TFOO;TFOO;', UpperCase(mUnits));
  mCalls := 0;
  Assert.IsTrue(Index.HasSymbol('TFoo',
    function(const ASymbol: TIndexSymbol): Boolean
    begin
      Inc(mCalls);
      Result := True;
    end));
  Assert.AreEqual(1, mCalls, 'Ende beim ersten Treffer');
  mCalls := 0;
  Assert.IsFalse(Index.HasSymbol('TFooB',
    function(const ASymbol: TIndexSymbol): Boolean
    begin
      Inc(mCalls);
      Result := True;
    end));
  Assert.AreEqual(0, mCalls, 'unbekannter Name');
  Index.RemoveFile('C:\A.pas');
  mCalls := 0;
  Assert.IsFalse(Index.HasSymbol('TFoo',
    function(const ASymbol: TIndexSymbol): Boolean
    begin
      Inc(mCalls);
      Result := False;
    end));
  Assert.AreEqual(1, mCalls, 'nach dem Entfernen nur noch B');
  mUnits := '';
end;

procedure TSymbolIndexTests.LookupsStayCorrectAfterManyReplacements;
var
  Index: ISymbolIndex;
  Found: TArray<TSymbolLocation>;
  Round: Integer;
begin
  // Ersetzte Units lassen tote Verweise zurück; nach genug Runden werden die Tabellen neu gebaut
  // (Diagnoselog 15.10.2026). Weder vorher noch danach darf ein alter Stand auftauchen.
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('B', 'C:\B.pas', ['TFoo'], 'TBase'));
  for Round := 1 to 3 * TSymbolIndex.cRebuildDeadRefs do
  begin
    if Odd(Round) then
    begin
      Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['TFoo', 'TBar'], 'TBase'));
    end
    else
    begin
      Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['TBar', 'TFoo', 'TBaz'], 'X.TBase'));
    end;
  end;
  Found := Index.FindSymbols('TFoo');
  Assert.AreEqual<NativeInt>(2, Length(Found));
  Assert.AreEqual<NativeInt>(1, Length(Index.FindSymbols('TBaz')));
  Assert.AreEqual<NativeInt>(4, Length(Index.Descendants('TBase')));
  Index.RemoveFile('C:\A.pas');
  Found := Index.FindSymbols('TFoo');
  Assert.AreEqual<NativeInt>(1, Length(Found));
  Assert.AreEqual('B', Found[0].UnitName);
  Assert.AreEqual<NativeInt>(0, Length(Index.FindSymbols('TBar')));
  Assert.AreEqual<NativeInt>(1, Length(Index.Descendants('TBase')));
end;

procedure TSymbolIndexTests.LookupsFollowCompaction;
var
  Index: ISymbolIndex;
  U: TUnitIndex;
  Found: TArray<TSymbolLocation>;
begin
  // Kompakt gehaltene Units verlieren Symbole; die Positionen verschieben sich.
  U := MakeUnit('A', 'C:\A.pas', ['TIntern', 'TOeffentlich']);
  U.Library_ := True;
  U.Symbols[1].InInterface := True;
  Index := TSymbolIndex.Create;
  Index.AddUnit(U);
  Index.SetBudget(1);
  Assert.AreEqual(1, Index.CompactCount);
  Assert.AreEqual<NativeInt>(0, Length(Index.FindSymbols('TIntern')));
  Found := Index.FindSymbols('TOeffentlich');
  Assert.AreEqual<NativeInt>(1, Length(Found));
  Assert.AreEqual('TOeffentlich', Found[0].Symbol.Name);
  Assert.AreEqual('C:\A.pas', Found[0].FileName);
end;

procedure TSymbolIndexTests.DescendantsListSymbolOnce;
var
  Index: ISymbolIndex;
  U: TUnitIndex;
begin
  U := MakeUnit('A', 'C:\A.pas', ['TKind']);
  U.Symbols[0].Ancestors := ['A.TBase', 'TBase<Integer>', 'IBase'];
  Index := TSymbolIndex.Create;
  Index.AddUnit(U);
  Assert.AreEqual<NativeInt>(1, Length(Index.Descendants('TBase')));
  Assert.AreEqual<NativeInt>(1, Length(Index.Descendants('Unit.IBase')));
  Assert.AreEqual<NativeInt>(0, Length(Index.Descendants('')));
end;

procedure TSymbolIndexTests.SymbolsNamedUsesTableOfStoredUnit;
var
  Index: ISymbolIndex;
  U, Found: TUnitIndex;
  Positions: TArray<Integer>;
begin
  // Diagnoselog 15.10.2026: Die Namensauflösung sucht über die Tabelle der abgelegten Unit.
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['Foo', 'Bar', 'foo']));
  Assert.IsTrue(Index.FindUnit('A', Found));
  Assert.IsTrue(Found.NameTable <> nil);
  Positions := Found.SymbolsNamed('FOO');
  Assert.AreEqual<NativeInt>(2, Length(Positions));
  Assert.AreEqual(0, Positions[0]);
  Assert.AreEqual(2, Positions[1]);
  Assert.AreEqual<NativeInt>(0, Length(Found.SymbolsNamed('Fehlt')));
  // Ersetzte Fassung: neue Tabelle, alte Positionen gelten nicht mehr.
  U := MakeUnit('A', 'C:\A.pas', ['Bar', 'Foo']);
  Index.AddUnit(U);
  Assert.IsTrue(Index.FindUnit('A', Found));
  Positions := Found.SymbolsNamed('foo');
  Assert.AreEqual<NativeInt>(1, Length(Positions));
  Assert.AreEqual(1, Positions[0]);
end;

procedure TSymbolIndexTests.SymbolsNamedFallsBackForChangedSymbols;
var
  Index: ISymbolIndex;
  Found: TUnitIndex;
  Positions: TArray<Integer>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['Foo']));
  Assert.IsTrue(Index.FindUnit('A', Found));
  // Neues Array in der Kopie: die Tabelle passt nicht mehr, gesucht wird linear.
  Found.Symbols := Copy(Found.Symbols) + MakeUnit('B', 'C:\B.pas', ['Neu', 'Foo']).Symbols;
  Positions := Found.SymbolsNamed('Foo');
  Assert.AreEqual<NativeInt>(2, Length(Positions));
  Assert.AreEqual(2, Positions[1]);
  Assert.AreEqual<NativeInt>(1, Length(Found.SymbolsNamed('neu')));
  // Ohne Tabelle (Unit nie im Index) ebenso.
  Found := MakeUnit('C', 'C:\C.pas', ['X', 'Y', 'x']);
  Assert.IsTrue(Found.NameTable = nil);
  Assert.AreEqual<NativeInt>(2, Length(Found.SymbolsNamed('X')));
end;

procedure TSymbolIndexTests.UnitsSnapshotReusedWithoutChange;
var
  Index: ISymbolIndex;
  First, Second: TArray<TUnitIndex>;
  Found: TUnitIndex;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['Foo']));
  Index.AddUnit(MakeUnit('B', 'C:\B.pas', ['Bar']));
  First := Index.Units;
  Second := Index.Units;
  Assert.AreEqual<NativeInt>(2, Length(First));
  Assert.IsTrue(Pointer(First) = Pointer(Second));
  // Lesende Zugriffe ändern den Stand nicht.
  Assert.IsTrue(Index.FindUnit('A', Found));
  Index.FindSymbols('Foo');
  Assert.IsTrue(Pointer(First) = Pointer(Index.Units));
end;

procedure TSymbolIndexTests.UnitsSnapshotRenewedAfterChange;
var
  Index: ISymbolIndex;
  First, Second: TArray<TUnitIndex>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['Foo']));
  First := Index.Units;
  Index.AddUnit(MakeUnit('B', 'C:\B.pas', ['Bar']));
  Second := Index.Units;
  Assert.IsFalse(Pointer(First) = Pointer(Second));
  Assert.AreEqual<NativeInt>(1, Length(First));
  Assert.AreEqual<NativeInt>(2, Length(Second));
  // Ersetzen derselben Datei.
  Index.AddUnit(MakeUnit('B', 'C:\B.pas', ['Bar', 'Baz']));
  First := Index.Units;
  Assert.IsFalse(Pointer(First) = Pointer(Second));
  Assert.AreEqual<NativeInt>(2, Length(First));
  Index.RemoveFile('C:\A.pas');
  Second := Index.Units;
  Assert.AreEqual<NativeInt>(1, Length(Second));
  Assert.AreEqual('B', Second[0].UnitName);
  Assert.AreEqual<NativeInt>(2, Length(Second[0].Symbols));
end;

procedure TSymbolIndexTests.UnavailableUnitsOnlyAffected;
var
  Index: ISymbolIndex;
  WithBranch: TUnitIndex;
  Found: TArray<TUnitIndex>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['Foo']));
  WithBranch := MakeUnit('B', 'C:\B.pas', ['Bar']);
  WithBranch.Unavailable := MakeUnit('B', 'C:\B.pas', ['NurDebug']).Symbols;
  Index.AddUnit(WithBranch);
  Found := Index.UnavailableUnits;
  Assert.AreEqual<NativeInt>(1, Length(Found));
  Assert.AreEqual('B', Found[0].UnitName);
  Assert.AreEqual('NurDebug', Found[0].Unavailable[0].Name);
  // Neue Fassung ohne nicht geltende Zweige: fällt heraus.
  Index.AddUnit(MakeUnit('B', 'C:\B.pas', ['Bar']));
  Assert.AreEqual<NativeInt>(0, Length(Index.UnavailableUnits));
  Index.AddUnit(WithBranch);
  Assert.AreEqual<NativeInt>(1, Length(Index.UnavailableUnits));
  Index.RemoveFile('C:\B.pas');
  Assert.AreEqual<NativeInt>(0, Length(Index.UnavailableUnits));
end;

/// <summary>Thread, der ACount Units mit dem gemeinsamen Symbol "Gemeinsam" in AIndex einträgt.</summary>
function AddUnitsThread(const AIndex: ISymbolIndex; AThread, ACount: Integer): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      Position: Integer;
    begin
      for Position := 1 to ACount do
      begin
        AIndex.AddUnit(MakeUnit(Format('U%d_%d', [AThread, Position]), Format('C:\U%d_%d.pas', [AThread, Position]),
          ['Gemeinsam', 'Eigen' + IntToStr(Position)]));
      end;
    end);
  Result.FreeOnTerminate := False;
end;

procedure TSymbolIndexTests.AddUnitConcurrentKeepsAllUnits;
const
  ThreadCount = 4;
  PerThread = 100;
var
  Index: ISymbolIndex;
  Threads: array[0..ThreadCount - 1] of TThread;
  Number: Integer;
  First, Last: TUnitIndex;
begin
  Index := TSymbolIndex.Create;
  for Number := 0 to ThreadCount - 1 do
  begin
    Threads[Number] := AddUnitsThread(Index, Number, PerThread);
  end;
  try
    for Number := 0 to ThreadCount - 1 do
    begin
      Threads[Number].Start;
    end;
    for Number := 0 to ThreadCount - 1 do
    begin
      Threads[Number].WaitFor;
    end;
  finally
    for Number := 0 to ThreadCount - 1 do
    begin
      Threads[Number].Free;
    end;
  end;
  Assert.AreEqual(ThreadCount * PerThread, Index.UnitCount);
  Assert.AreEqual<NativeInt>(ThreadCount * PerThread, Length(Index.Units));
  Assert.AreEqual<NativeInt>(ThreadCount * PerThread, Length(Index.FindSymbols('Gemeinsam')));
  // Der Pool teilt gleiche Zeichenketten auch zwischen den Threads.
  Assert.IsTrue(Index.FindUnit('U0_1', First));
  Assert.IsTrue(Index.FindUnit('U3_100', Last));
  Assert.IsTrue(Pointer(First.Symbols[0].Name) = Pointer(Last.Symbols[0].Name));
end;

{ TIndexCacheTests }

procedure TIndexCacheTests.RoundTripsUnits;
var
  Original, U: TUnitIndex;
  Loaded: TArray<TUnitIndex>;
  S: TIndexSymbol;
begin
  Original := Extract(UnitA);
  Original.Stamp := 1234567890123;
  Original.Hash := TIndexCache.HashOf(UnitA);
  Loaded := TIndexCache.Deserialize(TIndexCache.Serialize([Original]));
  Assert.AreEqual<NativeInt>(1, Length(Loaded));
  U := Loaded[0];
  Assert.AreEqual('A', U.UnitName);
  Assert.AreEqual(Original.FileName, U.FileName);
  Assert.AreEqual<Int64>(1234567890123, U.Stamp);
  Assert.AreEqual(Original.Hash, U.Hash);
  Assert.AreEqual<NativeInt>(Length(Original.Symbols), Length(U.Symbols));
  Assert.AreEqual('C', U.ImplementationUses[0]);
  Assert.IsTrue(FindSymbol(U, 'TFoo', S));
  Assert.AreEqual('IInterface', S.Ancestors[1]);
  Assert.IsTrue(S.InInterface);
  Assert.AreEqual(6, S.SelectionRange.StartPos.Line);
  Assert.IsTrue(FindSymbol(U, 'TFoo.Value', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.Property_);
end;

procedure TIndexCacheTests.RoundTripsSpecialCharactersAndFlags;
var
  Original, U: TUnitIndex;
  Loaded: TArray<TUnitIndex>;
  Symbol: TIndexSymbol;
begin
  // #617: Zeilenformat mit Escapes für Tabulator, Zeilenende, "|" und "\".
  Original := Default(TUnitIndex);
  Original.UnitName := 'Sonder';
  Original.FileName := 'C:\Pfad mit|Strich\Sonder.pas';
  Original.Library_ := True;
  Original.HasInitialization := True;
  Original.Includes := ['C:\Inc\a.inc', 'C:\Inc\b|c.inc'];
  Original.IncludeStamps := [11, 22];
  Original.Naming[TNamingKind.Field].Total := 7;
  Original.Naming[TNamingKind.Field].Prefixed := 5;
  Original.Naming[TNamingKind.Local].Total := 300;
  Original.Directives := ['deprecated', 'platform'];
  Original.DeprecatedText := 'Nutze Neu';
  Symbol := Default(TIndexSymbol);
  Symbol.Name := 'TListe';
  Symbol.TypeName := 'TDictionary<string,Integer>';
  Symbol.Condition := 'defined(A)'#9'and'#13#10'B';
  Symbol.ParamTypes := ['string', 'array of Integer'];
  Symbol.Unavailable := True;
  Original.Unavailable := [Symbol];
  Symbol.Unavailable := False;
  Original.Symbols := [Symbol];
  Loaded := TIndexCache.Deserialize(TIndexCache.Serialize([Original]));
  Assert.AreEqual<NativeInt>(1, Length(Loaded));
  U := Loaded[0];
  Assert.AreEqual(Original.FileName, U.FileName);
  Assert.IsTrue(U.Library_);
  Assert.IsTrue(U.HasInitialization);
  Assert.IsFalse(U.Compact);
  Assert.AreEqual('C:\Inc\b|c.inc', U.Includes[1]);
  Assert.AreEqual<Int64>(22, U.IncludeStamps[1]);
  Assert.AreEqual(7, U.Naming[TNamingKind.Field].Total);
  Assert.AreEqual(5, U.Naming[TNamingKind.Field].Prefixed);
  Assert.AreEqual(300, U.Naming[TNamingKind.Local].Total);
  Assert.AreEqual(0, U.Naming[TNamingKind.Parameter].Total);
  Assert.AreEqual('deprecated,platform', String.Join(',', U.Directives));
  Assert.AreEqual('Nutze Neu', U.DeprecatedText);
  Assert.AreEqual<NativeInt>(1, Length(U.Symbols));
  Assert.AreEqual('TDictionary<string,Integer>', U.Symbols[0].TypeName);
  Assert.AreEqual(Symbol.Condition, U.Symbols[0].Condition);
  Assert.AreEqual('array of Integer', U.Symbols[0].ParamTypes[1]);
  Assert.AreEqual<NativeInt>(1, Length(U.Unavailable));
  Assert.IsTrue(U.Unavailable[0].Unavailable);
end;

procedure TIndexCacheTests.IndexesAndCachesRationale;
const
  cSource = '// RATIONALE: Unit fuer den Test'#10 +
    'unit A;'#10'interface'#10'type'#10 +
    '  // WHY: siehe ADR-0007'#10 +
    '  TFoo = class'#10 +
    '    // NOTE: Feld ohne Getter'#10 +
    '    FWert: Integer;'#10 +
    '    procedure Lauf;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Lauf;'#10 +
    'begin'#10 +
    '  // HACK: bis #312 behoben ist'#10 +
    'end;'#10 +
    'end.';
var
  mOriginal, mLoaded: TUnitIndex;
  mSymbol: TIndexSymbol;
  mFound: Boolean;
begin
  mOriginal := Extract(cSource);
  Assert.AreEqual('RATIONALE'#9'0'#9'Unit fuer den Test', String.Join('|', mOriginal.Rationale));
  Assert.IsTrue(FindSymbol(mOriginal, 'TFoo', mSymbol));
  Assert.AreEqual('WHY'#9'4'#9'siehe ADR-0007', String.Join('|', mSymbol.Rationale));
  Assert.IsTrue(FindSymbol(mOriginal, 'TFoo.FWert', mSymbol));
  Assert.AreEqual('NOTE'#9'6'#9'Feld ohne Getter', String.Join('|', mSymbol.Rationale));
  // Implementierung: Begründung im Rumpf.
  mFound := False;
  for mSymbol in mOriginal.Symbols do
  begin
    if SameText(mSymbol.QualifiedName, 'TFoo.Lauf') and not mSymbol.InInterface then
    begin
      mFound := True;
      Assert.AreEqual('HACK'#9'13'#9'bis #312 behoben ist', String.Join('|', mSymbol.Rationale));
    end;
  end;
  Assert.IsTrue(mFound);
  mLoaded := TIndexCache.Deserialize(TIndexCache.Serialize([mOriginal]))[0];
  Assert.AreEqual(String.Join('|', mOriginal.Rationale), String.Join('|', mLoaded.Rationale));
  Assert.IsTrue(FindSymbol(mLoaded, 'TFoo', mSymbol));
  Assert.AreEqual(1, Integer(Length(TRationale.DecodeAll(mSymbol.Rationale))));
  Assert.AreEqual('ADR-0007', Copy(TRationale.DecodeAll(mSymbol.Rationale)[0].Text, 7, 8));
end;

procedure TIndexCacheTests.RejectsOtherVersionAndBrokenData;
var
  Data: TBytes;
begin
  // Frühere Formate (JSON, Zeilenformat 10), fremde und abgeschnittene Daten.
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.Deserialize(TEncoding.UTF8.GetBytes('{"version":999,"units":[]}'))));
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.Deserialize(TEncoding.UTF8.GetBytes('ATLAS-INDEX'#9'10'#10))));
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.Deserialize(nil)));
  Data := TIndexCache.Serialize([Extract(UnitA)]);
  Assert.AreEqual<NativeInt>(1, Length(TIndexCache.Deserialize(Data)));
  // Andere Version: das Byte nach der Kennung.
  Data[8] := Data[8] + 1;
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.Deserialize(Data)));
  Data := TIndexCache.Serialize([Extract(UnitA)]);
  SetLength(Data, Length(Data) - 5);
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.ReadEntries(Data)));
  Assert.AreNotEqual(TIndexCache.HashOf('a'), TIndexCache.HashOf('b'));
end;

procedure TIndexCacheTests.ReadsHeadersAndExpandsSymbolsOnDemand;
var
  Original, U: TUnitIndex;
  Entries: TArray<TIndexCacheEntry>;
begin
  Original := Extract(UnitA);
  Original.Stamp := 42;
  Original.Includes := ['C:\Inc\a.inc'];
  Original.IncludeStamps := [-1];
  Entries := TIndexCache.ReadEntries(TIndexCache.Serialize([Original]));
  Assert.AreEqual<NativeInt>(1, Length(Entries));
  // Kopf vollständig, Symbole noch nicht dekodiert.
  Assert.AreEqual('A', Entries[0].Header.UnitName);
  Assert.AreEqual<Int64>(42, Entries[0].Header.Stamp);
  Assert.AreEqual('B', Entries[0].Header.InterfaceUses[1]);
  Assert.AreEqual<Int64>(-1, Entries[0].Header.IncludeStamps[0]);
  Assert.AreEqual<NativeInt>(0, Length(Entries[0].Header.Symbols));
  Assert.IsFalse(Entries[0].Expanded);
  Assert.IsTrue(TIndexCache.Expand(Entries[0], U));
  Assert.AreEqual<NativeInt>(Length(Original.Symbols), Length(U.Symbols));
  Assert.AreEqual('C', U.ImplementationUses[0]);
end;

procedure TIndexCacheTests.SharesEqualStringsAfterLoading;
var
  First, Second: TUnitIndex;
  Symbol: TIndexSymbol;
  Loaded: TArray<TUnitIndex>;
begin
  // Gleiche Texte stehen einmal in der String-Tabelle und teilen sich nach dem Laden eine Instanz.
  Symbol := Default(TIndexSymbol);
  Symbol.Name := 'Wert';
  Symbol.TypeName := 'TDictionary<string,Integer>';
  First := Default(TUnitIndex);
  First.UnitName := 'Erste';
  First.FileName := 'C:\Erste.pas';
  First.Symbols := [Symbol];
  Second := First;
  Second.UnitName := 'Zweite';
  Second.FileName := 'C:\Zweite.pas';
  Loaded := TIndexCache.Deserialize(TIndexCache.Serialize([First, Second]));
  Assert.AreEqual<NativeInt>(2, Length(Loaded));
  Assert.AreEqual(Symbol.TypeName, Loaded[1].Symbols[0].TypeName);
  Assert.IsTrue(Pointer(Loaded[0].Symbols[0].TypeName) = Pointer(Loaded[1].Symbols[0].TypeName));
end;

procedure TIndexCacheTests.RejectsDamagedSymbolBlock;
var
  Data: TBytes;
  Entries: TArray<TIndexCacheEntry>;
  U: TUnitIndex;
begin
  Data := TIndexCache.Serialize([Extract(UnitA)]);
  Entries := TIndexCache.ReadEntries(Data);
  Assert.AreEqual<NativeInt>(1, Length(Entries));
  // Verweis auf einen Text weit hinter der Tabelle.
  Data[Entries[0].SymbolOffset] := $FF;
  Data[Entries[0].SymbolOffset + 1] := $7F;
  Assert.IsFalse(TIndexCache.Expand(Entries[0], U));
  Assert.AreEqual<NativeInt>(0, Length(U.Symbols));
end;

{ TIndexProjectFilesTests }

procedure TIndexProjectFilesTests.ListsMainSourceAndUnitsOnce;
var
  Project: TProjectInfo;
  Files: TArray<string>;
  A, B: TProjectUnit;
begin
  Project := Default(TProjectInfo);
  Project.MainSource := 'C:\P\P.dpr';
  A.Name := 'A';
  A.FileName := 'C:\P\A.pas';
  B.Name := 'B';
  B.FileName := 'c:\p\a.PAS';
  Project.Units := [A, B];
  Files := TIndexProjectFiles.Files(Project);
  Assert.AreEqual<NativeInt>(2, Length(Files));
  Assert.AreEqual('C:\P\P.dpr', Files[0]);
  Assert.AreEqual('C:\P\A.pas', Files[1]);
end;

procedure TIndexProjectFilesTests.ListsPathUnitsOnceWithoutExcluded;
var
  Listed: string;
  Files: TArray<string>;
begin
  Listed := '';
  Files := TIndexProjectFiles.PathFiles(['C:\A', 'c:\a\', ' C:\B ', ''],
    function(const AFolder: string): TArray<string>
    begin
      Listed := Listed + AFolder + ';';
      if SameText(AFolder, 'C:\A') then
      begin
        Result := ['C:\A\Z.pas', 'C:\A\Y.pas'];
      end
      else
      begin
        Result := ['C:\B\W.pas', 'C:\B\Demos\X.pas', 'c:\a\y.pas'];
      end;
    end,
    function(const AFileName: string): Boolean
    begin
      Result := Pos('\DEMOS\', AnsiUpperCase(AFileName)) > 0;
    end, ['C:\A\Z.pas']);
  // Jeder Ordner einmal; Z steht schon im Projekt, X ist ausgeschlossen, Y doppelt.
  Assert.AreEqual('C:\A;C:\B;', Listed);
  Assert.AreEqual(2, Integer(Length(Files)));
  Assert.AreEqual('C:\A\Y.pas', Files[0]);
  Assert.AreEqual('C:\B\W.pas', Files[1]);
end;

{ TIndexSchedulerTests }

/// <summary>Abbruchprüfung, die die Warteschlange merkt und abbricht, sobald der Aufbau 100 ms wartet
/// (höchstens 50 Prüfungen).</summary>
function QueueProbe(AScheduler: TIndexScheduler; var AQueue: TIndexSchedulerQueue;
  var APolls: Integer): TIndexCancelled;
var
  mQueue: ^TIndexSchedulerQueue;
  mPolls: PInteger;
begin
  mQueue := @AQueue;
  mPolls := @APolls;
  Result :=
    function: Boolean
    begin
      mQueue^ := AScheduler.Queue;
      Inc(mPolls^);
      Result := (mQueue^.OldestWaitMs >= 100) or (mPolls^ >= 50);
    end;
end;

procedure TIndexSchedulerTests.OrdersByStageThenPriority;
var
  Scheduler: TIndexScheduler;
  Active, Other: IIndexTurn;
  Cancelled: TIndexCancelled;
begin
  Cancelled :=
    function: Boolean
    begin
      Result := True;
    end;
  Scheduler := TIndexScheduler.Create;
  try
    Other := Scheduler.Register(1);
    Active := Scheduler.Register(0);
    Assert.AreEqual(2, Integer(Scheduler.Count));
    // Das aktive Projekt (Priorität 0) kommt in derselben Stufe zuerst.
    Assert.IsFalse(Other.Enter(TIndexStage.Project, Cancelled));
    Assert.IsTrue(Active.Enter(TIndexStage.Project, Cancelled));
    Assert.IsFalse(Other.Enter(TIndexStage.Project, Cancelled), 'Läuft ein Aufbau, warten die anderen');
    Active.Leave;
    // Die Projektdateien des anderen Projekts kommen vor den Suchpfaden des aktiven.
    Assert.IsFalse(Active.Enter(TIndexStage.SearchPaths, Cancelled));
    Assert.IsTrue(Other.Enter(TIndexStage.Project, Cancelled));
    Other.Leave;
    Assert.IsTrue(Active.Enter(TIndexStage.SearchPaths, Cancelled));
    Active.Leave;
    Active := nil;
    Assert.AreEqual(1, Integer(Scheduler.Count), 'Freigabe meldet ab');
    Assert.IsTrue(Other.Enter(TIndexStage.Library_, Cancelled));
    Other.Leave;
    Other := nil;
  finally
    Scheduler.Free;
  end;
end;

procedure TIndexSchedulerTests.QueueCountsWaitingBuilds;
var
  mScheduler: TIndexScheduler;
  mActive, mOther: IIndexTurn;
  mQueue: TIndexSchedulerQueue;
  mPolls: Integer;
begin
  mScheduler := TIndexScheduler.Create;
  try
    mActive := mScheduler.Register(0);
    mOther := mScheduler.Register(1);
    Assert.AreEqual(0, mScheduler.Queue.Running);
    Assert.IsTrue(mActive.Enter(TIndexStage.Project, nil));
    // Ohne zweiten Thread: Die Abbruchprüfung des Wartenden liest die Warteschlange, bis er 100 ms wartet.
    mPolls := 0;
    Assert.IsFalse(mOther.Enter(TIndexStage.Project, QueueProbe(mScheduler, mQueue, mPolls)));
    Assert.AreEqual(1, mQueue.Running);
    Assert.AreEqual(1, mQueue.Waiting);
    Assert.IsTrue(mQueue.OldestWaitMs >= 100, IntToStr(mQueue.OldestWaitMs));
    Assert.AreEqual(0, mScheduler.Queue.Waiting, 'abgebrochen wartet er nicht mehr');
    mActive.Leave;
    Assert.AreEqual(0, mScheduler.Queue.Running);
    mActive := nil;
    mOther := nil;
  finally
    mScheduler.Free;
  end;
end;

procedure TIndexProjectFilesTests.SharesLibraryAcrossProjectDefines;
var
  Debug, Release: TProjectInfo;
  Define: string;
  HasWin64: Boolean;
begin
  // Ein Bibliotheks-Cache für alle Projekte und Konfigurationen derselben Plattform (#647).
  Debug := Default(TProjectInfo);
  Debug.Platform := 'Win64';
  Debug.Defines := ['DEBUG', 'APP'];
  Release := Debug;
  Release.Defines := ['RELEASE'];
  Assert.AreEqual(TIndexProjectFiles.LibrarySignature(Debug, '37.0'),
    TIndexProjectFiles.LibrarySignature(Release, '37.0'));
  Release.Platform := 'Win32';
  Assert.AreNotEqual(TIndexProjectFiles.LibrarySignature(Debug, '37.0'),
    TIndexProjectFiles.LibrarySignature(Release, '37.0'));
  HasWin64 := False;
  for Define in TIndexProjectFiles.LibraryDefines(Debug, '37.0') do
  begin
    Assert.AreNotEqual('DEBUG', Define);
    HasWin64 := HasWin64 or (Define = 'WIN64');
  end;
  Assert.IsTrue(HasWin64);
end;

procedure TIndexProjectFilesTests.CombinesDefinesWithPlatformSymbols;
var
  Project: TProjectInfo;
  Defines: TArray<string>;
  Define: string;
  HasDebug, HasWin64, HasVer: Boolean;
  Signature: string;
begin
  Project := Default(TProjectInfo);
  Project.Platform := 'Win64';
  Project.Defines := ['DEBUG'];
  Defines := TIndexProjectFiles.Defines(Project, '37.0');
  HasDebug := False;
  HasWin64 := False;
  HasVer := False;
  for Define in Defines do
  begin
    HasDebug := HasDebug or (Define = 'DEBUG');
    HasWin64 := HasWin64 or (Define = 'WIN64');
    HasVer := HasVer or (Define = 'VER370');
  end;
  Assert.IsTrue(HasDebug);
  Assert.IsTrue(HasWin64);
  Assert.IsTrue(HasVer);
  Assert.AreNotEqual(TIndexProjectFiles.Signature(Project, '37.0'), TIndexProjectFiles.Signature(Project, '36.0'));
  // Geänderte Symbole, Suchpfade oder Namespaces machen den Cache ungültig, die Reihenfolge der Symbole nicht.
  Signature := TIndexProjectFiles.Signature(Project, '37.0');
  Project.Defines := ['debug'];
  Assert.AreEqual(Signature, TIndexProjectFiles.Signature(Project, '37.0'));
  Project.Defines := ['DEBUG', 'TRACE'];
  Assert.AreNotEqual(Signature, TIndexProjectFiles.Signature(Project, '37.0'));
  Project.Defines := ['DEBUG'];
  Project.SearchPaths := ['C:\Lib'];
  Assert.AreNotEqual(Signature, TIndexProjectFiles.Signature(Project, '37.0'));
  Project.SearchPaths := nil;
  Project.Namespaces := ['Vcl'];
  Assert.AreNotEqual(Signature, TIndexProjectFiles.Signature(Project, '37.0'));
  Project.Namespaces := nil;
  // Schalter der .dproj für $IFOPT (#847) stehen in den Defines und im Schlüssel.
  Project.Properties := [TPair<string, string>.Create('DCC_RangeChecking', 'true')];
  Assert.AreNotEqual(Signature, TIndexProjectFiles.Signature(Project, '37.0'));
  HasDebug := False;
  for Define in TIndexProjectFiles.Defines(Project, '37.0') do
  begin
    HasDebug := HasDebug or (Define = '$R+');
  end;
  Assert.IsTrue(HasDebug);
  Project.Properties := nil;
  // Delphi 12: BDS 23.0 ergibt VER360, nicht VER230.
  HasVer := False;
  for Define in TIndexProjectFiles.Defines(Project, '23.0') do
  begin
    Assert.AreNotEqual('VER230', Define);
    HasVer := HasVer or (Define = 'VER360');
  end;
  Assert.IsTrue(HasVer);
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexExtractorTests);
  TDUnitX.RegisterTestFixture(TSymbolIndexTests);
  TDUnitX.RegisterTestFixture(TIndexCacheTests);
  TDUnitX.RegisterTestFixture(TIndexProjectFilesTests);
  TDUnitX.RegisterTestFixture(TIndexSchedulerTests);

end.
