unit Argus.Core.Editor.Pairs.Tests;

// Tests für Klammer- und Blockpaare (#514).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusPairsTests = class
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
  end;

implementation

uses
  System.SysUtils,
  Argus.Core.Editor.Pairs,
  Argus.Core.Editor.Guides;

/// <summary>"Text@Tiefe" je Token, unpaarige mit "!".</summary>
function Describe(const AText: string): string;
var
  Lines: TArray<string>;
  Token: TArgusPairToken;
begin
  Lines := AText.Split([#10]);
  Result := '';
  for Token in TArgusPairs.Analyze(AText) do
  begin
    Result := Result + Copy(Lines[Token.Line], Token.Character + 1, Token.Length) + '@' + IntToStr(Token.Depth);
    if Token.Unpaired then
      Result := Result + '!';
    Result := Result + ' ';
  end;
  Result := Trim(Result);
end;

procedure TArgusPairsTests.NestedBeginEndHaveThreeDepths;
begin
  Assert.AreEqual('begin@0 begin@1 begin@2 end@2 end@1 end@0',
    Describe('begin'#10'  begin'#10'    begin'#10'    end;'#10'  end;'#10'end;'));
  // Runde und eckige Klammern teilen sich die Tiefe.
  Assert.AreEqual('(@0 (@1 [@2 ]@2 )@1 )@0', Describe('X := F(G(A[1]));'));
end;

procedure TArgusPairsTests.BracketsInStringsAndCommentsDoNotCount;
begin
  Assert.AreEqual('(@0 )@0', Describe('S := Format(''(%d'', { ( } (* ( *) 1); // )'));
  Assert.AreEqual('', Describe('// begin'#10'{ end }'));
end;

procedure TArgusPairsTests.MissingEndMarksBeginRed;
begin
  Assert.AreEqual('begin@0! begin@1 end@1', Describe('begin'#10'  begin'#10'  end;'));
  Assert.AreEqual('end@0!', Describe('end;'));
  Assert.AreEqual(')@0!', Describe('X)'));
  // Ende der Unit ist kein unpaariges end.
  Assert.AreEqual('', Describe('unit X;'#10'interface'#10'implementation'#10'end.'));
end;

procedure TArgusPairsTests.TypeDeclarationsAndForwardsAndVariantCase;
begin
  Assert.AreEqual('class@0 end@0', Describe('TFoo = class'#10'  class function F: Integer;'#10'end;'));
  // Vorwärtsdeklaration und Kurzform ohne Rumpf.
  Assert.AreEqual('(@0 )@0', Describe('TFoo = class;'#10'TBar = class(TFoo);'));
  Assert.AreEqual('', Describe('TEvent = procedure of object;'#10'TMeta = class of TFoo;'));
  Assert.AreEqual('record@0 (@0 )@0 end@0',
    Describe('TRec = record'#10'  case Integer of'#10'    0: (A: Integer);'#10'end;'));
  Assert.AreEqual('interface@0 end@0', Describe('IFoo = interface'#10'end;'));
end;

procedure TArgusPairsTests.TryFinallyRepeatUntilAndEscapes;
begin
  Assert.AreEqual('try@0 repeat@1 until@1 finally@0 end@0',
    Describe('try'#10'  repeat'#10'  until X;'#10'finally'#10'end;'));
  Assert.AreEqual('begin@0 end@0', Describe('begin'#10'  &end := 1;'#10'  A.Begin;'#10'end;'));
end;

procedure TArgusPairsTests.DisplayLineExpandsTabsAndRunsMatchOnlyAtTheirColumn;
var
  Line: string;
begin
  Assert.AreEqual('a   b', TArgusPairs.DisplayLine('a'#9'b'#13, 4));
  Assert.AreEqual('    x', TArgusPairs.DisplayLine(#9'x', 4));
  Assert.AreEqual(#9'x', TArgusPairs.DisplayLine(#9'x', 0));
  Line := TArgusPairs.DisplayLine('  if (A) then', 2);
  Assert.IsTrue(TArgusPairs.RunMatches(Line, '(', 6));
  Assert.IsTrue(TArgusPairs.RunMatches(Line, 'if', 3));
  // Lauf einer anderen Zeile bzw. an anderer Spalte: nicht einfärben.
  Assert.IsFalse(TArgusPairs.RunMatches(Line, 'begin', 3));
  Assert.IsFalse(TArgusPairs.RunMatches(Line, '(', 5));
  Assert.IsFalse(TArgusPairs.RunMatches(Line, 'then', 12));
  Assert.IsFalse(TArgusPairs.RunMatches(Line, '', 1));
end;

/// <summary>"Erste-Letzte@Spalte:Tiefe" je Linie.</summary>
function DescribeGuides(const AText: string; ATabWidth: Integer): string;
var
  Guide: TArgusGuide;
begin
  Result := '';
  for Guide in TArgusGuides.Compute(AText, ATabWidth) do
    Result := Result + Format('%d-%d@%d:%d ', [Guide.FirstLine, Guide.LastLine, Guide.Column, Guide.Depth]);
  Result := Trim(Result);
end;

procedure TArgusPairsTests.GuidesSpanMultiLineBlocksAtIndentOfOpenerLine;
begin
  // Innerer Block zuerst (Reihenfolge des Endes); "if A then begin" steht am Einzug des if.
  Assert.AreEqual('2-4@3:1 1-5@1:0', DescribeGuides('procedure X;'#10'begin'#10'  if A then begin'#10'    B;'#10 +
    '  end;'#10'end;', 2));
  Assert.AreEqual('0-2@1:0', DescribeGuides('repeat'#10'  A;'#10'until B;', 2));
end;

procedure TArgusPairsTests.GuidesForTypesTabsAndSingleLineBlocks;
begin
  Assert.AreEqual('0-2@3:0', DescribeGuides('  TFoo = class'#10'    F: Integer;'#10'  end;', 2));
  Assert.AreEqual('0-1@5:0', DescribeGuides(#9'begin'#13#10#9'end;', 4));
  // Block in einer Zeile: keine Linie.
  Assert.AreEqual('', DescribeGuides('begin end;', 2));
  // Unpaarig: keine Linie.
  Assert.AreEqual('', DescribeGuides('begin'#10'  A;', 2));
end;

procedure TArgusPairsTests.SwitchTurnsIdeStructureOffAndOnlyRestoresOwnChange;
var
  State, Next: TArgusIdeStructure;
begin
  State.Enabled := True;
  State.DisabledByArgus := False;
  Next := TArgusGuides.Switch(State, True);
  Assert.IsFalse(Next.Enabled, 'eigene Linien: IDE aus');
  Assert.IsTrue(Next.DisabledByArgus);
  Next := TArgusGuides.Switch(Next, False);
  Assert.IsTrue(Next.Enabled, 'eigene Linien aus: IDE wieder an');
  Assert.IsFalse(Next.DisabledByArgus);
  // Vom User selbst abgeschaltet: Argus fasst es nicht an.
  State.Enabled := False;
  State.DisabledByArgus := False;
  Next := TArgusGuides.Switch(State, False);
  Assert.IsFalse(Next.Enabled);
  Next := TArgusGuides.Switch(State, True);
  Assert.IsFalse(Next.Enabled);
  Assert.IsFalse(Next.DisabledByArgus);
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusPairsTests);

end.