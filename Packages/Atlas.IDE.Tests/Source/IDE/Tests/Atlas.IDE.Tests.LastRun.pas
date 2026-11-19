unit Atlas.IDE.Tests.LastRun;

// Letzten Testlauf für KI-Assistenten ablegen (#2409, tests.lastRun; MCP-Werkzeug get_last_tests):
// - Nach jedem gemeldeten Lauf (Haken OnReported des Läufers, nach den wackelnden Tests, damit deren Verlauf den
//   Lauf schon kennt) schreibt das Modul den Lauf je Testprojekt nach
//   %LOCALAPPDATA%\Atlas\last-tests\<Schlüssel>.json (Format Atlas.Text.TestRunFile, atomar ersetzt), auch nach
//   Teilläufen, Serien und Läufen beim Speichern. Den Lauf reicht es danach an ANext weiter.
// - Dazu gehören die Fundstellen der roten Tests (an der fehlgeschlagenen Anweisung mit tests.failureAtAssert,
//   #1771), die Dateien der Testunits (veraltete Ergebnisse erkennt der Server an späteren Änderungen), der
//   Auszug aus dem Protokoll je Test (tests.log, #2168) und die Zahlen der wackelnden Tests (#1773). Neu rot und
//   wieder grün kommen aus dem Vergleich mit der Datei davor.
// - Mit tests.lastRun aus wird nichts geschrieben; die zuletzt abgelegte Datei bleibt.
// Nur im Hauptthread.

interface

uses
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.LastRun,
  Atlas.IDE.Tests.Runner;

type
  /// <summary>Abfrage der wackelnden Tests des Testprojekts AProject; nil = keine.</summary>
  TAtlasTestFlakyFor = reference to function(const AProject: string): TAtlasTestFlakyCount;

  TAtlasIdeTestLastRun = class
  private const
    cKind = 'Letzter Testlauf';
  private
    FNext: TAtlasTestsReportedProc;
    FFlakyFor: TAtlasTestFlakyFor;
    procedure Save(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
  public
    /// <summary>ANext bekommt jeden Lauf danach (nil = keiner); AFlakyFor fragt die wackelnden Tests ab.</summary>
    constructor Create(const ANext: TAtlasTestsReportedProc; const AFlakyFor: TAtlasTestFlakyFor);
    destructor Destroy; override;
    /// <summary>Ordner der Ablage.</summary>
    class function Folder: string; static;
    /// <summary>Datei des Testprojekts AProject; Schlüssel wie die Projekt-Zusammenfassung.</summary>
    class function FileOf(const AProject: string): string; static;
    /// <summary>Lauf ablegen (Haken OnReported).</summary>
    procedure Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Text.TestRunFile,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tests.Log,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tests.Projects;

/// <summary>Zeilen einer Datei: offener Puffer, sonst die Platte.</summary>
function ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
begin
  Result := TAtlasIdeFiles.ReadLines(AFileName, ALines);
end;

/// <summary>Fundstellen der roten Tests in ARun.</summary>
function PlacesOf(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult): TArray<TAtlasTestPlace>;
var
  mFailure: TAtlasTestFailure;
begin
  Result := nil;
  for mFailure in TAtlasTestRun.Failures(ARun, TAtlasIdeTestProjects.UnitFiles(ATarget.Project), ReadLines,
    TAtlasIdeSettings.Current.TestsFailureAtAssert) do
  begin
    Result := Result + [TAtlasTestPlace.Make(mFailure.Test.FullName, mFailure.FileName, mFailure.Line)];
  end;
end;

/// <summary>Testunits des Laufs mit ihren Dateien im Testprojekt.</summary>
function UnitsOf(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult): TArray<TTestRunUnit>;
var
  mName: string;
  mUnit: TTestRunUnit;
begin
  Result := nil;
  for mName in TAtlasTestLastRun.UnitNames(ARun.Cases) do
  begin
    mUnit.Name := mName;
    mUnit.FileName := TAtlasIdeTestProjects.UnitFileOf(ATarget.Project, mName);
    Result := Result + [mUnit];
  end;
end;

{ TAtlasIdeTestLastRun }

constructor TAtlasIdeTestLastRun.Create(const ANext: TAtlasTestsReportedProc; const AFlakyFor: TAtlasTestFlakyFor);
begin
  inherited Create;
  FNext := ANext;
  FFlakyFor := AFlakyFor;
end;

destructor TAtlasIdeTestLastRun.Destroy;
begin
  FNext := nil;
  FFlakyFor := nil;
  inherited Destroy;
end;

class function TAtlasIdeTestLastRun.Folder: string;
begin
  Result := TTestRunFiles.Folder(TPath.Combine(TPath.GetCachePath, 'Atlas'));
end;

class function TAtlasIdeTestLastRun.FileOf(const AProject: string): string;
begin
  Result := TPath.Combine(Folder, TAtlasProjectSummaries.KeyOf(AProject) + '.json');
end;

procedure TAtlasIdeTestLastRun.Save(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
var
  mParts: TAtlasTestLastRunParts;
  mFileName, mPrevious: string;
begin
  mParts := Default(TAtlasTestLastRunParts);
  mParts.Project := ATarget.Project;
  mParts.Configuration := ATarget.Configuration;
  mParts.Platform := ATarget.Platform;
  mParts.Filter := ATarget.Tests;
  mParts.Run := ARun;
  mParts.Places := PlacesOf(ATarget, ARun);
  mParts.Units := UnitsOf(ATarget, ARun);
  if TAtlasIdeSettings.Current.TestsLog then
  begin
    mParts.Log := TAtlasTestLog.Parse(ARun.LogFile, ARun.Output, TAtlasIdeSettings.Current.TestsLogMaxLines);
  end;
  mParts.FinishedAtUtc := TTimeZone.Local.ToUniversalTime(Now);
  if Assigned(FFlakyFor) then
  begin
    mParts.Flaky := FFlakyFor(ATarget.Project);
  end;
  mFileName := FileOf(ATarget.Project);
  // Ohne lesbare Datei davor entfallen nur die Marken neu rot und wieder grün.
  if not TAtlasDataFile.TryRead(mFileName, mPrevious) then
  begin
    mPrevious := '';
  end;
  TAtlasDataFile.Write(mFileName, TTestRunFiles.ToJson(TAtlasTestLastRun.Build(mParts, mPrevious)));
end;

procedure TAtlasIdeTestLastRun.Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
begin
  if TAtlasIdeSettings.Current.TestsLastRun and (ATarget.Project <> '') then
  begin
    try
      Save(ATarget, ARun);
    except
      // Ohne Ablage liefert get_last_tests den Lauf davor; der Grund steht einmal im Protokoll.
      on E: Exception do
        TAtlasDataFile.ReportNotWritten(cKind, E);
    end;
  end;
  if Assigned(FNext) then
  begin
    FNext(ATarget, ARun);
  end;
end;

end.
