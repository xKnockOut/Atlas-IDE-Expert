unit Atlas.IDE.Settings.Options;

// Meldet die Seite „Atlas“ unter Tools › Optionen › Drittanbieter an
// (INTAAddInOptions, #227) und verbindet sie mit den Einstellungen in der
// Registry. „Verlauf zurücksetzen“ leert die lernende Gewichtung (#418).
// Die Liste der angehefteten Favoriten (#458) kommt aus TAtlasIdeFavorites; „Entfernen“ wirkt sofort.
// Darunter die Seite „Snippets“ (#51): Code-Vorlagen ansehen, eigene anlegen,
// bearbeiten und löschen; gespeichert wird beim Schließen mit OK. Der Punkt
// in der Überschrift „Atlas.Snippets“ hängt die Seite unter „Atlas“.
// Daneben die Seite „Atlas.Tastenkonflikte“ (#494): Wer welche Taste belegt,
// fragt sie über TAtlasIdeKeys.Owner ab; nach dem Speichern belegt die
// Komposition die Tasten über Settings.OnChanged neu.
// Abschnitt Symbolindex (#492): Kennzahlen aus atlas.server.status, „Index neu
// aufbauen“ und „Index löschen“ über die Befehle des Servers, im Hintergrund
// (#874): Die Antwort kommt im Hauptthread und geht nur an die Seite, für die
// sie bestellt wurde (FGeneration), solange der Dialog offen ist.
// Seite „Atlas.Server“ (#227): globale und Projekt-Einstellungen des Servers im
// Dialog, Baseline neu erzeugen oder löschen, Unterdrückungen je Regel und
// Index-Cache löschen über AtlasServer.exe als Prozess (TAtlasServerTool).
// ShowSetting (#628, „Einstellungen dazu …“): öffnet Tools › Optionen, wählt
// die Seite „Atlas“ in der Baumansicht des Dialogs (soweit sie sich finden
// lässt) und zeigt dort die Einstellung mit markierter Zeile (Reveal).
// ShowRule (#909, „Regel einstellen…“ im Fenster „Atlas-Prüfung“ und im
// Befund-Hover) öffnet den Dialog der Projekt-Einstellungen (ohne Projekt den
// der globalen) im Knoten der Gruppe der Regel: Die Prüfregeln stehen nur
// dort, nicht in Tools › Optionen. Die Seite Prüfregeln zeigt den Weg dorthin.
// Seite Issue-Tracker (#1260): Anbieter, Token und „Verbindung prüfen“ über
// Hooks.Tracker (Komposition). Die Prüfung läuft im Hintergrund (höchstens
// 5 s, TAtlasTrackerChecks), ihr Ergebnis gilt je Server bis zum Entladen;
// Unregister wartet auf laufende Prüfungen. Das Protokoll nennt nur Anbieter
// und Zustand, nie Adresse oder Token.
// Dialog „Abfrage bearbeiten“ (#1263): „Testen“ fragt wie die Prüfung im
// Hintergrund (höchstens 5 s, TAtlasTrackerChecks.StartQueryTest); das
// Protokoll nennt nur Anbieter und Ergebnis, nie Adresse, Abfrage oder Token.
// Tabelle Projekte (#1261): aktives Projekt, geöffnete .groupproj und die
// Zeile aus dessen .atlas; ShowTrackerProject („zuordnen …“ aus „Meine
// Issues“) öffnet die Seite mit einer vorbefüllten Zeile.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Tracker.Connections,
  Atlas.UI.EditorToolbar.Customize;

type
  /// <summary>Befehl an den Server im Hintergrund (#874); ADone im Hauptthread mit der Antwort, nil ohne Server
  /// oder bei Fehler. Den Wert gibt der Aufrufer von ADone frei.</summary>
  TAtlasServerCommand = reference to procedure(ACommand: string; ADone: TProc<TJSONValue>);

  /// <summary>Was die Optionsseiten von anderen Features brauchen; setzt die Composition (A-09: die Seiten
  /// importieren Befehlszählung, Tipps, Code Insight-Manager und Vervollständigung nicht). Nicht gesetzte Haken
  /// bleiben ohne Wirkung bzw. liefern ''.</summary>
  TAtlasOptionsHooks = record
    /// <summary>Lernende Gewichtung zurücksetzen (#418).</summary>
    ResetHistory: TProc;
    /// <summary>Befehl an den Server (#492).</summary>
    Command: TAtlasServerCommand;
    /// <summary>Zählung der Befehle zurücksetzen (#757).</summary>
    ResetUsage: TProc;
    /// <summary>Gesperrte Tipps wieder zeigen (#757).</summary>
    UnblockTips: TProc;
    /// <summary>Atlas-Befehle der Palette für „Leiste anpassen …“ der Editorleiste (#1101).</summary>
    ToolbarCommands: TFunc<TArray<TAtlasToolbarCommandInfo>>;
    /// <summary>Pfad der AtlasServer.exe nach den Einstellungen.</summary>
    ServerPath: TFunc<string>;
    /// <summary>Pfad der mitgelieferten AtlasServer.exe.</summary>
    DefaultServerPath: TFunc<string>;
    /// <summary>Ordner der Live Templates der IDE (#487).</summary>
    IdeTemplateFolder: TFunc<string>;
    /// <summary>Ordner der eigenen Code-Vorlagen (#51).</summary>
    SnippetFolder: TFunc<string>;
    /// <summary>Anbieter, Token und Transport des Issue-Trackers (#1260); nil = Seite ohne Token und Prüfung.
    /// </summary>
    Tracker: IAtlasTrackerAccess;
  end;

  TAtlasOptionsRegistration = class
  public
    class procedure Register(const AHooks: TAtlasOptionsHooks); static;
    class procedure Unregister; static;
    /// <summary>Tools › Optionen öffnen und auf der Seite „Atlas“ die Einstellung AKey (Name der
    /// Plugin-Einstellung) zeigen und markieren (#628).</summary>
    class procedure ShowSetting(const AKey: string); static;
    /// <summary>„Regel einstellen…“ (#909): Tools › Optionen auf der Seite Prüfregeln bei der Regel ARuleId
    /// öffnen.</summary>
    class procedure ShowRule(const ARuleId: string); static;
    /// <summary>„zuordnen …“ (#1261): Tools › Optionen auf der Seite Issue-Tracker mit einer Zeile für AMatch
    /// (.dproj, .groupproj) in der Tabelle Projekte öffnen.</summary>
    class procedure ShowTrackerProject(const AMatch: string); static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Core.Diagnostics.Guard,
  System.Classes,
  System.UITypes,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.ActnList,
  Vcl.Menus,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.LiveTemplates,
  Atlas.Core.Completion.SnippetCatalog,
  Atlas.UI.Settings.SnippetsPage,
  ToolsAPI,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Progress,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Keys,
  Atlas.UI.Settings.ServerPage,
  Atlas.Core.Settings.Baseline,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Settings.ServerTool,
  Atlas.IDE.Settings.Transfer,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Keys,
  Atlas.Core.Completion.Favorites,
  Atlas.IDE.Completion.Favorites,
  Atlas.IDE.Foundation.StructureSwitch,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.QueryTest,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.TeamFile;

