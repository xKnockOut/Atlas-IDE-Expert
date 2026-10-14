unit Atlas.IDE.CodeInsight.Manager;

// Code Insight-Manager für Delphi in RAD Studio (ADR 0006). Die IDE ruft ihn
// direkt auf; er fragt Atlas über eine eigene LSP-Sitzung.
// Umgesetzt: Symbolhinweis (Hover, GetHintText), Browse (Strg+Klick,
// GotoDefinition) und Vervollständigung im eigenen Popup (#410): Strg+Leer und
// "." lösen sie aus, InvokeCodeCompletion öffnet das Popup und meldet der IDE
// False, damit sie keine eigene Liste zeigt (#407). Parameterhilfe ebenso im eigenen
// Hint (#436): "(", "," und Strg+Umschalt+Leer, InvokeParameterCodeInsight meldet False.
//
// Server: Pfad und Argumente aus HKCU\Software\Atlas\IdePlugin
// (ServerPath, ServerArguments), ersatzweise aus dem früheren Schlüssel
// HKCU\Software\BetterDelphiLSP\IdePlugin (#403). Ohne Eintrag: AtlasServer.exe neben dem
// Plugin, sonst ..\..\..\Win64\Debug\Bin\ (Ausgabeordner des Repos).
// Diagnose = 1 (DWORD) im selben Schlüssel protokolliert die Aufrufe der IDE
// in Atlas.IDE.Expert.log neben dem Plugin.
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

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  ToolsAPI,
  Atlas.Core.Lsp.Adapters.ServerProcess,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Files.WatchedChanges,
  Atlas.Core.Files.Adapters.FolderWatcher,
  Atlas.IDE.Completion.Editor,
  Atlas.IDE.Signature.Editor,
  Atlas.IDE.Hover.Editor,
  Atlas.IDE.Problems.Controller;

type
  TAtlasCodeInsightManager = class(TInterfacedObject, IOTACodeInsightManager, IOTACodeInsightSelection)
  private
    FEnabled: Boolean;
    FServer: TLspServerProcess;
    FSession: TLspSession;
    FLastError: string;
    // Ob AtlasServer.exe da ist, höchstens alle paar Sekunden neu geprüft.
    FServerChecked: Cardinal;
    FServerFound: Boolean;
    // Zuletzt geprüfte Projektgruppe (#648).
    FProjectsChecked: Cardinal;
    /// <summary>Zuletzt geprüfter Projektkontext (#396).</summary>
    FContextsChecked: Cardinal;
    /// <summary>Änderungen außerhalb der IDE (#395).</summary>
    FFileChanges: TAtlasWatchedChanges;
    FFolderWatcher: TAtlasFolderWatcher;
    FDiagnose: Boolean;
    FCompletion: TAtlasEditorCompletion;
    FSignature: TAtlasEditorSignature;
    /// <summary>Eigener Hover-Tooltip (#442).</summary>
    FHover: TAtlasEditorHover;
    /// <summary>Probleme im Editor (#398).</summary>
    FProblems: TAtlasProblemsController;
    function EnsureSession: Boolean;
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
    /// <summary>Nimmt workspace/applyEdit der Sitzung an (#397).</summary>
    procedure AcceptApplyEdit(ASession: TLspSession);
    procedure ReportError(const AMessage: string);
    procedure Diagnose(const AMessage: string);
    function CurrentEditView: IOTAEditView;
    /// <summary>Cursorzeile ist ein ///-Kommentar (XMLDoc, #435).</summary>
    function InXmlDocLine: Boolean;
    function Completion: TAtlasEditorCompletion;
    function Signature: TAtlasEditorSignature;
    function SessionOrNil: TLspSession;
    class function ServerPath(out AArguments: string): string; static;
    /// <summary>Gibt es den Server? Ohne ihn übernimmt die eingebaute Code Insight.</summary>
    function ServerAvailable: Boolean;
    class function DiagnoseEnabled: Boolean; static;
  public
    /// <summary>Protokolldatei neben dem Plugin.</summary>
    class function DiagnoseLog: string; static;
    /// <summary>Server ohne eingestellten Pfad: neben dem Plugin, sonst Output\Win64\Debug\Bin im Repo.</summary>
    class function DefaultServerPath: string; static;
    constructor Create;
    destructor Destroy; override;
    /// <summary>Benachrichtigung an den Server, falls eine Sitzung läuft (#527); übernimmt AParams.
    /// Startet den Server dafür nicht.</summary>
    procedure NotifyServer(const AMethod: string; AParams: TJSONObject);
    /// <summary>Fortschritt des Servers ("Index 45 %"); '' ohne Sitzung oder Vorgang. Startet keinen Server (#492).</summary>
    function ServerProgress: string;
    /// <summary>Befehl an den Server (startet ihn bei Bedarf); Ergebnis gehört dem Aufrufer, nil bei Fehler.</summary>
    function ExecuteServerCommand(const ACommand: string; ATimeoutMs: Cardinal = 30000): TJSONValue;
    /// <summary>Laufende Sitzung, Server bei Bedarf gestartet; nil, wenn er nicht startet (Hauptthread).</summary>
    function ActiveSession: TLspSession;
    /// <summary>Gespeichert: didSave an den Server, falls eine Sitzung läuft (Prüfung mit dcc).</summary>
    procedure NotifySaved(const AFileName: string);
    /// <summary>Zeile im Diagnoseprotokoll (nur mit Diagnose = 1).</summary>
    procedure Log(const AMessage: string);
    /// <summary>Zeile im Protokoll unabhängig von Diagnose, z. B. Hänger (#501).</summary>
    procedure Report(const AMessage: string);
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
    { IOTACodeInsightSelection }
    function GetDisplayName: string;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  System.IOUtils,
  System.StrUtils,
  System.Win.Registry,
  Atlas.IDE.Settings.Store,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Problems.Contract,
  Winapi.Windows,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Projects.Context,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.IDE.Editor.WorkspaceEdit;

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

