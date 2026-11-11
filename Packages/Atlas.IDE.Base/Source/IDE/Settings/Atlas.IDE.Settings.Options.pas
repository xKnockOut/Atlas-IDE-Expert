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
// Den Index-Cache leert die Seite „Atlas.Server“ über AtlasServer.exe als
// Prozess (TAtlasIdeServerActions); Baseline und Unterdrückungen gehören dem
// Modul Prüfregeln (#1755).
// ShowSetting (#628, „Einstellungen dazu …“): öffnet Tools › Optionen, wählt
// die Seite „Atlas“ in der Baumansicht des Dialogs (soweit sie sich finden
// lässt) und zeigt dort die Einstellung mit markierter Zeile (Reveal).
// Seite Issue-Tracker: Den Abschnitt mit Verbindungen, Projekten, Abfragen
// und Prüfungen baut das Modul Tracker (#1455, Atlas.IDE.Tracker.Settings).
// ShowSetting mit Vorgabe („zuordnen …“ aus „Meine Issues“, #1261) reicht die
// Vorgabe nach dem Laden an den Abschnitt, dem die Einstellung gehört.
// Seite Versionsverwaltung: baut und verdrahtet das Modul Versionsverwaltung
// als Abschnitt (#1905); nach OK liest es settings.json über ApplySettings neu.
// ShowVcsServer reicht den Ordner als Vorgabe an dessen Abschnitt.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.UI.EditorToolbar.Customize;

type
  /// <summary>Befehl an den Server im Hintergrund (#874); ADone im Hauptthread mit der Antwort, nil ohne Server
  /// oder bei Fehler. Den Wert gibt der Aufrufer von ADone frei.</summary>
  TAtlasServerCommand = reference to procedure(ACommand: string; ADone: TProc<TJSONValue>);

  /// <summary>Was die Optionsseiten von anderen Features brauchen; setzt die Composition (die Seiten
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
  Atlas.Core.Modules.Contract,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.NodeScope,
  Atlas.Core.Lsp.Progress,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.Overview,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Groups,
  Atlas.Core.Settings.ModuleSwitches,
  Atlas.Core.Modules.Registry,
  Atlas.IDE.Settings.ServerActions,
  Atlas.IDE.Settings.SubPages,
  Atlas.IDE.Settings.ModuleNodes,
  Atlas.IDE.Settings.PageOptions,
  Atlas.UI.Settings.Page.General,
  Atlas.UI.Settings.Page.Completion,
  Atlas.UI.Settings.Page.Index,
  Atlas.UI.Settings.Page.Sections,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings,
  Atlas.IDE.Foundation.StructureSwitch,
  Atlas.IDE.Foundation.Settings;

type
  TAtlasAddInOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasSettingsPage;
    /// <summary>Knoten je Package (#1903): Besitzer, Überschrift im Baum ('Atlas.Module.Tests') und im Kopf.
    /// </summary>
    FScope: TAtlasSettingsNodeScope;
    FCaption: string;
    FTitle: string;
    /// <summary>Stand beim Laden; gespeichert wird nur, was der Knoten daran geändert hat.</summary>
    FLoaded: TAtlasPluginSettings;
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
    constructor Create(const AScope: TAtlasSettingsNodeScope; const ACaption, ATitle: string);
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

  /// <summary>Übersicht „Atlas“ (#1903): Hauptschalter, Stand der Packages, Suche.</summary>
  TAtlasOverviewOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TAtlasSettingsOverview;
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
  /// <summary>Knoten „Base“ unter „Module“ (#1903).</summary>
  BaseOptions: INTAAddInOptions;
  ServerOptions: INTAAddInOptions;
  SnippetOptions: INTAAddInOptions;
  KeysOptions: INTAAddInOptions;
  /// <summary>Gesetzt von Register, geleert von Unregister.</summary>
  Hooks: TAtlasOptionsHooks;
  /// <summary>Einstellung, die die Seite „Atlas“ beim nächsten Anlegen zeigen soll (#628); '' ohne.</summary>
  PendingReveal: string;
  /// <summary>Vorgabe zu PendingReveal für den Abschnitt eines Moduls (#1455); '' ohne.</summary>
  PendingArgument: string;

