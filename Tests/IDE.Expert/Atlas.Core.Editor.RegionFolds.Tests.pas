unit Atlas.Core.Editor.RegionFolds.Tests;

// Tests für Regionen beim Öffnen (editor.regionFolds): Werte der Einstellung,
// Regionen im Text und die Reihenfolge, in der die IDE-Seite sie zu- bzw.
// aufklappt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasRegionFoldsTests = class
  public
    [Test]
    procedure ModeFromSetting;
    [Test]
    procedure PascalFilesOnly;
    [Test]
    procedure FindsNestedRegions;
    [Test]
    procedure IgnoresUnmatchedAndSingleLineRegions;
    [Test]
    procedure DirectiveOnlyAtLineStart;
    [Test]
    procedure CollapseInnerFirst;
    [Test]
    procedure CollapseKeepsRegionsAroundCursor;
    [Test]
    procedure ExpandOuterFirst;
    [Test]
    procedure KeepAndOffDoNothing;
    [Test]
    procedure VisibleLineIsOutermostHeader;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin.Store,
  Atlas.Core.Editor.RegionFolds;

const
  // Zeilen 1–12: Außen (1–11) mit Innen A (3–5) und Innen B (6–10, darin Tief 7–9); Rest 11–12 frei.
  cNested = '{$REGION ''Außen''}'#13#10 + 'const A = 1;'#13#10 + '  {$REGION ''Innen A''}'#13#10 + '  B;'#13#10 +
    '  {$ENDREGION}'#13#10 + '  {$region ''Innen B''}'#13#10 + '    (*$REGION ''Tief''*)'#13#10 + '    C;'#13#10 +
    '    (*$ENDREGION*)'#13#10 + '  {$endregion}'#13#10 + '{$ENDREGION}'#13#10 + 'end.';

function Lines(const AValues: TArray<Integer>): string;
var
  mValue: Integer;
begin
  Result := '';
  for mValue in AValues do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + IntToStr(mValue);
  end;
end;

function Describe(const ARegions: TArray<TAtlasRegion>): string;
var
  mRegion: TAtlasRegion;
begin
  Result := '';
  for mRegion in ARegions do
  begin
    Result := Result + Format('%d-%d/%d ', [mRegion.StartLine, mRegion.EndLine, mRegion.Depth]);
  end;
  Result := Trim(Result);
end;

{ TAtlasRegionFoldsTests }

procedure TAtlasRegionFoldsTests.ModeFromSetting;
begin
  Assert.IsTrue(TAtlasRegionFolds.ModeOf('collapse') = TAtlasRegionFoldMode.Collapse);
  Assert.IsTrue(TAtlasRegionFolds.ModeOf('Expand') = TAtlasRegionFoldMode.Expand);
  Assert.IsTrue(TAtlasRegionFolds.ModeOf('off') = TAtlasRegionFoldMode.Off);
  Assert.IsTrue(TAtlasRegionFolds.ModeOf('keep') = TAtlasRegionFoldMode.Keep);
  Assert.IsTrue(TAtlasRegionFolds.ModeOf('irgendwie') = TAtlasRegionFoldMode.Keep, 'Unbekanntes wird zur Vorgabe');
  Assert.AreEqual('keep', AtlasRegionFoldModes[0], 'Vorgabe steht vorn');
end;

procedure TAtlasRegionFoldsTests.PascalFilesOnly;
begin
  Assert.IsTrue(TAtlasRegionFolds.IsPascal('C:\P\Unit1.pas'));
  Assert.IsTrue(TAtlasRegionFolds.IsPascal('C:\P\Projekt.DPR'));
  Assert.IsTrue(TAtlasRegionFolds.IsPascal('C:\P\Paket.dpk'));
  Assert.IsTrue(TAtlasRegionFolds.IsPascal('C:\P\Defs.inc'));
  Assert.IsFalse(TAtlasRegionFolds.IsPascal('C:\P\Unit1.dfm'));
  Assert.IsFalse(TAtlasRegionFolds.IsPascal('C:\P\Projekt.dproj'));
end;

procedure TAtlasRegionFoldsTests.FindsNestedRegions;
begin
  Assert.AreEqual('1-11/0 3-5/1 6-10/1 7-9/2', Describe(TAtlasRegionFolds.Find(cNested)));
