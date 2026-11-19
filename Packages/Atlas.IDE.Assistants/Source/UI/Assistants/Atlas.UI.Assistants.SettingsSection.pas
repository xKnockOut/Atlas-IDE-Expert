unit Atlas.UI.Assistants.SettingsSection;

// Abschnitt des Moduls KI-Assistenten im Optionsdialog (#1888, Muster #1456): eigene Seite „KI-Assistenten“
// (#1906) mit dem Modulschalter assistants.enabled, Schreiben in offene Dateien (assistants.edit) und Builds für
// KI-Assistenten (compiler.mcpBuild; der Schlüssel bleibt, gebaut wird über das Modul Build-Pipeline).
// KI-Schattentext (#1922): Schalter, Anbieter, Modell, Zeilen, Ausnahmen, Tagesgrenze und der Schlüssel des
// gewählten Anbieters. Der Schlüssel wird nie angezeigt; hinterlegen und entfernen gehen über KeyHooks, die die
// Komposition setzt (Anmeldespeicher von Windows).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.UI.Settings.Section,
  Atlas.UI.Settings.ChoiceBox;

type
  /// <summary>Verdeckte Abfrage: Titel, Beschriftung, Schlüssel; False bei Abbruch.</summary>
  TAtlasKeyAsk = reference to function(const ATitle, ALabel: string; var AKey: string): Boolean;

  /// <summary>Schlüssel je Anbieter (Wert von assistants.provider); nicht gesetzte Haken sperren die Knöpfe.
  /// </summary>
  TAtlasAssistantsKeyHooks = record
    Has: TFunc<string, Boolean>;
    /// <summary>Anbieter, Schlüssel; False, wenn er nicht geschrieben wurde.</summary>
    Store: TFunc<string, string, Boolean>;
    Delete: TProc<string>;
    /// <summary>Abfrage des Schlüssels; nil = InputQuery mit verdecktem Feld.</summary>
    Ask: TAtlasKeyAsk;
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
    function ProviderId: string;
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
  ModuleSwitch('assistants.enabled');
  // Änderungen an offenen Dateien (#397) und Builds über diese IDE (#261, build_project).
  Switch('assistants.edit', T(TAtlasAssistantsTextId.SettingsEdit));
  Switch('compiler.mcpBuild', T(TAtlasAssistantsTextId.SettingsMcpBuild));
  // KI-Schattentext (#1922).
  Switch('assistants.inlineSuggestions', T(TAtlasAssistantsTextId.SettingsInline));
  Host.AddHint(T(TAtlasAssistantsTextId.SettingsPrivacy), cPrivacyHeight);
  FProvider := Choice('assistants.provider', T(TAtlasAssistantsTextId.SettingsProvider),
    TArray<string>.Create(T(TAtlasAssistantsTextId.ProviderNone), T(TAtlasAssistantsTextId.ProviderAnthropic)),
    TArray<string>.Create(cAssistantsProviderNames[0], cAssistantsProviderNames[1]));
  AddKeyRows;
  Line('assistants.model', T(TAtlasAssistantsTextId.SettingsModel));
  Number('assistants.contextLines', T(TAtlasAssistantsTextId.SettingsContextLines));
  Line('assistants.exclude', T(TAtlasAssistantsTextId.SettingsExclude));
  Number('assistants.dailyLimit', T(TAtlasAssistantsTextId.SettingsDailyLimit));
end;

procedure TAtlasAssistantsSettingsSection.AddKeyRows;
var
  mRow: TWinControl;
begin
  mRow := Host.AddRow(cRowHeight, nil);
  Host.Attach(mRow, FProvider);
  FKeyState := TLabel.Create(FControls);
  FKeyState.Parent := mRow;
  FKeyState.SetBounds(0, cStateTop, cStateWidth, cStateHeight);
  FKeyState.ShowAccelChar := False;
  mRow := Host.AddRow(cRowHeight, nil);
  Host.Attach(mRow, FProvider);
  FKeyStore := TButton.Create(FControls);
  FKeyStore.Parent := mRow;
  FKeyStore.Caption := T(TAtlasAssistantsTextId.KeyStore);
  FKeyStore.SetBounds(0, 1, cButtonWidth, cButtonHeight);
  FKeyStore.OnClick := KeyStoreClick;
  FKeyDelete := TButton.Create(FControls);
  FKeyDelete.Parent := mRow;
  FKeyDelete.Caption := T(TAtlasAssistantsTextId.KeyDelete);
  FKeyDelete.SetBounds(cButtonGap, 1, cButtonWidth, cButtonHeight);
  FKeyDelete.OnClick := KeyDeleteClick;
  ShowKeyState;
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
  FKeyState := nil;
  FKeyStore := nil;
  FKeyDelete := nil;
  FProvider := nil;
  FreeAndNil(FControls);
  inherited Close;
end;

end.