type
  TAtlasAddInOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasSettingsPage;
    /// <summary>Zählt die angelegten Seiten; eine späte Antwort für eine geschlossene Seite verfällt (#874).</summary>
    FGeneration: Integer;
    /// <summary>Führt ACommand im Hintergrund aus; AText macht aus der Antwort (nil ohne Server) den Text für
    /// die Seite.</summary>
    procedure Run(const ACommand: string; const AText: TFunc<TJSONValue, string>);
    /// <summary>Seite Issue-Tracker (#1260): Verbindung aus der .atlas, Anbieter, Token und Prüfung.</summary>
    procedure ConnectTracker;
    /// <summary>Seite Prüfregeln (#909): Katalog im Hintergrund holen und mit "rules" der globalen Datei
    /// übergeben.</summary>
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

  /// <summary>Seite „Tastenkonflikte“ (#494).</summary>
  TAtlasKeysOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasKeysPage;
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

  TAtlasSnippetOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasSnippetsPage;
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

  /// <summary>Seite „Server“ (#227).</summary>
  TAtlasServerOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasServerPage;
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

var
  Options: INTAAddInOptions;
  ServerOptions: INTAAddInOptions;
  SnippetOptions: INTAAddInOptions;
  KeysOptions: INTAAddInOptions;
  /// <summary>Gesetzt von Register, geleert von Unregister.</summary>
  Hooks: TAtlasOptionsHooks;
  /// <summary>Einstellung, die die Seite „Atlas“ beim nächsten Anlegen zeigen soll (#628); '' ohne.</summary>
  PendingReveal: string;
  /// <summary>„Gilt für“ einer Zeile, die die Seite Issue-Tracker beim nächsten Anlegen vorbefüllt (#1261).
  /// </summary>
  PendingTrackerProject: string;

type
  /// <summary>Sucht im offenen Optionsdialog die Seite „Atlas“ und wählt sie (#628).</summary>
  TAtlasOptionsSelector = class
  private const
    IntervalMs = 200;
    MaxTries = 50;
  private
    FTimer: TTimer;
    FTries: Integer;
    procedure Tick(Sender: TObject);
    class function FindTree(AParent: TWinControl): TTreeView; static;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
  end;

var
  Selector: TAtlasOptionsSelector;

