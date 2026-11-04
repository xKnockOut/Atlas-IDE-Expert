unit Atlas.IDE.Settings.Options;

// Meldet die Seite „Atlas“ unter Tools › Optionen › Drittanbieter an
// (INTAAddInOptions, #227) und verbindet sie mit den Einstellungen in der
// Registry. „Verlauf zurücksetzen“ leert die lernende Gewichtung (#418).
// Die Liste der angehefteten Favoriten (#458) kommt aus TAtlasIdeFavorites; „Entfernen“ wirkt sofort.
// Die Unterseiten „Snippets“ (#51), „Tastenkonflikte“ (#494) und „Server“
// (#227) stehen in Atlas.IDE.Settings.SubPages.
// Abschnitt Symbolindex (#492): Kennzahlen aus atlas.server.status, „Index neu
// aufbauen“ und „Index löschen“ über die Befehle des Servers, im Hintergrund
// (#874): Die Antwort kommt im Hauptthread und geht nur an die Seite, für die
// sie bestellt wurde (FGeneration), solange der Dialog offen ist.
// Baseline, Unterdrückungen und Index-Cache über AtlasServer.exe als Prozess
// rufen beide Seiten über TAtlasIdeServerActions.
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
// Seite Versionsverwaltung (#1285): verbindet TAtlasVcsOptions; das Ergebnis
// geht nur an die Seite, für die es bestellt wurde (FGeneration, Alive). Nach
// OK liest TAtlasIdeVcs settings.json sofort neu, damit ein neuer Pfad gilt.

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
  Atlas.Core.Diagnostics.Guard,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.ActnList,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Progress,
  Atlas.UI.Settings.Page,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Settings.ServerActions,
  Atlas.IDE.Settings.SubPages,
  Atlas.IDE.Settings.VcsOptions,
  Atlas.IDE.Settings.PageOptions,
  Atlas.UI.Settings.Page.General,
  Atlas.UI.Settings.Page.Completion,
  Atlas.UI.Settings.Page.Index,
  Atlas.UI.Settings.Page.Sections,
  Atlas.UI.Settings.Page.VcsProjects,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.StructureSwitch,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Vcs.Service;

type
  TAtlasAddInOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasSettingsPage;
    /// <summary>Zählt die angelegten Seiten; eine späte Antwort für eine geschlossene Seite verfällt (#874).</summary>
    FGeneration: Integer;
    /// <summary>Sagt, ob die Seite noch offen und dieselbe ist wie beim Aufruf; hält das Objekt bis dahin.</summary>
    function Alive: TFunc<Boolean>;
    /// <summary>Führt ACommand im Hintergrund aus; AText macht aus der Antwort (nil ohne Server) den Text für
    /// die Seite.</summary>
    procedure Run(const ACommand: string; const AText: TFunc<TJSONValue, string>);
    /// <summary>Symbolindex (#492): vor LoadFrom, das die Kennzahlen gleich anzeigt.</summary>
    procedure ConnectIndex;
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

/// <summary>Text der Antwort auf „Index neu aufbauen“.</summary>
function RebuildText(AAnswer: TJSONValue): string;
begin
  if AAnswer <> nil then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexRebuilding);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer);
  end;
end;

/// <summary>Text der Antwort auf „Index löschen“.</summary>
function ClearText(AAnswer: TJSONValue): string;
begin
  if AAnswer <> nil then
  begin
    Result := TLspIndexStatus.ClearedText(AAnswer);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer);
  end;
end;

{ TAtlasAddInOptions }

function TAtlasAddInOptions.Alive: TFunc<Boolean>;
var
  mKeep: INTAAddInOptions;
  mOwner: TAtlasAddInOptions;
  mGeneration: Integer;
begin
  // mKeep hält das Objekt, bis die Antwort da ist; ob die Seite noch dieselbe ist, sagt FGeneration.
  mKeep := Self;
  mOwner := Self;
  mGeneration := FGeneration;
  Result :=
    function: Boolean
    begin
      Result := (mKeep <> nil) and (mOwner.FPage <> nil) and (mOwner.FGeneration = mGeneration);
    end;
end;

