unit Atlas.Core.Problems.Flow;

// Ablauf der Probleme im Editor (#398) ohne VCL und Open Tools API: welche
// Datei wann geholt wird, was mit den Antworten des Servers geschieht und wann
// alles verworfen wird. Server und IDE kommen über die Verträge in
// Atlas.Core.Problems.Contract.Sync; in der IDE treibt ihn
// TAtlasProblemsController (Takt, Zeichner, Meldungsliste), in den Tests eine
// Fälschung.
//   - Tick liest den oberen Editor. Hat sich der Puffer geändert, wandern die
//     Markierungen im Speicher mit (Edit). Nach der Tipp-Pause bzw. dem
//     Speichern (problems.update, problems.liveDelayMs) wird der Text
//     abgeglichen und textDocument/diagnostic im Hintergrund geholt.
//   - Bittet der Server um neues Holen (workspace/diagnostic/refresh, etwa
//     nach einem Compile mit neuen dcc-Meldungen), holt der Ablauf alle
//     abgeglichenen Dateien neu und übernimmt dabei auch die Compilermeldungen.
//   - Die übrigen Projektdateien kommen über workspace/diagnostic (#82), nur
//     solange Probleme gezeigt werden; das Abblenden inaktiver Zweige (#615)
//     und ungenutzter uses (#621) braucht nur die geöffneten.
//   - In der IDE geschlossene Dateien bekommen didClose; dann liefert sie der
//     Server wieder über workspace/diagnostic.
//   - Beim Wechsel des Editors geht das Getippte der vorigen Unit sofort an den
//     Server (Index, #492).
//   - Angeforderte Dateien (#1817) gleicht der nächste Takt mit dem Text aus
//     Editor bzw. Platte ab und holt sie, auch ohne offenen Editor.
//   - Während des Debuggens ruht die Prüfung (#1241), die Projektprüfung des
//     Servers erfährt es eigens (#1247). Ausgeschaltet oder nach weggefallenen
//     Projekten (Projektgruppe geschlossen oder gewechselt) wird alles
//     verworfen; Pull-Diagnosen melden Dateien, die nicht mehr dazugehören,
//     nie wieder.
//   - Eine neue Sitzung (Serverneustart, #393) holt alle Dateien neu.
// Die Antworten ordnet TAtlasProblemsResults ein: Speicher, letzte Prüfung,
// Stand der Projektprüfung, Fehler der IDE nach jeder Prüfung einer Datei
// (#1819, problems.ideErrors; mögliche Fehlalarme je Stelle einmal ins
// Protokoll) und Zähler für die Statusleiste (#509). TAtlasProblemsTexts merkt
// sich je Datei den gesehenen und den zuletzt geholten Text.
// Nur im Hauptthread verwenden.

interface

uses
  System.Generics.Collections,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Problems.Contract.Sync,
  Atlas.Core.Problems.Store,
  Atlas.Core.Problems.IdeErrors,
  Atlas.Core.Problems.InlineHints,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Deadline;