constructor TAtlasCodeInsightManager.Create;
begin
  inherited Create;
  LiveManager := Self;
  FEnabled := True;
  FDiagnose := DiagnoseEnabled;
  Diagnose('Plugin geladen: ' + GetModuleName(HInstance));
  FFileChanges := TAtlasWatchedChanges.Create;
  FFolderWatcher := TAtlasFolderWatcher.Create(FFileChanges);
  FProblems := TAtlasProblemsController.Create(
    function(AStart: Boolean): TLspSession
    begin
      if AStart and EnsureSession then
        Result := FSession
      else if (FServer <> nil) and FServer.Running and (FSession <> nil) and FSession.Initialized then
        Result := FSession
      else
        Result := nil;
    end,
    procedure(const AMessage: string)
    begin
      Diagnose(AMessage);
    end);
  FHover := TAtlasEditorHover.Create(
    function: TLspSession
    begin
      if EnsureSession then
        Result := FSession
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
    end);
end;

destructor TAtlasCodeInsightManager.Destroy;
begin
  if LiveManager = Self then
    LiveManager := nil;
  // Hält die Beobachter-Threads an; erst danach darf der Sammler weg.
  FreeAndNil(FFolderWatcher);
  FreeAndNil(FFileChanges);
  // Vor der Sitzung: wartet auf laufende Anfragen und meldet Tasten und Beobachter ab.
  FreeAndNil(FHover);
  FreeAndNil(FSignature);
  FreeAndNil(FCompletion);
  StopSession;
  // Nach StopSession: Die Threads sind dort schon angehalten.
  FreeAndNil(FProblems);
  inherited;
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
  // Ausgabeordner des Repos: Win64 bevorzugt, sonst ein Win32-Bau des Servers.
  Result := ExpandFileName(PluginDir + '..\..\..\Win64\Debug\Bin\AtlasServer.exe');
  if not FileExists(Result) and FileExists(ExpandFileName(PluginDir + '..\..\..\Win32\Debug\Bin\AtlasServer.exe')) then
    Result := ExpandFileName(PluginDir + '..\..\..\Win32\Debug\Bin\AtlasServer.exe');
