unit Atlas.Core.Editor.Pairs.Tests;

// Tests für Klammer- und Blockpaare (#514), ihre Besitzer-Schlüsselwörter (#653) und die Verschachtelung
// lokaler Routinen (#1788).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPairsTests = class
  public
    [Test]
    procedure NestedBeginEndHaveThreeDepths;
    [Test]
    procedure BracketsInStringsAndCommentsDoNotCount;
    [Test]
    procedure MissingEndMarksBeginRed;
    [Test]
    procedure TypeDeclarationsAndForwardsAndVariantCase;
    [Test]
    procedure TryFinallyRepeatUntilAndEscapes;
    [Test]
    procedure DisplayLineExpandsTabsAndRunsMatchOnlyAtTheirColumn;
    [Test]
    procedure GuidesSpanMultiLineBlocksAtIndentOfOpenerLine;
    [Test]
    procedure GuidesForTypesTabsAndSingleLineBlocks;
    [Test]
    procedure SwitchTurnsIdeStructureOffAndOnlyRestoresOwnChange;
    [Test]
    procedure IfThenAndElseTakeTheColorOfTheirBlock;
    [Test]
    procedure ElseIfThenColorsAllThreeWords;
    [Test]
    procedure LoopsWithAndOnDoColorTheirWords;
    [Test]
    procedure CaseColorsOf;
    [Test]
    procedure RoutineHeadTakesTheColorOfItsBody;
    [Test]
    procedure RoutineHeadsWithoutBodyStayPlain;
    [Test]
    procedure NoBlockNoOwners;
    [Test]
    procedure MissingEndMarksOwnersRed;
    [Test]
    procedure OwnersInStringsAndCommentsDoNotCount;
    [Test]
    procedure GuideStartsAtTheStatement;
    [Test]
    procedure PenWidthScalesWithLineHeight;
    [Test]
    procedure LocalRoutineTokensCarryTheirNesting;
    [Test]
    procedure LocalRoutineBlocksAreMarked;
    [Test]
    procedure InterfaceHeadsDoNotNest;
    [Test]
    procedure LocalTypesBelongToTheirRoutine;
    [Test]
    procedure SpansAndGuidesCarryTheNesting;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Editor.Guides;

/// <summary>"Text@Tiefe" je Token, Besitzer mit "*", unpaarige mit "!". AOwners: Besitzer mit ausgeben.</summary>
function DescribeTokens(const AText: string; AOwners: Boolean): string;
var
  mLines: TArray<string>;
  mToken: TAtlasPairToken;
