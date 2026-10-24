unit Atlas.IDE.CodeInsight.Manager;

// Code Insight-Manager für Delphi in RAD Studio (ADR 0006). Die IDE ruft ihn
// direkt auf; er fragt Atlas über eine eigene LSP-Sitzung.
// Umgesetzt: Symbolhinweis (Hover, GetHintText), Browse (Strg+Klick,
// GotoDefinition), Help Insight (leer, solange der Atlas-Tooltip an ist) und
// Vervollständigung im eigenen Popup (#410): Strg+Leer und "." lösen sie aus,
// InvokeCodeCompletion öffnet das Popup und meldet der IDE False, damit sie
// keine eigene Liste zeigt (#407). Parameterhilfe ebenso im eigenen
// Hint (#436): "(", "," und Strg+Umschalt+Leer, InvokeParameterCodeInsight meldet False.
//
// Server: Pfad und Argumente aus HKCU\Software\Atlas\IdePlugin
// (ServerPath, ServerArguments), ersatzweise aus dem früheren Schlüssel
// HKCU\Software\BetterDelphiLSP\IdePlugin (#403). Ohne Eintrag: AtlasServer.exe neben dem
// Plugin, sonst ..\..\..\Win64\Debug\Bin\ (Ausgabeordner des Repos).
// Diagnose = 1 (DWORD) im selben Schlüssel protokolliert die Aufrufe der IDE
// in Atlas.IDE.Expert<Version>.log neben dem Plugin (Name wie die BPL).
// Projektgruppe (#648): Die Sitzung meldet dem Server alle Projekte der Gruppe,
// das aktive zuerst; Änderungen der Gruppe prüft sie höchstens alle zwei Sekunden.
// Änderungen außerhalb der IDE (#395): Die Ordner der Projekte (Git-Arbeitsverzeichnis,
// sonst Projektordner) werden beobachtet; gesammelte Änderungen gehen bei der nächsten
// Anfrage als workspace/didChangeWatchedFiles an den Server (die Probleme-Prüfung
// fragt alle 250 ms).
// Projektkontext (#396): Konfiguration, Plattform und Optionen der Projekte
// der Gruppe gehen in initialize mit; Änderungen (Debug/Release, Win32/Win64,
// geänderte Optionen) prüft die Sitzung höchstens einmal je Sekunde.
// workspace/applyEdit (#397): Änderungen, die der Server von sich aus schickt,
// übernimmt der Hauptthread in die Puffer (TAtlasIdeWorkspaceEdit), danach
// geht die Antwort an den Server. Wartet der Hauptthread gerade selbst auf
// eine Antwort des Servers, kommt die Änderung erst nach deren Zeitlimit dran.
// Statusfeld (#591): Phase des Servers (nicht gestartet, startet, läuft,
// gestoppt, fehlgeschlagen) mit Version und mittlerer Antwortzeit; jede
// Änderung, auch das Ende des Prozesses im Lese-Thread, meldet OnServerChanged.
// Für die Zustandskachel (#754) mit Beginn der Phase (Start bzw. Ende) und ob
// Atlas den Server selbst beendet hat (StopSession) oder er abgestürzt ist.
// QueryStatusAsync fragt atlas.server.status im Hintergrund; StopSession
// wartet auf eine laufende Abfrage, bevor es die Sitzung freigibt.
// RunCommandAsync (#66) schickt einen Befehl mit Argumenten im Hintergrund,
// etwa die Metriken des Projekts nach einem Build; ebenso abgesichert.
// RunCommandsAsync (#68) schickt mehrere Befehle nacheinander in einem
// Hintergrundlauf, etwa Metriken und TODOs nach einem Build.
// Serverprozess, Ordnerbeobachter und die Quellen von Vervollständigung und
// Parameter-Hint aus dem Kern setzt die Kompositionswurzel ein
// (TAtlasCodeInsightAdapters, A-09).
// Ende des Servers (Bericht H5): Endet er von selbst, steht in atlas.log, womit
// (Exit-Code, etwa Stapelüberlauf), nach welcher Laufzeit, bei welcher Anfrage
// und wie viel er auf stderr schrieb; das Statusfeld nennt die Ursache. Den
// ersten Absturz startet die nächste Anfrage wie bisher neu. Endet er zweimal
// mit demselben Code innerhalb von zehn Minuten, startet Atlas ihn nicht mehr
// still neu, sondern meldet es mit „Server neu starten“ und „Fehlerbericht
// erstellen…“ (TAtlasServerCrashes). Ein Start von Hand hebt das auf.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.SyncObjs,
  ToolsAPI,
  Atlas.Core.Status.Lines,
  Atlas.Core.Diagnostics.ThreadList,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.Crashes,
  Atlas.Core.Files.WatchedChanges,
  Atlas.Core.Signature.Contract,
  Atlas.IDE.Completion.Editor,
  Atlas.IDE.Signature.Editor,
  Atlas.IDE.Hover.Editor,
  Atlas.IDE.InlayHints.Editor,
  Atlas.IDE.Editor.TestUnitLens,
  Atlas.IDE.Editor.MetricsLens,
  Atlas.IDE.Problems.Controller,
  Atlas.Core.Notifications.Contract;

