unit Atlas.IDE.CodeInsight.Composition.Session;

// Code Insight-Manager der Kompositionswurzel und was alle Teile über ihn brauchen: Sitzungen, Serverbefehle,
// Zeilen in der Meldungsansicht und im Protokoll, Fehlerbericht (#108), „Issue anlegen“ über das Modul Tracker
// (#1268, #1355) und Befehle anderer Module (#1455). Die übrigen Teile der Wurzel fragen den Manager nur hier.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.CrashCases,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Status.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.IDE.Commands.Palette,
  Atlas.IDE.CodeInsight.Manager;

/// <summary>Code Insight-Manager von Atlas; nil, solange er nicht angemeldet ist.</summary>
function Manager: TAtlasCodeInsightManager;
/// <summary>Manager bei der IDE anmelden (Teil „Manager“ der Feature-Tabelle).</summary>
procedure StartManager;
/// <summary>Manager abmelden und abbauen, auch wenn die IDE ihn noch hält (#886).</summary>
procedure StopManager;
/// <summary>Ist der Manager bei der IDE angemeldet?</summary>
function ManagerStarted: Boolean;
/// <summary>Aktive Sitzung (startet den Server bei Bedarf); nil ohne Manager.</summary>
function ActiveSession: TLspSession;
/// <summary>Laufende Sitzung (startet keinen Server); nil ohne.</summary>
function RunningSession: TLspSession;
/// <summary>Zustand des Servers; leer ohne Manager.</summary>
function ServerInfo: TAtlasServerInfo;
/// <summary>Indexiert der Server gerade (APercent -1 = unbekannt)? False ohne Manager.</summary>
function ServerIndexing(out APercent: Integer): Boolean;
/// <summary>Pfad des Servers nach den Einstellungen.</summary>
function ServerPath: string;
/// <summary>Zeile ins Diagnoseprotokoll des Managers; ohne Manager nichts.</summary>
procedure LogLine(const AText: string);
/// <summary>Bericht an den Manager (Protokoll und Statuszeile); ohne Manager nichts.</summary>
procedure ReportLine(const AText: string);
/// <summary>Warnung der Sicherung (#493): Meldungsansicht und Plugin-Protokoll, nie als Dialog.</summary>
procedure GuardWarning(const AText: string);
/// <summary>Zeile in der Meldungsansicht, ohne Plugin-Protokoll (z. B. Hinweis auf eine neue Version, #495).</summary>
procedure MessageLine(const AText: string);
/// <summary>Meldungsansicht mit der Gruppe Atlas nach vorn holen: für Ergebnisse eines Befehls, den der Benutzer
/// gerade ausgelöst hat (sonst sieht es aus, als passiere nichts).</summary>
procedure ShowAtlasMessages;
/// <summary>GuardWarning als Methodenreferenz für die Haken der Features.</summary>
function Warnings: TProc<string>;
/// <summary>MessageLine als Methodenreferenz für die Haken der Features.</summary>
function MessageLines: TProc<string>;
/// <summary>ReportLine als Methodenreferenz für die Haken der Features.</summary>
function Reports: TProc<string>;
/// <summary>LogLine als Methodenreferenz für die Haken der Features.</summary>
function LogLines: TProc<string>;
/// <summary>Zeile ins Protokoll der Sicherung (atlas.log) als Methodenreferenz.</summary>
function GuardLogs: TProc<string>;
/// <summary>Serverbefehl im Hintergrund (#874), der Server antwortet auch während des Indexierens; ohne Manager
/// gleich ADone(nil).</summary>
procedure RunServerCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
  const ADone: TProc<TJSONValue>);
