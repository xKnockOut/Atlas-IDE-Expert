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
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.InvertBoolean;

type
  TTargetsSetup = reference to procedure(ATree: TSyntaxTree; var ATargets: TInvertTargets);

function OffsetsOf(ATree: TSyntaxTree; const AName: string): TArray<Integer>;
var
  mToken: TPascalToken;
begin
  Result := nil;
  for mToken in ATree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, AName) then
    begin
      Result := Result + [mToken.Offset];
    end;
  end;
end;

procedure AddNames(ATree: TSyntaxTree; var ATargets: TInvertTargets; const AOld, ANew: string; AInvert: Boolean);
var
  mOffset: Integer;
begin
  for mOffset in OffsetsOf(ATree, AOld) do
  begin
    ATargets.AddName(mOffset, ANew, AInvert);
  end;
end;

function RewriteWith(const AText: string; const ASetup: TTargetsSetup; out AWarnings: TArray<TInvertWarning>): string;
var
  mTree: TSyntaxTree;
  mTargets: TInvertTargets;
begin
  mTree := TPascalParser.Parse(AText);
  try
    mTargets := Default(TInvertTargets);
    ASetup(mTree, mTargets);
    Result := TChangeSignature.ApplyEdits(AText, TInvertBoolean.Rewrite(mTree, AText, mTargets, AWarnings));
  finally
    mTree.Free;
  end;
end;

/// <summary>Alle Bezeichner AOld werden zu ANew mit Gegenbedeutung.</summary>
function Invert(const AText, AOld, ANew: string): string;
var
  mWarnings: TArray<TInvertWarning>;
begin
  Result := RewriteWith(AText,
    procedure(ATree: TSyntaxTree; var ATargets: TInvertTargets)
    begin
      AddNames(ATree, ATargets, AOld, ANew, True);
    end, mWarnings);
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
  mStart: Integer;
begin
  while (Position <= Length(Text)) and (Text[Position] = ' ') do
  begin
    Inc(Position);
  end;
  Result := '';
  if Position > Length(Text) then
  begin
    Exit;
  end;
  mStart := Position;
  if CharInSet(Text[Position], ['A'..'Z', 'a'..'z']) then
  begin
    while (mStart <= Length(Text)) and CharInSet(Text[mStart], ['A'..'Z', 'a'..'z', '0'..'9']) do
    begin
      Inc(mStart);
    end;
    Result := Copy(Text, Position, mStart - Position);
  end
  else if Copy(Text, Position, 2) = '<>' then
  begin
    Result := '<>';
  end
  else
  begin
    Result := Text[Position];
  end;
end;

function TEvaluator.Next: string;
begin
  Result := Peek;
  Inc(Position, Length(Result));
end;

function TEvaluator.Value(const AName: string): Boolean;
var
  mItem: string;
begin
  if SameText(AName, 'True') then
  begin
    Exit(True);
  end;
  if SameText(AName, 'False') then
  begin
    Exit(False);
  end;
  for mItem in Values do
  begin
    if SameText(Copy(mItem, 1, Pos('=', mItem) - 1), AName) then
    begin
      Exit(Copy(mItem, Pos('=', mItem) + 1, MaxInt) = '1');
    end;
  end;
  raise Exception.Create('Unbekannt: ' + AName);
end;

function TEvaluator.Factor: Boolean;
var
  mToken: string;
begin
  mToken := Next;
  if SameText(mToken, 'not') then
  begin
    Exit(not Factor);
  end;
  if mToken = '(' then
  begin
    Result := Expression;
    Next;
    Exit;
  end;
  Result := Value(mToken);
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
  mOp: string;
  mRight: Boolean;
begin
  Result := Term;
  while SameText(Peek, 'or') or SameText(Peek, 'xor') do
  begin
    mOp := LowerCase(Next);
    mRight := Term;
    if mOp = 'or' then
    begin
      Result := Result or mRight;
    end
    else
    begin
      Result := Result xor mRight;
    end;
  end;
end;

function TEvaluator.Expression: Boolean;
var
  mOp: string;
  mRight: Boolean;
begin
  Result := Simple;
  mOp := Peek;
  if (mOp = '=') or (mOp = '<>') then
  begin
    Next;
    mRight := Simple;
    if mOp = '=' then
    begin
      Result := Result = mRight;
    end
    else
    begin
      Result := Result <> mRight;
    end;
  end;
end;

function Evaluate(const AText: string; const AValues: TArray<string>): Boolean;
var
  mEvaluator: TEvaluator;
begin
  mEvaluator.Text := AText;
  mEvaluator.Position := 1;
  mEvaluator.Values := AValues;
  Result := mEvaluator.Expression;
  Assert.AreEqual('', mEvaluator.Peek, 'Rest in ' + AText);
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
  cExpressions: array[0..13] of string = ('X', 'not X', 'X and A', 'A or X', 'not (X or A)', 'X = False',
    'X <> A', '(X)', 'not (not X and A)', 'X xor A', 'not (X = A) and B', '(X or A) and (B or not X)',
    'True = X', 'not ((X))');
var
  mExpression, mRewritten, mAssigned: string;
  mBits: Integer;
  mValues, mInverted: TArray<string>;