type
  /// <summary>Adapter des Kerns, eingesetzt von der Kompositionswurzel.</summary>
  TAtlasCodeInsightAdapters = record
    /// <summary>Startet AtlasServer.exe; löst bei Fehlern EOSError aus.</summary>
    NewServer: TFunc<string, string, IAtlasLspServer>;
    NewFolderWatcher: TFunc<TAtlasWatchedChanges, IAtlasFolderWatcher>;
    NewCompletionSources: TAtlasCompletionSourcesFactory;
    NewSignatureSource: TFunc<TAtlasSessionFunc, IAtlasSignatureSource>;
  end;

  TAtlasCodeInsightManager = class(TInterfacedObject, IOTACodeInsightManager, IOTACodeInsightManager90,
    IOTACodeInsightSelection)
  private
    FEnabled: Boolean;
    FAdapters: TAtlasCodeInsightAdapters;
    FServer: IAtlasLspServer;
    FSession: TLspSession;
    FLastError: string;
    /// <summary>Erfolgreiche Starts des Servers; ab dem zweiten meldet jeder „Server neu gestartet“ (#601).
    /// </summary>
    FStarts: Integer;
    FOnOpenLog: TProc;
    FOnBugReport: TProc;
    /// <summary>Abstürze des Servers; nach zwei gleichen startet Atlas ihn nicht mehr still neu (Bericht H5).</summary>
    FCrashes: TAtlasServerCrashes;
    // Ob AtlasServer.exe da ist, höchstens alle paar Sekunden neu geprüft.
    FServerChecked: Cardinal;
    FServerFound: Boolean;
    // Zuletzt geprüfte Projektgruppe (#648).
    FProjectsChecked: Cardinal;
    /// <summary>Zuletzt geprüfter Projektkontext (#396).</summary>
    FContextsChecked: Cardinal;
    /// <summary>Änderungen außerhalb der IDE (#395).</summary>
    FFileChanges: TAtlasWatchedChanges;
    FFolderWatcher: IAtlasFolderWatcher;
    FDiagnose: Boolean;
    FCompletion: TAtlasEditorCompletion;
    FSignature: TAtlasEditorSignature;
    /// <summary>Eigener Hover-Tooltip (#442).</summary>
    FHover: TAtlasEditorHover;
    /// <summary>Probleme im Editor (#398).</summary>
    FProblems: TAtlasProblemsController;
    /// <summary>Inlay-Hints (#401).</summary>
    FInlayHints: TAtlasEditorInlayHints;
    FTestUnitLens: TAtlasEditorTestUnitLens;
    /// <summary>Code Lens mit Code-Metriken (#66).</summary>
    FMetricsLens: TAtlasEditorMetricsLens;
    FPhase: TAtlasServerPhase;
    FPhaseError: string;
    /// <summary>Beginn der Phase (Ortszeit) und „von Atlas beendet“ (#754).</summary>
    FPhaseSince: TDateTime;
    FPhaseEnded: Boolean;
    /// <summary>StopSession läuft: Ein Ende des Prozesses jetzt ist kein Absturz.</summary>
    FStopping: Boolean;
    /// <summary>EnsureSession startet gerade (gegen Wiedereintritt über CheckSynchronize, Code-Review A-01).</summary>
    FStarting: Boolean;
    /// <summary>Shutdown ist gelaufen: Sitzung, Threads und Editor-Anbindungen sind weg (#886).</summary>
    FShutDown: Boolean;
    FOnServerChanged: TProc;
    FQueryRunning: Boolean;
    FQueryIdle: TEvent;
    /// <summary>Befehl im Hintergrund (RunCommandAsync, #66).</summary>
    FCommandRunning: Boolean;
    FCommandIdle: TEvent;
    /// <summary>Bedienbefehle im Hintergrund (ExecuteServerCommandAsync, #874): Anzahl laufender und Signal „keiner“.</summary>
    FServerCommands: Integer;
    FServerCommandsIdle: TEvent;
    /// <summary>Threads von Statusabfrage, Befehlen und Bedienbefehlen; Destroy wartet auf ihr Ende (#886).</summary>
    FThreads: TAtlasThreadList;
    procedure SetPhase(APhase: TAtlasServerPhase; const AError: string); overload;
    procedure SetPhase(APhase: TAtlasServerPhase; const AError: string; AEnded: Boolean); overload;
    /// <summary>Der Server endete von selbst (Lese-Thread, Bericht H5): Ursache, Laufzeit und letzte Anfrage
    /// ins Protokoll, Ursache ins Statusfeld; nach zwei gleichen Abstürzen anhalten (ServerHeld).</summary>
    procedure ServerEnded(const AInfo: TLspCloseInfo);
    /// <summary>Hauptthread: Statusfeld und Benachrichtigung mit Neustart und Fehlerbericht (Bericht H5).</summary>
    procedure ServerHeld(ACode: Cardinal);
    /// <summary>Laufende Sitzung oder Start im Hauptthread; außerhalb des Hauptthreads nur, was schon läuft (A-01).</summary>
    function EnsureSession: Boolean;
    /// <summary>Server starten und Sitzung aufbauen; nur aus EnsureSession, nur im Hauptthread.</summary>
    function StartSession: Boolean;
    /// <summary>Projekte der geöffneten Gruppe, aktives zuerst; leer ohne Gruppe (#648).</summary>
    class function GroupProjects: TArray<string>; static;
    procedure RefreshProjects;
    /// <summary>Meldet geänderte Projektkontexte (#396); höchstens einmal je Sekunde (Hauptthread).</summary>
    procedure RefreshContexts;
    /// <summary>Beobachtet die Ordner dieser Projekte (#395).</summary>
    procedure WatchProjects(const AProjects: TArray<string>);
    /// <summary>Gesammelte Änderungen außerhalb der IDE an den Server (Hauptthread, #395).</summary>
    procedure FlushFileChanges;
    procedure StopSession;
    procedure StopSessionNow;
    /// <summary>Nimmt workspace/applyEdit der Sitzung an (#397).</summary>
    procedure AcceptApplyEdit(ASession: TLspSession);
    /// <summary>Warnungen und Fehler des Servers (window/showMessage) ins Meldungsfenster (#121).</summary>
    procedure AcceptShowMessage(ASession: TLspSession);
    procedure ReportError(const AMessage: string);
    /// <summary>Aktion „Protokoll öffnen“ für Einträge der Benachrichtigungszentrale (#601); leer ohne OnOpenLog.
    /// </summary>
    function LogActions: TArray<TAtlasNotificationAction>;
    procedure Diagnose(const AMessage: string);
    function CurrentEditView: IOTAEditView;
    /// <summary>Cursorzeile ist ein ///-Kommentar (XMLDoc, #435).</summary>
    function InXmlDocLine: Boolean;
    /// <summary>Cursorzeile ist eine Wertdarstellung (// atlas-debug:, [AtlasDebugDisplay], #854).</summary>
    function InDebugDisplayLine: Boolean;
    /// <summary>Cursor im Namen von FieldByName('…'), FindField('…') oder ParamByName('…') (#461).
    /// ATypedQuote: Das gerade getippte ' steht vielleicht noch nicht im Puffer.</summary>
    function InDataNameString(ATypedQuote: Boolean): Boolean;
    function Signature: TAtlasEditorSignature;
    function SessionOrNil: TLspSession;
    /// <summary>Führt AWork mit ASession in einem eigenen Thread aus und ruft ADone im Hauptthread (#874).
    /// ASession nil: ADone(nil) sofort.</summary>
    procedure RunInBackground(ASession: TLspSession; const AWork: TFunc<TLspSession, TJSONValue>;
      const ADone: TProc<TJSONValue>);
    /// <summary>Gibt es den Server? Ohne ihn übernimmt die eingebaute Code Insight.</summary>
    function ServerAvailable: Boolean;
    /// <summary>Bedient Atlas diese Datei? Wie HandlesFile, aber ohne Diagnosezeile.</summary>
    function Handles(const AFileName: string): Boolean;
    /// <summary>Zeigt Atlas den Tooltip selbst (Hauptschalter und Tooltip an)?</summary>
    class function OwnTooltip: Boolean; static;
    class function DiagnoseEnabled: Boolean; static;
  public
    /// <summary>Vervollständigung der Sitzung (Schnipsel, Neue Datei); nil vor dem Start.</summary>
    function Completion: TAtlasEditorCompletion;
    /// <summary>Pfad zu AtlasServer.exe aus den Einstellungen, sonst DefaultServerPath; AArguments: zusätzliche
    /// Argumente aus der Registry. Auch für die Aufrufe der Optionsseite (#227).</summary>
    class function ServerPath(out AArguments: string): string; static;
    /// <summary>Protokolldatei neben dem Plugin.</summary>
    class function DiagnoseLog: string; static;
    /// <summary>Server ohne eingestellten Pfad: neben dem Plugin, sonst Output\Win64\Debug\Bin im Repo.</summary>
    class function DefaultServerPath: string; static;
    constructor Create(const AAdapters: TAtlasCodeInsightAdapters);
    destructor Destroy; override;
    /// <summary>Alles abbauen, was im Code des Plugins weiterliefe: Editor-Anbindungen, Sitzung, Server und
    /// Hintergrund-Threads (#886). Mehrfach aufrufbar, nur im Hauptthread. Danach meldet der Manager sich als
    /// ausgeschaltet. Die Kompositionswurzel ruft es beim Abmelden, weil die IDE den Manager nach
    /// RemoveCodeInsightManager noch halten kann (etwa mitten im Gruppen-Build); Destroy liefe dann
    /// erst später.</summary>
    procedure Shutdown;
    /// <summary>Benachrichtigung an den Server, falls eine Sitzung läuft (#527); übernimmt AParams.
    /// Startet den Server dafür nicht.</summary>
    procedure NotifyServer(const AMethod: string; AParams: TJSONObject);
    /// <summary>Fortschritt des Servers ("Index 45 %"); '' ohne Sitzung oder Vorgang. Startet keinen Server (#492).</summary>
    function ServerProgress: string;
    /// <summary>Befehl an den Server, ohne den Hauptthread warten zu lassen (#874; eine synchrone Fassung gibt es
    /// nicht mehr). Startet den Server bei Bedarf (im Hauptthread), fragt im Hintergrund und ruft ADone im
    /// Hauptthread auf, mit nil bei Fehler, Zeitlimit oder ohne Server. Den Wert gibt der Manager nach
    /// ADone frei. Mehrere Befehle dürfen gleichzeitig laufen; StopSession wartet auf sie.</summary>
    procedure ExecuteServerCommandAsync(const ACommand: string; ATimeoutMs: Cardinal; const ADone: TProc<TJSONValue>);
    /// <summary>Befehl mit Argumenten (JSON-Array) an den laufenden Server (#108); startet keinen Server.
    /// nil ohne Sitzung, bei Fehler oder Zeitlimit; das Ergebnis gehört dem Aufrufer.</summary>
    function RunServerCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>Wie RunServerCommand, aber im Hintergrund (#874): ADone im Hauptthread mit der Antwort oder nil;
    /// den Wert gibt der Manager nach ADone frei. Startet keinen Server.</summary>
    procedure RunServerCommandAsync(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
      const ADone: TProc<TJSONValue>);
    /// <summary>Laufende Sitzung, Server bei Bedarf gestartet; nil, wenn er nicht startet (Hauptthread).</summary>
    function ActiveSession: TLspSession;
    /// <summary>Laufende, initialisierte Sitzung oder nil; startet keinen Server (#402).</summary>
    function RunningSession: TLspSession;
    /// <summary>Ist die Liste der Vervollständigung offen (#671)?</summary>
    function CompletionVisible: Boolean;
    /// <summary>Läuft der Platzhalter-Modus einer Vorlage (#589: dann keine Mehrfachmarken)?</summary>
    function PlaceholdersActive: Boolean;
    /// <summary>Gespeichert: didSave an den Server, falls eine Sitzung läuft (Prüfung mit dcc).</summary>
    procedure NotifySaved(const AFileName: string);
    /// <summary>Zeile im Diagnoseprotokoll (nur mit Diagnose = 1).</summary>
    procedure Log(const AMessage: string);
    /// <summary>Zeile im Protokoll unabhängig von Diagnose, z. B. Hänger (#501).</summary>
    procedure Report(const AMessage: string);
    /// <summary>Vervollständigung bzw. Parameter-Hint über eine eigene Taste von Atlas öffnen (#494).</summary>
    procedure OpenCompletion;
    procedure OpenSignature;
    /// <summary>Stand des Servers für das Statusfeld (#591); startet keinen Server.</summary>
    function ServerInfo: TAtlasServerInfo;
    /// <summary>Indizierung läuft? APercent = Fortschritt, -1 = unbekannt; False ohne Sitzung.</summary>
    function ServerIndexing(out APercent: Integer): Boolean;
    /// <summary>„Server neu starten“ (#591, #393): Sitzung beenden und neu starten; hebt das Anhalten nach
    /// Abstürzen auf (AllowStart).</summary>
    function RestartServer: Boolean;
    /// <summary>Start von Hand („Server starten“): Nach zwei gleichen Abstürzen startet Atlas den Server wieder
    /// (Bericht H5).</summary>
    procedure AllowStart;
    /// <summary>atlas.server.status im Hintergrund, nur bei laufender Sitzung und ohne laufende
    /// Abfrage; ADone bekommt das JSON ('' bei Fehler) im Hintergrund-Thread. False = nicht gestartet.</summary>
    function QueryStatusAsync(const ADone: TProc<string>): Boolean;
    /// <summary>Befehl mit Argumenten (JSON-Array) im Hintergrund an den laufenden Server (#66), nur ohne
    /// laufenden Hintergrundbefehl; startet keinen Server. ADone bekommt das Ergebnis als JSON ('' bei Fehler
    /// oder Zeitlimit) im Hintergrund-Thread. False = nicht gestartet.</summary>
    function RunCommandAsync(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
      const ADone: TProc<string>): Boolean;
    /// <summary>Mehrere Befehle nacheinander in einem Hintergrundlauf (#68), sonst wie RunCommandAsync; ATimeoutMs
    /// gilt je Befehl. ADone bekommt die Ergebnisse in derselben Reihenfolge ('' bei Fehler oder Zeitlimit).
    /// False = nicht gestartet oder ungleich viele Befehle und Argumente.</summary>
    function RunCommandsAsync(const ACommands, AArgumentsJson: TArray<string>; ATimeoutMs: Cardinal;
      const ADone: TProc<TArray<string>>): Boolean;
    /// <summary>Phase, Version oder Fortschritt haben sich geändert; aus jedem Thread.</summary>
    property OnServerChanged: TProc read FOnServerChanged write FOnServerChanged;
    /// <summary>„Protokoll öffnen“ für die Einträge der Quelle Server in der Benachrichtigungszentrale (#601).
    /// </summary>
    property OnOpenLog: TProc read FOnOpenLog write FOnOpenLog;
    /// <summary>„Fehlerbericht erstellen…“ in der Meldung nach zwei gleichen Abstürzen des Servers (Bericht H5).
    /// </summary>
    property OnBugReport: TProc read FOnBugReport write FOnBugReport;
    /// <summary>Bietet IOTACodeInsightManager90 (Help Insight) nur an, solange der Atlas-Tooltip an ist.</summary>
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    { IOTACodeInsightManager100 }
    function GetName: string;
    function GetIDString: string;
    function GetEnabled: Boolean;
    procedure SetEnabled(Value: Boolean);
    function EditorTokenValidChars(PreValidating: Boolean): TSysCharSet;
    procedure AllowCodeInsight(var Allow: Boolean; const Key: Char);
    function PreValidateCodeInsight(const Str: string): Boolean;
    function IsViewerBrowsable(Index: Integer): Boolean;
    function GetMultiSelect: Boolean;
    procedure GetSymbolList(out SymbolList: IOTACodeInsightSymbolList);
    procedure OnEditorKey(Key: Char; var CloseViewer: Boolean; var Accept: Boolean);
    function HandlesFile(const AFileName: string): Boolean;
    function GetLongestItem: string;
    procedure GetParameterList(out ParameterList: IOTACodeInsightParameterList);
    procedure GetCodeInsightType(AChar: Char; AElement: Integer; out CodeInsightType: TOTACodeInsightType;
      out InvokeType: TOTAInvokeType);
    function InvokeCodeCompletion(HowInvoked: TOTAInvokeType; var Str: string): Boolean;
    function InvokeParameterCodeInsight(HowInvoked: TOTAInvokeType; var SelectedIndex: Integer): Boolean;
    procedure ParameterCodeInsightAnchorPos(var EdPos: TOTAEditPos);
    function ParameterCodeInsightParamIndex(EdPos: TOTAEditPos): Integer;
    function GetHintText(HintLine, HintCol: Integer): string;
    function GotoDefinition(out AFileName: string; out ALineNum: Integer; Index: Integer = -1): Boolean;
    procedure Done(Accepted: Boolean; out DisplayParams: Boolean);
    { IOTACodeInsightManager }
    function GetOptionSetName: string;
    { IOTACodeInsightManager90 }
    function GetHelpInsightHtml: WideString;
    { IOTACodeInsightSelection }
    function GetDisplayName: string;
  end;

implementation

uses
  Atlas.Text.DebugDisplay,
  Atlas.Core.Hover.DebugValue,
  Atlas.IDE.Hover.DebugValue,
  Atlas.Core.Diagnostics.Guard,
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.Win.Registry,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Problems.Contract,
  Winapi.Windows,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.Core.Completion.Word,
  Atlas.Core.Projects.Contract,
  Atlas.IDE.Projects.Context,
  Atlas.IDE.Outline.Cache,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.UI.Strings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.TimeLimit,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources;

var
  /// <summary>Lebender Manager; nach dem Freigeben nil, damit späte applyEdit-Aufrufe nichts mehr tun.</summary>
  LiveManager: TObject;

const
  RegistryKey = 'Software\Atlas\IdePlugin';
  // Schlüssel vor der Umbenennung in Atlas (#403), wird nur noch gelesen.
  LegacyRegistryKey = 'Software\BetterDelphiLSP\IdePlugin';
  // Unterscheidet sich vom gleichnamigen benutzerdefinierten LSP-Eintrag.
  ManagerName = 'Atlas IDE Expert';
  ManagerId = 'Atlas.CodeInsight';

/// <summary>Fehler eines Einstiegspunkts an die Sicherung (#493, Code-Review S-05); ein beendeter Server oder sein
/// Zeitlimit (ELspClientError) ist erwartbar und zählt nicht.</summary>
procedure ReportFailure(AFeature: TAtlasFeature; E: Exception);
begin
  if not (E is ELspClientError) then
    TAtlasGuard.Report(AFeature, E);
end;

/// <summary>Öffnet den Schlüssel der Einstellungen, ersatzweise den früheren; liefert den
/// geöffneten Schlüssel oder ''.</summary>
function OpenSettingsKey(ARegistry: TRegistry): string;
begin
  ARegistry.RootKey := HKEY_CURRENT_USER;
  if ARegistry.OpenKeyReadOnly(RegistryKey) then
    Result := RegistryKey
  else if ARegistry.OpenKeyReadOnly(LegacyRegistryKey) then
    Result := LegacyRegistryKey
  else
    Result := '';
end;

{ TAtlasCodeInsightManager }

constructor TAtlasCodeInsightManager.Create(const AAdapters: TAtlasCodeInsightAdapters);
begin
  inherited Create;
  FAdapters := AAdapters;
  LiveManager := Self;
  FEnabled := True;
  FDiagnose := DiagnoseEnabled;
  FPhase := TAtlasServerPhase.NotStarted;
  FQueryIdle := TEvent.Create(nil, True, True, '');
  FCommandIdle := TEvent.Create(nil, True, True, '');
  FServerCommandsIdle := TEvent.Create(nil, True, True, '');
  FThreads := TAtlasThreadList.Create;
  FCrashes := TAtlasServerCrashes.Create(nil);
  Diagnose('Plugin geladen: ' + GetModuleName(HInstance));
  FFileChanges := TAtlasWatchedChanges.Create;
  FFolderWatcher := FAdapters.NewFolderWatcher(FFileChanges);
  // Gemeinsamer Pufferstand für Probleme und Inlay-Hints (P-04).
  TAtlasEditorSnapshots.Install;
  FProblems := TAtlasProblemsController.Create(
    function(AStart: Boolean): TLspSession
    begin
      // Start nur im Hauptthread (Probleme-Takt); EnsureSession kehrt sonst sofort zurück (A-01).
      if AStart then
        EnsureSession;
      Result := RunningSession;
    end,
    procedure(const AMessage: string)
    begin
      Diagnose(AMessage);
    end);
  FHover := TAtlasEditorHover.Create(
    function: TLspSession
    begin
      if EnsureSession then
        Result := RunningSession
      else
        Result := nil;
    end,
    procedure(const AMessage: string)
    begin
      Diagnose(AMessage);
    end,
    function(const AFileName: string; ALine, ACharacter: Integer): TArray<TAtlasProblem>
    begin
      if FProblems <> nil then
        Result := FProblems.ProblemsAt(AFileName, ALine, ACharacter)
      else
        Result := nil;
    end,
    function(const AFileName: string): Boolean
    begin
      Result := Handles(AFileName);
    end);
  // Startet keinen Server: Inlay-Hints kommen erst, wenn er ohnehin läuft.
  FInlayHints := TAtlasEditorInlayHints.Create(
    function: TLspSession
    begin
      if (FServer <> nil) and FServer.Running and (FSession <> nil) and FSession.Initialized then
        Result := FSession
      else
        Result := nil;
    end);
  // Code Lens zur Testunit (#189); startet ebenfalls keinen Server.
  FTestUnitLens := TAtlasEditorTestUnitLens.Create(
    function: TLspSession
    begin
      if (FServer <> nil) and FServer.Running and (FSession <> nil) and FSession.Initialized then
        Result := FSession
      else
        Result := nil;
    end);
  // Code Lens mit Code-Metriken (#66); startet ebenfalls keinen Server.
  FMetricsLens := TAtlasEditorMetricsLens.Create(
    function: TLspSession
    begin
      if (FServer <> nil) and FServer.Running and (FSession <> nil) and FSession.Initialized then
        Result := FSession
      else
        Result := nil;
    end);
end;

destructor TAtlasCodeInsightManager.Destroy;
begin
  Shutdown;
  FreeAndNil(FThreads);
  // Nach Shutdown: Kein Lese-Thread meldet mehr ein Ende.
  FreeAndNil(FCrashes);
  FQueryIdle.Free;
  FCommandIdle.Free;
  FServerCommandsIdle.Free;
  inherited;
end;

procedure TAtlasCodeInsightManager.Shutdown;
begin
  if FShutDown then
    Exit;
  FShutDown := True;
  FEnabled := False;
  if LiveManager = Self then
    LiveManager := nil;
  // Hält die Beobachter-Threads an; erst danach darf der Sammler weg.
  FFolderWatcher := nil;
  FreeAndNil(FFileChanges);
  // Vor der Sitzung: wartet auf laufende Anfragen und meldet Tasten und Beobachter ab.
  FreeAndNil(FInlayHints);
  FreeAndNil(FTestUnitLens);
  FreeAndNil(FMetricsLens);
  FreeAndNil(FHover);
  FreeAndNil(FSignature);
  FreeAndNil(FCompletion);
  FOnServerChanged := nil;
  StopSession;
  // Nach StopSession: Die Threads sind dort schon angehalten.
  FreeAndNil(FProblems);
  // Nach beiden Verbrauchern.
  TAtlasEditorSnapshots.Uninstall;
  // Die Threads geben sich nicht selbst frei: Erst wenn sie beendet sind, läuft nichts mehr im Code des Plugins,
  // auch nicht das Freigeben ihrer anonymen Methode (#886). Sie nutzen bis zuletzt die Ereignisse aus Destroy.
  if not FThreads.StopAll(TAtlasShutdown.StopMs) then
    Diagnose('Manager abgebaut, während ein Hintergrund-Thread noch lief');
end;

class function TAtlasCodeInsightManager.DiagnoseEnabled: Boolean;
var
  Registry: TRegistry;
begin
  // Diagnose = 1 (DWORD): Aufrufe der IDE und Ergebnisse in DiagnoseLog.
  Result := False;
  Registry := TRegistry.Create(KEY_READ);
  try
    if (OpenSettingsKey(Registry) <> '') and Registry.ValueExists('Diagnose') and
      (Registry.GetDataType('Diagnose') = rdInteger) then
      Result := Registry.ReadInteger('Diagnose') <> 0;
  finally
    Registry.Free;
  end;
end;

class function TAtlasCodeInsightManager.DiagnoseLog: string;
begin
  // Neben dem Plugin, nicht im Temp-Ordner: Den hat die IDE nicht in jedem Fall gemeinsam mit uns.
  Result := ChangeFileExt(GetModuleName(HInstance), '.log');
end;

class function TAtlasCodeInsightManager.ServerPath(out AArguments: string): string;
var
  Registry: TRegistry;
  Key: string;
begin
  Result := '';
  AArguments := '';
  Registry := TRegistry.Create(KEY_READ);
  try
    Key := OpenSettingsKey(Registry);
    if Key <> '' then
    begin
      if Registry.ValueExists('ServerPath') then
        Result := Registry.ReadString('ServerPath');
      if Registry.ValueExists('ServerArguments') then
        AArguments := Registry.ReadString('ServerArguments');
    end;
  finally
    Registry.Free;
  end;
  // Der alte Schlüssel zeigt meist noch auf BetterDelphiLSP.exe; fehlt sie, gelten die Vorgaben.
  if (Key = LegacyRegistryKey) and (Result <> '') and not FileExists(Result) then
    Result := '';
  if Result <> '' then
    Exit;
  Result := DefaultServerPath;
end;

class function TAtlasCodeInsightManager.DefaultServerPath: string;
var
  PluginDir: string;
begin
  PluginDir := ExtractFilePath(GetModuleName(HInstance));
  Result := PluginDir + 'AtlasServer.exe';
  if FileExists(Result) then
    Exit;
  // Installer (#495): BPL in <Ziel>\Win32 bzw. \Win64, der Server eine Ebene darüber.
  if FileExists(ExpandFileName(PluginDir + '..\AtlasServer.exe')) then
    Exit(ExpandFileName(PluginDir + '..\AtlasServer.exe'));
  // Ausgabeordner des Repos: Win64 bevorzugt, sonst ein Win32-Bau des Servers.
  Result := ExpandFileName(PluginDir + '..\..\..\Win64\Debug\Bin\AtlasServer.exe');
  if not FileExists(Result) and FileExists(ExpandFileName(PluginDir + '..\..\..\Win32\Debug\Bin\AtlasServer.exe')) then
    Result := ExpandFileName(PluginDir + '..\..\..\Win32\Debug\Bin\AtlasServer.exe');
end;

/// <summary>Pfade und Benutzername aus einer Zeile des Diagnoselogs (#647); Meldungen wie
/// „Server nicht gefunden: C:\…“ dürfen so weitergegeben werden.</summary>
function WithoutPaths(const AText: string): string;
var
  UserName: string;
begin
  Result := TRegEx.Replace(AText, '(?:\b[A-Za-z]:|\\\\)[\\/]\S*|file:\S+|\S*\\\S*', '<pfad>');
  UserName := GetEnvironmentVariable('USERNAME');
  if Length(UserName) >= 3 then
    Result := StringReplace(Result, UserName, '<benutzer>', [rfReplaceAll, rfIgnoreCase]);
end;

function TAtlasCodeInsightManager.LogActions: TArray<TAtlasNotificationAction>;
begin
  Result := nil;
  if Assigned(FOnOpenLog) then
    Result := [TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.StatusOpenLog), FOnOpenLog)];
