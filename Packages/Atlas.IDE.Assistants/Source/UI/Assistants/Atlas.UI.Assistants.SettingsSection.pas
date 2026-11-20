unit Atlas.UI.Assistants.SettingsSection;

// Abschnitt des Moduls KI-Assistenten im Optionsdialog (#1888, Muster #1456): eigene Seite „KI-Assistenten“
// (#1906) mit dem Modulschalter assistants.enabled, Schreiben in offene Dateien (assistants.edit), Builds für
// KI-Assistenten (compiler.mcpBuild; der Schlüssel bleibt, gebaut wird über das Modul Build-Pipeline), Debuggen
// durch KI-Assistenten (debug.mcp mit Rechten und Leiste, #1874; ausgeführt im Modul Debugger), IDE-Zustand für
// get_ide_context (assistants.context, #2050) und Hinweis auf veraltete Anweisungsdateien
// (assistants.instructionsHint, #2615).
// KI-Schattentext (#1922): Schalter, Anbieter, Modell, Zeilen, Ausnahmen, Tagesgrenze und der Schlüssel des
// gewählten Anbieters. Der Schlüssel wird nie angezeigt; hinterlegen und entfernen gehen über KeyHooks, die die
// Komposition setzt (Anmeldespeicher von Windows).
// OpenAI-kompatibler Anbieter (#2056): Adresse, Modell mit „Modelle abrufen“ (Auswahl aus /models), Zeitlimit und
// „Verbindung testen“ für jeden Anbieter. Beides läuft über die Haken im Hintergrund und nimmt die Werte, wie sie
// gerade auf der Seite stehen; eine Antwort nach dem Schließen der Seite verfällt.
// Anbieter der IDE (Smart CodeInsight, #2744, #2745): Quelle für einfache Aufgaben (assistants.textSource),
// Mitbenutzen eines Anbieters der IDE samt Name (Auswahl über „Anbieter der IDE …“), Liste der Anbieter mit Status
// und Funktionen, „Smart CodeInsight öffnen“ und das Anmelden des eigenen Anbieters bei der IDE. Die Liste kommt
// über den Haken IdeProviders; ohne ToolsAPI.AI (älteres Delphi 12) bleibt sie leer.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Menus,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.Section,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.Core.Assistants.Contract.IdeAi;

