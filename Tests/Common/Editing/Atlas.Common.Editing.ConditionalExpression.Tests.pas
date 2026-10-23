unit Atlas.Common.Editing.ConditionalExpression.Tests;

// Tests für „if-Anweisung und Bedingungsausdruck umwandeln“ (#684): Zuweisung,
// Exit und Aufruf in beide Richtungen, else-if-Ketten und verschachtelte
// Ausdrücke, Klammern nach Vorrang, unverträgliche oder unbekannte Typen,
// Seiteneffekte, Grenze von zwei Bedingungen, Inline-Variable, IfThen und
// Hin- und Rückweg. Jedes Ergebnis muss fehlerfrei parsen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConditionalExpressionTests = class
  public
    [Test]
    procedure AssignmentBecomesExpression;
    [Test]
    procedure ExitAndCallBecomeExpression;
    [Test]
    procedure ElseIfChainUpToTwoConditions;
    [Test]
    procedure NeedsElseSameFormAndOneStatement;
    [Test]
    procedure TypesMustBeKnownAndCompatible;
    [Test]
    procedure SideEffectsOnlyInExit;
    [Test]
    procedure ExpressionBecomesStatement;
    [Test]
    procedure NestedExpressionsBecomeChain;
    [Test]
    procedure StatementKeepsPrecedence;
    [Test]
    procedure InlineVarNeedsType;
    [Test]
    procedure NoStatementWhenRestIsUnsafe;
    [Test]
    procedure ReplacesIfThen;
    [Test]
    procedure CommentsBlockTheAction;
    [Test]
    procedure RoundTrip;
    [Test]
    procedure CompatibleKinds;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.StatementText,
  Atlas.Common.Editing.ConditionalExpression,
  Atlas.Text.Lines;

type
  TConversionKind = (ckToExpression, ckToStatement, ckIfThen);

/// <summary>Programm mit der Routine Run und den Anweisungen ABody.</summary>
function Source(const ABody: string): string;
begin
  Result := 'program P;'#10'procedure Run;'#10'var'#10'  X, I: Integer;'#10'begin'#10 + ABody + 'end;'#10 +
    'begin'#10'end.'#10;
end;

/// <summary>Typ nach dem Namen: X, I, N und F ganzzahlig, S Text, Ready logisch, P und Q TFoo, R TBar.</summary>
function NameType(ANode: TSyntaxNode): TValueType;
var
  Name: string;
begin
  Result := TValueType.Create(TValueKind.Unknown, '');
  Name := ANode.Name;
  if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) then
    Name := ANode[0].Name;
  if MatchText(Name, ['X', 'I', 'N', 'F', 'G']) then
    Result := TValueType.Create(TValueKind.Whole, '')
  else if SameText(Name, 'S') then
    Result := TValueType.Create(TValueKind.Text, '')
  else if SameText(Name, 'Ready') then
    Result := TValueType.Create(TValueKind.Logical, '')
  else if MatchText(Name, ['P', 'Q']) then
    Result := TValueType.Create(TValueKind.Named, 'TFoo')
  else if SameText(Name, 'R') then
    Result := TValueType.Create(TValueKind.Named, 'TBar');
end;

/// <summary>IfThen aus System.Math, außer der Name ist anders.</summary>
function MathIfThen(ACall: TSyntaxNode; out ADefault: string): Boolean;
begin
  ADefault := '0';
  Result := SameText(ACall[0].Name, 'IfThen');
end;

function Lookup: TConditionalLookup;
begin
  Result.ValueType := NameType;
  Result.IfThen := MathIfThen;
end;

function ApplyEdit(const AText: string; const AEdit: TTextEdit): string;
var
  Lines: TLineTable;
  Start, Stop: Integer;
begin
  Lines := TLineTable.Build(AText);
  Start := Lines.OffsetAt(AEdit.Range.StartPos);
  Stop := Lines.OffsetAt(AEdit.Range.EndPos);
  Result := Copy(AText, 1, Start) + AEdit.NewText + Copy(AText, Stop + 1, MaxInt);
