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
    /// <summary>#1921: Namen außerhalb der uses-Listen, auch qualifiziert, ohne Rücksicht auf Schreibung.</summary>
    [Test]
    procedure NamesUsedOutsideUsesLists;
    [Test]
    procedure UnitWithInitializationStays;
    [Test]
    procedure KeepListAndUnknownUnitsStay;
    [Test]
    procedure QualifiedAccessCountsAsUse;
    [Test]
    procedure NameOfUnitWithoutDotIsNoUse;
    [Test]
    procedure ConditionalBlockStaysUnchanged;
    [Test]
    procedure MovesUnitUsedOnlyInImplementation;
    [Test]
    procedure MovesUnitToInterface;
    [Test]
    procedure UnitUsedInInterfaceIsNotMoved;
    [Test]
    procedure SortsByNamespace;
    [Test]
    procedure InterfaceUsagesNameTheNeed;
    [Test]
    procedure MissingUnitIsSuggested;
    [Test]
    procedure MissingUnitSkipsUsedAndLocalNames;
    [Test]
    procedure ApplyingTwiceGivesSameResult;
    [Test]
    procedure AddsUnitsToMatchingSection;
    [Test]
    procedure AddsUnitsToChosenSection;
    /// <summary>#621: ungenutzt, wegen initialization oder usesKeep behalten, nur in der implementation.</summary>
    [Test]
    procedure EntriesNameTheirState;
    /// <summary>#621: In {$IFDEF}-Listen zählt nur der aktive Zweig, auch für die Bezeichner.</summary>
    [Test]
    procedure EntriesFollowActiveBranch;
    /// <summary>Das uses eines Programms, einer Bibliothek oder eines Packages zählt die Units des Projekts auf:
    /// nichts abblenden, nichts zum Streichen anbieten.</summary>
    [Test]
    procedure ProjectUsesAreNeverUnused;
    /// <summary>#621: Einzelne Einträge streichen ergibt parsbaren Code, auch mit Direktiven und Kommentaren.
    /// </summary>
    [Test]
    procedure RemoveEntriesKeepsCodeValid;
    /// <summary>#621: Code-Aktionen am Eintrag mit Kennung für den Hover.</summary>
    [Test]
    procedure ActionsAtEntryCarryTags;
    /// <summary>Verweist die Formulardatei auf ein Modul der Unit (UsedByForm), ist der Eintrag gebraucht.</summary>
    [Test]
    procedure FormReferenceCountsAsImplementationUse;
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
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Lsp.InactiveRegions;

/// <summary>Kleiner Index: Units.A (Foo), Units.B (Bar), Units.Reg (Init), Units.C (Baz, Mitglied Qux).</summary>
function Info(const AUnitName: string): TUsesUnitInfo;
begin
  Result := Default(TUsesUnitInfo);
  Result.Known := True;
  if SameText(AUnitName, 'Units.A') then
  begin
    Result.Names := ['Foo'];
  end
  else if SameText(AUnitName, 'Units.B') then
  begin
    Result.Names := ['Bar'];
  end
  else if SameText(AUnitName, 'Units.C') then
  begin
    Result.Names := ['Baz', 'Qux'];
  end
  else if SameText(AUnitName, 'Units.Form') then
  begin
    Result.Names := ['TForm1', 'Form1'];
    Result.UsedByForm := True;
  end
  else if SameText(AUnitName, 'Units.Reg') then
  begin
    Result.Names := ['Init'];
    Result.HasInitialization := True;
  end
  else
  begin
    Result.Known := False;
  end;
end;

function Declaring(const AName: string): TArray<string>;
begin
  if SameText(AName, 'Foo') then
  begin
    Result := ['Units.A'];
  end
  else if SameText(AName, 'Bar') then
  begin
    Result := ['Units.B'];
  end
  else
  begin
    Result := nil;
  end;
end;

function Source(const AInterfaceUses, AInterface, AImplementationUses, AImplementation: string): string;
begin
  Result := 'unit U;'#10'interface'#10;
  if AInterfaceUses <> '' then
  begin
    Result := Result + 'uses'#10'  ' + AInterfaceUses + ';'#10;
  end;
  Result := Result + AInterface + 'implementation'#10;
  if AImplementationUses <> '' then
  begin
    Result := Result + 'uses'#10'  ' + AImplementationUses + ';'#10;
  end;
  Result := Result + AImplementation + 'end.';