/// <summary>Im offenen Dialog zum Knoten der Einstellung springen (Übersicht und Suchfeld der Knoten, #1903, #1884).
/// </summary>
procedure OpenFromOverview(ASetting, ASwitch: string); forward;

/// <summary>Ist das Package mit dem Modulschalter ASwitch installiert (hat es einen Knoten)? '' = Base.</summary>
function ModuleInstalled(const ASwitch: string): Boolean;
begin
  Result := (ASwitch = '') or (TAtlasModuleNodes.NodeOfSwitch(ASwitch) <> nil);
end;

/// <summary>Name des Packages zum Modulschalter ASwitch.</summary>
function ModuleNameOf(ASwitch: string): string;
begin
  Result := TAtlasModuleNodes.NameOfSwitch(ASwitch);
end;

type
  /// <summary>Zugriff auf Items, das TCustomTreeView geschützt hält (Baum des Optionsdialogs ist eine eigene
  /// Ableitung).
  /// </summary>
  TAtlasTreeAccess = class(TCustomTreeView);

type
  /// <summary>Sucht im offenen Optionsdialog die Seite „Atlas“ und wählt sie (#628).</summary>
  TAtlasOptionsSelector = class
  private const
    cIntervalMs = 200;
    cMaxTries = 50;
  private
    FTimer: TTimer;
    FTries: Integer;
    procedure Tick(Sender: TObject);
    class function FindTree(AParent: TWinControl): TCustomTreeView; static;
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
  FTimer.Interval := cIntervalMs;
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

class function TAtlasOptionsSelector.FindTree(AParent: TWinControl): TCustomTreeView;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    // TCustomTreeView: Delphi 13 nimmt eine eigene Ableitung statt TTreeView (#1903).
    if AParent.Controls[mIndex] is TCustomTreeView then
    begin
      Exit(TCustomTreeView(AParent.Controls[mIndex]));
    end;
    if AParent.Controls[mIndex] is TWinControl then
    begin
      Result := FindTree(TWinControl(AParent.Controls[mIndex]));
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;
end;

procedure TAtlasOptionsSelector.Tick(Sender: TObject);
var
  mForm: TCustomForm;
  mTree: TCustomTreeView;
  mNode: TTreeNode;
begin
  try
    Inc(FTries);
    if (FTries > cMaxTries) or (PendingReveal = '') then
    begin
      Stop;
      Exit;
    end;
    mForm := Screen.ActiveCustomForm;
    if (mForm = nil) or not (fsModal in mForm.FormState) then
    begin
      Exit;
    end;
    mTree := FindTree(mForm);
    if mTree = nil then
    begin
      Exit;
    end;
    // Die Seite heißt „Atlas“ (GetCaption) und hängt unter „Drittanbieter“, nicht oben im Baum.
    for mNode in TAtlasTreeAccess(mTree).Items do
    begin
      if SameText(mNode.Text, 'Atlas') and (mNode.Parent <> nil) then
      begin
        Stop;
        mNode.MakeVisible;
        mTree.Selected := mNode;
        Exit;
      end;
    end;
    // Nicht gefunden: Delphi 13 legt die Unterseiten erst beim Aufklappen an ("Fremdhersteller" zu). Obere
    // Zweige aufklappen und beim nächsten Takt erneut suchen, statt aufzugeben.
    for mNode in TAtlasTreeAccess(mTree).Items do
    begin
      if (mNode.Parent = nil) and mNode.HasChildren and not mNode.Expanded then
      begin
        mNode.Expand(False);
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

constructor TAtlasAddInOptions.Create(const AScope: TAtlasSettingsNodeScope; const ACaption, ATitle: string);
begin
  inherited Create;
  FScope := AScope;
  FCaption := ACaption;
  FTitle := ATitle;
end;

