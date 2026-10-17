unit Atlas.Common.Editing.UsesActions.Tests;

// Tests für die uses-Aktionen (#284) und die Prüfung einzelner Einträge zum
// Abblenden (#621).

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
    [Test]
    procedure AddsUnitsToMatchingSection;
    /// <summary>#621: ungenutzt, wegen initialization oder usesKeep behalten, nur in der implementation.</summary>
    [Test]
    procedure EntriesNameTheirState;
    /// <summary>#621: In {$IFDEF}-Listen zählt nur der aktive Zweig, auch für die Bezeichner.</summary>
    [Test]
    procedure EntriesFollowActiveBranch;
    /// <summary>#621: Einzelne Einträge streichen ergibt parsbaren Code, auch mit Direktiven und Kommentaren.
    /// </summary>
    [Test]
    procedure RemoveEntriesKeepsCodeValid;
    /// <summary>#621: Code-Aktionen am Eintrag mit Kennung für den Hover.</summary>
    [Test]
    procedure ActionsAtEntryCarryTags;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Lsp.InactiveRegions;

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

procedure TUsesActionsTests.AddsUnitsToMatchingSection;
var
  Text: string;
  Edits: TArray<TRuleEdit>;
  Added: TArray<string>;
begin
  // Units suchen (#777): Foo steht im interface, also Units.A dorthin; Units.C ins implementation-uses;
  // Units.B ist schon da, doppelte und die eigene Unit entfallen.
  Text := Source('Units.B', 'procedure P(X: Foo);'#10, '', 'procedure P(X: Foo);'#10'begin'#10'end;'#10);
  Assert.IsTrue(TUsesActions.AddUnits(TPascalLexer.Tokenize(Text), ['Units.A', 'Units.C', 'Units.B', 'units.c', 'U'],
    Declaring, nil, #10, Edits, Added));
  Assert.AreEqual('Units.A,Units.C', string.Join(',', Added));
  // Die Einfügehilfe von TUsesClauses setzt je Unit eine Zeile und vor ein neues uses eine Leerzeile.
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  Units.B,'#10'  Units.A;'#10'procedure P(X: Foo);'#10 +
    'implementation'#10#10'uses'#10'  Units.C;'#10'procedure P(X: Foo);'#10'begin'#10'end;'#10'end.', Apply(Text, Edits));
  // Nichts Neues: kein Edit.
  Assert.IsFalse(TUsesActions.AddUnits(TPascalLexer.Tokenize(Text), ['Units.B'], Declaring, nil, #10, Edits, Added));
  Assert.AreEqual(0, Integer(Length(Added)));
  // Programm: das einzige uses.
  Text := 'program P;'#10'uses'#10'  Units.B;'#10'begin'#10'end.';
  Assert.IsTrue(TUsesActions.AddUnits(TPascalLexer.Tokenize(Text), ['Units.C'], Declaring, nil, #10, Edits, Added));
  Assert.AreEqual('program P;'#10'uses'#10'  Units.B,'#10'  Units.C;'#10'begin'#10'end.', Apply(Text, Edits));
end;

/// <summary>"Name:Zustand" je Eintrag, mit "|" getrennt.</summary>
function States(const AText: string; const AInactive: TArray<TTextRange>; const AKeep: TArray<string>): string;
const
  Names: array[TUsesEntryState] of string = ('unused', 'init', 'keep', 'impl');
var
  Entry: TUsesEntry;
begin
  Result := '';
  for Entry in TUsesActions.Entries(TPascalLexer.Tokenize(AText), AInactive, Info, AKeep) do
    Result := Result + Entry.Name + ':' + Names[Entry.State] + '|';
end;

procedure TUsesActionsTests.EntriesNameTheirState;
var
  Text: string;
  Entries: TArray<TUsesEntry>;
begin
  Text := Source('Units.A, Units.B, Units.Reg, Units.C, Vcl.Unbekannt', '', '',
    'procedure P;'#10'begin'#10'  Foo;'#10'end;'#10);
  Assert.AreEqual('Units.A:impl|Units.B:unused|Units.Reg:init|Units.C:keep|', States(Text, nil, ['units.c']));
  // Position des Namens: Units.B in Zeile 3 hinter "  Units.A, ".
  Entries := TUsesActions.Entries(TPascalLexer.Tokenize(Text), nil, Info, nil);
  Assert.AreEqual(3, Entries[1].Range.StartPos.Line);
  Assert.AreEqual(11, Entries[1].Range.StartPos.Character);
  Assert.AreEqual(18, Entries[1].Range.EndPos.Character);
  // Im interface benutzt: unauffällig.
  Text := Source('Units.A', 'procedure P(X: Foo);'#10, '', 'procedure P(X: Foo);'#10'begin'#10'end;'#10);
  Assert.AreEqual('', States(Text, nil, nil));
end;

procedure TUsesActionsTests.EntriesFollowActiveBranch;
var
  Text: string;
begin
  Text := Source('Units.A, {$IFDEF X}Units.B,{$ENDIF} Units.C', '', '',
    'procedure P;'#10'begin'#10'  Baz;'#10'  {$IFDEF X}Bar;{$ENDIF}'#10'end;'#10);
  // X nicht gesetzt: Units.B steht im inaktiven Zweig und fällt nicht auf; Units.A ist ungenutzt.
  Assert.AreEqual('Units.A:unused|Units.C:impl|', States(Text, TLspInactiveRegions.Ranges(Text, []), nil));
  // X gesetzt: Units.B wird im aktiven Zweig benutzt.
  Assert.AreEqual('Units.A:unused|Units.B:impl|Units.C:impl|', States(Text, TLspInactiveRegions.Ranges(Text, ['X']),
    nil));
  // Benutzt nur im inaktiven Zweig zählt nicht.
  Text := Source('', '', 'Units.B', 'procedure P;'#10'begin'#10'  {$IFDEF X}Bar;{$ENDIF}'#10'end;'#10);
  Assert.AreEqual('Units.B:unused|', States(Text, TLspInactiveRegions.Ranges(Text, []), nil));
  Assert.AreEqual('', States(Text, TLspInactiveRegions.Ranges(Text, ['X']), nil));
end;

/// <summary>Streicht die Einträge ANames (Bereiche aus References) und prüft, dass das Ergebnis parst.</summary>
function RemoveNamed(const AText: string; const ANames: TArray<string>; out AResult: string): Boolean;
var
  Reference: TUsesReference;
  Ranges: TArray<TTextRange>;
  Name: string;
  Edit: TTextEdit;
  Tree: TSyntaxTree;
begin
  Ranges := nil;
  for Reference in TUsesClauses.References(TPascalLexer.Tokenize(AText)) do
    for Name in ANames do
      if SameText(Reference.Name, Name) then
        Ranges := Ranges + [Reference.Range];
  Result := TUsesActions.RemoveEntries(AText, Ranges, Edit);
  AResult := AText;
  if not Result then
    Exit;
  AResult := Apply(AText, [Edit]);
  Tree := TPascalParser.Parse(AResult);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), AResult);
  finally
    Tree.Free;
  end;
end;

procedure TUsesActionsTests.RemoveEntriesKeepsCodeValid;
var
  Text, Removed: string;
begin
  Text := Source('Units.A, Units.B', '', '', '');
  Assert.IsTrue(RemoveNamed(Text, ['Units.B'], Removed));
  Assert.AreEqual(Source('Units.A', '', '', ''), Removed);
  Assert.IsTrue(RemoveNamed(Text, ['Units.A'], Removed));
  Assert.AreEqual(Source('Units.B', '', '', ''), Removed);
  // Alle: das ganze uses mit seiner Zeile.
  Assert.IsTrue(RemoveNamed(Text, ['Units.A', 'Units.B'], Removed));
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'end.', Removed);
  Text := 'unit U;'#10'interface'#10'uses Units.A;'#10'implementation'#10'end.';
  Assert.IsTrue(RemoveNamed(Text, ['Units.A'], Removed));
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'end.', Removed);
  // Mehrzeilig: der Eintrag mit seiner Zeile.
  Text := 'unit U;'#10'interface'#10'uses'#10'  Units.A,'#10'  Units.B,'#10'  Units.C;'#10'implementation'#10'end.';
  Assert.IsTrue(RemoveNamed(Text, ['Units.B'], Removed));
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  Units.A,'#10'  Units.C;'#10'implementation'#10'end.', Removed);
  // Direktiven: im Zweig mit dem Komma dahinter; ein Komma jenseits einer Direktive fasst Atlas nicht an.
  Text := Source('Units.A, {$IFDEF X}Units.B, {$ENDIF}Units.C', '', '', '');
  Assert.IsTrue(RemoveNamed(Text, ['Units.B'], Removed));
  Assert.AreEqual(Source('Units.A, {$IFDEF X}{$ENDIF}Units.C', '', '', ''), Removed);
  Assert.IsTrue(RemoveNamed(Text, ['Units.A'], Removed));
  Assert.AreEqual(Source('{$IFDEF X}Units.B, {$ENDIF}Units.C', '', '', ''), Removed);
  Assert.IsFalse(RemoveNamed(Text, ['Units.C'], Removed), 'Komma liegt im Zweig');
  // Kommentar am Eintrag davor bleibt.
  Text := 'unit U;'#10'interface'#10'uses'#10'  Units.A, // a'#10'  Units.B;'#10'implementation'#10'end.';
  Assert.IsTrue(RemoveNamed(Text, ['Units.B'], Removed));
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  Units.A // a'#10'  ;'#10'implementation'#10'end.', Removed);
  // "in 'datei'" gehört dazu, CRLF bleibt.
  Text := 'program P;'#13#10'uses'#13#10'  Units.A in ''a.pas'','#13#10'  Units.B;'#13#10'begin'#13#10'end.';
  Assert.IsTrue(RemoveNamed(Text, ['Units.A'], Removed));
  Assert.AreEqual('program P;'#13#10'uses'#13#10'  Units.B;'#13#10'begin'#13#10'end.', Removed);
end;

procedure TUsesActionsTests.ActionsAtEntryCarryTags;
var
  Text, Found: string;
  Context: TUsesContext;
  Action: TCodeAction;
  Tree: TSyntaxTree;
begin
  Text := Source('Units.A, Units.B, Units.C', '', '', 'procedure P;'#10'begin'#10'  Foo;'#10'end;'#10);
  Context := Default(TUsesContext);
  Context.Info := Info;
  Tree := TPascalParser.Parse(Text);
  try
    // Cursor auf Units.B (Zeile 3, Spalte 12).
    Found := '';
    for Action in TCodeActions.UsesActions(Text, Tree, TTextRange.Create(3, 12, 3, 12), Context, nil, True,
      False) do
      if Action.Tag <> '' then
        Found := Found + Action.Title + '=' + Action.Tag + '|';
    Assert.AreEqual('Units.B entfernen=uses.remove|Alle ungenutzten uses entfernen (2)=uses.removeAll|', Found);
    // Auf Units.A: nur in der implementation gebraucht, die Aktion für alle trägt die Kennung.
    Found := '';
    for Action in TCodeActions.UsesActions(Text, Tree, TTextRange.Create(3, 3, 3, 3), Context, nil, True,
      False) do
      if Action.Tag <> '' then
        Found := Found + Action.Title + '=' + Action.Tag + '|';
    Assert.AreEqual('Units.A ins implementation-uses verschieben=uses.move|', Found);
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesActionsTests);

end.