end;

/// <summary>Edits von hinten nach vorn anwenden.</summary>
function Apply(const AText: string; const AEdits: TArray<TRuleEdit>): string;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    mLine, mIndex: Integer;
  begin
    mLine := 0;
    mIndex := 1;
    while (mLine < APosition.Line) and (mIndex <= Length(AText)) do
    begin
      if AText[mIndex] = #10 then
      begin
        Inc(mLine);
      end;
      Inc(mIndex);
    end;
    Result := mIndex + APosition.Character;
  end;

var
  mOrder: TArray<Integer>;
  I, J, mSwap, mStart, mStop: Integer;
begin
  Result := AText;
  SetLength(mOrder, Length(AEdits));
  for I := 0 to High(mOrder) do
  begin
    mOrder[I] := I;
  end;
  for I := 0 to High(mOrder) do
  begin
    for J := I + 1 to High(mOrder) do
    begin
      if OffsetOf(AEdits[mOrder[J]].Range.StartPos) > OffsetOf(AEdits[mOrder[I]].Range.StartPos) then
      begin
        mSwap := mOrder[I];
        mOrder[I] := mOrder[J];
        mOrder[J] := mSwap;
      end;
    end;
  end;
  for I in mOrder do
  begin
    mStart := OffsetOf(AEdits[I].Range.StartPos);
    mStop := OffsetOf(AEdits[I].Range.EndPos);
    Result := Copy(Result, 1, mStart - 1) + AEdits[I].NewText + Copy(Result, mStop, MaxInt);
  end;
end;

function RemoveUnused(const AText: string; const AKeep: TArray<string>): string; overload;
var
  mTokens: TArray<TPascalToken>;
  mEdits: TArray<TRuleEdit>;
