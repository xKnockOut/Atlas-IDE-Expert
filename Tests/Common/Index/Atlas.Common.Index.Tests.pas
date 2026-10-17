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
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const AFileName, AText: string; AStamp: Int64);
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    function ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
    function WriteBytes(const AFileName: string; const ABytes: TBytes): Boolean;
    procedure Delete(const AFileName: string);
    property Reads: Integer read FReads write FReads;
    /// <summary>ReadBytes bzw. WriteBytes lösen EInOutError aus (Cache nicht lesbar/schreibbar).</summary>
    property FailReads: Boolean read FFailReads write FFailReads;
    property FailWrites: Boolean read FFailWrites write FFailWrites;
  end;

  [TestFixture]
  TIndexExtractorTests = class
  public
    [Test]
    procedure ExtractsTypesMembersAndRoutines;
    [Test]
    procedure ExtractsAncestors;
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
    procedure RejectsOtherVersionAndBrokenData;
    [Test]
    procedure ReadsHeadersAndExpandsSymbolsOnDemand;
    [Test]
    procedure SharesEqualStringsAfterLoading;
    [Test]
    procedure RejectsDamagedSymbolBlock;
  end;

  [TestFixture]
  TIndexBuilderTests = class
  private
    FFiles: TMemoryIndexFileSystem;
    FFileSystem: IIndexFileSystem;
    FIndex: ISymbolIndex;
    function Resolve(const AUnitName: string): string;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure IndexesProjectAndReferencedUnits;
    [Test]
    procedure ReusesCacheWithoutReading;
    [Test]
    procedure ReparsesChangedFiles;
    [Test]
    procedure ReportsProgressAndCancels;
    [Test]
    procedure EnsureUnitIndexesOnDemand;
    [Test]
    procedure AppliesExternalChanges;
    [Test]
    procedure AppliesUnsavedTextOfKnownUnits;
    [Test]
    procedure ChangedIncludeReindexesUnit;
    [Test]
    procedure CachedIncludeUnitReusedUntilIncludeChanges;
    [Test]
    procedure DecodesOnlyUsedCacheEntries;
    [Test]
    procedure CompactLibraryCacheReusedUnderBudget;
    [Test]
    procedure ReleaseCacheDropsEntries;
    [Test]
    // Worker- bzw. Pool-Threads legen Verwaltungsdaten an, die erst nach dem Test freigegeben werden.
    [IgnoreMemoryLeaks]
    procedure ServiceBuildsInBackgroundAndWritesCache;
    [Test]
    procedure EnsureUnitDoesNotWaitForOtherRequests;
    [Test]
    procedure ReadOnlyServiceWaitsForOtherWriter;
    [Test]
    procedure ServiceSharesLibraryCache;
    [Test]
    procedure ReadOnlyServiceStopsWaitingAfterLimit;
    [Test]
    procedure IndexesSearchAndLibraryStages;
    [Test]
    procedure ReportsProjectStageBeforeSearchPaths;
    [Test]
    procedure SkipsUnitIndexedUnderOtherName;
    [Test]
    procedure ReadsInstallationUnitsWithoutProjectDefines;
    [Test]
    // Der Index-Dienst arbeitet in einem eigenen Thread; dessen Verwaltungsdaten bleiben bis Programmende.
    [IgnoreMemoryLeaks]
    procedure ServiceWritesCacheAfterProjectStage;
    /// <summary>Code-Review A-04: Fehler im Aufbau gehen genau einmal an OnError.</summary>
    [Test]
    [IgnoreMemoryLeaks]
    procedure ServiceReportsCacheWriteFailureOnce;
    [Test]
    [IgnoreMemoryLeaks]
    procedure ServiceReportsCacheReadFailure;
    [Test]
    [IgnoreMemoryLeaks]
    procedure ServiceSurvivesFailingErrorHandler;
  end;

  [TestFixture]
  TIndexSchedulerTests = class
  public
    [Test]
    procedure OrdersByStageThenPriority;
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

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Cache,
  Atlas.Common.Index.Builder,
  Atlas.Common.Index.Service,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.Index.ProjectFiles;

const
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

function Extract(const AText: string; const ADefines: TArray<string> = nil): TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(AText, 'C:\Projekt\A.pas', ADefines);
end;

function FindSymbol(const AUnit: TUnitIndex; const AQualifiedName: string; out ASymbol: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.QualifiedName, AQualifiedName) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
  Result := False;
end;

function Count(const AUnit: TUnitIndex; const AQualifiedName: string): Integer;
var
  Symbol: TIndexSymbol;
begin
  Result := 0;
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.QualifiedName, AQualifiedName) then
      Inc(Result);
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
      Result.Symbols[I].Ancestors := [AAncestor];
  end;
end;

{ TMemoryIndexFileSystem }

constructor TMemoryIndexFileSystem.Create;
begin
  inherited Create;
  FTexts := TDictionary<string, string>.Create;
  FBytes := TDictionary<string, TBytes>.Create;
  FStamps := TDictionary<string, Int64>.Create;