type
  /// <summary>Letzte Prüfung einer Datei für die Statuszeile (#909); FileName '' = noch keine.</summary>
  TAtlasProblemsCheck = record
    FileName: string;
    DurationMs: Cardinal;
    At: TDateTime;
  end;

  /// <summary>Texte je Datei (Groß- und Kleinschreibung egal): zuletzt im Editor gesehen mit Pufferstand und zuletzt
  /// an den Server gegeben und geholt.</summary>
  TAtlasProblemsTexts = class
  private
    FSeen: TDictionary<string, string>;
    FVersions: TDictionary<string, Cardinal>;
    FPulled: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Pufferstand von AEditor merken; True, wenn er neu ist.</summary>
    function Track(const AEditor: TAtlasProblemsEditor): Boolean;
    /// <summary>Zuletzt im Editor gesehener Text; False, wenn die Datei nicht abgeglichen ist.</summary>
    function Seen(const AFileName: string; out AText: string): Boolean;
    /// <summary>AText von AFileName wurde abgeglichen und angefordert.</summary>
    procedure MarkPulled(const AFileName, AText: string);
    /// <summary>Zuletzt angeforderter Text; False, wenn die Datei in dieser Sitzung noch nicht geholt wurde.</summary>
    function Pulled(const AFileName: string; out AText: string): Boolean;
    /// <summary>Angeforderte Stände vergessen (neue Sitzung): Alles wird neu geholt.</summary>
    procedure ForgetPulled;
    /// <summary>AFileName ganz vergessen (in der IDE geschlossen).</summary>
    procedure Forget(const AFileName: string);
    procedure Clear;
  end;

  /// <summary>Antworten des Servers und was aus ihnen folgt.</summary>
  TAtlasProblemsResults = class
  private
    FEditors: IAtlasProblemsEditors;
    FTexts: TAtlasProblemsTexts;
    FLog: TAtlasProblemsLogProc;
    FStore: TAtlasProblemStore;
    // Fehler der IDE (#1819): mögliche Fehlalarme je Stelle einmal protokollieren; zuletzt abgefragt?
    FIdeJournal: TAtlasIdeErrorJournal;
    FIdeErrorsOn: Boolean;
    // Stand der Projektprüfung des Servers (#1247) und wann der letzte Lauf endete (TAtlasTicks, 0 = nie).
    FRun: TLspWorkspaceRun;
    FRunFinishedAt: UInt64;
    FLastCheck: TAtlasProblemsCheck;
    // Zähler (#509): zuletzt gemeldeter Stand.
    FCountsShown: Boolean;
    FCountsVersion: Integer;
    /// <summary>problems.ideErrors übernehmen; beim Ausschalten die Fehler der IDE verwerfen.</summary>
    procedure ApplyIdeErrors;
    /// <summary>Nach der Prüfung von AFileName: Fehler der IDE abfragen und mögliche Fehlalarme protokollieren;
    /// ausgeschaltet nichts.</summary>
    procedure QueryIdeErrors(const AFileName: string);
  public
    /// <summary>AEditors liefert die Fehler der IDE, ATexts (nicht übernommen) den aktuellen Text.</summary>
    constructor Create(const AEditors: IAtlasProblemsEditors; ATexts: TAtlasProblemsTexts;
      const ALog: TAtlasProblemsLogProc);
    destructor Destroy; override;
    /// <summary>problems.compilerMerge, editor.trackLines und problems.ideErrors übernehmen; beim Ausschalten der
    /// Fehler der IDE diese verwerfen.</summary>
    procedure Apply(const ASettings: TAtlasPluginSettings);
    /// <summary>Antwort auf einen Auftrag (Hauptthread).</summary>
    procedure Document(const ASettings: TAtlasPluginSettings; const APull: TAtlasProblemsPull;
      const AReport: TLspDiagnosticReport);
    /// <summary>Antwort der übrigen Projektdateien (Hauptthread).</summary>
    procedure Workspace(const ASettings: TAtlasPluginSettings; const AReports: TArray<TLspDiagnosticReport>;
      const ARun: TLspWorkspaceRun);
    /// <summary>Zähler der Statusleiste neu melden (#509)? AShow False = Feld entfernen.</summary>
    function CountsDue(const ASettings: TAtlasPluginSettings; out AShow: Boolean;
      out ACounts: TAtlasProblemCounts): Boolean;
    /// <summary>Stand der Projektprüfung des Servers (#1247); AFinishedAgoMs = Zeit seit dem Ende des letzten Laufs
    /// (High(UInt64) ohne). False, solange der Server keinen Stand gemeldet hat.</summary>
    function ProjectRun(out ARun: TLspWorkspaceRun; out AFinishedAgoMs: UInt64): Boolean;
    /// <summary>Zähler aller Befunde in AStore wie in der Liste (#509).</summary>
    class function CountsOf(AStore: TAtlasProblemStore): TAtlasProblemCounts; static;
    property Store: TAtlasProblemStore read FStore;
    /// <summary>Letzte Prüfung einer Datei (#909).</summary>
    property LastCheck: TAtlasProblemsCheck read FLastCheck;
  end;

  TAtlasProblemsFlow = class
  public const
    /// <summary>Abstand der Suche nach in der IDE geschlossenen, noch abgeglichenen Dateien.</summary>
    cClosedCheckMs = 5000;
    /// <summary>Nach gescheitertem Serverstart so lange warten.</summary>
    cStartRetryMs = 30000;
  private
    FServer: IAtlasProblemsServer;
    FEditors: IAtlasProblemsEditors;
    FLog: TAtlasProblemsLogProc;
    FTexts: TAtlasProblemsTexts;
    FResults: TAtlasProblemsResults;
    // Sitzung, für die das Holen bereitsteht; 0 = keine.
    FSession: Integer;
    FRefreshSeen: Integer;
    // Zuletzt dem Server gemeldete Debug-Pause (#1247).
    FDebugPauseSent: Boolean;
    // Zuletzt aktiver Editor: beim Wechsel seinen Stand sofort an den Server (#492).
    FLastFile: string;
    FChangedAt: UInt64;
    FClosedCheckAt: UInt64;
    FRetryAt: TAtlasDeadline;
    // Zuletzt gesehener Zähler weggefallener Projekte der Sitzung.
    FProjectsRemoved: Integer;
    FTickMs: Integer;
    /// <summary>Abgeschaltet oder Debugger aktiv: Holen beenden; True, dann ruht der Takt.</summary>
    function Halted(const ASettings: TAtlasPluginSettings): Boolean;
    /// <summary>Speicher und Stände verwerfen.</summary>
    procedure DropAll;
    /// <summary>Meldet dem Server Beginn und Ende des Debuggens (#1247): Die Projektprüfung ruht solange.</summary>
    procedure ReportDebugPause(APaused: Boolean);
    /// <summary>Projektgruppe geschlossen oder gewechselt: alles verwerfen und neu holen.</summary>
    procedure CheckProjectsRemoved;
    /// <summary>Angeforderte Dateien (#1817) mit dem Text aus Editor bzw. Platte abgleichen und holen.</summary>
    procedure PullRequestedFiles(const ASettings: TAtlasPluginSettings);
    /// <summary>Holen für die Sitzung von Connect bereitstellen; eine neue Sitzung holt alles neu.</summary>
    procedure EnsurePulls(const ASettings: TAtlasPluginSettings);
    procedure Serve(const ASettings: TAtlasPluginSettings; const AEditor: TAtlasProblemsEditor);
    /// <summary>Editor gewechselt: Getipptes der vorigen Unit sofort senden (#492).</summary>
    procedure SyncPrevious(const AFileName: string);
    /// <summary>Diagnosen der Datei holen, wenn der Server neu gebaut hat oder die Tipp-Pause um ist.</summary>
    procedure PullIfDue(const ASettings: TAtlasPluginSettings; const AEditor: TAtlasProblemsEditor);
    /// <summary>Datei mit Text AText jetzt holen (problems.update, Anforderung)?</summary>
    function PullDue(const ASettings: TAtlasPluginSettings; const AFileName, AText: string;
      AModified: Boolean): Boolean;
    /// <summary>Alle anderen abgeglichenen Dateien: Ihre Compilermeldungen können neu sein.</summary>
    function OtherPulls(const AFileName: string): TAtlasProblemsPulls;
    /// <summary>In der IDE geschlossene Dateien beim Server schließen.</summary>
    procedure CloseUnopened;
  public
    /// <summary>AServer holt, AEditors liest die IDE, ALog bekommt Protokollzeilen.</summary>
    constructor Create(const AServer: IAtlasProblemsServer; const AEditors: IAtlasProblemsEditors;
      const ALog: TAtlasProblemsLogProc);
    destructor Destroy; override;
    /// <summary>Ein Takt mit den Einstellungen ASettings.</summary>
    procedure Tick(const ASettings: TAtlasPluginSettings);
    /// <summary>Holen beenden (Ende der Sitzung, Teil 1).</summary>
    procedure StopPulls;
    /// <summary>Holen ist beendet (Teil 2): Die nächste Sitzung beginnt ohne Stände der alten.</summary>
    procedure Stopped;
    /// <summary>Läuft gerade eine Prüfung (textDocument/diagnostic)? (#1155)</summary>
    function Checking: Boolean;
    /// <summary>Speicher, Antworten und Zähler.</summary>
    property Results: TAtlasProblemsResults read FResults;
    /// <summary>Takt, den die Verzögerung problems.liveDelayMs verlangt (ms); nach jedem Tick neu.</summary>
    property TickMs: Integer read FTickMs;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Plan,
  Atlas.Core.Problems.Refresh,
  Atlas.Core.Settings.ProblemsUpdate;

