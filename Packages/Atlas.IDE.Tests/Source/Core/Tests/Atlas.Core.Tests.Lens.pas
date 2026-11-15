unit Atlas.Core.Tests.Lens;

// Code Lens „Test ausführen“ (#69, #585) und Marke „getestet von“ (#1778),
// Teil ohne VCL und Open Tools API:
// - Marken einer Testunit: je Fixture, je Test (alle Fälle) und je Fall mit
//   eigener Zeile, mit Auswahl und den Tests, die ihr Lauf ergibt.
// - Beschriftung: Art der Marke, Stand einer Serie (#1782), Zahl der Fälle
//   (#1879), Grenze für „langsam“ (#1772) und Leck (#1774).
// - Farbe nach dem Stand: grün, rot, gelb (Teilstand, langsam, Leck,
//   wackelt), grau bei veraltetem Ergebnis (#1770).
// - Knopf unter der Maus.
// Zeilen sind 0-basiert.

interface

uses
  System.Types,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Text.DUnitX,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Debug;

type
  /// <summary>Eine Marke: Fixture, Test (alle Fälle) oder ein Fall.</summary>
  TAtlasTestLensMark = record
    /// <summary>Zeile der Marke.</summary>
    Line: Integer;
    Selection: TAtlasTestSelection;
    /// <summary>Tests, die ein Lauf der Marke ergibt; erst wenn alle bestanden sind, gilt sie als bestanden.
    /// </summary>
    Expected: TArray<TAtlasTestKey>;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Art der Marke für ihre Beschriftung: alle Tests einer Fixture, ein Fall oder ein Test.</summary>
  TAtlasTestLensKind = (Fixture, TestCase, Test);
  /// <summary>Knopf einer Marke: ausführen, „Debuggen“ (#585), „Vergleichen“ (#1779), „Tabelle“ (#1879).</summary>
  TAtlasTestLensButton = (Run, Debug, Compare, Table);
{$SCOPEDENUMS OFF}

  /// <summary>Gezeichnete Rechtecke der Knöpfe einer Marke (Koordinaten des Editors, leer ohne).</summary>
  TAtlasTestLensRects = array[TAtlasTestLensButton] of TRect;

  TAtlasTestLens = class
  public const
    /// <summary>Kleinste Schrift einer Marke.</summary>
    cMinFontSize = 6;
    /// <summary>Rand links und rechts vom Text einer Marke in Punkten.</summary>
    cPillPadding = 5;
  public
    /// <summary>Marken der Testunit AFound: je Fixture, je Test und je Fall mit eigener Zeile (nicht bei [Ignore]:
    /// DUnitX führt die Fälle dann als einen Test); nur Marken mit Zeile und Namen für --run.</summary>
    class function Marks(const AFound: TDUnitXUnit): TArray<TAtlasTestLensMark>; static;
    /// <summary>Art der Marke zu ASelection.</summary>
    class function KindOf(const ASelection: TAtlasTestSelection): TAtlasTestLensKind; static;
    /// <summary>Stand nach einer Serie: bestanden und rot gemischt gelb wie ein Teilstand; Unknown, solange sie
    /// läuft.</summary>
    class function SeriesStatus(const AMark: TAtlasTestSeriesMark): TAtlasTestStatus; static;
    /// <summary>Zahl der Fälle an der Marke einer Methode mit [TestCase]; 0 an Fixture, Fall oder Methode ohne
    /// Fälle.</summary>
    class function CaseCount(const ASelection: TAtlasTestSelection; const AExpected: TArray<TAtlasTestKey>): Integer;
      static;
    /// <summary>Grenze für „langsam“ (#1772): ASlowMs, fehlgeschlagen und veraltet ist nie langsam (0).</summary>
    class function SlowLimit(AStatus: TAtlasTestStatus; AStale: Boolean; ASlowMs: Integer): Integer; static;
    /// <summary>Leck zeigen (#1774)? Bei ALeaked Tests mit Leck, nicht an einer fehlgeschlagenen Marke.</summary>
    class function ShowsLeak(ALeaked: Integer; AStatus: TAtlasTestStatus): Boolean; static;
    /// <summary>Knopf „Vergleichen“ (#1779) nur an einer fehlgeschlagenen, nicht veralteten Marke.</summary>
    class function Comparable(AStatus: TAtlasTestStatus; AStale: Boolean): Boolean; static;
    /// <summary>Farbe der Marke: ADefault ohne Ergebnis, sonst grün, rot oder gelb (Teilstand); AWarn gelb (langsam,
    /// Leck, wackelt), AStale grau.</summary>
    class function Tone(const AColors: TAtlasColors; ADefault: TAtlasColor; AStatus: TAtlasTestStatus;
      AWarn, AStale: Boolean): TAtlasColor; static;
    /// <summary>Knopf unter APoint in ARects (in der Reihenfolge der Knöpfe); False ohne.</summary>
    class function Hit(const ARects: TAtlasTestLensRects; const APoint: TPoint;
      out AButton: TAtlasTestLensButton): Boolean; static;
    /// <summary>Schrift einer Marke: einen Punkt kleiner als ASize, nicht unter cMinFontSize.</summary>
    class function PillFontSize(ASize: Integer): Integer; static;
    /// <summary>Rechteck einer Marke ab ALeft in der Zeile ARow für Text der Breite AWidth und Höhe AHeight:
    /// cPillPadding Rand links und rechts, 1 oben und unten, senkrecht mittig.</summary>
    class function PillRect(const ARow: TRect; ALeft, AWidth, AHeight: Integer): TRect; static;
  end;