type
  /// <summary>Verdeckte Abfrage: Titel, Beschriftung, Schlüssel; False bei Abbruch.</summary>
  TAtlasKeyAsk = reference to function(const ATitle, ALabel: string; var AKey: string): Boolean;

  /// <summary>Werte der Seite für eine Probe oder die Modellliste, auch ungespeichert.</summary>
  TAtlasAssistantsProbeInput = record
    ProviderId: string;
    Model: string;
    Url: string;
    TimeoutMs: Integer;
  end;

  /// <summary>Ergebnis im Hauptthread: Text für die Zeile unter den Knöpfen.</summary>
  TAtlasAssistantsProbeDone = reference to procedure(const AText: string);
  /// <summary>Ergebnis im Hauptthread: Modelle (nil bei Fehler) und Text.</summary>
  TAtlasAssistantsModelsDone = reference to procedure(const AModels: TArray<string>; const AText: string);
  TAtlasAssistantsProbe = reference to procedure(const AInput: TAtlasAssistantsProbeInput;
    const ADone: TAtlasAssistantsProbeDone);
  TAtlasAssistantsModels = reference to procedure(const AInput: TAtlasAssistantsProbeInput;
    const ADone: TAtlasAssistantsModelsDone);

  /// <summary>Schlüssel je Anbieter (Wert von assistants.provider); nicht gesetzte Haken sperren die Knöpfe.
  /// </summary>
  TAtlasAssistantsKeyHooks = record
    Has: TFunc<string, Boolean>;
    /// <summary>Anbieter, Schlüssel; False, wenn er nicht geschrieben wurde.</summary>
    Store: TFunc<string, string, Boolean>;
    Delete: TProc<string>;
    /// <summary>Abfrage des Schlüssels; nil = InputQuery mit verdecktem Feld.</summary>
    Ask: TAtlasKeyAsk;
    /// <summary>„Verbindung testen“ (#2056); im Hintergrund, ADone im Hauptthread.</summary>
    Probe: TAtlasAssistantsProbe;
    /// <summary>„Modelle abrufen“ (#2056); im Hintergrund, ADone im Hauptthread.</summary>
    Models: TAtlasAssistantsModels;
    /// <summary>KI-Anbieter der IDE (#2744); nil = keine Liste.</summary>
    IdeProviders: TFunc<TArray<TAtlasIdeAiProvider>>;
    /// <summary>Optionen der IDE bei Smart CodeInsight öffnen; False, wenn es nicht ging.</summary>
    OpenIdeOptions: TFunc<Boolean>;
  end;

  /// <summary>Verbindung einer Antwort aus dem Hintergrund zum Abschnitt; nil nach Close.</summary>
  IAtlasAssistantsSectionLink = interface
    ['{4F2B8D61-9C3E-4A75-B0D2-7E1F6A3C9B54}']
    function Section: TObject;
    procedure Cut;
  end;

  /// <summary>Zeilen zu den KI-Anbietern der IDE (#2744, #2745): Quelle für einfache Aufgaben, gewünschter Anbieter
  /// mit Auswahl und Liste, Anmeldung bei Smart CodeInsight. Gehört dem Besitzer der Elemente des Abschnitts.
  /// </summary>
  TAtlasAssistantsIdeRows = class(TComponent)
  private
    FHost: IAtlasSettingsSectionHost;
    FProviders: TFunc<TArray<TAtlasIdeAiProvider>>;
    FOpenOptions: TFunc<Boolean>;
    FName: TEdit;
    FButton: TButton;
    FMenu: TPopupMenu;
    FList: TLabel;
    procedure AddButtons(ACanList: Boolean);
    procedure AddList(ASource: TControl);
    procedure ButtonClick(Sender: TObject);
    procedure Picked(Sender: TObject);
    procedure OptionsClick(Sender: TObject);
  public
    /// <summary>Zeilen anlegen. AProviders: Anbieter der IDE (nil = keine Liste); AOpenOptions: Smart CodeInsight
    /// öffnen (nil = Knopf gesperrt).</summary>
    procedure Build(const AHost: IAtlasSettingsSectionHost; const AProviders: TFunc<TArray<TAtlasIdeAiProvider>>;
      const AOpenOptions: TFunc<Boolean>);
    /// <summary>Liste der Anbieter neu füllen.</summary>
    procedure Show;
    /// <summary>Funktionen eines Anbieters der IDE als Text („Chat, Anweisung“).</summary>
    class function FeaturesText(AFeatures: TAtlasIdeAiFeatures): string; static;
    /// <summary>Eine Zeile je Anbieter der IDE: Name, Status, Funktionen; ohne Anbieter ein Hinweis.</summary>
    class function ProviderLines(const AProviders: TArray<TAtlasIdeAiProvider>): string; static;
    property ListLabel: TLabel read FList;
    property NameEdit: TEdit read FName;
  end;

  TAtlasAssistantsSettingsSection = class(TAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.assistants';
    cAreaId = 'KI-Assistenten';
  private class var
    FKeyHooks: TAtlasAssistantsKeyHooks;
  private
    /// <summary>Besitzer der eigenen Elemente; die Zeilen gehören der Seite.</summary>
    FControls: TComponent;
    FProvider: TAtlasChoiceBox;
    FKeyState: TLabel;
    FKeyStore: TButton;
    FKeyDelete: TButton;
    FModel: TEdit;
    FOpenAiUrl: TEdit;
    FOpenAiModel: TEdit;
    FOpenAiTimeout: TEdit;
    FModelsButton: TButton;
    FModelsMenu: TPopupMenu;
    FProbeButton: TButton;
    FProbeState: TLabel;
    FIde: TAtlasAssistantsIdeRows;
    FLink: IAtlasAssistantsSectionLink;
    function ProviderId: string;
    function ProbeInput: TAtlasAssistantsProbeInput;
    procedure AddOpenAiRows;
    procedure AddProbeRow;
    procedure ProbeClick(Sender: TObject);
    procedure ModelsClick(Sender: TObject);
    procedure ModelPicked(Sender: TObject);
    procedure ShowModels(const AModels: TArray<string>; const AText: string);
    procedure ShowProbe(const AText: string);
    procedure AddKeyRows;
    procedure ShowKeyState;
    procedure KeyStoreClick(Sender: TObject);
    procedure KeyDeleteClick(Sender: TObject);
  protected
    procedure BuildRows; override;
  public
    destructor Destroy; override;
    function OwnerId: string; override;
    function AreaId: string; override;
    procedure WindowReady; override;
    procedure Close; override;
    /// <summary>Setzt die Komposition beim Anmelden und löst sie beim Abmelden (Default).</summary>
    class property KeyHooks: TAtlasAssistantsKeyHooks read FKeyHooks write FKeyHooks;
    property KeyStateLabel: TLabel read FKeyState;
    property KeyStoreButton: TButton read FKeyStore;
    property KeyDeleteButton: TButton read FKeyDelete;
    property ProviderBox: TAtlasChoiceBox read FProvider;
  end;

implementation

uses
  System.Types,
  Vcl.Dialogs,
  Atlas.Core.Settings.Plugin.Assistants,
  Atlas.UI.Assistants.Strings,
  Atlas.Core.Assistants.IdeProviders;

const
  cButtonWidth = 210;
  cButtonGap = 216;
  cRowHeight = 28;
  cButtonHeight = 25;
  /// <summary>Hinweis zum Datenschutz: Höhe für zwei Zeilen.</summary>
  cPrivacyHeight = 34;
  /// <summary>Liste der Anbieter der IDE: Höhe für vier Zeilen.</summary>
  cIdeListHeight = 66;
  /// <summary>Zeile mit dem Zustand (Schlüssel, Probe).</summary>
  cStateTop = 6;
  cStateWidth = 420;
  cStateHeight = 16;
  // Ein Steuerzeichen am Anfang der Beschriftung lässt InputQuery das Feld verdecken.
  cHidden = #31;

type
  TSectionLink = class(TInterfacedObject, IAtlasAssistantsSectionLink)
  private
    FSection: TObject;
  public
    constructor Create(ASection: TObject);
    function Section: TObject;
    procedure Cut;
  end;

{ TSectionLink }

constructor TSectionLink.Create(ASection: TObject);
begin
  inherited Create;
  FSection := ASection;
end;

function TSectionLink.Section: TObject;
begin
  Result := FSection;
end;

procedure TSectionLink.Cut;
begin
  FSection := nil;
end;

/// <summary>Text des Moduls.</summary>
function T(AId: TAtlasAssistantsTextId): string;
begin
  Result := TAtlasAssistantsStrings.Text(AId);
end;

{ TAtlasAssistantsSettingsSection }

destructor TAtlasAssistantsSettingsSection.Destroy;
begin
  FreeAndNil(FControls);
  inherited Destroy;
end;

procedure TAtlasAssistantsSettingsSection.BuildRows;
begin
  FControls := TComponent.Create(nil);
  FLink := TSectionLink.Create(Self);
  ModuleSwitch('assistants.enabled');
  // Änderungen an offenen Dateien (#397) und Builds über diese IDE (#261, build_project).
  Switch('assistants.edit', T(TAtlasAssistantsTextId.SettingsEdit));
  // Änderungen an ungespeicherten Dateien zurückhalten statt ablehnen (#2605).
  Switch('assistants.editHoldModified', T(TAtlasAssistantsTextId.SettingsEditHold));
  Switch('compiler.mcpBuild', T(TAtlasAssistantsTextId.SettingsMcpBuild));
  // Debuggen durch KI-Assistenten (#1874): Rechte und Leiste.
  Switch('debug.mcp', T(TAtlasAssistantsTextId.SettingsDebugMcp));
  Switch('debug.mcp.sideEffects', T(TAtlasAssistantsTextId.SettingsDebugSideEffects));
  Switch('debug.mcp.modify', T(TAtlasAssistantsTextId.SettingsDebugModify));
  Switch('debug.mcp.attach', T(TAtlasAssistantsTextId.SettingsDebugAttach));
  Switch('debug.mcp.banner', T(TAtlasAssistantsTextId.SettingsDebugBanner));
  // Anzeige „KI-Assistent aktiv“ mit Pause (#1906).
  Switch('assistants.banner', T(TAtlasAssistantsTextId.SettingsBanner));
  // IDE-Zustand (#2050): wo der Entwickler gerade ist, samt Auswahl bis zur Grenze.
  Switch('assistants.context', T(TAtlasAssistantsTextId.SettingsContext));
  Switch('assistants.context.selection', T(TAtlasAssistantsTextId.SettingsContextSelection));
  Number('assistants.context.selectionMax',
    T(TAtlasAssistantsTextId.SettingsContextSelectionMax));
  // Hinweis auf veraltete Anweisungsdateien für KI-Assistenten (#2615).
  Switch('assistants.instructionsHint', T(TAtlasAssistantsTextId.SettingsInstructionsHint));
  // Rückfragen in der IDE (#2620) und KI-Protokoll (#2049).
  Switch('assistants.questionsInIde', T(TAtlasAssistantsTextId.SettingsQuestions));
  Switch('assistants.log', T(TAtlasAssistantsTextId.SettingsLog));
  Number('assistants.log.max', T(TAtlasAssistantsTextId.SettingsLogMax));
  // KI-Schattentext (#1922).
  Switch('assistants.inlineSuggestions', T(TAtlasAssistantsTextId.SettingsInline));
  Host.AddHint(T(TAtlasAssistantsTextId.SettingsPrivacy), cPrivacyHeight);
  FProvider := Choice('assistants.provider', T(TAtlasAssistantsTextId.SettingsProvider),
    TArray<string>.Create(T(TAtlasAssistantsTextId.ProviderNone), T(TAtlasAssistantsTextId.ProviderAnthropic),
    T(TAtlasAssistantsTextId.ProviderOpenAi)),
    TArray<string>.Create(cAssistantsProviderNames[0], cAssistantsProviderNames[1], cAssistantsProviderNames[2]));
  AddKeyRows;
  FModel := Line('assistants.model', T(TAtlasAssistantsTextId.SettingsModel));
  AddOpenAiRows;
  AddProbeRow;
  Number('assistants.contextLines', T(TAtlasAssistantsTextId.SettingsContextLines));
  Line('assistants.exclude', T(TAtlasAssistantsTextId.SettingsExclude));
  Number('assistants.dailyLimit', T(TAtlasAssistantsTextId.SettingsDailyLimit));
  // Anbieter der IDE (#2744, #2745).
  FIde := TAtlasAssistantsIdeRows.Create(FControls);
  FIde.Build(Host, FKeyHooks.IdeProviders, FKeyHooks.OpenIdeOptions);
end;

{ TAtlasAssistantsIdeRows }

procedure TAtlasAssistantsIdeRows.Build(const AHost: IAtlasSettingsSectionHost;
  const AProviders: TFunc<TArray<TAtlasIdeAiProvider>>; const AOpenOptions: TFunc<Boolean>);
var
  mSource: TControl;
begin
  FHost := AHost;
  FProviders := AProviders;
  if not Assigned(FProviders) then
  begin
    FProviders :=
      function: TArray<TAtlasIdeAiProvider>
      begin
        Result := nil;
      end;
  end;
  FOpenOptions := AOpenOptions;
  mSource := FHost.AddChoice('assistants.textSource', T(TAtlasAssistantsTextId.SettingsTextSource),
    TArray<string>.Create(T(TAtlasAssistantsTextId.TextSourceIde), T(TAtlasAssistantsTextId.TextSourceOwn),
    T(TAtlasAssistantsTextId.TextSourceNone)),
    TArray<string>.Create(cAssistantsTextSources[0], cAssistantsTextSources[1], cAssistantsTextSources[2]));
  FHost.AddSwitch('assistants.ideProvider', T(TAtlasAssistantsTextId.SettingsIdeProvider));
  FName := FHost.AddText('assistants.ideProvider.name', T(TAtlasAssistantsTextId.SettingsIdeProviderName)) as TEdit;
  AddButtons(Assigned(AProviders));
  AddList(mSource);
  FHost.AddSwitch('assistants.registerInIde', T(TAtlasAssistantsTextId.SettingsRegisterInIde));
end;

procedure TAtlasAssistantsIdeRows.AddButtons(ACanList: Boolean);
var
  mRow: TWinControl;
  mOptions: TButton;
begin
  mRow := FHost.AddRow(cRowHeight, nil);
  FHost.Attach(mRow, FName);
  FButton := TButton.Create(Self);
  FButton.Parent := mRow;
  FButton.Caption := T(TAtlasAssistantsTextId.IdeProvidersButton);
  PlaceScaled(FButton, 0, 1, cButtonWidth, cButtonHeight);
  FButton.OnClick := ButtonClick;
  FButton.Enabled := ACanList;
  mOptions := TButton.Create(Self);
  mOptions.Parent := mRow;
  mOptions.Caption := T(TAtlasAssistantsTextId.IdeOptionsButton);
  PlaceScaled(mOptions, cButtonGap, 1, cButtonWidth, cButtonHeight);
  mOptions.OnClick := OptionsClick;
  mOptions.Enabled := Assigned(FOpenOptions);
  FMenu := TPopupMenu.Create(Self);
end;

procedure TAtlasAssistantsIdeRows.AddList(ASource: TControl);
var
  mRow: TWinControl;
begin
  mRow := FHost.AddRow(cIdeListHeight, nil);
  FHost.Attach(mRow, ASource);
  FList := TLabel.Create(Self);
  FList.Parent := mRow;
  PlaceScaled(FList, 0, 0, cStateWidth, cIdeListHeight);
  FList.ShowAccelChar := False;
  FList.WordWrap := False;
  Show;
end;

class function TAtlasAssistantsIdeRows.FeaturesText(AFeatures: TAtlasIdeAiFeatures): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  if TAtlasIdeAiFeature.Chat in AFeatures then
  begin
    mParts := mParts + [T(TAtlasAssistantsTextId.FeatureChat)];
  end;
  if TAtlasIdeAiFeature.Instruction in AFeatures then
  begin
    mParts := mParts + [T(TAtlasAssistantsTextId.FeatureInstruction)];
  end;
  if TAtlasIdeAiFeature.ListModels in AFeatures then
  begin
    mParts := mParts + [T(TAtlasAssistantsTextId.FeatureModels)];
  end;
  Result := string.Join(', ', mParts);
end;

class function TAtlasAssistantsIdeRows.ProviderLines(const AProviders: TArray<TAtlasIdeAiProvider>): string;
var
  mProvider: TAtlasIdeAiProvider;
  mLines: TArray<string>;
  mState: string;
begin
  if Length(AProviders) = 0 then
  begin
    Exit(T(TAtlasAssistantsTextId.IdeProvidersNone));
  end;
  mLines := nil;
  for mProvider in AProviders do
  begin
    if mProvider.Enabled then
    begin
      mState := T(TAtlasAssistantsTextId.IdeProviderActive);
    end
    else
    begin
      mState := T(TAtlasAssistantsTextId.IdeProviderOff);
    end;
    mLines := mLines + [TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.IdeProviderLine,
      [mProvider.Name, mState, FeaturesText(mProvider.Features)])];
  end;
  Result := string.Join(sLineBreak, mLines);