end;

procedure TAtlasCodeInsightManager.ReportError(const AMessage: string);
var
  Messages: IOTAMessageServices;
  Mode: TAtlasNotificationMode;
begin
  Diagnose('Fehler: ' + AMessage);
  // Jede Meldung nur einmal, sonst flutet ein fehlender Server das Meldungsfenster.
  if AMessage = FLastError then
    Exit;
  FLastError := AMessage;
  // Benachrichtigungszentrale (#601): bei „nur sammeln“ oder „aus“ keine Zeile im Meldungsfenster.
  Mode := TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Server,
    TAtlasNotificationSeverity.Error, TAtlasStrings.Text(TAtlasTextId.NotificationsServerError), AMessage,
    LogActions);
  if Mode <> TAtlasNotificationMode.Show then
    Exit;
  if Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Messages.AddTitleMessage('Atlas: ' + AMessage);
end;

procedure TAtlasCodeInsightManager.Diagnose(const AMessage: string);
begin
  if not FDiagnose then
    Exit;
  try
    TFile.AppendAllText(DiagnoseLog, FormatDateTime('hh":"nn":"ss.zzz', Now) + ' ' + WithoutPaths(AMessage) + sLineBreak,
      TEncoding.UTF8);
  except
    // Diagnose darf die IDE nie stören.
  end;