{ TAtlasProblemsTexts }

constructor TAtlasProblemsTexts.Create;
begin
  inherited Create;
  FSeen := TDictionary<string, string>.Create;
  FVersions := TDictionary<string, Cardinal>.Create;
  FPulled := TDictionary<string, string>.Create;
end;

destructor TAtlasProblemsTexts.Destroy;
begin
  FPulled.Free;
  FVersions.Free;
  FSeen.Free;
  inherited Destroy;
end;

function TAtlasProblemsTexts.Track(const AEditor: TAtlasProblemsEditor): Boolean;
var
  mKey: string;
  mKnownVersion: Cardinal;
begin
  mKey := TAtlasProblemStore.Key(AEditor.FileName);
  Result := not FVersions.TryGetValue(mKey, mKnownVersion) or (mKnownVersion <> AEditor.Version);
  if Result then
  begin
    FVersions.AddOrSetValue(mKey, AEditor.Version);
    FSeen.AddOrSetValue(mKey, AEditor.Text);
  end;
end;

function TAtlasProblemsTexts.Seen(const AFileName: string; out AText: string): Boolean;
begin
  Result := FSeen.TryGetValue(TAtlasProblemStore.Key(AFileName), AText);
end;

procedure TAtlasProblemsTexts.MarkPulled(const AFileName, AText: string);
begin
  FPulled.AddOrSetValue(TAtlasProblemStore.Key(AFileName), AText);