procedure TAtlasAddInOptions.Run(const ACommand: string; const AText: TFunc<TJSONValue, string>);
var
  mAlive: TFunc<Boolean>;
  mPage: TAtlasSettingsPage;
  mText: TFunc<TJSONValue, string>;
begin
  mText := AText;
  if not Assigned(Hooks.Command) then
  begin
    if FPage <> nil then
    begin
      FPage.Part<TAtlasSettingsIndexPart>.IndexAnswered(mText(nil));
    end;
    Exit;
  end;
  mAlive := Alive();
  mPage := FPage;
  Hooks.Command(ACommand,
    procedure(AAnswer: TJSONValue)
    begin
      if mAlive() then
      begin
        TAtlasGuard.Run(TAtlasFeature.Settings,
          procedure
          begin
            mPage.Part<TAtlasSettingsIndexPart>.IndexAnswered(mText(AAnswer));
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

procedure TAtlasAddInOptions.ConnectIndex;
begin
  FPage.Part<TAtlasSettingsIndexPart>.OnIndexMetrics :=
    procedure
    begin
      Run('atlas.server.status',
        function(AAnswer: TJSONValue): string
        begin
          Result := TLspIndexStatus.Metrics(AAnswer).Text;
        end);
    end;
  FPage.Part<TAtlasSettingsIndexPart>.OnIndexRebuild :=
    procedure
    begin
      Run('atlas.server.rebuildIndex',
        function(AAnswer: TJSONValue): string
        begin
          Result := RebuildText(AAnswer);
        end);
    end;
  FPage.Part<TAtlasSettingsIndexPart>.OnIndexClear :=
    procedure
    begin
      Run('atlas.server.clearIndex',
        function(AAnswer: TJSONValue): string
        begin
          Result := ClearText(AAnswer);
        end);
    end;
end;

procedure TAtlasAddInOptions.FrameCreated(AFrame: TCustomFrame);
begin
  Inc(FGeneration);
  FPage := AFrame as TAtlasSettingsPage;
  FPage.Part<TAtlasSettingsGeneralPart>.DefaultServerPath := HookText(Hooks.DefaultServerPath);
  FPage.Part<TAtlasSettingsCompletionPart>.OnResetHistory := Hooks.ResetHistory;
  TAtlasPageOptions.ConnectRules(FPage);
  // „Einstellungen dazu …“ (#628): gewünschte Zeile zeigen.
  if PendingReveal <> '' then
  begin
    FPage.Reveal(PendingReveal);
  end;
  TAtlasPageOptions.ConnectFavorites(FPage, Hooks.ToolbarCommands);
  ConnectIndex;
  TAtlasPageOptions.ConnectTransfer(FPage);
  TAtlasVcsOptions.Connect(FPage, Alive());
  FPage.LoadFrom(TAtlasIdeSettings.Stored);
  // Vorgabe für den Abschnitt eines Moduls (#1455), z. B. „zuordnen …“ aus „Meine Issues“: nach dem Laden.
  if (PendingReveal <> '') and (PendingArgument <> '') then
  begin
    FPage.Part<TAtlasSettingsSectionsPart>.ShowSettingArgument(PendingReveal, PendingArgument);
  end;
  // „Anmeldung am Server nötig – prüfen …“ der Willkommensseite (#1287): Zeile zeigen und prüfen.
  if PendingVcsServer <> '' then
  begin
    FPage.Part<TAtlasSettingsVcsServersPart>.RevealVcsServer(PendingVcsServer);
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

{ TAtlasOptionsRegistration }

class procedure TAtlasOptionsRegistration.Register(const AHooks: TAtlasOptionsHooks);
var
  Services: INTAEnvironmentOptionsServices;
begin
  if (Options = nil) and Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Services) then
  begin
    Hooks := AHooks;
    TAtlasIdeServerActions.ServerPath := AHooks.ServerPath;
    Options := TAtlasAddInOptions.Create;
    Services.RegisterAddInOptions(Options);
    SnippetOptions := TAtlasSnippetOptions.Create(AHooks.IdeTemplateFolder, AHooks.SnippetFolder);
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
  TAtlasIdeServerActions.ServerPath := nil;
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
