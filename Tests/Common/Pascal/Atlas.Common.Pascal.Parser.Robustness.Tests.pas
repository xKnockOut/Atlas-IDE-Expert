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
    [Test]
    procedure FuzzingNeverCrashesOrHangs;
    [Test]
    procedure DeepNestingIsReportedNotFatal;
    [Test]
    // RTL legt bei erster Benutzung Singletons an (Kodierungen, Pfad-/Registry-Hilfen); kein Leck des Testcodes.
    [IgnoreMemoryLeaks]
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
    // RTL legt bei erster Benutzung Singletons an (Kodierungen, Pfad-/Registry-Hilfen); kein Leck des Testcodes.
    [IgnoreMemoryLeaks]
    procedure LongConcatenationPassesAllRulesInSmallStack;
    [Test]
    // RTL legt bei erster Benutzung Singletons an (Kodierungen, Pfad-/Registry-Hilfen); kein Leck des Testcodes.
    [IgnoreMemoryLeaks]
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
  FuzzSeed = 20261007;
  FuzzRounds = 2000;
  /// <summary>Obergrenze je Parse; deutlich darüber gilt als Hänger.</summary>
  HangLimitMs = 2000;

  Samples: array[0..2] of string = (
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

  Garbage: array[0..9] of string = ('begin', 'end', '(', ')', '[', ']', ';', '''', '{', 'class');

// Beschädigt den Text zufällig: Zeichen löschen, abschneiden, Klammern und
// Schlüsselwörter einstreuen, Blöcke verdoppeln.
function Mutate(const AText: string): string;
var
  Round: Integer;
  Position: Integer;
begin
  Result := AText;
  for Round := 1 to 1 + Random(5) do
  begin
    if Result = '' then
      Exit;
    Position := Random(Length(Result));
    case Random(5) of
      0:
        Result := Result.Remove(Position, 1 + Random(20));
      1:
        Result := Result.Substring(0, Position);
      2:
        Result := Result.Insert(Position, Garbage[Random(Length(Garbage))]);
      3:
        Result := Result.Insert(Position, Result.Substring(Random(Length(Result)), Random(200)));
      4:
        Result := Result.Insert(Position, ' ' + Garbage[Random(Length(Garbage))] + ' ');
    end;
  end;
end;

function Repeated(const AText: string; ACount: Integer): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    for Index := 1 to ACount do
      Builder.Append(AText);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure ParseAndFree(const AText: string);
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  Tree.Free;
end;

function GenerateUnit(AClasses: Integer): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.AppendLine('unit Big;').AppendLine('interface').AppendLine('type');
    for Index := 1 to AClasses do
      Builder.AppendFormat('  TClass%d = class', [Index]).AppendLine
        .AppendLine('  private')
        .AppendLine('    FValue: Integer;')
        .AppendLine('  public')
        .AppendLine('    procedure Run(const A: string; B: Integer);')
        .AppendLine('    property Value: Integer read FValue write FValue;')
        .AppendLine('  end;');
    Builder.AppendLine('implementation');
    for Index := 1 to AClasses do
      Builder.AppendFormat('procedure TClass%d.Run(const A: string; B: Integer);', [Index]).AppendLine
        .AppendLine('var I: Integer;')
        .AppendLine('begin')
        .AppendLine('  for I := 0 to B do')
        .AppendLine('    if A <> '''' then FValue := FValue + Length(A) * I else Exit;')
        .AppendLine('end;');
    Builder.Append('end.');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

{ TPascalParserRobustnessTests }

procedure TPascalParserRobustnessTests.FuzzingNeverCrashesOrHangs;
var
  Round: Integer;
  Text: string;
  Watch: TStopwatch;
begin
  RandSeed := FuzzSeed;
  for Round := 1 to FuzzRounds do
  begin
    Text := Mutate(Samples[Round mod Length(Samples)]);
    Watch := TStopwatch.StartNew;
    try
      ParseAndFree(Text);
    except
      on E: Exception do
        Assert.Fail(Format('Runde %d: %s: %s'#13#10'%s', [Round, E.ClassName, E.Message, Text]));
    end;
    if Watch.ElapsedMilliseconds > HangLimitMs then
      Assert.Fail(Format('Runde %d: %d ms'#13#10'%s', [Round, Watch.ElapsedMilliseconds, Text]));
  end;
end;

procedure TPascalParserRobustnessTests.DeepNestingIsReportedNotFatal;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse('program P; begin X := ' + StringOfChar('(', 100000) + '1; end.');
  try
    Assert.IsTrue(Length(Tree.Diagnostics) > 0);
    Assert.IsTrue(Tree.Diagnostics[0].Message.StartsWith('Zu tief verschachtelt'), Tree.Diagnostics[0].Message);
  finally
    Tree.Free;
  end;
  ParseAndFree('program P; ' + Repeated('begin ', 50000) + 'end.');
  ParseAndFree('program P; begin X := ' + Repeated('[', 50000) + '; end.');
  ParseAndFree('unit U; interface implementation ' + Repeated('procedure A; ', 50000) + 'end.');
end;

procedure TPascalParserRobustnessTests.LongChainsDoNotOverflowStack;
var
  Builder: TStringBuilder;
  Index: Integer;
  Text: string;
  Tree: TSyntaxTree;
begin
  // 1+1+...+1 und a.b.c...: lange, aber flache Ketten im Quelltext ergeben tiefe Bäume.
  Builder := TStringBuilder.Create;
  try
    Builder.Append('program P; begin X := 1');
    for Index := 1 to 100000 do
      Builder.Append('+1');
    Builder.Append('; Y := a');
    for Index := 1 to 100000 do
      Builder.Append('.b');
    Builder.Append('; end.');
    Text := Builder.ToString;
  finally
    Builder.Free;
  end;
  Tree := TPascalParser.Parse(Text);
  try
    Assert.AreEqual<NativeInt>(0, Length(Tree.Diagnostics));
    TLspFoldingRanges.Collect(Tree);
  finally
    Tree.Free;
  end;
end;

/// <summary>'1' + '2' + … mit ACount Gliedern, jedes eine eigene Zahl.</summary>
function NumberChain(ACount: Integer; const AOperator: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('1');
    for Index := 2 to ACount do
      Builder.Append(' ').Append(AOperator).Append(' ').Append(Index);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function ProcedureWith(const AExpression: string): string;
begin
  Result := 'unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10 +
    '  X := ' + AExpression + ';'#13#10'end;'#13#10'end.';
end;

function FirstOfKind(ANode: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    begin
      if (Found = nil) and (AVisited.Kind = AKind) then
        Found := AVisited;
      Result := Found = nil;
    end);
  Result := Found;
end;

function TextOf(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

procedure TPascalParserRobustnessTests.LongConcatenationIsBalanced;
const
  Count = 5000;
var
  Expression, Text: string;
  Tree: TSyntaxTree;
  Root: TSyntaxNode;
  Literals: TList<string>;
  Index: Integer;
  RangesOk: Boolean;
begin
  Expression := NumberChain(Count, '+');
  Text := ProcedureWith(Expression);
  Tree := TPascalParser.Parse(Text);
  Literals := TList<string>.Create;
  try
    Assert.AreEqual<NativeInt>(0, Length(Tree.Diagnostics));
    // Linkslastig wären es über 5000 Ebenen.
    Assert.IsTrue(Tree.Depth < 40, 'Tiefe ' + IntToStr(Tree.Depth));
    Root := FirstOfKind(Tree.Root, TSyntaxKind.BinaryExpr);
    Assert.IsNotNull(Root);
    Assert.AreEqual(Expression, TextOf(Text, Root), 'Bereich des ganzen Ausdrucks');
    RangesOk := True;
    Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Part: string;
      begin
        if ANode.Kind = TSyntaxKind.Literal then
          Literals.Add(TextOf(Text, ANode))
        else if ANode.Kind = TSyntaxKind.BinaryExpr then
        begin
          // Jeder Teilbaum umfasst genau eine zusammenhängende Folge von Gliedern.
          Part := TextOf(Text, ANode);
          if (ANode.Name <> '+') or not CharInSet(Part[1], ['0'..'9']) or
            not CharInSet(Part[Length(Part)], ['0'..'9']) or
            (ANode.StartOffset <> ANode.Children[0].StartOffset) or
            (ANode.EndOffset <> ANode.Children[1].EndOffset) then
            RangesOk := False;
        end;
        Result := True;
      end);
    Assert.IsTrue(RangesOk, 'Bereiche der Teilbäume');
    Assert.AreEqual(Integer(Count), Integer(Literals.Count));
    for Index := 0 to Literals.Count - 1 do
      Assert.AreEqual(IntToStr(Index + 1), Literals[Index], 'Reihenfolge der Glieder');
  finally
    Literals.Free;
    Tree.Free;
  end;
end;

procedure TPascalParserRobustnessTests.ShortChainsStayLeftDeep;
var
  Text: string;
  Tree: TSyntaxTree;
  Root: TSyntaxNode;
begin
  // a + b + c = (a + b) + c
  Text := ProcedureWith('a + b + c');
  Tree := TPascalParser.Parse(Text);
  try
    Root := FirstOfKind(Tree.Root, TSyntaxKind.BinaryExpr);
    Assert.AreEqual('a + b + c', TextOf(Text, Root));
    Assert.AreEqual(Ord(TSyntaxKind.BinaryExpr), Ord(Root.Children[0].Kind));
    Assert.AreEqual('a + b', TextOf(Text, Root.Children[0]));
    Assert.AreEqual('c', Root.Children[1].Name);
  finally
    Tree.Free;
  end;
  // Gemischt: a - b + c - d = ((a - b) + c) - d
  Text := ProcedureWith('a - b + c - d');
  Tree := TPascalParser.Parse(Text);
  try
    Root := FirstOfKind(Tree.Root, TSyntaxKind.BinaryExpr);
    Assert.AreEqual('-', Root.Name);
    Assert.AreEqual('a - b + c', TextOf(Text, Root.Children[0]));
    Assert.AreEqual('+', Root.Children[0].Name);
    Assert.AreEqual('a - b', TextOf(Text, Root.Children[0].Children[0]));
  finally
    Tree.Free;
  end;
  // Nicht assoziativ: auch lange Ketten bleiben linkslastig.
  Text := ProcedureWith(NumberChain(100, '-'));
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsTrue(Tree.Depth > 100, 'Tiefe ' + IntToStr(Tree.Depth));
  finally
    Tree.Free;
  end;
end;

procedure TPascalParserRobustnessTests.LongConcatenationPassesAllRulesInSmallStack;
var
  Builder: TStringBuilder;
  Index, Destroys: Integer;
  Text, Failure: string;
  Findings: TArray<TRuleFinding>;
  Finding: TRuleFinding;
begin
  // Wie Rules.Catalog.Data.pas: eine Klasse und eine Funktion mit sehr langer String-Verkettung.
  Builder := TStringBuilder.Create;
  try
    Builder.Append('unit Katalog;'#13#10'interface'#13#10'type'#13#10 +
      '  TKatalog = class'#13#10'  public'#13#10'    destructor Destroy;'#13#10'  end;'#13#10 +
      'function Daten: string;'#13#10'implementation'#13#10 +
      'destructor TKatalog.Destroy;'#13#10'begin'#13#10'  inherited;'#13#10'end;'#13#10 +
      'function Daten: string;'#13#10'begin'#13#10'  Result := ''a''');
    for Index := 1 to 5000 do
      Builder.Append(' + #10 + ''z').Append(Index).Append('''');
    Builder.Append(';'#13#10'end;'#13#10'end.');
    Text := Builder.ToString;
  finally
    Builder.Free;
  end;
  Findings := nil;
  Failure := TSmallStack.Run(512,
    procedure
    begin
      Findings := TFileChecker.CheckText(BuiltinRules, TServerSettings.Default, 'Katalog.pas', Text);
    end);
  Assert.AreEqual('', Failure, 'kein Stapelüberlauf');
  // Die Vererbungsregeln melden weiter, was sie vorher meldeten.
  Destroys := 0;
  for Finding in Findings do
    if Finding.RuleId = 'destroy-without-override' then
      Inc(Destroys);
  Assert.AreEqual(1, Destroys);
  Findings := nil;
end;

procedure TPascalParserRobustnessTests.ParsesDelphiSourceCorpus;
var
  Root: string;
  Directories: TArray<string>;
  Directory: string;
  FileName: string;
  Files: Integer;
  Slowest: Int64;
  SlowestFile: string;
  Watch: TStopwatch;
  Total: TStopwatch;
  Text: string;
begin
  Root := GetEnvironmentVariable('ATLAS_CORPUS');
  if Root = '' then
  begin
    Root := GetEnvironmentVariable('BDS');
    if Root <> '' then
      Root := TPath.Combine(Root, 'source');
  end;
  if (Root = '') or not TDirectory.Exists(Root) then
  begin
    Assert.Pass('Übersprungen: kein Korpus (ATLAS_CORPUS oder BDS setzen)');
    Exit;
  end;
  // In der Delphi-Installation RTL und VCL, sonst der ganze Ordner.
  Directories := nil;
  for Directory in TArray<string>.Create(TPath.Combine(Root, 'rtl'), TPath.Combine(Root, 'vcl')) do
    if TDirectory.Exists(Directory) then
      Directories := Directories + [Directory];
  if Directories = nil then
    Directories := [Root];

  Files := 0;
  Slowest := 0;
  SlowestFile := '';
  Total := TStopwatch.StartNew;
  for Directory in Directories do
    for FileName in TDirectory.GetFiles(Directory, '*.pas', TSearchOption.soAllDirectories) do
    begin
      Text := TFile.ReadAllText(FileName);
      Watch := TStopwatch.StartNew;
      try
        ParseAndFree(Text);
      except
        on E: Exception do
          Assert.Fail(Format('%s: %s: %s', [FileName, E.ClassName, E.Message]));
      end;
      if Watch.ElapsedMilliseconds > Slowest then
      begin
        Slowest := Watch.ElapsedMilliseconds;
        SlowestFile := FileName;
      end;
      Inc(Files);
    end;
  Assert.IsTrue(Files > 0, 'Keine .pas-Dateien unter ' + Root);
  Assert.IsTrue(Slowest < HangLimitMs, Format('%s braucht %d ms', [SlowestFile, Slowest]));
  Assert.Pass(Format('%d Dateien in %d ms; langsamste: %s (%d ms)',
    [Files, Total.ElapsedMilliseconds, ExtractFileName(SlowestFile), Slowest]));
end;

procedure TPascalParserRobustnessTests.SyntaxDiagnosticsWithin200Ms;
var
  Store: IDocumentStore;
  Document: ITextDocument;
  Watch: TStopwatch;
  Params: TJSONObject;
begin
  // Etwa 3000 Zeilen; Zielwert der Spezifikation: Syntaxfehler < 200 ms.
  Store := TDocumentStore.Create;
  Document := Store.Open('file:///big.pas', 'objectpascal', 1, GenerateUnit(200));
  Watch := TStopwatch.StartNew;
  Params := TLspSyntaxDiagnostics.BuildParams(Document);
  Watch.Stop;
  Params.Free;
  Assert.IsTrue(Watch.ElapsedMilliseconds + TLspSyntaxDiagnostics.DefaultDelayMs < 200,
    Format('Parsen dauert %d ms', [Watch.ElapsedMilliseconds]));
end;

procedure TPascalParserRobustnessTests.OutlineAndFoldingWithin100Ms;
var
  Tree: TSyntaxTree;
  Watch: TStopwatch;
  Symbols: TJSONArray;
begin
  Tree := TPascalParser.Parse(GenerateUnit(200));
  try
    Watch := TStopwatch.StartNew;
    Symbols := TLspDocumentSymbols.BuildSymbols(Tree);
    Symbols.Free;
    TLspFoldingRanges.Collect(Tree);
    Watch.Stop;
    Assert.IsTrue(Watch.ElapsedMilliseconds < 100, Format('Gliederung und Faltbereiche: %d ms', [Watch.ElapsedMilliseconds]));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalParserRobustnessTests);

end.
