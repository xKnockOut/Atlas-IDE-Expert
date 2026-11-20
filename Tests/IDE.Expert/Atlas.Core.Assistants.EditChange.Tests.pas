unit Atlas.Core.Assistants.EditChange.Tests;

// Tests für den geänderten Zeilenblock einer Änderung von KI-Assistenten (#2049, #2605): Block, Zeilen, Umgebung,
// Zurücknehmen nach Änderungen an anderer Stelle und seither geänderte Stellen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasEditChangeTests = class
  public
    [Test]
    procedure BetweenFindsTheChangedLines;
    [Test]
    procedure InsertionCountsOnlyAddedLines;
    [Test]
    procedure EqualTextsAreEmpty;
    [Test]
    procedure RevertRestoresTheOldBlock;
    [Test]
    procedure RevertSurvivesEditsElsewhere;
    [Test]
    procedure RevertRefusesChangedPlace;
    [Test]
    procedure RevertRefusesAmbiguousPlace;
    [Test]
    procedure RevertAtFileStartStaysAnchored;
    [Test]
    procedure LargeChangeKeepsNoTexts;
    [Test]
    procedure DiffLinesShowOldAndNew;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Assistants.EditChange;

const
  cBefore = 'unit A;'#13#10'interface'#13#10'procedure P;'#13#10'implementation'#13#10'procedure P;'#13#10 +
    'begin'#13#10'  X := 1;'#13#10'end;'#13#10'end.'#13#10;
  cAfter = 'unit A;'#13#10'interface'#13#10'procedure P;'#13#10'implementation'#13#10'procedure P;'#13#10 +
    'begin'#13#10'  X := 2;'#13#10'  Y := 3;'#13#10'end;'#13#10'end.'#13#10;

{ TAtlasEditChangeTests }

procedure TAtlasEditChangeTests.BetweenFindsTheChangedLines;
var
  mChange: TAtlasEditChange;
begin
  mChange := TAtlasEditChange.Between(cBefore, cAfter);
  Assert.AreEqual(7, mChange.FirstLine);
  Assert.AreEqual(8, mChange.LastLine);
  Assert.AreEqual(1, mChange.Removed);
  Assert.AreEqual(2, mChange.Added);
  Assert.AreEqual('  X := 1;'#13#10, mChange.OldText);
  Assert.AreEqual('  X := 2;'#13#10'  Y := 3;'#13#10, mChange.NewText);
  Assert.AreEqual('procedure P;'#13#10'begin'#13#10, mChange.Before, 'zwei Zeilen davor');
  Assert.AreEqual('end;'#13#10'end.'#13#10, mChange.After, 'zwei Zeilen danach');
  Assert.IsFalse(mChange.AtStart);
  Assert.IsTrue(mChange.AtEnd, 'die Umgebung reicht bis zum Ende');
  Assert.IsTrue(mChange.Kept);
end;

procedure TAtlasEditChangeTests.InsertionCountsOnlyAddedLines;
var
  mChange: TAtlasEditChange;
begin
  mChange := TAtlasEditChange.Between('a'#10'b'#10, 'a'#10'x'#10'y'#10'b'#10);
  Assert.AreEqual(2, mChange.FirstLine);
  Assert.AreEqual(0, mChange.Removed);
  Assert.AreEqual(2, mChange.Added);
  Assert.AreEqual('', mChange.OldText);
end;

procedure TAtlasEditChangeTests.EqualTextsAreEmpty;
var
  mChange: TAtlasEditChange;
  mText: string;
begin
  mChange := TAtlasEditChange.Between(cBefore, cBefore);
  Assert.IsTrue(mChange.IsEmpty);
  Assert.IsFalse(mChange.RevertIn(cBefore, mText), 'nichts zurückzunehmen');
end;

procedure TAtlasEditChangeTests.RevertRestoresTheOldBlock;
var
  mText: string;
begin
  Assert.IsTrue(TAtlasEditChange.Between(cBefore, cAfter).RevertIn(cAfter, mText));
  Assert.AreEqual(cBefore, mText);
end;

procedure TAtlasEditChangeTests.RevertSurvivesEditsElsewhere;
var
  mText: string;
begin
  // Der Benutzer hat oben eine Zeile eingefügt: Die Stelle verschiebt sich, bleibt aber eindeutig.
  Assert.IsTrue(TAtlasEditChange.Between(cBefore, cAfter).RevertIn('// neu'#13#10 + cAfter, mText));
  Assert.AreEqual('// neu'#13#10 + cBefore, mText);
end;

procedure TAtlasEditChangeTests.RevertRefusesChangedPlace;
var
  mText: string;
begin
  Assert.IsFalse(TAtlasEditChange.Between(cBefore, cAfter).RevertIn(cAfter.Replace('Y := 3', 'Y := 4'), mText));
  Assert.AreEqual('', mText);
end;

procedure TAtlasEditChangeTests.RevertRefusesAmbiguousPlace;
var
  mChange: TAtlasEditChange;
  mText: string;
begin
  mChange := TAtlasEditChange.Between('a'#10'b'#10'c'#10'd'#10'e'#10'f'#10, 'a'#10'b'#10'c'#10'X'#10'e'#10'f'#10);
  // Derselbe Block mit Umgebung steht zweimal da: nicht raten.
  Assert.IsFalse(mChange.RevertIn('b'#10'c'#10'X'#10'e'#10'f'#10'b'#10'c'#10'X'#10'e'#10'f'#10, mText));
end;

procedure TAtlasEditChangeTests.RevertAtFileStartStaysAnchored;
var
  mChange: TAtlasEditChange;
  mText: string;
begin
  mChange := TAtlasEditChange.Between('alt'#10'b'#10, 'neu'#10'b'#10);
  Assert.IsTrue(mChange.AtStart);
  Assert.IsTrue(mChange.RevertIn('neu'#10'b'#10, mText));
  Assert.AreEqual('alt'#10'b'#10, mText);
  // Davor eingefügt: Der Block steht nicht mehr am Anfang, also ist die Stelle seither geändert.
  Assert.IsFalse(mChange.RevertIn('x'#10'neu'#10'b'#10, mText));
end;

procedure TAtlasEditChangeTests.LargeChangeKeepsNoTexts;
var
  mChange: TAtlasEditChange;
  mText: string;
begin
  mChange := TAtlasEditChange.Between('a', StringOfChar('x', TAtlasEditChange.cMaxKeptChars + 1));
  Assert.IsFalse(mChange.Kept);
  Assert.AreEqual('', mChange.NewText);
  Assert.IsFalse(mChange.RevertIn(StringOfChar('x', TAtlasEditChange.cMaxKeptChars + 1), mText));
end;

procedure TAtlasEditChangeTests.DiffLinesShowOldAndNew;
var
  mLines: TArray<string>;
begin
  mLines := TAtlasEditChange.Between(cBefore, cAfter).DiffLines;
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.AreEqual('-   X := 1;', mLines[0]);
  Assert.AreEqual('+   X := 2;', mLines[1]);
  Assert.AreEqual('+   Y := 3;', mLines[2]);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditChangeTests);

end.
