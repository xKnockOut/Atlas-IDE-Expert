unit Argus.Common.Index.Tests;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Argus.Common.Index.Contract;

type
  /// <summary>Dateisystem im Speicher; zählt Lesezugriffe.</summary>
  TMemoryIndexFileSystem = class(TInterfacedObject, IIndexFileSystem)
  private
    FTexts: TDictionary<string, string>;
    FStamps: TDictionary<string, Int64>;
    FReads: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const AFileName, AText: string; AStamp: Int64);
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
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
  end;

  [TestFixture]
  TIndexCacheTests = class
  public
    [Test]
    procedure RoundTripsUnits;
    [Test]
    procedure RejectsOtherVersionAndBrokenJson;
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
    procedure ChangedIncludeReindexesUnit;
    [Test]
    // Worker- bzw. Pool-Threads legen Verwaltungsdaten an, die erst nach dem Test freigegeben werden.
    [IgnoreMemoryLeaks]
    procedure ServiceBuildsInBackgroundAndWritesCache;
    [Test]
    procedure ReadOnlyServiceWaitsForOtherWriter;
    [Test]
    procedure ReadOnlyServiceStopsWaitingAfterLimit;
  end;

  [TestFixture]
  TIndexProjectFilesTests = class
  public
    [Test]
    procedure ListsMainSourceAndUnitsOnce;
    [Test]
    procedure CombinesDefinesWithPlatformSymbols;
  end;

implementation

uses
  Argus.Common.Documents.Contract,
  Argus.Common.Projects.Contract,
  Argus.Common.Index.Extractor,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Index.Cache,
  Argus.Common.Index.Builder,
  Argus.Common.Index.Service,
  Argus.Common.Index.ProjectFiles;

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
  FStamps := TDictionary<string, Int64>.Create;
end;

destructor TMemoryIndexFileSystem.Destroy;
begin
  FStamps.Free;
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

procedure TIndexCacheTests.RejectsOtherVersionAndBrokenJson;
begin
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.Deserialize('{"version":999,"units":[]}')));
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.Deserialize('{kaputt')));
  Assert.AreEqual<NativeInt>(0, Length(TIndexCache.Deserialize('')));
  Assert.AreNotEqual(TIndexCache.HashOf('a'), TIndexCache.HashOf('b'));
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

procedure TIndexBuilderTests.ServiceBuildsInBackgroundAndWritesCache;
var
  Service: TIndexService;
  Request: TIndexRequest;
  Finished: Boolean;
  Text: string;
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
  Assert.IsTrue(FFileSystem.ReadText('C:\Cache\index.json', Text));
  Assert.AreEqual<NativeInt>(5, Length(TIndexCache.Deserialize(Text)));
end;

procedure TIndexBuilderTests.ReadOnlyServiceWaitsForOtherWriter;
const
  CacheFile = 'C:\Cache\index.json';
var
  Service: TIndexService;
  Request: TIndexRequest;
  Builder: TIndexBuilder;
  CacheText: string;
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
  CacheText := TIndexCache.Serialize(FIndex.Units);
  FIndex := TSymbolIndex.Create;
  Busy := True;
  // Die andere Instanz schreibt nach kurzer Zeit ihren Cache und gibt die Sperre frei.
  Writer := TThread.CreateAnonymousThread(
    procedure
    begin
      TThread.Sleep(300);
      FFileSystem.WriteText(CacheFile, CacheText);
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
  Text: string;
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
  Assert.IsFalse(FFileSystem.ReadText('C:\Cache\index.json', Text));
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

end.