/// <summary>Befehl ohne Argumente an den Server (Menü, Optionsseite); ohne Manager gleich ADone(nil).</summary>
procedure ExecuteServerCommand(const ACommand: string; const ADone: TProc<TJSONValue>);
/// <summary>Antwort als JSON-Text an ADone ('' ohne Antwort); der Manager gibt den Wert nach dem Aufruf frei.
/// </summary>
function AnswerText(const ADone: TProc<string>): TProc<TJSONValue>;
/// <summary>Datei im Editor öffnen, wenn es sie gibt.</summary>
procedure OpenInEditor(const AFileName: string);
/// <summary>„Protokoll öffnen“ (#591): Diagnoseprotokoll, sonst das Protokoll der Sicherung.</summary>
procedure OpenLog;
/// <summary>„Fehlerbericht erstellen…“ (#108) aus Menü, Palette und dem Fenster des abgesicherten Starts.</summary>
procedure CreateBugReport;
/// <summary>„Issue anlegen“ zu einem Absturzfall des Servers (#1355): Dialog aus #1268, danach die Dateien des
/// Falls über „An Issue anhängen“ (#1276). Ohne Tracker bzw. mit issues.create aus nur eine Zeile mit dem Ordner.
/// </summary>
procedure CreateCrashIssue(ACase: TAtlasCrashCase);
/// <summary>Befunde des Fensters „Atlas-Prüfung“ für „Issue anlegen“: Regel, Meldung, Fundstelle und Zeile.
/// </summary>
function IssueFindings(const AFindings: TArray<TAtlasFinding>): TArray<TAtlasIssueFinding>;
/// <summary>„Für diesen Befund ein Issue anlegen …“ (#1268) über das Modul Tracker; ohne Modul nichts.</summary>
procedure CreateIssueFromFindings(const AFindings: TArray<TAtlasIssueFinding>);
/// <summary>Kann das Modul Tracker gerade ein Issue anlegen?</summary>
function CanCreateIssue: Boolean;
/// <summary>Befehl AId eines laufenden Moduls ausführen (Base kennt die Module nicht, Regel 9); ohne Modul nichts.
/// </summary>
procedure RunModuleCommand(const AId: string);
/// <summary>Tests ausführen über das Modul Tests (#69, #1455); ohne Modul der Hinweis, dass die Tests aus sind.
/// </summary>
procedure RunTestsOfModule(const AFileName: string; const ATests: TArray<string>);
/// <summary>AProc abgesichert je Feature (#493).</summary>
function Guarded(AFeature: TAtlasFeature; const AProc: TProc): TProc;
/// <summary>Befehl der Palette mit dem Text ATextId.</summary>
procedure AddCommand(APalette: TAtlasIdePalette; const AId: string; ATextId: TAtlasTextId; const AProc: TProc);
  overload;
/// <summary>Befehl der Palette, nur sichtbar, solange AVisible True liefert (#520).</summary>
procedure AddCommand(APalette: TAtlasIdePalette; const AId: string; ATextId: TAtlasTextId; const AProc: TProc;
  const AVisible: TFunc<Boolean>); overload;

implementation

uses
  Atlas.IDE.CodeInsight.Manager.Paths,
  ToolsAPI,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Diagnostics.BugReport,
  Atlas.IDE.CodeInsight.Composition.Adapters;

const
  cMessageGroup = 'Atlas';

var
  ManagerIndex: Integer = -1;
  // Gehört der IDE (Schnittstellenzähler); gültig, solange er angemeldet ist.
  ManagerInstance: TAtlasCodeInsightManager;
  // Eigene Referenz (#886): StopManager baut den Manager selbst ab, auch wenn die IDE ihn noch hält.
  ManagerRef: IInterface;

function Manager: TAtlasCodeInsightManager;
begin
  Result := ManagerInstance;
end;

procedure StartManager;
var
  mServices: IOTACodeInsightServices;
begin
  if Supports(BorlandIDEServices, IOTACodeInsightServices, mServices) then
  begin
    ManagerInstance := TAtlasCodeInsightManager.Create(CodeInsightAdapters);
    ManagerRef := ManagerInstance;
    // „Protokoll öffnen“ an den Einträgen des Servers in der Benachrichtigungszentrale (#601).
    ManagerInstance.OnOpenLog := OpenLog;
    // Nach zwei gleichen Abstürzen des Servers bietet die Meldung den Fehlerbericht an (Bericht H5).
    ManagerInstance.OnBugReport := CreateBugReport;
    // Absturzfälle des Servers (#1355): „Issue anlegen“ in der Meldung.
    ManagerInstance.OnCrashIssue := CreateCrashIssue;
    ManagerIndex := mServices.AddCodeInsightManager(ManagerInstance);
  end;
end;

procedure StopManager;
var
  mServices: IOTACodeInsightServices;
begin
  try
    if (ManagerIndex >= 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, mServices) then
    begin
      mServices.RemoveCodeInsightManager(ManagerIndex);
    end;
    ManagerIndex := -1;
    if ManagerInstance <> nil then
    begin
      // Nicht auf Destroy warten (#886): Hält die IDE den Manager noch (etwa wenn sie Atlas mitten im
      // Gruppen-Build entlädt), liefen sonst Sitzung, Server, Threads und Editor-Anbindungen nach dem Entladen weiter.
      ManagerInstance.Shutdown;
      if ManagerInstance.RefCount > 1 then
      begin
        TAtlasGuard.Log(Format('Code-Insight-Manager wird nach dem Abmelden noch %d-mal von der IDE gehalten',
          [ManagerInstance.RefCount - 1]));
      end;
    end;
  finally
    ManagerInstance := nil;
    ManagerRef := nil;
  end;
end;

function ManagerStarted: Boolean;
begin
  Result := ManagerIndex >= 0;
end;

function ActiveSession: TLspSession;
begin
  Result := nil;
  if ManagerInstance <> nil then
  begin
    Result := ManagerInstance.ActiveSession;
  end;