type
  /// <summary>„Verbindung prüfen“ der Seite Issue-Tracker (#1260): eine Abfrage je Klick im Hintergrund, Ergebnis
  /// je Server (CredentialTarget) für diese Sitzung.</summary>
  TAtlasTrackerChecks = class
  private class var
    FStates: TDictionary<string, TAtlasTrackerTokenStatus>;
    FThreads: TList<TThread>;
    class procedure Finished(AThread: TThread; const AKey: string; const AStatus: TAtlasTrackerTokenStatus;
      const ADone: TProc); static;
  public
    /// <summary>Zustand ohne Netz: ohne Token „fehlt“, sonst das Ergebnis der letzten Prüfung oder „gespeichert“.
    /// </summary>
    class function State(const AAccess: IAtlasTrackerAccess;
      const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus; static;
    /// <summary>Nach „Token hinterlegen …“ oder Entfernen: Ergebnis der letzten Prüfung verwerfen.</summary>
    class procedure Forget(const AConnection: TAtlasTrackerConnection); static;
    /// <summary>Prüfung im Hintergrund; ADone danach im Hauptthread.</summary>
    class procedure Start(const AAccess: IAtlasTrackerAccess; const AConnection: TAtlasTrackerConnection;
      const ADone: TProc); static;
    /// <summary>„Testen“ einer Abfrage (#1263) im Hintergrund; ADone danach im Hauptthread.</summary>
    class procedure StartQueryTest(const AAccess: IAtlasTrackerAccess; const AConnection: TAtlasTrackerConnection;
      const ATarget: TAtlasTrackerTarget; const ADone: TAtlasQueryTestDone); static;
    /// <summary>Beim Entladen: auf laufende Prüfungen warten, Ergebnisse freigeben.</summary>
    class procedure Release; static;
  end;

const
  TrackerStateKeys: array[TAtlasTrackerTokenState] of string = ('missing', 'saved', 'verified', 'rejected',
    'unreachable', 'unexpected');

class function TAtlasTrackerChecks.State(const AAccess: IAtlasTrackerAccess;
  const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus;
var
  mTarget: TAtlasTrackerTarget;
begin
  mTarget := AConnection.Target;
  if (AAccess = nil) or not AAccess.HasToken(mTarget) then
    Exit(TAtlasTrackerTokenStatus.Stored(False));
  if (FStates <> nil) and FStates.TryGetValue(LowerCase(mTarget.CredentialTarget), Result) then
    Exit;
  Result := TAtlasTrackerTokenStatus.Stored(True);
end;

class procedure TAtlasTrackerChecks.Forget(const AConnection: TAtlasTrackerConnection);
begin
  if FStates <> nil then
    FStates.Remove(LowerCase(AConnection.Target.CredentialTarget));
end;

class procedure TAtlasTrackerChecks.Start(const AAccess: IAtlasTrackerAccess;
  const AConnection: TAtlasTrackerConnection; const ADone: TProc);
var
  mAccess: IAtlasTrackerAccess;
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
  mKey: string;
  mDone: TProc;
  mThread: TThread;
begin
  mAccess := AAccess;
  mTarget := AConnection.Target;
  mProvider := AAccess.Provider(AConnection.Provider);
  mKey := LowerCase(mTarget.CredentialTarget);
  mDone := ADone;
  if FThreads = nil then
    FThreads := TList<TThread>.Create;
  mThread := TThread.CreateAnonymousThread(
    procedure
    var
      mStatus: TAtlasTrackerTokenStatus;
    begin
      try
        // Token aus dem Anmeldespeicher ohne Dialog; ohne Token kein Netz („fehlt“).
        mStatus := TAtlasTrackerConnections.Check(mProvider, mTarget, mAccess.Transport(mProvider, mTarget), Now);
      except
        on E: Exception do
        begin
          mStatus := TAtlasTrackerTokenStatus.Create(TAtlasTrackerTokenState.Unreachable, Now, 0);
          TAtlasGuard.Log('Issue-Tracker: Prüfung mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      if TAtlasShutdown.Signalled then
        Exit;
      Finished(mThread, mKey, mStatus, mDone);
    end);
  mThread.FreeOnTerminate := False;
  FThreads.Add(mThread);
  mThread.Start;
end;

class procedure TAtlasTrackerChecks.Finished(AThread: TThread; const AKey: string;
  const AStatus: TAtlasTrackerTokenStatus; const ADone: TProc);
begin
  TAtlasMainThread.Queue(TAtlasFeature.Settings,
    procedure
    begin
      if (FThreads = nil) or not FThreads.Contains(AThread) then
        Exit;
      FThreads.Remove(AThread);
      AThread.WaitFor;
      AThread.Free;
      if FStates = nil then
        FStates := TDictionary<string, TAtlasTrackerTokenStatus>.Create;
      FStates.AddOrSetValue(AKey, AStatus);
      // Anonym: Zustand, nie Adresse oder Token.
      TAtlasGuard.Log('Issue-Tracker: Verbindung geprüft (' + TrackerStateKeys[AStatus.State] + ')');
      ADone();
    end);
end;

class procedure TAtlasTrackerChecks.StartQueryTest(const AAccess: IAtlasTrackerAccess;
  const AConnection: TAtlasTrackerConnection; const ATarget: TAtlasTrackerTarget; const ADone: TAtlasQueryTestDone);
const
  OutcomeKeys: array[TAtlasTrackerQueryOutcome] of string = ('found', 'empty', 'noToken', 'notConfigured',
    'rejected', 'projectUnknown', 'queryRejected', 'unreadable', 'serverError', 'unreachable');
var
  mAccess: IAtlasTrackerAccess;
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
  mDone: TAtlasQueryTestDone;
  mThread: TThread;
begin
  mAccess := AAccess;
  mTarget := ATarget;
  mProvider := AAccess.Provider(AConnection.Provider);
  mDone := ADone;
  if FThreads = nil then
    FThreads := TList<TThread>.Create;
  mThread := TThread.CreateAnonymousThread(
    procedure
    var
      mResult: TAtlasTrackerQueryTestResult;
    begin
      try
        // Token aus dem Anmeldespeicher ohne Dialog; ohne Token „kein Token“ und kein Netz.
        mResult := TAtlasTrackerQueryTest.Run(mProvider, mTarget, mAccess.Transport(mProvider, mTarget));
      except
        on E: Exception do
        begin
          mResult := TAtlasTrackerQueryTestResult.Create(TAtlasTrackerQueryOutcome.Unreachable, '');
          TAtlasGuard.Log('Issue-Tracker: Test der Abfrage mit ' + E.ClassName + ' abgebrochen');
        end;
      end;
      if TAtlasShutdown.Signalled then
        Exit;
      TAtlasMainThread.Queue(TAtlasFeature.Settings,
        procedure
        begin
          if (FThreads = nil) or not FThreads.Contains(mThread) then
            Exit;
          FThreads.Remove(mThread);
          mThread.WaitFor;
          mThread.Free;
          // Anonym: Anbieter und Ergebnis, nie Adresse, Abfrage oder Token.
          TAtlasGuard.Log('Issue-Tracker: Abfrage getestet (' + mTarget.Provider + ', ' +
            OutcomeKeys[mResult.Outcome] + ')');
          mDone(mResult);
        end);
    end);
  mThread.FreeOnTerminate := False;
  FThreads.Add(mThread);
  mThread.Start;
end;

class procedure TAtlasTrackerChecks.Release;
var
  mThread: TThread;
begin
  if FThreads <> nil then
  begin
    // Höchstens die Zeitgrenze einer Prüfung (5 s); danach kommt kein Ergebnis mehr an.
    for mThread in FThreads do
    begin
      mThread.WaitFor;
      mThread.Free;
    end;
    FreeAndNil(FThreads);
  end;
  FreeAndNil(FStates);
end;

/// <summary>Verbindung aus dem Abschnitt tracker der .atlas des aktiven Projekts (#486); leer ohne.</summary>
function TeamTrackerConnections: TArray<TAtlasTrackerConnection>;
var
  mProject: string;
  mTeam: TAtlasTeamSettings;
begin
  Result := nil;
  mProject := TAtlasIdeTeamFile.ActiveProject;
  if mProject = '' then
    Exit;
  mTeam := TAtlasIdeTeamFile.Read(mProject);
  if not mTeam.Tracker.Configured then
    Exit;
  Result := [TAtlasTrackerConnection.FromTeamFile(ChangeFileExt(ExtractFileName(mProject), ''),
    TAtlasTrackerTarget.Create(mTeam.Tracker.Provider, mTeam.Tracker.Url, mTeam.Tracker.Project, ''))];
end;

/// <summary>Aktives Projekt, geöffnete .groupproj (wenn es darin ist) und die Zeile aus dessen .atlas (#1261).
/// </summary>
function TrackerProjectContext: TAtlasTrackerProjectContext;
var
  mTeam: TAtlasTeamSettings;
begin
  Result := TAtlasTrackerProjectContext.Empty;
  Result.ProjectFile := TAtlasIdeTeamFile.ActiveProject;
  if Result.ProjectFile = '' then
    Exit;
  Result.GroupFile := TAtlasIdeFiles.GroupOfProject(Result.ProjectFile);
  mTeam := TAtlasIdeTeamFile.Read(Result.ProjectFile);
  if mTeam.Tracker.Configured then
    Result.Team := [TAtlasTrackerProjectMapping.FromTeamFile(Result.ProjectFile,
      ChangeFileExt(ExtractFileName(Result.ProjectFile), ''), mTeam.Tracker.Project)];
end;


{ TAtlasOptionsSelector }

constructor TAtlasOptionsSelector.Create;
begin
  inherited Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := IntervalMs;
  FTimer.OnTimer := Tick;
end;

destructor TAtlasOptionsSelector.Destroy;
begin
  FTimer.Free;
  inherited Destroy;
end;

procedure TAtlasOptionsSelector.Start;
begin
  FTries := 0;
  FTimer.Enabled := True;
end;

procedure TAtlasOptionsSelector.Stop;
begin
  FTimer.Enabled := False;
end;

class function TAtlasOptionsSelector.FindTree(AParent: TWinControl): TTreeView;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to AParent.ControlCount - 1 do
  begin
    if AParent.Controls[Index] is TTreeView then
      Exit(TTreeView(AParent.Controls[Index]));
    if AParent.Controls[Index] is TWinControl then
    begin
      Result := FindTree(TWinControl(AParent.Controls[Index]));
      if Result <> nil then
        Exit;
    end;
  end;
end;

procedure TAtlasOptionsSelector.Tick(Sender: TObject);
var
  Form: TCustomForm;
  Tree: TTreeView;
  Node: TTreeNode;
begin
  try
    Inc(FTries);
    if (FTries > MaxTries) or (PendingReveal = '') then
    begin
      Stop;
      Exit;
    end;
    Form := Screen.ActiveCustomForm;
    if (Form = nil) or not (fsModal in Form.FormState) then
      Exit;
    Tree := FindTree(Form);
    if Tree = nil then
      Exit;
    // Die Seite heißt „Atlas“ (GetCaption) und hängt unter „Drittanbieter“, nicht oben im Baum.
    for Node in Tree.Items do
      if SameText(Node.Text, 'Atlas') and (Node.Parent <> nil) then
      begin
        Stop;
        Node.MakeVisible;
        Tree.Selected := Node;
        Exit;
      end;
    Stop;
  except
    on E: Exception do
    begin
      Stop;
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
    end;
  end;
end;

/// <summary>Ergebnis eines Hakens; '' ohne Haken.</summary>
function HookText(const AHook: TFunc<string>): string;
begin
  Result := '';
  if Assigned(AHook) then
    Result := AHook();
end;

function ServerExe: string;
begin
  Result := HookText(Hooks.ServerPath);
end;

/// <summary>atlas-baseline.json des aktiven Projekts (oder der alte Name, wenn nur er existiert); '' ohne Projekt.
/// </summary>
function BaselineFile: string;
var
  Folder: string;
begin
  Result := '';
  if TAtlasProjectSettings.SettingsFile = '' then
    Exit;
  Folder := ExtractFileDir(TAtlasProjectSettings.SettingsFile);
  Result := IncludeTrailingPathDelimiter(Folder) + TAtlasBaselineInfo.FileName;
  if not FileExists(Result) and FileExists(IncludeTrailingPathDelimiter(Folder) + TAtlasBaselineInfo.LegacyFileName)
  then
    Result := IncludeTrailingPathDelimiter(Folder) + TAtlasBaselineInfo.LegacyFileName;
end;

function BaselineText: string;
var
  FileName: string;
  Count, Entries: Integer;
begin
  FileName := BaselineFile;
  if FileName = '' then
    Exit(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject));
  if not FileExists(FileName) then
    Exit(TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineNone));
  Count := TAtlasBaselineInfo.Count(TFile.ReadAllText(FileName, TEncoding.UTF8), Entries);
  if Count < 0 then
    Exit(TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineNone));
  Result := TAtlasStrings.Fmt(TAtlasTextId.ServerPageBaselineCount, [Count, Entries]);