end;

procedure TAtlasCodeInsightManager.ReportError(const AMessage: string);
var
  Messages: IOTAMessageServices;
begin
  Diagnose('Fehler: ' + AMessage);
  // Jede Meldung nur einmal, sonst flutet ein fehlender Server das Meldungsfenster.
  if AMessage = FLastError then
    Exit;
  FLastError := AMessage;
  if Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Messages.AddTitleMessage('Atlas: ' + AMessage);
end;

procedure TAtlasCodeInsightManager.Diagnose(const AMessage: string);
begin
  if not FDiagnose then
    Exit;
  try
    TFile.AppendAllText(DiagnoseLog, FormatDateTime('hh:nn:ss.zzz', Now) + ' ' + AMessage + sLineBreak,
      TEncoding.UTF8);
  except
    // Diagnose darf die IDE nie stören.
  end;
end;

procedure TAtlasCodeInsightManager.StopSession;
begin
  // Laufende Anfragen der Vervollständigung nutzen die Sitzung noch.
  if FCompletion <> nil then
    FCompletion.Shutdown;
  if FSignature <> nil then
    FSignature.Shutdown;
  // Probleme: Threads anhalten, Verbindung schließen (laufende Anfragen kehren sofort zurück), warten.
  if FProblems <> nil then
    FProblems.BeginShutdown;
  if FServer <> nil then
    FServer.Client.Close;
  if FProblems <> nil then
    FProblems.WaitShutdown;
  FreeAndNil(FSession);
  FreeAndNil(FServer);
end;

function TAtlasCodeInsightManager.EnsureSession: Boolean;
var
  Path, Arguments: string;
  Documents: TArray<TLspOpenDocument>;
  Projects: TArray<string>;