begin
  mTokens := TPascalLexer.Tokenize(AText);
  if TUsesActions.RemoveUnits(mTokens, AText, TUsesActions.UnusedUnits(mTokens, Info, AKeep), #10, mEdits) then
  begin
    Result := Apply(AText, mEdits);
  end
  else
  begin
    Result := AText;
  end;
end;

function RemoveUnused(const AText: string): string; overload;
begin
  Result := RemoveUnused(AText, nil);
end;

procedure TUsesActionsTests.NamesUsedOutsideUsesLists;
const
  cText = 'unit X;'#10'interface'#10'uses Werk, TPunkt;'#10'implementation'#10 +
    'var K: tkunde; L: Werk.TListe<Integer>;'#10'end.';
var
  mUsed: TArray<Boolean>;
begin
  mUsed := TUsesActions.NamesUsed(TPascalLexer.Tokenize(cText), ['TKunde', 'TListe', 'TPunkt', 'Werk']);
  Assert.AreEqual(4, Integer(Length(mUsed)));
  Assert.IsTrue(mUsed[0]);
  Assert.IsTrue(mUsed[1]);
  // Namen in der uses-Liste zählen nicht; Werk steht dagegen als Qualifizierer im Code.
  Assert.IsFalse(mUsed[2]);
  Assert.IsTrue(mUsed[3]);
  Assert.AreEqual(0, Integer(Length(TUsesActions.NamesUsed(TPascalLexer.Tokenize(cText), nil))));
end;

procedure TUsesActionsTests.RemovesUnusedUnit;
begin
  Assert.AreEqual(Source('Units.A', '', '', 'procedure P;'#10'begin'#10'  Foo;'#10'end;'#10),
    RemoveUnused(Source('Units.A, Units.B', '', '', 'procedure P;'#10'begin'#10'  Foo;'#10'end;'#10)));
end;

procedure TUsesActionsTests.UnitWithInitializationStays;
var
  mText: string;
begin
  mText := Source('Units.Reg, Units.A', '', '', '');
  Assert.AreEqual(Source('Units.Reg', '', '', ''), RemoveUnused(mText));
end;

procedure TUsesActionsTests.KeepListAndUnknownUnitsStay;
var
  mText: string;
begin
  mText := Source('Units.A, Vcl.Unbekannt', '', '', '');
  Assert.AreEqual(mText, RemoveUnused(mText, ['units.a']));
end;

procedure TUsesActionsTests.QualifiedAccessCountsAsUse;
var
  mText: string;
begin
  // C wird nur über ein Mitglied, B qualifiziert benutzt.
  mText := Source('Units.B, Units.C', '', '', 'procedure P;'#10'begin'#10'  X.Qux;'#10'  B.Irgendwas;'#10'end;'#10);
  Assert.AreEqual(mText, RemoveUnused(mText));
end;

procedure TUsesActionsTests.NameOfUnitWithoutDotIsNoUse;
begin
  // Eine Routine B ist kein Zugriff B.Name: Units.B bleibt unbenutzt.
  Assert.AreEqual(Source('Units.A', '', '', 'procedure B;'#10'begin'#10'  Foo;'#10'end;'#10),
    RemoveUnused(Source('Units.A, Units.B', '', '', 'procedure B;'#10'begin'#10'  Foo;'#10'end;'#10)));
end;

procedure TUsesActionsTests.ConditionalBlockStaysUnchanged;
var
  mText: string;
begin
  mText := Source('Units.A, {$IFDEF X}Units.B,{$ENDIF} Units.C', '', '', '');
  Assert.AreEqual(mText, RemoveUnused(mText));
end;

procedure TUsesActionsTests.MovesUnitUsedOnlyInImplementation;
var
  mText: string;
  mTokens: TArray<TPascalToken>;
  mUnits: TArray<string>;
  mEdits: TArray<TRuleEdit>;
begin
  mText := Source('Units.A, Units.B', 'type'#10'  T = Bar;'#10, 'Units.C',
    'procedure P;'#10'begin'#10'  Foo; Baz;'#10'end;'#10);
  mTokens := TPascalLexer.Tokenize(mText);
  mUnits := TUsesActions.MovableUnits(mTokens, Info);
  Assert.AreEqual('Units.A', string.Join(',', mUnits));
  Assert.IsTrue(TUsesActions.MoveUnits(mTokens, mText, mUnits, #10, mEdits));
  Assert.AreEqual(Source('Units.B', 'type'#10'  T = Bar;'#10, 'Units.C,'#10'  Units.A',
    'procedure P;'#10'begin'#10'  Foo; Baz;'#10'end;'#10), Apply(mText, mEdits));
end;

procedure TUsesActionsTests.MovesUnitToInterface;
var
  mText: string;
  mEdits: TArray<TRuleEdit>;
begin
  // Unit-Beziehungen (#593): aus dem implementation- ins interface-uses, auch ohne interface-uses.
  mText := Source('Units.A', '', 'Units.B, Units.C', '');
  Assert.IsTrue(TUsesActions.MoveUnitsToInterface(TPascalLexer.Tokenize(mText), mText, ['Units.C'], #10, mEdits));
  Assert.AreEqual(Source('Units.A,'#10'  Units.C', '', 'Units.B', ''), Apply(mText, mEdits));
  mText := Source('', '', 'Units.B', '');
  Assert.IsTrue(TUsesActions.MoveUnitsToInterface(TPascalLexer.Tokenize(mText), mText, ['Units.B'], #10, mEdits));
  Assert.AreEqual('unit U;'#10'interface'#10#10'uses'#10'  Units.B;'#10'implementation'#10#10'end.', Apply(mText, mEdits),
    'leere Liste fällt weg, neue entsteht');
  mText := 'program P;'#10'uses'#10'  Units.B;'#10'begin'#10'end.';
  Assert.IsFalse(TUsesActions.MoveUnitsToInterface(TPascalLexer.Tokenize(mText), mText, ['Units.B'], #10, mEdits),
    'Programm ohne interface');
end;

procedure TUsesActionsTests.UnitUsedInInterfaceIsNotMoved;
var
  mText: string;
begin
  mText := Source('Units.A', 'procedure P(X: Foo);'#10, '', 'procedure P(X: Foo);'#10'begin'#10'  Foo;'#10'end;'#10);
  Assert.AreEqual(0, Integer(Length(TUsesActions.MovableUnits(TPascalLexer.Tokenize(mText), Info))));
end;

procedure TUsesActionsTests.InterfaceUsagesNameTheNeed;
var
  mText: string;
  mFound: TArray<TUsesInterfaceUsage>;
begin
  // Unit-Zyklus (#896): Bezeichner im interface-Teil, auch qualifiziert über den Unit-Namen; nicht im uses,
  // nicht im implementation-Teil.
  mText := Source('Units.Kunde', 'type'#10'  TA = class(TKunde) end;'#10'  TB = Kunde.TListe;'#10, 'Units.Kunde',
    'var X: TKunde;'#10);
  mFound := TUsesActions.InterfaceUsages(TPascalLexer.Tokenize(mText), 'Units.Kunde',
    TArray<string>.Create('TKunde', 'TListe'));
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual('TKunde', mFound[0].Name);
  Assert.AreEqual(5, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(13, mFound[0].Range.StartPos.Character);
  Assert.AreEqual('Kunde', mFound[1].Name);
  Assert.AreEqual('TListe', mFound[2].Name);
  // Nur im implementation-Teil gebraucht: verschiebbar.
  mText := Source('Units.Kunde', '', '', 'var X: TKunde;'#10);
  Assert.AreEqual(0, Integer(Length(TUsesActions.InterfaceUsages(TPascalLexer.Tokenize(mText), 'Units.Kunde',
    TArray<string>.Create('TKunde')))));
  // Programme haben keinen interface-Teil.
  mText := 'program P;'#10'uses'#10'  Units.Kunde;'#10'var X: TKunde;'#10'begin'#10'end.';
  Assert.AreEqual(0, Integer(Length(TUsesActions.InterfaceUsages(TPascalLexer.Tokenize(mText), 'Units.Kunde',
    TArray<string>.Create('TKunde')))));
end;

procedure TUsesActionsTests.SortsByNamespace;
var
  mText: string;
  mEdits: TArray<TRuleEdit>;
begin
  mText := Source('Eigen, Vcl.Forms, Data.DB, Abc, Vcl.Controls, Data.Bind', '', '', '');
  Assert.IsTrue(TUsesClauses.Organize(TPascalLexer.Tokenize(mText), mText, True, #10, mEdits, True));
  // "uses" steht in eigener Zeile, also eine Unit je Zeile.
  Assert.AreEqual(Source('Data.Bind,'#10'  Data.DB,'#10'  Vcl.Controls,'#10'  Vcl.Forms,'#10'  Abc,'#10'  Eigen', '', '', ''),
    Apply(mText, mEdits));
end;

procedure TUsesActionsTests.MissingUnitIsSuggested;
var
  mText: string;
  mTree: TSyntaxTree;
  mUnits: TArray<string>;
begin
  mText := Source('Units.B', '', '', 'procedure P;'#10'begin'#10'  Foo;'#10'end;'#10);
  mTree := TPascalParser.Parse(mText);
  try
    // Zeile 7: "  Foo;"
    mUnits := TUsesActions.MissingUnits(TPascalLexer.Tokenize(mText), mTree, TTextPosition.Create(7, 3), Declaring,
      nil);
    Assert.AreEqual('Units.A', string.Join(',', mUnits));
  finally
    mTree.Free;
  end;
end;

procedure TUsesActionsTests.MissingUnitSkipsUsedAndLocalNames;
var
  mText: string;
  mTree: TSyntaxTree;
begin
  // Bar kommt aus Units.B (eingebunden), Foo ist lokal deklariert, X.Foo ist ein Mitglied.
  mText := Source('Units.B', '', '', 'procedure P;'#10'var'#10'  Foo: Integer;'#10'begin'#10'  Bar; Foo := 1; X.Foo;'#10'end;'#10);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.AreEqual(0, Integer(Length(TUsesActions.MissingUnits(TPascalLexer.Tokenize(mText), mTree,
      TTextPosition.Create(9, 3), Declaring, nil))));
    Assert.AreEqual(0, Integer(Length(TUsesActions.MissingUnits(TPascalLexer.Tokenize(mText), mTree,
      TTextPosition.Create(9, 8), Declaring, nil))));
  finally
    mTree.Free;
  end;
  mText := Source('', '', '', 'procedure P;'#10'begin'#10'  X.Foo;'#10'end;'#10);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.AreEqual(0, Integer(Length(TUsesActions.MissingUnits(TPascalLexer.Tokenize(mText), mTree,
      TTextPosition.Create(5, 5), Declaring, nil))));
  finally
    mTree.Free;
  end;
end;

procedure TUsesActionsTests.ApplyingTwiceGivesSameResult;
var
  mOnce, mTwice: string;
  mTree: TSyntaxTree;
begin
  mOnce := RemoveUnused(Source('Units.A, Units.B, Units.C', '', 'Units.Reg', 'procedure P;'#10'begin'#10'  Bar;'#10'end;'#10));
  mTwice := RemoveUnused(mOnce);
  Assert.AreEqual(mOnce, mTwice);
  mTree := TPascalParser.Parse(mOnce);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
  finally
    mTree.Free;
  end;
end;

procedure TUsesActionsTests.AddsUnitsToMatchingSection;
var
  mText: string;
  mEdits: TArray<TRuleEdit>;
  mAdded: TArray<string>;
begin
  // Units suchen (#777): Foo steht im interface, also Units.A dorthin; Units.C ins implementation-uses;
  // Units.B ist schon da, doppelte und die eigene Unit entfallen.
  mText := Source('Units.B', 'procedure P(X: Foo);'#10, '', 'procedure P(X: Foo);'#10'begin'#10'end;'#10);
  Assert.IsTrue(TUsesActions.AddUnits(TPascalLexer.Tokenize(mText),
    TUsesAddRequest.Create(['Units.A', 'Units.C', 'Units.B', 'units.c', 'U'], Declaring, nil, #10), mEdits, mAdded));
  Assert.AreEqual('Units.A,Units.C', string.Join(',', mAdded));
  // Die Einfügehilfe von TUsesClauses setzt je Unit eine Zeile und vor ein neues uses eine Leerzeile.
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  Units.B,'#10'  Units.A;'#10'procedure P(X: Foo);'#10 +
    'implementation'#10#10'uses'#10'  Units.C;'#10'procedure P(X: Foo);'#10'begin'#10'end;'#10'end.', Apply(mText, mEdits));
  // Nichts Neues: kein Edit.
  Assert.IsFalse(TUsesActions.AddUnits(TPascalLexer.Tokenize(mText), TUsesAddRequest.Create(['Units.B'], Declaring, nil,
    #10), mEdits, mAdded));
  Assert.AreEqual(0, Integer(Length(mAdded)));
  // Programm: das einzige uses.
  mText := 'program P;'#10'uses'#10'  Units.B;'#10'begin'#10'end.';
  Assert.IsTrue(TUsesActions.AddUnits(TPascalLexer.Tokenize(mText), TUsesAddRequest.Create(['Units.C'], Declaring, nil,
    #10), mEdits, mAdded));
  Assert.AreEqual('program P;'#10'uses'#10'  Units.B,'#10'  Units.C;'#10'begin'#10'end.', Apply(mText, mEdits));
end;

procedure TUsesActionsTests.AddsUnitsToChosenSection;
var
  mText: string;
  mEdits: TArray<TRuleEdit>;
  mAdded: TArray<string>;
begin
  // Unit verwenden (#786): Der Umschalter gilt fest, auch wenn der interface-Teil Foo aus Units.A nennt.
  mText := Source('Units.B', 'procedure P(X: Foo);'#10, '', 'procedure P(X: Foo);'#10'begin'#10'end;'#10);
  Assert.IsTrue(TUsesActions.AddUnits(TPascalLexer.Tokenize(mText), TUsesAddRequest.Create(['Units.A', 'Units.C',
    'Units.B'], Declaring, nil, #10).WithTarget(TUsesAddTarget.Implementation_), mEdits, mAdded));
  Assert.AreEqual('Units.A,Units.C', string.Join(',', mAdded), 'ohne Duplikat');
  Assert.AreEqual(1, Integer(Length(mEdits)), 'ein Edit, also ein Rückgängig-Schritt');
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  Units.B;'#10'procedure P(X: Foo);'#10 +
    'implementation'#10#10'uses'#10'  Units.A, Units.C;'#10'procedure P(X: Foo);'#10'begin'#10'end;'#10'end.',
    Apply(mText, mEdits));
  Assert.IsTrue(TUsesActions.AddUnits(TPascalLexer.Tokenize(mText), TUsesAddRequest.Create(['Units.C'], Declaring, nil,
    #10).WithTarget(TUsesAddTarget.Interface_), mEdits, mAdded));
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  Units.B,'#10'  Units.C;'#10'procedure P(X: Foo);'#10 +
    'implementation'#10'procedure P(X: Foo);'#10'begin'#10'end;'#10'end.', Apply(mText, mEdits));
  // Programm: das einzige uses, gleich welcher Abschnitt.
  mText := 'program P;'#10'uses'#10'  Units.B;'#10'begin'#10'end.';
  Assert.IsTrue(TUsesActions.AddUnits(TPascalLexer.Tokenize(mText), TUsesAddRequest.Create(['Units.C'], Declaring, nil,
    #10).WithTarget(TUsesAddTarget.Implementation_), mEdits, mAdded));
  Assert.AreEqual('program P;'#10'uses'#10'  Units.B,'#10'  Units.C;'#10'begin'#10'end.', Apply(mText, mEdits));
end;

/// <summary>"Name:Zustand" je Eintrag, mit "|" getrennt.</summary>
function States(const AText: string; const AInactive: TArray<TTextRange>; const AKeep: TArray<string>): string;
const
  cNames: array[TUsesEntryState] of string = ('unused', 'init', 'keep', 'impl');
var
  mEntry: TUsesEntry;
begin
  Result := '';
  for mEntry in TUsesActions.Entries(TPascalLexer.Tokenize(AText), AInactive, Info, AKeep) do
  begin
    Result := Result + mEntry.Name + ':' + cNames[mEntry.State] + '|';
  end;
end;

procedure TUsesActionsTests.EntriesNameTheirState;
var
  mText: string;
  mEntries: TArray<TUsesEntry>;
begin
  mText := Source('Units.A, Units.B, Units.Reg, Units.C, Vcl.Unbekannt', '', '',
    'procedure P;'#10'begin'#10'  Foo;'#10'end;'#10);
  Assert.AreEqual('Units.A:impl|Units.B:unused|Units.Reg:init|Units.C:keep|', States(mText, nil, ['units.c']));
  // Position des Namens: Units.B in Zeile 3 hinter "  Units.A, ".
  mEntries := TUsesActions.Entries(TPascalLexer.Tokenize(mText), nil, Info, nil);
  Assert.AreEqual(3, mEntries[1].Range.StartPos.Line);
  Assert.AreEqual(11, mEntries[1].Range.StartPos.Character);
  Assert.AreEqual(18, mEntries[1].Range.EndPos.Character);
  // Im interface benutzt: unauffällig.
  mText := Source('Units.A', 'procedure P(X: Foo);'#10, '', 'procedure P(X: Foo);'#10'begin'#10'end;'#10);
  Assert.AreEqual('', States(mText, nil, nil));
end;

procedure TUsesActionsTests.FormReferenceCountsAsImplementationUse;
var
  mText: string;
begin
  // Der Code nennt nichts aus Units.Form, die Formulardatei aber Form1.Connection.
  mText := Source('Units.A, Units.Form', '', '', 'procedure P;'#10'begin'#10'  Foo;'#10'end;'#10);
  Assert.AreEqual('Units.A:impl|Units.Form:impl|', States(mText, nil, nil));
  Assert.AreEqual(0, Integer(Length(TUsesActions.UnusedUnits(TPascalLexer.Tokenize(mText), Info, nil))));
end;

procedure TUsesActionsTests.EntriesFollowActiveBranch;
var
  mText: string;
begin
  mText := Source('Units.A, {$IFDEF X}Units.B,{$ENDIF} Units.C', '', '',
    'procedure P;'#10'begin'#10'  Baz;'#10'  {$IFDEF X}Bar;{$ENDIF}'#10'end;'#10);
  // X nicht gesetzt: Units.B steht im inaktiven Zweig und fällt nicht auf; Units.A ist ungenutzt.
  Assert.AreEqual('Units.A:unused|Units.C:impl|', States(mText, TLspInactiveRegions.Ranges(mText, []), nil));
  // X gesetzt: Units.B wird im aktiven Zweig benutzt.
  Assert.AreEqual('Units.A:unused|Units.B:impl|Units.C:impl|', States(mText, TLspInactiveRegions.Ranges(mText, ['X']),
    nil));
  // Benutzt nur im inaktiven Zweig zählt nicht.
  mText := Source('', '', 'Units.B', 'procedure P;'#10'begin'#10'  {$IFDEF X}Bar;{$ENDIF}'#10'end;'#10);
  Assert.AreEqual('Units.B:unused|', States(mText, TLspInactiveRegions.Ranges(mText, []), nil));
  Assert.AreEqual('', States(mText, TLspInactiveRegions.Ranges(mText, ['X']), nil));
end;

procedure TUsesActionsTests.ProjectUsesAreNeverUnused;
var
  mText: string;
  mHead: string;
  mTokens: TArray<TPascalToken>;
begin
  for mHead in TArray<string>.Create('program P;', '{ Kopf }'#10'{$APPTYPE CONSOLE}'#10'program P;', 'library L;',
    'package Pk;') do
  begin
    mText := mHead + #10'uses'#10'  Units.A in ''A.pas'', Units.B, Units.Reg;'#10'begin'#10'  Foo;'#10'end.'#10;
    mTokens := TPascalLexer.Tokenize(mText);
    Assert.IsTrue(TUsesActions.ListsProjectUnits(mTokens), mHead);
    Assert.AreEqual(0, Integer(Length(TUsesActions.Entries(mTokens, nil, Info, nil))), mHead);
    Assert.AreEqual(0, Integer(Length(TUsesActions.UnusedUnits(mTokens, Info, nil))), mHead);
  end;
  // Eine Unit mit denselben uses meldet Units.B weiterhin.
  mText := Source('Units.A, Units.B', '', '', 'procedure P;'#10'begin'#10'  Foo;'#10'end;'#10);
  Assert.IsFalse(TUsesActions.ListsProjectUnits(TPascalLexer.Tokenize(mText)));
  Assert.AreEqual('Units.A:impl|Units.B:unused|', States(mText, nil, nil));
end;

/// <summary>Streicht die Einträge ANames (Bereiche aus References) und prüft, dass das Ergebnis parst.</summary>
function RemoveNamed(const AText: string; const ANames: TArray<string>; out AResult: string): Boolean;
var
  mReference: TUsesReference;
  mRanges: TArray<TTextRange>;
  mName: string;
  mEdit: TTextEdit;
  mTree: TSyntaxTree;
begin
  mRanges := nil;
  for mReference in TUsesClauses.References(TPascalLexer.Tokenize(AText)) do
  begin
    for mName in ANames do
    begin
      if SameText(mReference.Name, mName) then
      begin
        mRanges := mRanges + [mReference.Range];
      end;
    end;
  end;
  Result := TUsesActions.RemoveEntries(AText, mRanges, mEdit);
  AResult := AText;
  if not Result then
  begin
    Exit;
  end;
  AResult := Apply(AText, [mEdit]);
  mTree := TPascalParser.Parse(AResult);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), AResult);
  finally
    mTree.Free;
  end;
end;

procedure TUsesActionsTests.RemoveEntriesKeepsCodeValid;
var
  mText, mRemoved: string;
begin
  mText := Source('Units.A, Units.B', '', '', '');
  Assert.IsTrue(RemoveNamed(mText, ['Units.B'], mRemoved));
  Assert.AreEqual(Source('Units.A', '', '', ''), mRemoved);
  Assert.IsTrue(RemoveNamed(mText, ['Units.A'], mRemoved));
  Assert.AreEqual(Source('Units.B', '', '', ''), mRemoved);
  // Alle: das ganze uses mit seiner Zeile.
  Assert.IsTrue(RemoveNamed(mText, ['Units.A', 'Units.B'], mRemoved));
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'end.', mRemoved);
  mText := 'unit U;'#10'interface'#10'uses Units.A;'#10'implementation'#10'end.';
  Assert.IsTrue(RemoveNamed(mText, ['Units.A'], mRemoved));
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'end.', mRemoved);
  // Mehrzeilig: der Eintrag mit seiner Zeile.
  mText := 'unit U;'#10'interface'#10'uses'#10'  Units.A,'#10'  Units.B,'#10'  Units.C;'#10'implementation'#10'end.';
  Assert.IsTrue(RemoveNamed(mText, ['Units.B'], mRemoved));
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  Units.A,'#10'  Units.C;'#10'implementation'#10'end.', mRemoved);
  // Direktiven: im Zweig mit dem Komma dahinter; ein Komma jenseits einer Direktive fasst Atlas nicht an.
  mText := Source('Units.A, {$IFDEF X}Units.B, {$ENDIF}Units.C', '', '', '');
  Assert.IsTrue(RemoveNamed(mText, ['Units.B'], mRemoved));
  Assert.AreEqual(Source('Units.A, {$IFDEF X}{$ENDIF}Units.C', '', '', ''), mRemoved);
  Assert.IsTrue(RemoveNamed(mText, ['Units.A'], mRemoved));
  Assert.AreEqual(Source('{$IFDEF X}Units.B, {$ENDIF}Units.C', '', '', ''), mRemoved);
  Assert.IsFalse(RemoveNamed(mText, ['Units.C'], mRemoved), 'Komma liegt im Zweig');
  // Kommentar am Eintrag davor bleibt.
  mText := 'unit U;'#10'interface'#10'uses'#10'  Units.A, // a'#10'  Units.B;'#10'implementation'#10'end.';
  Assert.IsTrue(RemoveNamed(mText, ['Units.B'], mRemoved));
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  Units.A // a'#10'  ;'#10'implementation'#10'end.', mRemoved);
  // "in 'datei'" gehört dazu, CRLF bleibt.
  mText := 'program P;'#13#10'uses'#13#10'  Units.A in ''a.pas'','#13#10'  Units.B;'#13#10'begin'#13#10'end.';
  Assert.IsTrue(RemoveNamed(mText, ['Units.A'], mRemoved));
  Assert.AreEqual('program P;'#13#10'uses'#13#10'  Units.B;'#13#10'begin'#13#10'end.', mRemoved);
end;

procedure TUsesActionsTests.ActionsAtEntryCarryTags;
var
  mText, mFound: string;
  mContext: TUsesContext;
  mAction: TCodeAction;
  mTree: TSyntaxTree;
begin
  mText := Source('Units.A, Units.B, Units.C', '', '', 'procedure P;'#10'begin'#10'  Foo;'#10'end;'#10);
  mContext := Default(TUsesContext);
  mContext.Info := Info;
  mTree := TPascalParser.Parse(mText);
  try
    // Cursor auf Units.B (Zeile 3, Spalte 12).
    mFound := '';
    for mAction in TCodeActions.UsesActions(mText, mTree, TTextRange.Create(3, 12, 3, 12), mContext, True, False) do
    begin
      if mAction.Tag <> '' then
      begin
        mFound := mFound + mAction.Title + '=' + mAction.Tag + '|';
      end;
    end;
    Assert.AreEqual('Units.B entfernen=uses.remove|Alle ungenutzten uses entfernen (2)=uses.removeAll|', mFound);
    // Auf Units.A: nur in der implementation gebraucht, die Aktion für alle trägt die Kennung.
    mFound := '';
    for mAction in TCodeActions.UsesActions(mText, mTree, TTextRange.Create(3, 3, 3, 3), mContext, True, False) do
    begin
      if mAction.Tag <> '' then
      begin
        mFound := mFound + mAction.Title + '=' + mAction.Tag + '|';
      end;
    end;
    Assert.AreEqual('Units.A ins implementation-uses verschieben=uses.move|', mFound);
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TUsesActionsTests);

end.
