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
    /// <summary>Ohne Änderung liefert Units denselben Schnappschuss (kein Kopieren).</summary>
    [Test]
    procedure UnitsSnapshotReusedWithoutChange;
    [Test]
    procedure UnitsSnapshotRenewedAfterChange;
    /// <summary>UnavailableUnits nur mit Deklarationen aus nicht geltenden Zweigen.</summary>
    [Test]
    procedure UnavailableUnitsOnlyAffected;
    /// <summary>InternUnit außerhalb der Index-Sperre; parallele AddUnit verlieren nichts.</summary>
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
    /// <summary>#2142: Stufe und Warten je Aufbau für „Atlas-Einrichtung“, auch ohne Scheduler.</summary>
    [Test]
    procedure StageWatchFollowsTurn;
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
  cUnitA =
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
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Cache,
  Atlas.Common.Rationale.Contract,
  Atlas.Common.Index.Builder,
  Atlas.Common.Index.Service,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.Index.ProjectFiles;

function Extract(const AText: string; const ADefines: TArray<string>): TUnitIndex; overload;
begin
  Result := TIndexExtractor.ExtractText(AText, 'C:\Projekt\A.pas', ADefines);
end;

function Extract(const AText: string): TUnitIndex; overload;
begin
  Result := Extract(AText, nil);
end;

function FindSymbol(const AUnit: TUnitIndex; const AQualifiedName: string; out ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.QualifiedName, AQualifiedName) then
    begin
      ASymbol := mSymbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

function Count(const AUnit: TUnitIndex; const AQualifiedName: string): Integer;
var
  mSymbol: TIndexSymbol;
begin
  Result := 0;
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.QualifiedName, AQualifiedName) then
    begin
      Inc(Result);
    end;
  end;
end;

function MakeUnit(const AName, AFileName: string; const ASymbols: array of string;
  const AAncestor: string): TUnitIndex; overload;
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

function MakeUnit(const AName, AFileName: string; const ASymbols: array of string): TUnitIndex; overload;
begin
  Result := MakeUnit(AName, AFileName, ASymbols, '');
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
  mAfter: TProc<string>;
begin
  if FFailReads then
  begin
    raise EInOutError.Create('simuliert');
  end;
  TMonitor.Enter(Self);
  try
    Inc(FReads);
    Result := FBytes.TryGetValue(UpperCase(AFileName), ABytes);
    mAfter := FAfterRead;
  finally
    TMonitor.Exit(Self);
  end;
  if Assigned(mAfter) then
  begin
    mAfter(AFileName);
  end;
end;

function TMemoryIndexFileSystem.WriteBytes(const AFileName: string; const ABytes: TBytes;
  out AError: string): Boolean;
var
  mStamp: Int64;
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
    if not FStamps.TryGetValue(UpperCase(AFileName), mStamp) then
    begin
      mStamp := 0;
    end;
    FStamps.AddOrSetValue(UpperCase(AFileName), mStamp + 1);
    Result := True;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMemoryIndexFileSystem.WriteBytes(const AFileName: string; const ABytes: TBytes): Boolean;
var
  mError: string;
begin
  Result := WriteBytes(AFileName, ABytes, mError);
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
  U := Extract(cUnitA);
  Assert.AreEqual('A', U.UnitName);
  Assert.IsTrue(FindSymbol(U, 'TFoo', S));
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.ClassType, S.Kind);
  Assert.AreEqual(6, S.SelectionRange.StartPos.Line);
  Assert.AreEqual(2, S.SelectionRange.StartPos.Character);
  Assert.IsTrue(FindSymbol(U, 'TFoo.FValue', S));
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Field, S.Kind);
  Assert.IsTrue(FindSymbol(U, 'TFoo.Value', S));
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Property_, S.Kind);
  Assert.IsTrue(FindSymbol(U, 'TFoo.Create', S));
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Constructor_, S.Kind);
  // Deklaration im interface und Rumpf in implementation
  Assert.AreEqual(2, Count(U, 'TFoo.Run'));
  Assert.IsTrue(FindSymbol(U, 'TFarbe.Gruen', S));
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.EnumMember, S.Kind);
  Assert.IsTrue(FindSymbol(U, 'Max', S));
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Constant, S.Kind);
  Assert.IsTrue(FindSymbol(U, 'Global', S));
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Variable, S.Kind);
  Assert.AreEqual(2, Count(U, 'Hilfe'));
end;

procedure TIndexExtractorTests.ExtractsAncestors;
var
  U: TUnitIndex;
  S: TIndexSymbol;
begin
  U := Extract(cUnitA);
  Assert.IsTrue(FindSymbol(U, 'TFoo', S));
  Assert.AreEqual<NativeInt>(2, Length(S.Ancestors));
  Assert.AreEqual('TBase', S.Ancestors[0]);
  Assert.AreEqual('IInterface', S.Ancestors[1]);
  Assert.IsTrue(FindSymbol(U, 'TBase', S));
  Assert.AreEqual<NativeInt>(0, Length(S.Ancestors));
end;

procedure TIndexExtractorTests.ExtractsAncestorArgsOfEveryAncestor;
const
  cText = 'unit G;'#10'interface'#10'type'#10 +
    '  TVergleich = class(TInterfacedObject, IComparer<TKunde>, IMap<string, TArray<Integer>>)'#10'  end;'#10 +
    '  TListe = class(TObjectList<TKunde>)'#10'  end;'#10 +
    '  TEinfach = class(TObject, IInterface)'#10'  end;'#10 +
    'implementation'#10'end.';
var
  U: TUnitIndex;
  mLoaded: TArray<TUnitIndex>;
  S: TIndexSymbol;
begin
  U := Extract(cText);
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
  mLoaded := TIndexCache.Deserialize(TIndexCache.Serialize([U]));
  Assert.IsTrue(FindSymbol(mLoaded[0], 'TVergleich', S));
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
  U := Extract(cUnitA);
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
  mSeen: Boolean;
