unit Argus.Common.Editing.UsesActions.Tests;

// Tests für die uses-Aktionen (#284).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUsesActionsTests = class
  public
    [Test]
    procedure RemovesUnusedUnit;
    [Test]
    procedure UnitWithInitializationStays;
    [Test]
    procedure KeepListAndUnknownUnitsStay;
    [Test]
    procedure QualifiedAccessCountsAsUse;
    [Test]
    procedure ConditionalBlockStaysUnchanged;
    [Test]
    procedure MovesUnitUsedOnlyInImplementation;
    [Test]
    procedure UnitUsedInInterfaceIsNotMoved;
    [Test]
    procedure SortsByNamespace;
    [Test]
    procedure MissingUnitIsSuggested;
    [Test]
    procedure MissingUnitSkipsUsedAndLocalNames;
    [Test]
    procedure ApplyingTwiceGivesSameResult;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.Contract,
  Argus.Common.Pascal.Lexer,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Rules.Contract,
  Argus.Common.Editing.UsesClause,
  Argus.Common.Editing.UsesActions;

/// <summary>Kleiner Index: Units.A (Foo), Units.B (Bar), Units.Reg (Init), Units.C (Baz, Mitglied Qux).</summary>
function Info(const AUnitName: string): TUsesUnitInfo;
begin
  Result := Default(TUsesUnitInfo);
  Result.Known := True;
  if SameText(AUnitName, 'Units.A') then
    Result.Names := ['Foo']
  else if SameText(AUnitName, 'Units.B') then
    Result.Names := ['Bar']
  else if SameText(AUnitName, 'Units.C') then
    Result.Names := ['Baz', 'Qux']
  else if SameText(AUnitName, 'Units.Reg') then
  begin
    Result.Names := ['Init'];
    Result.HasInitialization := True;
  end
  else
    Result.Known := False;
end;

function Declaring(const AName: string): TArray<string>;
begin
  if SameText(AName, 'Foo') then
    Result := ['Units.A']
  else if SameText(AName, 'Bar') then
    Result := ['Units.B']
  else
    Result := nil;
end;

function Source(const AInterfaceUses, AInterface, AImplementationUses, AImplementation: string): string;
begin
  Result := 'unit U;'#10'interface'#10;
  if AInterfaceUses <> '' then
    Result := Result + 'uses'#10'  ' + AInterfaceUses + ';'#10;
  Result := Result + AInterface + 'implementation'#10;
  if AImplementationUses <> '' then
    Result := Result + 'uses'#10'  ' + AImplementationUses + ';'#10;
  Result := Result + AImplementation + 'end.';
end;

/// <summary>Edits von hinten nach vorn anwenden.</summary>
function Apply(const AText: string; const AEdits: TArray<TRuleEdit>): string;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    Line, Index: Integer;
  begin
    Line := 0;
    Index := 1;
    while (Line < APosition.Line) and (Index <= Length(AText)) do
    begin
      if AText[Index] = #10 then
        Inc(Line);
      Inc(Index);
    end;
    Result := Index + APosition.Character;
  end;

var
  Order: TArray<Integer>;
  I, J, Swap, Start, Stop: Integer;
begin
  Result := AText;
  SetLength(Order, Length(AEdits));
  for I := 0 to High(Order) do
    Order[I] := I;
  for I := 0 to High(Order) do
    for J := I + 1 to High(Order) do
      if OffsetOf(AEdits[Order[J]].Range.StartPos) > OffsetOf(AEdits[Order[I]].Range.StartPos) then
      begin
        Swap := Order[I];
        Order[I] := Order[J];
        Order[J] := Swap;
      end;
  for I in Order do
  begin
    Start := OffsetOf(AEdits[I].Range.StartPos);
    Stop := OffsetOf(AEdits[I].Range.EndPos);
    Result := Copy(Result, 1, Start - 1) + AEdits[I].NewText + Copy(Result, Stop, MaxInt);
  end;
end;

function RemoveUnused(const AText: string; const AKeep: TArray<string> = nil): string;
var
  Tokens: TArray<TPascalToken>;
  Edits: TArray<TRuleEdit>;