end;

function TAtlasProblemsTexts.Pulled(const AFileName: string; out AText: string): Boolean;
begin
  Result := FPulled.TryGetValue(TAtlasProblemStore.Key(AFileName), AText);
end;

procedure TAtlasProblemsTexts.ForgetPulled;
begin
  FPulled.Clear;
end;

procedure TAtlasProblemsTexts.Forget(const AFileName: string);
var
  mKey: string;
begin
  mKey := TAtlasProblemStore.Key(AFileName);
  FSeen.Remove(mKey);
  FVersions.Remove(mKey);
  FPulled.Remove(mKey);
end;

procedure TAtlasProblemsTexts.Clear;
begin
  FSeen.Clear;
  FVersions.Clear;
  FPulled.Clear;
end;

{ TAtlasProblemsResults }

procedure TAtlasProblemsResults.ApplyIdeErrors;
var
  mOn: Boolean;
begin
  mOn := FEditors.IdeErrorsEnabled;
  if mOn = FIdeErrorsOn then
  begin
    Exit;
  end;
  FIdeErrorsOn := mOn;
  if not mOn then
  begin
    FStore.ClearIdeErrors;
    FIdeJournal.Clear;
  end;
end;

procedure TAtlasProblemsResults.QueryIdeErrors(const AFileName: string);
var
  mErrors: TArray<TAtlasProblem>;
  mLine: string;
begin
  ApplyIdeErrors;
  if not FIdeErrorsOn then
  begin
    Exit;
  end;
  if not FEditors.IdeErrors(AFileName, mErrors) then
  begin
    // Die IDE kennt die Datei nicht (mehr) bzw. kein Modul: keine Aussage, also auch kein Fehlalarm.
    FStore.SetIdeErrors(AFileName, nil);
    Exit;
  end;
  FStore.SetIdeErrors(AFileName, mErrors);
  for mLine in FIdeJournal.NewLines(AFileName, FStore.WithIde(AFileName)) do
  begin
    FLog(mLine);
  end;