begin
  U := Extract(cUnitA);
  Assert.IsTrue(FindSymbol(U, 'TFoo', S));
  Assert.IsTrue(S.InInterface);
  mSeen := False;
  for S in U.Symbols do
  begin
    if (S.QualifiedName = 'TFoo.Run') and not S.InInterface then
    begin
      mSeen := True;
    end;
  end;
  Assert.IsTrue(mSeen, 'Rumpf in implementation');
end;

procedure TIndexExtractorTests.SkipsInactiveBranches;
const
  cSource =
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
  U := Extract(cSource, ['MSWINDOWS']);
  Assert.IsTrue(FindSymbol(U, 'NurWindows', S));
  Assert.AreEqual(3, S.SelectionRange.StartPos.Line);
  Assert.IsFalse(FindSymbol(U, 'NurAndere', S));
  U := Extract(cSource, []);
  Assert.IsFalse(FindSymbol(U, 'NurWindows', S));
  Assert.IsTrue(FindSymbol(U, 'NurAndere', S));
  Assert.AreEqual(5, S.SelectionRange.StartPos.Line);
end;

procedure TIndexExtractorTests.RecordsConditionsAndUnavailableDeclarations;
const
  cSource =
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
  mSymbol: TIndexSymbol;
  mConditions, mMissing: string;
begin
  U := TIndexExtractor.ExtractText(cSource, 'C:\P\Plattform.pas', ['WIN32', 'MSWINDOWS']);
  mConditions := '';
  for mSymbol in U.Symbols do
  begin
    if mSymbol.Container = '' then
    begin
      mConditions := mConditions + mSymbol.Name + '=' + mSymbol.Condition + ';';
    end;
  end;
  Assert.Contains(mConditions, 'TNur32=not WIN64;');
  Assert.Contains(mConditions, 'TImmer=;');
  Assert.Contains(mConditions, 'NurWindows=MSWINDOWS;');
  Assert.Contains(mConditions, 'Alt=platform;');
  Assert.DoesNotContain(mConditions, 'TNur64');
  mMissing := '';
  for mSymbol in U.Unavailable do
  begin
    mMissing := mMissing + mSymbol.Name + '=' + mSymbol.Condition + ';';
  end;
  Assert.AreEqual('TNur64=WIN64;', mMissing);
  Assert.IsTrue(U.Unavailable[0].InInterface);
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.ClassType, U.Unavailable[0].Kind);
end;

procedure TIndexExtractorTests.KeepsShortStringLengthInSignature;
var
  U: TUnitIndex;
  mSymbol: TIndexSymbol;
  mFound: string;
begin
  U := TIndexExtractor.ExtractText('unit Satz;'#10'interface'#10'const'#10'  Laenge = 4;'#10'type'#10 +
    '  TSatz = record'#10'    Kennung: string[8];'#10'    Kurz: string[Laenge];'#10'    Name: string;'#10 +
    '    Liste: TList<string>;'#10'  end;'#10'var'#10'  Global: string [ 5 ];'#10'implementation'#10'end.',
    'Satz.pas', nil);
  mFound := '';
  for mSymbol in U.Symbols do
  begin
    if mSymbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Variable] then
    begin
      mFound := mFound + mSymbol.Signature + '|' + mSymbol.TypeName + #10;
    end;
  end;
  Assert.AreEqual('Kennung: string[8]|string'#10'Kurz: string[Laenge]|string'#10'Name: string|string'#10 +
    'Liste: TList<string>|TList'#10'Global: string[5]|string'#10, mFound);
end;

procedure TIndexExtractorTests.RecordsConditionsOfMembers;
const
  cSource =
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
  mSymbol: TIndexSymbol;
  mConditions, mMissing: string;
begin
  U := TIndexExtractor.ExtractText(cSource, 'C:\P\Mitglieder.pas', ['WIN32', 'MSWINDOWS']);
  mConditions := '';
  for mSymbol in U.Symbols do
  begin
    if mSymbol.Container = 'TGeraet' then
    begin
      mConditions := mConditions + mSymbol.Name + '=' + mSymbol.Condition + ';';
    end;
  end;
  Assert.Contains(mConditions, 'FHandle32=not WIN64;');
  Assert.Contains(mConditions, 'Nur32=not WIN64;');
  Assert.Contains(mConditions, 'Immer=;');
  mMissing := '';
  for mSymbol in U.Unavailable do
  begin
    mMissing := mMissing + mSymbol.Container + '.' + mSymbol.Name + '=' + mSymbol.Condition + ';';
  end;
  Assert.AreEqual('TGeraet.FHandle64=WIN64;TGeraet.FExtra=WIN64;TGeraet.Nur64=WIN64;TGeraet.Groesse64=WIN64;',
    mMissing);
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Field, U.Unavailable[0].Kind);
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Method, U.Unavailable[2].Kind);
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Property_, U.Unavailable[3].Kind);
  Assert.AreEqual(15, U.Unavailable[1].SelectionRange.StartPos.Character, 'Spalte des zweiten Felds');
end;

procedure TIndexExtractorTests.RecordsUnavailableImplementationRoutines;
const
  cSource =
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
  mSymbol: TIndexSymbol;
  mMissing: string;