end;

procedure TAtlasRegionFoldsTests.IgnoresUnmatchedAndSingleLineRegions;
const
  cText = '{$ENDREGION}'#10'{$REGION ''Eine Zeile''}{$ENDREGION}'#10'{$REGION ''Offen''}'#10'X;'#10 +
    '{$REGION ''Zu''}'#10'Y;'#10'{$ENDREGION}';
begin
  Assert.AreEqual('5-7/1', Describe(TAtlasRegionFolds.Find(cText)),
    'Schluss ohne Kopf, einzeilige und offene Regionen zählen nicht');
end;

procedure TAtlasRegionFoldsTests.DirectiveOnlyAtLineStart;
const
  cText = 'X; {$REGION ''Hinten''}'#10'Y;'#10'{$ENDREGION}'#10'{$REGIONS}'#10'Z;'#10'{$ENDREGION}'#10 +
    #9'{$REGION}'#10'W;'#10#9'{$ENDREGION}';
begin
  Assert.AreEqual('7-9/0', Describe(TAtlasRegionFolds.Find(cText)),
    'Kopf hinter Code und andere Direktiven zählen nicht, Tabulator davor schon');
end;

procedure TAtlasRegionFoldsTests.CollapseInnerFirst;
begin
  Assert.AreEqual('7,3,6,1', Lines(TAtlasRegionFolds.Order(TAtlasRegionFolds.Find(cNested),
    TAtlasRegionFoldMode.Collapse, 0)));
  Assert.AreEqual('7,3,6,1', Lines(TAtlasRegionFolds.Order(TAtlasRegionFolds.Find(cNested),
    TAtlasRegionFoldMode.Collapse, 12)), 'Marke außerhalb aller Regionen');
end;

procedure TAtlasRegionFoldsTests.CollapseKeepsRegionsAroundCursor;
var
  mRegions: TArray<TAtlasRegion>;
begin
  mRegions := TAtlasRegionFolds.Find(cNested);
  Assert.AreEqual('7,3', Lines(TAtlasRegionFolds.Order(mRegions, TAtlasRegionFoldMode.Collapse, 6)),
    'Marke auf dem Kopf von Innen B: Innen B und Außen bleiben offen');
  Assert.AreEqual('7,3,6', Lines(TAtlasRegionFolds.Order(mRegions, TAtlasRegionFoldMode.Collapse, 2)),
    'Marke direkt in Außen');
  Assert.AreEqual('3', Lines(TAtlasRegionFolds.Order(mRegions, TAtlasRegionFoldMode.Collapse, 8)),
    'Marke ganz innen');
end;

procedure TAtlasRegionFoldsTests.ExpandOuterFirst;
begin
  Assert.AreEqual('1,3,6,7', Lines(TAtlasRegionFolds.Order(TAtlasRegionFolds.Find(cNested),
    TAtlasRegionFoldMode.Expand, 8)), 'Aufklappen ohne Rücksicht auf die Marke');
end;

procedure TAtlasRegionFoldsTests.KeepAndOffDoNothing;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasRegionFolds.Order(TAtlasRegionFolds.Find(cNested),
    TAtlasRegionFoldMode.Keep, 0))));
  Assert.AreEqual(0, Integer(Length(TAtlasRegionFolds.Order(TAtlasRegionFolds.Find(cNested),
    TAtlasRegionFoldMode.Off, 0))));
  Assert.AreEqual(0, Integer(Length(TAtlasRegionFolds.Order(TAtlasRegionFolds.Find('unit U;'),
    TAtlasRegionFoldMode.Collapse, 0))), 'ohne Regionen');
end;

procedure TAtlasRegionFoldsTests.VisibleLineIsOutermostHeader;
var
  mRegions: TArray<TAtlasRegion>;
begin
  mRegions := TAtlasRegionFolds.Find(cNested);
  Assert.AreEqual(1, TAtlasRegionFolds.VisibleLine(mRegions, 8));
  Assert.AreEqual(1, TAtlasRegionFolds.VisibleLine(mRegions, 11), 'Schlusszeile gehört dazu');
  Assert.AreEqual(12, TAtlasRegionFolds.VisibleLine(mRegions, 12));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRegionFoldsTests);

end.