end;

constructor TAtlasProblemsResults.Create(const AEditors: IAtlasProblemsEditors; ATexts: TAtlasProblemsTexts;
  const ALog: TAtlasProblemsLogProc);
begin
  inherited Create;
  FEditors := AEditors;
  FTexts := ATexts;
  FLog := ALog;
  FStore := TAtlasProblemStore.Create;
  FIdeJournal := TAtlasIdeErrorJournal.Create;
end;

destructor TAtlasProblemsResults.Destroy;
begin
  FIdeJournal.Free;
  FStore.Free;
  inherited Destroy;
end;

procedure TAtlasProblemsResults.Apply(const ASettings: TAtlasPluginSettings);
begin
  // Bestätigte Compilermeldungen zusammenführen (problems.compilerMerge, #1024); ändert nur bei Wechsel.
  FStore.CompilerMerge := TAtlasProblemsPlan.CompilerMerge(ASettings);
  // Meldungen gelöschter Zeilen fallen weg statt blass auf die Folgezeile zu rutschen (#1818, editor.trackLines).
  FStore.DropDeletedLines := TAtlasProblemsPlan.DropDeletedLines(ASettings);
  ApplyIdeErrors;
end;

procedure TAtlasProblemsResults.Document(const ASettings: TAtlasPluginSettings; const APull: TAtlasProblemsPull;
  const AReport: TLspDiagnosticReport);
var
  mCurrent: string;
begin
  if not TAtlasProblemsPlan.Active(ASettings) then
  begin
    Exit;
  end;
  FLastCheck.FileName := APull.FileName;
  FLastCheck.DurationMs := APull.DurationMs;
  FLastCheck.At := Now;
  if not AReport.Unchanged then
  begin
    FStore.Update(APull.FileName, APull.Text, True, AReport.Problems, AReport.ResultId, APull.ReplaceCompiler);
    // Inzwischen weitergetippt: Positionen auf den aktuellen Text bringen.
    if FTexts.Seen(APull.FileName, mCurrent) and (mCurrent <> APull.Text) then
    begin
      FStore.Edit(APull.FileName, mCurrent);
    end;
  end;
  // Auch ohne neue Befunde: Error Insight der IDE kann sich seit der letzten Prüfung geändert haben.
  QueryIdeErrors(APull.FileName);
end;

procedure TAtlasProblemsResults.Workspace(const ASettings: TAtlasPluginSettings;
  const AReports: TArray<TLspDiagnosticReport>; const ARun: TLspWorkspaceRun);
var
  mReport: TLspDiagnosticReport;
  mText: string;
begin
  if not TAtlasProblemsPlan.Shown(ASettings) then
  begin
    Exit;
  end;
  if ARun.Known then
  begin
    // Ende des Laufs merken: Die Statusleiste meldet eine Weile „fertig“.
    if FRun.Active and not ARun.Active then
    begin
      FRunFinishedAt := TAtlasTicks.Now;
    end;
    FRun := ARun;
  end;
  for mReport in AReports do
  begin
    // Abgeglichene Dateien kommen über textDocument/diagnostic.
    if not FTexts.Seen(mReport.FileName, mText) then
    begin
      FStore.Update(mReport.FileName, '', False, mReport.Problems, mReport.ResultId, True);
    end;
  end;
end;

function TAtlasProblemsResults.CountsDue(const ASettings: TAtlasPluginSettings; out AShow: Boolean;
  out ACounts: TAtlasProblemCounts): Boolean;
begin
  AShow := TAtlasProblemsPlan.Active(ASettings) and TAtlasProblemsPlan.StatusCounter(ASettings);
  ACounts := Default(TAtlasProblemCounts);
  Result := TAtlasProblemsPlan.CountsDue(AShow, FCountsShown, FStore.Version, FCountsVersion);
  if not Result then
  begin
    Exit;
  end;
  FCountsShown := AShow;
  FCountsVersion := FStore.Version;
  if AShow then
  begin
    ACounts := CountsOf(FStore);
  end;
