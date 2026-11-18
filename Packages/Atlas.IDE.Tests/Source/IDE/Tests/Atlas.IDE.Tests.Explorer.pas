unit Atlas.IDE.Tests.Explorer;

// Fenster „Atlas-Tests“ (#1776, tests.window) in der IDE:
// - Testprojekte der Projektgruppe (Hauptdatei mit DUnitX.TestFramework); bei
//   mehreren wählt der Benutzer oben, vorgewählt ist das aktive Testprojekt.
// - Testunits: die .pas-Dateien des Testprojekts, die DUnitX verwenden, mit
//   Atlas.Text.DUnitX gelesen (Puffer der IDE, sonst Platte; ohne Server).
//   Gelesen wird beim Öffnen, nach jedem Lauf, nach dem Speichern einer
//   Unit des Testprojekts und mit „Neu einlesen“; ungeänderte Dateien kommen
//   aus dem Zwischenspeicher (Änderungszeit, Atlas.Core.Tests.UnitScans).
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
//   (#585; Haltepunkt am Anfang nur bei einem einzelnen Test). Das
//   Kontextmenü des Baums führt die Auswahl N-mal bzw. einzeln in zufälliger
//   Reihenfolge aus (#1782, Atlas.IDE.Tests.Series, Atlas.UI.Tests.SeriesMenu).
// - Testlisten (#2167): Reiter, Kopfzeile und Ausführen in
//   Atlas.IDE.Tests.Lists (TAtlasIdeTestLists.Instance); das Fenster liefert
//   ihnen den Stand (Connect) und zeigt im Reiter einer Liste nur deren Tests.
// - Protokoll je Test (#2168, tests.log): Atlas.IDE.Tests.ExplorerLog merkt
//   sich das Protokoll der Läufe; der Reiter „Protokoll (n)“ zeigt es zum
//   gewählten Test, Fall bzw. zur Fixture.
// - Nach einem Lauf, der schiefging (Fehlschläge, kein Bericht, Zeitgrenze),
//   zeigt ShowFailedRun das Fenster mit dem Testprojekt des Laufs und holt
//   es nach vorn (#2467, tests.window.openOnFailure).
// - Ein Zeitgeber folgt dem Läufer (Lauf beginnt bzw. endet), solange das
//   Fenster zu sehen ist (Atlas.IDE.Tests.ExplorerTicker); er lebt nur so
//   lange wie dieses Objekt.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Explorer,
  Atlas.Core.Tests.Series,
  Atlas.Core.Tests.StatusField,
  Atlas.Core.Tests.UnitScans,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Debug,
  Atlas.IDE.Tests.Series,
  Atlas.IDE.Tests.Lists,
  Atlas.IDE.Tests.ExplorerLog,
  Atlas.IDE.Tests.ExplorerTicker,
  Atlas.UI.Tests.ExplorerFrame;

