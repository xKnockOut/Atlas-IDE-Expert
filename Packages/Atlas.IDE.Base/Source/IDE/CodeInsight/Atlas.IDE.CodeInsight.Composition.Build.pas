unit Atlas.IDE.CodeInsight.Composition.Build;

// Compile-Ereignisse (#527) mit den Compilermeldungen an den Server (#528), Bewertung eines Builds (#530) an die
// Benachrichtigungszentrale (#601), Prüfung beim Speichern (#548), Projekt-Zusammenfassungen (#592) und
// Code-Metriken, TODOs und Baseline nach einem Build (#66, #68, #97, #758) sowie der Metrikbericht (#66).

interface

uses
  Atlas.IDE.Build.Notifier,
  Atlas.IDE.Build.CheckOnSave;

/// <summary>Compile-Ereignisse; nil, solange sie nicht angemeldet sind.</summary>
function Compile: TAtlasIdeCompileEvents;
/// <summary>Prüfung beim Speichern (#548); nil ohne.</summary>
function CheckOnSave: TAtlasIdeCheckOnSave;
/// <summary>Compile-Ereignisse samt Meldungsleser, letzten Meldungen und Bewertung anmelden.</summary>
procedure RegisterCompileEvents;
/// <summary>Bewertung abmelden, Compile-Ereignisse und letzte Meldungen freigeben.</summary>
procedure UnregisterCompileEvents;
function CompileStarted: Boolean;
procedure StartCheckOnSave;
procedure StopCheckOnSave;
function CheckOnSaveStarted: Boolean;
/// <summary>Projekt-Zusammenfassungen (#592, #1455): schreibt Base, auch ohne Willkommensseite.</summary>
procedure StartProjectSummaries;
procedure StopProjectSummaries;
function ProjectSummariesStarted: Boolean;
/// <summary>Metrikbericht des aktiven Projekts (#66): Markdown vom Server (startet ihn bei Bedarf) im
/// Hintergrund, gespeichert unter %LOCALAPPDATA%\Atlas\Berichte und im Editor geöffnet.</summary>
procedure MetricsReport;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.IOUtils,
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Pipeline,
  Atlas.Core.Build.Verdict,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Editor.Metrics,
  Atlas.Core.Projects.Baseline,
  Atlas.Core.Problems.Store,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Build.MessageView,
  Atlas.IDE.Build.LastMessages,
  Atlas.IDE.Projects.Summaries,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Status;

const
  cMetricsCommand = 'atlas.server.metrics';
  cTodosCommand = 'atlas.server.todos';

type
  /// <summary>Bewertung eines Builds (#530) aus dem Modul Build-Pipeline bzw. nur nach dem Compiler (Modul aus) an
  /// die Benachrichtigungszentrale (#601).</summary>
  TNotificationsVerdictListener = class(TInterfacedObject, IAtlasBuildVerdictListener)
  public
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
  end;

var
  CompileInstance: TAtlasIdeCompileEvents;
  CheckOnSaveInstance: TAtlasIdeCheckOnSave;
  // Meldungen des letzten Builds je Projekt (#530) für Atlas.CompilerBaseline; lebt mit den Compile-Ereignissen.
  LastBuildMessages: TAtlasIdeLastBuildMessages;
  // Bewertung eines Builds (#530) an die Benachrichtigungszentrale (#601); lebt mit den Compile-Ereignissen.
  NotificationsVerdict: IAtlasRegistration;
  // Projekt-Zusammenfassungen (#592, #1455).
  ProjectSummaries: TAtlasIdeProjectSummaries;

function Compile: TAtlasIdeCompileEvents;
begin
  Result := CompileInstance;
end;

function CheckOnSave: TAtlasIdeCheckOnSave;
begin
  Result := CheckOnSaveInstance;
end;

procedure TNotificationsVerdictListener.BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mProject: TAtlasCompileProject;
  mVerdict: TAtlasBuildVerdict;
begin
  if Notifications = nil then
  begin
    Exit;
  end;
  mMessages := AMessages;
  mProject := AProject;
  mVerdict := AVerdict;
  TAtlasGuard.Run(TAtlasFeature.Notifications,
    procedure
    begin
      Notifications.BuildEvaluated(mMessages, mProject, mVerdict);
    end);
end;

function MetricsArguments(const AProject, AMode: string): string;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TLspSession.PathToUri(AProject));
    mArguments.Add(AMode);
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