end;

procedure TAtlasCodeInsightManager.StopSession;
begin
  // Nur im Hauptthread (A-01); verschachtelt (CheckSynchronize beim Warten) nichts tun.
  if not TAtlasMainThread.IsMain or FStopping then
    Exit;
  FStopping := True;
  try
    StopSessionNow;
  finally
    FStopping := False;
  end;
end;

procedure TAtlasCodeInsightManager.StopSessionNow;
begin
  Assert(TAtlasMainThread.IsMain, 'StopSessionNow außerhalb des Hauptthreads');
  // Laufende Anfragen der Vervollständigung nutzen die Sitzung noch.
  if FCompletion <> nil then
    FCompletion.Shutdown;
  if FSignature <> nil then
    FSignature.Shutdown;
  // Probleme: Threads anhalten, Verbindung schließen (laufende Anfragen kehren sofort zurück), warten.
  if FProblems <> nil then
    FProblems.BeginShutdown;
  if FSession <> nil then
    FSession.SetOnProgress(nil);
  if FServer <> nil then
    FServer.Client.Close;
  // Hover-Anfragen halten die Sitzung als rohen Zeiger; nach Close kehren sie sofort zurück (Code-Review A-07).
  if FHover <> nil then
    FHover.Shutdown;
  if FProblems <> nil then
    FProblems.WaitShutdown;
  // Eine Statusabfrage im Hintergrund kehrt nach Close sofort zurück (#591), ebenso ein Befehl (#66).
  FQueryIdle.WaitFor(5000);
  // Aufgegebene Zeitlimit-Arbeiter können noch in Prepare bzw. Sync der Sitzung stecken (A-01, A-13).
  if not TAtlasTimeLimit.WaitIdle(TAtlasShutdown.StopMs) then
    Diagnose('Sitzung beendet, während ein Zeitlimit-Arbeiter noch lief');
  FCommandIdle.WaitFor(5000);
  FServerCommandsIdle.WaitFor(5000);
  FreeAndNil(FSession);
  FServer := nil;
end;

procedure TAtlasCodeInsightManager.SetPhase(APhase: TAtlasServerPhase; const AError: string);
begin
  SetPhase(APhase, AError, False);
end;

procedure TAtlasCodeInsightManager.SetPhase(APhase: TAtlasServerPhase; const AError: string; AEnded: Boolean);
var
  Changed: TProc;
begin
  // Ein beendeter Server bleibt beendet, bis er wieder startet; der Zeitpunkt bleibt der erste.
  if (APhase <> FPhase) or (AEnded <> FPhaseEnded) then
    FPhaseSince := Now;
  FPhase := APhase;
  FPhaseError := AError;
  FPhaseEnded := (APhase = TAtlasServerPhase.Stopped) and AEnded;
  Changed := FOnServerChanged;
  if Assigned(Changed) then
    Changed();
end;

function TAtlasCodeInsightManager.ServerInfo: TAtlasServerInfo;
begin
  Result := Default(TAtlasServerInfo);
  Result.Phase := FPhase;
  Result.Error := FPhaseError;
  Result.Since := FPhaseSince;
  Result.Ended := FPhaseEnded;
  Result.Version := '';
  Result.AverageMs := 0;
  Result.Samples := 0;
  if (FSession <> nil) and FSession.Initialized then
    Result.Version := FSession.ServerVersion;
  if FServer <> nil then
    Result.AverageMs := FServer.Client.AverageMs(Result.Samples);
end;

function TAtlasCodeInsightManager.ServerIndexing(out APercent: Integer): Boolean;
begin
  APercent := -1;
  Result := (FSession <> nil) and FSession.Initialized and FSession.Indexing(APercent);
end;

function TAtlasCodeInsightManager.RestartServer: Boolean;
begin
  Report('Server wird neu gestartet');
  AllowStart;
  StopSession;
  SetPhase(TAtlasServerPhase.Stopped, '', True);
  Result := EnsureSession;
end;

procedure TAtlasCodeInsightManager.AllowStart;
begin
  if FCrashes.Held then
    TAtlasGuard.Log('Server: Start von Hand nach wiederholtem Absturz');
  FCrashes.Reset;
end;

procedure TAtlasCodeInsightManager.ServerEnded(const AInfo: TLspCloseInfo);
var
  Manager: TAtlasCodeInsightManager;
  Code: Cardinal;
  Line: string;
  Continues: Boolean;
begin
  Code := TAtlasServerExits.Unknown;
  if AInfo.ExitKnown then
    Code := AInfo.ExitCode;
  Line := TAtlasServerExits.Line(Code, AInfo.RuntimeMs, AInfo.LastMethod, AInfo.OpenMethods, AInfo.ErrorLines);
  // atlas.log für den Fehlerbericht, das Diagnoseprotokoll für den zeitlichen Zusammenhang mit den Aufrufen.
  TAtlasGuard.Log(Line);
  Report(Line);
  Continues := FCrashes.Crashed(Code);
  if not Continues then
    TAtlasGuard.Log(Format('Server: zweimal %s innerhalb von %d min, kein weiterer Start ohne Zutun',
      [TAtlasServerExits.Describe(Code), TAtlasServerCrashes.WindowMinutes]));
  Manager := Self;
  // Statusfeld und Benachrichtigung im Hauptthread: FPhaseError ist ein String, den der Hauptthread liest.
  TAtlasMainThread.Queue(TAtlasFeature.Server,
    procedure
    begin
      if LiveManager <> Manager then
        Exit;
      if not Continues then
        Manager.ServerHeld(Code)
      // Inzwischen neu gestartet oder von Atlas beendet: Die Ursache gehört nicht mehr ins Statusfeld.
      else if (Manager.FPhase = TAtlasServerPhase.Stopped) and not Manager.FPhaseEnded then
        Manager.SetPhase(TAtlasServerPhase.Stopped, TAtlasServerExits.Describe(Code));
    end);
end;

procedure TAtlasCodeInsightManager.ServerHeld(ACode: Cardinal);
var
  Manager: TAtlasCodeInsightManager;
  Restart: TProc;
  Actions: TArray<TAtlasNotificationAction>;
  Cause: string;
begin
  // Von Hand neu gestartet, bevor dieser Eintrag dran war: nichts mehr zu melden.
  if not FCrashes.Held then
    Exit;
  Cause := TAtlasServerExits.Describe(ACode);
  SetPhase(TAtlasServerPhase.Stopped, TAtlasStrings.Fmt(TAtlasTextId.ServerHeldPhase, [Cause]));
  Manager := Self;
  Restart :=
    procedure
    begin
      if LiveManager = Manager then
        Manager.RestartServer;
    end;
  Actions := [TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.StatusRestartServer), Restart)];
  if Assigned(FOnBugReport) then
    Actions := Actions + [TAtlasNotificationCenter.Action(TAtlasStrings.Text(TAtlasTextId.BugReportMenu),
      FOnBugReport)];
  Actions := Actions + LogActions;
  TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Server, TAtlasNotificationSeverity.Error,
    TAtlasStrings.Text(TAtlasTextId.ServerHeldTitle),
    TAtlasStrings.Fmt(TAtlasTextId.ServerHeldText, [Cause, TAtlasServerCrashes.WindowMinutes]), Actions);
end;

function TAtlasCodeInsightManager.QueryStatusAsync(const ADone: TProc<string>): Boolean;
var
  Session: TLspSession;
  Idle: TEvent;
