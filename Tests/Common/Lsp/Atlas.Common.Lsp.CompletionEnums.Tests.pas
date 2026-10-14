unit Atlas.Common.Lsp.CompletionEnums.Tests;

// Tests für Aufzählungen und Mengen in der Vervollständigung (#448), Teil ohne Namensauflösung.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.CompletionEnums;

type
  [TestFixture]
  TCompletionEnumsTests = class
  public
    [Test]
    procedure FindsComparisonsAndCaseBranches;
    [Test]
    procedure IgnoresOtherPlaces;
    [Test]
    procedure FindsSetConstructors;
    [Test]
    procedure IgnoresIndexes;
    [Test]
    procedure ReadsDeclarations;
    [Test]
    procedure MarksPresentValues;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer;

/// <summary>Text ohne "|" und die Position des "|".</summary>
function Split(const AMarked: string; out APosition: TTextPosition): TArray<TPascalToken>;
var
  Index, Line, Character: Integer;
begin
  Line := 0;
  Character := 0;
  for Index := 1 to Pos('|', AMarked) - 1 do
    if AMarked[Index] = #10 then
    begin
      Inc(Line);
      Character := 0;
    end
    else
      Inc(Character);
  APosition := TTextPosition.Create(Line, Character);
  Result := TPascalLexer.Tokenize(StringReplace(AMarked, '|', '', []));
end;

function ValueNames(const AMarked: string): string;
var
  Position: TTextPosition;
  Tokens: TArray<TPascalToken>;
  Slot: TEnumValueSlot;
begin
  Tokens := Split(AMarked, Position);
  if TCompletionEnums.ValueSlot(Tokens, Position, Slot) then
    Result := string.Join('.', Slot.Names)
  else
    Result := '-';
end;

function SetText(const AMarked: string; out ASlot: TEnumSetSlot): Boolean;
var
  Position: TTextPosition;
  Tokens: TArray<TPascalToken>;
begin
  Tokens := Split(AMarked, Position);
  Result := TCompletionEnums.SetSlot(Tokens, Position, ASlot);
end;

{ TCompletionEnumsTests }