end;

destructor TMemoryIndexFileSystem.Destroy;
begin
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
begin
  if FFailReads then
    raise EInOutError.Create('simuliert');
  TMonitor.Enter(Self);
  try
    Inc(FReads);
    Result := FBytes.TryGetValue(UpperCase(AFileName), ABytes);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TMemoryIndexFileSystem.WriteBytes(const AFileName: string; const ABytes: TBytes): Boolean;
begin
  if FFailWrites then
    raise EInOutError.Create('simuliert');
  TMonitor.Enter(Self);
  try
    FBytes.AddOrSetValue(UpperCase(AFileName), ABytes);
    FStamps.AddOrSetValue(UpperCase(AFileName), 1);
    Result := True;
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
    if (S.QualifiedName = 'TFoo.Run') and not S.InInterface then
      Seen := True;
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
    if Symbol.Container = '' then
      Conditions := Conditions + Symbol.Name + '=' + Symbol.Condition + ';';
  Assert.Contains(Conditions, 'TNur32=not WIN64;');
  Assert.Contains(Conditions, 'TImmer=;');
  Assert.Contains(Conditions, 'NurWindows=MSWINDOWS;');
  Assert.Contains(Conditions, 'Alt=platform;');
  Assert.DoesNotContain(Conditions, 'TNur64');
  Missing := '';
  for Symbol in U.Unavailable do
    Missing := Missing + Symbol.Name + '=' + Symbol.Condition + ';';
  Assert.AreEqual('TNur64=WIN64;', Missing);
  Assert.IsTrue(U.Unavailable[0].InInterface);
  Assert.IsTrue(U.Unavailable[0].Kind = TIndexSymbolKind.ClassType);
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
    if Symbol.Container = 'TGeraet' then
      Conditions := Conditions + Symbol.Name + '=' + Symbol.Condition + ';';
  Assert.Contains(Conditions, 'FHandle32=not WIN64;');
  Assert.Contains(Conditions, 'Nur32=not WIN64;');
  Assert.Contains(Conditions, 'Immer=;');
  Missing := '';
  for Symbol in U.Unavailable do
    Missing := Missing + Symbol.Container + '.' + Symbol.Name + '=' + Symbol.Condition + ';';
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
    Missing := Missing + Symbol.Name + '=' + Symbol.Condition + ';';
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
  for Round := 1 to 3 * TSymbolIndex.RebuildDeadRefs do
    if Odd(Round) then
      Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['TFoo', 'TBar'], 'TBase'))
    else
      Index.AddUnit(MakeUnit('A', 'C:\A.pas', ['TBar', 'TFoo', 'TBaz'], 'X.TBase'));
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
        AIndex.AddUnit(MakeUnit(Format('U%d_%d', [AThread, Position]), Format('C:\U%d_%d.pas', [AThread, Position]),
          ['Gemeinsam', 'Eigen' + IntToStr(Position)]));
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
    Threads[Number] := AddUnitsThread(Index, Number, PerThread);
  try
    for Number := 0 to ThreadCount - 1 do
      Threads[Number].Start;
    for Number := 0 to ThreadCount - 1 do
      Threads[Number].WaitFor;
  finally
    for Number := 0 to ThreadCount - 1 do
      Threads[Number].Free;
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
  Assert.AreEqual<NativeInt>(1, Length(U.Symbols));
  Assert.AreEqual('TDictionary<string,Integer>', U.Symbols[0].TypeName);
  Assert.AreEqual(Symbol.Condition, U.Symbols[0].Condition);
  Assert.AreEqual('array of Integer', U.Symbols[0].ParamTypes[1]);
  Assert.AreEqual<NativeInt>(1, Length(U.Unavailable));
  Assert.IsTrue(U.Unavailable[0].Unavailable);
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

{ TIndexBuilderTests }

procedure TIndexBuilderTests.WarmUpFirstUse;
begin
  Setup;
  try
    ServiceSharesLibraryCache;
  finally
    TearDown;
  end;
end;

