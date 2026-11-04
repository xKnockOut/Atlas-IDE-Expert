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
// Seite Issue-Tracker: Den Abschnitt mit Verbindungen, Projekten, Abfragen
// und Prüfungen baut das Modul Tracker (#1455, Atlas.IDE.Tracker.Settings).
// ShowSetting mit Vorgabe („zuordnen …“ aus „Meine Issues“, #1261) reicht die
// Vorgabe nach dem Laden an den Abschnitt, dem die Einstellung gehört.
// Seite Versionsverwaltung (#1285): Fundort ohne Prozess, „Prüfen“ und
// „Aktuelles Projekt“ über TAtlasIdeVcs im Hintergrund; das Ergebnis geht nur
// an die Seite, für die es bestellt wurde (FGeneration). Nach OK liest
// TAtlasIdeVcs settings.json sofort neu, damit ein neuer Pfad gleich gilt.

interface

uses
  System.SysUtils,
  System.JSON,
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
  end;

  TAtlasOptionsRegistration = class
  public
    class procedure Register(const AHooks: TAtlasOptionsHooks); static;
    class procedure Unregister; static;
    /// <summary>Tools › Optionen öffnen und auf der Seite „Atlas“ die Einstellung AKey (Name der
    /// Plugin-Einstellung) zeigen und markieren (#628).</summary>
    class procedure ShowSetting(const AKey: string); overload; static;
    /// <summary>Wie ShowSetting; danach bekommt der Abschnitt des Moduls, dem AKey gehört, die Vorgabe AArgument
    /// (z. B. „zuordnen …“ mit dem Projekt, #1261).</summary>
    class procedure ShowSetting(const AKey, AArgument: string); overload; static;
    /// <summary>„Regel einstellen…“ (#909): Tools › Optionen auf der Seite Prüfregeln bei der Regel ARuleId
    /// öffnen.</summary>
    class procedure ShowRule(const ARuleId: string); static;
    /// <summary>„Anmeldung am Server nötig – prüfen …“ (#1287): Tools › Optionen auf der Seite Versionsverwaltung
    /// öffnen und den Serverzugang für AFolder prüfen.</summary>
    class procedure ShowVcsServer(const AFolder: string); static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  System.IOUtils,
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
  Atlas.IDE.Foundation.Files,
  Atlas.Core.Projects.Vcs,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.ToolCheck,
  Atlas.Core.Vcs.ServerCheck,
  Atlas.IDE.Vcs.Service,
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
    /// <summary>Seite Versionsverwaltung (#1285).</summary>
    procedure ConnectVcs;
    /// <summary>Zeile AFolder der Tabelle „Server“ im Hintergrund prüfen (#1287).</summary>
    procedure CheckVcsServer(const AFolder: string);
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
  /// <summary>Vorgabe zu PendingReveal für den Abschnitt eines Moduls (#1455); '' ohne.</summary>
  PendingArgument: string;
  /// <summary>Ordner, dessen Serverzugang die Seite Versionsverwaltung beim nächsten Anlegen prüft (#1287).
  /// </summary>
  PendingVcsServer: string;

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

/// <summary>Aktives Projekt, geöffnete .groupproj (wenn es darin ist) und die Zeile aus dem Abschnitt vcs der .atlas
/// für die Seite Versionsverwaltung (#1286).</summary>
function VcsProjectContext: TAtlasVcsProjectContext;
var
  mTeam: TAtlasTeamSettings;
