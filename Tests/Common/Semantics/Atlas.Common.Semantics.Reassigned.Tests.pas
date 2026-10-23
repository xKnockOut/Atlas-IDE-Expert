unit Atlas.Common.Semantics.Reassigned.Tests;

// Tests der neu zugewiesenen Variablen (#712): Zählung schreibender Stellen
// (:=, var-/out-Argument, Inc/Dec, Include/Exclude, Read/ReadLn), mögliche
// Änderungen, Inline-Variablen, Schleifenzähler, Parametermodifizierer,
// Felder, jede Kombination der Ziele und der Kandidat "Konstante".

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Semantics.Reassigned;

type
  [TestFixture]
  TReassignedTests = class
  private
    /// <summary>Je Name "Name=Art:sicher/Schleife/moeglich", sortiert, mit Leerzeichen getrennt.</summary>
    class function Counts(const ASource: string; const ALookup: TFlowSignatureLookup = nil): string; static;
    /// <summary>Namen der neu zugewiesenen Einträge für ATargets, sortiert.</summary>
    class function Marked(const ASource: string; ATargets: TReassignedTargets): string; static;
    /// <summary>Stellen des Namens AName als "Zeile:Zeichen" mit w (schreibt), l (Schleife), m (womöglich).</summary>
    class function Places(const ASource, AName: string): string; static;
  public
    [Test]
    procedure AssignmentsAndIncDec;
    [Test]
    procedure VarAndOutArguments;
    [Test]
    procedure IncludeExcludeAndRead;
    [Test]
    procedure PossibleWritesDoNotCount;
    [Test]
    procedure ResolvedSignaturesFromLookup;
    [Test]
    procedure InlineVariables;
    [Test]
    procedure LoopCounters;
    [Test]
    procedure ParameterModifiers;
    [Test]
    procedure FieldsWrittenInOneMethod;
    [Test]
    procedure NestedRoutinesAndAnonymousMethods;
    [Test]
    procedure EveryTargetCombination;
    [Test]
    procedure ConstCandidates;
    [Test]
    procedure OccurrencesInTextOrder;
    [Test]
    procedure TargetNamesAndSymbolAt;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser;

const
  LB = #13#10;
  WriteCodes: array[TReassignedWrite] of string = ('', 'w', 'l', 'm');

function Wrap(const ABody: string): string;
begin
  Result := 'unit U;' + LB + 'interface' + LB + 'implementation' + LB + ABody + LB + 'end.';
end;

class function TReassignedTests.Counts(const ASource: string; const ALookup: TFlowSignatureLookup): string;
var
  Tree: TSyntaxTree;
  Symbol: TReassignedSymbol;
  Items: TList<string>;
begin
  Items := TList<string>.Create;
  Tree := TPascalParser.Parse(ASource);
  try
    for Symbol in TReassigned.Analyze(ASource, Tree, ALookup) do
      Items.Add(Format('%s=%s:%d/%d/%d', [Symbol.Name, TReassigned.KindNames[Symbol.Kind], Symbol.Writes,
        Symbol.LoopWrites, Symbol.MaybeWrites]));
    Items.Sort;
    Result := string.Join(' ', Items.ToArray);
  finally
    Tree.Free;
    Items.Free;
  end;
end;

class function TReassignedTests.Marked(const ASource: string; ATargets: TReassignedTargets): string;
var
  Tree: TSyntaxTree;
  Symbol: TReassignedSymbol;
  Items: TList<string>;
begin
  Items := TList<string>.Create;
  Tree := TPascalParser.Parse(ASource);
  try
    for Symbol in TReassigned.Filter(TReassigned.Analyze(ASource, Tree, nil), ATargets) do
      Items.Add(Symbol.Name);
    Items.Sort;
    Result := string.Join(' ', Items.ToArray);
  finally
    Tree.Free;
    Items.Free;
  end;
end;

class function TReassignedTests.Places(const ASource, AName: string): string;
var
  Tree: TSyntaxTree;
  Symbol: TReassignedSymbol;
  Occurrence: TReassignedOccurrence;