end;

procedure TAtlasAssistantsIdeRows.Show;
begin
  if FList <> nil then
  begin
    FList.Caption := ProviderLines(FProviders());
  end;
end;

procedure TAtlasAssistantsIdeRows.ButtonClick(Sender: TObject);
var
  mProvider: TAtlasIdeAiProvider;
  mItem: TMenuItem;
  mPoint: TPoint;
begin
  Show;
  FMenu.Items.Clear;
  for mProvider in FProviders() do
  begin
    // Der eigene Eintrag steht nie zur Wahl (keine Schleife, #2745).
    if TAtlasIdeAiProviders.IsOwn(mProvider.Name) then
    begin
      Continue;
    end;
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := mProvider.Name;
    mItem.Hint := mProvider.Name;
    mItem.AutoHotkeys := maManual;
    mItem.Enabled := mProvider.Usable;
    mItem.OnClick := Picked;
    FMenu.Items.Add(mItem);
  end;
  if (FMenu.Items.Count > 0) and FButton.HandleAllocated and FButton.Showing then
  begin
    mPoint := FButton.ClientToScreen(TPoint.Create(0, FButton.Height));
    FMenu.Popup(mPoint.X, mPoint.Y);
  end;
end;

procedure TAtlasAssistantsIdeRows.Picked(Sender: TObject);
begin
  if (FName <> nil) and (Sender is TMenuItem) then
  begin
    FName.Text := TMenuItem(Sender).Hint;
    FHost.Changed;
  end;