procedure TCompletionEnumsTests.FindsComparisonsAndCaseBranches;
begin
  Assert.AreEqual('Shape.Kind', ValueNames('if Shape.Kind = |'));
  Assert.AreEqual('Shape.Kind', ValueNames('if Shape.Kind <> sk|'));
  Assert.AreEqual('Shape.Kind', ValueNames('case Shape.Kind of'#10'  |'));
  Assert.AreEqual('Shape.Kind', ValueNames('case Shape.Kind of'#10'  skCircle: Foo;'#10'  |'));
  Assert.AreEqual('Shape.Kind', ValueNames('case Shape.Kind of'#10'  skCircle, sk|'));
  Assert.AreEqual('Shape.Kind', ValueNames('case Shape.Kind of'#10'  skCircle: if A then B else C;'#10'  |'));
  // Eine innere case-Anweisung ist mit ihrem end abgeschlossen.
  Assert.AreEqual('Shape.Kind', ValueNames('case Shape.Kind of'#10'  skCircle: case X of a: ; end;'#10'  |'));
end;

procedure TCompletionEnumsTests.IgnoresOtherPlaces;
begin
  // Mitten in einem Zweig, in Aufrufen, Deklarationen und bei anderen Ausdrücken nach case.
  Assert.AreEqual('-', ValueNames('case Shape.Kind of'#10'  skCircle: begin A; |'));
  Assert.AreEqual('-', ValueNames('Foo(a, |'));
  Assert.AreEqual('-', ValueNames('var a, |'));
  Assert.AreEqual('-', ValueNames('case F(x) of'#10'  |'));
  Assert.AreEqual('-', ValueNames('X := |'));
end;

procedure TCompletionEnumsTests.FindsSetConstructors;
var
  Slot: TEnumSetSlot;
begin
  Assert.IsTrue(SetText('Anchors := [akLeft, |]', Slot));
  Assert.AreEqual(0, Integer(Length(Slot.ElementOf)));
  Assert.AreEqual('akLeft', string.Join(',', Slot.Present));
  Assert.AreEqual(11, Slot.EditRange.StartPos.Character);
  Assert.AreEqual(21, Slot.EditRange.EndPos.Character, 'bis hinter "]"');
  // Das Wort am Cursor zählt nicht als enthalten; was danach in der Klammer steht, schon.
  Assert.IsTrue(SetText('Anchors := [akLeft, ak|, akTop];', Slot));
  Assert.AreEqual('akLeft,akTop', string.Join(',', Slot.Present));
  // Offene Klammer: nur bis zum Cursor; die nächste Zeile gehört nicht dazu.
  Assert.IsTrue(SetText('Anchors := [akLeft, |'#10'  Foo;', Slot));
  Assert.AreEqual('akLeft', string.Join(',', Slot.Present));
  Assert.AreEqual(0, Slot.EditRange.EndPos.Line);
  Assert.AreEqual(20, Slot.EditRange.EndPos.Character);
  // "in": Elementtyp aus der Kette links; Bereiche und qualifizierte Werte bleiben stehen.
  Assert.IsTrue(SetText('if Shape.Kind in [skCircle..skRect, TShapeKind.skLine, |]', Slot));
  Assert.AreEqual('Shape.Kind', string.Join('.', Slot.ElementOf));
  Assert.AreEqual('skCircle..skRect|TShapeKind.skLine', string.Join('|', Slot.Present));
end;

procedure TCompletionEnumsTests.IgnoresIndexes;
var
  Slot: TEnumSetSlot;
begin
  Assert.IsFalse(SetText('X := List[|', Slot));
  Assert.IsFalse(SetText('X := F(x)[|', Slot));
  Assert.IsFalse(SetText('X := P^[|', Slot));
  Assert.IsFalse(SetText('X := (|', Slot));
  Assert.IsFalse(SetText('X := [A + |', Slot), 'Ausdruck statt Werteliste');
end;

procedure TCompletionEnumsTests.ReadsDeclarations;
var
  Values: TArray<string>;
begin
  Values := TCompletionEnums.EnumValues('TAlign = (alNone, alTop = 2, {x} alBottom, // y'#10'  alLeft);');
  Assert.AreEqual('alNone,alTop,alBottom,alLeft', string.Join(',', Values));
  Assert.AreEqual(0, Integer(Length(TCompletionEnums.EnumValues('TFoo = class(TObject)'))));
  Assert.AreEqual('TAnchorKind', TCompletionEnums.SetElement('TAnchors = set of TAnchorKind;'));
  Assert.AreEqual('System.UITypes.TX', TCompletionEnums.SetElement('TS = set of System.UITypes.TX;'));
  Assert.AreEqual('', TCompletionEnums.SetElement('TS = set of (a, b);'));
  Assert.AreEqual('', TCompletionEnums.SetElement('TS = array of Byte;'));
  Assert.IsTrue(TCompletionEnums.ScopedAt('{$SCOPEDENUMS ON} type A = (x);', 20));
  Assert.IsFalse(TCompletionEnums.ScopedAt('{$SCOPEDENUMS ON}{$scopedenums off} type', 40));
  Assert.IsFalse(TCompletionEnums.ScopedAt('type {$SCOPEDENUMS ON}', 3), 'Direktive erst danach');
end;

procedure TCompletionEnumsTests.MarksPresentValues;
var
  Checked: TArray<Boolean>;
begin
  Assert.IsTrue(TCompletionEnums.Checked(['a', 'b', 'c', 'd'], ['b..c', 'T.a'], Checked));
  Assert.IsTrue(Checked[0]);
  Assert.IsTrue(Checked[1]);
  Assert.IsTrue(Checked[2]);
  Assert.IsFalse(Checked[3]);
  // Unbekannte Namen (Variablen, Konstanten): die Klammer lässt sich nicht neu schreiben.
  Assert.IsFalse(TCompletionEnums.Checked(['a', 'b'], ['Standard'], Checked));
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionEnumsTests);

end.