end;

/// <summary>AtlasServer.exe mit AArguments im Projektordner; '' bei Erfolg, sonst die Meldung.</summary>
function RunTool(const AArguments: string; ATimeoutMs: Cardinal; out AOutput: string): string;
var
  Code: Cardinal;
  Error, Folder: string;
begin
  Result := '';
  Folder := ExtractFileDir(TAtlasProjectSettings.ActiveProject);
  if not TAtlasServerTool.Run(ServerExe, AArguments, Folder, ATimeoutMs, AOutput, Code, Error) then
    Result := TAtlasStrings.Fmt(TAtlasTextId.ServerPageToolFailed, [Error])
  else if Code = 3 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.ServerPageToolFailed, ['Exit-Code 3']);
end;

{ TAtlasAddInOptions }

procedure TAtlasAddInOptions.Run(const ACommand: string; const AText: TFunc<TJSONValue, string>);
var
  Keep: INTAAddInOptions;
  Owner: TAtlasAddInOptions;
  Generation: Integer;
  Text: TFunc<TJSONValue, string>;
begin
  // Keep hält das Objekt, bis die Antwort da ist; ob die Seite noch dieselbe ist, sagt FGeneration.
  Keep := Self;
  Owner := Self;
  Generation := FGeneration;
  Text := AText;
  if not Assigned(Hooks.Command) then
  begin
    if FPage <> nil then
      FPage.IndexAnswered(Text(nil));
    Exit;
  end;
  Hooks.Command(ACommand,
    procedure(AAnswer: TJSONValue)
    begin
      if (Keep <> nil) and (Owner.FPage <> nil) and (Owner.FGeneration = Generation) then
        TAtlasGuard.Run(TAtlasFeature.Settings,
          procedure
          begin
            Owner.FPage.IndexAnswered(Text(AAnswer));
          end);
    end);
