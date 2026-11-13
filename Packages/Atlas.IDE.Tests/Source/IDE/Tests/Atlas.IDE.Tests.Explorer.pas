unit Atlas.IDE.Tests.Explorer;

// Fenster „Atlas-Tests“ (#1776, tests.window) in der IDE:
// - Testprojekte der Projektgruppe (Hauptdatei mit DUnitX.TestFramework); bei
//   mehreren wählt der Benutzer oben, vorgewählt ist das aktive Testprojekt.
// - Testunits: die .pas-Dateien des Testprojekts, die DUnitX verwenden, mit
//   Atlas.Text.DUnitX gelesen (Puffer der IDE, sonst Platte; ohne Server).
//   Gelesen wird beim Öffnen, nach jedem Lauf, nach dem Speichern einer
//   Unit des Testprojekts und mit „Neu einlesen“; ungeänderte Dateien kommen
//   aus dem Zwischenspeicher (Änderungszeit).
// - Ergebnisse: Nach jedem gemeldeten Lauf (Haken OnReported des Läufers)
//   merkt sich das Fenster die Ergebnisse je Testprojekt dieser Sitzung und
//   reicht den Lauf an ANext weiter; veraltete (#1770) und wackelnde Tests
//   (#1773) über AQueries. Die Einzelheiten eines wackelnden Tests zeigen
//   seinen Verlauf; „Wackelnde Tests zeigen“ öffnet das Fenster mit genau dem
//   Filter „wackelt“ (Show mit AFlakyOnly).
//   Der Teststand in der Statusleiste (#1777) liest die Ergebnisse über
//   StatusInput.
// - Baum, Filter, Suche und Auswahl: Atlas.Core.Tests.Explorer; Darstellung:
//   Atlas.UI.Tests.ExplorerFrame im Dockfenster Atlas.IDE.Tests.ExplorerWindow.
// - Ausführen über den Läufer (#69): „Alle ausführen“ baut das Testprojekt
//   und startet alle Tests, „Ausgewählte ausführen“ genau die gewählten
//   (--run mit ihren Namen), „Ausgewählte debuggen“ startet sie im Debugger
//   (#585; Haltepunkt am Anfang nur bei einem einzelnen Test).
// - Protokoll je Test (#2168, tests.log): Atlas.IDE.Tests.ExplorerLog merkt
//   sich das Protokoll der Läufe; der Reiter „Protokoll (n)“ zeigt es zum
//   gewählten Test, Fall bzw. zur Fixture.
// - Ein Zeitgeber folgt dem Läufer (Lauf beginnt bzw. endet), solange das
//   Fenster zu sehen ist; er lebt nur so lange wie dieses Objekt.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  Atlas.Text.DUnitX,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Explorer,
  Atlas.Core.Tests.StatusField,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Debug,
  Atlas.IDE.Tests.ExplorerLog,
  Atlas.UI.Tests.ExplorerFrame;