end;

function RunningSession: TLspSession;
begin
  Result := nil;
  if ManagerInstance <> nil then
  begin
    Result := ManagerInstance.RunningSession;
  end;
end;

function ServerInfo: TAtlasServerInfo;
begin
  Result := Default(TAtlasServerInfo);
  if ManagerInstance <> nil then
  begin
    Result := ManagerInstance.ServerInfo;
  end;
end;

function ServerIndexing(out APercent: Integer): Boolean;
begin
  APercent := -1;
  Result := (ManagerInstance <> nil) and ManagerInstance.ServerIndexing(APercent);
end;

function ServerPath: string;
var
  mArguments: string;
begin
  Result := TAtlasCodeInsightPaths.ServerPath(mArguments);
end;

procedure LogLine(const AText: string);
begin
  if ManagerInstance <> nil then
  begin
    ManagerInstance.Log(AText);
  end;
end;

procedure ReportLine(const AText: string);
begin
  if ManagerInstance <> nil then
  begin
    ManagerInstance.Report(AText);
  end;
end;

/// <summary>Gruppe Atlas der Meldungsansicht, bei Bedarf angelegt; False ohne Meldungsansicht.</summary>
function MessageGroup(out AMessages: IOTAMessageServices; out AGroup: IOTAMessageGroup): Boolean;
begin
  AGroup := nil;
  Result := Supports(BorlandIDEServices, IOTAMessageServices, AMessages);
  if not Result then
  begin
    Exit;
  end;
  AGroup := AMessages.GetGroup(cMessageGroup);
  if AGroup = nil then
  begin
    AGroup := AMessages.AddMessageGroup(cMessageGroup);
  end;
end;

procedure GuardWarning(const AText: string);
begin
  ReportLine(AText);
  MessageLine(AText);
end;

procedure MessageLine(const AText: string);
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
begin
  if MessageGroup(mMessages, mGroup) then
  begin
    mMessages.AddTitleMessage(AText, mGroup);
  end;
end;

procedure ShowAtlasMessages;
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mGroup := mMessages.GetGroup(cMessageGroup);
  if mGroup <> nil then
  begin
    mMessages.ShowMessageView(mGroup);
  end;
end;

function Warnings: TProc<string>;
begin
  Result :=
    procedure(AText: string)
    begin
      GuardWarning(AText);
    end;
end;

function MessageLines: TProc<string>;
begin
  Result :=
    procedure(AText: string)
    begin
      MessageLine(AText);
    end;
end;

function Reports: TProc<string>;
begin
  Result :=
    procedure(AText: string)
    begin
      ReportLine(AText);
    end;
end;

function LogLines: TProc<string>;
begin
  Result :=
    procedure(AText: string)
    begin
      LogLine(AText);
    end;
end;

function GuardLogs: TProc<string>;
begin
  Result :=
    procedure(AText: string)
    begin
      TAtlasGuard.Log(AText);
    end;
end;

procedure RunServerCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
  const ADone: TProc<TJSONValue>);
begin
  if ManagerInstance <> nil then
  begin
    ManagerInstance.RunServerCommandAsync(ACommand, AArgumentsJson, ATimeoutMs, ADone);
  end
  else if Assigned(ADone) then
  begin
    ADone(nil);
  end;
end;

procedure ExecuteServerCommand(const ACommand: string; const ADone: TProc<TJSONValue>);
begin
  if ManagerInstance <> nil then
  begin
    ManagerInstance.ExecuteServerCommandAsync(ACommand, 30000, ADone);
  end
  else if Assigned(ADone) then
  begin
    ADone(nil);
  end;
end;

function AnswerText(const ADone: TProc<string>): TProc<TJSONValue>;
begin
  Result :=
    procedure(AValue: TJSONValue)
    begin
      if AValue = nil then
      begin
        ADone('');
      end
      else
      begin
        ADone(AValue.ToJSON([]));
      end;
    end;
end;

procedure OpenInEditor(const AFileName: string);
var
  mActions: IOTAActionServices;
begin
  if (AFileName <> '') and FileExists(AFileName) and Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    mActions.OpenFile(AFileName);
  end;
end;

procedure OpenLog;
var
  mFileName: string;
begin
  mFileName := TAtlasCodeInsightPaths.DiagnoseLog;
  if not FileExists(mFileName) and (TAtlasGuard.RotatingLog <> nil) then
  begin
    mFileName := TAtlasGuard.RotatingLog.FileName;
  end;
  OpenInEditor(mFileName);
end;

procedure CreateBugReport;
begin
  TAtlasIdeBugReport.Execute(
    procedure(const ACommand, AArgumentsJson: string; const ADone: TProc<TJSONValue>)
    begin
      // Im Hintergrund (#874): Der Server antwortet auch während des Indexierens sofort, das Plugin wartet nicht.
      RunServerCommand(ACommand, AArgumentsJson, 10000, ADone);
    end,
    Warnings());