begin
  Result := False;
  if FQueryRunning or (FServer = nil) or not FServer.Running or (FSession = nil) or not FSession.Initialized then
    Exit;
  FQueryRunning := True;
  FQueryIdle.ResetEvent;
  Session := FSession;
  Idle := FQueryIdle;
  FThreads.Start(
    procedure
    var
      Answer: TJSONValue;
      Json: string;
    begin
      try
        Json := '';
        try
          Answer := Session.ExecuteCommand(TAtlasStatusLines.StatusCommand, 5000);
          try
            if Answer <> nil then
              Json := Answer.ToJSON;
          finally
            Answer.Free;
          end;
          if Assigned(ADone) then
            ADone(Json);
        except
          // Hintergrund-Thread: nie eine Ausnahme nach außen.
          on Exception do
            ;
        end;
      finally
        // Danach nichts mehr am Manager: StopSession wartet genau auf dieses Signal.
        FQueryRunning := False;
        Idle.SetEvent;
      end;
    end);
  Result := True;
end;

function TAtlasCodeInsightManager.RunCommandAsync(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
  const ADone: TProc<string>): Boolean;
var
  Done: TProc<string>;
begin
  Done := ADone;
  Result := RunCommandsAsync([ACommand], [AArgumentsJson], ATimeoutMs,
    procedure(AAnswers: TArray<string>)
    begin
      if Assigned(Done) then
        Done(AAnswers[0]);
    end);
end;

function TAtlasCodeInsightManager.RunCommandsAsync(const ACommands, AArgumentsJson: TArray<string>;
  ATimeoutMs: Cardinal; const ADone: TProc<TArray<string>>): Boolean;
var
  Session: TLspSession;
  Idle: TEvent;
  Commands, Arguments: TArray<string>;
  Timeout: Cardinal;
  Done: TProc<TArray<string>>;
begin
  Result := False;
  if (Length(ACommands) = 0) or (Length(ACommands) <> Length(AArgumentsJson)) then
    Exit;
  if FCommandRunning or (FServer = nil) or not FServer.Running or (FSession = nil) or
    not FSession.Initialized then
    Exit;
  FCommandRunning := True;
  FCommandIdle.ResetEvent;
  Session := FSession;
  Idle := FCommandIdle;
  Commands := Copy(ACommands);
  Arguments := Copy(AArgumentsJson);
  Timeout := ATimeoutMs;
  Done := ADone;
  FThreads.Start(
    procedure
    var
      Answer: TJSONValue;
      Answers: TArray<string>;
      Index: Integer;
    begin
      try
        try
          SetLength(Answers, Length(Commands));
          for Index := 0 to High(Commands) do
          begin
            Answers[Index] := '';
            Answer := nil;
            try
              Answer := Session.RunCommand(Commands[Index], Arguments[Index], Timeout);
            except
              // Fehler, Zeitlimit oder geschlossene Verbindung: '' für diesen Befehl (Answer bleibt nil).
              on Exception do
                ;
            end;
            try
              if Answer <> nil then
                Answers[Index] := Answer.ToJSON;
            finally
              Answer.Free;
            end;
          end;
          if Assigned(Done) then
            Done(Answers);
        except
          // Hintergrund-Thread: nie eine Ausnahme nach außen.
          on Exception do
            ;
        end;
      finally
        // Danach nichts mehr am Manager: StopSession wartet genau auf dieses Signal.
        FCommandRunning := False;
        Idle.SetEvent;
      end;
    end);
  Result := True;
end;

function TAtlasCodeInsightManager.EnsureSession: Boolean;
begin
  // Start und Stopp gehören dem Hauptthread (A-01): Zeitlimit-Arbeiter, Lese-Thread und Hintergrund-Threads
  // bekommen nur, was schon läuft.
  if not TAtlasMainThread.IsMain then
    Exit(RunningSession <> nil);
  // Abgebaut, aber von der IDE noch gehalten (#886): keinen Server mehr starten.
  if FShutDown then
    Exit(False);
  // Verschachtelt aus StopSession oder StartSession (Warten auf Threads arbeitet eingereihte Aufrufe ab):
  // weder neu starten noch die gleich freigegebene Sitzung herausgeben.
  if FStopping or FStarting then
    Exit(RunningSession <> nil);
  if (FServer <> nil) and FServer.Running and (FSession <> nil) and FSession.Initialized then
  begin
    RefreshContexts;
    RefreshProjects;
    FlushFileChanges;
    Exit(True);
  end;
  // Zweimal gleich abgestürzt (Bericht H5): kein stiller Neustart; „Server neu starten“ hebt das auf.
  if FCrashes.Held then
    Exit(False);
  FStarting := True;
  try
    Result := StartSession;
  finally
    FStarting := False;
  end;
end;

function TAtlasCodeInsightManager.StartSession: Boolean;
var
  Path, Arguments: string;
  Documents: TArray<TLspOpenDocument>;
  Projects: TArray<string>;
  Crashed: Boolean;
  Text: string;
  Client: TLspClient;
  Code: Cardinal;
begin
  // Vom Server selbst beendet (nicht von Atlas): für den Eintrag „Server neu gestartet“ (#601).
  Crashed := (FPhase = TAtlasServerPhase.Stopped) and not FPhaseEnded;
  // Abgestürzter oder hängender Server: Was die alte Sitzung abgeglichen hatte, bekommt
  // der neue Server sofort wieder, nicht erst bei der nächsten Anfrage je Datei (#393).
  Documents := nil;
  if FSession <> nil then
    Documents := FSession.OpenDocuments;
  StopSession;
  Path := ServerPath(Arguments);
  Diagnose('Starte Server: ' + Path);
  if not FileExists(Path) then
  begin
    ReportError('Server nicht gefunden: ' + Path);
    SetPhase(TAtlasServerPhase.Failed, 'AtlasServer.exe nicht gefunden');
    Exit(False);
  end;
  SetPhase(TAtlasServerPhase.Starting, '');
  try
    FServer := FAdapters.NewServer(Path, Arguments);
    Client := FServer.Client;
    // Ende des Prozesses (z. B. im Task-Manager beendet) färbt das Statusfeld sofort rot (#591).
    Client.OnClosed :=
      procedure
      var
        Ended: Boolean;
      begin
        // Während StopSession beendet Atlas den Server selbst; sonst ist er abgestürzt (#754).
        Ended := FStopping;
        SetPhase(TAtlasServerPhase.Stopped, '', Ended);
        // Erst danach: Die Ursache aus ServerEnded setzt der Hauptthread nur auf einen abgestürzten Server.
        if not Ended then
          ServerEnded(Client.CloseInfo);
      end;
    FSession := TLspSession.Create(FServer.Client);
    FContextsChecked := 0;
    RefreshContexts;
    AcceptApplyEdit(FSession);
    AcceptShowMessage(FSession);
    Projects := GroupProjects;
    FSession.SetProjects(Projects);
    WatchProjects(Projects);
    // Server-Einstellungen liest der Server selbst aus settings.json und atlas.json; das Plugin schickt keine.
    FSession.SetOnProgress(
      procedure
      var
        Changed: TProc;
      begin
        Changed := FOnServerChanged;
        if Assigned(Changed) then
          Changed();
      end);
    FProjectsChecked := GetTickCount;
    FSession.Initialize;
    if Documents <> nil then
    begin
      FSession.Reopen(Documents);
      Diagnose(Format('Nach Neustart erneut geöffnet: %d Dateien', [Length(Documents)]));
    end;
    FLastError := '';
    SetPhase(TAtlasServerPhase.Running, '');
    Result := True;
    // Jeder weitere Start ist ein Neustart (#393): Eintrag in der Benachrichtigungszentrale (#601); drei
    // innerhalb von 10 s fasst sie zu „3 × Server neu gestartet“ zusammen.
    Inc(FStarts);
    if FStarts > 1 then
    begin
      Text := '';
      if Crashed and FCrashes.LastCode(Code) then
        Text := TAtlasStrings.Fmt(TAtlasTextId.ServerCrashedCause, [TAtlasServerExits.Describe(Code)])
      else if Crashed then
        Text := TAtlasStrings.Text(TAtlasTextId.NotificationsServerCrashed);
      if Length(Documents) > 0 then
        Text := Trim(Text + ' ' + TAtlasStrings.Fmt(TAtlasTextId.NotificationsServerReopened, [Length(Documents)]));
      if Crashed then
        TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Server, TAtlasNotificationSeverity.Warning,
          TAtlasStrings.Text(TAtlasTextId.NotificationsServerRestarted), Text, LogActions)
      else
        TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Server, TAtlasNotificationSeverity.Info,
          TAtlasStrings.Text(TAtlasTextId.NotificationsServerRestarted), Text, LogActions);
    end;
  except
    on E: Exception do
    begin
      ReportError('Start fehlgeschlagen: ' + E.Message);
      StopSession;
      SetPhase(TAtlasServerPhase.Failed, WithoutPaths(E.Message));
      Result := False;
    end;
  end;
end;

class function TAtlasCodeInsightManager.GroupProjects: TArray<string>;
var
  Modules: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Active: IOTAProject;
  Index: Integer;
  FileName: string;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Group := Modules.MainProjectGroup;
  if Group = nil then
    Exit;
  Active := Group.ActiveProject;
  if (Active <> nil) and SameText(ExtractFileExt(Active.FileName), '.dproj') and FileExists(Active.FileName) then
    Result := [Active.FileName];
  for Index := 0 to Group.ProjectCount - 1 do
  begin
    FileName := Group.Projects[Index].FileName;
    // Nur gespeicherte Delphi-Projekte; neue, noch namenlose Projekte haben keinen Ordner.
    if not SameText(ExtractFileExt(FileName), '.dproj') or not FileExists(FileName) then
      Continue;
    if (Active <> nil) and SameText(FileName, Active.FileName) then
      Continue;
    Result := Result + [FileName];
  end;
end;

procedure TAtlasCodeInsightManager.AcceptApplyEdit(ASession: TLspSession);
var
  Manager: TAtlasCodeInsightManager;
begin
  Manager := Self;
  ASession.OnApplyEdit :=
    procedure(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply)
    begin
      // Lese-Thread: Open Tools API nur im Hauptthread. Atlas gehört der Eintrag: beim Entladen verworfen
      // (Code-Review A-02); ohne Antwort gibt die Sitzung die Id frei (S-07).
      TAtlasMainThread.Queue(TAtlasFeature.EditorCommands,
        procedure
        var
          Outcome: TAtlasWorkspaceEditResult;
          Applied: Boolean;
          Reason: string;
        begin
          // Manager weg oder neue Sitzung: Die alte Verbindung gibt es nicht mehr, nicht antworten.
          if (LiveManager <> Manager) or (Manager.FSession <> ASession) then
            Exit;
          Applied := False;
          if AEdit.Unsupported > 0 then
            Reason := 'Dateioperationen (anlegen, umbenennen, löschen) werden nicht unterstützt.'
          else
            try
              Outcome := TAtlasIdeWorkspaceEdit.Apply(AEdit,
                TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
                TAtlasStrings.Text(TAtlasTextId.UndoActionServer));
              Manager.Diagnose(Format('workspace/applyEdit: %d Änderungen in %d Dateien %s', [Outcome.Edits,
                Outcome.Files, Outcome.Error]));
              Applied := Outcome.Error = '';
              Reason := Outcome.Error;
            except
              on E: Exception do
              begin
                Reason := E.Message;
                TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
              end;
            end;
          // Genau eine Antwort, auch nach einer Ausnahme (S-05).
          AReply(Applied, Reason);
        end);
    end;
