unit Atlas.Common.Pascal.Parser.Robustness.Tests;

// Robustheit und Leistung des Parsers:
// - Fuzzing: gültigen Code zufällig beschädigen; der Parser darf weder
//   abstürzen noch hängen.
// - Extreme Verschachtelung und lange Ketten ohne Stapelüberlauf.
// - Korpustest: RTL- und VCL-Quellen der Delphi-Installation parsen
//   (Ordner aus ATLAS_CORPUS oder $(BDS)\source; ohne beides übersprungen).
// - Leistungsmessung mit festen Zielwerten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalParserRobustnessTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen (statt [IgnoreMemoryLeaks]): Thread mit
    /// eigenem Stapel, alle Regeln, Dateien suchen und mit Kodierungserkennung lesen. Was die RTL dabei beim
    /// ersten Mal anlegt, bleibt bis Programmende.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure FuzzingNeverCrashesOrHangs;
    [Test]
    procedure DeepNestingIsReportedNotFatal;
    [Test]
    procedure LongChainsDoNotOverflowStack;
    /// <summary>#1094: Lange Ketten von + (and, or, xor) werden ausgeglichen gebaut; Reihenfolge und
    /// Bereiche der Operanden bleiben erhalten.</summary>
    [Test]
    procedure LongConcatenationIsBalanced;
    /// <summary>#1094: Kurze Ketten und nicht assoziative Operatoren bleiben linkslastig wie bisher.</summary>
    [Test]
    procedure ShortChainsStayLeftDeep;
    /// <summary>#1094: Eine Verkettung wie in Rules.Catalog.Data.pas läuft mit allen eingebauten Regeln in
    /// 512 KB Stapel. Vorher lief hier der Stapel über und der Server startete neu.</summary>
    [Test]
    procedure LongConcatenationPassesAllRulesInSmallStack;
    [Test]
    procedure ParsesDelphiSourceCorpus;
    [Test]
    [Category('Benchmark')]
    procedure SyntaxDiagnosticsWithin200Ms;
    [Test]
    [Category('Benchmark')]
    procedure OutlineAndFoldingWithin100Ms;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  System.IOUtils,
  System.Diagnostics,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Common.Lsp.FoldingRanges,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Checker,
  Atlas.Tests.SmallStack;