begin
  Result := '';
  Tree := TPascalParser.Parse(ASource);
  try
    for Symbol in TReassigned.Analyze(ASource, Tree, nil) do
      if SameText(Symbol.Name, AName) then
        for Occurrence in Symbol.Occurrences do
        begin
          if Result <> '' then
            Result := Result + ' ';
          Result := Result + Format('%d:%d%s', [Occurrence.Range.StartPos.Line, Occurrence.Range.StartPos.Character,
            WriteCodes[Occurrence.Write]]);
        end;
  finally
    Tree.Free;
  end;
end;

procedure TReassignedTests.AssignmentsAndIncDec;
const
  Source =
    'procedure P;' + LB +
    'var' + LB +
    '  A, B, C, D: Integer;' + LB +
    'begin' + LB +
    '  A := 1;' + LB +
    '  A := A + 1;' + LB +
    '  B := 2;' + LB +
    '  C := 3;' + LB +
    '  Inc(C);' + LB +
    '  Dec(D, 2);' + LB +
    '  Writeln(A, B, C, D);' + LB +
    'end;';
begin
  Assert.AreEqual('A=local:2/0/0 B=local:1/0/0 C=local:2/0/0 D=local:1/0/0', Counts(Wrap(Source)));
  Assert.AreEqual('A C', Marked(Wrap(Source), TReassigned.DefaultTargets));
end;

procedure TReassignedTests.VarAndOutArguments;
const
  Source =
    'procedure Fill(var AValue: Integer; out AText: string; ACount: Integer);' + LB +
    'begin' + LB +
    'end;' + LB +
    'procedure P;' + LB +
    'var' + LB +
    '  N, M: Integer;' + LB +
    '  S: string;' + LB +
    'begin' + LB +
    '  N := 0;' + LB +
    '  Fill(N, S, M);' + LB +
    'end;';
begin
  // N: Zuweisung und var-Argument; S: out-Argument; M nur gelesen (Wertparameter).
  Assert.AreEqual('ACount=valueParameter:0/0/0 AText=varParameter:0/0/0 AValue=varParameter:0/0/0 ' +
    'M=local:0/0/0 N=local:2/0/0 S=local:1/0/0', Counts(Wrap(Source)));
  Assert.AreEqual('N', Marked(Wrap(Source), TReassigned.DefaultTargets));
end;

procedure TReassignedTests.IncludeExcludeAndRead;
const
  Source =
    'procedure P;' + LB +
    'var' + LB +
    '  Flags: TFlags;' + LB +
    '  F: TextFile;' + LB +
    '  Line: string;' + LB +
    '  I: Integer;' + LB +
    'begin' + LB +
    '  Flags := [];' + LB +
    '  Include(Flags, fA);' + LB +
    '  Exclude(Flags, fB);' + LB +
    '  ReadLn(F, Line);' + LB +
    '  Read(F, I);' + LB +
    '  Line := Line + ''x'';' + LB +
    'end;';
begin
  Assert.AreEqual('F=local:2/0/0 Flags=local:3/0/0 I=local:1/0/0 Line=local:2/0/0', Counts(Wrap(Source)));
  Assert.AreEqual('F Flags Line', Marked(Wrap(Source), TReassigned.DefaultTargets));
end;

procedure TReassignedTests.PossibleWritesDoNotCount;
const
  Source =
    'procedure P;' + LB +
    'var' + LB +
    '  A, B, C, D: TRec;' + LB +
    'begin' + LB +
    '  A := Default(TRec);' + LB +
    '  Ptr := @A;' + LB +
    '  B := Default(TRec);' + LB +
    '  B.X := 1;' + LB +
    '  C := Default(TRec);' + LB +
    '  Unbekannt(C);' + LB +
    '  D := Default(TRec);' + LB +
    '  D.Liste.Add(1);' + LB +
    'end;';
begin
  // Adresse, Teilzuweisung und unbekannte Signatur: womöglich, nicht gezählt; Methodenaufruf liest.
  Assert.AreEqual('A=local:1/0/1 B=local:1/0/1 C=local:1/0/1 D=local:1/0/0', Counts(Wrap(Source)));
  Assert.AreEqual('', Marked(Wrap(Source), TReassigned.DefaultTargets));
