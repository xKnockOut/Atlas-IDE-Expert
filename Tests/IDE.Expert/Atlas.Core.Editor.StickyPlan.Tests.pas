unit Atlas.Core.Editor.StickyPlan.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStickyPlanTests = class
  public
    [Test]
    procedure KindsFollowSettings;
    [Test]
    procedure KindsEmptyWhenAllOff;
    [Test]
    procedure WordAtStopsAtNonLetter;
    [Test]
    procedure WordAtOutsideLineIsEmpty;
    [Test]
    procedure PairsPerLineGroupsAndDropsOutside;
    [Test]
    procedure BranchesOfKeepsWantedOwners;
    [Test]
    procedure LongBranchesCountsHeadAndEnd;
    [Test]
    procedure HasColumnFindsOnlyListed;
    [Test]
    procedure RowAtInsidePaintedHeader;
    [Test]
    procedure RowAtOutsideHeader;
    [Test]
    procedure ScreenRowUsesMiddleOfLine;
    [Test]
    procedure ScrolledOnlyAfterFirstPaint;
    [Test]
    procedure RefreshOrder;
    [Test]
    procedure ClickNeedsLeftButtonWithoutShiftAlt;
    [Test]
    procedure CtrlClickFreshForSameFileWithinWindow;
    [Test]
    procedure GuideXStaysInCodeArea;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Outline.StickyScroll,
  Atlas.Core.Editor.StickyPlan;

function PairToken(ALine, ACharacter: Integer): TAtlasPairToken;
begin
  Result := Default(TAtlasPairToken);
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

function PairBlock(AOwnerLine, AOwnerCharacter, ACloseLine: Integer): TAtlasPairBlock;
begin
  Result := Default(TAtlasPairBlock);
  Result.OwnerLine := AOwnerLine;
  Result.OwnerCharacter := AOwnerCharacter;
  Result.CloseLine := ACloseLine;
end;

{ TAtlasStickyPlanTests }

procedure TAtlasStickyPlanTests.KindsFollowSettings;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.StickyScrollTypes := True;
  mSettings.StickyScrollRoutines := False;
  mSettings.StickyScrollBlocks := True;
  mSettings.StickyScrollLoops := False;
  mSettings.StickyScrollTry := True;
  mSettings.StickyScrollCase := False;
  mSettings.StickyScrollWith := True;
  Assert.AreEqual<TAtlasStickyKinds>([TAtlasStickyKind.Types, TAtlasStickyKind.Branches,
    TAtlasStickyKind.TryBlocks, TAtlasStickyKind.WithBlocks], TAtlasStickyPlan.Kinds(mSettings));
end;

procedure TAtlasStickyPlanTests.KindsEmptyWhenAllOff;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.StickyScrollTypes := False;
  mSettings.StickyScrollRoutines := False;
  mSettings.StickyScrollBlocks := False;
  mSettings.StickyScrollLoops := False;
  mSettings.StickyScrollTry := False;
  mSettings.StickyScrollCase := False;
  mSettings.StickyScrollWith := False;
  Assert.AreEqual<TAtlasStickyKinds>([], TAtlasStickyPlan.Kinds(mSettings));
end;

procedure TAtlasStickyPlanTests.WordAtStopsAtNonLetter;
begin
  Assert.AreEqual('while', TAtlasStickyPlan.WordAt('  While(x) do', 2));
  Assert.AreEqual('do', TAtlasStickyPlan.WordAt('  While(x) do', 11));
end;

procedure TAtlasStickyPlanTests.WordAtOutsideLineIsEmpty;
begin
  Assert.AreEqual('', TAtlasStickyPlan.WordAt('if', 5));
  Assert.AreEqual('', TAtlasStickyPlan.WordAt('  (', 2));
end;

procedure TAtlasStickyPlanTests.PairsPerLineGroupsAndDropsOutside;
var
  mLines: TArray<TArray<TAtlasPairToken>>;
begin
  mLines := TAtlasStickyPlan.PairsPerLine(TArray<TAtlasPairToken>.Create(PairToken(0, 1), PairToken(2, 3),
    PairToken(0, 7), PairToken(5, 0), PairToken(-1, 0)), 3);
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.AreEqual(2, Integer(Length(mLines[0])));
  Assert.AreEqual(7, mLines[0][1].Character);
  Assert.AreEqual(0, Integer(Length(mLines[1])));
  Assert.AreEqual(1, Integer(Length(mLines[2])));