end;

function TAtlasAddInOptions.GetArea: string;
begin
  // Leer: unter „Drittanbieter“, wie die Open Tools API empfiehlt.
  Result := '';
end;

function TAtlasAddInOptions.GetCaption: string;
begin
  Result := 'Atlas';
end;

function TAtlasAddInOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasSettingsPage;
end;

procedure TAtlasAddInOptions.FrameCreated(AFrame: TCustomFrame);
begin
  Inc(FGeneration);
  FPage := AFrame as TAtlasSettingsPage;
  FPage.DefaultServerPath := HookText(Hooks.DefaultServerPath);
  // Version der gewählten AtlasServer.exe (#227).
  FPage.OnServerVersion :=
    function(APath: string): string
    begin
      Result := TAtlasServerTool.FileVersion(APath);
    end;
  FPage.OnResetHistory := Hooks.ResetHistory;
  // Seite Prüfregeln (#909): Wege zu den Regeln im Projekt- und im globalen Dialog, Baseline.
  FPage.OnRulesProject :=
    procedure
    begin
      TAtlasProjectSettings.Execute;
    end;
  FPage.OnRulesGlobal :=
    procedure
    begin
      TAtlasProjectSettings.ExecuteGlobal;
    end;
  FPage.OnBaselineInfo :=
    function: string
    begin
      Result := BaselineText;
    end;
  FPage.OnBaselineUpdate :=
    function: string
    var
      Output: string;
    begin
      if TAtlasProjectSettings.ActiveProject = '' then
        Exit(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject));
      Result := RunTool('--check "' + TAtlasProjectSettings.ActiveProject + '" --update-baseline',
        TAtlasServerTool.CheckTimeoutMs, Output);
      if Result = '' then
        Result := BaselineText;
    end;
  FPage.OnBaselineDelete :=
    function: string
    begin
      if (BaselineFile <> '') and FileExists(BaselineFile) then
        TFile.Delete(BaselineFile);
      Result := BaselineText;
    end;
  // „Einstellungen dazu …“ (#628): gewünschte Zeile zeigen.
  if PendingReveal <> '' then
    FPage.Reveal(PendingReveal);
  // Angeheftete Favoriten (#458): Liste und Entfernen.
  FPage.OnRemoveFavorites :=
    procedure(AKeys: TArray<string>)
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasIdeFavorites.Remove(AKeys);
        end);
    end;
  FPage.OnFavorites :=
    function: TArray<TAtlasFavorite>
    begin
      Result := TAtlasIdeFavorites.Items;
    end;
  FPage.OnToolbarCommands :=
    function: TArray<TAtlasToolbarCommandInfo>
    begin
      Result := nil;
      if Assigned(Hooks.ToolbarCommands) then
        Result := Hooks.ToolbarCommands();
    end;
  // Karte „Atlas entdecken“ (#757): Zählung zurücksetzen, gesperrte Tipps wieder zeigen.
  FPage.OnResetUsage :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          if Assigned(Hooks.ResetUsage) then
            Hooks.ResetUsage();
        end);
    end;
  FPage.OnUnblockTips :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          if Assigned(Hooks.UnblockTips) then
            Hooks.UnblockTips();
        end);
    end;
  // Symbolindex (#492): vor LoadFrom, das die Kennzahlen gleich anzeigt.
  FPage.OnIndexMetrics :=
    procedure
    begin
      Run('atlas.server.status',
        function(AAnswer: TJSONValue): string
        begin
          Result := TLspIndexStatus.Metrics(AAnswer).Text;
        end);
    end;
  FPage.OnIndexRebuild :=
    procedure
    begin
      Run('atlas.server.rebuildIndex',
        function(AAnswer: TJSONValue): string
        begin
          if AAnswer <> nil then
            Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexRebuilding)
          else
            Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer);
        end);
    end;
  FPage.OnIndexClear :=
    procedure
    begin
      Run('atlas.server.clearIndex',
        function(AAnswer: TJSONValue): string
        begin
          if AAnswer <> nil then
            Result := TLspIndexStatus.ClearedText(AAnswer)
          else
            Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer);
        end);
    end;
  // Projektdatei .atlas (#486): Werte „aus .atlas“ auch bei noch ausgeschaltetem Schalter; Öffnen legt sie an.
  FPage.OnTeamFile :=
    function: TAtlasTeamSettings
    begin
      Result := TAtlasIdeTeamFile.Read(TAtlasIdeTeamFile.ActiveProject);
    end;
  FPage.OnOpenTeamFile :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasIdeTeamFile.OpenInEditor;
        end);
    end;
  // Export, Import und „Alles zurücksetzen“ (#723) mit den Werten der Seite; Import und Zurücksetzen speichern
  // sofort (mit Sicherung), die Seite lädt danach neu.
  FPage.OnExportSettings :=
    procedure(ACurrent: TAtlasPluginSettings)
    begin
      TAtlasIdeSettingsTransfer.ExportSettings(ACurrent);
    end;
  FPage.OnImportSettings :=
    function(const ACurrent: TAtlasPluginSettings; AProfile: Boolean; out AResult: TAtlasPluginSettings): Boolean
    begin
      Result := TAtlasIdeSettingsTransfer.ImportSettings(ACurrent, AProfile, AResult);
    end;
  FPage.OnResetAllSettings :=
    function(const ACurrent: TAtlasPluginSettings; out AResult: TAtlasPluginSettings): Boolean
    begin
      Result := TAtlasIdeSettingsTransfer.ResetAll(ACurrent, AResult);
    end;
  ConnectTracker;
  FPage.LoadFrom(TAtlasIdeSettings.Stored);
  // „zuordnen …“ aus „Meine Issues“ (#1261): Zeile nach dem Laden vorbefüllen.
  if PendingTrackerProject <> '' then
    FPage.AssignTrackerProject(PendingTrackerProject);