type
  TAtlasIdeTestExplorer = class
  private type
    /// <summary>Gelesene Unit des Testprojekts: Änderungszeit, Text (nur Testunits) und Fixtures.</summary>
    TScanned = record
      Age: TDateTime;
      IsTest: Boolean;
      Lines: TArray<string>;
      Found: TDUnitXUnit;
    end;
    /// <summary>Ergebnisse eines Testprojekts dieser Sitzung und Ende und Dauer des letzten Laufs.</summary>
    TProjectRun = record
      Cases: TArray<TTestCaseResult>;
      At: TDateTime;
      DurationMs: Int64;
    end;
  private const
    cTickMs = 500;
  private
    FTests: TAtlasIdeTests;
    FDebugger: TAtlasIdeTestDebugger;
    FQueries: TAtlasTestStateQueries;
    FNext: TAtlasTestsReportedProc;
    FTimer: TTimer;
    /// <summary>Ergebnisse je Testprojekt (Schlüssel klein) dieser Sitzung.</summary>
    FResults: TDictionary<string, TProjectRun>;
    /// <summary>Protokoll je Test (#2168) je Testprojekt dieser Sitzung.</summary>
    FLogs: TAtlasIdeTestLogs;
    /// <summary>Gelesene Units je Datei (Schlüssel klein).</summary>
    FScanned: TDictionary<string, TScanned>;
    /// <summary>Gewähltes Testprojekt (.dproj); '' = noch keins.</summary>
    FProject: string;
    FProjects: TArray<string>;
    FUnits: TArray<TAtlasTestUnitInput>;
    FRefs: TArray<TAtlasTestUnitRef>;
    FNodes: TArray<TAtlasTestNode>;
    FDirty: Boolean;
    FBusy: Boolean;
    FVersion: Integer;
    procedure Tick(Sender: TObject);
    procedure Wire(AFrame: TAtlasTestsExplorerFrame);
    /// <summary>Testprojekte und Testunits neu lesen, Baum neu bauen und zeigen.</summary>
    procedure Reload;
    procedure ReadProjects;
    procedure ReadUnits;
    function ScanFile(const AFileName: string): TScanned;
    /// <summary>Baum mit den aktuellen Filtern zeigen.</summary>
    procedure ShowRows;
    function StatusText: string;
    procedure ChooseProject(AIndex: Integer);
    procedure Selected(ANode: Integer);
    procedure OpenNode(ANode: Integer);
    procedure RunAll;
    procedure RunSelected;
    procedure DebugSelected;
    /// <summary>Gewählte Knoten; ohne Auswahl eine Meldung und leer.</summary>
    function Chosen: TArray<Integer>;
  public
    /// <summary>ATests und ADebugger gehören dem Aufrufer und leben länger; AQueries nennt veraltete (#1770) und
    /// wackelnde Tests (#1773, je nil = keine); ANext bekommt jeden Lauf danach (nil = keiner).</summary>
    constructor Create(ATests: TAtlasIdeTests; ADebugger: TAtlasIdeTestDebugger;
      const AQueries: TAtlasTestStateQueries; const ANext: TAtlasTestsReportedProc);
    destructor Destroy; override;
    /// <summary>Fenster „Atlas-Tests“ gewünscht (tests.run und tests.window)?</summary>
    class function Wanted: Boolean; static;
    /// <summary>Ergebnisse aus ARun merken (Haken OnReported).</summary>
    procedure Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
    /// <summary>Eine Datei wurde gespeichert: gehört sie zum Testprojekt, neu lesen.</summary>
    procedure FileSaved(const AFileName: string);
    /// <summary>Befehl „Atlas-Tests“: Fenster zeigen und füllen; mit AFlakyOnly („Wackelnde Tests zeigen“, #1773)
    /// mit genau dem Filter „wackelt“.</summary>
    procedure Show(AFlakyOnly: Boolean);
    /// <summary>tests.window aus: Fenster verstecken.</summary>
    procedure ApplySettings;
    class procedure ThemeChanged; static;
    /// <summary>Stand für den Teststand in der Statusleiste (#1777): Ergebnisse, letzter Lauf und, wenn das
    /// Fenster gerade dieses Testprojekt zeigt, die Zahl der veralteten Tests (sonst -1). Project bleibt leer;
    /// der Aufrufer setzt den Namen.</summary>
    function StatusInput(const AProject: string): TAtlasTestStatusInput;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  System.DateUtils,
  System.StrUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Tests.Debug,
  Atlas.Core.Tests.Flaky,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Tests.Projects,
  Atlas.IDE.Tests.ExplorerWindow,
  Atlas.UI.Tests.Strings;

function KeyOf(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

function ProjectName(const AFileName: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AFileName), '');
end;

/// <summary>AFileName an ALine (0-basiert) im Editor öffnen.</summary>
procedure OpenLine(const AFileName: string; ALine: Integer);
begin
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      TAtlasIdeResults.Open(AFileName, ALine, 0);
    end);
end;

{ TAtlasIdeTestExplorer }

constructor TAtlasIdeTestExplorer.Create(ATests: TAtlasIdeTests; ADebugger: TAtlasIdeTestDebugger;
  const AQueries: TAtlasTestStateQueries; const ANext: TAtlasTestsReportedProc);
begin
  inherited Create;
  FTests := ATests;
  FDebugger := ADebugger;
  FQueries := AQueries;
  FNext := ANext;
  FResults := TDictionary<string, TProjectRun>.Create;
  FScanned := TDictionary<string, TScanned>.Create;
  FLogs := TAtlasIdeTestLogs.Create;
  FDirty := True;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  if Wanted then
  begin
    // Früh anmelden: Der Desktop stellt das Fenster nur wieder her, wenn die IDE die Kennung kennt.
    TAtlasIdeTestsExplorerWindow.Prepare;
  end;
  TAtlasIdeTestsExplorerWindow.OnFrame := Wire;
  if TAtlasIdeTestsExplorerWindow.ExistingFrame <> nil then
  begin
    Wire(TAtlasIdeTestsExplorerWindow.ExistingFrame);
  end;