function TAtlasAddInOptions.GetCaption: string;
begin
  Result := FCaption;
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
  TAtlasPageOptions.ConnectServerVersion(FPage);
  // „Einstellungen dazu …“ (#628): gewünschte Zeile zeigen.
  if PendingReveal <> '' then
  begin
    FPage.Reveal(PendingReveal);
  end;
  TAtlasPageOptions.ConnectFavorites(FPage, Hooks.ToolbarCommands);
  ConnectIndex;
  TAtlasPageOptions.ConnectTransfer(FPage);
  TAtlasPageOptions.ConnectHelp(FPage);
  // Suchfeld über dem Baum (#1884): nur installierte Packages; Treffer anderer Knoten im offenen Dialog öffnen.
  FPage.Search.OnInstalled := ModuleInstalled;
  FPage.Search.OnModuleName := ModuleNameOf;
  FPage.OnOpenSetting := OpenFromOverview;
  // Knoten je Package (#1903): nur, was diesem Knoten gehört.
  FPage.SetTitle(FTitle);
  FPage.ApplyScope(FScope);
  FLoaded := TAtlasIdeSettings.Stored;
  FPage.LoadFrom(FLoaded);
  // Vorgabe für den Abschnitt eines Moduls (#1455), z. B. „zuordnen …“ aus „Meine Issues“: nach dem Laden.
  if (PendingReveal <> '') and (PendingArgument <> '') then
  begin
    FPage.Part<TAtlasSettingsSectionsPart>.ShowSettingArgument(PendingReveal, PendingArgument);
  end;
end;

procedure TAtlasAddInOptions.DialogClosed(Accepted: Boolean);
var
  mSettings: TAtlasPluginSettings;
  mTarget: IAtlasMemorySettingsStore;
begin
  PendingReveal := '';
  PendingArgument := '';
  try
    if Accepted and (FPage <> nil) then
    begin
      // Nur die Änderungen dieses Knotens: Ein anderer Knoten hat vielleicht schon gespeichert (#1903).
      mTarget := TAtlasMemorySettingsStore.FromSettings(TAtlasIdeSettings.Stored);
      TAtlasSettingsMerge.Changes(TAtlasMemorySettingsStore.FromSettings(FLoaded),
        TAtlasMemorySettingsStore.FromSettings(FPage.CurrentSettings), mTarget);
      mSettings := TAtlasIdeSettings.Stored;
      mSettings.Load(mTarget);
      mSettings.Normalize;
      TAtlasIdeSettings.Update(mSettings);
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

/// <summary>Seite eines Moduls unter „Module“ (#1903): die Optionsseite, gefiltert auf das Modul.</summary>
function ModuleOptions(const AInfo: TAtlasModuleInfo): INTAAddInOptions;
begin
  Result := TAtlasAddInOptions.Create(TAtlasSettingsNodeScope.Module(AInfo.Id, AInfo.Switch),
    TAtlasModuleNodes.CaptionOf(AInfo.Name), AInfo.Name);
end;

/// <summary>Klassen der Steuerelemente unter AParent, deren Name „Tree“ enthält (Protokoll, wenn kein Baum passt).
/// </summary>
function TreeLikeClasses(AParent: TWinControl): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    if Pos('TREE', UpperCase(AParent.Controls[mIndex].ClassName)) > 0 then
    begin
      Result := Result + ' ' + AParent.Controls[mIndex].ClassName;
    end;
    if AParent.Controls[mIndex] is TWinControl then
    begin
      Result := Result + TreeLikeClasses(TWinControl(AParent.Controls[mIndex]));
    end;
  end;
end;

/// <summary>Kind von ANode mit dem Text AText; klappt ANode dafür auf, weil Delphi 13 Unterknoten erst beim Aufklappen
/// anlegt. nil, wenn ANode nil ist oder kein Kind passt.</summary>
function ChildNamed(ANode: TTreeNode; const AText: string): TTreeNode;
begin
  Result := nil;
  if ANode = nil then
  begin
    Exit;
  end;
  if not ANode.Expanded then
  begin
    ANode.Expand(False);
  end;
  Result := ANode.getFirstChild;
  while (Result <> nil) and not SameText(Result.Text, AText) do
  begin
    Result := Result.getNextSibling;
  end;