end;

procedure TAtlasAddInOptions.ConnectTracker;
var
  mKeep: INTAAddInOptions;
  mOwner: TAtlasAddInOptions;
  mGeneration: Integer;
  mNames, mCaptions: TArray<string>;
  mProvider: IAtlasTrackerProvider;
begin
  // Seite Issue-Tracker (#1260): Verbindung aus der .atlas immer, Token und Prüfung nur mit der Komposition.
  FPage.OnTrackerTeam :=
    function: TArray<TAtlasTrackerConnection>
    begin
      Result := TeamTrackerConnections;
    end;
  FPage.OnTrackerContext :=
    function: TAtlasTrackerProjectContext
    begin
      Result := TrackerProjectContext;
    end;
  if Hooks.Tracker = nil then
    Exit;
  mNames := nil;
  mCaptions := nil;
  for mProvider in Hooks.Tracker.Providers do
  begin
    mNames := mNames + [mProvider.Name];
    mCaptions := mCaptions + [mProvider.Caption];
  end;
  FPage.SetTrackerProviders(mNames, mCaptions);
  mKeep := Self;
  mOwner := Self;
  mGeneration := FGeneration;
  FPage.OnTrackerState :=
    function(const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus
    begin
      Result := TAtlasTrackerChecks.State(Hooks.Tracker, AConnection);
    end;
  FPage.OnTrackerToken :=
    procedure(const AConnection: TAtlasTrackerConnection)
    var
      mTokenProvider: IAtlasTrackerProvider;
    begin
      mTokenProvider := Hooks.Tracker.Provider(AConnection.Provider);
      if mTokenProvider = nil then
        Exit;
      // Derselbe verdeckte Dialog wie Atlas.TrackerLogin; leer entfernt das Token.
      if Hooks.Tracker.EnterToken(mTokenProvider, AConnection.Target) then
        TAtlasTrackerChecks.Forget(AConnection);
    end;
  FPage.OnTrackerCheck :=
    procedure(const AConnection: TAtlasTrackerConnection)
    var
      mConnection: TAtlasTrackerConnection;
    begin
      mConnection := AConnection;
      TAtlasTrackerChecks.Start(Hooks.Tracker, mConnection,
        procedure
        begin
          // Nur an die Seite, für die geprüft wurde, solange der Dialog offen ist.
          if (mKeep <> nil) and (mOwner.FPage <> nil) and (mOwner.FGeneration = mGeneration) then
            mOwner.FPage.TrackerCheckDone(mConnection);
        end);
    end;
  FPage.OnTrackerQueryTest :=
    procedure(const AConnection: TAtlasTrackerConnection; const ATarget: TAtlasTrackerTarget;
      const ADone: TAtlasQueryTestDone)
    begin
      // Der Dialog prüft selbst, ob er noch offen ist.
      TAtlasTrackerChecks.StartQueryTest(Hooks.Tracker, AConnection, ATarget, ADone);
    end;
  FPage.OnTrackerRemove :=
    procedure(const AConnection: TAtlasTrackerConnection)
    begin
      if not Hooks.Tracker.HasToken(AConnection.Target) then
        Exit;
      if MessageDlg(TAtlasStrings.Fmt(TAtlasTextId.SettingsIssuesConnectionRemoveToken, [AConnection.Target.Server]),
        mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      begin
        Hooks.Tracker.RemoveToken(AConnection.Target);
        TAtlasTrackerChecks.Forget(AConnection);
      end;
    end;
end;

procedure TAtlasAddInOptions.DialogClosed(Accepted: Boolean);
var
  Settings: TAtlasPluginSettings;
begin
  PendingReveal := '';
  PendingTrackerProject := '';
  try
    if Accepted and (FPage <> nil) then
    begin
      Settings := TAtlasIdeSettings.Stored;
      FPage.SaveTo(Settings);
      TAtlasIdeSettings.Update(Settings);
    end;
    // Strukturhervorhebung und Help Insight der IDE erst nach dem Dialog abgleichen: Mit OK
    // schreibt die IDE danach ihre Editoroptionen aus dem Speicher zurück, auch die Schalter,
    // die Atlas abgeschaltet hatte. Sonst zeigt sie ab dem nächsten Start wieder beide Tooltips.
    if Accepted then
      TAtlasMainThread.ForceQueue(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasGuard.Run(TAtlasFeature.Settings,
            procedure
            begin
              TAtlasIdeStructureSwitch.Sync;
            end);
        end);
    FPage := nil;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

function TAtlasAddInOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TAtlasAddInOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasAddInOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TAtlasSnippetOptions }

function TAtlasSnippetOptions.GetArea: string;
begin
  Result := '';
end;

function TAtlasSnippetOptions.GetCaption: string;
begin
  Result := 'Atlas.Snippets';
end;

function TAtlasSnippetOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasSnippetsPage;
end;

procedure TAtlasSnippetOptions.FrameCreated(AFrame: TCustomFrame);
var
  Ide, Own: TAtlasSnippetList;
  Stats: TAtlasLiveTemplateStats;
  Errors: TArray<string>;
begin
  try
    FPage := AFrame as TAtlasSnippetsPage;
    Ide := nil;
    if TAtlasIdeSettings.Current.ImportIdeTemplates then
      Ide := TAtlasLiveTemplates.LoadFolder(HookText(Hooks.IdeTemplateFolder), Stats);
    Own := TAtlasSnippets.LoadFolder(HookText(Hooks.SnippetFolder), Errors);
    FPage.Load(TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, Ide, Own));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasSnippetOptions.DialogClosed(Accepted: Boolean);