const
  cFuzzSeed = 20261007;
  cFuzzRounds = 2000;
  /// <summary>Obergrenze je Parse; deutlich darüber gilt als Hänger.</summary>
  cHangLimitMs = 2000;

  cSamples: array[0..2] of string = (
    'unit Sample;'#13#10 +
    'interface'#13#10 +
    'uses System.SysUtils, System.Generics.Collections;'#13#10 +
    'type'#13#10 +
    '  [Attr(''x'')]'#13#10 +
    '  TList<T: class> = class(TInterfacedObject, IEnumerable)'#13#10 +
    '  strict private'#13#10 +
    '    FItems: array of T;'#13#10 +
    '    class var FCount: Integer;'#13#10 +
    '  public'#13#10 +
    '    constructor Create(const ACapacity: Integer = 4); overload;'#13#10 +
    '    function Map<R>(const F: TFunc<T, R>): TList<R>; virtual; abstract;'#13#10 +
    '    property Items[I: Integer]: T read GetItem write SetItem; default;'#13#10 +
    '  end;'#13#10 +
    '  TRec = packed record case Integer of 0: (A: Integer); 1: (B: Byte); end;'#13#10 +
    '  TCallback = procedure(A: Integer) of object;'#13#10 +
    'const Names: array[0..1] of string = (''a'', ''b'');'#13#10 +
    'implementation'#13#10 +
    'constructor TList<T>.Create(const ACapacity: Integer);'#13#10 +
    'var I: Integer;'#13#10 +
    'begin'#13#10 +
    '  inherited Create;'#13#10 +
    '  for var J := 0 to ACapacity - 1 do'#13#10 +
    '    if (J mod 2 = 0) and not Assigned(FItems[J]) then FItems[J] := nil else Continue;'#13#10 +
    '  case ACapacity of 1..2, 3: Exit; else raise EArgumentException.Create(''x''); end;'#13#10 +
    '  try I := 1 except on E: Exception do Writeln(E.Message); end;'#13#10 +
    '  TThread.Queue(nil, procedure begin Writeln(I) end);'#13#10 +
    'end;'#13#10 +
    'initialization'#13#10 +
    '  {$IFDEF DEBUG} Writeln(''debug''); {$ENDIF}'#13#10 +
    'end.',

    'program Demo;'#13#10 +
    '{$APPTYPE CONSOLE}'#13#10 +
    'uses A in ''a.pas'';'#13#10 +
    'var S: string; P: ^Integer;'#13#10 +
    'begin'#13#10 +
    '  S := ''''''zeile'#13#10'eins'''''''';'#13#10 +
    '  while P^ > 0 do begin Dec(P^); with S do repeat until True; end;'#13#10 +
    '  asm mov eax, 1 end;'#13#10 +
    '  // Kommentar (* alt *) { block }'#13#10 +
    'end.',

    'library L;'#13#10 +
    'type TObj = object procedure X; end; THelper = record helper for Integer function Twice: Integer; end;'#13#10 +
    'function F(var A; out B: Integer; const C: array of const): Boolean; stdcall;'#13#10 +
    'begin Result := @A <> nil; end;'#13#10 +
    'exports F;'#13#10 +
    'begin end.');

  cGarbage: array[0..9] of string = ('begin', 'end', '(', ')', '[', ']', ';', '''', '{', 'class');

// Beschädigt den Text zufällig: Zeichen löschen, abschneiden, Klammern und
// Schlüsselwörter einstreuen, Blöcke verdoppeln.
function Mutate(const AText: string): string;
var
  mRound: Integer;
  mPosition: Integer;
begin
  Result := AText;
  for mRound := 1 to 1 + Random(5) do
  begin
    if Result = '' then
    begin
      Exit;
    end;
    mPosition := Random(Length(Result));
    case Random(5) of
      0:
        Result := Result.Remove(mPosition, 1 + Random(20));
      1:
        Result := Result.Substring(0, mPosition);
      2:
        Result := Result.Insert(mPosition, cGarbage[Random(Length(cGarbage))]);
      3:
        Result := Result.Insert(mPosition, Result.Substring(Random(Length(Result)), Random(200)));
      4:
        Result := Result.Insert(mPosition, ' ' + cGarbage[Random(Length(cGarbage))] + ' ');
    end;
  end;
end;

function Repeated(const AText: string; ACount: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 1 to ACount do
    begin
      mBuilder.Append(AText);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

procedure ParseAndFree(const AText: string);
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  mTree.Free;
end;

function GenerateUnit(AClasses: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.AppendLine('unit Big;').AppendLine('interface').AppendLine('type');
    for mIndex := 1 to AClasses do
    begin
      mBuilder.AppendFormat('  TClass%d = class', [mIndex]).AppendLine
        .AppendLine('  private')
        .AppendLine('    FValue: Integer;')
        .AppendLine('  public')
        .AppendLine('    procedure Run(const A: string; B: Integer);')
        .AppendLine('    property Value: Integer read FValue write FValue;')
        .AppendLine('  end;');
    end;
    mBuilder.AppendLine('implementation');
    for mIndex := 1 to AClasses do
    begin
      mBuilder.AppendFormat('procedure TClass%d.Run(const A: string; B: Integer);', [mIndex]).AppendLine
        .AppendLine('var I: Integer;')
        .AppendLine('begin')
        .AppendLine('  for I := 0 to B do')
        .AppendLine('    if A <> '''' then FValue := FValue + Length(A) * I else Exit;')
        .AppendLine('end;');
    end;
    mBuilder.Append('end.');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ TPascalParserRobustnessTests }

procedure TPascalParserRobustnessTests.WarmUpFirstUse;
var
  mFolder, mFileName: string;
begin
  LongChainsDoNotOverflowStack;
  LongConcatenationPassesAllRulesInSmallStack;
  // Wie der Korpustest, nur mit einer Datei.
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasKorpus' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(mFolder);
  try
    TFile.WriteAllText(TPath.Combine(mFolder, 'Probe.pas'), cSamples[0], TEncoding.UTF8);
    for mFileName in TDirectory.GetFiles(mFolder, '*.pas', TSearchOption.soAllDirectories) do
    begin
      ParseAndFree(TFile.ReadAllText(mFileName, TEncoding.UTF8));
    end;
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TPascalParserRobustnessTests.FuzzingNeverCrashesOrHangs;
var
  mRound: Integer;
  mText: string;
  mWatch: TStopwatch;
begin
  RandSeed := cFuzzSeed;
  for mRound := 1 to cFuzzRounds do
  begin
    mText := Mutate(cSamples[mRound mod Length(cSamples)]);
    mWatch := TStopwatch.StartNew;
    try
      ParseAndFree(mText);
    except
      on E: Exception do
        Assert.Fail(Format('Runde %d: %s: %s'#13#10'%s', [mRound, E.ClassName, E.Message, mText]));
    end;
    if mWatch.ElapsedMilliseconds > cHangLimitMs then
    begin
      Assert.Fail(Format('Runde %d: %d ms'#13#10'%s', [mRound, mWatch.ElapsedMilliseconds, mText]));
    end;
  end;
end;

procedure TPascalParserRobustnessTests.DeepNestingIsReportedNotFatal;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse('program P; begin X := ' + StringOfChar('(', 100000) + '1; end.');
  try
    Assert.IsTrue(Length(mTree.Diagnostics) > 0);
    Assert.IsTrue(mTree.Diagnostics[0].Message.StartsWith('Zu tief verschachtelt'), mTree.Diagnostics[0].Message);
  finally
    mTree.Free;
  end;
  ParseAndFree('program P; ' + Repeated('begin ', 50000) + 'end.');
  ParseAndFree('program P; begin X := ' + Repeated('[', 50000) + '; end.');
  ParseAndFree('unit U; interface implementation ' + Repeated('procedure A; ', 50000) + 'end.');
end;

procedure TPascalParserRobustnessTests.LongChainsDoNotOverflowStack;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
  mText: string;
  mTree: TSyntaxTree;
begin
  // 1+1+...+1 und a.b.c...: lange, aber flache Ketten im Quelltext ergeben tiefe Bäume.
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('program P; begin X := 1');
    for mIndex := 1 to 100000 do
    begin
      mBuilder.Append('+1');
    end;
    mBuilder.Append('; Y := a');
    for mIndex := 1 to 100000 do
    begin
      mBuilder.Append('.b');
    end;
    mBuilder.Append('; end.');
    mText := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  mTree := TPascalParser.Parse(mText);
  try
    Assert.AreEqual<NativeInt>(0, Length(mTree.Diagnostics));
    TLspFoldingRanges.Collect(mTree);
  finally
    mTree.Free;
  end;
end;

/// <summary>'1' + '2' + … mit ACount Gliedern, jedes eine eigene Zahl.</summary>
function NumberChain(ACount: Integer; const AOperator: string): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('1');
    for mIndex := 2 to ACount do
    begin
      mBuilder.Append(' ').Append(AOperator).Append(' ').Append(mIndex);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function ProcedureWith(const AExpression: string): string;
begin
  Result := 'unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10 +
    '  X := ' + AExpression + ';'#13#10'end;'#13#10'end.';
end;

function FirstOfKind(ANode: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  mFound: TSyntaxNode;
begin
  mFound := nil;
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    begin
      if (mFound = nil) and (AVisited.Kind = AKind) then
      begin
        mFound := AVisited;
      end;
      Result := mFound = nil;
    end);
  Result := mFound;
end;

function TextOf(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

procedure TPascalParserRobustnessTests.LongConcatenationIsBalanced;
const
  cCount = 5000;
var
  mExpression, mText: string;
  mTree: TSyntaxTree;
  mRoot: TSyntaxNode;
  mLiterals: TList<string>;
  mIndex: Integer;
  mRangesOk: Boolean;
begin
  mExpression := NumberChain(cCount, '+');
  mText := ProcedureWith(mExpression);
  mTree := TPascalParser.Parse(mText);
  mLiterals := TList<string>.Create;
  try
    Assert.AreEqual<NativeInt>(0, Length(mTree.Diagnostics));
    // Linkslastig wären es über 5000 Ebenen.
    Assert.IsTrue(mTree.Depth < 40, 'Tiefe ' + IntToStr(mTree.Depth));
    mRoot := FirstOfKind(mTree.Root, TSyntaxKind.BinaryExpr);
    Assert.IsNotNull(mRoot);
    Assert.AreEqual(mExpression, TextOf(mText, mRoot), 'Bereich des ganzen Ausdrucks');
    mRangesOk := True;
    mRoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Part: string;
      begin
        if ANode.Kind = TSyntaxKind.Literal then
        begin
          mLiterals.Add(TextOf(mText, ANode));
        end
        else if ANode.Kind = TSyntaxKind.BinaryExpr then
        begin
          // Jeder Teilbaum umfasst genau eine zusammenhängende Folge von Gliedern.
          Part := TextOf(mText, ANode);
          if (ANode.Name <> '+') or not CharInSet(Part[1], ['0'..'9']) or
            not CharInSet(Part[Length(Part)], ['0'..'9']) or
            (ANode.StartOffset <> ANode.Children[0].StartOffset) or
            (ANode.EndOffset <> ANode.Children[1].EndOffset) then
          begin
            mRangesOk := False;
          end;
        end;
        Result := True;
      end);
    Assert.IsTrue(mRangesOk, 'Bereiche der Teilbäume');
    Assert.AreEqual(Integer(cCount), Integer(mLiterals.Count));
    for mIndex := 0 to mLiterals.Count - 1 do
    begin
      Assert.AreEqual(IntToStr(mIndex + 1), mLiterals[mIndex], 'Reihenfolge der Glieder');
    end;
  finally
    mLiterals.Free;
    mTree.Free;
  end;
end;

procedure TPascalParserRobustnessTests.ShortChainsStayLeftDeep;
var
  mText: string;
  mTree: TSyntaxTree;
  mRoot: TSyntaxNode;
begin
  // a + b + c = (a + b) + c
  mText := ProcedureWith('a + b + c');
  mTree := TPascalParser.Parse(mText);
  try
    mRoot := FirstOfKind(mTree.Root, TSyntaxKind.BinaryExpr);
    Assert.AreEqual('a + b + c', TextOf(mText, mRoot));
    Assert.AreEqual(Ord(TSyntaxKind.BinaryExpr), Ord(mRoot.Children[0].Kind));
    Assert.AreEqual('a + b', TextOf(mText, mRoot.Children[0]));
    Assert.AreEqual('c', mRoot.Children[1].Name);
  finally
    mTree.Free;
  end;
  // Gemischt: a - b + c - d = ((a - b) + c) - d
  mText := ProcedureWith('a - b + c - d');
  mTree := TPascalParser.Parse(mText);
  try
    mRoot := FirstOfKind(mTree.Root, TSyntaxKind.BinaryExpr);
    Assert.AreEqual('-', mRoot.Name);
    Assert.AreEqual('a - b + c', TextOf(mText, mRoot.Children[0]));
    Assert.AreEqual('+', mRoot.Children[0].Name);
    Assert.AreEqual('a - b', TextOf(mText, mRoot.Children[0].Children[0]));
  finally
    mTree.Free;
  end;
  // Nicht assoziativ: auch lange Ketten bleiben linkslastig.
  mText := ProcedureWith(NumberChain(100, '-'));
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsTrue(mTree.Depth > 100, 'Tiefe ' + IntToStr(mTree.Depth));
  finally
    mTree.Free;
  end;
end;

procedure TPascalParserRobustnessTests.LongConcatenationPassesAllRulesInSmallStack;
var
  mBuilder: TStringBuilder;
  mIndex, mDestroys: Integer;
  mText, mFailure: string;
  mFindings: TArray<TRuleFinding>;
  mFinding: TRuleFinding;
begin
  // Wie Rules.Catalog.Data.pas: eine Klasse und eine Funktion mit sehr langer String-Verkettung.
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('unit Katalog;'#13#10'interface'#13#10'type'#13#10 +
      '  TKatalog = class'#13#10'  public'#13#10'    destructor Destroy;'#13#10'  end;'#13#10 +
      'function Daten: string;'#13#10'implementation'#13#10 +
      'destructor TKatalog.Destroy;'#13#10'begin'#13#10'  inherited;'#13#10'end;'#13#10 +
      'function Daten: string;'#13#10'begin'#13#10'  Result := ''a''');
    for mIndex := 1 to 5000 do
    begin
      mBuilder.Append(' + #10 + ''z').Append(mIndex).Append('''');
    end;
    mBuilder.Append(';'#13#10'end;'#13#10'end.');
    mText := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  mFindings := nil;
  mFailure := TSmallStack.Run(512,
    procedure
    begin
      mFindings := TFileChecker.CheckText(BuiltinRules, TServerSettings.Default, 'Katalog.pas', mText);
    end);
  Assert.AreEqual('', mFailure, 'kein Stapelüberlauf');
  // Die Vererbungsregeln melden weiter, was sie vorher meldeten.
  mDestroys := 0;
  for mFinding in mFindings do
  begin
    if mFinding.RuleId = 'destroy-without-override' then
    begin
      Inc(mDestroys);
    end;
  end;
  Assert.AreEqual(1, mDestroys);
  mFindings := nil;
end;

/// <summary>Wurzel des Korpus aus ATLAS_CORPUS, sonst der Ordner source der Delphi-Installation (BDS); '' ohne.
/// </summary>
function CorpusRoot: string;
begin
  Result := GetEnvironmentVariable('ATLAS_CORPUS');
  if Result = '' then
  begin
    Result := GetEnvironmentVariable('BDS');
    if Result <> '' then
    begin
      Result := TPath.Combine(Result, 'source');
    end;
  end;
end;

/// <summary>In der Delphi-Installation RTL und VCL, sonst der ganze Ordner ARoot.</summary>
function CorpusDirectories(const ARoot: string): TArray<string>;
var
  mDirectory: string;
begin
  Result := nil;
  for mDirectory in TArray<string>.Create(TPath.Combine(ARoot, 'rtl'), TPath.Combine(ARoot, 'vcl')) do
  begin
    if TDirectory.Exists(mDirectory) then
    begin
      Result := Result + [mDirectory];
    end;
  end;
  if Result = nil then
  begin
    Result := [ARoot];
  end;
end;

/// <summary>Parst jede .pas unter ADirectory; zählt AFiles hoch und merkt sich die langsamste Datei.</summary>
procedure ParseDirectory(const ADirectory: string; var AFiles: Integer; var ASlowest: Int64;
  var ASlowestFile: string);
var
  mFileName, mText: string;
  mWatch: TStopwatch;
begin
  for mFileName in TDirectory.GetFiles(ADirectory, '*.pas', TSearchOption.soAllDirectories) do
  begin
    mText := TFile.ReadAllText(mFileName, TEncoding.UTF8);
    mWatch := TStopwatch.StartNew;
    try
      ParseAndFree(mText);
    except
      on E: Exception do
      begin
        Assert.Fail(Format('%s: %s: %s', [mFileName, E.ClassName, E.Message]));
      end;
    end;
    if mWatch.ElapsedMilliseconds > ASlowest then
    begin
      ASlowest := mWatch.ElapsedMilliseconds;
      ASlowestFile := mFileName;
    end;
    Inc(AFiles);
  end;
end;

procedure TPascalParserRobustnessTests.ParsesDelphiSourceCorpus;
var
  mRoot: string;
  mDirectory: string;
  mFiles: Integer;
  mSlowest: Int64;
  mSlowestFile: string;
  mTotal: TStopwatch;
begin
  mRoot := CorpusRoot;
  // Ohne Assert.Pass: Es hinterließ hier 192 Byte, die der Leckmonitor dem Test anrechnet.
  if (mRoot = '') or not TDirectory.Exists(mRoot) then
  begin
    System.Writeln('  Übersprungen: kein Korpus (ATLAS_CORPUS oder BDS setzen)');
    Exit;
  end;
  mFiles := 0;
  mSlowest := 0;
  mSlowestFile := '';
  mTotal := TStopwatch.StartNew;
  for mDirectory in CorpusDirectories(mRoot) do
  begin
    ParseDirectory(mDirectory, mFiles, mSlowest, mSlowestFile);
  end;
  Assert.IsTrue(mFiles > 0, 'Keine .pas-Dateien unter ' + mRoot);
  Assert.IsTrue(mSlowest < cHangLimitMs, Format('%s braucht %d ms', [mSlowestFile, mSlowest]));
  System.Writeln(Format('  %d Dateien in %d ms; langsamste: %s (%d ms)',
    [mFiles, mTotal.ElapsedMilliseconds, ExtractFileName(mSlowestFile), mSlowest]));
end;

procedure TPascalParserRobustnessTests.SyntaxDiagnosticsWithin200Ms;
var
  mStore: IDocumentStore;
  mDocument: ITextDocument;
  mWatch: TStopwatch;
  mParams: TJSONObject;
begin
  // Etwa 3000 Zeilen; Zielwert der Spezifikation: Syntaxfehler < 200 ms.
  mStore := TDocumentStore.Create;
  mDocument := mStore.Open('file:///big.pas', 'objectpascal', 1, GenerateUnit(200));
  mWatch := TStopwatch.StartNew;
  mParams := TLspSyntaxDiagnostics.BuildParams(mDocument);
  mWatch.Stop;
  mParams.Free;
  Assert.IsTrue(mWatch.ElapsedMilliseconds + TLspSyntaxDiagnostics.cDefaultDelayMs < 200,
    Format('Parsen dauert %d ms', [mWatch.ElapsedMilliseconds]));
end;

procedure TPascalParserRobustnessTests.OutlineAndFoldingWithin100Ms;
var
  mTree: TSyntaxTree;
  mWatch: TStopwatch;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(GenerateUnit(200));
  try
    mWatch := TStopwatch.StartNew;
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree);
    mSymbols.Free;
    TLspFoldingRanges.Collect(mTree);
    mWatch.Stop;
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 100, Format('Gliederung und Faltbereiche: %d ms', [mWatch.ElapsedMilliseconds]));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalParserRobustnessTests);

end.