type
  /// <summary>Testlisten (#2167) für die Composition, ohne eigene Zeile in deren uses.</summary>
  TAtlasIdeTestLists = Atlas.IDE.Tests.Lists.TAtlasIdeTestLists;

  TAtlasIdeTestExplorer = class
  private type
    /// <summary>Ergebnisse eines Testprojekts dieser Sitzung und Ende und Dauer des letzten Laufs.</summary>
    TProjectRun = record
      Cases: TArray<TTestCaseResult>;
      At: TDateTime;
      DurationMs: Int64;
    end;
  private
    FTests: TAtlasIdeTests;
    FDebugger: TAtlasIdeTestDebugger;
    FSeries: TAtlasIdeTestSeries;
    FQueries: TAtlasTestStateQueries;
    FNext: TAtlasTestsReportedProc;
    FTicker: TAtlasIdeTestExplorerTicker;
    /// <summary>Ergebnisse je Testprojekt (Schlüssel klein) dieser Sitzung.</summary>
    FResults: TDictionary<string, TProjectRun>;
    /// <summary>Protokoll je Test (#2168) je Testprojekt dieser Sitzung.</summary>
    FLogs: TAtlasIdeTestLogs;
    /// <summary>Gelesene Units des Testprojekts.</summary>
    FScans: TAtlasTestUnitScans;
    /// <summary>Gewähltes Testprojekt (.dproj); '' = noch keins.</summary>
    FProject: string;
    FProjects: TArray<string>;
    FUnits: TArray<TAtlasTestUnitInput>;
    FRefs: TArray<TAtlasTestUnitRef>;
    FNodes: TArray<TAtlasTestNode>;
    procedure Wire(AFrame: TAtlasTestsExplorerFrame);
    /// <summary>Testprojekte und Testunits neu lesen, Baum neu bauen und zeigen.</summary>
    procedure Reload;
    procedure ReadProjects;
    procedure ReadUnits;
    /// <summary>Statuszeile des Fensters.</summary>
    function StatusText: string;
    /// <summary>Neuer Stand des Läufers (läuft bzw. neuer Bericht) im Fenster.</summary>
    procedure ShowBusy(ABusy: Boolean);
    /// <summary>Baum mit den aktuellen Filtern zeigen.</summary>
    procedure ShowRows;
    procedure ChooseProject(AIndex: Integer);
    procedure Selected(ANode: Integer);
    procedure OpenNode(ANode: Integer);
    procedure RunAll;
    procedure RunSelected;
    procedure DebugSelected;
    /// <summary>Gewählte Knoten; ohne Auswahl eine Meldung und leer.</summary>
    function Chosen: TArray<Integer>;
    /// <summary>Gewählte Knoten als Serie (#1782): Datei, Gegenstand und Namen (AShuffle: je Test bzw. Fall ein
    /// Name). False ohne Auswahl.</summary>
    function SeriesChoice(AShuffle: Boolean; out AFileName: string; out ASubject: TAtlasTestSeriesSubject;
      out ANames: TArray<string>): Boolean;
  public
    /// <summary>ATests, ADebugger und ASeries gehören dem Aufrufer und leben länger; AQueries nennt veraltete
    /// (#1770) und wackelnde Tests (#1773, je nil = keine); ANext bekommt jeden Lauf danach (nil = keiner).</summary>
    constructor Create(ATests: TAtlasIdeTests; ADebugger: TAtlasIdeTestDebugger; ASeries: TAtlasIdeTestSeries;
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
    /// <summary>Fenster nach einem Lauf von AProject zeigen, der schiefging (#2467): mit diesem Testprojekt, nach
    /// vorn. Nichts mit tests.window.openOnFailure oder tests.window aus.</summary>
    procedure ShowFailedRun(const AProject: string);
  end;

implementation

uses
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
  Atlas.UI.Tests.SeriesMenu,
  Atlas.UI.Tests.Strings;

function KeyOf(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

function ProjectName(const AFileName: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AFileName), '');
end;

/// <summary>Testlisten des Moduls (#2167); nil, solange keine bestehen.</summary>
function Lists: TAtlasIdeTestLists;
begin
  Result := TAtlasIdeTestLists.Instance;
end;

/// <summary>Datei an Zeile ALine (0-basiert) öffnen.</summary>
procedure OpenAt(const AFileName: string; ALine: Integer);
begin
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      TAtlasIdeResults.Open(AFileName, ALine, 0);
    end);
end;

type
  /// <summary>Gewählte Knoten als Serie (#1782); False ohne Auswahl.</summary>
  TAtlasTestSeriesChoice = reference to function(AShuffle: Boolean; out AFileName: string;
    out ASubject: TAtlasTestSeriesSubject; out ANames: TArray<string>): Boolean;

/// <summary>Einträge des Kontextmenüs für Serien (#1782) über ASeries mit der Auswahl aus AChoice.</summary>
function SeriesHandlers(ASeries: TAtlasIdeTestSeries; const AChoice: TAtlasTestSeriesChoice):
  TAtlasTestsSeriesHandlers;
var
  mSeries: TAtlasIdeTestSeries;
  mChoice: TAtlasTestSeriesChoice;
begin
  mSeries := ASeries;
  mChoice := AChoice;
  Result := Default(TAtlasTestsSeriesHandlers);
  Result.OnRepeat :=
    procedure
    var
      mFileName: string;
      mSubject: TAtlasTestSeriesSubject;
      mNames: TArray<string>;
    begin
      if mChoice(False, mFileName, mSubject, mNames) then
      begin
        mSeries.RepeatNames(mFileName, mSubject, mNames);
      end;
    end;
  Result.OnShuffle :=
    procedure
    var
      mFileName: string;
      mSubject: TAtlasTestSeriesSubject;
      mNames: TArray<string>;
    begin
      if mChoice(True, mFileName, mSubject, mNames) then
      begin
        mSeries.ShuffleNames(mFileName, mSubject, mNames);
      end;
    end;
  Result.OnShuffleAgain := mSeries.ShuffleAgain;
  Result.OnCancel := mSeries.Cancel;
  Result.Running :=
    function: Boolean
    begin
      Result := mSeries.Running;
    end;
  Result.CanShuffleAgain :=
    function: Boolean
    begin
      Result := mSeries.CanShuffleAgain;
    end;