end;

procedure TAtlasAssistantsIdeRows.OptionsClick(Sender: TObject);
begin
  if not FOpenOptions() then
  begin
    ShowMessage(T(TAtlasAssistantsTextId.IdeOptionsMissing));
  end;
end;

/// <summary>Lage in Pixeln bei 96 dpi, an die Auflösung des Steuerelements angepasst.</summary>
procedure PlaceScaled(AControl: TControl; ALeft, ATop, AWidth, AHeight: Integer);
begin
  AControl.SetBounds(AControl.ScaleValue(ALeft), AControl.ScaleValue(ATop), AControl.ScaleValue(AWidth),
    AControl.ScaleValue(AHeight));
end;

procedure TAtlasAssistantsSettingsSection.AddKeyRows;
var
  mRow: TWinControl;
begin
  mRow := Host.AddRow(cRowHeight, nil);
  Host.Attach(mRow, FProvider);
  FKeyState := TLabel.Create(FControls);
  FKeyState.Parent := mRow;
  PlaceScaled(FKeyState, 0, cStateTop, cStateWidth, cStateHeight);
  FKeyState.ShowAccelChar := False;
  mRow := Host.AddRow(cRowHeight, nil);
  Host.Attach(mRow, FProvider);
  FKeyStore := TButton.Create(FControls);
  FKeyStore.Parent := mRow;
  FKeyStore.Caption := T(TAtlasAssistantsTextId.KeyStore);
  PlaceScaled(FKeyStore, 0, 1, cButtonWidth, cButtonHeight);
  FKeyStore.OnClick := KeyStoreClick;
  FKeyDelete := TButton.Create(FControls);
  FKeyDelete.Parent := mRow;
  FKeyDelete.Caption := T(TAtlasAssistantsTextId.KeyDelete);
  PlaceScaled(FKeyDelete, cButtonGap, 1, cButtonWidth, cButtonHeight);
  FKeyDelete.OnClick := KeyDeleteClick;
  ShowKeyState;