end;

function PositionOf(const AText, AMarker: string): TTextPosition;
begin
  Result := TLineTable.Build(AText).PositionAt(Pos(AMarker, AText) - 1);
end;

/// <summary>Umwandlung AKind an AMarker mit ALookup; das Ergebnis muss fehlerfrei parsen.</summary>
function Convert(const AText, AMarker: string; AKind: TConversionKind; const ALookup: TConditionalLookup;
  out AResult: string): Boolean;
var
  Tree, Check: TSyntaxTree;
  Done: TStatementRewrite;
  Position: TTextPosition;
begin
  AResult := '';
  Tree := TPascalParser.Parse(AText);
  try
    Position := PositionOf(AText, AMarker);
    case AKind of
      ckToExpression:
        Result := TConditionalExpression.ToExpression(AText, Tree, Position, ALookup, Done);
      ckToStatement:
        Result := TConditionalExpression.ToStatement(AText, Tree, Position, TStatementLayout.Create('', '  ', #10),
          Done);
    else
      Result := TConditionalExpression.ReplaceIfThen(AText, Tree, Position, ALookup, Done);
    end;
    if Result then
    begin
      AResult := ApplyEdit(AText, Done.Edit);
      Check := TPascalParser.Parse(AResult);
      try
        Assert.AreEqual(0, Integer(Length(Check.Diagnostics)), AResult);
      finally
        Check.Free;
      end;
    end;
  finally
    Tree.Free;
  end;
end;

function Converted(const AText, AMarker: string; AKind: TConversionKind): string;
begin
  Assert.IsTrue(Convert(AText, AMarker, AKind, Lookup, Result), 'Aktion fehlt: ' + AText);
end;

function Offered(const AText, AMarker: string; AKind: TConversionKind): Boolean;
var
  Text: string;
begin
  Result := Convert(AText, AMarker, AKind, Lookup, Text);
end;

procedure TConditionalExpressionTests.AssignmentBecomesExpression;
begin
  Assert.AreEqual(Source('  X := if I > 0 then 1 else 2;'#10),
    Converted(Source('  if I > 0 then'#10'    X := 1'#10'  else'#10'    X := 2;'#10), 'if', ckToExpression));
  // begin … end mit einer Anweisung zählt wie die Anweisung.
  Assert.AreEqual(Source('  X := if Ready then I else N;'#10), Converted(Source('  if Ready then'#10'  begin'#10 +
    '    X := I;'#10'  end'#10'  else'#10'    X := N;'#10), 'if', ckToExpression));
  // Ein Bedingungsausdruck als Wert vor else bekommt Klammern.
  Assert.AreEqual(Source('  X := if Ready then (if I > 0 then 1 else 2) else 3;'#10),
    Converted(Source('  if Ready then'#10'    X := if I > 0 then 1 else 2'#10'  else'#10'    X := 3;'#10), 'if Ready',
    ckToExpression));
end;

procedure TConditionalExpressionTests.ExitAndCallBecomeExpression;
begin
  Assert.AreEqual(Source('  Exit(if Ready then 1 else 2);'#10),
    Converted(Source('  if Ready then'#10'    Exit(1)'#10'  else'#10'    Exit(2);'#10), 'if', ckToExpression));
  Assert.AreEqual(Source('  Log(I, if Ready then ''a'' else ''b'');'#10),
    Converted(Source('  if Ready then'#10'    Log(I, ''a'')'#10'  else'#10'    Log(I, ''b'');'#10), 'if',
    ckToExpression));
  // Zwei verschiedene Argumente oder verschiedene Aufrufe: keine Aktion.
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    Log(1, ''a'')'#10'  else'#10'    Log(2, ''b'');'#10), 'if',
    ckToExpression));
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    Log(''a'')'#10'  else'#10'    Show(''b'');'#10), 'if',
    ckToExpression));
  // Gleiche Aufrufe: nichts zu verbinden.
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    Log(''a'')'#10'  else'#10'    Log(''a'');'#10), 'if',
    ckToExpression));
end;

procedure TConditionalExpressionTests.ElseIfChainUpToTwoConditions;
begin
  Assert.AreEqual(Source('  X := if I = 1 then 10 else if I = 2 then 20 else 30;'#10),
    Converted(Source('  if I = 1 then'#10'    X := 10'#10'  else if I = 2 then'#10'    X := 20'#10'  else'#10 +
    '    X := 30;'#10), 'if I = 1', ckToExpression));
  // Ab drei Bedingungen gibt es case (#646) statt eines Ausdrucks.
  Assert.IsFalse(Offered(Source('  if I = 1 then'#10'    X := 10'#10'  else if I = 2 then'#10'    X := 20'#10 +
    '  else if I = 3 then'#10'    X := 30'#10'  else'#10'    X := 40;'#10), 'if I = 1', ckToExpression));
end;

procedure TConditionalExpressionTests.NeedsElseSameFormAndOneStatement;
begin
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    X := 1;'#10), 'if', ckToExpression));
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    X := 1'#10'  else'#10'    I := 2;'#10), 'if',
    ckToExpression));
  Assert.IsFalse(Offered(Source('  if Ready then'#10'  begin'#10'    X := 1;'#10'    I := 1;'#10'  end'#10'  else'#10 +
    '    X := 2;'#10), 'if', ckToExpression));
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    X := 1'#10'  else'#10'    Exit(2);'#10), 'if',
    ckToExpression));
  // else-if-Kette ohne abschließendes else.
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    X := 1'#10'  else if I = 2 then'#10'    X := 2;'#10), 'if',
    ckToExpression));
end;

procedure TConditionalExpressionTests.TypesMustBeKnownAndCompatible;
var
  Text: string;
begin
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    Log(''a'')'#10'  else'#10'    Log(1);'#10), 'if',
    ckToExpression));
  // Ganzzahl und Gleitkomma passen zusammen, nil zu einem Klassentyp.
  Assert.IsTrue(Offered(Source('  if Ready then'#10'    Log(1)'#10'  else'#10'    Log(2.5);'#10), 'if',
    ckToExpression));
  Assert.IsTrue(Offered(Source('  if Ready then'#10'    Use(P)'#10'  else'#10'    Use(nil);'#10), 'if',
    ckToExpression));
  Assert.IsTrue(Offered(Source('  if Ready then'#10'    Use(P)'#10'  else'#10'    Use(Q);'#10), 'if',
    ckToExpression));
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    Use(P)'#10'  else'#10'    Use(R);'#10), 'if',
    ckToExpression));
  // Unbekannter Typ: keine Aktion.
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    Use(Unknown1)'#10'  else'#10'    Use(Unknown2);'#10), 'if',
    ckToExpression));
  Text := Source('  if Ready then'#10'    X := I'#10'  else'#10'    X := N;'#10);
  Assert.IsFalse(Convert(Text, 'if', ckToExpression, Default(TConditionalLookup), Text));
end;

procedure TConditionalExpressionTests.SideEffectsOnlyInExit;
begin
  // Die Funktionen liefen sonst zusammen mit den übrigen Argumenten in anderer Reihenfolge.
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    Log(F(1))'#10'  else'#10'    Log(G(2));'#10), 'if',
    ckToExpression));
  // Gleiche Argumente mit Seiteneffekt liefen vor der Bedingung.
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    Log(F(1), ''a'')'#10'  else'#10'    Log(F(1), ''b'');'#10),
    'if', ckToExpression));
  Assert.AreEqual(Source('  Exit(if Ready then F(1) else G(2));'#10),
    Converted(Source('  if Ready then'#10'    Exit(F(1))'#10'  else'#10'    Exit(G(2));'#10), 'if', ckToExpression));
end;

procedure TConditionalExpressionTests.ExpressionBecomesStatement;
begin
  Assert.AreEqual(Source('  if I > 0 then'#10'    X := 1'#10'  else'#10'    X := 2;'#10),
    Converted(Source('  X := if I > 0 then 1 else 2;'#10), 'if', ckToStatement));
  Assert.AreEqual(Source('  if Ready then'#10'    Exit(1)'#10'  else'#10'    Exit(2);'#10),
    Converted(Source('  Exit(if Ready then 1 else 2);'#10), 'if', ckToStatement));
  Assert.AreEqual(Source('  if Ready then'#10'    Log(I, ''a'')'#10'  else'#10'    Log(I, ''b'');'#10),
    Converted(Source('  Log(I, if Ready then ''a'' else ''b'');'#10), 'if', ckToStatement));
  // Auch aus einem Teil des Ausdrucks heraus; Klammern um den Ausdruck fallen weg.
  Assert.AreEqual(Source('  if Ready then'#10'    X := 1'#10'  else'#10'    X := 2;'#10),
    Converted(Source('  X := (if Ready then 1 else 2);'#10), 'then 1', ckToStatement));
  // Ohne Bedingungsausdruck nichts.
  Assert.IsFalse(Offered(Source('  X := 1;'#10), 'X', ckToStatement));
end;

procedure TConditionalExpressionTests.NestedExpressionsBecomeChain;
begin
  Assert.AreEqual(Source('  if I = 1 then'#10'    X := 10'#10'  else if I = 2 then'#10'    X := 20'#10'  else'#10 +
    '    X := 30;'#10), Converted(Source('  X := if I = 1 then 10 else if I = 2 then 20 else 30;'#10), 'I = 2',
    ckToStatement));
  // Ein Ausdruck vor else wird ein inneres if in begin … end.
  Assert.AreEqual(Source('  if Ready then'#10'  begin'#10'    if I > 0 then'#10'      X := 1'#10'    else'#10 +
    '      X := 2;'#10'  end'#10'  else'#10'    X := 3;'#10),
    Converted(Source('  X := if Ready then (if I > 0 then 1 else 2) else 3;'#10), 'if Ready', ckToStatement));
end;

procedure TConditionalExpressionTests.StatementKeepsPrecedence;
begin
  Assert.AreEqual(Source('  if Ready then'#10'    X := (I + 1) * 3'#10'  else'#10'    X := 2 * 3;'#10),
    Converted(Source('  X := (if Ready then I + 1 else 2) * 3;'#10), 'if', ckToStatement));
  Assert.AreEqual(Source('  if Ready then'#10'    X := 1 + I'#10'  else'#10'    X := 1 + 2;'#10),
    Converted(Source('  X := 1 + (if Ready then I else 2);'#10), 'if', ckToStatement));
end;

procedure TConditionalExpressionTests.InlineVarNeedsType;
begin
  Assert.AreEqual(Source('  var Y: Integer;'#10'  if Ready then'#10'    Y := 1'#10'  else'#10'    Y := 2;'#10),
    Converted(Source('  var Y: Integer := if Ready then 1 else 2;'#10), 'if', ckToStatement));
  Assert.IsFalse(Offered(Source('  var Y := if Ready then 1 else 2;'#10), 'if', ckToStatement));
end;

procedure TConditionalExpressionTests.NoStatementWhenRestIsUnsafe;
begin
  // F(1) liefe sonst nach der Bedingung statt davor.
  Assert.IsFalse(Offered(Source('  Items[F(1)] := if Ready then 1 else 2;'#10), 'if', ckToStatement));
  Assert.IsFalse(Offered(Source('  Log(F(1), if Ready then 1 else 2);'#10), 'if', ckToStatement));
  // Zwei Ausdrücke in einer Anweisung.
  Assert.IsFalse(Offered(Source('  Log(if Ready then 1 else 2, if I > 0 then 3 else 4);'#10), 'if Ready',
    ckToStatement));
  // Reine Funktionen dürfen bleiben.
  Assert.IsTrue(Offered(Source('  Log(Length(S), if Ready then 1 else 2);'#10), 'if', ckToStatement));
end;

procedure TConditionalExpressionTests.ReplacesIfThen;
begin
  Assert.AreEqual(Source('  X := if Ready then 1 else 2;'#10),
    Converted(Source('  X := IfThen(Ready, 1, 2);'#10), 'IfThen', ckIfThen));
  // Ohne drittes Argument der Vorgabewert der Unit.
  Assert.AreEqual(Source('  X := if Ready then 1 else 0;'#10),
    Converted(Source('  X := IfThen(Ready, 1);'#10), 'Ready', ckIfThen));
  // Als Operand Klammern, als Wert vor then bzw. else ebenso.
  Assert.AreEqual(Source('  X := (if Ready then 1 else 2) + 1;'#10),
    Converted(Source('  X := IfThen(Ready, 1, 2) + 1;'#10), 'IfThen', ckIfThen));
  Assert.AreEqual(Source('  X := if I > 0 then (if Ready then 1 else 2) else 3;'#10),
    Converted(Source('  X := if I > 0 then IfThen(Ready, 1, 2) else 3;'#10), 'IfThen', ckIfThen));
  // Ein anderes IfThen (Lookup sagt nein): keine Aktion.
  Assert.IsFalse(Offered(Source('  X := IfThenOther(Ready, 1, 2);'#10), 'IfThen', ckIfThen));
end;

procedure TConditionalExpressionTests.CommentsBlockTheAction;
begin
  Assert.IsFalse(Offered(Source('  if Ready then'#10'    X := 1 // eins'#10'  else'#10'    X := 2;'#10), 'if',
    ckToExpression));
  Assert.IsFalse(Offered(Source('  X := if Ready then 1 { eins } else 2;'#10), 'if', ckToStatement));
  Assert.IsFalse(Offered(Source('  X := IfThen(Ready, 1 { eins }, 2);'#10), 'IfThen', ckIfThen));
end;

procedure TConditionalExpressionTests.RoundTrip;
var
  Text: string;
begin
  Text := Source('  if I = 1 then'#10'    X := 10'#10'  else if I = 2 then'#10'    X := 20'#10'  else'#10 +
    '    X := 30;'#10);
  Assert.AreEqual(Text, Converted(Converted(Text, 'if I = 1', ckToExpression), 'if', ckToStatement));
end;

procedure TConditionalExpressionTests.CompatibleKinds;
begin
  Assert.IsTrue(TConditionalExpression.Compatible(TValueType.Create(TValueKind.Whole, ''),
    TValueType.Create(TValueKind.Float, '')));
  Assert.IsTrue(TConditionalExpression.Compatible(TValueType.Create(TValueKind.NilValue, ''),
    TValueType.Create(TValueKind.Named, 'TFoo')));
  Assert.IsFalse(TConditionalExpression.Compatible(TValueType.Create(TValueKind.NilValue, ''),
    TValueType.Create(TValueKind.Whole, '')));
  Assert.IsFalse(TConditionalExpression.Compatible(TValueType.Create(TValueKind.Text, ''),
    TValueType.Create(TValueKind.Whole, '')));
  Assert.IsFalse(TConditionalExpression.Compatible(TValueType.Create(TValueKind.Unknown, ''),
    TValueType.Create(TValueKind.Unknown, '')));
  Assert.IsTrue(TConditionalExpression.Compatible(TValueType.Create(TValueKind.Named, 'TFoo'),
    TValueType.Create(TValueKind.Named, 'tfoo')));
end;

initialization
  TDUnitX.RegisterTestFixture(TConditionalExpressionTests);

end.