end;

{ TAtlasIdeTestExplorer }

constructor TAtlasIdeTestExplorer.Create(ATests: TAtlasIdeTests; ADebugger: TAtlasIdeTestDebugger;
  ASeries: TAtlasIdeTestSeries; const AQueries: TAtlasTestStateQueries; const ANext: TAtlasTestsReportedProc);
begin
  inherited Create;
  FTests := ATests;
  FDebugger := ADebugger;
  FSeries := ASeries;
  FQueries := AQueries;
  FNext := ANext;
  FResults := TDictionary<string, TProjectRun>.Create;
  FScans := TAtlasTestUnitScans.Create(TAtlasIdeFiles.LineReader(), nil);
  FLogs := TAtlasIdeTestLogs.Create;
  FTicker := TAtlasIdeTestExplorerTicker.Create(FTests, Reload, ShowBusy);
  // Testlisten (#2167): Stand für Palette, Taste und Reiter; ohne gezeigtes Fenster liest es neu, das Fenster
  // zieht beim nächsten Takt nach.
  if Lists <> nil then
  begin
    Lists.Connect(
      function(AWithUnits: Boolean): TAtlasTestListSource
      begin
        Result := Default(TAtlasTestListSource);
        ReadProjects;
        if AWithUnits then
        begin
          ReadUnits;
          FNodes := TAtlasTestExplorer.Build(FUnits, StatusInput(FProject).Cases);
          FTicker.MarkDirty;
        end;
        Result.Project := FProject;
        Result.Units := FUnits;
        Result.Nodes := FNodes;
      end, ShowRows);
  end;
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
  FreeAndNil(FTicker);
  if Lists <> nil then
  begin
    Lists.Connect(nil, nil);
  end;
  TAtlasIdeTestsExplorerWindow.OnFrame := nil;
  if TAtlasIdeTestsExplorerWindow.ExistingFrame <> nil then
  begin
    TAtlasIdeTestsExplorerWindow.ExistingFrame.SetHandlers(Default(TAtlasTestsExplorerHandlers));
    TAtlasTestsSeriesMenu.Detach(TAtlasIdeTestsExplorerWindow.ExistingFrame.Tree);
  end;
  TAtlasIdeTestsExplorerWindow.Release;
  FResults.Free;
  FScans.Free;
  FLogs.Free;
  FQueries := Default(TAtlasTestStateQueries);
  FNext := nil;
  inherited;
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
      FScans.Clear;
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
      OpenAt(AFileName, ALine);
    end;
  AFrame.SetHandlers(mHandlers);
  // Serien (#1782) im Kontextmenü des Baums.
  TAtlasTestsSeriesMenu.Detach(AFrame.Tree);
  TAtlasTestsSeriesMenu.Attach(AFrame.Tree, SeriesHandlers(FSeries, SeriesChoice));
  if Lists <> nil then
  begin
    Lists.Wire(AFrame);
  end;
  FTicker.Start;
  Reload;
end;

procedure TAtlasIdeTestExplorer.Reload;
var
  mFrame: TAtlasTestsExplorerFrame;
  mNames: TArray<string>;
  mProject: string;
begin
  mFrame := TAtlasIdeTestsExplorerWindow.ExistingFrame;
  if mFrame = nil then
  begin
    FTicker.Synced;
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
  if Lists <> nil then
  begin
    Lists.Refresh(FProject);
  end;
  mFrame.SetBusy(FTicker.Synced);
  ShowRows;
end;

procedure TAtlasIdeTestExplorer.ReadProjects;
var
  mProject: IOTAProject;
  mActive: string;
begin
  FProjects := nil;
  for mProject in TAtlasIdeTestProjects.TestProjects('') do
  begin
    FProjects := FProjects + [mProject.FileName];
  end;
  mActive := '';
  if GetActiveProject <> nil then
  begin
    mActive := GetActiveProject.FileName;
  end;
  FProject := TAtlasTestExplorerChoice.Project(FProject, FProjects, mActive);
end;

procedure TAtlasIdeTestExplorer.ReadUnits;
var
  mProject: IOTAProject;
  mIndex: Integer;
  mFileName: string;
  mScanned: TAtlasTestUnitScan;
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
    mScanned := FScans.Scan(mFileName);
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

function TAtlasIdeTestExplorer.StatusText: string;
var
  mTotal, mPassed, mFailed, mNotRun: Integer;
