unit Atlas.IDE.Tests.Slowest;

// Befehl „Langsamste Tests zeigen“ (#1772, tests.showDuration):
// - Nach jedem gemeldeten Lauf (Haken OnReported des Läufers) merkt sich das
//   Modul die Ergebnisse des Testprojekts dieser Sitzung; ein neuer Lauf
//   ersetzt die Tests gleichen Namens, ein anderes Testprojekt beginnt neu.
//   Den Lauf reicht es danach an ANext weiter.
// - Der Befehl zeigt das Fenster Atlas.UI.Tests.Slowest mit allen Tests mit
//   Dauer, der langsamste zuerst; die gewählte Zeile öffnet den Methodenkopf
//   des Tests im Editor.
// - Ohne Ergebnisse mit Dauer eine Zeile in der Meldungsansicht.

interface

uses
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Run,
  Atlas.IDE.Tests.Runner;

type
  TAtlasIdeTestSlowest = class
  private
    FTests: TAtlasIdeTests;
    FNext: TAtlasTestsReportedProc;
    /// <summary>Testprojekt der gemerkten Ergebnisse; '' ohne.</summary>
    FProject: string;
    FCases: TArray<TTestCaseResult>;
    /// <summary>Methodenkopf des Tests AFullName öffnen; sonst eine Meldung.</summary>
    procedure Open(const AFullName: string);
  public
    /// <summary>ATests gehört dem Aufrufer und lebt länger; ANext bekommt jeden Lauf danach (nil = keiner).
    /// </summary>
    constructor Create(ATests: TAtlasIdeTests; const ANext: TAtlasTestsReportedProc);
    destructor Destroy; override;
    /// <summary>Ergebnisse aus ARun merken (Haken OnReported).</summary>
    procedure Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
    /// <summary>Befehl „Langsamste Tests zeigen“.</summary>
    procedure Run;
    property Cases: TArray<TTestCaseResult> read FCases;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Tests.Durations,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Tests.Debug,
  Atlas.UI.Tests.Slowest,
  Atlas.UI.Tests.Strings;

{ TAtlasIdeTestSlowest }

constructor TAtlasIdeTestSlowest.Create(ATests: TAtlasIdeTests; const ANext: TAtlasTestsReportedProc);
begin
  inherited Create;
  FTests := ATests;
  FNext := ANext;
end;

destructor TAtlasIdeTestSlowest.Destroy;
begin
  FNext := nil;
  FCases := nil;
  inherited;
end;

procedure TAtlasIdeTestSlowest.Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
begin
  if not SameText(ATarget.Project, FProject) then
  begin
    FCases := nil;
  end;
  FProject := ATarget.Project;
  FCases := TAtlasTestRun.Merged(FCases, ARun.Cases);
  if Assigned(FNext) then
  begin
    FNext(ATarget, ARun);
  end;
end;

procedure TAtlasIdeTestSlowest.Open(const AFullName: string);
var
  mFileName: string;
  mLine: Integer;
begin
  if not TAtlasIdeTestDebugger.LocateByName(FProject, AFullName, mFileName, mLine) then
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsSlowestNotFound, [AFullName]));
    Exit;
  end;
  // LocateByName zählt ab 1, der Editor ab 0.
  TAtlasIdeResults.Open(mFileName, Max(mLine - 1, 0), 0);
end;

procedure TAtlasIdeTestSlowest.Run;
var
  mRows: TArray<TAtlasTestSlowRow>;
  mSlowMs, mChosen: Integer;
begin
  if not TAtlasIdeSettings.Current.TestsShowDuration then
  begin
    Exit;
  end;
  mSlowMs := TAtlasIdeSettings.Current.TestsSlowMs;
  mRows := TAtlasTestDurations.Rows(FCases, mSlowMs, FormatSettings.DecimalSeparator);
  if Length(mRows) = 0 then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsSlowestNone));
    Exit;
  end;
  mChosen := TAtlasTestsSlowestDialog.Execute(mRows, mSlowMs);
  if (mChosen >= 0) and (mChosen <= High(mRows)) then
  begin
    Open(mRows[mChosen].Test);
  end;
end;

end.