begin
  Tokens := TPascalLexer.Tokenize(AText);
  if TUsesActions.RemoveUnits(Tokens, AText, TUsesActions.UnusedUnits(Tokens, Info, AKeep), #10, Edits) then
    Result := Apply(AText, Edits)
  else
    Result := AText;
end;

procedure TUsesActionsTests.RemovesUnusedUnit;
begin
  Assert.AreEqual(Source('Units.A', '', '', 'procedure P;'#10'begin'#10'  Foo;'#10'end;'#10),
    RemoveUnused(Source('Units.A, Units.B', '', '', 'procedure P;'#10'begin'#10'  Foo;'#10'end;'#10)));
end;

procedure TUsesActionsTests.UnitWithInitializationStays;
var
  Text: string;
begin
  Text := Source('Units.Reg, Units.A', '', '', '');
  Assert.AreEqual(Source('Units.Reg', '', '', ''), RemoveUnused(Text));
end;

procedure TUsesActionsTests.KeepListAndUnknownUnitsStay;
var
  Text: string;
begin
  Text := Source('Units.A, Vcl.Unbekannt', '', '', '');
  Assert.AreEqual(Text, RemoveUnused(Text, ['units.a']));
end;

procedure TUsesActionsTests.QualifiedAccessCountsAsUse;
var
  Text: string;
begin
  // C wird nur über ein Mitglied, B qualifiziert benutzt.
  Text := Source('Units.B, Units.C', '', '', 'procedure P;'#10'begin'#10'  X.Qux;'#10'  B.Irgendwas;'#10'end;'#10);
  Assert.AreEqual(Text, RemoveUnused(Text));
end;

procedure TUsesActionsTests.ConditionalBlockStaysUnchanged;
var
  Text: string;
begin
  Text := Source('Units.A, {$IFDEF X}Units.B,{$ENDIF} Units.C', '', '', '');
  Assert.AreEqual(Text, RemoveUnused(Text));
end;

procedure TUsesActionsTests.MovesUnitUsedOnlyInImplementation;
var
  Text: string;
  Tokens: TArray<TPascalToken>;
  Units: TArray<string>;
  Edits: TArray<TRuleEdit>;
begin
  Text := Source('Units.A, Units.B', 'type'#10'  T = Bar;'#10, 'Units.C',
    'procedure P;'#10'begin'#10'  Foo; Baz;'#10'end;'#10);
  Tokens := TPascalLexer.Tokenize(Text);
  Units := TUsesActions.MovableUnits(Tokens, Info);
  Assert.AreEqual('Units.A', string.Join(',', Units));
  Assert.IsTrue(TUsesActions.MoveUnits(Tokens, Text, Units, #10, Edits));
  Assert.AreEqual(Source('Units.B', 'type'#10'  T = Bar;'#10, 'Units.C,'#10'  Units.A',
    'procedure P;'#10'begin'#10'  Foo; Baz;'#10'end;'#10), Apply(Text, Edits));
end;

procedure TUsesActionsTests.UnitUsedInInterfaceIsNotMoved;
var
  Text: string;
begin
  Text := Source('Units.A', 'procedure P(X: Foo);'#10, '', 'procedure P(X: Foo);'#10'begin'#10'  Foo;'#10'end;'#10);
  Assert.AreEqual(0, Integer(Length(TUsesActions.MovableUnits(TPascalLexer.Tokenize(Text), Info))));
end;

procedure TUsesActionsTests.SortsByNamespace;
var
  Text: string;
  Edits: TArray<TRuleEdit>;
begin
  Text := Source('Eigen, Vcl.Forms, Data.DB, Abc, Vcl.Controls, Data.Bind', '', '', '');
  Assert.IsTrue(TUsesClauses.Organize(TPascalLexer.Tokenize(Text), Text, True, #10, Edits, True));
  // "uses" steht in eigener Zeile, also eine Unit je Zeile.
  Assert.AreEqual(Source('Data.Bind,'#10'  Data.DB,'#10'  Vcl.Controls,'#10'  Vcl.Forms,'#10'  Abc,'#10'  Eigen', '', '', ''),
    Apply(Text, Edits));
end;

procedure TUsesActionsTests.MissingUnitIsSuggested;
var
  Text: string;
  Tree: TSyntaxTree;
  Units: TArray<string>;
begin
  Text := Source('Units.B', '', '', 'procedure P;'#10'begin'#10'  Foo;'#10'end;'#10);
  Tree := TPascalParser.Parse(Text);
  try
    // Zeile 7: "  Foo;"
    Units := TUsesActions.MissingUnits(TPascalLexer.Tokenize(Text), Tree, TTextPosition.Create(7, 3), Declaring, nil);
    Assert.AreEqual('Units.A', string.Join(',', Units));
  finally
    Tree.Free;
  end;
end;

procedure TUsesActionsTests.MissingUnitSkipsUsedAndLocalNames;
var
  Text: string;
  Tree: TSyntaxTree;
begin
  // Bar kommt aus Units.B (eingebunden), Foo ist lokal deklariert, X.Foo ist ein Mitglied.
  Text := Source('Units.B', '', '', 'procedure P;'#10'var'#10'  Foo: Integer;'#10'begin'#10'  Bar; Foo := 1; X.Foo;'#10'end;'#10);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.AreEqual(0, Integer(Length(TUsesActions.MissingUnits(TPascalLexer.Tokenize(Text), Tree,
      TTextPosition.Create(9, 3), Declaring, nil))));
    Assert.AreEqual(0, Integer(Length(TUsesActions.MissingUnits(TPascalLexer.Tokenize(Text), Tree,
      TTextPosition.Create(9, 8), Declaring, nil))));
  finally
    Tree.Free;
  end;
  Text := Source('', '', '', 'procedure P;'#10'begin'#10'  X.Foo;'#10'end;'#10);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.AreEqual(0, Integer(Length(TUsesActions.MissingUnits(TPascalLexer.Tokenize(Text), Tree,
      TTextPosition.Create(5, 5), Declaring, nil))));
  finally
    Tree.Free;
  end;
end;

procedure TUsesActionsTests.ApplyingTwiceGivesSameResult;
var
  Once, Twice: string;
  Tree: TSyntaxTree;
begin
  Once := RemoveUnused(Source('Units.A, Units.B, Units.C', '', 'Units.Reg', 'procedure P;'#10'begin'#10'  Bar;'#10'end;'#10));
  Twice := RemoveUnused(Once);
  Assert.AreEqual(Once, Twice);
  Tree := TPascalParser.Parse(Once);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesActionsTests);

end.