end;

destructor TAtlasIdeTestExplorer.Destroy;
begin
  // Erst der Zeitgeber, dann das Fenster: Danach erreicht nichts mehr dieses Objekt.
  FreeAndNil(FTimer);
  TAtlasIdeTestsExplorerWindow.OnFrame := nil;
  if TAtlasIdeTestsExplorerWindow.ExistingFrame <> nil then
  begin
    TAtlasIdeTestsExplorerWindow.ExistingFrame.SetHandlers(Default(TAtlasTestsExplorerHandlers));
  end;
  TAtlasIdeTestsExplorerWindow.Release;
  FResults.Free;
  FScanned.Free;
  FLogs.Free;
  FQueries := Default(TAtlasTestStateQueries);
  FNext := nil;
  inherited;
end;

class function TAtlasIdeTestExplorer.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestRun and TAtlasIdeSettings.Current.TestsWindow;
end;

procedure TAtlasIdeTestExplorer.Wire(AFrame: TAtlasTestsExplorerFrame);
var
  mHandlers: TAtlasTestsExplorerHandlers;
begin
  mHandlers := Default(TAtlasTestsExplorerHandlers);
  mHandlers.OnRunAll := RunAll;
  mHandlers.OnRunSelected := RunSelected;
  mHandlers.OnDebugSelected := DebugSelected;
  mHandlers.OnRefresh :=
    procedure
    begin
      FScanned.Clear;
      Reload;
    end;
  mHandlers.OnFilter := ShowRows;
  mHandlers.OnProject := ChooseProject;
  mHandlers.OnOpenNode := OpenNode;
  mHandlers.OnSelect := Selected;
  // TProc<string, Integer> nimmt keine Methode mit const-Parameter (E2010).
  mHandlers.OnOpenLine :=
    procedure(AFileName: string; ALine: Integer)
    begin
      OpenLine(AFileName, ALine);
    end;
  AFrame.SetHandlers(mHandlers);
  FTimer.Enabled := True;
  Reload;
end;

procedure TAtlasIdeTestExplorer.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    var
      mFrame: TAtlasTestsExplorerFrame;
    begin
      mFrame := TAtlasIdeTestsExplorerWindow.ExistingFrame;
      if mFrame = nil then
      begin
        FTimer.Enabled := False;
        Exit;
      end;
      if not TAtlasIdeTestsExplorerWindow.Visible then
      begin
        Exit;
      end;
      if FDirty then
      begin
        Reload;
      end
      else if (FBusy <> FTests.Busy) or (FVersion <> FTests.Version) then
      begin
        FBusy := FTests.Busy;
        FVersion := FTests.Version;
        mFrame.SetBusy(FBusy);
        mFrame.SetStatus(StatusText);
      end;
    end);
end;

procedure TAtlasIdeTestExplorer.Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
var
  mKey: string;
  mRun: TProjectRun;
begin
  mKey := KeyOf(ATarget.Project);
  if not FResults.TryGetValue(mKey, mRun) then
  begin
    mRun := Default(TProjectRun);
  end;
  mRun.Cases := TAtlasTestRun.Merged(mRun.Cases, ARun.Cases);
  mRun.At := Now;
  mRun.DurationMs := ARun.DurationMs;
  FResults.AddOrSetValue(mKey, mRun);
  FLogs.Remember(ATarget.Project, ARun);
  // Der Lauf kann Testunits geändert haben (Vergleichsdateien, Fälle aus der Tabelle): beim nächsten Takt neu.
  FDirty := True;
  if Assigned(FNext) then
  begin
    FNext(ATarget, ARun);
  end;
end;

procedure TAtlasIdeTestExplorer.FileSaved(const AFileName: string);
begin
  if FScanned.ContainsKey(KeyOf(AFileName)) then
  begin
    FScanned.Remove(KeyOf(AFileName));
    FDirty := True;
  end;
end;

procedure TAtlasIdeTestExplorer.Show(AFlakyOnly: Boolean);
var
  mFrame: TAtlasTestsExplorerFrame;