end;

procedure TAtlasAssistantsSettingsSection.AddOpenAiRows;
var
  mRow: TWinControl;
begin
  FOpenAiUrl := Line('assistants.openaiCompatible.url', T(TAtlasAssistantsTextId.SettingsOpenAiUrl));
  FOpenAiModel := Line('assistants.openaiCompatible.model', T(TAtlasAssistantsTextId.SettingsOpenAiModel));
  mRow := Host.AddRow(cRowHeight, nil);
  Host.Attach(mRow, FOpenAiModel);
  FModelsButton := TButton.Create(FControls);
  FModelsButton.Parent := mRow;
  FModelsButton.Caption := T(TAtlasAssistantsTextId.ModelsButton);
  PlaceScaled(FModelsButton, 0, 1, cButtonWidth, cButtonHeight);
  FModelsButton.OnClick := ModelsClick;
  FModelsButton.Enabled := Assigned(FKeyHooks.Models);
  FModelsMenu := TPopupMenu.Create(FControls);
  FOpenAiTimeout := Number('assistants.openaiCompatible.timeoutMs', T(TAtlasAssistantsTextId.SettingsOpenAiTimeout));
end;

procedure TAtlasAssistantsSettingsSection.AddProbeRow;
var
  mRow: TWinControl;
begin
  mRow := Host.AddRow(cRowHeight, nil);
  Host.Attach(mRow, FProvider);
  FProbeButton := TButton.Create(FControls);
  FProbeButton.Parent := mRow;
  FProbeButton.Caption := T(TAtlasAssistantsTextId.ProbeButton);
  PlaceScaled(FProbeButton, 0, 1, cButtonWidth, cButtonHeight);
  FProbeButton.OnClick := ProbeClick;
  FProbeButton.Enabled := Assigned(FKeyHooks.Probe);
  FProbeState := TLabel.Create(FControls);
  FProbeState.Parent := mRow;
  PlaceScaled(FProbeState, cButtonGap, cStateTop, cStateWidth, cStateHeight);
  FProbeState.ShowAccelChar := False;