implementation

uses
  System.Math;

/// <summary>Marke an ALine anhängen, wenn es die Zeile gibt und die Auswahl Namen hat.</summary>
procedure AddMark(var AMarks: TArray<TAtlasTestLensMark>; const AFound: TDUnitXUnit;
  ALine, AFixture, ATest, ACase: Integer);
var
  mMark: TAtlasTestLensMark;
begin
  if ALine < 0 then
  begin
    Exit;
  end;
  mMark := Default(TAtlasTestLensMark);
  mMark.Line := ALine;
  mMark.Selection := TAtlasTestDebug.Selection(AFound, AFixture, ATest, ACase);
  mMark.Expected := TAtlasTestRun.Expected(AFound, AFixture, ATest, ACase);
  if Length(mMark.Selection.Names) > 0 then
  begin
    AMarks := AMarks + [mMark];
  end;
end;

/// <summary>Marke des Tests und seiner Fälle mit eigener Zeile.</summary>
procedure AddTest(var AMarks: TArray<TAtlasTestLensMark>; const AFound: TDUnitXUnit; AFixture, ATest: Integer);
var
  mTest: TDUnitXTest;
  mCase: Integer;
begin
  mTest := AFound.Fixtures[AFixture].Tests[ATest];
  AddMark(AMarks, AFound, AFound.MarkLine(AFixture, ATest), AFixture, ATest, -1);
  // Fälle mit eigener Zeile bekommen eigene Marken (mit [Ignore] führt DUnitX sie als einen Test).
  if mTest.Ignored then
  begin
    Exit;
  end;
  for mCase := 0 to High(mTest.CaseLines) do
  begin
    if AFound.CaseHasOwnLine(AFixture, ATest, mCase) then
    begin
      AddMark(AMarks, AFound, mTest.CaseLines[mCase], AFixture, ATest, mCase);
    end;
  end;
end;

{ TAtlasTestLens }

class function TAtlasTestLens.Marks(const AFound: TDUnitXUnit): TArray<TAtlasTestLensMark>;
var
  mFixture, mTest: Integer;
begin
  Result := nil;
  for mFixture := 0 to High(AFound.Fixtures) do
  begin
    AddMark(Result, AFound, AFound.MarkLine(mFixture, -1), mFixture, -1, -1);
    for mTest := 0 to High(AFound.Fixtures[mFixture].Tests) do
    begin
      AddTest(Result, AFound, mFixture, mTest);
    end;
  end;
end;

