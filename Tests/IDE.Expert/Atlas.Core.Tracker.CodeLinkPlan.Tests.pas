unit Atlas.Core.Tracker.CodeLinkPlan.Tests;

// Tests der Issue-Kennungen im Editor ohne IDE (#1967): Pascal-Dateien, wann ein Stand neu gerechnet wird, welche
// Zeile der Editor zeichnet, abgefangene Klicks und Befehl zum Strg+Klick.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasCodeLinkPlanTests = class
  public
    [Test]
    procedure PascalFilesOnly;
    [Test]
    procedure StateChangesWithBufferOrPattern;
    [Test]
    procedure PaintedLineMatchesText;
    [Test]
    procedure ClicksAndCommands;
  end;

implementation

uses
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CodeLinkPlan;

procedure TAtlasCodeLinkPlanTests.PascalFilesOnly;
begin
  Assert.IsTrue(TAtlasCodeLinkPlan.IsPascal('C:\Src\Main.PAS'));
  Assert.IsTrue(TAtlasCodeLinkPlan.IsPascal('Paket.dpk'));
  Assert.IsTrue(TAtlasCodeLinkPlan.IsPascal('Werte.inc'));
  Assert.IsFalse(TAtlasCodeLinkPlan.IsPascal('Main.dfm'));
  Assert.IsFalse(TAtlasCodeLinkPlan.IsPascal(''));
end;

procedure TAtlasCodeLinkPlanTests.StateChangesWithBufferOrPattern;
var
  mTarget: TAtlasTrackerTarget;
  mKey: string;
begin
  mTarget := Default(TAtlasTrackerTarget);
  mTarget.Provider := 'youtrack';
  mTarget.Url := 'https://yt';
  mTarget.Project := 'ATL';
  mKey := TAtlasCodeLinkPlan.PatternKey(mTarget, '{kennung} ');
  Assert.AreNotEqual(mKey, TAtlasCodeLinkPlan.PatternKey(mTarget, ''), 'Commit-Präfix gehört zum Muster');
  Assert.IsTrue(TAtlasCodeLinkPlan.Unchanged(7, 'c:\a.pas', mKey, 7, 'C:\A.pas', mKey));
  Assert.IsFalse(TAtlasCodeLinkPlan.Unchanged(8, 'C:\A.pas', mKey, 7, 'C:\A.pas', mKey), 'neuer Pufferstand');
  Assert.IsFalse(TAtlasCodeLinkPlan.Unchanged(7, 'C:\B.pas', mKey, 7, 'C:\A.pas', mKey), 'andere Datei');
  Assert.IsFalse(TAtlasCodeLinkPlan.Unchanged(7, 'C:\A.pas', 'x', 7, 'C:\A.pas', mKey), 'anderes Muster');
end;

procedure TAtlasCodeLinkPlanTests.PaintedLineMatchesText;
var
  mLines: TArray<string>;
begin
  mLines := TArray<string>.Create('unit A;', '// ATL-1  ', 'end.');
  Assert.AreEqual(1, TAtlasCodeLinkPlan.PaintedLine(2, '// ATL-1', mLines));
  Assert.AreEqual(0, TAtlasCodeLinkPlan.PaintedLine(1, 'unit A;   ', mLines));
  Assert.AreEqual(-1, TAtlasCodeLinkPlan.PaintedLine(2, '// ATL-2', mLines), 'Text weicht ab');
  Assert.AreEqual(-1, TAtlasCodeLinkPlan.PaintedLine(0, 'unit A;', mLines));
  Assert.AreEqual(-1, TAtlasCodeLinkPlan.PaintedLine(4, '', mLines));
end;

procedure TAtlasCodeLinkPlanTests.ClicksAndCommands;
begin
  Assert.IsTrue(TAtlasCodeLinkPlan.Catches(True, False, True, False), 'Strg+Klick');
  Assert.IsTrue(TAtlasCodeLinkPlan.Catches(True, False, True, True), 'Strg+Umschalt+Klick');
  Assert.IsFalse(TAtlasCodeLinkPlan.Catches(True, False, False, False), 'Klick ohne Strg');
  Assert.IsTrue(TAtlasCodeLinkPlan.Catches(False, True, False, False), 'Rechtsklick');
  Assert.IsFalse(TAtlasCodeLinkPlan.Catches(False, True, False, True), 'Umschalt+Rechtsklick');
  Assert.IsFalse(TAtlasCodeLinkPlan.Catches(False, False, True, False));
  Assert.AreEqual(Integer(TAtlasCodeLinkPlan.cMenuShow), TAtlasCodeLinkPlan.ClickCommand(False));
  Assert.AreEqual(Integer(TAtlasCodeLinkPlan.cMenuBrowse), TAtlasCodeLinkPlan.ClickCommand(True));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCodeLinkPlanTests);

end.