begin
  Result := TAtlasVcsProjectContext.Empty;
  Result.ProjectFile := TAtlasIdeTeamFile.ActiveProject;
  if Result.ProjectFile = '' then
  begin
    Exit;
  end;
  Result.GroupFile := TAtlasIdeFiles.GroupOfProject(Result.ProjectFile);
  mTeam := TAtlasIdeTeamFile.Read(Result.ProjectFile);
  if mTeam.Vcs.Configured then
  begin
    Result.Team := [TAtlasVcsProjectMapping.FromTeamFile(Result.ProjectFile, mTeam.Vcs.Provider,
      mTeam.Vcs.MainBranch)];
  end;
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
    begin
      Exit(TTreeView(AParent.Controls[Index]));
    end;
    if AParent.Controls[Index] is TWinControl then
    begin
      Result := FindTree(TWinControl(AParent.Controls[Index]));
      if Result <> nil then
      begin
        Exit;
      end;
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
    begin
      Exit;
    end;
    Tree := FindTree(Form);
    if Tree = nil then
    begin
      Exit;
    end;
    // Die Seite heißt „Atlas“ (GetCaption) und hängt unter „Drittanbieter“, nicht oben im Baum.
    for Node in Tree.Items do
    begin
      if SameText(Node.Text, 'Atlas') and (Node.Parent <> nil) then
      begin
        Stop;
        Node.MakeVisible;
        Tree.Selected := Node;
        Exit;
      end;
    end;
    // Nicht gefunden: Delphi 13 legt die Unterseiten erst beim Aufklappen an ("Fremdhersteller" zu). Obere
    // Zweige aufklappen und beim nächsten Takt erneut suchen, statt aufzugeben.
    for Node in Tree.Items do
    begin
      if (Node.Parent = nil) and Node.HasChildren and not Node.Expanded then
      begin
        Node.Expand(False);
      end;
    end;
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
  begin
    Result := AHook();
  end;
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
  begin
    Exit;
  end;
  Folder := ExtractFileDir(TAtlasProjectSettings.SettingsFile);
  Result := IncludeTrailingPathDelimiter(Folder) + TAtlasBaselineInfo.FileName;
  if not FileExists(Result) and FileExists(IncludeTrailingPathDelimiter(Folder) + TAtlasBaselineInfo.LegacyFileName)
  then
  begin
    Result := IncludeTrailingPathDelimiter(Folder) + TAtlasBaselineInfo.LegacyFileName;
  end;
end;

function BaselineText: string;
var
  FileName: string;
  Count, Entries: Integer;
begin
  FileName := BaselineFile;
  if FileName = '' then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject));
  end;
  if not FileExists(FileName) then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineNone));
  end;
  Count := TAtlasBaselineInfo.Count(TFile.ReadAllText(FileName, TEncoding.UTF8), Entries);
  if Count < 0 then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineNone));
  end;
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
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.ServerPageToolFailed, [Error]);
  end
  else if Code = 3 then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.ServerPageToolFailed, ['Exit-Code 3']);
  end;
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
    begin
      FPage.IndexAnswered(Text(nil));
    end;
    Exit;
  end;
  Hooks.Command(ACommand,
    procedure(AAnswer: TJSONValue)
    begin
      if (Keep <> nil) and (Owner.FPage <> nil) and (Owner.FGeneration = Generation) then
      begin
        TAtlasGuard.Run(TAtlasFeature.Settings,
          procedure
          begin
            Owner.FPage.IndexAnswered(Text(AAnswer));
          end);
      end;
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
      begin
        Exit(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject));
      end;
      Result := RunTool('--check "' + TAtlasProjectSettings.ActiveProject + '" --update-baseline',
        TAtlasServerTool.CheckTimeoutMs, Output);
      if Result = '' then
      begin
        Result := BaselineText;
      end;
    end;
  FPage.OnBaselineDelete :=
    function: string
    begin
      if (BaselineFile <> '') and FileExists(BaselineFile) then
      begin
        TFile.Delete(BaselineFile);
      end;
      Result := BaselineText;
    end;
  // „Einstellungen dazu …“ (#628): gewünschte Zeile zeigen.
  if PendingReveal <> '' then
  begin
    FPage.Reveal(PendingReveal);
  end;
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
      begin
        Result := Hooks.ToolbarCommands();
      end;
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
          begin
            Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexRebuilding);
          end
          else
          begin
            Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer);
          end;
        end);
    end;
  FPage.OnIndexClear :=
    procedure
    begin
      Run('atlas.server.clearIndex',
        function(AAnswer: TJSONValue): string
        begin
          if AAnswer <> nil then
          begin
            Result := TLspIndexStatus.ClearedText(AAnswer);
          end
          else
          begin
            Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer);
          end;
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
  ConnectVcs;
  FPage.LoadFrom(TAtlasIdeSettings.Stored);
  // Vorgabe für den Abschnitt eines Moduls (#1455), z. B. „zuordnen …“ aus „Meine Issues“: nach dem Laden.
  if (PendingReveal <> '') and (PendingArgument <> '') then
  begin
    FPage.ShowSettingArgument(PendingReveal, PendingArgument);
  end;
  // „Anmeldung am Server nötig – prüfen …“ der Willkommensseite (#1287): Zeile zeigen und prüfen.
  if PendingVcsServer <> '' then
  begin
    FPage.RevealVcsServer(PendingVcsServer);
  end;
