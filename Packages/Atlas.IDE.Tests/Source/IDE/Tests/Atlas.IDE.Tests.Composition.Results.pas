unit Atlas.IDE.Tests.Composition.Results;

// Auswertungen nach einem Testlauf, aus Atlas.IDE.Tests.Composition gelöst. Jeder Lauf geht durch eine Kette:
// langsamste Tests (#1772) → Erwartet und erhalten (#1779) → letzter Testlauf für KI-Assistenten (#2409) →
// Stände der veralteten Ergebnisse (#1770). Dazu die Befehle „Veraltete Tests ausführen“, „Erwartet und erhalten
// vergleichen“, „Langsamste Tests zeigen“ und „Liegengebliebene .received-Dateien löschen“ (#1881) sowie die
// Werte für „Vergleichen“ im Befund-Hover und an der Testmarke.

interface

uses
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Debug,
  Atlas.IDE.Tests.Runner;

/// <summary>Kette der Auswertungen für ATests anlegen (ATests lebt länger); nach den wackelnden Tests, deren
/// Verlauf der letzte Testlauf abfragt.</summary>
procedure StartResults(ATests: TAtlasIdeTests);
/// <summary>Kette freigeben; nach Fenster und Lens, die sie abfragen, vor dem Läufer.</summary>
procedure StopResults;
/// <summary>Erstes Glied der Kette: nimmt jeden gemeldeten Lauf.</summary>
function ResultsReported: TAtlasTestsReportedProc;
/// <summary>Veraltete Tests einer Unit (#1770).</summary>
function StaleKeys: TAtlasTestStaleKeys;
/// <summary>„Vergleichen“ an der Testmarke (#1779, #1881); ohne Serie.</summary>
function ResultCompareHooks: TAtlasTestCompareHooks;
function StaleTestsVisible: Boolean;
procedure RunStale;
function CompareVisible: Boolean;
procedure CompareValues;
function SlowestVisible: Boolean;
procedure ShowSlowest;
function ApprovalFilesVisible: Boolean;
procedure CleanApprovalFiles;
/// <summary>Werte eines Fehlschlags in Zeile ALine der Testunit im Editor.</summary>
function ResultHasValuesAt(ALine: Integer): Boolean;
procedure CompareResultAt(ALine: Integer);
/// <summary>Werte eines Fehlschlags des Tests AFullName.</summary>
function ResultHasValues(const AFullName: string): Boolean;
procedure CompareResult(const AFullName: string);

implementation

uses
  System.SysUtils,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tests.Stale,
  Atlas.IDE.Tests.Compare,
  Atlas.IDE.Tests.LastRun,
  Atlas.IDE.Tests.Slowest,
  Atlas.IDE.Tests.Composition.Explorer;

var
  GStale: TAtlasIdeStaleTests;
  GCompare: TAtlasIdeTestCompare;
  GLastRun: TAtlasIdeTestLastRun;
  GSlowest: TAtlasIdeTestSlowest;

procedure StartResults(ATests: TAtlasIdeTests);
begin
  // Veraltete Ergebnisse (#1770): Stand je Test nach jedem Lauf.
  GStale := TAtlasIdeStaleTests.Create(ATests);
  // Letzter Testlauf für KI-Assistenten (#2409): fragt den Verlauf der wackelnden Tests (#1773) ab; reicht den
  // Lauf an die Stände weiter.
  GLastRun := TAtlasIdeTestLastRun.Create(GStale.Remember, FlakyCountFor);
  // Erwartet und erhalten vergleichen (#1779): Fehlschläge mit Werten; reicht den Lauf an den letzten Testlauf weiter.
  GCompare := TAtlasIdeTestCompare.Create(ATests, GLastRun.Remember);
  // Langsamste Tests (#1772): Ergebnisse des Testprojekts; reicht den Lauf an den Vergleich weiter.
  GSlowest := TAtlasIdeTestSlowest.Create(ATests, GCompare.Remember);
end;

procedure StopResults;
begin
  FreeAndNil(GSlowest);
  FreeAndNil(GCompare);
  FreeAndNil(GLastRun);
  FreeAndNil(GStale);
end;

function ResultsReported: TAtlasTestsReportedProc;
begin
  Result := GSlowest.Remember;
end;

function StaleKeys: TAtlasTestStaleKeys;
begin
  Result := GStale.StaleIn;
end;

function ResultCompareHooks: TAtlasTestCompareHooks;
begin
  Result := Default(TAtlasTestCompareHooks);
  Result.CanCompare := GCompare.CanCompare;
  Result.Show := GCompare.Show;
  // Vergleichsdateien (#1881): „Abweichung · Vergleich“ statt „Vergleichen“.
  Result.Caption := GCompare.CaptionOf;
end;

/// <summary>Läufer gestartet (die Kette lebt mit ihm) und Einstellung tests.run an.</summary>
function ResultsVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestRun and (GStale <> nil);
end;

function StaleTestsVisible: Boolean;
begin
  Result := ResultsVisible and TAtlasIdeSettings.Current.TestsStale;
end;

procedure RunStale;
begin
  if GStale <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GStale.Run);
  end;
end;

function CompareVisible: Boolean;
begin
  Result := ResultsVisible and TAtlasIdeSettings.Current.TestsCompare;
end;

procedure CompareValues;
begin
  if GCompare <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GCompare.Run);
  end;
end;

function SlowestVisible: Boolean;
begin
  Result := ResultsVisible and TAtlasIdeSettings.Current.TestsShowDuration;
end;

procedure ShowSlowest;
begin
  if GSlowest <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GSlowest.Run);
  end;
end;

function ApprovalFilesVisible: Boolean;
begin
  Result := ResultsVisible and TAtlasIdeSettings.Current.TestsApprovalFiles;
end;

procedure CleanApprovalFiles;
begin
  if GCompare <> nil then
  begin
    GCompare.CleanApprovalFiles;
  end;
end;

function ResultHasValuesAt(ALine: Integer): Boolean;
begin
  Result := (GCompare <> nil) and GCompare.HasValuesAt(ALine);
end;

procedure CompareResultAt(ALine: Integer);
begin
  if GCompare <> nil then
  begin
    GCompare.CompareAt(ALine);
  end;
end;

function ResultHasValues(const AFullName: string): Boolean;
begin
  Result := (GCompare <> nil) and GCompare.HasValues(AFullName);
end;

procedure CompareResult(const AFullName: string);
begin
  if GCompare <> nil then
  begin
    GCompare.CompareTest(AFullName);
  end;
end;

end.