end;

/// <summary>Wählt im offenen Optionsdialog den Knoten Atlas › APath (#1903). False, wenn sich Baum oder Knoten nicht
/// finden lassen; dann steht im Protokoll, welche Baumklassen der Dialog hat.</summary>
function SelectOptionsNode(const APath: TArray<string>): Boolean;
var
  mForm: TCustomForm;
  mTree: TCustomTreeView;
  mNode, mAtlas: TTreeNode;
  mText: string;
begin
  Result := False;
  mForm := Screen.ActiveCustomForm;
  if mForm = nil then
  begin
    Exit;
  end;
  mTree := TAtlasOptionsSelector.FindTree(mForm);
  if mTree = nil then
  begin
    TAtlasGuard.Log('Optionen: kein Baum im Dialog zum Springen gefunden; Klassen:' + TreeLikeClasses(mForm)); // german-ok Protokoll
    Exit;
  end;
  mAtlas := nil;
  for mNode in TAtlasTreeAccess(mTree).Items do
  begin
    if SameText(mNode.Text, 'Atlas') and (mNode.Parent <> nil) then
    begin
      mAtlas := mNode;
      Break;
    end;
  end;
  mNode := mAtlas;
  for mText in APath do
  begin
    mNode := ChildNamed(mNode, mText);
  end;
  if mNode = nil then
  begin
    TAtlasGuard.Log('Optionen: Knoten Atlas › ' + string.Join(' › ', APath) + ' nicht im Baum ' + mTree.ClassName); // german-ok Protokoll
    Exit;
  end;
  mNode.MakeVisible;
  mTree.Selected := mNode;
  Result := True;
end;

{ TAtlasOverviewOptions }

function TAtlasOverviewOptions.GetArea: string;
begin
  Result := '';
end;

function TAtlasOverviewOptions.GetCaption: string;
begin
  Result := 'Atlas';
end;

function TAtlasOverviewOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TAtlasSettingsOverview;
end;

/// <summary>Klick in der Übersicht: Einstellung ASetting im Knoten des Modulschalters ASwitch ('' = Base) zeigen;
/// ASetting '' = Knoten „Module“.</summary>
procedure OpenFromOverview(ASetting, ASwitch: string);
var
  mName: string;
  mNode: INTAAddInOptions;
begin
  if ASetting = '' then
  begin
    SelectOptionsNode([TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsModulesNode)]);
    Exit;
  end;
  mName := 'Base';
  if ASwitch <> '' then
  begin
    mName := TAtlasModuleNodes.NameOfSwitch(ASwitch);
  end;
  PendingReveal := ASetting;
  if not SelectOptionsNode([TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsModulesNode), mName]) then
  begin
    PendingReveal := '';
    Exit;
  end;
  // Schon einmal gezeigter Knoten (#1884): Die IDE legt seine Seite nicht neu an, also selbst zeigen.
  mNode := TAtlasModuleNodes.NodeOfSwitch(ASwitch);
  if (mNode <> nil) and ((mNode as TObject) is TAtlasAddInOptions) and
    (TAtlasAddInOptions(mNode as TObject).FPage <> nil) then
  begin
    TAtlasAddInOptions(mNode as TObject).FPage.Reveal(ASetting);
    PendingReveal := '';
  end;
end;

procedure TAtlasOverviewOptions.FrameCreated(AFrame: TCustomFrame);
var
  mKnown: TArray<TAtlasKnownModule>;
  mModule: TAtlasKnownModule;
  mInstalled, mOn: Integer;
  mCatalog: TAtlasSettingsCatalog;
  mSwitches: TArray<TAtlasModuleSwitch>;
  mSettings: TAtlasPluginSettings;