end;

procedure TAtlasAddInOptions.ConnectVcs;
var
  mKeep: INTAAddInOptions;
  mOwner: TAtlasAddInOptions;
  mGeneration: Integer;
begin
  mKeep := Self;
  mOwner := Self;
  mGeneration := FGeneration;
  FPage.OnVcsContext :=
    function: TAtlasVcsProjectContext
    begin
      Result := VcsProjectContext;
    end;
  FPage.OnVcsLocate :=
    function(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation
    begin
      Result := TAtlasIdeVcs.Locate(AKind, APath);
    end;
  FPage.OnVcsCheck :=
    procedure(AKind: TAtlasVcsKind; const APath: string)
    var
      mLocation: TAtlasVcsToolLocation;
    begin
      if not TAtlasIdeVcs.CheckTool(AKind, APath,
        procedure(ACheck: TAtlasVcsToolCheck)
        begin
          // Nur an die Seite, für die geprüft wurde, solange der Dialog offen ist.
          if (mKeep <> nil) and (mOwner.FPage <> nil) and (mOwner.FGeneration = mGeneration) then
          begin
            mOwner.FPage.VcsCheckDone(ACheck);
          end;
        end) then
      begin
        // Nichts gestartet (Versionsverwaltung noch nicht bereit): Zustand ohne Prozess.
        mLocation := TAtlasIdeVcs.Locate(AKind, APath);
        mOwner.FPage.VcsCheckDone(TAtlasVcsToolChecks.Missing(AKind, mLocation));
      end;
    end;
  FPage.OnVcsProject :=
    procedure
    var
      mProject, mGroup: string;
    begin
      // Aktive .dproj in der geöffneten .groupproj; Art und Hauptbranch nach vcs.projects und .atlas (#1286).
      mProject := TAtlasIdeTeamFile.ActiveProject;
      mGroup := '';
      if mProject <> '' then
      begin
        mGroup := TAtlasIdeFiles.GroupOfProject(mProject);
      end;
      TAtlasIdeVcs.QueryProject(mProject, mGroup,
        procedure(AState: TAtlasVcsProjectState)
        begin
          if (mKeep <> nil) and (mOwner.FPage <> nil) and (mOwner.FGeneration = mGeneration) then
          begin
            mOwner.FPage.VcsProjectDone(AState);
          end;
        end);
    end;
  // Serverzugang (#1287): Zustand nur aus der Sitzung, Prüfen und Anmelden nur auf Klick.
  FPage.OnVcsServerState :=
    function(AFolder: string): TAtlasVcsServerCheck
    begin
      Result := TAtlasIdeVcs.ServerState(AFolder);
    end;
  FPage.OnVcsServerCheck :=
    procedure(const AFolder: string)
    begin
      CheckVcsServer(AFolder);
    end;
  FPage.OnVcsServerLogin :=
    function(const AFolder: string; const ACheck: TAtlasVcsServerCheck): Boolean
    var
      mFolder: string;
    begin
      mFolder := AFolder;
      // Nach dem Schließen der Konsole dieselbe Zeile erneut prüfen.
      Result := TAtlasIdeVcs.OpenServerLogin(ACheck,
        procedure
        begin
          if (mKeep <> nil) and (mOwner.FPage <> nil) and (mOwner.FGeneration = mGeneration) then
          begin
            mOwner.CheckVcsServer(mFolder);
          end;
        end);
    end;
end;

procedure TAtlasAddInOptions.CheckVcsServer(const AFolder: string);
var
  mKeep: INTAAddInOptions;
  mOwner: TAtlasAddInOptions;
  mGeneration: Integer;
  mFolder: string;
begin
  mKeep := Self;
  mOwner := Self;
  mGeneration := FGeneration;
  mFolder := AFolder;
  if not TAtlasIdeVcs.CheckServer(mFolder,
    procedure(ACheck: TAtlasVcsServerCheck)
    begin
      // Nur an die Seite, für die geprüft wurde, solange der Dialog offen ist.
      if (mKeep <> nil) and (mOwner.FPage <> nil) and (mOwner.FGeneration = mGeneration) then
      begin
        mOwner.FPage.VcsServerDone(mFolder, ACheck);
      end;
    end) then
  begin
    FPage.VcsServerDone(mFolder, TAtlasVcsServerCheck.Empty);
  end;
end;

procedure TAtlasAddInOptions.DialogClosed(Accepted: Boolean);
var
  Settings: TAtlasPluginSettings;
begin
  PendingReveal := '';
  PendingArgument := '';
  PendingVcsServer := '';
  try
    if Accepted and (FPage <> nil) then
    begin
      Settings := TAtlasIdeSettings.Stored;
      FPage.SaveTo(Settings);
      TAtlasIdeSettings.Update(Settings);
      // vcs.* (#1285) liegen in settings.json: neuer Pfad und neues Zeitlimit gelten sofort.
      TAtlasIdeVcs.Reload;
    end;
    // Strukturhervorhebung und Help Insight der IDE erst nach dem Dialog abgleichen: Mit OK
    // schreibt die IDE danach ihre Editoroptionen aus dem Speicher zurück, auch die Schalter,
    // die Atlas abgeschaltet hatte. Sonst zeigt sie ab dem nächsten Start wieder beide Tooltips.
    if Accepted then
    begin
      TAtlasMainThread.ForceQueue(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasGuard.Run(TAtlasFeature.Settings,
            procedure
            begin
              TAtlasIdeStructureSwitch.Sync;
            end);
        end);
    end;
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
    begin
      Ide := TAtlasLiveTemplates.LoadFolder(HookText(Hooks.IdeTemplateFolder), Stats);
    end;
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
    begin
      FPage.Catalog.Save(HookText(Hooks.SnippetFolder));
    end;
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
  begin
    Exit;
  end;
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
        begin
          Exit(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsNoProject));
        end;
        Result := RunTool('--check "' + TAtlasProjectSettings.ActiveProject + '" --update-baseline',
          TAtlasServerTool.CheckTimeoutMs, Output);
        if Result = '' then
        begin
          Result := BaselineText;
        end;
      end;
    FPage.OnBaselineDelete :=
      function: string
      begin
        if (BaselineFile <> '') and FileExists(BaselineFile) then
        begin
          TFile.Delete(BaselineFile);
        end;
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
          begin
            Result := Result + [TAtlasStrings.Fmt(TAtlasTextId.ServerPageSuppressionRow,
              [Row.Rule, Row.Total, Row.Unused, Row.Files])];
          end;
          if Length(Result) = 0 then
          begin
            Result := [TAtlasStrings.Text(TAtlasTextId.ServerPageSuppressionsNone)];
          end;
        finally
          if FileExists(OutputFile) then
          begin
            TFile.Delete(OutputFile);
          end;
        end;
      end;
    FPage.OnClearCache :=
      function: string
      var
        Output: string;
      begin
        Result := RunTool('--clear-cache', TAtlasServerTool.ShortTimeoutMs, Output);
        if Result = '' then
        begin
          Result := Trim(Output);
        end;
        if Result = '' then
        begin
          Result := TAtlasStrings.Text(TAtlasTextId.ServerPageToolDone);
        end;
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
    begin
      Services.UnregisterAddInOptions(SnippetOptions);
    end;
    if KeysOptions <> nil then
    begin
      Services.UnregisterAddInOptions(KeysOptions);
    end;
    if ServerOptions <> nil then
    begin
      Services.UnregisterAddInOptions(ServerOptions);
    end;
    if Options <> nil then
    begin
      Services.UnregisterAddInOptions(Options);
    end;
  end;
  SnippetOptions := nil;
  KeysOptions := nil;
  ServerOptions := nil;
  Options := nil;
  Hooks := Default(TAtlasOptionsHooks);
  PendingReveal := '';
  PendingArgument := '';
  PendingVcsServer := '';
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
    begin
      Exit(AItem);
    end;
    for Child := 0 to AItem.Count - 1 do
    begin
      Result := FindItem(AItem.Items[Child]);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;

