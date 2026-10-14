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
  end;

  [TestFixture]
  TIndexExtractorTests = class
  public
    [Test]
    procedure ExtractsTypesMembersAndRoutines;
    [Test]
    procedure ExtractsAncestors;
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
    [IgnoreMemoryLeaks]
    procedure ServiceWritesCacheAfterProjectStage;
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
  // Den Symbolblock von F beschädigen; die Köpfe bleiben lesbar.
  for Entry in TIndexCache.ReadEntries(Data) do
    if SameText(Entry.Header.UnitName, 'F') then
    begin
      Data[Entry.SymbolOffset] := $FF;
      Data[Entry.SymbolOffset + 1] := $7F;
    end;
  Entries := TIndexCache.ReadEntries(Data);
  Assert.AreEqual<NativeInt>(6, Length(Entries));
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
    Assert.AreEqual(2, Scheduler.Count);
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
    Assert.AreEqual(1, Scheduler.Count, 'Freigabe meldet ab');
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