end;

/// <summary>„Issue anlegen“ des Moduls Tracker (#1268, #1455); False ohne laufendes Modul.</summary>
function IssueCreation(out ACreation: IAtlasIssueCreation): Boolean;
var
  mItem: IInterface;
begin
  ACreation := nil;
  Result := False;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasIssueCreation) do
  begin
    if Supports(mItem, IAtlasIssueCreation, ACreation) then
    begin
      Result := True;
      Break;
    end;
  end;
end;

function IssueFindings(const AFindings: TArray<TAtlasFinding>): TArray<TAtlasIssueFinding>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AFindings));
  for mIndex := 0 to High(AFindings) do
  begin
    Result[mIndex].Rule := AFindings[mIndex].Rule;
    Result[mIndex].Message := AFindings[mIndex].MessageText(TAtlasIdeSettings.Current.ProblemsShowCompilerCode);
    Result[mIndex].Location := AFindings[mIndex].Location;
    Result[mIndex].LineText := AFindings[mIndex].LineText;
  end;
end;

procedure CreateIssueFromFindings(const AFindings: TArray<TAtlasIssueFinding>);
var
  mCreation: IAtlasIssueCreation;
begin
  if IssueCreation(mCreation) then
  begin
    mCreation.FromFindings(AFindings);
  end;
end;

function CanCreateIssue: Boolean;
var
  mCreation: IAtlasIssueCreation;
begin
  Result := IssueCreation(mCreation) and mCreation.Enabled;
end;

procedure CreateCrashIssue(ACase: TAtlasCrashCase);
var
  mFiles: TArray<TAtlasIssueTextFile>;
  mCaseFiles: TArray<TAtlasCrashCaseFile>;
  mIndex: Integer;
  mCreation: IAtlasIssueCreation;
begin
  if not IssueCreation(mCreation) or not mCreation.Enabled then
  begin
    MessageLine(TAtlasStrings.Text(TAtlasTextId.CrashCaseTitle) + ': ' + ACase.Folder);
    Exit;
  end;
  mCaseFiles := TAtlasCrashCases.AttachFiles(ACase.Folder);
  SetLength(mFiles, Length(mCaseFiles));
  for mIndex := 0 to High(mCaseFiles) do
  begin
    mFiles[mIndex].Name := mCaseFiles[mIndex].Name;
    mFiles[mIndex].Text := mCaseFiles[mIndex].Text;
  end;
  mCreation.FromCrash(TAtlasCrashCases.IssueTitle(ACase), TAtlasCrashCases.IssueDescription(ACase), mFiles);
end;

procedure RunModuleCommand(const AId: string);
var
  mCommand: TAtlasModuleCommand;
begin
  if TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, AId, mCommand) and Assigned(mCommand.Run) and
    TAtlasModuleContributions.IsVisible(mCommand) then
  begin
    TAtlasGuard.Run(TAtlasFeature.EditorCommands, mCommand.Run);
  end;
end;

/// <summary>Testläufer des Moduls Tests (#69, #1455); False ohne laufendes Modul.</summary>
function TestRunner(out ARunner: IAtlasTestRunner): Boolean;
var
  mItem: IInterface;
begin
  ARunner := nil;
  Result := False;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasTestRunner) do
  begin
    if Supports(mItem, IAtlasTestRunner, ARunner) then
    begin
      Result := True;
      Break;
    end;
  end;
end;

procedure RunTestsOfModule(const AFileName: string; const ATests: TArray<string>);
var
  mRunner: IAtlasTestRunner;
begin
  if TestRunner(mRunner) then
  begin
    mRunner.RunTests(AFileName, ATests);
  end
  else
  begin
    GuardWarning(TAtlasStrings.Text(TAtlasTextId.TestsRunOff));
  end;
end;

function Guarded(AFeature: TAtlasFeature; const AProc: TProc): TProc;
var
  mFeature: TAtlasFeature;
  mProc: TProc;
begin
  mFeature := AFeature;
  mProc := AProc;
  Result :=
    procedure
    begin
      TAtlasGuard.Run(mFeature, mProc);
    end;
end;

procedure AddCommand(APalette: TAtlasIdePalette; const AId: string; ATextId: TAtlasTextId; const AProc: TProc);
begin
  APalette.RegisterCommand(AId, TAtlasStrings.Text(ATextId), '', AProc);
end;

procedure AddCommand(APalette: TAtlasIdePalette; const AId: string; ATextId: TAtlasTextId; const AProc: TProc;
  const AVisible: TFunc<Boolean>);
begin
  APalette.RegisterCommand(AId, TAtlasStrings.Text(ATextId), '', AProc, AVisible);
end;

end.