begin
  if not Wanted then
  begin
    Exit;
  end;
  TAtlasIdeTestsExplorerWindow.Prepare;
  mFrame := TAtlasIdeTestsExplorerWindow.Show;
  if mFrame <> nil then
  begin
    FTimer.Enabled := True;
    Reload;
    if AFlakyOnly then
    begin
      mFrame.Bar.SetFilters([TAtlasTestFilter.Flaky]);
    end;
  end;
end;

procedure TAtlasIdeTestExplorer.ApplySettings;
begin
  if not Wanted then
  begin
    TAtlasIdeTestsExplorerWindow.Hide;
    FTimer.Enabled := False;
  end;
end;

class procedure TAtlasIdeTestExplorer.ThemeChanged;
begin
  TAtlasIdeTestsExplorerWindow.ApplyTheme;
end;

procedure TAtlasIdeTestExplorer.ReadProjects;
var
  mProject: IOTAProject;
  mActive: IOTAProject;
  mFound: Boolean;
begin
  FProjects := nil;
  for mProject in TAtlasIdeTestProjects.TestProjects('') do
  begin
    FProjects := FProjects + [mProject.FileName];
  end;
  mFound := (FProject <> '') and (IndexText(FProject, FProjects) >= 0);
  if mFound then
  begin
    Exit;
  end;
  // Vorwahl: das aktive Testprojekt, sonst das erste.
  FProject := '';
  mActive := GetActiveProject;
  if (mActive <> nil) and (IndexText(mActive.FileName, FProjects) >= 0) then
  begin
    FProject := mActive.FileName;
  end
  else if Length(FProjects) > 0 then
  begin
    FProject := FProjects[0];
  end;
end;

function TAtlasIdeTestExplorer.ScanFile(const AFileName: string): TScanned;
var
  mAge: TDateTime;
begin
  mAge := 0;
  if FileExists(AFileName) then
  begin
    mAge := TFile.GetLastWriteTime(AFileName);
  end;
  if FScanned.TryGetValue(KeyOf(AFileName), Result) and (Result.Age = mAge) then
  begin
    Exit;
  end;
  Result := Default(TScanned);
  Result.Age := mAge;
  if TAtlasIdeFiles.ReadLines(AFileName, Result.Lines) and TDUnitXSource.UsesDUnitX(Result.Lines) then
  begin
    Result.Found := TDUnitXSource.Scan(Result.Lines);
    Result.IsTest := Length(Result.Found.Fixtures) > 0;
  end;
  if not Result.IsTest then
  begin
    // Nur Testunits behalten ihren Text (veraltete Tests); andere Units merken sich nur die Zeit.
    Result.Lines := nil;
  end;
  FScanned.AddOrSetValue(KeyOf(AFileName), Result);
end;

procedure TAtlasIdeTestExplorer.ReadUnits;
var
  mProject: IOTAProject;
  mIndex: Integer;
  mFileName: string;
  mScanned: TScanned;
  mInput: TAtlasTestUnitInput;
  mRef: TAtlasTestUnitRef;
  mState: TAtlasTestUnitState;
begin
  FUnits := nil;
  FRefs := nil;
  mProject := TAtlasIdeTestProjects.ProjectByFile(FProject);
  if mProject = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mProject.GetModuleCount - 1 do
  begin
    mFileName := mProject.GetModule(mIndex).FileName;
    if not SameText(ExtractFileExt(mFileName), '.pas') then
    begin
      Continue;
    end;
    mRef.UnitName := ProjectName(mFileName);
    mRef.FileName := mFileName;
    FRefs := FRefs + [mRef];
    mScanned := ScanFile(mFileName);
    if not mScanned.IsTest then
    begin
      Continue;
    end;
    mInput := Default(TAtlasTestUnitInput);
    mInput.FileName := mFileName;
    mInput.Found := mScanned.Found;
    mState := FQueries.StateOf(mScanned.Found, mScanned.Lines);
    mInput.StaleKeys := mState.StaleKeys;
    mInput.Flaky := mState.Flaky;
    FUnits := FUnits + [mInput];
  end;
end;

function TAtlasIdeTestExplorer.StatusInput(const AProject: string): TAtlasTestStatusInput;
var
  mRun: TProjectRun;
  mNode: TAtlasTestNode;
