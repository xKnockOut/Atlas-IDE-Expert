unit Atlas.UI.Assistants.SettingsSection;

// Abschnitt des Moduls KI-Assistenten im Optionsdialog (#1888, Muster #1456): eigene Seite „KI-Assistenten“
// (#1906) mit dem Modulschalter assistants.enabled, Schreiben in offene Dateien (assistants.edit), Builds für
// KI-Assistenten (compiler.mcpBuild; der Schlüssel bleibt, gebaut wird über das Modul Build-Pipeline), Debuggen
// durch KI-Assistenten (debug.mcp mit Rechten und Leiste, #1874; ausgeführt im Modul Debugger), IDE-Zustand für
// get_ide_context (assistants.context, #2050) und Hinweis auf veraltete Anweisungsdateien
// (assistants.instructionsHint, #2615); verbundene IDE für Kommandozeilen-Assistenten (assistants.link mit Auswahl,
// Vergleich und Taste, #2377).
// KI-Schattentext (#1922): Schalter, Anbieter, Modell, Zeilen, Ausnahmen, Tagesgrenze und der Schlüssel des
// gewählten Anbieters. Der Schlüssel wird nie angezeigt; hinterlegen und entfernen gehen über KeyHooks, die die
// Komposition setzt (Anmeldespeicher von Windows).
// OpenAI-kompatibler Anbieter (#2056): Adresse, Modell mit „Modelle abrufen“ (Auswahl aus /models), Zeitlimit und
// „Verbindung testen“ für jeden Anbieter. Beides läuft über die Haken im Hintergrund und nimmt die Werte, wie sie
// gerade auf der Seite stehen; eine Antwort nach dem Schließen der Seite verfällt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Menus,
  Atlas.UI.Settings.Section,
  Atlas.UI.Settings.ChoiceBox;

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
  end;

  /// <summary>Verbindung einer Antwort aus dem Hintergrund zum Abschnitt; nil nach Close.</summary>
  IAtlasAssistantsSectionLink = interface
    ['{4F2B8D61-9C3E-4A75-B0D2-7E1F6A3C9B54}']
    function Section: TObject;
    procedure Cut;
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
  Atlas.UI.Assistants.Strings;

const
  cButtonWidth = 210;
  cButtonGap = 216;
  cRowHeight = 28;
  cButtonHeight = 25;
  /// <summary>Hinweis zum Datenschutz: Höhe für zwei Zeilen.</summary>
  cPrivacyHeight = 34;
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
  // Verbundene IDE für Kommandozeilen-Assistenten (#2377).
  Switch('assistants.link', T(TAtlasAssistantsTextId.SettingsLink));
  Switch('assistants.link.shareSelection', T(TAtlasAssistantsTextId.SettingsLinkShareSelection));
  Switch('assistants.link.diffPreview', T(TAtlasAssistantsTextId.SettingsLinkDiffPreview));
  Key('assistants.link.mentionKey', T(TAtlasAssistantsTextId.SettingsLinkMentionKey));
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
  FreeAndNil(FControls);
  inherited Close;
end;

end.
