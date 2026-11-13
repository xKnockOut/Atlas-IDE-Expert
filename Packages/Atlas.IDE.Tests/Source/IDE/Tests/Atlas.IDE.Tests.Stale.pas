unit Atlas.IDE.Tests.Stale;

// Veraltete Testergebnisse in der IDE (#1770, tests.stale):
// - Nach jedem gemeldeten Lauf (Haken OnReported des Läufers) merkt sich das
//   Modul je Test den Stand des Rumpfs aus dem Text der Testunit (Puffer der
//   IDE, sonst Platte), mit tests.stale.units auch die Prüfsummen der Units,
//   die die Testunit verwendet und die das Testprojekt kennt
//   (Atlas.Core.Tests.Stale).
// - Die Code Lens fragt nach jedem Lesen ihrer Unit, welche Tests veraltet
//   sind (StaleIn).
// - „Veraltete Tests ausführen“ (Run) führt die Tests aus, deren Stand
//   abweicht; haben mehrere Testprojekte veraltete Tests, zuerst das aktive.

interface

uses
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Stale,
  Atlas.IDE.Tests.Runner;

type
  TAtlasIdeStaleTests = class
  private
    FTests: TAtlasIdeTests;
    FStamps: TAtlasTestStamps;
  public
    /// <summary>ATests gehört dem Aufrufer und lebt länger.</summary>
    constructor Create(ATests: TAtlasIdeTests);
    destructor Destroy; override;
    /// <summary>Stand der Tests des Laufs ARun merken (Haken OnReported); nichts mit tests.stale aus.</summary>
    procedure Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
    /// <summary>Schlüssel der Tests von AUnit (Text ALines) mit veraltetem Ergebnis; leer mit tests.stale aus.
    /// </summary>
    function StaleIn(const AUnit: TDUnitXUnit; const ALines: TArray<string>): TArray<string>;
    /// <summary>Befehl „Veraltete Tests ausführen“.</summary>
    procedure Run;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  ToolsAPI,
  Atlas.UI.Tests.Strings,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings;

/// <summary>Zeilen einer Datei: offener Puffer, sonst die Platte.</summary>
function ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
begin
  Result := TAtlasIdeFiles.ReadLines(AFileName, ALines);
end;

/// <summary>Datei einer Unit im Testprojekt AProjectFile.</summary>
function UnitFileFunc(const AProjectFile: string): TAtlasTestUnitFile;
var
  mProjectFile: string;
begin
  mProjectFile := AProjectFile;
  Result :=
    function(const AUnitName: string): string
    begin
      Result := TAtlasIdeTests.UnitFileOf(mProjectFile, AUnitName);
    end;
end;

{ TAtlasIdeStaleTests }

constructor TAtlasIdeStaleTests.Create(ATests: TAtlasIdeTests);
begin
  inherited Create;
  FTests := ATests;
  FStamps := TAtlasTestStamps.Create;
end;

destructor TAtlasIdeStaleTests.Destroy;
begin
  FStamps.Free;
  inherited Destroy;
end;

procedure TAtlasIdeStaleTests.Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
var
  mDone: TArray<string>;
  mItem: TTestCaseResult;
  mFileName: string;
  mLines: TArray<string>;
  mUnits: TArray<TAtlasUnitStamp>;
begin
  if not TAtlasIdeSettings.Current.TestsStale then
  begin
    Exit;
  end;
  // Jede Testunit des Laufs einmal, mit dem Text von jetzt.
  mDone := nil;
  for mItem in ARun.Cases do
  begin
    mFileName := '';
    if (mItem.UnitName <> '') and (IndexText(mItem.UnitName, mDone) < 0) then
    begin
      mDone := mDone + [mItem.UnitName];
      mFileName := TAtlasIdeTests.UnitFileOf(ATarget.Project, mItem.UnitName);
    end;
    if (mFileName = '') or not ReadLines(mFileName, mLines) then
    begin
      Continue;
    end;
    mUnits := nil;
    if TAtlasIdeSettings.Current.TestsStaleUnits then
    begin
      mUnits := TAtlasTestStamps.UnitStamps(mLines, UnitFileFunc(ATarget.Project), ReadLines);
    end;
    FStamps.Remember(ATarget.Project, mFileName, TDUnitXSource.Scan(mLines), mLines, ARun.Cases, mUnits);
  end;
end;

function TAtlasIdeStaleTests.StaleIn(const AUnit: TDUnitXUnit; const ALines: TArray<string>): TArray<string>;
begin
  Result := nil;
  if TAtlasIdeSettings.Current.TestsStale and (FStamps.Count > 0) then
  begin
    Result := FStamps.StaleIn(AUnit, ALines, TAtlasIdeSettings.Current.TestsStaleUnits, ReadLines);
  end;
end;

procedure TAtlasIdeStaleTests.Run;
var
  mRuns: TArray<TAtlasStaleRun>;
  mActive: IOTAProject;
  mIndex, mChosen: Integer;
begin
  if not TAtlasIdeSettings.Current.TestRun or not TAtlasIdeSettings.Current.TestsStale then
  begin
    Exit;
  end;
  mRuns := FStamps.StaleRuns(TAtlasIdeSettings.Current.TestsStaleUnits, ReadLines);
  if Length(mRuns) = 0 then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsNoStale));
    Exit;
  end;
  // Ein Lauf auf einmal: das aktive Testprojekt, sonst das erste mit veralteten Tests.
  mChosen := 0;
  mActive := GetActiveProject;
  for mIndex := 0 to High(mRuns) do
  begin
    if (mActive <> nil) and SameText(mRuns[mIndex].Project, mActive.FileName) then
    begin
      mChosen := mIndex;
      Break;
    end;
  end;
  FTests.RunTests(mRuns[mChosen].FileName, mRuns[mChosen].Names);
end;

end.