end;

procedure TAtlasStickyPlanTests.BranchesOfKeepsWantedOwners;
var
  mBlocks: TArray<TAtlasStickyBlock>;
begin
  // Zeile 0: if (Branches), Zeile 1: for (Loops), Zeile 2: begin (kein Besitzer), Besitzerzeile 9 fehlt.
  mBlocks := TAtlasStickyPlan.BranchesOf(TArray<TAtlasPairBlock>.Create(PairBlock(0, 2, 4), PairBlock(1, 4, 3),
    PairBlock(2, 0, 3), PairBlock(9, 0, 10)), TArray<string>.Create('  if A then', '    for I := 0 to 1 do',
    'begin'), [TAtlasStickyKind.Branches]);
  Assert.AreEqual(1, Integer(Length(mBlocks)));
  Assert.AreEqual(0, mBlocks[0].Line);
  Assert.AreEqual(2, mBlocks[0].Character);
  Assert.AreEqual(4, mBlocks[0].EndLine);
end;

procedure TAtlasStickyPlanTests.LongBranchesCountsHeadAndEnd;
var
  mBlocks: TArray<TAtlasStickyBlock>;
begin
  mBlocks := TAtlasStickyPlan.LongBranches(TArray<TAtlasStickyBlock>.Create(TAtlasStickyBlock.Create(10, 0, 12),
    TAtlasStickyBlock.Create(20, 0, 21)), 3);
  Assert.AreEqual(1, Integer(Length(mBlocks)));
  Assert.AreEqual(10, mBlocks[0].Line);
end;

procedure TAtlasStickyPlanTests.HasColumnFindsOnlyListed;
begin
  Assert.IsTrue(TAtlasStickyPlan.HasColumn(TArray<Integer>.Create(3, 7), 7));
  Assert.IsFalse(TAtlasStickyPlan.HasColumn(TArray<Integer>.Create(3, 7), 5));
  Assert.IsFalse(TAtlasStickyPlan.HasColumn(nil, 0));
end;

procedure TAtlasStickyPlanTests.RowAtInsidePaintedHeader;
var
  mRow: Integer;
begin
  Assert.IsTrue(TAtlasStickyPlan.RowAt(TAtlasStickyGrid.Create(3, 3, 16, 40), 40, 35, mRow));
  Assert.AreEqual(2, mRow);
end;

procedure TAtlasStickyPlanTests.RowAtOutsideHeader;
var
  mRow: Integer;
begin
  // Unter dem Kopf, links vom Codebereich (Rinne), oberhalb, ohne gezeichnete Zeilen, ohne Zeilenhöhe.
  Assert.IsFalse(TAtlasStickyPlan.RowAt(TAtlasStickyGrid.Create(3, 3, 16, 40), 40, 48, mRow));
  Assert.IsFalse(TAtlasStickyPlan.RowAt(TAtlasStickyGrid.Create(3, 3, 16, 40), 39, 5, mRow));
  Assert.IsFalse(TAtlasStickyPlan.RowAt(TAtlasStickyGrid.Create(3, 3, 16, 40), 40, -1, mRow));
  Assert.AreEqual(-1, mRow);
  Assert.IsFalse(TAtlasStickyPlan.RowAt(TAtlasStickyGrid.Create(0, 3, 16, 40), 40, 5, mRow));
  Assert.IsFalse(TAtlasStickyPlan.RowAt(TAtlasStickyGrid.Create(3, 3, 0, 40), 40, 5, mRow));
  // Gezeichnet waren drei, gerechnet sind nur noch zwei Köpfe.
  Assert.IsFalse(TAtlasStickyPlan.RowAt(TAtlasStickyGrid.Create(3, 2, 16, 40), 40, 35, mRow));
end;

procedure TAtlasStickyPlanTests.ScreenRowUsesMiddleOfLine;
begin
  Assert.AreEqual(0, TAtlasStickyPlan.ScreenRow(0, 16));
  Assert.AreEqual(2, TAtlasStickyPlan.ScreenRow(32, 16));
  // Teilweise gemalte Zeile beim Bildlauf: die Mitte entscheidet.
  Assert.AreEqual(1, TAtlasStickyPlan.ScreenRow(10, 16));
  Assert.AreEqual(-1, TAtlasStickyPlan.ScreenRow(10, 0));
end;