end;

procedure TAtlasCodeInsightManager.AcceptShowMessage(ASession: TLspSession);
var
  Manager: TAtlasCodeInsightManager;
begin
  Manager := Self;
  ASession.OnShowMessage :=
    procedure(AType: Integer; const AMessage: string)
    begin
      // Information und Protokoll gehören ins Diagnoseprotokoll, nicht ins Meldungsfenster.
      if AType > 2 then
        Exit;
      TAtlasMainThread.Queue(TAtlasFeature.Server,
        procedure
        var
          Messages: IOTAMessageServices;
          Group: IOTAMessageGroup;
          Severity: TAtlasNotificationSeverity;
        begin
          if (LiveManager <> Manager) or (Manager.FSession <> ASession) then
            Exit;
          Manager.Diagnose('window/showMessage: ' + AMessage);
          // Benachrichtigungszentrale (#601): Fehler (1) rot, Warnung (2) gelb; Meldungsfenster nur bei Show.
          if AType = 1 then
            Severity := TAtlasNotificationSeverity.Error
          else
            Severity := TAtlasNotificationSeverity.Warning;
          if TAtlasNotificationCenter.Default.Notify(TAtlasNotificationSources.Server, Severity,
            TAtlasStrings.Text(TAtlasTextId.NotificationsServerMessage), AMessage, Manager.LogActions) <>
            TAtlasNotificationMode.Show then
            Exit;
          if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
            Exit;
          Group := Messages.GetGroup('Atlas');
          if Group = nil then
            Group := Messages.AddMessageGroup('Atlas');
          Messages.AddTitleMessage('Atlas: ' + AMessage, Group);
        end);
    end;
end;

procedure TAtlasCodeInsightManager.RefreshProjects;
var
  Projects: TArray<string>;
begin
  // Open Tools API nur im Hauptthread.
  if (GetCurrentThreadId <> MainThreadID) or (GetTickCount - FProjectsChecked < 2000) then
    Exit;
  FProjectsChecked := GetTickCount;
  try
    Projects := GroupProjects;
    FSession.SetProjects(Projects);
    WatchProjects(Projects);
  except
    on E: Exception do
      Diagnose('Projektgruppe nicht gemeldet: ' + E.Message);
  end;
end;

procedure TAtlasCodeInsightManager.RefreshContexts;
var
  Context: TAtlasProjectContext;
  Changed: TArray<TAtlasProjectContext>;
begin
  // Open Tools API nur im Hauptthread.
  if (GetCurrentThreadId <> MainThreadID) or
    ((FContextsChecked <> 0) and (GetTickCount - FContextsChecked < 1000)) then
    Exit;
  FContextsChecked := GetTickCount;
  try
    // Mit Diagnose=1 prüfbar, ob die geerbten Optionen ankommen (#396).
    Changed := FSession.SetProjectContexts(TAtlasIdeProjectContext.Group);
    for Context in Changed do
      Diagnose('Projektkontext: ' + Context.Describe);
    // Andere Plattform oder Konfiguration: andere aktive {$IFDEF}-Zweige, Gliederung neu holen (#845).
    if Length(Changed) > 0 then
      TAtlasIdeOutlineCache.InvalidateAll;
  except
    on E: Exception do
      Diagnose('Projektkontext nicht gemeldet: ' + E.Message);
  end;
end;

procedure TAtlasCodeInsightManager.WatchProjects(const AProjects: TArray<string>);
begin
  try
    FFolderWatcher.SetRoots(TAtlasWatchedChanges.Roots(AProjects,
      function(const APath: string): Boolean
      begin
        // .git ist ein Ordner, in Worktrees und Submodulen eine Datei.
        Result := DirectoryExists(APath) or FileExists(APath);
      end));
  except
    on E: Exception do
      Diagnose('Ordner nicht beobachtet: ' + E.Message);
  end;
end;

procedure TAtlasCodeInsightManager.FlushFileChanges;
var
  Changes: TArray<TAtlasFileChange>;
begin
  if GetCurrentThreadId <> MainThreadID then
    Exit;
  Changes := FFileChanges.Take(GetTickCount);
  if Changes = nil then
    Exit;
  try
    FSession.FilesChanged(Changes);
    Diagnose(Format('Änderungen außerhalb der IDE gemeldet: %d Dateien', [Length(Changes)]));
  except
    on E: Exception do
      Diagnose('Änderungen außerhalb der IDE nicht gemeldet: ' + E.Message);
  end;
end;

function TAtlasCodeInsightManager.CurrentEditView: IOTAEditView;
var
  Services: IOTACodeInsightServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    Services.GetEditView(Result);
  if Result = nil then
    Result := (BorlandIDEServices as IOTAEditorServices).TopView;
end;

function TAtlasCodeInsightManager.SessionOrNil: TLspSession;
begin
  if EnsureSession then
    Result := FSession
  else
    Result := nil;
end;

function TAtlasCodeInsightManager.ActiveSession: TLspSession;
begin
  Result := SessionOrNil;
end;

function TAtlasCodeInsightManager.CompletionVisible: Boolean;
begin
  Result := (FCompletion <> nil) and FCompletion.Visible;
end;

function TAtlasCodeInsightManager.PlaceholdersActive: Boolean;
begin
  Result := (FCompletion <> nil) and FCompletion.PlaceholdersActive;
end;

function TAtlasCodeInsightManager.RunningSession: TLspSession;
begin
  Result := nil;
  // Während StopSession nie: Die Sitzung wird gleich freigegeben (A-01). Aus jedem Thread aufrufbar.
  if FStopping then
    Exit;
  if (FServer <> nil) and FServer.Running and (FSession <> nil) and FSession.Initialized then
    Result := FSession;
end;

function TAtlasCodeInsightManager.ServerProgress: string;
begin
  if (FSession <> nil) and FSession.Initialized then
    Result := FSession.ProgressText
  else
    Result := '';
end;

procedure TAtlasCodeInsightManager.ExecuteServerCommandAsync(const ACommand: string; ATimeoutMs: Cardinal;
  const ADone: TProc<TJSONValue>);
var
  Command: string;
  Timeout: Cardinal;
begin
  Command := ACommand;
  Timeout := ATimeoutMs;
  // Start gehört dem Hauptthread (A-01); ohne Server gleich die Antwort „keine“.
  RunInBackground(SessionOrNil,
    function(ASession: TLspSession): TJSONValue
    begin
      Result := ASession.ExecuteCommand(Command, Timeout);
    end, ADone);
end;

procedure TAtlasCodeInsightManager.RunServerCommandAsync(const ACommand, AArgumentsJson: string;
  ATimeoutMs: Cardinal; const ADone: TProc<TJSONValue>);
var
  Command, Arguments: string;
  Timeout: Cardinal;
begin
  Command := ACommand;
  Arguments := AArgumentsJson;
  Timeout := ATimeoutMs;
  RunInBackground(RunningSession,
    function(ASession: TLspSession): TJSONValue
    begin
      Result := ASession.RunCommand(Command, Arguments, Timeout);
    end, ADone);
end;

procedure TAtlasCodeInsightManager.RunInBackground(ASession: TLspSession;
  const AWork: TFunc<TLspSession, TJSONValue>; const ADone: TProc<TJSONValue>);
var
  Session: TLspSession;
  Idle: TEvent;
  Work: TFunc<TLspSession, TJSONValue>;
  Done: TProc<TJSONValue>;
begin
  Done := ADone;
  Session := ASession;
  if Session = nil then
  begin
    if Assigned(Done) then
      Done(nil);
    Exit;
  end;
  Work := AWork;
  if AtomicIncrement(FServerCommands) = 1 then
    FServerCommandsIdle.ResetEvent;
  Idle := FServerCommandsIdle;
  FThreads.Start(
    procedure
    var
      Answer: TJSONValue;
      Json: string;
    begin
      try
        Json := '';
        Answer := nil;
        try
          Answer := Work(Session);
          if Answer <> nil then
            Json := Answer.ToJSON;
        except
          // Fehler, Zeitlimit oder geschlossene Verbindung: Antwort „keine“.
          on Exception do
            Json := '';
        end;
        Answer.Free;
        // Als Text in den Hauptthread: Verwirft TAtlasMainThread den Eintrag (Entladen), bleibt nichts liegen.
        TAtlasMainThread.Queue(TAtlasFeature.Server,
          procedure
          var
            Value: TJSONValue;
          begin
            Value := nil;
            if Json <> '' then
              Value := TJSONObject.ParseJSONValue(Json);
            try
              if Assigned(Done) then
                Done(Value);
            finally
              Value.Free;
            end;
          end);
      finally
        // Danach nichts mehr am Manager: StopSession wartet genau auf dieses Signal.
        if AtomicDecrement(FServerCommands) = 0 then
          Idle.SetEvent;
      end;
    end);
end;

function TAtlasCodeInsightManager.RunServerCommand(const ACommand, AArgumentsJson: string;
  ATimeoutMs: Cardinal): TJSONValue;
var
  Session: TLspSession;
begin
  Result := nil;
  Session := RunningSession;
  if Session = nil then
    Exit;
  try
    Result := Session.RunCommand(ACommand, AArgumentsJson, ATimeoutMs);
  except
    on E: Exception do
      Diagnose('Befehl ' + ACommand + ' fehlgeschlagen: ' + E.ClassName);
  end;
end;

function TAtlasCodeInsightManager.Signature: TAtlasEditorSignature;
begin
  if FSignature = nil then
    FSignature := TAtlasEditorSignature.Create(
      FAdapters.NewSignatureSource(
        function: TLspSession
        begin
          // Im Hauptthread beim Öffnen des Hints: nur eine laufende Sitzung, nie ein Start (A-01).
          Result := RunningSession;
        end),
      function: Boolean
      begin
        Result := (FCompletion <> nil) and FCompletion.Visible;
      end,
      procedure(const AMessage: string)
      begin
        Diagnose(AMessage);
      end);
  Result := FSignature;