begin
  U := TIndexExtractor.ExtractText(cSource, 'C:\P\Start.pas', ['WIN32', 'MSWINDOWS']);
  mMissing := '';
  for mSymbol in U.Unavailable do
  begin
    mMissing := mMissing + mSymbol.Name + '=' + mSymbol.Condition + ';';
  end;
  Assert.AreEqual('ApplyAppIcon=FPC;', mMissing);
  Assert.IsFalse(U.Unavailable[0].InInterface);
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Routine, U.Unavailable[0].Kind);
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
  mIndex: ISymbolIndex;
  U: TUnitIndex;
  mFound: TArray<TSymbolLocation>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('A', 'C:\A.pas', ['TFoo', 'TBar']));
  mIndex.AddUnit(MakeUnit('B', 'C:\B.pas', ['TFoo']));
  Assert.IsTrue(mIndex.FindUnit('a', U));
  Assert.AreEqual('C:\A.pas', U.FileName);
  Assert.IsTrue(mIndex.FindFile('c:\b.PAS', U));
  Assert.AreEqual('B', U.UnitName);
  mFound := mIndex.FindSymbols('tfoo');
  Assert.AreEqual<NativeInt>(2, Length(mFound));
  Assert.AreEqual(2, mIndex.UnitCount);
  Assert.AreEqual(3, mIndex.SymbolCount);
  Assert.IsFalse(mIndex.FindUnit('Z', U));
end;

procedure TSymbolIndexTests.ReplacesUnitOfSameFile;
var
  mIndex: ISymbolIndex;
  U: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('A', 'C:\A.pas', ['TFoo', 'TBar']));
  mIndex.AddUnit(MakeUnit('A', 'C:\a.pas', ['TNeu']));
  Assert.AreEqual(1, mIndex.UnitCount);
  Assert.AreEqual(1, mIndex.SymbolCount);
  Assert.AreEqual<NativeInt>(0, Length(mIndex.FindSymbols('TFoo')));
  mIndex.RemoveFile('C:\A.PAS');
  Assert.AreEqual(0, mIndex.UnitCount);
  Assert.IsFalse(mIndex.FindUnit('A', U));
end;

procedure TSymbolIndexTests.FindsDescendants;
var
  mIndex: ISymbolIndex;
  mFound: TArray<TSymbolLocation>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('A', 'C:\A.pas', ['TBase']));
  mIndex.AddUnit(MakeUnit('B', 'C:\B.pas', ['TKind'], 'A.TBase'));
  mIndex.AddUnit(MakeUnit('C', 'C:\C.pas', ['TListe'], 'TList<TBase>'));
  mFound := mIndex.Descendants('TBase');
  Assert.AreEqual<NativeInt>(1, Length(mFound));
  Assert.AreEqual('TKind', mFound[0].Symbol.Name);
  Assert.AreEqual<NativeInt>(1, Length(mIndex.Descendants('TList')));
end;

procedure TSymbolIndexTests.FindSymbolsMatchesWholeNamesOnly;
var
  mIndex: ISymbolIndex;
  mFound: TArray<TSymbolLocation>;
begin
  // Vorprüfung über die Länge (#647): gleich lange und längere Namen dürfen nicht treffen.
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('A', 'C:\A.pas', ['TFooBar', 'TFoo', 'TFo']));
  mIndex.AddUnit(MakeUnit('B', 'C:\B.pas', ['TBaz', 'TFOO']));
  mFound := mIndex.FindSymbols('tfoo');
  Assert.AreEqual<NativeInt>(2, Length(mFound));
  Assert.IsTrue(SameText('TFoo', mFound[0].Symbol.Name));
  Assert.IsTrue(SameText('TFoo', mFound[1].Symbol.Name));
  Assert.AreEqual<NativeInt>(0, Length(mIndex.FindSymbols('TFooB')));
end;

procedure TSymbolIndexTests.HasSymbolStopsAtFirstMatch;
var
  mIndex: ISymbolIndex;
  mCalls: Integer;
  mUnits: string;