end;

function TAtlasAssistantsSettingsSection.ProbeInput: TAtlasAssistantsProbeInput;
begin
  Result := Default(TAtlasAssistantsProbeInput);
  Result.ProviderId := ProviderId;
  if FModel <> nil then
  begin
    Result.Model := Trim(FModel.Text);
  end;
  if Result.ProviderId = cAssistantsProviderNames[2] then
  begin
    Result.Model := Trim(FOpenAiModel.Text);
    Result.Url := Trim(FOpenAiUrl.Text);
    Result.TimeoutMs := StrToIntDef(Trim(FOpenAiTimeout.Text), cDefaultAssistantsOpenAiTimeoutMs);
  end
  else if Result.ProviderId = cAssistantsProviderNames[1] then
  begin
    Result.TimeoutMs := cMaxAssistantsOpenAiTimeoutMs;
  end;
end;

/// <summary>Antwort an den Abschnitt hinter ALink, solange er offen ist.</summary>
function ProbeDoneFor(const ALink: IAtlasAssistantsSectionLink): TAtlasAssistantsProbeDone;
begin
  Result :=
    procedure(const AText: string)
    begin
      if ALink.Section <> nil then
      begin
        TAtlasAssistantsSettingsSection(ALink.Section).ShowProbe(AText);
      end;
    end;