end;

function TAtlasProblemsResults.ProjectRun(out ARun: TLspWorkspaceRun; out AFinishedAgoMs: UInt64): Boolean;
begin
  ARun := FRun;
  AFinishedAgoMs := High(UInt64);
  if FRunFinishedAt > 0 then
  begin
    AFinishedAgoMs := TAtlasTicks.Since(FRunFinishedAt);
  end;
  Result := FRun.Known;
end;

class function TAtlasProblemsResults.CountsOf(AStore: TAtlasProblemStore): TAtlasProblemCounts;
var
  mFileName: string;
  mAll: TArray<TAtlasProblem>;
begin
  mAll := nil;
  if AStore <> nil then
  begin
    for mFileName in AStore.Files do
    begin
      mAll := mAll + AStore.ForFile(mFileName);
    end;
  end;
  Result := TAtlasInlineDiagnostics.Counts(mAll);
end;

{ TAtlasProblemsFlow }

function TAtlasProblemsFlow.Halted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := not TAtlasProblemsPlan.Active(ASettings);
  if Result then
  begin
    if FServer.Pulling then
    begin
      StopPulls;
    end;
    DropAll;
    Exit;
  end;
  FResults.Apply(ASettings);
  // Während des Debuggens ruht die Prüfung (#1241): keine Anfragen, keine Hintergrundprüfung; danach geht es weiter.
  Result := FEditors.Debugging;
  ReportDebugPause(Result);
  if Result and FServer.Pulling then
  begin
    StopPulls;
  end;
end;

procedure TAtlasProblemsFlow.DropAll;
begin
  FResults.Store.Clear;
  FTexts.Clear;
end;

procedure TAtlasProblemsFlow.ReportDebugPause(APaused: Boolean);
begin
  if (FDebugPauseSent = APaused) or (FServer.Connect(False) = 0) then
  begin
    Exit;
  end;
  FServer.PauseProjectCheck(APaused);
  FDebugPauseSent := APaused;
end;

procedure TAtlasProblemsFlow.CheckProjectsRemoved;
begin
  // Pull-Diagnosen melden weggefallene Dateien nie mehr, ihre Befunde blieben sonst im Speicher und im Fenster
  // „Atlas-Prüfung“.
  if (FServer.Connect(False) = 0) or (FServer.ProjectsRemoved = FProjectsRemoved) then
  begin
    Exit;
  end;
  FProjectsRemoved := FServer.ProjectsRemoved;
  FLog('Problems: projects removed, findings dropped, checking again');
  StopPulls;
  DropAll;
end;

procedure TAtlasProblemsFlow.PullRequestedFiles(const ASettings: TAtlasPluginSettings);
var
  mFiles: TArray<string>;
  mFile, mText: string;
  mPull: TAtlasProblemsPull;
  mPulls: TAtlasProblemsPulls;
begin
  mFiles := TAtlasProblemsCheckRequest.TakeFiles;
  if Length(mFiles) = 0 then
  begin
    Exit;
  end;
  if FServer.Connect(True) = 0 then
  begin
    FLog('Problems: requested check dropped, no server');
    Exit;
  end;
  EnsurePulls(ASettings);
  mPulls := nil;
  for mFile in mFiles do
  begin
    if not TAtlasProblemsPlan.IsSource(mFile) or not FEditors.ReadText(mFile, mText) then
    begin
      Continue;
    end;
    // Ungeöffnete Dateien schließt CloseUnopened später wieder; ihre Befunde liefert dann workspace/diagnostic.
    FServer.Sync(mFile, mText);
    FTexts.MarkPulled(mFile, mText);
    mPull := Default(TAtlasProblemsPull);
    mPull.FileName := mFile;
    mPull.Text := mText;
    mPull.ReplaceCompiler := not FResults.Store.Contains(mFile);
    mPulls := mPulls + [mPull];
  end;
  FServer.Pull(mPulls);