begin
  // Ja/Nein-Fragen ohne Fundstellenliste (#1342): dieselben Symbole wie FindSymbols, Ende beim ersten Treffer.
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('A', 'C:\A.pas', ['TFooBar', 'TFoo']));
  mIndex.AddUnit(MakeUnit('B', 'C:\B.pas', ['TBaz', 'TFOO']));
  mCalls := 0;
  mUnits := '';
  Assert.IsFalse(mIndex.HasSymbol('tfoo',
    function(const ASymbol: TIndexSymbol): Boolean
    begin
      Inc(mCalls);
      mUnits := mUnits + ASymbol.Name + ';';
      Result := False;
    end));
  Assert.AreEqual(2, mCalls, 'alle gleichnamigen Symbole');
  Assert.AreEqual('TFOO;TFOO;', UpperCase(mUnits));
  mCalls := 0;
  Assert.IsTrue(mIndex.HasSymbol('TFoo',
    function(const ASymbol: TIndexSymbol): Boolean
    begin
      Inc(mCalls);
      Result := True;
    end));
  Assert.AreEqual(1, mCalls, 'Ende beim ersten Treffer');
  mCalls := 0;
  Assert.IsFalse(mIndex.HasSymbol('TFooB',
    function(const ASymbol: TIndexSymbol): Boolean
    begin
      Inc(mCalls);
      Result := True;
    end));
  Assert.AreEqual(0, mCalls, 'unbekannter Name');
  mIndex.RemoveFile('C:\A.pas');
  mCalls := 0;
  Assert.IsFalse(mIndex.HasSymbol('TFoo',
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
  mIndex: ISymbolIndex;
  mFound: TArray<TSymbolLocation>;
  mRound: Integer;
begin
  // Ersetzte Units lassen tote Verweise zurück; nach genug Runden werden die Tabellen neu gebaut
  // (Diagnoselog 15.10.2026). Weder vorher noch danach darf ein alter Stand auftauchen.
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('B', 'C:\B.pas', ['TFoo'], 'TBase'));
  for mRound := 1 to 3 * TSymbolIndex.cRebuildDeadRefs do
  begin
    if Odd(mRound) then
    begin
      mIndex.AddUnit(MakeUnit('A', 'C:\A.pas', ['TFoo', 'TBar'], 'TBase'));
    end
    else
    begin
      mIndex.AddUnit(MakeUnit('A', 'C:\A.pas', ['TBar', 'TFoo', 'TBaz'], 'X.TBase'));
    end;
  end;
  mFound := mIndex.FindSymbols('TFoo');
  Assert.AreEqual<NativeInt>(2, Length(mFound));
  Assert.AreEqual<NativeInt>(1, Length(mIndex.FindSymbols('TBaz')));
  Assert.AreEqual<NativeInt>(4, Length(mIndex.Descendants('TBase')));
  mIndex.RemoveFile('C:\A.pas');
  mFound := mIndex.FindSymbols('TFoo');
  Assert.AreEqual<NativeInt>(1, Length(mFound));
  Assert.AreEqual('B', mFound[0].UnitName);
  Assert.AreEqual<NativeInt>(0, Length(mIndex.FindSymbols('TBar')));
  Assert.AreEqual<NativeInt>(1, Length(mIndex.Descendants('TBase')));
end;

procedure TSymbolIndexTests.LookupsFollowCompaction;
var
  mIndex: ISymbolIndex;
  U: TUnitIndex;
  mFound: TArray<TSymbolLocation>;
begin
  // Kompakt gehaltene Units verlieren Symbole; die Positionen verschieben sich.
  U := MakeUnit('A', 'C:\A.pas', ['TIntern', 'TOeffentlich']);
  U.Library_ := True;
  U.Symbols[1].InInterface := True;
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(U);
  mIndex.SetBudget(1);
  Assert.AreEqual(1, mIndex.CompactCount);
  Assert.AreEqual<NativeInt>(0, Length(mIndex.FindSymbols('TIntern')));
  mFound := mIndex.FindSymbols('TOeffentlich');
  Assert.AreEqual<NativeInt>(1, Length(mFound));
  Assert.AreEqual('TOeffentlich', mFound[0].Symbol.Name);
  Assert.AreEqual('C:\A.pas', mFound[0].FileName);
end;

procedure TSymbolIndexTests.DescendantsListSymbolOnce;
var
  mIndex: ISymbolIndex;
  U: TUnitIndex;
begin
  U := MakeUnit('A', 'C:\A.pas', ['TKind']);
  U.Symbols[0].Ancestors := ['A.TBase', 'TBase<Integer>', 'IBase'];
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(U);
  Assert.AreEqual<NativeInt>(1, Length(mIndex.Descendants('TBase')));
  Assert.AreEqual<NativeInt>(1, Length(mIndex.Descendants('Unit.IBase')));
  Assert.AreEqual<NativeInt>(0, Length(mIndex.Descendants('')));
end;

procedure TSymbolIndexTests.SymbolsNamedUsesTableOfStoredUnit;
var
  mIndex: ISymbolIndex;
  U, mFound: TUnitIndex;
  mPositions: TArray<Integer>;
begin
  // Diagnoselog 15.10.2026: Die Namensauflösung sucht über die Tabelle der abgelegten Unit.
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('A', 'C:\A.pas', ['Foo', 'Bar', 'foo']));
  Assert.IsTrue(mIndex.FindUnit('A', mFound));
  Assert.IsNotNull(mFound.NameTable);
  mPositions := mFound.SymbolsNamed('FOO');
  Assert.AreEqual<NativeInt>(2, Length(mPositions));
  Assert.AreEqual(0, mPositions[0]);
  Assert.AreEqual(2, mPositions[1]);
  Assert.AreEqual<NativeInt>(0, Length(mFound.SymbolsNamed('Fehlt')));
  // Ersetzte Fassung: neue Tabelle, alte Positionen gelten nicht mehr.
  U := MakeUnit('A', 'C:\A.pas', ['Bar', 'Foo']);
  mIndex.AddUnit(U);
  Assert.IsTrue(mIndex.FindUnit('A', mFound));
  mPositions := mFound.SymbolsNamed('foo');
  Assert.AreEqual<NativeInt>(1, Length(mPositions));
  Assert.AreEqual(1, mPositions[0]);
end;

procedure TSymbolIndexTests.SymbolsNamedFallsBackForChangedSymbols;
var
  mIndex: ISymbolIndex;
  mFound: TUnitIndex;
  mPositions: TArray<Integer>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('A', 'C:\A.pas', ['Foo']));
  Assert.IsTrue(mIndex.FindUnit('A', mFound));
  // Neues Array in der Kopie: die Tabelle passt nicht mehr, gesucht wird linear.
  mFound.Symbols := Copy(mFound.Symbols) + MakeUnit('B', 'C:\B.pas', ['Neu', 'Foo']).Symbols;
  mPositions := mFound.SymbolsNamed('Foo');
  Assert.AreEqual<NativeInt>(2, Length(mPositions));
  Assert.AreEqual(2, mPositions[1]);
  Assert.AreEqual<NativeInt>(1, Length(mFound.SymbolsNamed('neu')));
  // Ohne Tabelle (Unit nie im Index) ebenso.
  mFound := MakeUnit('C', 'C:\C.pas', ['X', 'Y', 'x']);
  Assert.IsNull(mFound.NameTable);
  Assert.AreEqual<NativeInt>(2, Length(mFound.SymbolsNamed('X')));
end;

procedure TSymbolIndexTests.UnitsSnapshotReusedWithoutChange;
var
  mIndex: ISymbolIndex;
  mFirst, mSecond: TArray<TUnitIndex>;
  mFound: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('A', 'C:\A.pas', ['Foo']));
  mIndex.AddUnit(MakeUnit('B', 'C:\B.pas', ['Bar']));
  mFirst := mIndex.Units;
  mSecond := mIndex.Units;
  Assert.AreEqual<NativeInt>(2, Length(mFirst));
  Assert.AreEqual<Pointer>(Pointer(mSecond), Pointer(mFirst));
  // Lesende Zugriffe ändern den Stand nicht.
  Assert.IsTrue(mIndex.FindUnit('A', mFound));
  mIndex.FindSymbols('Foo');
  Assert.AreEqual<Pointer>(Pointer(mIndex.Units), Pointer(mFirst));
