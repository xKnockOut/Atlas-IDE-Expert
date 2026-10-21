unit Atlas.Common.Editing.InvertBoolean.Tests;

// Tests für „Boolean umkehren“ (#715): Namensvorschläge, Umschreiben von
// Zuweisungen und Bedingungen, Funktionen, Setter, var-Übergaben, Formulare
// und eine Wahrheitstafel, die jede Umschreibung gegen das Original prüft.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInvertBooleanTests = class
  public
    [Test]
    procedure SuggestBuiltinPairs;
    [Test]
    procedure SuggestCustomPairsAndPrefix;
    [Test]
    procedure MockupExample;
    [Test]
    procedure ConditionsAreSimplified;
    [Test]
    procedure AssignmentsAreNegated;
    [Test]
    procedure TruthTableIsKept;
    [Test]
    procedure FunctionBodyReturnsOpposite;
    [Test]
    procedure SetterParameterAndCalls;
    [Test]
    procedure VarArgumentIsReported;
    [Test]
    procedure InitialValuesAreNegated;
    [Test]
    procedure AnonymousMethodIsRewritten;
    [Test]
    procedure DfmValuesAreInverted;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.InvertBoolean;

type
  TTargetsSetup = reference to procedure(ATree: TSyntaxTree; var ATargets: TInvertTargets);

function OffsetsOf(ATree: TSyntaxTree; const AName: string): TArray<Integer>;
var
  Token: TPascalToken;
begin
  Result := nil;
  for Token in ATree.Tokens do
    if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, AName) then
      Result := Result + [Token.Offset];
end;

procedure AddNames(ATree: TSyntaxTree; var ATargets: TInvertTargets; const AOld, ANew: string; AInvert: Boolean);
var
  Offset: Integer;
begin
  for Offset in OffsetsOf(ATree, AOld) do
    ATargets.AddName(Offset, ANew, AInvert);
end;

function RewriteWith(const AText: string; const ASetup: TTargetsSetup; out AWarnings: TArray<TInvertWarning>): string;
var
  Tree: TSyntaxTree;
  Targets: TInvertTargets;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Targets := Default(TInvertTargets);
    ASetup(Tree, Targets);
    Result := TChangeSignature.ApplyEdits(AText, TInvertBoolean.Rewrite(Tree, AText, Targets, AWarnings));
  finally
    Tree.Free;
  end;
end;

/// <summary>Alle Bezeichner AOld werden zu ANew mit Gegenbedeutung.</summary>
function Invert(const AText, AOld, ANew: string): string;
var
  Warnings: TArray<TInvertWarning>;
begin
  Result := RewriteWith(AText,
    procedure(ATree: TSyntaxTree; var ATargets: TInvertTargets)
    begin
      AddNames(ATree, ATargets, AOld, ANew, True);
    end, Warnings);
end;

function InProc(const ABody: string): string;
begin
  Result := 'unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'begin'#13#10 + ABody +
    #13#10'end;'#13#10'end.'#13#10;
end;