begin
  try
    FPage := AFrame as TAtlasSettingsOverview;
    mKnown := AtlasModuleRegistry.Known;
    mSettings := TAtlasIdeSettings.Stored;
    mCatalog := TAtlasSettingsCatalog.CreateDefault;
    try
      mSwitches := TAtlasModuleSwitches.Read(mCatalog);
    finally
      mCatalog.Free;
    end;
    mInstalled := 0;
    mOn := 0;
    for mModule in mKnown do
    begin
      if mModule.Installed then
      begin
        Inc(mInstalled);
        // Ohne Modulschalter immer an.
        if (mModule.Info.Switch = '') or TAtlasModuleSwitches.IsOn(mSettings, mSwitches, mModule.Info.Switch) then
        begin
          Inc(mOn);
        end;
      end;
    end;
    FPage.OnModuleName :=
      function(ASwitch: string): string
      begin
        Result := TAtlasModuleNodes.NameOfSwitch(ASwitch);
      end;
    // Klick auf einen Treffer bzw. die Zeile der Packages (#1903): im offenen Dialog zum Knoten springen; die Seite
    // dort zeigt die Einstellung beim Anlegen (PendingReveal).
    FPage.OnOpen := OpenFromOverview;
    // Suche (#1884): nur installierte Packages, Zustand nach den gespeicherten Werten, abschaltbar.
    FPage.OnInstalled := ModuleInstalled;
    FPage.OnSettings :=
      function: TAtlasPluginSettings
      begin
        Result := TAtlasIdeSettings.Stored;
      end;
    FPage.SetSearchAvailable(mSettings.SettingsSearch);
    FPage.Load(mInstalled, Length(mKnown), mOn);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Settings, E);
  end;
end;

procedure TAtlasOverviewOptions.DialogClosed(Accepted: Boolean);
begin
  // Nur Anzeige und Suche: Die Knoten speichern ihre Werte selbst.
  FPage := nil;
end;

function TAtlasOverviewOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TAtlasOverviewOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TAtlasOverviewOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TAtlasOptionsRegistration }

class procedure TAtlasOptionsRegistration.Register(const AHooks: TAtlasOptionsHooks);
var
  mServices: INTAEnvironmentOptionsServices;
begin
  if (Options = nil) and Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, mServices) then
  begin
    Hooks := AHooks;
    TAtlasIdeServerActions.ServerPath := AHooks.ServerPath;
    Options := TAtlasOverviewOptions.Create;
    mServices.RegisterAddInOptions(Options);
    // Zuerst „Module“ mit Base und je Modul einem Knoten, dann Snippets, Tastenkonflikte, Server (#1903).
    BaseOptions := TAtlasAddInOptions.Create(TAtlasSettingsNodeScope.Base, TAtlasModuleNodes.CaptionOf('Base'),
      'Base');
    TAtlasModuleNodes.Start(BaseOptions, ModuleOptions);
    SnippetOptions := TAtlasSnippetOptions.Create(AHooks.IdeTemplateFolder, AHooks.SnippetFolder);
    mServices.RegisterAddInOptions(SnippetOptions);
    KeysOptions := TAtlasKeysOptions.Create;
    mServices.RegisterAddInOptions(KeysOptions);
    ServerOptions := TAtlasServerOptions.Create;
    mServices.RegisterAddInOptions(ServerOptions);
  end;
end;

class procedure TAtlasOptionsRegistration.Unregister;
var
  mServices: INTAEnvironmentOptionsServices;
begin
  TAtlasModuleNodes.Stop;
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, mServices) then
  begin
    if SnippetOptions <> nil then
    begin
      mServices.UnregisterAddInOptions(SnippetOptions);
    end;
    if KeysOptions <> nil then
    begin
      mServices.UnregisterAddInOptions(KeysOptions);
    end;
    if ServerOptions <> nil then
    begin
      mServices.UnregisterAddInOptions(ServerOptions);
    end;
    if Options <> nil then
    begin
      mServices.UnregisterAddInOptions(Options);
    end;
  end;
  BaseOptions := nil;
  SnippetOptions := nil;
  KeysOptions := nil;
  ServerOptions := nil;
  Options := nil;
  Hooks := Default(TAtlasOptionsHooks);
  TAtlasIdeServerActions.ServerPath := nil;
  PendingReveal := '';
  PendingArgument := '';
  FreeAndNil(Selector);