end;

procedure TReassignedTests.ResolvedSignaturesFromLookup;
const
  Source =
    'procedure P;' + LB +
    'var' + LB +
    '  A, B: Integer;' + LB +
    'begin' + LB +
    '  A := 1;' + LB +
    '  Liste.Fill(A);' + LB +
    '  B := 1;' + LB +
    '  Liste.Show(B);' + LB +
    'end;';
var
  Lookup: TFlowSignatureLookup;
begin
  // Ohne Typauflösung ist Obj.Methode unbekannt; die Namensauflösung kennt die Signatur.
  Assert.AreEqual('A=local:1/0/1 B=local:1/0/1', Counts(Wrap(Source)));
  Lookup :=
    function(ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode
    begin
      Result := TFlowArgumentMode.Value;
      if SameText(ACall.Name, 'Fill') then
        Result := TFlowArgumentMode.Reference;
    end;
  Assert.AreEqual('A=local:2/0/0 B=local:1/0/0', Counts(Wrap(Source), Lookup));
end;

procedure TReassignedTests.InlineVariables;
const
  Source =
    'procedure P;' + LB +
    'begin' + LB +
    '  var A := 1;' + LB +
    '  A := 2;' + LB +
    '  var B: Integer := 3;' + LB +
    '  var C: Integer;' + LB +
    '  C := B;' + LB +
    '  C := C * 2;' + LB +
    '  const K = 5;' + LB +
    '  Writeln(A, C, K);' + LB +
    'end;';
begin
  // Der Startwert zählt als erste Zuweisung; Inline-Konstanten zählen nicht.
  Assert.AreEqual('A=inlineVariable:2/0/0 B=inlineVariable:1/0/0 C=inlineVariable:2/0/0', Counts(Wrap(Source)));
  Assert.AreEqual('A C', Marked(Wrap(Source), [TReassignedTarget.Locals]));
end;

procedure TReassignedTests.LoopCounters;
const
  Source =
    'procedure P(const L: TList);' + LB +
    'var' + LB +
    '  I, Total: Integer;' + LB +
    'begin' + LB +
    '  Total := 0;' + LB +
    '  for I := 0 to 9 do' + LB +
    '    Total := Total + I;' + LB +
    '  for var X in L do' + LB +
    '    Writeln(X);' + LB +
    'end;';
begin
  // L ist ein const-Parameter und zählt nicht.
  Assert.AreEqual('I=loopVariable:0/1/0 Total=local:2/0/0 X=loopVariable:0/1/0', Counts(Wrap(Source)));
  Assert.AreEqual('Total', Marked(Wrap(Source), [TReassignedTarget.Locals]));
  Assert.AreEqual('I X', Marked(Wrap(Source), [TReassignedTarget.LoopVars]));
end;

procedure TReassignedTests.ParameterModifiers;
const
  Source =
    'procedure P(A: Integer; const B: Integer; var C: Integer; out D: Integer; constref E: Integer;' + LB +
    '  F: Integer; var G: Integer);' + LB +
    'begin' + LB +
    '  A := A + 1;' + LB +
    '  C := B;' + LB +
    '  D := E + F;' + LB +
    '  Writeln(G);' + LB +
    'end;';
begin
  // const und constref lassen sich nicht beschreiben und zählen nicht.
  Assert.AreEqual('A=valueParameter:1/0/0 C=varParameter:1/0/0 D=varParameter:1/0/0 F=valueParameter:0/0/0 ' +
    'G=varParameter:0/0/0', Counts(Wrap(Source)));
  Assert.AreEqual('A', Marked(Wrap(Source), [TReassignedTarget.ValueParams]));
  Assert.AreEqual('C D', Marked(Wrap(Source), [TReassignedTarget.VarParams]));
end;

procedure TReassignedTests.FieldsWrittenInOneMethod;
const
  Source =
    'unit U;' + LB +
    'interface' + LB +
    'type' + LB +
    '  TZaehler = class' + LB +
    '  private' + LB +
    '    FCount, FName: string;' + LB +
    '    FTwice: Integer;' + LB +
    '    FSelf: Integer;' + LB +
    '    FRead: Integer;' + LB +
    '  public' + LB +
    '    constructor Create;' + LB +
    '    procedure Add;' + LB +
    '    procedure Rename(const AName: string);' + LB +
    '  end;' + LB +
    'implementation' + LB +
    'constructor TZaehler.Create;' + LB +
    'begin' + LB +
    '  FName := ''x'';' + LB +
    'end;' + LB +
    'procedure TZaehler.Add;' + LB +
    'begin' + LB +
    '  Inc(FCount);' + LB +
    '  FTwice := 1;' + LB +
    '  Self.FSelf := FSelf + 1;' + LB +
    '  Writeln(FRead);' + LB +
    'end;' + LB +
    'procedure TZaehler.Rename(const AName: string);' + LB +
    'begin' + LB +
    '  FName := AName;' + LB +
    '  FTwice := 2;' + LB +
    'end;' + LB +
    'end.';
begin
  Assert.AreEqual('FCount=field:1/0/0 FName=field:2/0/0 FRead=field:0/0/0 FSelf=field:1/0/0 FTwice=field:2/0/0',
    Counts(Source));
  // FName schreibt auch der Konstruktor, FTwice zwei Methoden, FRead niemand.
  Assert.AreEqual('FCount FSelf', Marked(Source, [TReassignedTarget.Fields]));
  Assert.AreEqual('', Marked(Source, TReassigned.DefaultTargets));
  Assert.AreEqual('7:4 23:7w 23:16', Places(Source, 'FSelf'));
end;

procedure TReassignedTests.NestedRoutinesAndAnonymousMethods;
const
  Source =
    'procedure P;' + LB +
    'var' + LB +
    '  A, B: Integer;' + LB +
    '  procedure Inner;' + LB +
    '  var' + LB +
    '    B: Integer;' + LB +
    '  begin' + LB +
    '    A := 2;' + LB +
    '    B := 1;' + LB +
    '  end;' + LB +
    'begin' + LB +
    '  A := 1;' + LB +
    '  B := 1;' + LB +
    '  Run(procedure(X: Integer)' + LB +
    '    begin' + LB +
    '      X := X + A;' + LB +
    '      B := 2;' + LB +
    '    end);' + LB +
    'end;';
begin
  // A schreibt die verschachtelte Routine mit; ihr B ist ein eigener Name. Die anonyme Methode schreibt das
  // äußere B und ihren Parameter X.
  Assert.AreEqual('A=local:2/0/0 B=local:1/0/0 B=local:2/0/0 X=valueParameter:1/0/0', Counts(Wrap(Source)));
  Assert.AreEqual('A B X', Marked(Wrap(Source), TReassigned.DefaultTargets));
end;

procedure TReassignedTests.EveryTargetCombination;
const
  Source =
    'unit U;' + LB +
    'interface' + LB +
    'type' + LB +
    '  TFoo = class' + LB +
    '    FField: Integer;' + LB +
    '    procedure Run(AValue: Integer; var AOut: Integer);' + LB +
    '  end;' + LB +
    'implementation' + LB +
    'procedure TFoo.Run(AValue: Integer; var AOut: Integer);' + LB +
    'var' + LB +
    '  L, I: Integer;' + LB +
    'begin' + LB +
    '  L := 1;' + LB +
    '  L := 2;' + LB +
    '  for I := 1 to 2 do' + LB +
    '    AValue := I;' + LB +
    '  AOut := L;' + LB +
    '  FField := 3;' + LB +
    'end;' + LB +
    'end.';
  Expected: array[TReassignedTarget] of string = ('L', 'I', 'AValue', 'AOut', 'FField');
var
  Mask: Integer;
  Targets: TReassignedTargets;
  Target: TReassignedTarget;
  Names: TList<string>;
begin
  Names := TList<string>.Create;
  try
    for Mask := 0 to (1 shl (Ord(High(TReassignedTarget)) + 1)) - 1 do
    begin
      Targets := [];
      Names.Clear;
      for Target := Low(TReassignedTarget) to High(TReassignedTarget) do
        if (Mask and (1 shl Ord(Target))) <> 0 then
        begin
          Include(Targets, Target);
          Names.Add(Expected[Target]);
        end;
      Names.Sort;
      Assert.AreEqual(string.Join(' ', Names.ToArray), Marked(Source, Targets), 'Maske ' + IntToStr(Mask));
    end;
  finally
    Names.Free;
  end;
end;

procedure TReassignedTests.ConstCandidates;
const
  Source =
    'procedure P;' + LB +
    'var' + LB +
    '  A, B, C: Integer;' + LB +
    'begin' + LB +
    '  A := 1;' + LB +
    '  B := 1;' + LB +
    '  B := 2;' + LB +
    '  C := 1;' + LB +
    '  Unbekannt(C);' + LB +
    '  var D := A;' + LB +
    '  for var I := 0 to 1 do' + LB +
    '    Writeln(I, D);' + LB +
    'end;';
var
  Tree: TSyntaxTree;
  Symbol: TReassignedSymbol;
  Names: string;
begin
  Names := '';
  Tree := TPascalParser.Parse(Wrap(Source));
  try
    for Symbol in TReassigned.Analyze(Wrap(Source), Tree, nil) do
      if Symbol.IsConstCandidate then
        Names := Names + Symbol.Name + ' ';
  finally
    Tree.Free;
  end;
  Assert.AreEqual('A D', Trim(Names));
end;

procedure TReassignedTests.OccurrencesInTextOrder;
const
  Source =
    'procedure P;' + LB +
    'var' + LB +
    '  I: Integer;' + LB +
    'begin' + LB +
    '  I := 1;' + LB +
    '  for I := I to 5 do' + LB +
    '    Inc(Total, I);' + LB +
    'end;';
begin
  // Zeilen ab 0 in der eingepackten Unit: Deklaration, Zuweisung, Schleife, Lesen.
  Assert.AreEqual('5:2 7:2w 8:6l 8:11 9:15', Places(Wrap(Source), 'I'));
end;

procedure TReassignedTests.TargetNamesAndSymbolAt;
const
  Source =
    'procedure P;' + LB +
    'var' + LB +
    '  A: Integer;' + LB +
    'begin' + LB +
    '  A := 1;' + LB +
    '  A := 2;' + LB +
    'end;';
var
  Target: TReassignedTarget;
  Tree: TSyntaxTree;
  Symbol: TReassignedSymbol;
  Symbols: TArray<TReassignedSymbol>;
begin
  Assert.IsTrue(TReassigned.TryParseTarget('valueParams', Target));
  Assert.IsTrue(Target = TReassignedTarget.ValueParams);
  Assert.IsTrue(TReassigned.TryParseTarget(' LOOPVARS ', Target));
  Assert.IsTrue(Target = TReassignedTarget.LoopVars);
  Assert.IsFalse(TReassigned.TryParseTarget('globals', Target));
  Assert.IsTrue(TReassigned.TargetsOf(TArray<string>.Create('locals', 'fields', 'x')) =
    [TReassignedTarget.Locals, TReassignedTarget.Fields]);
  Tree := TPascalParser.Parse(Wrap(Source));
  try
    Symbols := TReassigned.Analyze(Wrap(Source), Tree, nil);
    Assert.IsTrue(TReassigned.SymbolAt(Symbols, TTextPosition.Create(8, 3), Symbol));
    Assert.AreEqual('A', Symbol.Name);
    Assert.AreEqual(2, Symbol.WriteCount);
    Assert.AreEqual(2, Integer(Length(Symbol.WriteLines)));
    Assert.AreEqual(7, Symbol.WriteLines[0]);
    Assert.IsTrue(TReassigned.SymbolAt(Symbols, TTextPosition.Create(5, 2), Symbol), 'Deklaration');
    Assert.IsFalse(TReassigned.SymbolAt(Symbols, TTextPosition.Create(7, 6), Symbol));
  finally
    Symbols := nil;
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TReassignedTests);

end.