procedure TIndexBuilderTests.Setup;
begin
  FFiles := TMemoryIndexFileSystem.Create;
  FFileSystem := FFiles;
  FFiles.Put('C:\P\P.dpr', 'program P;'#10'uses A in ''A.pas'';'#10'begin end.', 1);
  FFiles.Put('C:\P\A.pas', UnitA, 1);
  FFiles.Put('C:\Lib\B.pas', 'unit B;'#10'interface'#10'uses D;'#10'type TB = class end;'#10'implementation'#10'uses E;'#10'end.', 1);
  FFiles.Put('C:\Lib\C.pas', 'unit C;'#10'interface'#10'implementation'#10'end.', 1);
  FFiles.Put('C:\Lib\D.pas', 'unit D;'#10'interface'#10'implementation'#10'end.', 1);
  FFiles.Put('C:\Lib\E.pas', 'unit E;'#10'interface'#10'implementation'#10'end.', 1);
  FFiles.Put('C:\Lib\F.pas', 'unit F;'#10'interface'#10'type TF = class end;'#10'implementation'#10'end.', 1);
  FIndex := TSymbolIndex.Create;
end;

procedure TIndexBuilderTests.TearDown;
begin
  FIndex := nil;
  FFileSystem := nil;
end;

function TIndexBuilderTests.Resolve(const AUnitName: string): string;
begin
  if SameText(AUnitName, 'System.SysUtils') then
    Result := ''
  else
    Result := 'C:\Lib\' + AUnitName + '.pas';
end;

procedure TIndexBuilderTests.IndexesProjectAndReferencedUnits;
var
  Builder: TIndexBuilder;
  BuildResult: TIndexBuildResult;
  U: TUnitIndex;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    BuildResult := Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  // P, A aus dem Projekt; B und C aus den uses von A; D aus dem interface von B.
  // E steht nur im implementation-Teil von B und bleibt draußen, F wird nie referenziert.
  Assert.AreEqual(5, BuildResult.Parsed);
  Assert.IsTrue(FIndex.FindUnit('B', U));
  Assert.IsTrue(FIndex.FindUnit('C', U));
  Assert.IsTrue(FIndex.FindUnit('D', U));
  Assert.IsFalse(FIndex.FindUnit('E', U));
  Assert.IsFalse(FIndex.FindUnit('F', U));
end;

procedure TIndexBuilderTests.IndexesSearchAndLibraryStages;
var
  Builder: TIndexBuilder;
  BuildResult: TIndexBuildResult;
  U: TUnitIndex;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    // F nur über den Suchpfad, E nur über den Bibliothekspfad; B kam schon über uses und wird nicht neu gelesen.
    BuildResult := Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], ['C:\Lib\F.pas'], ['C:\Lib\E.pas', 'C:\Lib\B.pas'],
      nil, nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(7, BuildResult.Parsed);
  Assert.IsTrue(FIndex.FindUnit('F', U));
  Assert.IsFalse(U.Library_, 'Suchpfad-Units gehören zum Projekt');
  Assert.IsTrue(FIndex.FindUnit('E', U));
  Assert.IsTrue(U.Library_, 'Bibliotheks-Units sind Bibliothek');
end;

procedure TIndexBuilderTests.ReportsProjectStageBeforeSearchPaths;
var
  Builder: TIndexBuilder;
  StageParsed: Integer;
  HadSearchUnit: Boolean;
  U: TUnitIndex;
begin
  StageParsed := -1;
  HadSearchUnit := True;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], ['C:\Lib\F.pas'], ['C:\Lib\E.pas'], nil, nil, nil,
      procedure(const APartial: TIndexBuildResult)
      begin
        StageParsed := APartial.Parsed;
        HadSearchUnit := FIndex.FindUnit('F', U);
      end);
  finally
    Builder.Free;
  end;
  // P, A, B, C, D: Projektdateien und über uses erreichbare Units (#647).
  Assert.AreEqual(5, StageParsed);
  Assert.IsFalse(HadSearchUnit, 'Suchpfade kommen erst nach der Projektstufe');
end;

procedure TIndexBuilderTests.SkipsUnitIndexedUnderOtherName;
var
  Builder: TIndexBuilder;
  BuildResult: TIndexBuildResult;
  ResolveScoped: TUnitFileResolver;
begin
  // "uses Forms" findet Vcl.Forms; im Index steht sie unter "Vcl.Forms" (#647).
  FFiles.Put('C:\Lib\Vcl.Forms.pas', 'unit Vcl.Forms;'#10'interface'#10'implementation'#10'end.', 1);
  FFiles.Put('C:\Q\Q1.pas', 'unit Q1;'#10'interface'#10'uses Forms;'#10'implementation'#10'end.', 1);
  FFiles.Put('C:\Q\Q2.pas', 'unit Q2;'#10'interface'#10'uses Forms;'#10'implementation'#10'end.', 1);
  ResolveScoped :=
    function(const AUnitName: string): string
    begin
      if SameText(AUnitName, 'Forms') then
        Result := 'C:\Lib\Vcl.Forms.pas'
      else
        Result := '';
    end;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, ResolveScoped);
  try
    BuildResult := Builder.Build(['C:\Q\Q1.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(2, BuildResult.Parsed);
  // Zweites Projekt mit demselben Index: Vcl.Forms ist schon da.
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, ResolveScoped);
  try
    BuildResult := Builder.Build(['C:\Q\Q2.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(1, BuildResult.Parsed, 'nur Q2');
end;

procedure TIndexBuilderTests.ReadsInstallationUnitsWithoutProjectDefines;
const
  Source = 'interface'#10'{$IFDEF APP}procedure NurApp;{$ENDIF}'#10'implementation'#10'end.';
var
  Builder: TIndexBuilder;
  ResolveScoped: TUnitFileResolver;
begin
  // RTL/VCL/FMX kommen als fertige DCUs: Projekt-Defines wirken dort nicht (#647).
  FFiles.Put('C:\BDS\source\rtl\RtlUnit.pas', 'unit RtlUnit;'#10 + Source, 1);
  FFiles.Put('C:\Firma\FirmaUnit.pas', 'unit FirmaUnit;'#10 + Source, 1);
  FFiles.Put('C:\P\Haupt.pas', 'unit Haupt;'#10'interface'#10'uses RtlUnit, FirmaUnit;'#10'implementation'#10'end.', 1);
  ResolveScoped :=
    function(const AUnitName: string): string
    begin
      if SameText(AUnitName, 'RtlUnit') then
        Result := 'C:\BDS\source\rtl\RtlUnit.pas'
      else if SameText(AUnitName, 'FirmaUnit') then
        Result := 'C:\Firma\FirmaUnit.pas'
      else
        Result := '';
    end;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, ['APP', 'MSWINDOWS'], ResolveScoped);
  try
    Builder.LibraryRoots := ['C:\BDS'];
    Builder.LibraryDefines := ['MSWINDOWS'];
    Builder.Build(['C:\P\Haupt.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('NurApp')), 'nur FirmaUnit');
  Assert.AreEqual('FirmaUnit', FIndex.FindSymbols('NurApp')[0].UnitName);
  Assert.IsTrue(TIndexBuilder.IsUnder('c:\bds\x.pas', ['C:\BDS\']));
  Assert.IsFalse(TIndexBuilder.IsUnder('C:\BDS2\x.pas', ['C:\BDS']));
end;

procedure TIndexBuilderTests.ServiceWritesCacheAfterProjectStage;
var
  Service: TIndexService;
  Request: TIndexRequest;
  StageUnits: NativeInt;
  Data: TBytes;
begin
  StageUnits := -1;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnProjectReady :=
      procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
      var
        StageData: TBytes;
      begin
        // In einer Projektgruppe endet der ganze Aufbau erst spät; der Cache muss vorher stehen (#647).
        if FFileSystem.ReadBytes('C:\Cache\index.json', StageData) then
          StageUnits := Length(TIndexCache.Deserialize(StageData));
      end;
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.SearchFiles := ['C:\Lib\F.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\index.json';
    Service.Start(Request);
    Service.WaitFor;
  finally
    Service.Free;
  end;
  Assert.AreEqual<NativeInt>(5, StageUnits);
  Assert.IsTrue(FFileSystem.ReadBytes('C:\Cache\index.json', Data));
  Assert.AreEqual<NativeInt>(6, Length(TIndexCache.Deserialize(Data)), 'am Ende mit Suchpfad-Unit');
end;

procedure TIndexBuilderTests.ReusesCacheWithoutReading;
var
  Builder: TIndexBuilder;
  Cache: TArray<TUnitIndex>;
  BuildResult: TIndexBuildResult;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Cache := TIndexCache.Deserialize(TIndexCache.Serialize(FIndex.Units));
  FIndex := TSymbolIndex.Create;
  FFiles.Reads := 0;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(0, BuildResult.Parsed);
  Assert.AreEqual(5, BuildResult.FromCache);
  Assert.AreEqual(0, FFiles.Reads);
  Assert.AreEqual(5, FIndex.UnitCount);
end;

procedure TIndexBuilderTests.ReparsesChangedFiles;
var
  Builder: TIndexBuilder;
  Cache: TArray<TUnitIndex>;
  BuildResult: TIndexBuildResult;
  Found: TArray<TSymbolLocation>;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.Build(['C:\Lib\C.pas', 'C:\Lib\D.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Cache := FIndex.Units;
  // C: neuer Zeitstempel, gleicher Inhalt → aus dem Cache. D: neuer Inhalt → neu einlesen.
  FFiles.Put('C:\Lib\C.pas', 'unit C;'#10'interface'#10'implementation'#10'end.', 2);
  FFiles.Put('C:\Lib\D.pas', 'unit D;'#10'interface'#10'type TNeu = class end;'#10'implementation'#10'end.', 2);
  FIndex := TSymbolIndex.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(['C:\Lib\C.pas', 'C:\Lib\D.pas', 'C:\Lib\Fehlt.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(1, BuildResult.Parsed);
  Assert.AreEqual(1, BuildResult.FromCache);
  Assert.AreEqual(1, BuildResult.Missing);
  Found := FIndex.FindSymbols('TNeu');
  Assert.AreEqual<NativeInt>(1, Length(Found));
end;

procedure TIndexBuilderTests.ReportsProgressAndCancels;
var
  Builder: TIndexBuilder;
  Events: TList<TIndexProgressKind>;
  BuildResult: TIndexBuildResult;
begin
  Events := TList<TIndexProgressKind>.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    BuildResult := Builder.Build(['C:\P\A.pas', 'C:\Lib\C.pas'],
      procedure(AKind: TIndexProgressKind; const AMessage: string; APercent: Integer)
      begin
        Events.Add(AKind);
      end,
      function: Boolean
      begin
        // Nach der ersten Datei abbrechen.
        Result := FIndex.UnitCount >= 1;
      end);
    Assert.IsTrue(BuildResult.Cancelled);
    Assert.AreEqual(1, FIndex.UnitCount);
    Assert.IsTrue(Events.First = TIndexProgressKind.Started);
    Assert.IsTrue(Events.Last = TIndexProgressKind.Finished);
  finally
    Builder.Free;
    Events.Free;
  end;
end;

procedure TIndexBuilderTests.EnsureUnitIndexesOnDemand;
var
  Builder: TIndexBuilder;
  U: TUnitIndex;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Assert.IsTrue(Builder.EnsureUnit('F'));
    Assert.IsTrue(FIndex.FindUnit('F', U));
    Assert.IsFalse(Builder.EnsureUnit('GibtEsNicht'));
    Assert.IsFalse(Builder.EnsureUnit('System.SysUtils'));
  finally
    Builder.Free;
  end;
end;

procedure TIndexBuilderTests.AppliesUnsavedTextOfKnownUnits;
var
  Builder: TIndexBuilder;
  U: TUnitIndex;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\Lib\D.pas'], nil, nil);
    // Getippt, nicht gespeichert: neue Klasse sofort im Index, Datei unverändert.
    Assert.IsTrue(Builder.ApplyText('C:\Lib\D.pas',
      'unit D;'#10'interface'#10'type TGetippt = class end;'#10'implementation'#10'end.'));
    Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('TGetippt')));
    Assert.IsTrue(FIndex.FindUnit('D', U));
    // Gleicher Text: nichts zu tun; unbekannte Datei: nichts.
    Assert.IsFalse(Builder.ApplyText('C:\Lib\D.pas',
      'unit D;'#10'interface'#10'type TGetippt = class end;'#10'implementation'#10'end.'));
    Assert.IsFalse(Builder.ApplyText('C:\Lib\Neu.pas', 'unit Neu;'#10'interface'#10'implementation'#10'end.'));
    // Schließen ohne Speichern: der Stand der Platte gilt wieder.
    Builder.ApplyChanges([TFileChange.Create('C:\Lib\D.pas', TFileChangeKind.Changed)]);
    Assert.AreEqual<NativeInt>(0, Length(FIndex.FindSymbols('TGetippt')));
  finally
    Builder.Free;
  end;
end;

procedure TIndexBuilderTests.AppliesExternalChanges;
var
  Builder: TIndexBuilder;
  U: TUnitIndex;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\Lib\C.pas', 'C:\Lib\D.pas'], nil, nil);
    Assert.IsFalse(Builder.EnsureUnit('G'));
    // D geändert, C gelöscht, G neu angelegt, F unbekannt und unverändert.
    FFiles.Put('C:\Lib\D.pas', 'unit D;'#10'interface'#10'type TNeu = class end;'#10'implementation'#10'end.', 2);
    FFiles.Delete('C:\Lib\C.pas');
    FFiles.Put('C:\Lib\G.pas', 'unit G;'#10'interface'#10'implementation'#10'end.', 2);
    Assert.AreEqual(2, Builder.ApplyChanges([TFileChange.Create('C:\Lib\D.pas', TFileChangeKind.Changed),
      TFileChange.Create('C:\Lib\C.pas', TFileChangeKind.Deleted),
      TFileChange.Create('C:\Lib\G.pas', TFileChangeKind.Created),
      TFileChange.Create('C:\Lib\F.pas', TFileChangeKind.Changed)]));
    Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('TNeu')));
    Assert.IsFalse(FIndex.FindUnit('C', U));
    Assert.IsFalse(FIndex.FindUnit('F', U));
    // Neue Dateien kommen erst bei Bedarf in den Index, auch wenn die Unit vorher fehlte.
    Assert.IsFalse(FIndex.FindUnit('G', U));
    Assert.IsTrue(Builder.EnsureUnit('G'));
  finally
    Builder.Free;
  end;
end;

procedure TIndexBuilderTests.ChangedIncludeReindexesUnit;
const
  UnitText = 'unit H;'#10'interface'#10'{$I C:\Inc\Schalter.inc}'#10 +
    '{$IFDEF NEU}type TMitNeu = class end;{$ELSE}type TOhneNeu = class end;{$ENDIF}'#10'implementation'#10'end.';
var
  Builder: TIndexBuilder;
  U: TUnitIndex;
begin
  // #264: $DEFINE aus der .inc wirkt; Änderung an der .inc liest H neu ein.
  FFiles.Put('C:\Inc\Schalter.inc', '{$DEFINE NEU}', 1);
  FFiles.Put('C:\Lib\H.pas', UnitText, 1);
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\Lib\H.pas'], nil, nil);
    Assert.IsTrue(FIndex.FindUnit('H', U));
    Assert.AreEqual<NativeInt>(1, Length(U.Includes));
    Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('TMitNeu')));
    FFiles.Put('C:\Inc\Schalter.inc', '', 2);
    Assert.AreEqual(1, Builder.ApplyChanges([TFileChange.Create('C:\Inc\Schalter.inc', TFileChangeKind.Changed)]));
    Assert.AreEqual<NativeInt>(0, Length(FIndex.FindSymbols('TMitNeu')));
    Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('TOhneNeu')));
  finally
    Builder.Free;
  end;
end;

procedure TIndexBuilderTests.CachedIncludeUnitReusedUntilIncludeChanges;
const
  UnitText = 'unit H;'#10'interface'#10'{$I C:\Inc\Schalter.inc}'#10 +
    '{$IFDEF NEU}type TMitNeu = class end;{$ENDIF}'#10'implementation'#10'end.';
var
  Builder: TIndexBuilder;
  Cache: TArray<TUnitIndex>;
  BuildResult: TIndexBuildResult;
begin
  // #617: Units mit Includes kommen aus dem Cache, solange keine Include-Datei sich ändert.
  FFiles.Put('C:\Inc\Schalter.inc', '{$DEFINE NEU}', 1);
  FFiles.Put('C:\Lib\H.pas', UnitText, 1);
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.Build(['C:\Lib\H.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Cache := TIndexCache.Deserialize(TIndexCache.Serialize(FIndex.Units));
  FIndex := TSymbolIndex.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(['C:\Lib\H.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(0, BuildResult.Parsed);
  Assert.AreEqual(1, BuildResult.FromCache);
  FFiles.Put('C:\Inc\Schalter.inc', '', 2);
  FIndex := TSymbolIndex.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(['C:\Lib\H.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(1, BuildResult.Parsed);
  Assert.AreEqual<NativeInt>(0, Length(FIndex.FindSymbols('TMitNeu')));
end;

procedure TIndexBuilderTests.CompactLibraryCacheReusedUnderBudget;
const
  UnitText = 'unit K;'#10'interface'#10'type TK = class end;'#10'implementation'#10 +
    'procedure Versteckt; begin end;'#10'end.';
var
  Builder: TIndexBuilder;
  Cache: TArray<TUnitIndex>;
  BuildResult: TIndexBuildResult;
begin
  // Diagnoselog 15.10.2026: Bei knappem Budget stehen Bibliotheken kompakt im Cache. Sie werden
  // wiederverwendet, solange ein Budget gilt; ohne Budget braucht es alle Symbole.
  FFiles.Put('C:\Lib\K.pas', UnitText, 1);
  FIndex.SetBudget(1);
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.Build(nil, nil, ['C:\Lib\K.pas'], nil, nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(1, FIndex.CompactCount);
  Cache := TIndexCache.Deserialize(TIndexCache.Serialize(FIndex.Units));
  Assert.IsTrue(Cache[0].Compact);
  FIndex := TSymbolIndex.Create;
  FIndex.SetBudget(1);
  FFiles.Reads := 0;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(nil, nil, ['C:\Lib\K.pas'], nil, nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(0, BuildResult.Parsed);
  Assert.AreEqual(1, BuildResult.FromCache);
  Assert.AreEqual(0, FFiles.Reads);
  FIndex := TSymbolIndex.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    BuildResult := Builder.Build(nil, nil, ['C:\Lib\K.pas'], nil, nil, nil);
  finally
    Builder.Free;
  end;
  Assert.AreEqual(1, BuildResult.Parsed, 'ohne Budget neu einlesen');
  Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('Versteckt')));
end;

procedure TIndexBuilderTests.ReleaseCacheDropsEntries;
var
  Builder: TIndexBuilder;
  Cache: TArray<TUnitIndex>;
begin
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.Build(['C:\Lib\C.pas', 'C:\Lib\D.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  Cache := FIndex.Units;
  FIndex := TSymbolIndex.Create;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, nil);
  try
    Builder.UseCache(Cache);
    Assert.AreEqual(2, Builder.CachedCount);
    Builder.Build(['C:\Lib\C.pas', 'C:\Lib\D.pas'], nil, nil);
    Builder.ReleaseCache;
    Assert.AreEqual(0, Builder.CachedCount);
    // Später nachgeladene Units liest der Builder aus der Datei.
    Assert.IsTrue(Builder.EnsureUnit('C'));
  finally
    Builder.Free;
  end;
end;

procedure TIndexBuilderTests.DecodesOnlyUsedCacheEntries;
var
  Builder: TIndexBuilder;
  Data: TBytes;
  Entries: TArray<TIndexCacheEntry>;
  Entry: TIndexCacheEntry;
  BuildResult: TIndexBuildResult;
begin
  // #617: Der Builder liest nur die Köpfe und dekodiert die Symbole der Units, die er übernimmt.
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], nil, nil);
    Assert.IsTrue(Builder.EnsureUnit('F'));
  finally
    Builder.Free;
  end;
  Data := TIndexCache.Serialize(FIndex.Units);
  Entries := TIndexCache.ReadEntries(Data);
  Assert.AreEqual<NativeInt>(6, Length(Entries));
  // Den Symbolblock von F nach dem Lesen der Köpfe beschädigen (in der Datei fiele das schon an der
  // Prüfsumme auf, #492); die Einträge teilen sich die Daten.
  for Entry in Entries do
    if SameText(Entry.Header.UnitName, 'F') then
    begin
      Entry.Data[Entry.SymbolOffset] := $FF;
      Entry.Data[Entry.SymbolOffset + 1] := $7F;
    end;
  FIndex := TSymbolIndex.Create;
  FFiles.Reads := 0;
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.UseCache(Entries);
    BuildResult := Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], nil, nil);
    Assert.AreEqual(0, BuildResult.Parsed);
    Assert.AreEqual(5, BuildResult.FromCache);
    Assert.AreEqual(0, FFiles.Reads);
    Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('TB')));
    // F wurde nie gebraucht; erst EnsureUnit stößt auf den beschädigten Block und liest die Datei.
    Assert.IsTrue(Builder.EnsureUnit('F'));
  finally
    Builder.Free;
  end;
  Assert.AreEqual(1, FFiles.Reads);
  Assert.AreEqual<NativeInt>(1, Length(FIndex.FindSymbols('TF')));
end;

procedure TIndexBuilderTests.EnsureUnitDoesNotWaitForOtherRequests;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Entered, Release: TEvent;
  Other: TThread;
  Watch: TStopwatch;
begin
  // #617: Eine Anfrage, die gerade eine Unit sucht und parst, hält die anderen nicht auf.
  Entered := TEvent.Create(nil, True, False, '');
  Release := TEvent.Create(nil, True, False, '');
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit :=
      function(const AUnitName: string): string
      begin
        if SameText(AUnitName, 'Langsam') then
        begin
          Entered.SetEvent;
          Release.WaitFor(5000);
          Exit('');
        end;
        Result := Resolve(AUnitName);
      end;
    Service.Start(Request);
    Service.WaitFor;
    Other := TThread.CreateAnonymousThread(
      procedure
      begin
        Service.EnsureUnit('Langsam');
      end);
    Other.FreeOnTerminate := False;
    Other.Start;
    try
      Assert.AreEqual(TWaitResult.wrSignaled, Entered.WaitFor(5000));
      Watch := TStopwatch.StartNew;
      Assert.IsTrue(Service.EnsureUnit('F'));
      // Mit der alten globalen Sperre hätte F bis zur Freigabe (5 s) gewartet.
      Assert.IsTrue(Watch.ElapsedMilliseconds < 2000, 'F wartete auf Langsam');
    finally
      Release.SetEvent;
      Other.WaitFor;
      Other.Free;
    end;
  finally
    Service.Free;
    Release.Free;
    Entered.Free;
  end;
end;

procedure TIndexBuilderTests.ServiceBuildsInBackgroundAndWritesCache;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Finished: Boolean;
  Data: TBytes;
begin
  Finished := False;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnFinished :=
      procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
      begin
        Finished := True;
      end;
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\index.json';
    Service.Start(Request);
    Service.WaitFor;
    Assert.IsTrue(Finished);
    Assert.AreEqual(5, Service.Index.UnitCount);
    Assert.IsTrue(Service.EnsureUnit('F'));
  finally
    Service.Free;
  end;
  Assert.IsTrue(FFileSystem.ReadBytes('C:\Cache\index.json', Data));
  Assert.AreEqual<NativeInt>(5, Length(TIndexCache.Deserialize(Data)));
end;

procedure TIndexBuilderTests.ServiceReportsCacheWriteFailureOnce;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Errors, Finished: Integer;
begin
  Errors := 0;
  Finished := 0;
  FFiles.FailWrites := True;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnFinished :=
      procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
      begin
        Inc(Finished);
      end;
    Service.OnError :=
      procedure(const AError: Exception)
      begin
        Inc(Errors);
      end;
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\index.json';
    Service.Start(Request);
    Service.WaitFor;
    Assert.AreEqual(1, Errors);
    Assert.AreEqual(0, Finished);
  finally
    Service.Free;
  end;
end;

procedure TIndexBuilderTests.ServiceReportsCacheReadFailure;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Errors: Integer;
  ErrorClass: string;
begin
  Errors := 0;
  ErrorClass := '';
  FFiles.FailReads := True;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnError :=
      procedure(const AError: Exception)
      begin
        Inc(Errors);
        ErrorClass := AError.ClassName;
      end;
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\index.json';
    Service.Start(Request);
    Service.WaitFor;
    Assert.AreEqual(1, Errors);
    Assert.AreEqual('EInOutError', ErrorClass);
    // Der Builder wurde nie veröffentlicht (und nicht geleakt): EnsureUnit findet nichts.
    Assert.IsFalse(Service.EnsureUnit('X'));
  finally
    Service.Free;
  end;
end;

procedure TIndexBuilderTests.ServiceSurvivesFailingErrorHandler;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Finished: Boolean;
begin
  Finished := False;
  FFiles.FailWrites := True;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnError :=
      procedure(const AError: Exception)
      begin
        raise EInvalidOpException.Create('Meldung scheitert');
      end;
    Service.OnFinished :=
      procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
      begin
        Finished := True;
      end;
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\index.json';
    Service.Start(Request);
    Service.WaitFor;
    Assert.IsFalse(Finished);
    // Der Thread endete geordnet; ein neuer Lauf ohne Fehler läuft durch.
    FFiles.FailWrites := False;
    Service.Start(Request);
    Service.WaitFor;
    Assert.IsTrue(Finished);
  finally
    Service.Free;
  end;
end;

procedure TIndexBuilderTests.ServiceSharesLibraryCache;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Data: TBytes;
  FromCache: Integer;
  UnitIndex: TUnitIndex;
begin
  // Erstes Projekt: Projekt-Units und Bibliothek getrennt (#492).
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\projekt1.json';
    Request.LibraryCacheFile := 'C:\Cache\bibliothek.json';
    Service.Start(Request);
    Service.WaitFor;
  finally
    Service.Free;
  end;
  Assert.IsTrue(FFileSystem.ReadBytes('C:\Cache\projekt1.json', Data));
  for UnitIndex in TIndexCache.Deserialize(Data) do
    Assert.IsFalse(UnitIndex.Library_, 'keine Bibliothek im Projekt-Cache: ' + UnitIndex.FileName);
  Assert.IsTrue(FFileSystem.ReadBytes('C:\Cache\bibliothek.json', Data));
  Assert.AreEqual<NativeInt>(3, Length(TIndexCache.Deserialize(Data)));
  // Zweites Projekt mit eigenem Cache: die Bibliothek kommt aus dem gemeinsamen.
  FIndex := TSymbolIndex.Create;
  FromCache := -1;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Service.OnFinished :=
      procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
      begin
        FromCache := AResult.FromCache;
      end;
    Request.CacheFile := 'C:\Cache\projekt2.json';
    Service.Start(Request);
    Service.WaitFor;
  finally
    Service.Free;
  end;
  Assert.AreEqual(3, FromCache, 'nur die Projekt-Units neu eingelesen');
end;

procedure TIndexBuilderTests.ReadOnlyServiceWaitsForOtherWriter;
const
  CacheFile = 'C:\Cache\index.json';
var
  Service: TIndexService;
  Request: TIndexRequest;
  Builder: TIndexBuilder;
  CacheData: TBytes;
  Busy: Boolean;
  Writer: TThread;
begin
  // Stand der anderen Instanz vorbereiten, aber noch nicht schreiben.
  Builder := TIndexBuilder.Create(FIndex, FFileSystem, nil, Resolve);
  try
    Builder.Build(['C:\P\P.dpr', 'C:\P\A.pas'], nil, nil);
  finally
    Builder.Free;
  end;
  CacheData := TIndexCache.Serialize(FIndex.Units);
  FIndex := TSymbolIndex.Create;
  Busy := True;
  // Die andere Instanz schreibt nach kurzer Zeit ihren Cache und gibt die Sperre frei.
  Writer := TThread.CreateAnonymousThread(
    procedure
    begin
      TThread.Sleep(300);
      FFileSystem.WriteBytes(CacheFile, CacheData);
      Busy := False;
    end);
  Writer.FreeOnTerminate := False;
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := CacheFile;
    Request.ReadOnlyCache := True;
    Request.CacheBusy :=
      function: Boolean
      begin
        Result := Busy;
      end;
    Request.CacheWaitMs := 10000;
    FFiles.Reads := 0;
    Writer.Start;
    Service.Start(Request);
    Service.WaitFor;
    // Nur der Cache wurde gelesen, keine Quelldatei.
    Assert.AreEqual(1, FFiles.Reads);
    Assert.AreEqual(5, Service.Index.UnitCount);
  finally
    Service.Free;
    Writer.WaitFor;
    Writer.Free;
  end;
end;

procedure TIndexBuilderTests.ReadOnlyServiceStopsWaitingAfterLimit;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Data: TBytes;
begin
  Service := TIndexService.Create(FIndex, FFileSystem);
  try
    Request := Default(TIndexRequest);
    Request.Files := ['C:\P\P.dpr', 'C:\P\A.pas'];
    Request.ResolveUnit := Resolve;
    Request.CacheFile := 'C:\Cache\index.json';
    Request.ReadOnlyCache := True;
    Request.CacheBusy :=
      function: Boolean
      begin
        Result := True;
      end;
    Request.CacheWaitMs := 300;
    Service.Start(Request);
    Service.WaitFor;
    Assert.AreEqual(5, Service.Index.UnitCount);
  finally
    Service.Free;
  end;
  // Nur lesend: kein Cache geschrieben.
  Assert.IsFalse(FFileSystem.ReadBytes('C:\Cache\index.json', Data));
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
        Result := ['C:\A\Z.pas', 'C:\A\Y.pas']
      else
        Result := ['C:\B\W.pas', 'C:\B\Demos\X.pas', 'c:\a\y.pas'];
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
  TDUnitX.RegisterTestFixture(TIndexBuilderTests);
  TDUnitX.RegisterTestFixture(TIndexProjectFilesTests);
  TDUnitX.RegisterTestFixture(TIndexSchedulerTests);

end.