begin
  for mExpression in cExpressions do
  begin
    mRewritten := Statement(Invert(InProc('  R := ' + mExpression + ';'), 'X', 'Y'));
    mRewritten := Copy(mRewritten, Length('  R := ') + 1, Length(mRewritten) - Length('  R := ;'));
    mAssigned := Statement(Invert(InProc('  X := ' + mExpression + ';'), 'X', 'Y'));
    Assert.IsTrue(StartsStr('  Y := ', mAssigned), mAssigned);
    mAssigned := Copy(mAssigned, Length('  Y := ') + 1, Length(mAssigned) - Length('  Y := ;'));
    for mBits := 0 to 7 do
    begin
      mValues := ['X=' + IntToStr(mBits and 1), 'A=' + IntToStr((mBits shr 1) and 1), 'B=' + IntToStr((mBits shr 2) and 1)];
      mInverted := ['Y=' + IntToStr(1 - (mBits and 1)), mValues[1], mValues[2]];
      Assert.AreEqual(Evaluate(mExpression, mValues), Evaluate(mRewritten, mInverted), mExpression + ' → ' + mRewritten);
      // Zuweisung an X: Y bekommt den Gegenwert.
      Assert.AreEqual(not Evaluate(mExpression, mValues), Evaluate(mAssigned, mInverted), mExpression + ' → ' + mAssigned);
    end;
  end;
end;

procedure TInvertBooleanTests.FunctionBodyReturnsOpposite;
const
  cSource =
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
  mWarnings: TArray<TInvertWarning>;
  mText: string;
begin
  mText := RewriteWith(cSource,
    procedure(ATree: TSyntaxTree; var ATargets: TInvertTargets)
    var
      Offsets: TArray<Integer>;
    begin
      AddNames(ATree, ATargets, 'IsEmpty', 'HasItems', True);
      Offsets := OffsetsOf(ATree, 'IsEmpty');
      // Name im Rumpfkopf (zweites Vorkommen).
      ATargets.AddBody(Offsets[1]);
    end, mWarnings);
  Assert.Contains(mText, '    function HasItems: Boolean;');
  Assert.Contains(mText, 'function TFoo.HasItems: Boolean;');
  Assert.Contains(mText, '    Exit(False);');
  Assert.Contains(mText, '  Result := not (Inner and (Count < 0));');
  Assert.Contains(mText, '  if not Result then');
  // Die lokale Funktion hat ihr eigenes Result.
  Assert.Contains(mText, '    Result := True;');
  Assert.Contains(mText, '  if not F.HasItems then');
  Assert.Contains(mText, '  F.HasItems;');
end;

procedure TInvertBooleanTests.SetterParameterAndCalls;
const
  cSource =
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
  mWarnings: TArray<TInvertWarning>;
  mText: string;
begin
  mText := RewriteWith(cSource,
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
      begin
        Assert.IsTrue(Offset > 0);
      end;
    end, mWarnings);
  Assert.Contains(mText, '    FVisible: Boolean;');
  Assert.Contains(mText, '    procedure SetVisible(const Value: Boolean);');
  Assert.Contains(mText, '    property Visible: Boolean read FVisible write SetVisible;');
  Assert.Contains(mText, '  if Value = FVisible then');
  Assert.Contains(mText, '  FVisible := Value;');
  Assert.Contains(mText, '  Panel.Visible := Value;');
  Assert.Contains(mText, '  F.SetVisible(not (A and B));');
  Assert.Contains(mText, '  F.Visible := False;');
end;

procedure TInvertBooleanTests.VarArgumentIsReported;
var
  mWarnings: TArray<TInvertWarning>;
  mText: string;
begin
  mText := RewriteWith(InProc('  Toggle(X, X);'#13#10'  Watch(@X);'),
    procedure(ATree: TSyntaxTree; var ATargets: TInvertTargets)
    begin
      AddNames(ATree, ATargets, 'X', 'Y', True);
      ATargets.VarArgument :=
        function(ACall: TSyntaxNode; AArgument: Integer): Boolean
        begin
          Result := AArgument = 0;
        end;
    end, mWarnings);
  Assert.AreEqual('  Toggle(Y, not Y);'#13#10'  Watch(@Y);', Statement(mText));
  Assert.AreEqual(2, Integer(Length(mWarnings)));
  Assert.AreEqual(5, mWarnings[0].Position.Line);
  Assert.AreEqual(9, mWarnings[0].Position.Character);
  Assert.AreEqual(6, mWarnings[1].Position.Line);
  Assert.AreEqual(8, mWarnings[1].Position.Character);
end;

procedure TInvertBooleanTests.InitialValuesAreNegated;
const
  cSource =
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
  mText: string;
begin
  mText := Invert(cSource, 'X', 'Y');
  Assert.Contains(mText, '  Y: Boolean = False;');
  Assert.Contains(mText, '  Z: Boolean = not Y;');
  Assert.Contains(mText, '  var L := Y;');
end;

procedure TInvertBooleanTests.AnonymousMethodIsRewritten;
begin
  Assert.AreEqual('  Run(procedure begin Y := False; if Y then Go; end, not Y);',
    Statement(Invert(InProc('  Run(procedure begin X := True; if not X then Go; end, X);'), 'X', 'Y')));
end;

procedure TInvertBooleanTests.DfmValuesAreInverted;
const
  cDfm =
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
  mWarnings: TArray<TInvertWarning>;
  mText: string;
begin
  mText := TChangeSignature.ApplyEdits(cDfm, TInvertBoolean.DfmEdits(cDfm, ['TFooPanel'], 'Hidden', 'Visible',
    mWarnings));
  Assert.Contains(mText, '  object Panel1: TFooPanel'#13#10'    Visible = False');
  Assert.Contains(mText, '  object Panel2: TFooPanel'#13#10'    Visible = Maybe');
  Assert.Contains(mText, '  object Other: TOther'#13#10'    Hidden = True');
  Assert.AreEqual(1, Integer(Length(mWarnings)));
  Assert.AreEqual(5, mWarnings[0].Position.Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TInvertBooleanTests);

end.