begin
  case TAtlasTestExplorerChoice.Status(FTests.Busy, FProject, Length(FNodes)) of
    TAtlasTestExplorerStatus.Running:
      Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsLensRunning);
    TAtlasTestExplorerStatus.NoProject:
      Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerNoProject);
    TAtlasTestExplorerStatus.NoTests:
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ExplorerNoTests, [ProjectName(FProject)]);
  else
    TAtlasTestExplorer.Totals(FNodes, mTotal, mPassed, mFailed, mNotRun);
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ExplorerSummary, [mTotal, mPassed, mFailed, mNotRun]);
  end;
end;

procedure TAtlasIdeTestExplorer.ShowBusy(ABusy: Boolean);
var
  mFrame: TAtlasTestsExplorerFrame;
begin
  mFrame := TAtlasIdeTestsExplorerWindow.ExistingFrame;
  if mFrame <> nil then
  begin
    mFrame.SetBusy(ABusy);
    mFrame.SetStatus(StatusText);
  end;
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
  if Lists <> nil then
  begin
    // Im Reiter einer Testliste (#2167) nur deren Tests.
    mVisible := Lists.Filter(mFrame, FUnits, FNodes, mVisible);
  end;
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

procedure TAtlasIdeTestExplorer.OpenNode(ANode: Integer);
begin
  if (ANode >= 0) and (ANode <= High(FNodes)) and (FNodes[ANode].FileName <> '') then
  begin
    OpenAt(FNodes[ANode].FileName, Max(FNodes[ANode].Line, 0));
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
    FTests.RunTests(FNodes[mChosen[0]].FileName, mNames, False);
  end;
end;

procedure TAtlasIdeTestExplorer.DebugSelected;
var
  mChosen: TArray<Integer>;
  mSelection: TAtlasTestSelection;
begin
  mChosen := Chosen;
  if Length(mChosen) = 0 then
  begin
    Exit;
  end;
  mSelection := TAtlasTestExplorerChoice.DebugSelection(FUnits, FNodes, mChosen);
  if Length(mSelection.Names) > 0 then
  begin
    FDebugger.Debug(FNodes[mChosen[0]].FileName, mSelection);
  end;
end;

function TAtlasIdeTestExplorer.SeriesChoice(AShuffle: Boolean; out AFileName: string;
  out ASubject: TAtlasTestSeriesSubject; out ANames: TArray<string>): Boolean;
var
  mChosen: TArray<Integer>;
  mNode: TAtlasTestNode;
begin
  AFileName := '';
  ASubject := Default(TAtlasTestSeriesSubject);
  ANames := nil;
  mChosen := Chosen;
  Result := Length(mChosen) > 0;
  if not Result then
  begin
    Exit;
  end;
  mNode := FNodes[mChosen[0]];
  AFileName := mNode.FileName;
  ASubject := TAtlasTestExplorerChoice.SubjectOf(FUnits[mNode.UnitIndex].Found, mNode);
  if AShuffle then
  begin
    ANames := TAtlasTestExplorerChoice.ShuffleNames(FUnits, FNodes, mChosen);
  end
  else
  begin
    ANames := TAtlasTestExplorer.RunNames(FUnits, FNodes, mChosen);
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

class function TAtlasIdeTestExplorer.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestRun and TAtlasIdeSettings.Current.TestsWindow;
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
  FTicker.MarkDirty;
  if Assigned(FNext) then
  begin
    FNext(ATarget, ARun);
  end;
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
  mName := TAtlasTestExplorerChoice.DetailName(FNodes, ANode);
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

procedure TAtlasIdeTestExplorer.FileSaved(const AFileName: string);
begin
  if FScans.Forget(AFileName) then
  begin
    FTicker.MarkDirty;
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
    FTicker.Start;
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
    FTicker.Stop;
  end;
end;

class procedure TAtlasIdeTestExplorer.ThemeChanged;
begin
  TAtlasIdeTestsExplorerWindow.ApplyTheme;
end;

function TAtlasIdeTestExplorer.StatusInput(const AProject: string): TAtlasTestStatusInput;
var
  mRun: TProjectRun;
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
  Result.Stale := TAtlasTestExplorerChoice.StaleCount(FNodes);
end;

procedure TAtlasIdeTestExplorer.ShowFailedRun(const AProject: string);
begin
  if not TAtlasIdeSettings.Current.TestsWindowOnFailure or not Wanted then
  begin
    Exit;
  end;
  // Das Fenster zeigt das Testprojekt des Laufs; ReadProjects behält es, solange es zur Gruppe gehört.
  if AProject <> '' then
  begin
    FProject := AProject;
  end;
  Show(False);
end;

end.