end;

procedure TSymbolIndexTests.UnitsSnapshotRenewedAfterChange;
var
  mIndex: ISymbolIndex;
  mFirst, mSecond: TArray<TUnitIndex>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('A', 'C:\A.pas', ['Foo']));
  mFirst := mIndex.Units;
  mIndex.AddUnit(MakeUnit('B', 'C:\B.pas', ['Bar']));
  mSecond := mIndex.Units;
  Assert.AreNotEqual<Pointer>(Pointer(mSecond), Pointer(mFirst));
  Assert.AreEqual<NativeInt>(1, Length(mFirst));
  Assert.AreEqual<NativeInt>(2, Length(mSecond));
  // Ersetzen derselben Datei.
  mIndex.AddUnit(MakeUnit('B', 'C:\B.pas', ['Bar', 'Baz']));
  mFirst := mIndex.Units;
  Assert.AreNotEqual<Pointer>(Pointer(mSecond), Pointer(mFirst));
  Assert.AreEqual<NativeInt>(2, Length(mFirst));
  mIndex.RemoveFile('C:\A.pas');
  mSecond := mIndex.Units;
  Assert.AreEqual<NativeInt>(1, Length(mSecond));
  Assert.AreEqual('B', mSecond[0].UnitName);
  Assert.AreEqual<NativeInt>(2, Length(mSecond[0].Symbols));
end;

procedure TSymbolIndexTests.UnavailableUnitsOnlyAffected;
var
  mIndex: ISymbolIndex;
  mWithBranch: TUnitIndex;
  mFound: TArray<TUnitIndex>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('A', 'C:\A.pas', ['Foo']));
  mWithBranch := MakeUnit('B', 'C:\B.pas', ['Bar']);
  mWithBranch.Unavailable := MakeUnit('B', 'C:\B.pas', ['NurDebug']).Symbols;
  mIndex.AddUnit(mWithBranch);
  mFound := mIndex.UnavailableUnits;
  Assert.AreEqual<NativeInt>(1, Length(mFound));
  Assert.AreEqual('B', mFound[0].UnitName);
  Assert.AreEqual('NurDebug', mFound[0].Unavailable[0].Name);
  // Neue Fassung ohne nicht geltende Zweige: fällt heraus.
  mIndex.AddUnit(MakeUnit('B', 'C:\B.pas', ['Bar']));
  Assert.AreEqual<NativeInt>(0, Length(mIndex.UnavailableUnits));
  mIndex.AddUnit(mWithBranch);
  Assert.AreEqual<NativeInt>(1, Length(mIndex.UnavailableUnits));
  mIndex.RemoveFile('C:\B.pas');
  Assert.AreEqual<NativeInt>(0, Length(mIndex.UnavailableUnits));
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
  cThreadCount = 4;
  cPerThread = 100;
var
  mIndex: ISymbolIndex;
  mThreads: array[0..cThreadCount - 1] of TThread;
  mNumber: Integer;
  mFirst, mLast: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  for mNumber := 0 to cThreadCount - 1 do
  begin
    mThreads[mNumber] := AddUnitsThread(mIndex, mNumber, cPerThread);
  end;
  try
    for mNumber := 0 to cThreadCount - 1 do
    begin
      mThreads[mNumber].Start;
    end;
    for mNumber := 0 to cThreadCount - 1 do
    begin
      mThreads[mNumber].WaitFor;
    end;
  finally
    for mNumber := 0 to cThreadCount - 1 do
    begin
      mThreads[mNumber].Free;
    end;
  end;
  Assert.AreEqual(cThreadCount * cPerThread, mIndex.UnitCount);
  Assert.AreEqual<NativeInt>(cThreadCount * cPerThread, Length(mIndex.Units));
  Assert.AreEqual<NativeInt>(cThreadCount * cPerThread, Length(mIndex.FindSymbols('Gemeinsam')));
  // Der Pool teilt gleiche Zeichenketten auch zwischen den Threads.
  Assert.IsTrue(mIndex.FindUnit('U0_1', mFirst));
  Assert.IsTrue(mIndex.FindUnit('U3_100', mLast));
  Assert.AreEqual<Pointer>(Pointer(mLast.Symbols[0].Name), Pointer(mFirst.Symbols[0].Name));
end;

{ TIndexCacheTests }

procedure TIndexCacheTests.RoundTripsUnits;
var
  mOriginal, U: TUnitIndex;
  mLoaded: TArray<TUnitIndex>;
  S: TIndexSymbol;
begin
  mOriginal := Extract(cUnitA);
  mOriginal.Stamp := 1234567890123;
  mOriginal.Hash := TIndexCache.HashOf(cUnitA);
  mLoaded := TIndexCache.Deserialize(TIndexCache.Serialize([mOriginal]));
  Assert.AreEqual<NativeInt>(1, Length(mLoaded));
  U := mLoaded[0];
  Assert.AreEqual('A', U.UnitName);
  Assert.AreEqual(mOriginal.FileName, U.FileName);
  Assert.AreEqual<Int64>(1234567890123, U.Stamp);
  Assert.AreEqual(mOriginal.Hash, U.Hash);
  Assert.AreEqual<NativeInt>(Length(mOriginal.Symbols), Length(U.Symbols));
  Assert.AreEqual('C', U.ImplementationUses[0]);
  Assert.IsTrue(FindSymbol(U, 'TFoo', S));
  Assert.AreEqual('IInterface', S.Ancestors[1]);
  Assert.IsTrue(S.InInterface);
  Assert.AreEqual(6, S.SelectionRange.StartPos.Line);
  Assert.IsTrue(FindSymbol(U, 'TFoo.Value', S));
  Assert.AreEqual<TIndexSymbolKind>(TIndexSymbolKind.Property_, S.Kind);