procedure TAtlasStickyPlanTests.ScrolledOnlyAfterFirstPaint;
begin
  Assert.IsFalse(TAtlasStickyPlan.Scrolled(-1, 5, 2, 2));
  Assert.IsFalse(TAtlasStickyPlan.Scrolled(5, 5, 2, 2));
  Assert.IsTrue(TAtlasStickyPlan.Scrolled(4, 5, 2, 0));
  Assert.IsTrue(TAtlasStickyPlan.Scrolled(4, 5, 0, 1));
  Assert.IsFalse(TAtlasStickyPlan.Scrolled(4, 5, 0, 0));
end;

procedure TAtlasStickyPlanTests.RefreshOrder;
begin
  Assert.AreEqual<TAtlasStickyRefresh>(TAtlasStickyRefresh.Keep,
    TAtlasStickyPlan.Refresh(False, True, True, True, True));
  Assert.AreEqual<TAtlasStickyRefresh>(TAtlasStickyRefresh.Clear,
    TAtlasStickyPlan.Refresh(True, False, True, True, True));
  Assert.AreEqual<TAtlasStickyRefresh>(TAtlasStickyRefresh.Reload,
    TAtlasStickyPlan.Refresh(False, False, True, True, True));
  Assert.AreEqual<TAtlasStickyRefresh>(TAtlasStickyRefresh.Repaint,
    TAtlasStickyPlan.Refresh(False, False, False, True, True));
  Assert.AreEqual<TAtlasStickyRefresh>(TAtlasStickyRefresh.Keep,
    TAtlasStickyPlan.Refresh(False, False, False, True, False));
  Assert.AreEqual<TAtlasStickyRefresh>(TAtlasStickyRefresh.Keep,
    TAtlasStickyPlan.Refresh(False, False, False, False, True));
end;

procedure TAtlasStickyPlanTests.ClickNeedsLeftButtonWithoutShiftAlt;
begin
  Assert.AreEqual<TAtlasStickyClick>(TAtlasStickyClick.Jump, TAtlasStickyPlan.Click(True, False, False, False));
  Assert.AreEqual<TAtlasStickyClick>(TAtlasStickyClick.Definition, TAtlasStickyPlan.Click(True, False, True, False));
  Assert.AreEqual<TAtlasStickyClick>(TAtlasStickyClick.Ignore, TAtlasStickyPlan.Click(False, False, False, False));
  Assert.AreEqual<TAtlasStickyClick>(TAtlasStickyClick.Ignore, TAtlasStickyPlan.Click(True, True, False, False));
  Assert.AreEqual<TAtlasStickyClick>(TAtlasStickyClick.Ignore, TAtlasStickyPlan.Click(True, True, True, False));
  Assert.AreEqual<TAtlasStickyClick>(TAtlasStickyClick.Ignore, TAtlasStickyPlan.Click(True, False, True, True));
end;

procedure TAtlasStickyPlanTests.CtrlClickFreshForSameFileWithinWindow;
begin
  Assert.IsTrue(TAtlasStickyPlan.CtrlClickFresh('C:\A.pas', 'c:\a.PAS', 1000, 2999));
  Assert.IsFalse(TAtlasStickyPlan.CtrlClickFresh('C:\A.pas', 'C:\A.pas', 1000, 3000));
  Assert.IsFalse(TAtlasStickyPlan.CtrlClickFresh('C:\A.pas', 'C:\B.pas', 1000, 1001));
  Assert.IsFalse(TAtlasStickyPlan.CtrlClickFresh('', '', 1000, 1001));
end;

procedure TAtlasStickyPlanTests.GuideXStaysInCodeArea;
begin
  // Zelle ab 100, 9 Pixel breit, Stift 1: drei Pixel davor.
  Assert.AreEqual(97, TAtlasStickyPlan.GuideX(100, 9, 1, 40, 500));
  // Mindestens zwei Pixel Abstand; breiter Stift rückt um die halbe Breite nach links.
  Assert.AreEqual(97, TAtlasStickyPlan.GuideX(100, 3, 3, 40, 500));
  // Nicht weiter links als kurz vor dem Codebereich.
  Assert.AreEqual(36, TAtlasStickyPlan.GuideX(38, 9, 1, 40, 500));
  // Ohne Codebereich keine Grenze.
  Assert.AreEqual(35, TAtlasStickyPlan.GuideX(38, 9, 1, 40, 40));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStickyPlanTests);

end.