begin
  try
    if Accepted and (FPage <> nil) and (FPage.Catalog <> nil) and FPage.Catalog.Modified then
      FPage.Catalog.Save(HookText(Hooks.SnippetFolder));
    FPage := nil;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

function TAtlasSnippetOptions.ValidateContents: Boolean;
var
  Message: string;
begin
  Result := True;
  if FPage = nil then
    Exit;
  Message := FPage.Validate;
  if Message <> '' then
  begin
    ShowMessage(Message);
    Result := False;
  end;
end;

function TAtlasSnippetOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasSnippetOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TAtlasKeysOptions }

function TAtlasKeysOptions.GetArea: string;
begin
  Result := '';
end;

function TAtlasKeysOptions.GetCaption: string;
begin
  // Punkt: Unterseite von „Atlas“.
  Result := 'Atlas.' + TAtlasStrings.Text(TAtlasTextId.KeysTitle);
end;

function TAtlasKeysOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasKeysPage;
end;

procedure TAtlasKeysOptions.FrameCreated(AFrame: TCustomFrame);
begin
  try
    FPage := AFrame as TAtlasKeysPage;
    FPage.LoadFrom(TAtlasIdeSettings.Stored);
    FPage.OwnerOf :=
      function(AShortCut: Word): string
      begin
        Result := TAtlasIdeKeys.Owner(AShortCut);
      end;
    FPage.ShowForeignCompletions(TAtlasIdeKeys.ForeignCompletions);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasKeysOptions.DialogClosed(Accepted: Boolean);
var
  Settings: TAtlasPluginSettings;
begin
  try
    if Accepted and (FPage <> nil) then
    begin
      Settings := TAtlasIdeSettings.Stored;
      FPage.SaveTo(Settings);
      TAtlasIdeSettings.Update(Settings);
    end;
    FPage := nil;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

function TAtlasKeysOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TAtlasKeysOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasKeysOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TAtlasServerOptions }


function TAtlasServerOptions.GetArea: string;
begin
  Result := '';
end;

function TAtlasServerOptions.GetCaption: string;
begin
  // Punkt: Unterseite von „Atlas“.
  Result := 'Atlas.' + TAtlasStrings.Text(TAtlasTextId.ServerPageTitle);
end;

function TAtlasServerOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasServerPage;
end;