end;

procedure TIndexCacheTests.RoundTripsSpecialCharactersAndFlags;
var
  mOriginal, U: TUnitIndex;
  mLoaded: TArray<TUnitIndex>;
  mSymbol: TIndexSymbol;
begin
  // #617: Zeilenformat mit Escapes für Tabulator, Zeilenende, "|" und "\".
  mOriginal := Default(TUnitIndex);
  mOriginal.UnitName := 'Sonder';
  mOriginal.FileName := 'C:\Pfad mit|Strich\Sonder.pas';
  mOriginal.Library_ := True;
  mOriginal.HasInitialization := True;
  mOriginal.Includes := ['C:\Inc\a.inc', 'C:\Inc\b|c.inc'];
  mOriginal.IncludeStamps := [11, 22];
  mOriginal.Naming[TNamingKind.Field].Total := 7;
  mOriginal.Naming[TNamingKind.Field].Prefixed := 5;
  mOriginal.Naming[TNamingKind.Local].Total := 300;
  mOriginal.Directives := ['deprecated', 'platform'];
  mOriginal.DeprecatedText := 'Nutze Neu';
  mSymbol := Default(TIndexSymbol);
  mSymbol.Name := 'TListe';
  mSymbol.TypeName := 'TDictionary<string,Integer>';
  mSymbol.Condition := 'defined(A)'#9'and'#13#10'B';
  mSymbol.ParamTypes := ['string', 'array of Integer'];
  mSymbol.Unavailable := True;
  mOriginal.Unavailable := [mSymbol];
  mSymbol.Unavailable := False;
  mOriginal.Symbols := [mSymbol];
  mLoaded := TIndexCache.Deserialize(TIndexCache.Serialize([mOriginal]));
  Assert.AreEqual<NativeInt>(1, Length(mLoaded));
  U := mLoaded[0];
  Assert.AreEqual(mOriginal.FileName, U.FileName);
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
  Assert.AreEqual(mSymbol.Condition, U.Symbols[0].Condition);
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
  mData: TBytes;
begin
  // Frühere Formate (JSON, Zeilenformat 10), fremde und abgeschnittene Daten.
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.Deserialize(TEncoding.UTF8.GetBytes('{"version":999,"units":[]}'))));
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.Deserialize(TEncoding.UTF8.GetBytes('ATLAS-INDEX'#9'10'#10))));
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.Deserialize(nil)));
  mData := TIndexCache.Serialize([Extract(cUnitA)]);
  Assert.AreEqual<NativeInt>(1, Length(TIndexCache.Deserialize(mData)));
  // Andere Version: das Byte nach der Kennung.
  mData[8] := mData[8] + 1;
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.Deserialize(mData)));
  mData := TIndexCache.Serialize([Extract(cUnitA)]);
  SetLength(mData, Length(mData) - 5);
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.ReadEntries(mData)));
  Assert.AreNotEqual(TIndexCache.HashOf('a'), TIndexCache.HashOf('b'));
end;

procedure TIndexCacheTests.ReadsHeadersAndExpandsSymbolsOnDemand;
var
  mOriginal, U: TUnitIndex;
  mEntries: TArray<TIndexCacheEntry>;
begin
  mOriginal := Extract(cUnitA);
  mOriginal.Stamp := 42;
  mOriginal.Includes := ['C:\Inc\a.inc'];
  mOriginal.IncludeStamps := [-1];
  mEntries := TIndexCache.ReadEntries(TIndexCache.Serialize([mOriginal]));
  Assert.AreEqual<NativeInt>(1, Length(mEntries));
  // Kopf vollständig, Symbole noch nicht dekodiert.
  Assert.AreEqual('A', mEntries[0].Header.UnitName);
  Assert.AreEqual<Int64>(42, mEntries[0].Header.Stamp);
  Assert.AreEqual('B', mEntries[0].Header.InterfaceUses[1]);
  Assert.AreEqual<Int64>(-1, mEntries[0].Header.IncludeStamps[0]);
  Assert.AreEqual<NativeInt>(0, Length(mEntries[0].Header.Symbols));
  Assert.IsFalse(mEntries[0].Expanded);
  Assert.IsTrue(TIndexCache.Expand(mEntries[0], U));
  Assert.AreEqual<NativeInt>(Length(mOriginal.Symbols), Length(U.Symbols));
  Assert.AreEqual('C', U.ImplementationUses[0]);
end;

procedure TIndexCacheTests.SharesEqualStringsAfterLoading;
var
  mFirst, mSecond: TUnitIndex;
  mSymbol: TIndexSymbol;
  mLoaded: TArray<TUnitIndex>;
begin
  // Gleiche Texte stehen einmal in der String-Tabelle und teilen sich nach dem Laden eine Instanz.
  mSymbol := Default(TIndexSymbol);
  mSymbol.Name := 'Wert';
  mSymbol.TypeName := 'TDictionary<string,Integer>';
  mFirst := Default(TUnitIndex);
  mFirst.UnitName := 'Erste';
  mFirst.FileName := 'C:\Erste.pas';
  mFirst.Symbols := [mSymbol];
  mSecond := mFirst;
  mSecond.UnitName := 'Zweite';
  mSecond.FileName := 'C:\Zweite.pas';
  mLoaded := TIndexCache.Deserialize(TIndexCache.Serialize([mFirst, mSecond]));
  Assert.AreEqual<NativeInt>(2, Length(mLoaded));
  Assert.AreEqual(mSymbol.TypeName, mLoaded[1].Symbols[0].TypeName);
  Assert.AreEqual<Pointer>(Pointer(mLoaded[1].Symbols[0].TypeName), Pointer(mLoaded[0].Symbols[0].TypeName));