var
  Item: TMenuItem;
begin
  Result := False;
  if not Supports(BorlandIDEServices, INTAServices, Services) then
  begin
    Exit;
  end;
  if Services.ActionList <> nil then
  begin
    for Index := 0 to Services.ActionList.ActionCount - 1 do
    begin
      if SameText(Services.ActionList.Actions[Index].Name, ActionName) then
      begin
        Services.ActionList.Actions[Index].Execute;
        Exit(True);
      end;
    end;
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

/// <summary>Tools › Optionen über IOTAEnvironmentOptions140.EditOptions auf der Seite „Atlas“ öffnen; False, wenn die
/// IDE das nicht anbietet.</summary>
function EditAtlasOptions: Boolean;
var
  Services: IOTAServices;
  Environment: IOTAEnvironmentOptions140;
begin
  Result := Supports(BorlandIDEServices, IOTAServices, Services) and (Services.GetEnvironmentOptions <> nil) and
    Supports(Services.GetEnvironmentOptions, IOTAEnvironmentOptions140, Environment);
  if Result then
  begin
    Environment.EditOptions('', Options.GetCaption);
  end;
end;

class procedure TAtlasOptionsRegistration.ShowRule(const ARuleId: string);
begin
  TAtlasProjectSettings.ShowRule(ARuleId);