end;

/// <summary>Aktion bzw. Menüpunkt „Optionen…“ der IDE ausführen; False, wenn keins zu finden ist.</summary>
function RunOptionsDialog: Boolean;
const
  cActionName = 'ToolsOptionsCommand';
  cItemName = 'ToolsOptionsItem';
var
  mServices: INTAServices;
  mIndex: Integer;

  function FindItem(AItem: TMenuItem): TMenuItem;
  var
    mChild: Integer;
  begin
    Result := nil;
    if SameText(AItem.Name, cItemName) then
    begin
      Exit(AItem);
    end;
    for mChild := 0 to AItem.Count - 1 do
    begin
      Result := FindItem(AItem.Items[mChild]);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;

var
  mItem: TMenuItem;
begin
  Result := False;
  if not Supports(BorlandIDEServices, INTAServices, mServices) then
  begin
    Exit;
  end;
  if mServices.ActionList <> nil then
  begin
    for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
    begin
      if SameText(mServices.ActionList.Actions[mIndex].Name, cActionName) then
      begin
        mServices.ActionList.Actions[mIndex].Execute;
        Exit(True);
      end;
    end;
  end;
  if mServices.MainMenu <> nil then
  begin
    mItem := FindItem(mServices.MainMenu.Items);
    if mItem <> nil then
    begin
      mItem.Click;
      Exit(True);
    end;
  end;
end;

/// <summary>Tools › Optionen über IOTAEnvironmentOptions140.EditOptions auf der Seite „Atlas“ öffnen; False, wenn die
/// IDE das nicht anbietet.</summary>
function EditAtlasOptions(const ACaption: string): Boolean;
var
  mServices: IOTAServices;
  mEnvironment: IOTAEnvironmentOptions140;
begin
  Result := Supports(BorlandIDEServices, IOTAServices, mServices) and (mServices.GetEnvironmentOptions <> nil) and
    Supports(mServices.GetEnvironmentOptions, IOTAEnvironmentOptions140, mEnvironment);
  if Result then
  begin
    mEnvironment.EditOptions('', ACaption);
  end;
end;

/// <summary>Knoten, in dem die Einstellung AKey steht (#1903): der des Moduls, dem sie gehört, sonst Base.
/// Schlüssel, die nur die Seite kennt (Zeilen der Versionsverwaltung wie „VcsProjects“), nach ihrer Vorsilbe.
/// </summary>
function NodeOfSetting(const AKey: string): INTAAddInOptions;
var
  mCatalog: TAtlasSettingsCatalog;
  mGroups: TAtlasSettingsGroups;
  mSwitch: string;
begin
  mCatalog := TAtlasSettingsCatalog.CreateDefault;
  mGroups := TAtlasSettingsGroups.Create(mCatalog);
  try
    mSwitch := '';
    if (mCatalog.IndexOfName(AKey) >= 0) or (mCatalog.IndexOfKey(AKey) >= 0) then
    begin
      if mCatalog.IndexOfName(AKey) < 0 then
      begin
        mSwitch := TAtlasSettingsNodeScope.ModuleOf(mCatalog, mGroups, mCatalog[mCatalog.IndexOfKey(AKey)].Name);
      end
      else
      begin
        mSwitch := TAtlasSettingsNodeScope.ModuleOf(mCatalog, mGroups, AKey);
      end;
    end
    else if AKey.StartsWith('Vcs', True) then
    begin
      mSwitch := 'vcs';
    end;
  finally
    mGroups.Free;
    mCatalog.Free;
  end;
  Result := TAtlasModuleNodes.NodeOfSwitch(mSwitch);
  if Result = nil then
  begin
    Result := BaseOptions;
  end;
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
    if not EditAtlasOptions(NodeOfSetting(AKey).GetCaption) then
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
  // Der Abschnitt der Versionsverwaltung nimmt den Ordner als Vorgabe zu vcs.projects (#1905).
  ShowSetting('VcsProjects', AFolder);
end;

end.