/// <summary>Antworten von Metriken, TODOs und Stand der Baseline in die Projekt-Zusammenfassung (Hauptthread).
/// </summary>
procedure RecordAnswers(const AProject: string; const AAnswers: TArray<string>; const ABaseline: TAtlasBaselineState;
  AStamp: TDateTime);
begin
  if TAtlasIdeProjectSummaries.Current = nil then
  begin
    Exit;
  end;
  // Leere oder ungültige Antworten lassen die Zusammenfassung unverändert.
  TAtlasIdeProjectSummaries.Current.RecordMetrics(AProject, AAnswers[0], AStamp);
  TAtlasIdeProjectSummaries.Current.RecordTodos(AProject, AAnswers[1], AStamp);
  TAtlasIdeProjectSummaries.Current.RecordBaseline(AProject, ABaseline, AStamp);
end;

/// <summary>Code-Metriken (#66), TODO-Übersicht (#68) und Stand der Baseline (#97) nach einem Build für die
/// Projekt-Zusammenfassung (Projektverlauf #758, Einrichtung #759): in einem Hintergrundlauf vom laufenden Server
/// (startet ihn nicht), Zeitpunkt AStampUtc der des Builds: Damit kommen die Werte in seinen Messpunkt.</summary>
procedure RecordProjectMetrics(const AProject: string; AStampUtc: TDateTime);
var
  mProject: string;
  mStamp: TDateTime;
begin
  if (Manager = nil) or (TAtlasIdeProjectSummaries.Current = nil) or (AProject = '') or
    not TAtlasIdeSettings.Current.Enabled then
  begin
    Exit;
  end;
  mProject := AProject;
  mStamp := AStampUtc;
  Manager.RunCommandsAsync([cMetricsCommand, cTodosCommand],
    [MetricsArguments(mProject, 'summary'), MetricsArguments(mProject, 'summary')], 60000,
    procedure(AAnswers: TArray<string>)
    var
      mAnswers: TArray<string>;
      mBaseline: TAtlasBaselineState;
    begin
      mAnswers := AAnswers;
      // Die Baseline-Datei hier im Hintergrund lesen: Bei Altprojekten prüft das viele Pfade.
      mBaseline := TAtlasProjectBaselines.StateOnDisk(ExtractFileDir(mProject));
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          TAtlasGuard.Run(TAtlasFeature.WelcomePage,
            procedure
            begin
              RecordAnswers(mProject, mAnswers, mBaseline, mStamp);
            end);
        end);
    end);
end;

/// <summary>Bericht als Datei schreiben und im Editor öffnen (Hauptthread).</summary>
procedure WriteMetricsReport(const AAnswer, AFileName: string);
var
  mText: string;
begin
  if not TAtlasMetricsReportFile.MarkdownFrom(AAnswer, mText) then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.MetricsReportFailed));
    Exit;
  end;
  ForceDirectories(ExtractFileDir(AFileName));
  TFile.WriteAllText(AFileName, mText, TEncoding.UTF8);
  OpenInEditor(AFileName);
end;

/// <summary>Antwort des Metrikberichts in den Hauptthread und dort abgesichert schreiben.</summary>
function MetricsReportDone(const AFileName: string): TProc<string>;
var
  mFileName: string;
begin
  mFileName := AFileName;
  Result :=
    procedure(AAnswer: string)
    var
      mAnswer: string;
    begin
      mAnswer := AAnswer;
      TAtlasMainThread.Queue(TAtlasFeature.Menu,
        procedure
        begin
          TAtlasGuard.Run(TAtlasFeature.Palette,
            procedure
            begin
              WriteMetricsReport(mAnswer, mFileName);
            end);
        end);
    end;
end;

procedure MetricsReport;
var
  mProject: IOTAProject;
  mFileName: string;
begin
  // Abgeschaltet: auch über Tastenkürzel oder „Ausprobieren“ nichts tun.
  if (Manager = nil) or not TAtlasIdeSettings.Current.MetricsReport then
  begin
    Exit;
  end;
  mProject := GetActiveProject;
  if (mProject = nil) or (mProject.FileName = '') then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.MetricsReportNoProject));
    Exit;
  end;
  mFileName := TAtlasMetricsReportFile.FileName(
    TAtlasMetricsReportFile.Folder(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas')), mProject.FileName);
  if Manager.ActiveSession = nil then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.MetricsReportFailed));
    Exit;
  end;
  if Manager.RunCommandAsync(cMetricsCommand, MetricsArguments(mProject.FileName, 'markdown'), 120000,
    MetricsReportDone(mFileName)) then
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.MetricsReportRunning));
  end
  else
  begin
    // Ein Befehl im Hintergrund läuft schon (etwa die Metriken nach einem Build): später noch einmal.
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.MetricsReportBusy));
  end;
