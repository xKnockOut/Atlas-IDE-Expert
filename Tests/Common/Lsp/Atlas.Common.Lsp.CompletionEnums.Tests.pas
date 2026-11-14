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
  mIndex, mLine, mCharacter: Integer;
begin
  mLine := 0;
  mCharacter := 0;
  for mIndex := 1 to Pos('|', AMarked) - 1 do
  begin
    if AMarked[mIndex] = #10 then
    begin
      Inc(mLine);
      mCharacter := 0;
    end
    else
    begin
      Inc(mCharacter);
    end;
  end;
  APosition := TTextPosition.Create(mLine, mCharacter);
  Result := TPascalLexer.Tokenize(StringReplace(AMarked, '|', '', []));
end;

function ValueNames(const AMarked: string): string;
var
  mPosition: TTextPosition;
  mTokens: TArray<TPascalToken>;
  mSlot: TEnumValueSlot;
begin
  mTokens := Split(AMarked, mPosition);
  if TCompletionEnums.ValueSlot(mTokens, mPosition, mSlot) then
  begin
    Result := string.Join('.', mSlot.Names);
  end
  else
  begin
    Result := '-';
  end;
end;

function SetText(const AMarked: string; out ASlot: TEnumSetSlot): Boolean;
var
  mPosition: TTextPosition;
  mTokens: TArray<TPascalToken>;
begin
  mTokens := Split(AMarked, mPosition);
  Result := TCompletionEnums.SetSlot(mTokens, mPosition, ASlot);
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
  mSlot: TEnumSetSlot;
begin
  Assert.IsTrue(SetText('Anchors := [akLeft, |]', mSlot));
  Assert.AreEqual(0, Integer(Length(mSlot.ElementOf)));
  Assert.AreEqual('akLeft', string.Join(',', mSlot.Present));
  Assert.AreEqual(11, mSlot.EditRange.StartPos.Character);
  Assert.AreEqual(21, mSlot.EditRange.EndPos.Character, 'bis hinter "]"');
  // Das Wort am Cursor zählt nicht als enthalten; was danach in der Klammer steht, schon.
  Assert.IsTrue(SetText('Anchors := [akLeft, ak|, akTop];', mSlot));
  Assert.AreEqual('akLeft,akTop', string.Join(',', mSlot.Present));
  // Offene Klammer: nur bis zum Cursor; die nächste Zeile gehört nicht dazu.
  Assert.IsTrue(SetText('Anchors := [akLeft, |'#10'  Foo;', mSlot));
  Assert.AreEqual('akLeft', string.Join(',', mSlot.Present));
  Assert.AreEqual(0, mSlot.EditRange.EndPos.Line);
  Assert.AreEqual(20, mSlot.EditRange.EndPos.Character);
  // "in": Elementtyp aus der Kette links; Bereiche und qualifizierte Werte bleiben stehen.
  Assert.IsTrue(SetText('if Shape.Kind in [skCircle..skRect, TShapeKind.skLine, |]', mSlot));
  Assert.AreEqual('Shape.Kind', string.Join('.', mSlot.ElementOf));
  Assert.AreEqual('skCircle..skRect|TShapeKind.skLine', string.Join('|', mSlot.Present));
end;

procedure TCompletionEnumsTests.IgnoresIndexes;
var
  mSlot: TEnumSetSlot;
begin
  Assert.IsFalse(SetText('X := List[|', mSlot));
  Assert.IsFalse(SetText('X := F(x)[|', mSlot));
  Assert.IsFalse(SetText('X := P^[|', mSlot));
  Assert.IsFalse(SetText('X := (|', mSlot));
  Assert.IsFalse(SetText('X := [A + |', mSlot), 'Ausdruck statt Werteliste');
end;

procedure TCompletionEnumsTests.ReadsDeclarations;
var
  mValues: TArray<string>;
begin
  mValues := TCompletionEnums.EnumValues('TAlign = (alNone, alTop = 2, {x} alBottom, // y'#10'  alLeft);');
  Assert.AreEqual('alNone,alTop,alBottom,alLeft', string.Join(',', mValues));
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
  mChecked: TArray<Boolean>;
begin
  Assert.IsTrue(TCompletionEnums.Checked(['a', 'b', 'c', 'd'], ['b..c', 'T.a'], mChecked));
  Assert.IsTrue(mChecked[0]);
  Assert.IsTrue(mChecked[1]);
  Assert.IsTrue(mChecked[2]);
  Assert.IsFalse(mChecked[3]);
  // Unbekannte Namen (Variablen, Konstanten): die Klammer lässt sich nicht neu schreiben.
  Assert.IsFalse(TCompletionEnums.Checked(['a', 'b'], ['Standard'], mChecked));
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionEnumsTests);

end.