end;

procedure TAtlasProblemsFlow.EnsurePulls(const ASettings: TAtlasPluginSettings);
var
  mSession: Integer;
begin
  mSession := FServer.Connect(False);
  if (FSession <> 0) and (FSession <> mSession) then
  begin
    FServer.StopPulls;
  end;
  // Neue Sitzung, etwa nach einem Serverneustart (#393): Diagnosen aller Dateien neu holen.
  if FSession <> mSession then
  begin
    FTexts.ForgetPulled;
  end;
  // Andere Projektdateien nur für die Probleme; das Abblenden braucht nur geöffnete.
  FServer.StartPulls(TAtlasProblemsPlan.Shown(ASettings));
  FSession := mSession;
end;

procedure TAtlasProblemsFlow.Serve(const ASettings: TAtlasPluginSettings; const AEditor: TAtlasProblemsEditor);
begin
  EnsurePulls(ASettings);
  // Konfiguration oder Plattform gewechselt, Defines geändert (#615).
  FServer.UpdateTarget;
  SyncPrevious(AEditor.FileName);
  // Im Designer und auf der Willkommensseite nicht nachfragen; zurück im Code holt der nächste Takt den Stand.
  if AEditor.CodeInFront then
  begin
    PullIfDue(ASettings, AEditor);
  end;
  if TAtlasTicks.Since(FClosedCheckAt) >= cClosedCheckMs then
  begin
    FClosedCheckAt := TAtlasTicks.Now;
    CloseUnopened;
  end;
end;

procedure TAtlasProblemsFlow.SyncPrevious(const AFileName: string);
var
  mOtherText: string;
begin
  // Sonst fehlt eine neue Deklaration in der anderen Unit (Index nach der Tipp-Pause, #492).
  case TAtlasProblemsPlan.Switch(FLastFile, AFileName, FServer.Idle) of
    TAtlasProblemsSwitch.Remember:
      begin
        FLastFile := AFileName;
        Exit;
      end;
    TAtlasProblemsSwitch.Wait:
      Exit;
  else
    // SyncPrevious: unten.
  end;
  if FTexts.Seen(FLastFile, mOtherText) then
  begin
    FServer.Sync(FLastFile, mOtherText);
  end;
  FLastFile := AFileName;
end;

procedure TAtlasProblemsFlow.PullIfDue(const ASettings: TAtlasPluginSettings; const AEditor: TAtlasProblemsEditor);
var
  mRefresh, mChanged: Boolean;
  mPull: TAtlasProblemsPull;
  mPulls: TAtlasProblemsPulls;
begin
  mRefresh := FServer.RefreshCount <> FRefreshSeen;
  mChanged := PullDue(ASettings, AEditor.FileName, AEditor.Text, AEditor.Modified);
  if not (mRefresh or mChanged) or not FServer.Idle then
  begin
    Exit;
  end;
  TAtlasProblemsCheckRequest.Clear;
  FServer.Sync(AEditor.FileName, AEditor.Text);
  FTexts.MarkPulled(AEditor.FileName, AEditor.Text);
  mPull := Default(TAtlasProblemsPull);
  mPull.FileName := AEditor.FileName;
  mPull.Text := AEditor.Text;
  mPull.ReplaceCompiler := mRefresh or not FResults.Store.Contains(AEditor.FileName);
  if not mPull.ReplaceCompiler then
  begin
    mPull.PreviousId := FResults.Store.ResultId(AEditor.FileName);
  end;
  mPulls := TAtlasProblemsPulls.Create(mPull);
  if mRefresh then
  begin
    FRefreshSeen := FServer.RefreshCount;
    mPulls := mPulls + OtherPulls(AEditor.FileName);
  end;
  FServer.Pull(mPulls);
end;

function TAtlasProblemsFlow.PullDue(const ASettings: TAtlasPluginSettings; const AFileName, AText: string;
  AModified: Boolean): Boolean;
