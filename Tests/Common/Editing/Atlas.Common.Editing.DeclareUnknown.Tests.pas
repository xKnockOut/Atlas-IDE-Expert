unit Atlas.Common.Editing.DeclareUnknown.Tests;

// Tests für das Deklarieren unbekannter Namen (#471), Teil ohne Namensauflösung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclareUnknownTests = class
  public
    [Test]
    procedure FindsAssignmentTargetsAndValues;
    [Test]
    procedure IgnoresMembersCallsAndDeclarations;
    [Test]
    procedure DerivesTypeFromShape;
    [Test]
    procedure FindsTermName;
    [Test]
    procedure NamesFieldsAndValues;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.DeclareUnknown;

/// <summary>Tokens ohne "|" und die Position des "|".</summary>
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

function SlotAt(const AMarked: string; out ATokens: TArray<TPascalToken>; out ASlot: TUnknownSlot): Boolean;
var
  mPosition: TTextPosition;
begin
  ATokens := Split(AMarked, mPosition);
  Result := TDeclareUnknown.Slot(ATokens, mPosition, ASlot);
end;

/// <summary>Typ aus der Form der rechten Seite; bei einem Operanden dessen Text in eckigen Klammern.</summary>
function ShapeOf(const AMarked: string): string;
var
  mTokens: TArray<TPascalToken>;
  mSlot: TUnknownSlot;
  mFirst, mLast, mIndex: Integer;
begin
  if not SlotAt(AMarked, mTokens, mSlot) then
  begin
    Exit('-');
  end;
  Result := TDeclareUnknown.Shape(mTokens, mSlot.ValueFirst, mSlot.ValueLast, mFirst, mLast);
  if (Result = '') and (mFirst >= 0) then
  begin
    Result := '[';
    for mIndex := mFirst to mLast do
    begin
      Result := Result + mTokens[mIndex].Text;
    end;
    Result := Result + ']';
  end;
end;

{ TDeclareUnknownTests }

procedure TDeclareUnknownTests.FindsAssignmentTargetsAndValues;
var
  mTokens: TArray<TPascalToken>;
  mSlot: TUnknownSlot;