end;

/// <summary>Build des Benutzers mit lesbaren Meldungen (#530): Meldungen merken, dann bewerten lassen. Übernimmt das
/// Modul Build-Pipeline die Bewertung nicht (aus), bewertet Base nur nach dem Compiler; die Folgen
/// (Benachrichtigung, Tests nach dem Build) gehen in beiden Fällen an jeden IAtlasBuildVerdictListener.</summary>
procedure EvaluateBuild(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
  ASucceeded: Boolean);
var
  mFailures: TArray<string>;
  mFailure: string;
begin
  if LastBuildMessages <> nil then
  begin
    LastBuildMessages.Remember(AProject.FileName, AMessages);
  end;
  if not TAtlasBuildPipeline.Evaluate(AMessages, AProject, ASucceeded, mFailures) then
  begin
    mFailures := mFailures + TAtlasBuildPipeline.Announce(AMessages, AProject,
      TAtlasBuildPipeline.CompilerVerdict(AMessages, ASucceeded));
  end;
  for mFailure in mFailures do
  begin
    TAtlasGuard.Log('Bewertung des Builds: ' + mFailure);
  end;
end;

/// <summary>Dateien, die die IDE kennt: offene Module und die Module des Projekts (für Meldungen ohne Pfad).</summary>
function KnownFiles(const AProjectFile: string): TArray<string>;
var
  mModules: IOTAModuleServices;
  mProject: IOTAProject;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  for mIndex := 0 to mModules.ModuleCount - 1 do
  begin
    Result := Result + [mModules.Modules[mIndex].FileName];
  end;
  if (AProjectFile <> '') and Supports(mModules.FindModule(AProjectFile), IOTAProject, mProject) then
  begin
    for mIndex := 0 to mProject.GetModuleCount - 1 do
    begin
      if mProject.GetModule(mIndex).FileName <> '' then
      begin
        Result := Result + [mProject.GetModule(mIndex).FileName];
      end;
    end;
  end;
end;

/// <summary>Projekt-Zusammenfassung (#592, Base): letzter Build bzw. letzte Hintergrundprüfung; nach einem Build
/// auch Code-Metriken und TODOs (#66, #68, #758), nicht nach einer Hintergrundprüfung.</summary>
procedure RecordBuild(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
  ASucceeded, AReadable: Boolean);
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mProject: TAtlasCompileProject;
  mSucceeded, mReadable: Boolean;
  mStamp: TDateTime;
begin
  mMessages := AMessages;
  mProject := AProject;
  mSucceeded := ASucceeded;
  mReadable := AReadable;
  // Ein Zeitpunkt je Build: Metriken, TODOs und Baseline kommen damit in den Messpunkt des Builds (#758).
  mStamp := TAtlasIdeProjectSummaries.StampUtc;
  if TAtlasIdeProjectSummaries.Current <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        TAtlasIdeProjectSummaries.Current.Recorded(mMessages, mProject, mSucceeded, mReadable, mStamp);
      end);
  end;
  if AReadable and not AProject.Background then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        RecordProjectMetrics(mProject.FileName, mStamp);
      end);
  end;
end;

/// <summary>Build des Benutzers mit lesbaren Meldungen (#530): erst bewerten (Modul Build-Pipeline: Basislinie,
/// build.zeroHints, build.warningsAsErrors, Zusammenfassung), dann Benachrichtigung (#601) und Tests nach dem Build
/// (#69). Hintergrundprüfung bzw. Build ohne lesbare Meldungen: Eintrag in der Benachrichtigungszentrale.</summary>
procedure FollowBuild(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
  ASucceeded, AReadable: Boolean);
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mProject: TAtlasCompileProject;
  mSucceeded, mReadable: Boolean;
begin
  mMessages := AMessages;
  mProject := AProject;
  mSucceeded := ASucceeded;
  mReadable := AReadable;
  if AReadable and not AProject.Background then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        EvaluateBuild(mMessages, mProject, mSucceeded);
      end);
  end
  else if Notifications <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Notifications,
      procedure
      begin
        Notifications.BuildFinished(mMessages, mProject, mSucceeded, mReadable);
      end);
  end;
end;