end;

function TAtlasCodeInsightManager.Completion: TAtlasEditorCompletion;
begin
  if FCompletion = nil then
  begin
    FCompletion := TAtlasEditorCompletion.Create(
      function: TLspSession
      begin
        // Aufgerufen im Zeitlimit-Arbeiter (#493): nur eine laufende Sitzung, nie ein Start (A-01).
        Result := RunningSession;
      end,
      procedure(const AMessage: string)
      begin
        Diagnose(AMessage);
      end,
      FAdapters.NewCompletionSources);
    // Nach "Add(|)" den Parameter-Hint öffnen (#430).
    FCompletion.OnOpenSignature :=
      procedure
      begin
        Signature.Invoke(CurrentEditView);
      end;
  end;
  Result := FCompletion;
end;

function TAtlasCodeInsightManager.GetHintText(HintLine, HintCol: Integer): string;
var
  View: IOTAEditView;
  Text, DebugText: string;
  Lines: TArray<string>;
  Character: Integer;
  Activity: IInterface;
begin
  Activity := TAtlasActivity.Scope('Symbolhinweis');
  Result := '';
  // Durch die Sicherung abgeschaltet (#493, Code-Review S-05).
  if TAtlasGuard.Disabled(TAtlasFeature.Hover) then
    Exit;
  Diagnose(Format('GetHintText(%d, %d) aufgerufen', [HintLine, HintCol]));
  // Eigener Tooltip (#442): die IDE zeigt keinen zweiten.
  if TAtlasIdeSettings.Current.HoverTooltip then
    Exit;
  try
    View := CurrentEditView;
    if (View = nil) or (View.Buffer = nil) or not EnsureSession then
      Exit;
    Text := TAtlasEditorBuffer.Text(View.Buffer);
    Lines := Text.Split([#13#10, #10]);
    if (HintLine < 1) or (HintLine > Length(Lines)) then
      Exit;
    Character := TLspSession.ColumnToIndex(Lines[HintLine - 1], HintCol, TAtlasEditorBuffer.TabWidth(View.Buffer));
    Result := FSession.Hover(View.Buffer.FileName, Text, HintLine - 1, Character);
    // Wert im angehaltenen Debugger (#891) vor dem Hover-Text; nur sofort verfügbare Werte, die IDE wartet nicht.
    if TAtlasIdeSettings.Current.DebugHoverValues and TAtlasIdeDebugValues.Stopped then
    begin
      DebugText := TAtlasIdeDebugValues.EvaluateNow(TAtlasDebugExpression.AtCharacter(Lines[HintLine - 1],
        Character), View.Buffer.FileName, HintLine).PlainText;
      if (DebugText <> '') and (Result <> '') then
        Result := DebugText + #13#10#13#10 + Result
      else if DebugText <> '' then
        Result := DebugText;
    end;
    Diagnose(Format('Hover (%s), Zeile %d, Spalte %d (Cursor %d/%d): %d Zeichen', [ExtractFileExt(View.Buffer.FileName),
      HintLine, HintCol, View.CursorPos.Line, View.CursorPos.Col, Length(Result)]));
  except
    on E: Exception do
    begin
      ReportError('Hover: ' + E.Message);
      ReportFailure(TAtlasFeature.Hover, E);
      Result := '';
    end;
  end;
end;

function TAtlasCodeInsightManager.GotoDefinition(out AFileName: string; out ALineNum: Integer;
  Index: Integer): Boolean;
var
  View: IOTAEditView;
  Text: string;
  Lines: TArray<string>;
  Cursor: TOTAEditPos;
  Character: Integer;
  Location: TLspLocation;
  Activity: IInterface;
begin
  Activity := TAtlasActivity.Scope('Gehe zu Definition');
  // Laut ToolsAPI: AFileName = '' und ALineNum = 0 bricht ohne Meldung ab.
  // Mit False meldet die IDE „Datei "" nicht gefunden“; deshalb True.
  AFileName := '';
  ALineNum := 0;
  Result := True;
  // Durch die Sicherung abgeschaltet (#493, Code-Review S-05); AFileName = '' bricht still ab.
  if TAtlasGuard.Disabled(TAtlasFeature.GoToDefinition) then
    Exit;
  Diagnose(Format('GotoDefinition(Index %d) aufgerufen', [Index]));
  try
    View := CurrentEditView;
    if (View = nil) or (View.Buffer = nil) then
    begin
      Diagnose('Gehe zu Definition: keine Editoransicht');
      Exit;
    end;
    if not EnsureSession then
      Exit;
    Text := TAtlasEditorBuffer.Text(View.Buffer);
    Lines := Text.Split([#13#10, #10]);
    // Die synchrone Schnittstelle übergibt keine Klickposition; maßgeblich ist der Cursor.
    Cursor := View.CursorPos;
    if (Cursor.Line < 1) or (Cursor.Line > Length(Lines)) then
    begin
      Diagnose(Format('Gehe zu Definition: Cursorzeile %d außerhalb des Puffers (%d Zeilen)',
        [Cursor.Line, Length(Lines)]));
      Exit;
    end;
    Character := TLspSession.ColumnToIndex(Lines[Cursor.Line - 1], Cursor.Col, TAtlasEditorBuffer.TabWidth(View.Buffer));
    if FSession.Definition(View.Buffer.FileName, Text, Cursor.Line - 1, Character, Location) then
    begin
      AFileName := Location.FileName;
      ALineNum := Location.Line + 1;
    end;
    Diagnose(Format('Gehe zu Definition (Index %d) (%s), Zeile %d, Spalte %d (Zeichen %d): %s',
      [Index, ExtractFileExt(View.Buffer.FileName), Cursor.Line, Cursor.Col, Character,
       IfThen(AFileName <> '', Format('%s, Zeile %d', [ExtractFileExt(AFileName), ALineNum]), 'keine Definition')]));
  except
    on E: Exception do
    begin
      ReportError('Gehe zu Definition: ' + E.Message);
      ReportFailure(TAtlasFeature.GoToDefinition, E);
      AFileName := '';
      ALineNum := 0;
    end;
  end;
end;

function TAtlasCodeInsightManager.GetName: string;
begin
  Result := ManagerName;
end;

function TAtlasCodeInsightManager.GetIDString: string;
begin
  Result := ManagerId;
end;

function TAtlasCodeInsightManager.GetDisplayName: string;
begin
  Result := ManagerName;
end;

function TAtlasCodeInsightManager.GetOptionSetName: string;
begin
  // Dieselben Editoreinstellungen wie der eingebaute Delphi-Manager.
  Result := 'Borland.EditOptions.Pascal';
end;

class function TAtlasCodeInsightManager.OwnTooltip: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.HoverTooltip;
end;

function TAtlasCodeInsightManager.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  // Ohne IOTACodeInsightManager90 holt sich die IDE Help Insight anderswo (DelphiLSP) und zeigt
  // es neben dem Atlas-Tooltip. Mit dem Atlas-Tooltip aus bleibt es beim Verhalten der IDE.
  if IsEqualGUID(IID, IOTACodeInsightManager90) and not OwnTooltip then
  begin
    Pointer(Obj) := nil;
    Exit(E_NOINTERFACE);
  end;
  Result := inherited QueryInterface(IID, Obj);
end;

function TAtlasCodeInsightManager.GetHelpInsightHtml: WideString;
begin
  // Der Atlas-Tooltip zeigt alles; die IDE soll keinen zweiten Tooltip öffnen.
  Result := '';
  Diagnose('GetHelpInsightHtml aufgerufen');
end;

function TAtlasCodeInsightManager.GetEnabled: Boolean;
begin
  Result := FEnabled;
end;

procedure TAtlasCodeInsightManager.SetEnabled(Value: Boolean);
begin
  FEnabled := Value;
  Diagnose('SetEnabled(' + BoolToStr(Value, True) + ')');
  if not Value then
    StopSession;
end;

function TAtlasCodeInsightManager.EditorTokenValidChars(PreValidating: Boolean): TSysCharSet;
begin
  Result := ['A'..'Z', 'a'..'z', '0'..'9', '_', '&'];
  if PreValidating then
    Include(Result, '.');
end;

procedure TAtlasCodeInsightManager.AllowCodeInsight(var Allow: Boolean; const Key: Char);
begin
  Allow := False;
  try
    // #0 Vervollständigung (Strg+Leer), "." Vervollständigung nach Punkt, #2 Browse
    // (Strg+Klick), #3 Symbolhinweis; #1 Parameterhilfe (Strg+Umschalt+Leer), "(" und ",".
    // "<" nur für XMLDoc-Tags in ///-Kommentaren (#435), siehe GetCodeInsightType. "[" für Mengen (#448): Der
    // Server liefert nur in einem Mengenkonstruktor etwas, sonst bleibt das Popup zu.
    Allow := CharInSet(Key, [#0, '.', #1, '(', ',', #2, #3, '<', '[']);
    Diagnose(Format('AllowCodeInsight(#%d) = %s', [Ord(Key), BoolToStr(Allow, True)]));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
  end;
end;

function TAtlasCodeInsightManager.PreValidateCodeInsight(const Str: string): Boolean;
begin
  Result := True;
end;

function TAtlasCodeInsightManager.IsViewerBrowsable(Index: Integer): Boolean;
begin
  Result := False;
end;

function TAtlasCodeInsightManager.GetMultiSelect: Boolean;
begin
  Result := False;
end;

procedure TAtlasCodeInsightManager.GetSymbolList(out SymbolList: IOTACodeInsightSymbolList);
begin
  SymbolList := nil;
end;

procedure TAtlasCodeInsightManager.OnEditorKey(Key: Char; var CloseViewer: Boolean; var Accept: Boolean);
begin
  try
    CloseViewer := True;
    Accept := False;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
  end;
end;

function TAtlasCodeInsightManager.ServerAvailable: Boolean;
var
  Arguments, Path: string;
begin
  if (FServerChecked = 0) or (GetTickCount - FServerChecked > 5000) then
  begin
    FServerChecked := GetTickCount;
    Path := ServerPath(Arguments);
    FServerFound := FileExists(Path);
    if not FServerFound then
      ReportError('Server nicht gefunden: ' + Path + ' (die eingebaute Code Insight bleibt aktiv)');
  end;
  Result := FServerFound;
end;

function TAtlasCodeInsightManager.Handles(const AFileName: string): Boolean;
var
  Extension: string;
begin
  // Nach Shutdown (abgemeldet, die IDE hält den Manager noch): nichts mehr übernehmen (#886).
  if FShutDown then
    Exit(False);
  Extension := LowerCase(ExtractFileExt(AFileName));
  // Hauptschalter (#407): ausgeschaltet übernimmt die eingebaute Code Insight; ebenso ohne Server.
  Result := TAtlasIdeSettings.Current.Enabled and not TAtlasGuard.Disabled(TAtlasFeature.Completion) and
    ((Extension = '.pas') or (Extension = '.dpr') or (Extension = '.dpk') or (Extension = '.inc')) and ServerAvailable;
end;

function TAtlasCodeInsightManager.HandlesFile(const AFileName: string): Boolean;
begin
  Result := False;
  try
    Result := Handles(AFileName);
    Diagnose(Format('HandlesFile(%s) = %s', [ExtractFileExt(AFileName), BoolToStr(Result, True)]));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
  end;
end;

function TAtlasCodeInsightManager.GetLongestItem: string;
begin
  Result := 'constructor';
end;

procedure TAtlasCodeInsightManager.GetParameterList(out ParameterList: IOTACodeInsightParameterList);
begin
  ParameterList := nil;
end;

function TAtlasCodeInsightManager.InXmlDocLine: Boolean;
var
  View: IOTAEditView;
begin
  View := CurrentEditView;
  Result := (View <> nil) and (View.Buffer <> nil) and
    TrimLeft(TAtlasEditorBuffer.LineText(View, View.CursorPos.Line)).StartsWith('///');
end;

function TAtlasCodeInsightManager.InDebugDisplayLine: Boolean;
var
  View: IOTAEditView;
  Line, Template: string;
  Column: Integer;
  Names: TArray<string>;
begin
  View := CurrentEditView;
  Result := False;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Line := TAtlasEditorBuffer.LineText(View, View.CursorPos.Line);
  Result := TDebugDisplayText.CommentTemplate(Line, Template, Column) or
    TDebugDisplayText.AttributeTemplate(Line, Template, Column) or TDebugDisplayText.CommentChildren(Line, Names) or
    TDebugDisplayText.AttributeChildren(Line, Names);
end;

function TAtlasCodeInsightManager.InDataNameString(ATypedQuote: Boolean): Boolean;
var
  View: IOTAEditView;
  Line: string;
  Character: Integer;
begin
  Result := False;
  View := CurrentEditView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Line := TAtlasEditorBuffer.LineText(View, View.CursorPos.Line);
  Character := TLspSession.ColumnToIndex(Line, View.CursorPos.Col, TAtlasEditorBuffer.TabWidth(View.Buffer));
  Result := TAtlasWord.InDataNameString(Line, Character);
  if not Result and ATypedQuote then
  begin
    Insert('''', Line, Character + 1);
    Result := TAtlasWord.InDataNameString(Line, Character + 1);
  end;
end;

procedure TAtlasCodeInsightManager.GetCodeInsightType(AChar: Char; AElement: Integer;
  out CodeInsightType: TOTACodeInsightType; out InvokeType: TOTAInvokeType);
begin
  CodeInsightType := citNone;
  InvokeType := itManual;
  try
    InvokeType := itManual;
    case AChar of
      #0: CodeInsightType := citCodeInsight;
      '.':
        begin
          // Nach der in den Editoroptionen eingestellten Verzögerung.
          CodeInsightType := citCodeInsight;
          InvokeType := itTimer;
        end;
      #1: CodeInsightType := citParameterCodeInsight;
      '(', ',':
        begin
          CodeInsightType := citParameterCodeInsight;
          InvokeType := itTimer;
        end;
      '<', '[':
        begin
          CodeInsightType := citCodeInsight;
          InvokeType := itTimer;
        end;
      // Nach dem ";" hinter einem übernommenen Konstruktor „Mit try…finally absichern“ (#489).
      ';':
        if Completion.GuardPending(CurrentEditView) then
        begin
          CodeInsightType := citCodeInsight;
          InvokeType := itTimer;
        end;
      // Nach { in einer Wertdarstellung die Mitglieder des Typs (#854).
      '{':
        if InDebugDisplayLine then
        begin
          CodeInsightType := citCodeInsight;
          InvokeType := itTimer;
        end;
      // Nach FieldByName(' die Feldnamen (#461).
      '''':
        if InDataNameString(True) then
        begin
          CodeInsightType := citCodeInsight;
          InvokeType := itTimer;
        end;
      #2: CodeInsightType := citBrowseCodeInsight;
      #3: CodeInsightType := citHintCodeInsight;
    else
      CodeInsightType := citNone;
    end;
    // In Kommentaren und Strings keine Vervollständigung (#435); Ausnahme: XMLDoc-Tags in ///-Zeilen.
    // "<" außerhalb davon ist ein Vergleich, keine Auslösung.
    if (CodeInsightType = citCodeInsight) and ((AChar = '<') or (AElement = atComment)) and InXmlDocLine then
      // Vervollständigung bleibt; die XMLDoc-Quelle liefert die Tags.
    else if (CodeInsightType = citCodeInsight) and (AElement = atString) and InDataNameString(AChar = '''') then
      // Feld- und Parameternamen (#461): Vervollständigung im String, die Namen kommen vom Server.
    else if (CodeInsightType = citCodeInsight) and ((AElement = atComment) or (AElement = atString)) and
      InDebugDisplayLine then
      // Platzhalter in Wertdarstellungen (#854): die Mitglieder des Typs kommen vom Server.
    else if (AChar = '<') or ((CodeInsightType in [citCodeInsight, citParameterCodeInsight]) and
      ((AElement = atComment) or (AElement = atString))) then
      CodeInsightType := citNone;
    Diagnose(Format('GetCodeInsightType(#%d, Element %d) = %d', [Ord(AChar), AElement, Ord(CodeInsightType)]));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
  end;
end;

function TAtlasCodeInsightManager.InvokeCodeCompletion(HowInvoked: TOTAInvokeType; var Str: string): Boolean;
var
  Activity: IInterface;
begin
  Activity := TAtlasActivity.Scope('Vervollständigung öffnen');
  // False: Die IDE zeigt keine eigene Liste; unser Popup übernimmt (#407, #410).
  Result := False;
  Diagnose(Format('InvokeCodeCompletion(%d, %d Zeichen)', [Ord(HowInvoked), Length(Str)]));
  try
    // Start nur hier im Hauptthread (A-01); die Quellen bekommen danach die laufende Sitzung.
    // Ohne Server liefern die übrigen Quellen trotzdem.
    EnsureSession;
    Completion.Invoke(CurrentEditView, HowInvoked <> itManual);
  except
    on E: Exception do
    begin
      ReportError('Vervollständigung: ' + E.Message);
      ReportFailure(TAtlasFeature.Completion, E);
    end;
  end;
end;

function TAtlasCodeInsightManager.InvokeParameterCodeInsight(HowInvoked: TOTAInvokeType;
  var SelectedIndex: Integer): Boolean;
var
  Activity: IInterface;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TAtlasGuard.Disabled(TAtlasFeature.Signature) then
    Exit(False);
  Activity := TAtlasActivity.Scope('Parameterhilfe');
  // False: Die IDE zeigt keine eigene Parameterhilfe; unser Hint übernimmt (#436).
  Result := False;
  Diagnose(Format('InvokeParameterCodeInsight(%d)', [Ord(HowInvoked)]));
  try
    // Start nur hier im Hauptthread (A-01).
    EnsureSession;
    Signature.Invoke(CurrentEditView);
  except
    on E: Exception do
    begin
      ReportError('Parameterhilfe: ' + E.Message);
      ReportFailure(TAtlasFeature.Signature, E);
    end;
  end;
end;

procedure TAtlasCodeInsightManager.OpenCompletion;
begin
  if not FEnabled or TAtlasGuard.Disabled(TAtlasFeature.Completion) or not ServerAvailable then
    Exit;
  Diagnose('Vervollständigung über eigene Taste');
  try
    // Start nur hier im Hauptthread (A-01).
    EnsureSession;
    Completion.Invoke(CurrentEditView);
  except
    on E: Exception do
    begin
      ReportError('Vervollständigung: ' + E.Message);
      ReportFailure(TAtlasFeature.Completion, E);
    end;
  end;
end;

procedure TAtlasCodeInsightManager.OpenSignature;
begin
  if not FEnabled or TAtlasGuard.Disabled(TAtlasFeature.Signature) or not ServerAvailable then
    Exit;
  Diagnose('Parameterhilfe über eigene Taste');
  try
    // Start nur hier im Hauptthread (A-01).
    EnsureSession;
    Signature.Invoke(CurrentEditView);
  except
    on E: Exception do
    begin
      ReportError('Parameterhilfe: ' + E.Message);
      ReportFailure(TAtlasFeature.Signature, E);
    end;
  end;
end;

procedure TAtlasCodeInsightManager.ParameterCodeInsightAnchorPos(var EdPos: TOTAEditPos);
begin
end;

function TAtlasCodeInsightManager.ParameterCodeInsightParamIndex(EdPos: TOTAEditPos): Integer;
begin
  Result := -1;
end;

procedure TAtlasCodeInsightManager.Done(Accepted: Boolean; out DisplayParams: Boolean);
begin
  DisplayParams := False;
  try
    DisplayParams := False;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Completion, E);
  end;
end;

procedure TAtlasCodeInsightManager.NotifySaved(const AFileName: string);
begin
  if (FSession = nil) or not FSession.Initialized then
    Exit;
  try
    FSession.Saved(AFileName);
  except
    on E: Exception do
      Diagnose('didSave nicht gesendet: ' + E.Message);
  end;
end;

procedure TAtlasCodeInsightManager.NotifyServer(const AMethod: string; AParams: TJSONObject);
begin
  // Nur eine laufende Sitzung; für eine Meldung startet der Server nicht.
  if (FSession = nil) or not FSession.Initialized then
  begin
    AParams.Free;
    Exit;
  end;
  try
    FSession.Notify(AMethod, AParams);
  except
    on E: Exception do
      Diagnose(Format('%s nicht gesendet: %s', [AMethod, E.Message]));
  end;
end;

procedure TAtlasCodeInsightManager.Log(const AMessage: string);
begin
  Diagnose(AMessage);
end;

procedure TAtlasCodeInsightManager.Report(const AMessage: string);
begin
  try
    TFile.AppendAllText(DiagnoseLog, FormatDateTime('hh":"nn":"ss.zzz', Now) + ' ' + WithoutPaths(AMessage) + sLineBreak,
      TEncoding.UTF8);
  except
    // Protokoll ist Beiwerk; ein gesperrtes Log darf die IDE nicht stören.
  end;
end;
end.