begin
  Result := Default(TAtlasTestStatusInput);
  Result.Busy := FTests.Busy;
  Result.Stale := -1;
  if FResults.TryGetValue(KeyOf(AProject), mRun) then
  begin
    Result.Cases := mRun.Cases;
    Result.LastRun := mRun.At;
    Result.DurationMs := mRun.DurationMs;
  end;
  if (KeyOf(AProject) <> KeyOf(FProject)) or (Length(FNodes) = 0) then
  begin
    Exit;
  end;
  Result.Stale := 0;
  for mNode in FNodes do
  begin
    if (mNode.Kind = TAtlasTestNodeKind.Test) and (TAtlasTestExplorer.StateOf(mNode) = TAtlasTestNodeState.Stale) then
    begin
      Inc(Result.Stale);
    end;
  end;
end;

procedure TAtlasIdeTestExplorer.Reload;
var
  mFrame: TAtlasTestsExplorerFrame;
  mNames: TArray<string>;
  mProject: string;
begin
  mFrame := TAtlasIdeTestsExplorerWindow.ExistingFrame;
  FDirty := False;
  if mFrame = nil then
  begin
    Exit;
  end;
  ReadProjects;
  ReadUnits;
  FNodes := TAtlasTestExplorer.Build(FUnits, StatusInput(FProject).Cases);
  mNames := nil;
  for mProject in FProjects do
  begin
    mNames := mNames + [ProjectName(mProject)];
  end;
  mFrame.SetProjects(mNames, IndexText(FProject, FProjects));
  FBusy := FTests.Busy;
  FVersion := FTests.Version;
  mFrame.SetBusy(FBusy);
  ShowRows;
end;

function TAtlasIdeTestExplorer.StatusText: string;
var
  mTotal, mPassed, mFailed, mNotRun: Integer;
begin
  if FTests.Busy then
  begin
    Exit(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsLensRunning));
  end;
  if FProject = '' then
  begin
    Exit(TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerNoProject));
  end;
  if Length(FNodes) = 0 then
  begin
    Exit(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ExplorerNoTests, [ProjectName(FProject)]));
  end;
  TAtlasTestExplorer.Totals(FNodes, mTotal, mPassed, mFailed, mNotRun);
  Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ExplorerSummary, [mTotal, mPassed, mFailed, mNotRun]);
end;

procedure TAtlasIdeTestExplorer.ShowRows;
var
  mFrame: TAtlasTestsExplorerFrame;
  mTexts: TAtlasTestRowTexts;
  mVisible: TArray<Boolean>;
begin
  mFrame := TAtlasIdeTestsExplorerWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mTexts.Ignored := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerIgnored);
  mTexts.Flaky := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerFlakyMark);
  mTexts.DecimalSeparator := FormatSettings.DecimalSeparator;
  mVisible := TAtlasTestExplorer.Visible(FNodes, mFrame.Filters, mFrame.SearchText,
    TAtlasIdeSettings.Current.TestsSlowMs);
  mFrame.SetRows(TAtlasTestExplorer.Rows(FNodes, mVisible, mTexts), StatusText);
  Selected(mFrame.FocusedNode);
end;

procedure TAtlasIdeTestExplorer.ChooseProject(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FProjects)) then
  begin
    Exit;
  end;
  FProject := FProjects[AIndex];
  Reload;
end;

/// <summary>Verlauf des wackelnden Tests ANode (#1773) vor den Einzelheiten; leer, wenn er nicht wackelt.
/// </summary>
function FlakyDetails(const ANode: TAtlasTestNode;
  const AUnits: TArray<TAtlasTestUnitInput>): TArray<TAtlasTestStackLine>;
var
  mFlaky: TAtlasFlakyTest;
  mTexts: TAtlasTestFlakyTexts;
  mSince: string;
begin
  Result := nil;
  if not TAtlasTestExplorer.FlakyOf(ANode, AUnits, mFlaky) then
  begin
    Exit;
  end;
  mTexts := Default(TAtlasTestFlakyTexts);
  mTexts.Summary := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerDetailFlaky);
  mTexts.Since := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerDetailFlakySince);
  mTexts.Message := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerDetailFlakyMessage);
  // Grün und rot als Häkchen und Kreuz: Die Liste der Einzelheiten kennt keine Farben.
  mTexts.PassedDot := #$2713;
  mTexts.FailedDot := #$2717;
  mSince := '';
  if mFlaky.SinceUtc > 0 then
  begin
    mSince := DateTimeToStr(TTimeZone.Local.ToLocalTime(mFlaky.SinceUtc), FormatSettings);
  end;
  Result := TAtlasTestExplorer.FlakyLines(mFlaky, mSince, mTexts);