begin
  mLines := AText.Split([#10]);
  Result := '';
  for mToken in TAtlasPairs.Analyze(AText) do
  begin
    if mToken.Owner and not AOwners then
    begin
      Continue;
    end;
    Result := Result + Copy(mLines[mToken.Line], mToken.Character + 1, mToken.Length) + '@' + IntToStr(mToken.Depth);
    if mToken.Owner then
    begin
      Result := Result + '*';
    end;
    if mToken.Unpaired then
    begin
      Result := Result + '!';
    end;
    Result := Result + ' ';
  end;
  Result := Trim(Result);
end;

/// <summary>"Text@Tiefe/Routine" je Token samt Besitzern (#1788), Besitzer mit "*".</summary>
function Nesting(const AText: string): string;
var
  mLines: TArray<string>;
  mToken: TAtlasPairToken;
begin
  mLines := AText.Split([#10]);
  Result := '';
  for mToken in TAtlasPairs.Analyze(AText) do
  begin
    Result := Result + Copy(mLines[mToken.Line], mToken.Character + 1, mToken.Length) + '@' + IntToStr(mToken.Depth) +
      '/' + IntToStr(mToken.Routine);
    if mToken.Owner then
    begin
      Result := Result + '*';
    end;
    Result := Result + ' ';
  end;
  Result := Trim(Result);
end;

const
  /// <summary>Routine A mit lokaler Funktion B, darin ein if-Block (#1788).</summary>
  cLocal = 'procedure A;'#10'  function B: Boolean;'#10'  begin'#10'    if X then'#10'    begin'#10'    end;'#10 +
    '  end;'#10'begin'#10'end;';

/// <summary>Wie bisher (#514): nur Klammern und Blockwörter.</summary>
function Describe(const AText: string): string;
begin
  Result := DescribeTokens(AText, False);
end;

/// <summary>Mit Besitzer-Schlüsselwörtern (#653).</summary>
function Owners(const AText: string): string;
begin
  Result := DescribeTokens(AText, True);
end;

procedure TAtlasPairsTests.NestedBeginEndHaveThreeDepths;
begin
  Assert.AreEqual('begin@0 begin@1 begin@2 end@2 end@1 end@0',
    Describe('begin'#10'  begin'#10'    begin'#10'    end;'#10'  end;'#10'end;'));
  // Runde und eckige Klammern teilen sich die Tiefe.
  Assert.AreEqual('(@0 (@1 [@2 ]@2 )@1 )@0', Describe('X := F(G(A[1]));'));
end;

procedure TAtlasPairsTests.BracketsInStringsAndCommentsDoNotCount;
begin
  Assert.AreEqual('(@0 )@0', Describe('S := Format(''(%d'', { ( } (* ( *) 1); // )'));
  Assert.AreEqual('', Describe('// begin'#10'{ end }'));
end;

procedure TAtlasPairsTests.MissingEndMarksBeginRed;
begin
  Assert.AreEqual('begin@0! begin@1 end@1', Describe('begin'#10'  begin'#10'  end;'));
  Assert.AreEqual('end@0!', Describe('end;'));
  Assert.AreEqual(')@0!', Describe('X)'));
  // Ende der Unit ist kein unpaariges end.
  Assert.AreEqual('', Describe('unit X;'#10'interface'#10'implementation'#10'end.'));
end;

procedure TAtlasPairsTests.TypeDeclarationsAndForwardsAndVariantCase;
begin
  Assert.AreEqual('class@0 end@0', Describe('TFoo = class'#10'  class function F: Integer;'#10'end;'));
  // Vorwärtsdeklaration und Kurzform ohne Rumpf.
  Assert.AreEqual('(@0 )@0', Describe('TFoo = class;'#10'TBar = class(TFoo);'));
  Assert.AreEqual('', Describe('TEvent = procedure of object;'#10'TMeta = class of TFoo;'));
  Assert.AreEqual('record@0 (@0 )@0 end@0',
    Describe('TRec = record'#10'  case Integer of'#10'    0: (A: Integer);'#10'end;'));
  Assert.AreEqual('interface@0 end@0', Describe('IFoo = interface'#10'end;'));
end;

procedure TAtlasPairsTests.TryFinallyRepeatUntilAndEscapes;
begin
  Assert.AreEqual('try@0 repeat@1 until@1 finally@0 end@0',
    Describe('try'#10'  repeat'#10'  until X;'#10'finally'#10'end;'));
  Assert.AreEqual('begin@0 end@0', Describe('begin'#10'  &end := 1;'#10'  A.Begin;'#10'end;'));
  // Sprungmarken im asm-Block sind keine Blockwörter (#861).
  Assert.AreEqual('asm@0 end@0', Describe('asm'#10'  JNZ @@End'#10'@@end:'#10'end;'));
  // Steuerzeichen ^[ ist keine Klammer, P^[1] schon (#862).
  Assert.AreEqual('', Describe('Esc = ^[;'));
  Assert.AreEqual('[@0 ]@0', Describe('X := P^[1];'));
end;

procedure TAtlasPairsTests.DisplayLineExpandsTabsAndRunsMatchOnlyAtTheirColumn;
var
  mLine: string;
begin
  Assert.AreEqual('a   b', TAtlasPairs.DisplayLine('a'#9'b'#13, 4));
  Assert.AreEqual('    x', TAtlasPairs.DisplayLine(#9'x', 4));
  Assert.AreEqual(#9'x', TAtlasPairs.DisplayLine(#9'x', 0));
  mLine := TAtlasPairs.DisplayLine('  if (A) then', 2);
  Assert.IsTrue(TAtlasPairs.RunMatches(mLine, '(', 6));
  Assert.IsTrue(TAtlasPairs.RunMatches(mLine, 'if', 3));
  // Lauf einer anderen Zeile bzw. an anderer Spalte: nicht einfärben.
  Assert.IsFalse(TAtlasPairs.RunMatches(mLine, 'begin', 3));
  Assert.IsFalse(TAtlasPairs.RunMatches(mLine, '(', 5));
  Assert.IsFalse(TAtlasPairs.RunMatches(mLine, 'then', 12));
  Assert.IsFalse(TAtlasPairs.RunMatches(mLine, '', 1));
  // Zeichenindex als Editorspalte (#615).
  Assert.AreEqual(1, TAtlasPairs.ColumnOf('abc', 0, 4));
  Assert.AreEqual(3, TAtlasPairs.ColumnOf('abc', 2, 4));
  Assert.AreEqual(5, TAtlasPairs.ColumnOf('a'#9'b', 2, 4));
  Assert.AreEqual(5, TAtlasPairs.ColumnOf(#9'x', 1, 4));
  Assert.AreEqual(2, TAtlasPairs.ColumnOf(#9'x', 1, 0));
end;

/// <summary>"Erste-Letzte@Spalte:Tiefe" je Linie.</summary>
function DescribeGuides(const AText: string; ATabWidth: Integer): string;
var
  mGuide: TAtlasGuide;
begin
  Result := '';
  for mGuide in TAtlasGuides.Compute(AText, ATabWidth) do
  begin
    Result := Result + Format('%d-%d@%d:%d ', [mGuide.FirstLine, mGuide.LastLine, mGuide.Column, mGuide.Depth]);
  end;
  Result := Trim(Result);
end;

procedure TAtlasPairsTests.GuidesSpanMultiLineBlocksAtIndentOfOpenerLine;
begin
  // Innerer Block zuerst (Reihenfolge des Endes); "if A then begin" steht am Einzug des if.
  Assert.AreEqual('2-4@3:1 1-5@1:0', DescribeGuides('procedure X;'#10'begin'#10'  if A then begin'#10'    B;'#10 +
    '  end;'#10'end;', 2));
  Assert.AreEqual('0-2@1:0', DescribeGuides('repeat'#10'  A;'#10'until B;', 2));
end;

procedure TAtlasPairsTests.GuidesForTypesTabsAndSingleLineBlocks;
begin
  Assert.AreEqual('0-2@3:0', DescribeGuides('  TFoo = class'#10'    F: Integer;'#10'  end;', 2));
  Assert.AreEqual('0-1@5:0', DescribeGuides(#9'begin'#13#10#9'end;', 4));
  // Block in einer Zeile: keine Linie.
  Assert.AreEqual('', DescribeGuides('begin end;', 2));
  // Unpaarig: keine Linie.
  Assert.AreEqual('', DescribeGuides('begin'#10'  A;', 2));
end;

procedure TAtlasPairsTests.SwitchTurnsIdeStructureOffAndOnlyRestoresOwnChange;
var
  mState, mNext: TAtlasIdeStructure;
begin
  mState.Enabled := True;
  mState.DisabledByAtlas := False;
  mNext := TAtlasGuides.Switch(mState, True);
  Assert.IsFalse(mNext.Enabled, 'eigene Linien: IDE aus');
  Assert.IsTrue(mNext.DisabledByAtlas);
  mNext := TAtlasGuides.Switch(mNext, False);
  Assert.IsTrue(mNext.Enabled, 'eigene Linien aus: IDE wieder an');
  Assert.IsFalse(mNext.DisabledByAtlas);
  // Vom User selbst abgeschaltet: Atlas fasst es nicht an.
  mState.Enabled := False;
  mState.DisabledByAtlas := False;
  mNext := TAtlasGuides.Switch(mState, False);
  Assert.IsFalse(mNext.Enabled);
  mNext := TAtlasGuides.Switch(mState, True);
  Assert.IsFalse(mNext.Enabled);
  Assert.IsFalse(mNext.DisabledByAtlas);
end;

procedure TAtlasPairsTests.IfThenAndElseTakeTheColorOfTheirBlock;
begin
  // Abnahme #653: if, then und das erste begin/end in einer Farbe; else in der des zweiten Blocks.
  Assert.AreEqual('procedure@0* begin@0 if@1* then@1* begin@1 end@1 else@1* begin@1 end@1 end@0',
    Owners('procedure X;'#10'begin'#10'  if A then'#10'  begin'#10'  end'#10'  else'#10'  begin'#10'  end;'#10 +
    'end;'));
  // Stil "end else begin" und Bedingung über mehrere Zeilen.
  Assert.AreEqual('if@0* (@0 )@0 then@0* begin@0 end@0 else@0* begin@0 end@0',
    Owners('if A and'#10'  (B or C) then begin'#10'end else begin'#10'end;'));
  // Ohne Besitzer bleibt die Ausgabe wie bisher.
  Assert.AreEqual('begin@0 end@0 begin@0 end@0', Describe('if A then begin'#10'end else begin'#10'end;'));
end;

procedure TAtlasPairsTests.ElseIfThenColorsAllThreeWords;
begin
  // Das erste if hat keinen Block und bleibt ungefärbt.
  Assert.AreEqual('else@0* if@0* then@0* begin@0 end@0',
    Owners('if A then Foo'#10'else if B then'#10'begin'#10'end;'));
end;

procedure TAtlasPairsTests.LoopsWithAndOnDoColorTheirWords;
begin
  Assert.AreEqual('for@0* do@0* begin@0 end@0', Owners('for I := 0 to 9 do begin'#10'end;'));
  Assert.AreEqual('for@0* do@0* begin@0 end@0', Owners('for S in List do'#10'begin'#10'end;'));
  Assert.AreEqual('while@0* (@0 )@0 do@0* begin@0 end@0', Owners('while (A) do'#10'begin'#10'end;'));
  Assert.AreEqual('with@0* do@0* begin@0 end@0', Owners('with A, B do begin end;'));
  Assert.AreEqual('try@0 except@0 on@1* do@1* begin@1 end@1 end@0',
    Owners('try'#10'except'#10'  on E: Exception do'#10'  begin'#10'  end;'#10'end;'));
end;

procedure TAtlasPairsTests.CaseColorsOf;
begin
  Assert.AreEqual('case@0 (@0 )@0 of@0* end@0', Owners('case F(X) of'#10'  1: ;'#10'end;'));
  // Variante Teile im record öffnen keinen Block, also auch kein "of".
  Assert.AreEqual('record@0 end@0', Owners('TRec = record'#10'  case Integer of'#10'    0: ;'#10'end;'));
end;

procedure TAtlasPairsTests.RoutineHeadTakesTheColorOfItsBody;
var
  mBlocks: TArray<TAtlasPairBlock>;
begin
  // Abnahme #653: auch mit var-Block zwischen Kopf und Rumpf.
  Assert.AreEqual('procedure@0* begin@0 end@0',
    Owners('procedure TFoo.Bar;'#10'var'#10'  I: Integer;'#10'begin'#10'end;'));
  Assert.AreEqual('class@0* function@0* begin@0 end@0',
    Owners('class function TFoo.Make: TFoo;'#10'begin'#10'end;'));
  Assert.AreEqual('class@0* operator@0* (@0 )@0 begin@0 end@0',
    Owners('class operator TFoo.Add(A, B: TFoo): TFoo;'#10'begin'#10'end;'));
  Assert.AreEqual('constructor@0* begin@0 end@0 destructor@0* begin@0 end@0',
    Owners('constructor TFoo.Create;'#10'begin'#10'end;'#10'destructor TFoo.Destroy;'#10'begin'#10'end;'));
  // Lokale Routine: ihr Kopf gehört zum ersten Rumpf, der äußere Kopf zum zweiten.
  TAtlasPairs.Analyze('procedure A;'#10'  procedure B;'#10'  begin'#10'  end;'#10'begin'#10'end;', mBlocks);
  Assert.AreEqual(2, Integer(Length(mBlocks)));
  Assert.AreEqual(1, mBlocks[0].OwnerLine);
  Assert.AreEqual(2, mBlocks[0].OwnerCharacter);
  Assert.AreEqual(0, mBlocks[1].OwnerLine);
end;

procedure TAtlasPairsTests.RoutineHeadsWithoutBodyStayPlain;
begin
  // Deklaration im interface, Prozedurtypen, Methoden in der Klasse, forward.
  Assert.AreEqual('procedure@0* begin@0 end@0',
    Owners('interface'#10'procedure A;'#10'implementation'#10'procedure A;'#10'begin'#10'end;'));
  Assert.AreEqual('procedure@0* begin@0 end@0',
    Owners('type'#10'  TP = reference to procedure;'#10'  TE = procedure of object;'#10'var'#10 +
    '  P: procedure;'#10'procedure A; forward;'#10'procedure B;'#10'begin'#10'end;'));
  Assert.AreEqual('class@0 end@0', Owners('TFoo = class'#10'  procedure A;'#10'end;'));
end;

procedure TAtlasPairsTests.NoBlockNoOwners;
begin
  Assert.AreEqual('', Owners('if X then Foo;'));
  Assert.AreEqual('', Owners('for I := 0 to 9 do Foo;'));
  Assert.AreEqual('begin@0 end@0', Owners('if X then Foo else Bar;'#10'begin'#10'end;'));
end;

procedure TAtlasPairsTests.MissingEndMarksOwnersRed;
begin
  // Abnahme #653: fehlt das end, sind if, then und begin in der Fehlerfarbe.
  Assert.AreEqual('if@0*! then@0*! begin@0!', Owners('if A then'#10'begin'#10'  B;'));
end;

procedure TAtlasPairsTests.OwnersInStringsAndCommentsDoNotCount;
begin
  Assert.AreEqual('begin@0 end@0', Owners('S := ''if A then''; // if A then'#10'{ if A then } begin end;'));
  Assert.AreEqual('begin@0 end@0', Owners('&if := A; X := &then;'#10'begin end;'));
end;

/// <summary>Wie DescribeGuides, mit Besitzern.</summary>
function DescribeOwnerGuides(const AText: string; ATabWidth: Integer): string;
var
  mBlocks: TArray<TAtlasPairBlock>;
  mGuide: TAtlasGuide;
begin
  TAtlasPairs.Analyze(AText, mBlocks);
  Result := '';
  for mGuide in TAtlasGuides.FromBlocks(AText.Split([#10]), mBlocks, ATabWidth, True) do
  begin
    Result := Result + Format('%d-%d@%d:%d ', [mGuide.FirstLine, mGuide.LastLine, mGuide.Column, mGuide.Depth]);
  end;
  Result := Trim(Result);
end;

procedure TAtlasPairsTests.GuideStartsAtTheStatement;
const
  cCode = 'procedure X;'#10'begin'#10'  if A then'#10'  begin'#10'    B;'#10'  end;'#10'end;';
begin
  // Abnahme #653: Die Linie des begin unter "if … then" beginnt an der if-Zeile.
  Assert.AreEqual('2-5@3:1 0-6@1:0', DescribeOwnerGuides(cCode, 2));
  // Ohne Besitzer wie bisher am begin.
  Assert.AreEqual('3-5@3:1 1-6@1:0', DescribeGuides(cCode, 2));
  // begin hinter then in derselben Zeile: unverändert.
  Assert.AreEqual('0-2@1:0', DescribeOwnerGuides('if A then begin'#10'  B;'#10'end;', 2));
end;

procedure TAtlasPairsTests.PenWidthScalesWithLineHeight;
begin
  // Breite 1 sieht aus wie bisher.
  Assert.AreEqual(1, TAtlasGuides.PenWidth(1, 16, 16));
  Assert.AreEqual(2, TAtlasGuides.PenWidth(2, 17, 16));
  // 200 % (Monitor oder Zoom).
  Assert.AreEqual(4, TAtlasGuides.PenWidth(2, 32, 16));
  // Grenzen und fehlende Werte.
  Assert.AreEqual(3, TAtlasGuides.PenWidth(9, 16, 16));
  Assert.AreEqual(1, TAtlasGuides.PenWidth(0, 16, 16));
  Assert.AreEqual(2, TAtlasGuides.PenWidth(2, 0, 16));
end;

procedure TAtlasPairsTests.LocalRoutineTokensCarryTheirNesting;
begin
  // Ursache von #1788: Tiefe zählt nur Blöcke, deshalb haben A und B beide Tiefe 0; Routine trennt sie.
  Assert.AreEqual('procedure@0/0* function@0/1* begin@0/1 if@1/1* then@1/1* begin@1/1 end@1/1 end@0/1 ' +
    'begin@0/0 end@0/0', Nesting(cLocal));
  // Zwei Stufen: C in B in A.
  Assert.AreEqual('procedure@0/0* procedure@0/1* procedure@0/2* begin@0/2 end@0/2 begin@0/1 end@0/1 begin@0/0 ' +
    'end@0/0', Nesting('procedure A;'#10'procedure B;'#10'procedure C;'#10'begin'#10'end;'#10'begin'#10'end;'#10 +
    'begin'#10'end;'));
  // Nach dem Ende der lokalen Routine wieder Stufe 0: zwei Routinen nacheinander.
  Assert.AreEqual('procedure@0/0* begin@0/0 end@0/0 procedure@0/0* begin@0/0 end@0/0',
    Nesting('procedure A;'#10'begin'#10'end;'#10'procedure B;'#10'begin'#10'end;'));
end;

procedure TAtlasPairsTests.LocalRoutineBlocksAreMarked;
var
  mBlocks: TArray<TAtlasPairBlock>;
begin
  TAtlasPairs.Analyze(cLocal, mBlocks);
  // In der Reihenfolge ihres Endes: if-Block, Rumpf von B, Rumpf von A.
  Assert.AreEqual(3, Integer(Length(mBlocks)));
  Assert.IsFalse(mBlocks[0].IsRoutine);
  Assert.AreEqual(1, mBlocks[0].Routine);
  Assert.IsTrue(mBlocks[1].IsRoutine);
  Assert.AreEqual(1, mBlocks[1].Routine);
  Assert.AreEqual(1, mBlocks[1].OwnerLine);
  Assert.IsTrue(mBlocks[2].IsRoutine);
  Assert.AreEqual(0, mBlocks[2].Routine);
end;

procedure TAtlasPairsTests.InterfaceHeadsDoNotNest;
begin
  // Köpfe im interface haben keinen Rumpf; ohne Abschnittserkennung stünde die Klasse eine Stufe tiefer.
  Assert.AreEqual('class@0/0 end@0/0', Nesting('unit U;'#10'interface'#10'procedure P;'#10'procedure Q;'#10 +
    'type'#10'  TFoo = class'#10'  end;'));
  // Der Typ IFoo = interface beginnt keinen Abschnitt.
  Assert.AreEqual('interface@0/0 end@0/0 procedure@0/0* begin@0/0 end@0/0',
    Nesting('type'#10'  IFoo = interface'#10'  end;'#10'procedure A;'#10'begin'#10'end;'));
end;

procedure TAtlasPairsTests.LocalTypesBelongToTheirRoutine;
begin
  Assert.AreEqual('procedure@0/0* record@0/0 end@0/0 procedure@0/1* record@0/1 end@0/1 begin@0/1 end@0/1 ' +
    'begin@0/0 end@0/0', Nesting('procedure A;'#10'type'#10'  TA = record'#10'  end;'#10'  procedure B;'#10 +
    '  type'#10'    TB = record'#10'    end;'#10'  begin'#10'  end;'#10'begin'#10'end;'));
end;

procedure TAtlasPairsTests.SpansAndGuidesCarryTheNesting;
var
  mBlocks: TArray<TAtlasPairBlock>;
  mTokens, mLineTokens: TArray<TAtlasPairToken>;
  mToken: TAtlasPairToken;
  mSpans: TArray<TAtlasPairSpan>;
  mGuides: TArray<TAtlasGuide>;
  mLines: TArray<string>;
begin
  mLines := cLocal.Split([#10]);
  mTokens := TAtlasPairs.Analyze(cLocal, mBlocks);
  mLineTokens := nil;
  for mToken in mTokens do
  begin
    if mToken.Line = 1 then
    begin
      mLineTokens := mLineTokens + [mToken];
    end;
  end;
  mSpans := TAtlasPairs.Spans(TrimLeft(mLines[1]), mLines[1], mLineTokens, True);
  Assert.AreEqual(1, Integer(Length(mSpans)));
  Assert.AreEqual(1, mSpans[0].Routine, 'Kopf der lokalen Funktion im mitlaufenden Kopf');
  mGuides := TAtlasGuides.FromBlocks(mLines, mBlocks, 2, True);
  Assert.AreEqual(3, Integer(Length(mGuides)));
  Assert.AreEqual(1, mGuides[1].Routine);
  Assert.AreEqual(1, mGuides[1].FirstLine, 'Linie ab dem Kopf');
  Assert.AreEqual(0, mGuides[2].Routine);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPairsTests);

end.