begin
  Assert.IsTrue(SlotAt('begin'#10'  TotalCount| := Lines.Count + Extra.Count;'#10'end;', mTokens, mSlot));
  Assert.AreEqual('TotalCount', mSlot.Name);
  Assert.IsTrue(mSlot.AssignTarget);
  Assert.IsTrue(mSlot.InlineAllowed);
  Assert.AreEqual(10, mSlot.CursorOffset);
  Assert.AreEqual('Lines', mTokens[mSlot.ValueFirst].Text);
  Assert.AreEqual('Count', mTokens[mSlot.ValueLast].Text);
  // Cursor mitten im Namen.
  Assert.IsTrue(SlotAt('begin'#10'  Total|Count := 1;'#10'end;', mTokens, mSlot));
  Assert.AreEqual(5, mSlot.CursorOffset);
  // Als Wert: kein Ziel, keine Inline-Variable.
  Assert.IsTrue(SlotAt('begin'#10'  Zeige(Anzahl|);'#10'end;', mTokens, mSlot));
  Assert.IsFalse(mSlot.AssignTarget);
  Assert.IsFalse(mSlot.InlineAllowed);
  // Im then-Zweig ohne begin ist "var" nicht erlaubt.
  Assert.IsTrue(SlotAt('begin'#10'  if A then Summe| := 1;'#10'end;', mTokens, mSlot));
  Assert.IsFalse(mSlot.InlineAllowed);
end;

procedure TDeclareUnknownTests.IgnoresMembersCallsAndDeclarations;
var
  mTokens: TArray<TPascalToken>;
  mSlot: TUnknownSlot;
begin
  Assert.IsFalse(SlotAt('begin'#10'  Liste.Anzahl| := 1;'#10'end;', mTokens, mSlot), 'Mitglied');
  Assert.IsFalse(SlotAt('begin'#10'  Rechne|(1);'#10'end;', mTokens, mSlot), 'Aufruf (#472)');
  Assert.IsFalse(SlotAt('begin'#10'  Objekt|.Free;'#10'end;', mTokens, mSlot), 'Kette');
  Assert.IsFalse(SlotAt('begin'#10'  var Neu| := 1;'#10'end;', mTokens, mSlot), 'Inline-Deklaration');
  Assert.IsFalse(SlotAt('begin'#10'  var I: TLis|;'#10'end;', mTokens, mSlot), 'Typ einer Inline-Deklaration');
  Assert.IsFalse(SlotAt('begin'#10'  X := 1 |'#10'end;', mTokens, mSlot), 'kein Name am Cursor');
end;

procedure TDeclareUnknownTests.DerivesTypeFromShape;
begin
  Assert.AreEqual('[Lines.Count]', ShapeOf('begin'#10'  Total| := Lines.Count + Extra.Count;'#10'end;'));
  Assert.AreEqual('Boolean', ShapeOf('begin'#10'  Fertig| := (A > 1) and B;'#10'end;'));
  Assert.AreEqual('Boolean', ShapeOf('begin'#10'  Drin| := X in [1, 2];'#10'end;'));
  Assert.AreEqual('Extended', ShapeOf('begin'#10'  Anteil| := A / B;'#10'end;'));
  Assert.AreEqual('Integer', ShapeOf('begin'#10'  Haelfte| := A div 2;'#10'end;'));
  Assert.AreEqual('TButton', ShapeOf('begin'#10'  Knopf| := Sender as TButton;'#10'end;'));
  Assert.AreEqual('Pointer', ShapeOf('begin'#10'  Zeiger| := @Wert;'#10'end;'));
  Assert.AreEqual('[F(A,B).Name]', ShapeOf('begin'#10'  Name| := -F(A, B).Name * 2;'#10'end;'));
  Assert.AreEqual('[''abc'']', ShapeOf('begin'#10'  Text| := ''abc'' + X;'#10'end;'));
  // Vergleich in Klammern zählt nicht: "F(A = B)" hat den Typ von F.
  Assert.AreEqual('[F(A=B)]', ShapeOf('begin'#10'  Wert| := F(A = B);'#10'end;'));
end;

procedure TDeclareUnknownTests.FindsTermName;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize('Liste.Items(1).Name');
  Assert.AreEqual('Name', mTokens[TDeclareUnknown.TermName(mTokens, 0, High(mTokens))].Text);
  mTokens := TPascalLexer.Tokenize('TFoo.Create(A, B)');
  Assert.AreEqual('Create', mTokens[TDeclareUnknown.TermName(mTokens, 0, High(mTokens))].Text);
  mTokens := TPascalLexer.Tokenize('Liste[0]');
  Assert.AreEqual(-1, TDeclareUnknown.TermName(mTokens, 0, High(mTokens)), 'Index: Elementtyp unbekannt');
  mTokens := TPascalLexer.Tokenize('42');
  Assert.AreEqual('Integer', TDeclareUnknown.LiteralType(mTokens[0]));
  mTokens := TPascalLexer.Tokenize('1.5');
  Assert.AreEqual('Extended', TDeclareUnknown.LiteralType(mTokens[0]));
  mTokens := TPascalLexer.Tokenize('True');
  Assert.AreEqual('Boolean', TDeclareUnknown.LiteralType(mTokens[0]));
end;

procedure TDeclareUnknownTests.NamesFieldsAndValues;
begin
  Assert.IsTrue(TDeclareUnknown.UsesFieldPrefix(nil), 'ohne Felder Delphi-Stil');
  Assert.IsTrue(TDeclareUnknown.UsesFieldPrefix(['FLines', 'FName', 'Count']));
  Assert.IsFalse(TDeclareUnknown.UsesFieldPrefix(['Lines', 'Name', 'FCount']));
  Assert.AreEqual('FTotalCount', TDeclareUnknown.FieldName('TotalCount', True));
  Assert.AreEqual('FTotal', TDeclareUnknown.FieldName('total', True));
  Assert.AreEqual('FTotal', TDeclareUnknown.FieldName('FTotal', True));
  Assert.AreEqual('TotalCount', TDeclareUnknown.FieldName('TotalCount', False));
  Assert.AreEqual('0', TDeclareUnknown.DefaultValue('Integer'));
  Assert.AreEqual('''''', TDeclareUnknown.DefaultValue('string'));
  Assert.AreEqual('False', TDeclareUnknown.DefaultValue('Boolean'));
  Assert.AreEqual(TDeclareUnknown.cValuePlaceholder, TDeclareUnknown.DefaultValue('TFoo'));
  Assert.AreEqual('Total$0Count', TDeclareUnknown.WithCaret('TotalCount', 5));
  Assert.AreEqual('FTotalCount$0', TDeclareUnknown.WithCaret('FTotalCount', 11));
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclareUnknownTests);

end.