end;

class procedure TAtlasOptionsRegistration.ShowSetting(const AKey: string);
begin
  if Options = nil then
  begin
    Exit;
  end;
  PendingReveal := AKey;
  if Selector = nil then
  begin
    Selector := TAtlasOptionsSelector.Create;
  end;
  // Der Dialog ist modal: Der Zeitgeber wählt die Seite, während er offen ist (nur noch Rückfall).
  Selector.Start;
  try
    // Offizieller Weg: Dialog gleich auf der Seite „Atlas“ unter „Fremdhersteller“ (leere Area). Die Seite zeigt
    // beim Anlegen PendingReveal. Der Baum von Delphi 13 ist kein TTreeView mehr; die Suche darin fand nichts.
    if not EditAtlasOptions then
    begin
      RunOptionsDialog;
    end;
  finally
    // Modal: Hier ist der Dialog wieder zu. Nicht gefunden oder geschlossen: nichts mehr vormerken.
    if Selector <> nil then
    begin
      Selector.Stop;
    end;
    PendingReveal := '';
  end;
end;

class procedure TAtlasOptionsRegistration.ShowSetting(const AKey, AArgument: string);
begin
  PendingArgument := AArgument;
  try
    ShowSetting(AKey);
  finally
    PendingArgument := '';
  end;
end;

class procedure TAtlasOptionsRegistration.ShowVcsServer(const AFolder: string);
begin
  PendingVcsServer := AFolder;
  try
    ShowSetting('VcsProjects');
  finally
    PendingVcsServer := '';
  end;
end;

end.