var
  mState: TAtlasProblemsRefreshState;
  mKnown: string;
begin
  mState := Default(TAtlasProblemsRefreshState);
  mState.CheckedBefore := FTexts.Pulled(AFileName, mKnown);
  mState.Changed := not mState.CheckedBefore or (mKnown <> AText);
  mState.Modified := AModified;
  mState.QuietMs := TAtlasTicks.SinceMs(FChangedAt);
  mState.Requested := TAtlasProblemsCheckRequest.Pending;
  // Kürzere Verzögerung als der Takt: öfter nachsehen.
  FTickMs := TAtlasProblemsRefresh.TickMs(ASettings.ProblemsLiveDelayMs);
  Result := TAtlasProblemsRefresh.Due(TAtlasProblemsUpdateSetting.Parse(ASettings.ProblemsUpdate), mState,
    ASettings.ProblemsLiveDelayMs);
end;

function TAtlasProblemsFlow.OtherPulls(const AFileName: string): TAtlasProblemsPulls;
var
  mOther, mOtherText: string;
  mPull: TAtlasProblemsPull;
begin
  Result := nil;
  for mOther in FServer.SyncedFiles do
  begin
    if not SameText(mOther, AFileName) and FServer.SyncedText(mOther, mOtherText) then
    begin
      mPull := Default(TAtlasProblemsPull);
      mPull.FileName := mOther;
      mPull.Text := mOtherText;
      mPull.ReplaceCompiler := True;
      Result := Result + [mPull];
    end;
  end;
end;

procedure TAtlasProblemsFlow.CloseUnopened;
var
  mFileName: string;
begin
  for mFileName in FServer.SyncedFiles do
  begin
    if not FEditors.IsOpen(mFileName) then
    begin
      FServer.Close(mFileName);
      FTexts.Forget(mFileName);
    end;
  end;
end;

constructor TAtlasProblemsFlow.Create(const AServer: IAtlasProblemsServer; const AEditors: IAtlasProblemsEditors;
  const ALog: TAtlasProblemsLogProc);
begin
  inherited Create;
  FServer := AServer;
  FEditors := AEditors;
  FLog := ALog;
  FTexts := TAtlasProblemsTexts.Create;
  FResults := TAtlasProblemsResults.Create(AEditors, FTexts, ALog);
  FTickMs := TAtlasProblemsRefresh.cMaxTickMs;
end;

destructor TAtlasProblemsFlow.Destroy;
begin
  FResults.Free;
  FTexts.Free;
  inherited Destroy;
end;

procedure TAtlasProblemsFlow.Tick(const ASettings: TAtlasPluginSettings);
var
  mEditor: TAtlasProblemsEditor;
begin
  FServer.Collect;
  if Halted(ASettings) then
  begin
    Exit;
  end;
  CheckProjectsRemoved;
  PullRequestedFiles(ASettings);
  // Ohne Fokus ändert sich der Puffer nur über Neuladen, das den Stand ohnehin als veraltet markiert.
  if not FEditors.ActiveEditor(mEditor) or not TAtlasProblemsPlan.IsSource(mEditor.FileName) then
  begin
    Exit;
  end;
  // Markierungen wandern mit, bevor neue Diagnosen da sind.
  if FTexts.Track(mEditor) then
  begin
    FResults.Store.Edit(mEditor.FileName, mEditor.Text);
    FChangedAt := TAtlasTicks.Now;
  end;
  if FServer.Connect(FRetryAt.Reached) = 0 then
  begin
    FRetryAt := TAtlasDeadline.After(cStartRetryMs);
    Exit;
  end;
  Serve(ASettings, mEditor);
end;

procedure TAtlasProblemsFlow.StopPulls;
begin
  FServer.StopPulls;
  FSession := 0;
end;

procedure TAtlasProblemsFlow.Stopped;
begin
  FTexts.ForgetPulled;
  FRefreshSeen := 0;
end;

function TAtlasProblemsFlow.Checking: Boolean;
begin
  Result := not FServer.Idle;
end;

end.