end;

procedure TIndexCacheTests.RejectsDamagedSymbolBlock;
var
  mData: TBytes;
  mEntries: TArray<TIndexCacheEntry>;
  U: TUnitIndex;
begin
  mData := TIndexCache.Serialize([Extract(cUnitA)]);
  mEntries := TIndexCache.ReadEntries(mData);
  Assert.AreEqual<NativeInt>(1, Length(mEntries));
  // Verweis auf einen Text weit hinter der Tabelle.
  mData[mEntries[0].SymbolOffset] := $FF;
  mData[mEntries[0].SymbolOffset + 1] := $7F;
  Assert.IsFalse(TIndexCache.Expand(mEntries[0], U));
  Assert.AreEqual<NativeInt>(0, Length(U.Symbols));
end;

{ TIndexProjectFilesTests }

procedure TIndexProjectFilesTests.ListsMainSourceAndUnitsOnce;
var
  mProject: TProjectInfo;
  mFiles: TArray<string>;
  A, B: TProjectUnit;
begin
  mProject := Default(TProjectInfo);
  mProject.MainSource := 'C:\P\P.dpr';
  A.Name := 'A';
  A.FileName := 'C:\P\A.pas';
  B.Name := 'B';
  B.FileName := 'c:\p\a.PAS';
  mProject.Units := [A, B];
  mFiles := TIndexProjectFiles.Files(mProject);
  Assert.AreEqual<NativeInt>(2, Length(mFiles));
  Assert.AreEqual('C:\P\P.dpr', mFiles[0]);
  Assert.AreEqual('C:\P\A.pas', mFiles[1]);
end;

procedure TIndexProjectFilesTests.ListsPathUnitsOnceWithoutExcluded;
var
  mListed: string;
  mFiles: TArray<string>;