end;

function ModelsDoneFor(const ALink: IAtlasAssistantsSectionLink): TAtlasAssistantsModelsDone;
begin
  Result :=
    procedure(const AModels: TArray<string>; const AText: string)
    begin
      if ALink.Section <> nil then
      begin
        TAtlasAssistantsSettingsSection(ALink.Section).ShowModels(AModels, AText);
      end;
    end;
end;

procedure TAtlasAssistantsSettingsSection.ProbeClick(Sender: TObject);
begin
  if ProviderId = cAssistantsProviderNames[0] then
  begin
    ShowProbe(T(TAtlasAssistantsTextId.KeyNoProvider));
    Exit;
  end;
  ShowProbe(T(TAtlasAssistantsTextId.ProbeRunning));
  FProbeButton.Enabled := False;
  FKeyHooks.Probe(ProbeInput, ProbeDoneFor(FLink));
end;

procedure TAtlasAssistantsSettingsSection.ShowProbe(const AText: string);
begin
  if FProbeState = nil then
  begin
    Exit;
  end;
  FProbeState.Caption := AText;
  FProbeButton.Enabled := Assigned(FKeyHooks.Probe);
end;

procedure TAtlasAssistantsSettingsSection.ModelsClick(Sender: TObject);
var
  mInput: TAtlasAssistantsProbeInput;
begin
  mInput := ProbeInput;
  mInput.ProviderId := cAssistantsProviderNames[2];
  mInput.Url := Trim(FOpenAiUrl.Text);
  mInput.TimeoutMs := StrToIntDef(Trim(FOpenAiTimeout.Text), cDefaultAssistantsOpenAiTimeoutMs);
  ShowProbe(T(TAtlasAssistantsTextId.ModelsRunning));
  FModelsButton.Enabled := False;
  FKeyHooks.Models(mInput, ModelsDoneFor(FLink));
end;

procedure TAtlasAssistantsSettingsSection.ShowModels(const AModels: TArray<string>; const AText: string);
var
  mModel: string;
  mItem: TMenuItem;
  mPoint: TPoint;
begin
  if FModelsButton = nil then
  begin
    Exit;
  end;
  FModelsButton.Enabled := Assigned(FKeyHooks.Models);
  ShowProbe(AText);
  if Length(AModels) = 0 then
  begin
    Exit;
  end;
  FModelsMenu.Items.Clear;
  for mModel in AModels do
  begin
    mItem := TMenuItem.Create(FModelsMenu);
    mItem.Caption := mModel;
    mItem.Hint := mModel;
    mItem.AutoHotkeys := maManual;
    mItem.OnClick := ModelPicked;
    FModelsMenu.Items.Add(mItem);
  end;
  if FModelsButton.HandleAllocated and FModelsButton.Showing then
  begin
    mPoint := FModelsButton.ClientToScreen(TPoint.Create(0, FModelsButton.Height));
    FModelsMenu.Popup(mPoint.X, mPoint.Y);
  end;
end;