end;

procedure TAtlasIdeTestExplorer.Selected(ANode: Integer);
var
  mFrame: TAtlasTestsExplorerFrame;
  mTexts: TAtlasTestDetailTexts;
  mName: string;
  mCount: Integer;
begin
  mFrame := TAtlasIdeTestsExplorerWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mName := '';
  if (ANode >= 0) and (ANode <= High(FNodes)) and (FNodes[ANode].Kind <> TAtlasTestNodeKind.TestUnit) then
  begin
    mName := FNodes[ANode].FullName;
  end;
  mFrame.SetLog(FLogs.Lines(FProject, mName, FRefs, mCount), mCount, TAtlasIdeSettings.Current.TestsLog);
  if mName = '' then
  begin
    mFrame.SetDetails(nil);
    Exit;
  end;
  mTexts.Passed := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerDetailPassed);
  mTexts.NotRun := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerDetailNotRun);
  mTexts.Skipped := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerDetailSkipped);
  mTexts.Message := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerDetailMessage);
  mTexts.Expected := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerDetailExpected);
  mTexts.Actual := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerDetailActual);
  mTexts.Stack := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerDetailStack);
  mTexts.DecimalSeparator := FormatSettings.DecimalSeparator;
  mFrame.SetDetails(FlakyDetails(FNodes[ANode], FUnits) + TAtlasTestExplorer.DetailLines(
    TAtlasTestExplorer.ResultsOf(FNodes[ANode], FUnits, StatusInput(FProject).Cases), FRefs, mTexts));
end;

procedure TAtlasIdeTestExplorer.OpenNode(ANode: Integer);
begin
  if (ANode >= 0) and (ANode <= High(FNodes)) and (FNodes[ANode].FileName <> '') then
  begin
    OpenLine(FNodes[ANode].FileName, Max(FNodes[ANode].Line, 0));
  end;
end;

function TAtlasIdeTestExplorer.Chosen: TArray<Integer>;
var
  mFrame: TAtlasTestsExplorerFrame;
begin
  Result := nil;
  mFrame := TAtlasIdeTestsExplorerWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    Result := mFrame.SelectedNodes;
  end;
  if Length(Result) = 0 then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerNothingSelected));
  end;
end;

procedure TAtlasIdeTestExplorer.RunAll;
var
  mReason: string;
begin
  if (FProject <> '') and not FTests.RunProject(FProject, mReason) and (mReason <> '') then
  begin
    FTests.Say(mReason);
  end;
end;

procedure TAtlasIdeTestExplorer.RunSelected;
var
  mChosen: TArray<Integer>;
  mNames: TArray<string>;
begin
  mChosen := Chosen;
  mNames := TAtlasTestExplorer.RunNames(FUnits, FNodes, mChosen);
  if Length(mNames) > 0 then
  begin
    // Die Testunit des ersten gewählten Knotens bestimmt das Testprojekt wie bei der Testlinse.
    FTests.RunTests(FNodes[mChosen[0]].FileName, mNames);
  end;
end;

procedure TAtlasIdeTestExplorer.DebugSelected;
var
  mChosen: TArray<Integer>;
  mNode: TAtlasTestNode;
  mSelection: TAtlasTestSelection;
begin
  mChosen := Chosen;
  if Length(mChosen) = 0 then
  begin
    Exit;
  end;
  mNode := FNodes[mChosen[0]];
  // Eine ganze Testunit: über ihre erste Fixture benennen, die Namen decken alle ab.
  mSelection := TAtlasTestDebug.Selection(FUnits[mNode.UnitIndex].Found, Max(mNode.FixtureIndex, 0),
    mNode.TestIndex, mNode.CaseIndex);
  mSelection.Names := TAtlasTestExplorer.RunNames(FUnits, FNodes, mChosen);
  if (Length(mChosen) > 1) or (mNode.Kind = TAtlasTestNodeKind.TestUnit) then
  begin
    // Mehrere Tests: kein einmaliger Haltepunkt am Anfang eines davon.
    mSelection.BreakLine := -1;
  end;
  if Length(mSelection.Names) > 0 then
  begin
    FDebugger.Debug(mNode.FileName, mSelection);
  end;
end;

end.