/// <summary>Meldungen ins Diagnoseprotokoll und an den Server (#528).</summary>
procedure SendMessages(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
  ASucceeded: Boolean; const AInfo: string);
begin
  if Manager = nil then
  begin
    Exit;
  end;
  if Length(AMessages) > 0 then
  begin
    Manager.Report(Format('Meldungsfenster: %s (z. B. %s, Zeile %d)', [AInfo, AMessages[0].FileName,
      AMessages[0].Line]));
  end
  else
  begin
    Manager.Report('Meldungsfenster: ' + AInfo);
  end;
  Manager.NotifyServer('atlas/compilerMessages',
    TAtlasCompilerMessages.ToJson(AMessages, AProject.FileName, AProject.Platform, ASucceeded, AProject.Background));
end;

/// <summary>Compilermeldungen aus dem Reiter „Build“ (#528): Zusammenfassung, Module, Bewertung und Server.
/// </summary>
procedure MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
  ASucceeded: Boolean; const AInfo: string; AReadable: Boolean);
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mFailure: string;
begin
  mMessages := TAtlasCompilerMessages.Resolve(AMessages, AProject.FileName, KnownFiles(AProject.FileName));
  RecordBuild(mMessages, AProject, ASucceeded, AReadable);
  // Gelesene Meldungen an die Module, etwa die Builds auf Auftrag (#261) der Build-Pipeline.
  for mFailure in TAtlasBuildPipeline.MessagesRead(mMessages, AProject) do
  begin
    TAtlasGuard.Log('Compilermeldungen: ' + mFailure);
  end;
  FollowBuild(mMessages, AProject, ASucceeded, AReadable);
  SendMessages(mMessages, AProject, ASucceeded, AInfo);
end;

procedure RegisterCompileEvents;
var
  mEvents: TAtlasCompileEvents;
begin
  mEvents := TAtlasCompileEvents.Create;
  mEvents.OnNotify :=
    procedure(const AMethod: string; AParams: TJSONObject)
    begin
      if Manager <> nil then
      begin
        Manager.NotifyServer(AMethod, AParams);
      end
      else
      begin
        AParams.Free;
      end;
    end;
  mEvents.OnLog := LogLine;
  mEvents.Add(TAtlasCompileLog.Create(mEvents, LogLine));
  // Release-Build-Wächter (#533), Prüfung vor dem Kompilieren (#529) und Läufer der Builds auf Auftrag (#261)
  // meldet das Modul Build-Pipeline an und ab, die Projektaufgaben vor dem Build (#900) das Modul Build (#1455).
  // Compilermeldungen aus dem Reiter „Build“ an den Server (#528).
  mEvents.Add(TAtlasMessageViewReader.Create(MessagesRead));
  CompileInstance := TAtlasIdeCompileEvents.Create(mEvents);
  LastBuildMessages := TAtlasIdeLastBuildMessages.Create;
  NotificationsVerdict := AtlasModuleRegistry.Provide(IAtlasBuildVerdictListener,
    TNotificationsVerdictListener.Create as IAtlasBuildVerdictListener);
end;

procedure UnregisterCompileEvents;
begin
  // Läufer, Wächter und Prüfung (Modul Build-Pipeline) und Bauen beim Öffnen (Modul Build) stoppen mit ihren
  // Modulen vorher.
  if NotificationsVerdict <> nil then
  begin
    NotificationsVerdict.Revoke;
  end;
  NotificationsVerdict := nil;
  FreeAndNil(CompileInstance);
  FreeAndNil(LastBuildMessages);
end;

function CompileStarted: Boolean;
begin
  Result := CompileInstance <> nil;
end;

procedure StartCheckOnSave;
begin
  CheckOnSaveInstance := TAtlasIdeCheckOnSave.Create(CompileInstance.Events, Reports());
end;

procedure StopCheckOnSave;
begin
  FreeAndNil(CheckOnSaveInstance);
end;

function CheckOnSaveStarted: Boolean;
begin
  Result := CheckOnSaveInstance <> nil;
end;

procedure StartProjectSummaries;
begin
  ProjectSummaries := TAtlasIdeProjectSummaries.Create(
    function: TAtlasProblemStore
    begin
      Result := TAtlasProblemsController.Current;
    end);
  ProjectSummaries.Start;
end;

procedure StopProjectSummaries;
begin
  FreeAndNil(ProjectSummaries);
end;

function ProjectSummariesStarted: Boolean;
begin
  Result := ProjectSummaries <> nil;
end;

end.