procedure TAtlasServerOptions.FrameCreated(AFrame: TCustomFrame);
begin
  try
    FPage := AFrame as TAtlasServerPage;
    FPage.OnEditGlobal :=
      procedure
      begin
        TAtlasProjectSettings.ExecuteGlobal;
      end;
    FPage.OnEditProject :=
      procedure
      begin
        TAtlasProjectSettings.Execute;
      end;
    FPage.OnBaselineInfo :=
      function: string
      begin
        Result := BaselineText;
      end;
    FPage.OnBaselineUpdate :=
      function: string
      var
        Output: string;
      begin
        if TAtlasProjectSettings.ActiveProject = '' then
          Exit(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject));
        Result := RunTool('--check "' + TAtlasProjectSettings.ActiveProject + '" --update-baseline',
          TAtlasServerTool.CheckTimeoutMs, Output);
        if Result = '' then
          Result := BaselineText;
      end;
    FPage.OnBaselineDelete :=
      function: string
      begin
        if (BaselineFile <> '') and FileExists(BaselineFile) then
          TFile.Delete(BaselineFile);
        Result := BaselineText;
      end;
    FPage.OnSuppressions :=
      function: TArray<string>
      var
        OutputFile, Output, Error: string;
        Row: TAtlasSuppressionRow;
      begin
        Result := nil;
        if TAtlasProjectSettings.ActiveProject = '' then
        begin
          Result := [TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject)];
          Exit;
        end;
        OutputFile := TPath.GetTempFileName;
        try
          Error := RunTool('--check "' + TAtlasProjectSettings.ActiveProject +
            '" --suppression-stats --format json --output "' + OutputFile + '"', TAtlasServerTool.CheckTimeoutMs,
            Output);
          if Error <> '' then
          begin
            Result := [Error];
            Exit;
          end;
          for Row in TAtlasBaselineInfo.Suppressions(TFile.ReadAllText(OutputFile, TEncoding.UTF8)) do
            Result := Result + [TAtlasStrings.Fmt(TAtlasTextId.ServerPageSuppressionRow,
              [Row.Rule, Row.Total, Row.Unused, Row.Files])];
          if Length(Result) = 0 then
            Result := [TAtlasStrings.Text(TAtlasTextId.ServerPageSuppressionsNone)];
        finally
          if FileExists(OutputFile) then
            TFile.Delete(OutputFile);
        end;
      end;
    FPage.OnClearCache :=
      function: string
      var
        Output: string;
      begin
        Result := RunTool('--clear-cache', TAtlasServerTool.ShortTimeoutMs, Output);
        if Result = '' then
          Result := Trim(Output);
        if Result = '' then
          Result := TAtlasStrings.Text(TAtlasTextId.ServerPageToolDone);
      end;
    FPage.Refresh;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasServerOptions.DialogClosed(Accepted: Boolean);
begin
  FPage := nil;
end;

function TAtlasServerOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TAtlasServerOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasServerOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TAtlasOptionsRegistration }

class procedure TAtlasOptionsRegistration.Register(const AHooks: TAtlasOptionsHooks);
var
  Services: INTAEnvironmentOptionsServices;
begin
  if (Options = nil) and Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Services) then
  begin
    Hooks := AHooks;
    Options := TAtlasAddInOptions.Create;
    Services.RegisterAddInOptions(Options);
    SnippetOptions := TAtlasSnippetOptions.Create;
    Services.RegisterAddInOptions(SnippetOptions);
    KeysOptions := TAtlasKeysOptions.Create;
    Services.RegisterAddInOptions(KeysOptions);
    ServerOptions := TAtlasServerOptions.Create;
    Services.RegisterAddInOptions(ServerOptions);
  end;
end;

class procedure TAtlasOptionsRegistration.Unregister;
var
  Services: INTAEnvironmentOptionsServices;
begin
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Services) then
  begin
    if SnippetOptions <> nil then
      Services.UnregisterAddInOptions(SnippetOptions);
    if KeysOptions <> nil then
      Services.UnregisterAddInOptions(KeysOptions);
    if ServerOptions <> nil then
      Services.UnregisterAddInOptions(ServerOptions);
    if Options <> nil then
      Services.UnregisterAddInOptions(Options);
  end;
  SnippetOptions := nil;
  KeysOptions := nil;
  ServerOptions := nil;
  Options := nil;
  TAtlasTrackerChecks.Release;
  Hooks := Default(TAtlasOptionsHooks);
  PendingReveal := '';
  PendingTrackerProject := '';
  FreeAndNil(Selector);
end;

/// <summary>Aktion bzw. Menüpunkt „Optionen…“ der IDE ausführen; False, wenn keins zu finden ist.</summary>
function RunOptionsDialog: Boolean;
const
  ActionName = 'ToolsOptionsCommand';
  ItemName = 'ToolsOptionsItem';
var
  Services: INTAServices;
  Index: Integer;

  function FindItem(AItem: TMenuItem): TMenuItem;
  var
    Child: Integer;
  begin
    Result := nil;
    if SameText(AItem.Name, ItemName) then
      Exit(AItem);
    for Child := 0 to AItem.Count - 1 do
    begin
      Result := FindItem(AItem.Items[Child]);
      if Result <> nil then
        Exit;
    end;
  end;

var
  Item: TMenuItem;
begin
  Result := False;
  if not Supports(BorlandIDEServices, INTAServices, Services) then
    Exit;
  if Services.ActionList <> nil then
    for Index := 0 to Services.ActionList.ActionCount - 1 do
      if SameText(Services.ActionList.Actions[Index].Name, ActionName) then
      begin
        Services.ActionList.Actions[Index].Execute;
        Exit(True);
      end;
  if Services.MainMenu <> nil then
  begin
    Item := FindItem(Services.MainMenu.Items);
    if Item <> nil then
    begin
      Item.Click;
      Exit(True);
    end;
  end;
end;

class procedure TAtlasOptionsRegistration.ShowRule(const ARuleId: string);
begin
  TAtlasProjectSettings.ShowRule(ARuleId);
end;

class procedure TAtlasOptionsRegistration.ShowSetting(const AKey: string);
begin
  if Options = nil then
    Exit;
  PendingReveal := AKey;
  if Selector = nil then
    Selector := TAtlasOptionsSelector.Create;
  // Der Dialog ist modal: Der Zeitgeber wählt die Seite, während er offen ist.
  Selector.Start;
  try
    RunOptionsDialog;
  finally
    // Modal: Hier ist der Dialog wieder zu. Nicht gefunden oder geschlossen: nichts mehr vormerken.
    if Selector <> nil then
      Selector.Stop;
    PendingReveal := '';
  end;
end;

class procedure TAtlasOptionsRegistration.ShowTrackerProject(const AMatch: string);
begin
  PendingTrackerProject := AMatch;
  try
    ShowSetting('IssuesProjects');
  finally
    PendingTrackerProject := '';
  end;
end;

end.
