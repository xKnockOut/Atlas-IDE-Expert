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

function SlotAt(const AMarked: string; out ATokens: TArray<TPascalToken>; out ASlot: TUnknownSlot): Boolean;
var
  Position: TTextPosition;
begin
  ATokens := Split(AMarked, Position);
  Result := TDeclareUnknown.Slot(ATokens, Position, ASlot);
end;

/// <summary>Typ aus der Form der rechten Seite; bei einem Operanden dessen Text in eckigen Klammern.</summary>
function ShapeOf(const AMarked: string): string;
var
  Tokens: TArray<TPascalToken>;
  Slot: TUnknownSlot;
  First, Last, Index: Integer;
begin
  if not SlotAt(AMarked, Tokens, Slot) then
    Exit('-');
  Result := TDeclareUnknown.Shape(Tokens, Slot.ValueFirst, Slot.ValueLast, First, Last);
  if (Result = '') and (First >= 0) then
  begin
    Result := '[';
    for Index := First to Last do
      Result := Result + Tokens[Index].Text;
    Result := Result + ']';
  end;
end;

{ TDeclareUnknownTests }

procedure TDeclareUnknownTests.FindsAssignmentTargetsAndValues;
var
  Tokens: TArray<TPascalToken>;
  Slot: TUnknownSlot;
begin
  Assert.IsTrue(SlotAt('begin'#10'  TotalCount| := Lines.Count + Extra.Count;'#10'end;', Tokens, Slot));
  Assert.AreEqual('TotalCount', Slot.Name);
  Assert.IsTrue(Slot.AssignTarget);
  Assert.IsTrue(Slot.InlineAllowed);
  Assert.AreEqual(10, Slot.CursorOffset);
  Assert.AreEqual('Lines', Tokens[Slot.ValueFirst].Text);
  Assert.AreEqual('Count', Tokens[Slot.ValueLast].Text);
  // Cursor mitten im Namen.
  Assert.IsTrue(SlotAt('begin'#10'  Total|Count := 1;'#10'end;', Tokens, Slot));
  Assert.AreEqual(5, Slot.CursorOffset);
  // Als Wert: kein Ziel, keine Inline-Variable.
  Assert.IsTrue(SlotAt('begin'#10'  Zeige(Anzahl|);'#10'end;', Tokens, Slot));
  Assert.IsFalse(Slot.AssignTarget);
  Assert.IsFalse(Slot.InlineAllowed);
  // Im then-Zweig ohne begin ist "var" nicht erlaubt.
  Assert.IsTrue(SlotAt('begin'#10'  if A then Summe| := 1;'#10'end;', Tokens, Slot));
  Assert.IsFalse(Slot.InlineAllowed);
end;

procedure TDeclareUnknownTests.IgnoresMembersCallsAndDeclarations;
var
  Tokens: TArray<TPascalToken>;
  Slot: TUnknownSlot;
begin
  Assert.IsFalse(SlotAt('begin'#10'  Liste.Anzahl| := 1;'#10'end;', Tokens, Slot), 'Mitglied');
  Assert.IsFalse(SlotAt('begin'#10'  Rechne|(1);'#10'end;', Tokens, Slot), 'Aufruf (#472)');
  Assert.IsFalse(SlotAt('begin'#10'  Objekt|.Free;'#10'end;', Tokens, Slot), 'Kette');
  Assert.IsFalse(SlotAt('begin'#10'  var Neu| := 1;'#10'end;', Tokens, Slot), 'Inline-Deklaration');
  Assert.IsFalse(SlotAt('begin'#10'  var I: TLis|;'#10'end;', Tokens, Slot), 'Typ einer Inline-Deklaration');
  Assert.IsFalse(SlotAt('begin'#10'  X := 1 |'#10'end;', Tokens, Slot), 'kein Name am Cursor');
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
  Tokens: TArray<TPascalToken>;
begin
  Tokens := TPascalLexer.Tokenize('Liste.Items(1).Name');
  Assert.AreEqual('Name', Tokens[TDeclareUnknown.TermName(Tokens, 0, High(Tokens))].Text);
  Tokens := TPascalLexer.Tokenize('TFoo.Create(A, B)');
  Assert.AreEqual('Create', Tokens[TDeclareUnknown.TermName(Tokens, 0, High(Tokens))].Text);
  Tokens := TPascalLexer.Tokenize('Liste[0]');
  Assert.AreEqual(-1, TDeclareUnknown.TermName(Tokens, 0, High(Tokens)), 'Index: Elementtyp unbekannt');
  Tokens := TPascalLexer.Tokenize('42');
  Assert.AreEqual('Integer', TDeclareUnknown.LiteralType(Tokens[0]));
  Tokens := TPascalLexer.Tokenize('1.5');
  Assert.AreEqual('Extended', TDeclareUnknown.LiteralType(Tokens[0]));
  Tokens := TPascalLexer.Tokenize('True');
  Assert.AreEqual('Boolean', TDeclareUnknown.LiteralType(Tokens[0]));
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
  Assert.AreEqual(TDeclareUnknown.ValuePlaceholder, TDeclareUnknown.DefaultValue('TFoo'));
  Assert.AreEqual('Total$0Count', TDeclareUnknown.WithCaret('TotalCount', 5));
  Assert.AreEqual('FTotalCount$0', TDeclareUnknown.WithCaret('FTotalCount', 11));
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclareUnknownTests);

end.