procedure TAtlasAssistantsSettingsSection.ModelPicked(Sender: TObject);
begin
  if (FOpenAiModel <> nil) and (Sender is TMenuItem) then
  begin
    FOpenAiModel.Text := TMenuItem(Sender).Hint;
    Host.Changed;
  end;
end;

function TAtlasAssistantsSettingsSection.ProviderId: string;
begin
  Result := cAssistantsProviderNames[0];
  if (FProvider <> nil) and (FProvider.Choice >= Low(cAssistantsProviderNames)) and
    (FProvider.Choice <= High(cAssistantsProviderNames)) then
  begin
    Result := cAssistantsProviderNames[FProvider.Choice];
  end;
end;

procedure TAtlasAssistantsSettingsSection.ShowKeyState;
var
  mId: string;
  mKnown: Boolean;
begin
  if FKeyState = nil then
  begin
    Exit;
  end;
  mId := ProviderId;
  mKnown := mId <> cAssistantsProviderNames[0];
  if not mKnown then
  begin
    FKeyState.Caption := T(TAtlasAssistantsTextId.KeyNoProvider);
  end
  else if Assigned(FKeyHooks.Has) and FKeyHooks.Has(mId) then
  begin
    FKeyState.Caption := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.KeyPresent, [mId]);
  end
  else
  begin
    FKeyState.Caption := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.KeyMissing, [mId]);
  end;
  FKeyStore.Enabled := mKnown and Assigned(FKeyHooks.Store);
  FKeyDelete.Enabled := mKnown and Assigned(FKeyHooks.Delete);
end;

procedure TAtlasAssistantsSettingsSection.WindowReady;
begin
  inherited WindowReady;
  ShowKeyState;
  if FIde <> nil then
  begin
    FIde.Show;
  end;
end;

/// <summary>Verdeckte Abfrage über InputQuery; der Schlüssel wird nie vorbelegt.</summary>
function AskHidden(const ATitle, ALabel: string; var AKey: string): Boolean;
var
  mValues: array of string;
begin
  SetLength(mValues, 1);
  mValues[0] := '';
  Result := InputQuery(ATitle, [cHidden + ALabel], mValues);
  if Result then
  begin
    AKey := Trim(mValues[0]);
  end;
  mValues[0] := '';
end;

procedure TAtlasAssistantsSettingsSection.KeyStoreClick(Sender: TObject);
var
  mId, mKey: string;
  mOk: Boolean;
begin
  mId := ProviderId;
  mKey := '';
  if Assigned(FKeyHooks.Ask) then
  begin
    mOk := FKeyHooks.Ask(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.KeyPromptTitle, [mId]),
      T(TAtlasAssistantsTextId.KeyPromptLabel), mKey);
  end
  else
  begin
    mOk := AskHidden(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.KeyPromptTitle, [mId]),
      T(TAtlasAssistantsTextId.KeyPromptLabel), mKey);
  end;
  if mOk and (mKey <> '') and Assigned(FKeyHooks.Store) then
  begin
    FKeyHooks.Store(mId, mKey);
  end;
  mKey := '';
  ShowKeyState;
end;

procedure TAtlasAssistantsSettingsSection.KeyDeleteClick(Sender: TObject);
begin
  if Assigned(FKeyHooks.Delete) then
  begin
    FKeyHooks.Delete(ProviderId);
  end;
  ShowKeyState;
end;

function TAtlasAssistantsSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasAssistantsSettingsSection.AreaId: string;
begin
  Result := cAreaId;
end;

procedure TAtlasAssistantsSettingsSection.Close;
begin
  // Rückwärts zum Aufbau: erst die eigenen Elemente, dann die Zeilen der Seite.
  // Antworten aus dem Hintergrund erreichen den Abschnitt danach nicht mehr.
  if FLink <> nil then
  begin
    FLink.Cut;
    FLink := nil;
  end;
  FKeyState := nil;
  FKeyStore := nil;
  FKeyDelete := nil;
  FProvider := nil;
  FModel := nil;
  FOpenAiUrl := nil;
  FOpenAiModel := nil;
  FOpenAiTimeout := nil;
  FModelsButton := nil;
  FModelsMenu := nil;
  FProbeButton := nil;
  FProbeState := nil;
  FIde := nil;
  FreeAndNil(FControls);
  inherited Close;
end;

end.