begin
  mListed := '';
  mFiles := TIndexProjectFiles.PathFiles(['C:\A', 'c:\a\', ' C:\B ', ''],
    function(const AFolder: string): TArray<string>
    begin
      mListed := mListed + AFolder + ';';
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
  Assert.AreEqual('C:\A;C:\B;', mListed);
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual('C:\A\Y.pas', mFiles[0]);
  Assert.AreEqual('C:\B\W.pas', mFiles[1]);
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
  mScheduler: TIndexScheduler;
  mActive, mOther: IIndexTurn;
  mCancelled: TIndexCancelled;
begin
  mCancelled :=
    function: Boolean
    begin
      Result := True;
    end;
  mScheduler := TIndexScheduler.Create;
  try
    mOther := mScheduler.Register(1);
    mActive := mScheduler.Register(0);
    Assert.AreEqual(2, Integer(mScheduler.Count));
    // Das aktive Projekt (Priorität 0) kommt in derselben Stufe zuerst.
    Assert.IsFalse(mOther.Enter(TIndexStage.Project, mCancelled));
    Assert.IsTrue(mActive.Enter(TIndexStage.Project, mCancelled));
    Assert.IsFalse(mOther.Enter(TIndexStage.Project, mCancelled), 'Läuft ein Aufbau, warten die anderen');
    mActive.Leave;
    // Die Projektdateien des anderen Projekts kommen vor den Suchpfaden des aktiven.
    Assert.IsFalse(mActive.Enter(TIndexStage.SearchPaths, mCancelled));
    Assert.IsTrue(mOther.Enter(TIndexStage.Project, mCancelled));
    mOther.Leave;
    Assert.IsTrue(mActive.Enter(TIndexStage.SearchPaths, mCancelled));
    mActive.Leave;
    mActive := nil;
    Assert.AreEqual(1, Integer(mScheduler.Count), 'Freigabe meldet ab');
    Assert.IsTrue(mOther.Enter(TIndexStage.Library_, mCancelled));
    mOther.Leave;
    mOther := nil;
  finally
    mScheduler.Free;
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

type
  /// <summary>Reihenfolge, die einmal den Abbruch fragt: wartet, bis er nein sagt (für
  /// StageWatchFollowsTurn).</summary>
  TProbeTurn = class(TInterfacedObject, IIndexTurn)
  public
    function Enter(AStage: TIndexStage; const ACancelled: TIndexCancelled): Boolean;
    procedure Leave;
  end;

function TProbeTurn.Enter(AStage: TIndexStage; const ACancelled: TIndexCancelled): Boolean;
begin
  Result := not (Assigned(ACancelled) and ACancelled());
end;

procedure TProbeTurn.Leave;
begin
  // Nichts freizugeben.
end;

/// <summary>Abbruchprüfung, die den Stand von AWatch merkt und mit ACancel antwortet.</summary>
function StageProbe(AWatch: TIndexStageWatch; var AState: TIndexStageState; ACancel: Boolean): TIndexCancelled;
var
  mState: ^TIndexStageState;
begin
  mState := @AState;
  Result :=
    function: Boolean
    begin
      mState^ := AWatch.State;
      Result := ACancel;
    end;
end;

procedure TIndexSchedulerTests.StageWatchFollowsTurn;
var
  mWatch: TIndexStageWatch;
  mTurn: IIndexTurn;
  mSeen: TIndexStageState;
begin
  mWatch := TIndexStageWatch.Create;
  try
    Assert.IsFalse(mWatch.State.Running);
    mTurn := mWatch.Watch(TProbeTurn.Create);
    // Während der Aufbau auf seine Reihe wartet: Stufe bekannt, wartet.
    mSeen := Default(TIndexStageState);
    Assert.IsTrue(mTurn.Enter(TIndexStage.SearchPaths, StageProbe(mWatch, mSeen, False)));
    Assert.IsTrue(mSeen.Running);
    Assert.IsTrue(mSeen.Waiting);
    Assert.AreEqual('searchPaths', mSeen.StageName);
    // Dran: läuft, wartet nicht mehr.
    Assert.IsTrue(mWatch.State.Running);
    Assert.IsFalse(mWatch.State.Waiting);
    mTurn.Leave;
    // Abgebrochen beim Warten: läuft nicht mehr.
    Assert.IsFalse(mTurn.Enter(TIndexStage.Library_, StageProbe(mWatch, mSeen, True)));
    Assert.AreEqual('library', mSeen.StageName);
    Assert.IsFalse(mWatch.State.Running);
    // Ohne Scheduler ist jede Stufe sofort dran.
    mTurn := mWatch.Watch(nil);
    Assert.IsTrue(mTurn.Enter(TIndexStage.Project, nil));
    Assert.AreEqual('projectFiles', mWatch.State.StageName);
    mTurn.Leave;
    mWatch.Clear;
    Assert.IsFalse(mWatch.State.Running);
    mTurn := nil;
  finally
    mWatch.Free;
  end;
end;

procedure TIndexProjectFilesTests.SharesLibraryAcrossProjectDefines;
var
  mDebug, mRelease: TProjectInfo;
  mDefine: string;
  mHasWin64: Boolean;
begin
  // Ein Bibliotheks-Cache für alle Projekte und Konfigurationen derselben Plattform (#647).
  mDebug := Default(TProjectInfo);
  mDebug.Platform := 'Win64';
  mDebug.Defines := ['DEBUG', 'APP'];
  mRelease := mDebug;
  mRelease.Defines := ['RELEASE'];
  Assert.AreEqual(TIndexProjectFiles.LibrarySignature(mDebug, '37.0'),
    TIndexProjectFiles.LibrarySignature(mRelease, '37.0'));
  mRelease.Platform := 'Win32';
  Assert.AreNotEqual(TIndexProjectFiles.LibrarySignature(mDebug, '37.0'),
    TIndexProjectFiles.LibrarySignature(mRelease, '37.0'));
  mHasWin64 := False;
  for mDefine in TIndexProjectFiles.LibraryDefines(mDebug, '37.0') do
  begin
    Assert.AreNotEqual('DEBUG', mDefine);
    mHasWin64 := mHasWin64 or (mDefine = 'WIN64');
  end;
  Assert.IsTrue(mHasWin64);
end;

procedure TIndexProjectFilesTests.CombinesDefinesWithPlatformSymbols;
var
  mProject: TProjectInfo;
  mDefines: TArray<string>;
  mDefine: string;
  mHasDebug, mHasWin64, mHasVer: Boolean;
  mSignature: string;
begin
  mProject := Default(TProjectInfo);
  mProject.Platform := 'Win64';
  mProject.Defines := ['DEBUG'];
  mDefines := TIndexProjectFiles.Defines(mProject, '37.0');
  mHasDebug := False;
  mHasWin64 := False;
  mHasVer := False;
  for mDefine in mDefines do
  begin
    mHasDebug := mHasDebug or (mDefine = 'DEBUG');
    mHasWin64 := mHasWin64 or (mDefine = 'WIN64');
    mHasVer := mHasVer or (mDefine = 'VER370');
  end;
  Assert.IsTrue(mHasDebug);
  Assert.IsTrue(mHasWin64);
  Assert.IsTrue(mHasVer);
  Assert.AreNotEqual(TIndexProjectFiles.Signature(mProject, '37.0'), TIndexProjectFiles.Signature(mProject, '36.0'));
  // Geänderte Symbole, Suchpfade oder Namespaces machen den Cache ungültig, die Reihenfolge der Symbole nicht.
  mSignature := TIndexProjectFiles.Signature(mProject, '37.0');
  mProject.Defines := ['debug'];
  Assert.AreEqual(mSignature, TIndexProjectFiles.Signature(mProject, '37.0'));
  mProject.Defines := ['DEBUG', 'TRACE'];
  Assert.AreNotEqual(mSignature, TIndexProjectFiles.Signature(mProject, '37.0'));
  mProject.Defines := ['DEBUG'];
  mProject.SearchPaths := ['C:\Lib'];
  Assert.AreNotEqual(mSignature, TIndexProjectFiles.Signature(mProject, '37.0'));
  mProject.SearchPaths := nil;
  mProject.Namespaces := ['Vcl'];
  Assert.AreNotEqual(mSignature, TIndexProjectFiles.Signature(mProject, '37.0'));
  mProject.Namespaces := nil;
  // Schalter der .dproj für $IFOPT (#847) stehen in den Defines und im Schlüssel.
  mProject.Properties := [TPair<string, string>.Create('DCC_RangeChecking', 'true')];
  Assert.AreNotEqual(mSignature, TIndexProjectFiles.Signature(mProject, '37.0'));
  mHasDebug := False;
  for mDefine in TIndexProjectFiles.Defines(mProject, '37.0') do
  begin
    mHasDebug := mHasDebug or (mDefine = '$R+');
  end;
  Assert.IsTrue(mHasDebug);
  mProject.Properties := nil;
  // Delphi 12: BDS 23.0 ergibt VER360, nicht VER230.
  mHasVer := False;
  for mDefine in TIndexProjectFiles.Defines(mProject, '23.0') do
  begin
    Assert.AreNotEqual('VER230', mDefine);
    mHasVer := mHasVer or (mDefine = 'VER360');
  end;
  Assert.IsTrue(mHasVer);
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexExtractorTests);
  TDUnitX.RegisterTestFixture(TSymbolIndexTests);
  TDUnitX.RegisterTestFixture(TIndexCacheTests);
  TDUnitX.RegisterTestFixture(TIndexProjectFilesTests);
  TDUnitX.RegisterTestFixture(TIndexSchedulerTests);

end.