begin
  if (FServer <> nil) and FServer.Running and (FSession <> nil) and FSession.Initialized then
  begin
    RefreshContexts;
    RefreshProjects;
    FlushFileChanges;
    Exit(True);
  end;
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
    Exit(False);
  end;
  try
    FServer := TLspServerProcess.Create(Path, Arguments);
    FSession := TLspSession.Create(FServer.Client);
    FContextsChecked := 0;
    RefreshContexts;
    AcceptApplyEdit(FSession);
    Projects := GroupProjects;
    FSession.SetProjects(Projects);
    WatchProjects(Projects);
    FProjectsChecked := GetTickCount;
    FSession.Initialize;
    if Documents <> nil then
    begin
      FSession.Reopen(Documents);
      Diagnose(Format('Nach Neustart erneut geöffnet: %d Dateien', [Length(Documents)]));
    end;
    FLastError := '';
    Result := True;
  except
    on E: Exception do
    begin
      ReportError('Start fehlgeschlagen: ' + E.Message);
      StopSession;
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
      // Lese-Thread: Open Tools API nur im Hauptthread.
      TThread.Queue(nil,
        procedure
        var
          Outcome: TAtlasWorkspaceEditResult;
        begin
          // Manager weg oder neue Sitzung: Die alte Verbindung gibt es nicht mehr.
          if (LiveManager <> Manager) or (Manager.FSession <> ASession) then
            Exit;
          if AEdit.Unsupported > 0 then
          begin
            AReply(False, 'Dateioperationen (anlegen, umbenennen, löschen) werden nicht unterstützt.');
            Exit;
          end;
          try
            Outcome := TAtlasIdeWorkspaceEdit.Apply(AEdit, TAtlasIdeSettings.Current.OpenForEdits);
          except
            on E: Exception do
            begin
              AReply(False, E.Message);
              Exit;
            end;
          end;
          Manager.Diagnose(Format('workspace/applyEdit: %d Änderungen in %d Dateien %s', [Outcome.Edits,
            Outcome.Files, Outcome.Error]));
          AReply(Outcome.Error = '', Outcome.Error);
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
begin
  // Open Tools API nur im Hauptthread.
  if (GetCurrentThreadId <> MainThreadID) or
    ((FContextsChecked <> 0) and (GetTickCount - FContextsChecked < 1000)) then
    Exit;
  FContextsChecked := GetTickCount;
  try
    FSession.SetProjectContexts(TAtlasIdeProjectContext.Group);
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

function TAtlasCodeInsightManager.ServerProgress: string;
begin
  if (FSession <> nil) and FSession.Initialized then
    Result := FSession.ProgressText
  else
    Result := '';
end;

function TAtlasCodeInsightManager.ExecuteServerCommand(const ACommand: string; ATimeoutMs: Cardinal): TJSONValue;
var
  Session: TLspSession;
begin
  Session := SessionOrNil;
  if Session = nil then
    Exit(nil);
  Result := Session.ExecuteCommand(ACommand, ATimeoutMs);
end;

function TAtlasCodeInsightManager.Signature: TAtlasEditorSignature;
begin
  if FSignature = nil then
    FSignature := TAtlasEditorSignature.Create(
      function: TLspSession
      begin
        Result := SessionOrNil;
      end,
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
        Result := SessionOrNil;
      end,
      procedure(const AMessage: string)
      begin
        Diagnose(AMessage);
      end);
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
  Text: string;
  Lines: TArray<string>;
  Activity: IInterface;
begin
  Activity := TAtlasActivity.Scope('Symbolhinweis');
  Result := '';
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
    Result := FSession.Hover(View.Buffer.FileName, Text, HintLine - 1,
      TLspSession.ColumnToIndex(Lines[HintLine - 1], HintCol, TAtlasEditorBuffer.TabWidth(View.Buffer)));
    Diagnose(Format('Hover in %s, Zeile %d, Spalte %d (Cursor %d/%d): %s', [ExtractFileName(View.Buffer.FileName),
      HintLine, HintCol, View.CursorPos.Line, View.CursorPos.Col, IfThen(Result = '', 'leer', Result)]));
  except
    on E: Exception do
    begin
      ReportError('Hover: ' + E.Message);
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
    Diagnose(Format('Gehe zu Definition (Index %d) in %s, Zeile %d, Spalte %d (Zeichen %d): %s',
      [Index, ExtractFileName(View.Buffer.FileName), Cursor.Line, Cursor.Col, Character,
       IfThen(AFileName <> '', Format('%s, Zeile %d', [AFileName, ALineNum]), 'keine Definition')]));
  except
    on E: Exception do
    begin
      ReportError('Gehe zu Definition: ' + E.Message);
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
    // "<" nur für XMLDoc-Tags in ///-Kommentaren (#435), siehe GetCodeInsightType.
    Allow := CharInSet(Key, [#0, '.', #1, '(', ',', #2, #3, '<']);
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

function TAtlasCodeInsightManager.HandlesFile(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Result := False;
  try
    Extension := LowerCase(ExtractFileExt(AFileName));
    // Hauptschalter (#407): ausgeschaltet übernimmt die eingebaute Code Insight; ebenso ohne Server.
    Result := TAtlasIdeSettings.Current.Enabled and not TAtlasGuard.Disabled(TAtlasFeature.Completion) and ((Extension = '.pas') or (Extension = '.dpr') or
      (Extension = '.dpk') or (Extension = '.inc')) and ServerAvailable;
    Diagnose(Format('HandlesFile(%s) = %s', [AFileName, BoolToStr(Result, True)]));
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
      '<':
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
  Diagnose(Format('InvokeCodeCompletion(%d, "%s")', [Ord(HowInvoked), Str]));
  try
    Completion.Invoke(CurrentEditView);
  except
    on E: Exception do
      ReportError('Vervollständigung: ' + E.Message);
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
    Signature.Invoke(CurrentEditView);
  except
    on E: Exception do
      ReportError('Parameterhilfe: ' + E.Message);
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
    TFile.AppendAllText(DiagnoseLog, FormatDateTime('hh:nn:ss.zzz', Now) + ' ' + AMessage + sLineBreak,
      TEncoding.UTF8);
  except
    // Protokoll ist Beiwerk; ein gesperrtes Log darf die IDE nicht stören.
  end;
end;
end.