function Statement(const AText: string): string;
begin
  // Der Rumpf aus InProc ohne Rahmen.
  Result := AText;
  Delete(Result, 1, Pos('begin'#13#10, Result) + Length('begin'#13#10) - 1);
  Result := Copy(Result, 1, Pos(#13#10'end;'#13#10'end.', Result) - 1);
end;

{ Kleine Auswertung für die Wahrheitstafel: not, and, or, xor, =, <>, Klammern, True/False, Namen. }

type
  TEvaluator = record
    Text: string;
    Position: Integer;
    Values: TArray<string>;
    function Peek: string;
    function Next: string;
    function Value(const AName: string): Boolean;
    function Expression: Boolean;
    function Simple: Boolean;
    function Term: Boolean;
    function Factor: Boolean;
  end;

function TEvaluator.Peek: string;
var
  Start: Integer;
begin
  while (Position <= Length(Text)) and (Text[Position] = ' ') do
    Inc(Position);
  Result := '';
  if Position > Length(Text) then
    Exit;
  Start := Position;
  if CharInSet(Text[Position], ['A'..'Z', 'a'..'z']) then
  begin
    while (Start <= Length(Text)) and CharInSet(Text[Start], ['A'..'Z', 'a'..'z', '0'..'9']) do
      Inc(Start);
    Result := Copy(Text, Position, Start - Position);
  end
  else if Copy(Text, Position, 2) = '<>' then
    Result := '<>'
  else
    Result := Text[Position];
end;

function TEvaluator.Next: string;
begin
  Result := Peek;
  Inc(Position, Length(Result));
end;

function TEvaluator.Value(const AName: string): Boolean;
var
  Item: string;
begin
  if SameText(AName, 'True') then
    Exit(True);
  if SameText(AName, 'False') then
    Exit(False);
  for Item in Values do
    if SameText(Copy(Item, 1, Pos('=', Item) - 1), AName) then
      Exit(Copy(Item, Pos('=', Item) + 1, MaxInt) = '1');
  raise Exception.Create('Unbekannt: ' + AName);
end;

function TEvaluator.Factor: Boolean;
var
  Token: string;
begin
  Token := Next;
  if SameText(Token, 'not') then
    Exit(not Factor);
  if Token = '(' then
  begin
    Result := Expression;
    Next;
    Exit;
  end;
  Result := Value(Token);
end;

function TEvaluator.Term: Boolean;
begin
  Result := Factor;
  while SameText(Peek, 'and') do
  begin
    Next;
    Result := Factor and Result;
  end;
end;

function TEvaluator.Simple: Boolean;
var
  Op: string;
  Right: Boolean;
begin
  Result := Term;
  while SameText(Peek, 'or') or SameText(Peek, 'xor') do
  begin
    Op := LowerCase(Next);
    Right := Term;
    if Op = 'or' then
      Result := Result or Right
    else
      Result := Result xor Right;
  end;
end;

function TEvaluator.Expression: Boolean;
var
  Op: string;
  Right: Boolean;
begin
  Result := Simple;
  Op := Peek;
  if (Op = '=') or (Op = '<>') then
  begin
    Next;
    Right := Simple;
    if Op = '=' then
      Result := Result = Right
    else
      Result := Result <> Right;
  end;
end;

function Evaluate(const AText: string; const AValues: TArray<string>): Boolean;
var
  Evaluator: TEvaluator;
begin
  Evaluator.Text := AText;
  Evaluator.Position := 1;
  Evaluator.Values := AValues;
  Result := Evaluator.Expression;
  Assert.AreEqual('', Evaluator.Peek, 'Rest in ' + AText);
end;

{ TInvertBooleanTests }

procedure TInvertBooleanTests.SuggestBuiltinPairs;
begin
  Assert.AreEqual('FVisible', TInvertBoolean.Suggest('FHidden'));
  Assert.AreEqual('FHidden', TInvertBoolean.Suggest('FVisible'));
  Assert.AreEqual('Disabled', TInvertBoolean.Suggest('Enabled'));
  Assert.AreEqual('HasItems', TInvertBoolean.Suggest('IsEmpty'));
  Assert.AreEqual('isInvalid', TInvertBoolean.Suggest('isValid'));
  Assert.AreEqual('GetUnlocked', TInvertBoolean.Suggest('GetLocked'));
  Assert.AreEqual('SetVisible', TInvertBoolean.Suggest('SetHidden'));
  // Teilwort zählt nicht: "Validate" enthält kein Wort "Valid".
  Assert.AreEqual('FNotValidated', TInvertBoolean.Suggest('FValidated'));
  Assert.AreEqual('FNotReady', TInvertBoolean.Suggest('FReady'));
  Assert.AreEqual('IsNotReady', TInvertBoolean.Suggest('IsReady'));
  Assert.AreEqual('IsReady', TInvertBoolean.Suggest('IsNotReady'));
  Assert.AreEqual('ready', TInvertBoolean.Suggest('notReady'));
  Assert.AreEqual('notDone', TInvertBoolean.Suggest('done'));
  Assert.AreEqual('ANotFlag', TInvertBoolean.Suggest('AFlag'));
end;

procedure TInvertBooleanTests.SuggestCustomPairsAndPrefix;
begin
  Assert.AreEqual('FSilent', TInvertBoolean.Suggest('FVerbose', ['Verbose=Silent'], 'Not'));
  Assert.AreEqual('FVerbose', TInvertBoolean.Suggest('FSilent', ['Verbose=Silent'], 'Not'));
  // Eigene Paare gehen vor: Hidden → Shown statt Visible.
  Assert.AreEqual('FShown', TInvertBoolean.Suggest('FHidden', ['Hidden=Shown'], 'Not'));
  Assert.AreEqual('FNoReady', TInvertBoolean.Suggest('FReady', nil, 'No'));
  Assert.AreEqual('FReady', TInvertBoolean.Suggest('FNoReady', nil, 'No'));
  Assert.AreEqual('FNotReady', TInvertBoolean.Suggest('FReady', ['=x', 'kaputt'], ''));
end;

procedure TInvertBooleanTests.MockupExample;
begin
  Assert.AreEqual(
    '  FVisible := True;'#13#10 +
    '  if FVisible then'#13#10 +
    '    Panel.Visible := FVisible;',
    Statement(Invert(InProc(
    '  FHidden := False;'#13#10 +
    '  if not FHidden then'#13#10 +
    '    Panel.Visible := not FHidden;'), 'FHidden', 'FVisible')));
end;

procedure TInvertBooleanTests.ConditionsAreSimplified;

  procedure Check(const AExpected, ACondition: string);
  begin
    Assert.AreEqual('  if ' + AExpected + ' then ;',
      Statement(Invert(InProc('  if ' + ACondition + ' then ;'), 'X', 'Y')), ACondition);
  end;

begin
  Check('not Y', 'X');
  Check('Y', 'not X');
  Check('Y', 'X = False');
  Check('not Y', 'X = True');
  Check('Y', 'False = X');
  Check('not Y', 'X <> False');
  Check('Y', 'not (X)');
  Check('not Y', 'not not X');
  Check('not Y and Z', 'X and Z');
  Check('Y or not Z', 'not (X and Z)');
  Check('Y and not Z', 'not (X or Z)');
  Check('Y <> Z', 'X = Z');
  Check('Y = Z', 'X <> Z');
  Check('Y = Z', 'not (X = Z)');
  Check('(Y or not Z) and A', 'not (X and Z) and A');
  Check('Obj.Check(not Y)', 'Obj.Check(X)');
  Check('not Y { Kommentar } and Z', 'X { Kommentar } and Z');
  // Nur Lesestellen anderer Namen bleiben unberührt.
  Check('A and B', 'A and B');
end;

procedure TInvertBooleanTests.AssignmentsAreNegated;

  procedure Check(const AExpected, AStatement: string);
  begin
    Assert.AreEqual('  ' + AExpected, Statement(Invert(InProc('  ' + AStatement), 'X', 'Y')), AStatement);
  end;

begin
  Check('Y := False;', 'X := True;');
  Check('Y := True;', 'X := False;');
  Check('Y := not A;', 'X := A;');
  Check('Y := A;', 'X := not A;');
  Check('Y := A <> B;', 'X := A = B;');
  Check('Y := not (A and B);', 'X := A and B;');
  Check('Y := not Y;', 'X := not X;');
  Check('Y := Y or A;', 'X := X and not A;');
  Check('Obj.Y := not Y;', 'Obj.X := not X;');
  Check('Obj.Y := X2;', 'Obj.X := not X2;');
  Check('B := not Y;', 'B := X;');
end;

procedure TInvertBooleanTests.TruthTableIsKept;
const
  Expressions: array[0..13] of string = ('X', 'not X', 'X and A', 'A or X', 'not (X or A)', 'X = False',
    'X <> A', '(X)', 'not (not X and A)', 'X xor A', 'not (X = A) and B', '(X or A) and (B or not X)',
    'True = X', 'not ((X))');
var
  Expression, Rewritten, Assigned: string;
  Bits: Integer;
  Values, Inverted: TArray<string>;
begin
  for Expression in Expressions do
  begin
    Rewritten := Statement(Invert(InProc('  R := ' + Expression + ';'), 'X', 'Y'));
    Rewritten := Copy(Rewritten, Length('  R := ') + 1, Length(Rewritten) - Length('  R := ;'));
    Assigned := Statement(Invert(InProc('  X := ' + Expression + ';'), 'X', 'Y'));
    Assert.IsTrue(StartsStr('  Y := ', Assigned), Assigned);
    Assigned := Copy(Assigned, Length('  Y := ') + 1, Length(Assigned) - Length('  Y := ;'));
    for Bits := 0 to 7 do
    begin
      Values := ['X=' + IntToStr(Bits and 1), 'A=' + IntToStr((Bits shr 1) and 1), 'B=' + IntToStr((Bits shr 2) and 1)];
      Inverted := ['Y=' + IntToStr(1 - (Bits and 1)), Values[1], Values[2]];
      Assert.AreEqual(Evaluate(Expression, Values), Evaluate(Rewritten, Inverted), Expression + ' → ' + Rewritten);
      // Zuweisung an X: Y bekommt den Gegenwert.
      Assert.AreEqual(not Evaluate(Expression, Values), Evaluate(Assigned, Inverted), Expression + ' → ' + Assigned);
    end;
  end;
end;

procedure TInvertBooleanTests.FunctionBodyReturnsOpposite;
const
  Source =
    'unit U;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    function IsEmpty: Boolean;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'function TFoo.IsEmpty: Boolean;'#13#10 +
    '  function Inner: Boolean;'#13#10 +
    '  begin'#13#10 +
    '    Result := True;'#13#10 +
    '  end;'#13#10 +
    'begin'#13#10 +
    '  if Count = 0 then'#13#10 +
    '    Exit(True);'#13#10 +
    '  Result := Inner and (Count < 0);'#13#10 +
    '  if Result then'#13#10 +
    '    Log;'#13#10 +
    'end;'#13#10 +
    'procedure Use(F: TFoo);'#13#10 +
    'begin'#13#10 +
    '  if F.IsEmpty then'#13#10 +
    '    F.Clear;'#13#10 +
    '  F.IsEmpty;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Warnings: TArray<TInvertWarning>;
  Text: string;
begin
  Text := RewriteWith(Source,
    procedure(ATree: TSyntaxTree; var ATargets: TInvertTargets)
    var
      Offsets: TArray<Integer>;
    begin
      AddNames(ATree, ATargets, 'IsEmpty', 'HasItems', True);
      Offsets := OffsetsOf(ATree, 'IsEmpty');
      // Name im Rumpfkopf (zweites Vorkommen).
      ATargets.AddBody(Offsets[1]);
    end, Warnings);
  Assert.Contains(Text, '    function HasItems: Boolean;');
  Assert.Contains(Text, 'function TFoo.HasItems: Boolean;');
  Assert.Contains(Text, '    Exit(False);');
  Assert.Contains(Text, '  Result := not (Inner and (Count < 0));');
  Assert.Contains(Text, '  if not Result then');
  // Die lokale Funktion hat ihr eigenes Result.
  Assert.Contains(Text, '    Result := True;');
  Assert.Contains(Text, '  if not F.HasItems then');
  Assert.Contains(Text, '  F.HasItems;');
end;

procedure TInvertBooleanTests.SetterParameterAndCalls;
const
  Source =
    'unit U;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '  private'#13#10 +
    '    FHidden: Boolean;'#13#10 +
    '    procedure SetHidden(const Value: Boolean);'#13#10 +
    '  public'#13#10 +
    '    property Hidden: Boolean read FHidden write SetHidden;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.SetHidden(const Value: Boolean);'#13#10 +
    'begin'#13#10 +
    '  if Value = FHidden then'#13#10 +
    '    Exit;'#13#10 +
    '  FHidden := Value;'#13#10 +
    '  Panel.Visible := not Value;'#13#10 +
    'end;'#13#10 +
    'procedure Use(F: TFoo);'#13#10 +
    'begin'#13#10 +
    '  F.SetHidden(A and B);'#13#10 +
    '  F.Hidden := True;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Warnings: TArray<TInvertWarning>;
  Text: string;
begin
  Text := RewriteWith(Source,
    procedure(ATree: TSyntaxTree; var ATargets: TInvertTargets)
    var
      Offsets: TArray<Integer>;
      Offset: Integer;
    begin
      AddNames(ATree, ATargets, 'FHidden', 'FVisible', True);
      AddNames(ATree, ATargets, 'Hidden', 'Visible', True);
      AddNames(ATree, ATargets, 'SetHidden', 'SetVisible', False);
      Offsets := OffsetsOf(ATree, 'SetHidden');
      ATargets.AddLocal(Offsets[2], 'Value', 'Value');
      ATargets.AddCall(Offsets[3], 0);
      for Offset in OffsetsOf(ATree, 'Panel') do
        Assert.IsTrue(Offset > 0);
    end, Warnings);
  Assert.Contains(Text, '    FVisible: Boolean;');
  Assert.Contains(Text, '    procedure SetVisible(const Value: Boolean);');
  Assert.Contains(Text, '    property Visible: Boolean read FVisible write SetVisible;');
  Assert.Contains(Text, '  if Value = FVisible then');
  Assert.Contains(Text, '  FVisible := Value;');
  Assert.Contains(Text, '  Panel.Visible := Value;');
  Assert.Contains(Text, '  F.SetVisible(not (A and B));');
  Assert.Contains(Text, '  F.Visible := False;');
end;

procedure TInvertBooleanTests.VarArgumentIsReported;
var
  Warnings: TArray<TInvertWarning>;
  Text: string;
begin
  Text := RewriteWith(InProc('  Toggle(X, X);'#13#10'  Watch(@X);'),
    procedure(ATree: TSyntaxTree; var ATargets: TInvertTargets)
    begin
      AddNames(ATree, ATargets, 'X', 'Y', True);
      ATargets.VarArgument :=
        function(ACall: TSyntaxNode; AArgument: Integer): Boolean
        begin
          Result := AArgument = 0;
        end;
    end, Warnings);
  Assert.AreEqual('  Toggle(Y, not Y);'#13#10'  Watch(@Y);', Statement(Text));
  Assert.AreEqual(2, Integer(Length(Warnings)));
  Assert.AreEqual(5, Warnings[0].Position.Line);
  Assert.AreEqual(9, Warnings[0].Position.Character);
  Assert.AreEqual(6, Warnings[1].Position.Line);
  Assert.AreEqual(8, Warnings[1].Position.Character);
end;

procedure TInvertBooleanTests.InitialValuesAreNegated;
const
  Source =
    'unit U;'#13#10 +
    'interface'#13#10 +
    'var'#13#10 +
    '  X: Boolean = True;'#13#10 +
    '  Z: Boolean = X;'#13#10 +
    'implementation'#13#10 +
    'procedure P;'#13#10 +
    'begin'#13#10 +
    '  var L := not X;'#13#10 +
    'end;'#13#10 +
    'end.'#13#10;
var
  Text: string;
begin
  Text := Invert(Source, 'X', 'Y');
  Assert.Contains(Text, '  Y: Boolean = False;');
  Assert.Contains(Text, '  Z: Boolean = not Y;');
  Assert.Contains(Text, '  var L := Y;');
end;

procedure TInvertBooleanTests.AnonymousMethodIsRewritten;
begin
  Assert.AreEqual('  Run(procedure begin Y := False; if Y then Go; end, not Y);',
    Statement(Invert(InProc('  Run(procedure begin X := True; if not X then Go; end, X);'), 'X', 'Y')));
end;

procedure TInvertBooleanTests.DfmValuesAreInverted;
const
  Dfm =
    'object Form1: TForm1'#13#10 +
    '  object Panel1: TFooPanel'#13#10 +
    '    Hidden = True'#13#10 +
    '  end'#13#10 +
    '  object Panel2: TFooPanel'#13#10 +
    '    Hidden = Maybe'#13#10 +
    '  end'#13#10 +
    '  object Other: TOther'#13#10 +
    '    Hidden = True'#13#10 +
    '  end'#13#10 +
    'end'#13#10;
var
  Warnings: TArray<TInvertWarning>;
  Text: string;
begin
  Text := TChangeSignature.ApplyEdits(Dfm, TInvertBoolean.DfmEdits(Dfm, ['TFooPanel'], 'Hidden', 'Visible',
    Warnings));
  Assert.Contains(Text, '  object Panel1: TFooPanel'#13#10'    Visible = False');
  Assert.Contains(Text, '  object Panel2: TFooPanel'#13#10'    Visible = Maybe');
  Assert.Contains(Text, '  object Other: TOther'#13#10'    Hidden = True');
  Assert.AreEqual(1, Integer(Length(Warnings)));
  Assert.AreEqual(5, Warnings[0].Position.Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TInvertBooleanTests);

end.