class function TAtlasTestLens.KindOf(const ASelection: TAtlasTestSelection): TAtlasTestLensKind;
begin
  if ASelection.Method = '' then
  begin
    Result := TAtlasTestLensKind.Fixture;
  end
  else if ASelection.CaseName <> '' then
  begin
    Result := TAtlasTestLensKind.TestCase;
  end
  else
  begin
    Result := TAtlasTestLensKind.Test;
  end;
end;

class function TAtlasTestLens.SeriesStatus(const AMark: TAtlasTestSeriesMark): TAtlasTestStatus;
begin
  if AMark.Running then
  begin
    Result := TAtlasTestStatus.Unknown;
  end
  else if AMark.AnyPassed and AMark.AnyFailed then
  begin
    Result := TAtlasTestStatus.Partial;
  end
  else if AMark.AnyFailed then
  begin
    Result := TAtlasTestStatus.Failed;
  end
  else
  begin
    Result := TAtlasTestStatus.Passed;
  end;
end;

class function TAtlasTestLens.CaseCount(const ASelection: TAtlasTestSelection;
  const AExpected: TArray<TAtlasTestKey>): Integer;
var
  mKey: TAtlasTestKey;
begin
  Result := 0;
  if (ASelection.Method = '') or (ASelection.CaseName <> '') then
  begin
    Exit;
  end;
  for mKey in AExpected do
  begin
    if mKey.CaseName <> '' then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasTestLens.SlowLimit(AStatus: TAtlasTestStatus; AStale: Boolean; ASlowMs: Integer): Integer;
begin
  Result := ASlowMs;
  if (AStatus = TAtlasTestStatus.Failed) or AStale then
  begin
    Result := 0;
  end;
end;

class function TAtlasTestLens.ShowsLeak(ALeaked: Integer; AStatus: TAtlasTestStatus): Boolean;
begin
  Result := (ALeaked > 0) and (AStatus <> TAtlasTestStatus.Failed);
end;

class function TAtlasTestLens.Comparable(AStatus: TAtlasTestStatus; AStale: Boolean): Boolean;
begin
  Result := (AStatus = TAtlasTestStatus.Failed) and not AStale;
end;

class function TAtlasTestLens.Tone(const AColors: TAtlasColors; ADefault: TAtlasColor; AStatus: TAtlasTestStatus;
  AWarn, AStale: Boolean): TAtlasColor;
begin
  Result := ADefault;
  if AStatus = TAtlasTestStatus.Failed then
  begin
    Result := AColors.Error;
  end
  else if AStatus = TAtlasTestStatus.Passed then
  begin
    Result := AColors.Add;
  end
  else if AStatus = TAtlasTestStatus.Partial then
  begin
    // Erst ein Teil der Tests lief (#1762): gelb, nicht grün.
    Result := AColors.Warn;
  end;
  if AWarn then
  begin
    Result := AColors.Warn;
  end;
  // Veraltet (#1770): alter Stand grau.
  if AStale then
  begin
    Result := AColors.Muted;
  end;
end;

class function TAtlasTestLens.Hit(const ARects: TAtlasTestLensRects; const APoint: TPoint;
  out AButton: TAtlasTestLensButton): Boolean;
var
  mButton: TAtlasTestLensButton;
begin
  AButton := TAtlasTestLensButton.Run;
  for mButton := Low(TAtlasTestLensButton) to High(TAtlasTestLensButton) do
  begin
    if not ARects[mButton].IsEmpty and ARects[mButton].Contains(APoint) then
    begin
      AButton := mButton;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasTestLens.PillFontSize(ASize: Integer): Integer;
begin
  Result := Max(cMinFontSize, ASize - 1);
end;

class function TAtlasTestLens.PillRect(const ARow: TRect; ALeft, AWidth, AHeight: Integer): TRect;
var
  mTop: Integer;
begin
  mTop := ARow.Top + Max(0, (ARow.Bottom - ARow.Top - AHeight - 2) div 2);
  Result := TRect.Create(ALeft, mTop, ALeft + AWidth + 2 * cPillPadding, mTop + AHeight + 2);
end;

end.
