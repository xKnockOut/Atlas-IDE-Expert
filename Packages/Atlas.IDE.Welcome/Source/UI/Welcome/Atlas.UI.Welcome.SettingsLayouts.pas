unit Atlas.UI.Welcome.SettingsLayouts;

// Benannte Layouts der Willkommensseite im Optionsdialog (#767, im Modul seit
// #1456; vorher Teil von Atlas.UI.Settings.Page). Zeile mit Auswahl des aktiven
// Layouts und den Knöpfen „Neu …“, „Umbenennen …“ und „Löschen“; die Spalten
// stehen als gebundene Zahl darüber. Beim Wechsel behält das bisherige Layout
// Spalten und Sichtbarkeit der Bereiche, das neue setzt die Schalter der
// Bereiche (Switches) und die Spalten. Sichtbar heißt bei „Neu in Atlas“: nicht
// „aus“. Gespeichert werden Layouts, aktives Layout und Spalten in Save.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.Core.Welcome.Layout,
  Atlas.Core.Welcome.Layouts;

type
  /// <summary>Namen erfragen (Neu, Umbenennen); False bei Abbruch.</summary>
  TAtlasWelcomeAskName = reference to function(const APrompt: string; var AName: string): Boolean;
  /// <summary>Meldung (AQuestion False) oder Rückfrage mit Ja/Nein; True = Ja bzw. gelesen.</summary>
  TAtlasWelcomeConfirm = reference to function(const AText: string; AQuestion: Boolean): Boolean;

  /// <summary>Schalter eines Bereichs der Seite unter dem Namen seiner Einstellung (z. B. WelcomePageContinue).
  /// </summary>
  TAtlasWelcomeSwitch = record
    Setting: string;
    Check: TCheckBox;
  end;

  TAtlasWelcomeSettingsLayouts = class
  public const
    cLayoutsKey = 'welcomePage.layouts';
    cActiveKey = 'welcomePage.activeLayout';
    cColumnsKey = 'welcomePage.columns';
  private
    FLayouts: TAtlasWelcomeLayouts;
    FHost: IAtlasSettingsSectionHost;
    FChoice: TAtlasChoiceBox;
    FNew: TButton;
    FRename: TButton;
    FDelete: TButton;
    FColumns: TCustomEdit;
    FWhatsNew: TAtlasChoiceBox;
    FSwitches: TArray<TAtlasWelcomeSwitch>;
    FOnAskName: TAtlasWelcomeAskName;
    FOnConfirm: TAtlasWelcomeConfirm;
    function AddButton(AParent: TWinControl; AOwner: TComponent; ALeft: Integer; const ACaption: string;
      AClick: TNotifyEvent): TButton;
    function SwitchOf(const AId: string): TCheckBox;
    function SectionShown(const AId: string; out AShown: Boolean): Boolean;
    procedure ShowSection(const AId: string; AShown: Boolean);
    procedure Keep;
    procedure ShowLayouts(AVisibility: Boolean);
    function AskName(var AName: string): Boolean;
    function Confirm(const AText: string; AQuestion: Boolean): Boolean;
    procedure ChoiceChange(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure RenameClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
  public
    constructor Create;
    /// <summary>Zeile der Auswahl über AHost; AOwner besitzt Auswahl und Knöpfe, AColumns ist die gebundene Zahl.
    /// </summary>
    procedure Build(const AHost: IAtlasSettingsSectionHost; AOwner: TComponent; AColumns: TCustomEdit;
      ALeft: Integer);
    /// <summary>Bereichsschalter, deren Häkchen zum aktiven Layout gehören; AWhatsNew die Auswahl „Neu in Atlas“.
    /// </summary>
    procedure Track(const ASwitches: TArray<TAtlasWelcomeSwitch>; AWhatsNew: TAtlasChoiceBox);
    procedure Load(const AValues: IAtlasSettingsValues);
    procedure Save(const AValues: IAtlasSettingsValues);
    /// <summary>Layout AIndex aktiv machen; das bisherige behält Spalten und Sichtbarkeit.</summary>
    procedure Select(AIndex: Integer);
    procedure Close;
    property Layouts: TAtlasWelcomeLayouts read FLayouts;
    property Choice: TAtlasChoiceBox read FChoice;
    property NewButton: TButton read FNew;
    property RenameButton: TButton read FRename;
    property DeleteButton: TButton read FDelete;
    /// <summary>Statt InputQuery (Tests).</summary>
    property OnAskName: TAtlasWelcomeAskName read FOnAskName write FOnAskName;
    /// <summary>Statt MessageDlg (Tests).</summary>
    property OnConfirm: TAtlasWelcomeConfirm read FOnConfirm write FOnConfirm;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  Vcl.Dialogs,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.UI.Welcome.Strings;

const
  cRowHeight = 28;
  cButtonWidth = 96;
  cButtonGap = 6;
  cChoiceWidth = 180;

constructor TAtlasWelcomeSettingsLayouts.Create;
begin
  inherited Create;
  FLayouts := TAtlasWelcomeLayouts.Defaults;
end;

function TAtlasWelcomeSettingsLayouts.AddButton(AParent: TWinControl; AOwner: TComponent; ALeft: Integer;
  const ACaption: string; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := 0;
  Result.Width := cButtonWidth;
  Result.OnClick := AClick;
end;

procedure TAtlasWelcomeSettingsLayouts.Build(const AHost: IAtlasSettingsSectionHost; AOwner: TComponent;
  AColumns: TCustomEdit; ALeft: Integer);
var
  mRow: TWinControl;
  mCaption: TLabel;
  mLeft: Integer;
begin
  FHost := AHost;
  FColumns := AColumns;
  mRow := AHost.AddRow(cRowHeight, TArray<string>.Create(cActiveKey, cLayoutsKey));
  mCaption := TLabel.Create(AOwner);
  mCaption.Parent := mRow;
  mCaption.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeActiveLayout);
  mCaption.Left := 0;
  mCaption.Top := 5;
  // Ohne Fenster füllbar (TAtlasChoiceBox): Die IDE lädt die Seite, bevor sie ein übergeordnetes Fenster hat.
  FChoice := TAtlasChoiceBox.Create(AOwner);
  FChoice.Parent := mRow;
  FChoice.Left := ALeft;
  FChoice.Top := 1;
  FChoice.Width := cChoiceWidth;
  FChoice.OnChange := ChoiceChange;
  mLeft := ALeft + cChoiceWidth + cButtonGap;
  FNew := AddButton(mRow, AOwner, mLeft, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeLayoutNew),
    NewClick);
  FRename := AddButton(mRow, AOwner, mLeft + cButtonWidth + cButtonGap,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeLayoutRename), RenameClick);
  FDelete := AddButton(mRow, AOwner, mLeft + 2 * (cButtonWidth + cButtonGap),
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.SettingsWelcomeLayoutDelete), DeleteClick);
end;

procedure TAtlasWelcomeSettingsLayouts.Track(const ASwitches: TArray<TAtlasWelcomeSwitch>;
  AWhatsNew: TAtlasChoiceBox);
begin
  FSwitches := ASwitches;
  FWhatsNew := AWhatsNew;
end;

function TAtlasWelcomeSettingsLayouts.SwitchOf(const AId: string): TCheckBox;
var
  mSetting: string;
  mSwitch: TAtlasWelcomeSwitch;
begin
  Result := nil;
  mSetting := TAtlasWelcomeCustomizing.SettingOf(AId);
  for mSwitch in FSwitches do
  begin
    if (mSetting <> '') and SameText(mSwitch.Setting, mSetting) then
    begin
      Result := mSwitch.Check;
      Break;
    end;
  end;
end;

function TAtlasWelcomeSettingsLayouts.SectionShown(const AId: string; out AShown: Boolean): Boolean;
var
  mCheck: TCheckBox;
begin
  AShown := False;
  if SameText(AId, TAtlasWelcomeIds.News) then
  begin
    Result := FWhatsNew <> nil;
    AShown := Result and (FWhatsNew.Choice > 0);
  end
  else
  begin
    mCheck := SwitchOf(AId);
    Result := mCheck <> nil;
    AShown := Result and mCheck.Checked;
  end;
end;

procedure TAtlasWelcomeSettingsLayouts.ShowSection(const AId: string; AShown: Boolean);
var
  mShown: Boolean;
  mCheck: TCheckBox;
begin
  if not SectionShown(AId, mShown) or (mShown = AShown) then
  begin
    Exit;
  end;
  if SameText(AId, TAtlasWelcomeIds.News) then
  begin
    // Sichtbar = „nach einem Update“, unsichtbar = „aus“ (Reihenfolge wie TAtlasWhatsNewMode).
    if AShown then
    begin
      FWhatsNew.Choice := Ord(TAtlasWhatsNewMode.AfterUpdate);
    end
    else
    begin
      FWhatsNew.Choice := Ord(TAtlasWhatsNewMode.Off);
    end;
  end
  else
  begin
    mCheck := SwitchOf(AId);
    mCheck.Checked := AShown;
  end;
end;

procedure TAtlasWelcomeSettingsLayouts.Keep;
var
  mLayout: TAtlasWelcomeLayout;
  mItem: TAtlasWelcomeCatalogItem;
  mShown: Boolean;
begin
  mLayout := FLayouts.Current;
  if FColumns <> nil then
  begin
    mLayout := mLayout.WithColumns(EnsureRange(StrToIntDef(Trim(FColumns.Text), mLayout.Columns),
      TAtlasWelcomeLayout.MinColumns, TAtlasWelcomeLayout.MaxColumns));
  end;
  for mItem in TAtlasWelcomeCustomizing.Catalog do
  begin
    if SectionShown(mItem.Id, mShown) and (mLayout.IndexOf(mItem.Id) >= 0) then
    begin
      mLayout := mLayout.WithVisible(mItem.Id, mShown);
    end;
  end;
  FLayouts := FLayouts.WithCurrent(mLayout);
end;

procedure TAtlasWelcomeSettingsLayouts.ShowLayouts(AVisibility: Boolean);
var
  mLayout: TAtlasWelcomeLayout;
  mSlot: TAtlasWelcomeSlot;
begin
  mLayout := FLayouts.Current;
  if FChoice <> nil then
  begin
    FChoice.OnChange := nil;
    try
      FChoice.SetChoices(FLayouts.Names);
      FChoice.Choice := FLayouts.Active;
    finally
      FChoice.OnChange := ChoiceChange;
    end;
  end;
  if FColumns <> nil then
  begin
    FColumns.Text := IntToStr(mLayout.Columns);
  end;
  if (FHost <> nil) and (FDelete <> nil) then
  begin
    FHost.Allow(FDelete, Length(FLayouts.Items) > 1);
  end;
  if AVisibility then
  begin
    for mSlot in mLayout.Slots do
    begin
      ShowSection(mSlot.Id, mSlot.Visible);
    end;
  end;
end;

procedure TAtlasWelcomeSettingsLayouts.Load(const AValues: IAtlasSettingsValues);
var
  mLayout: TAtlasWelcomeLayout;
  mItem: TAtlasWelcomeCatalogItem;
  mShown: Boolean;
begin
  // Wie TAtlasWelcomeCustomizing.Load: Spalten und Sichtbarkeit des aktiven Layouts aus den Einstellungen, die
  // die Seite in die gebundenen Felder schon geladen hat.
  FLayouts := TAtlasWelcomeLayouts.FromJson(AValues.ReadString(cLayoutsKey), AValues.ReadString(cActiveKey));
  mLayout := FLayouts.Current;
  for mItem in TAtlasWelcomeCustomizing.Catalog do
  begin
    if SectionShown(mItem.Id, mShown) and (mLayout.IndexOf(mItem.Id) >= 0) then
    begin
      mLayout := mLayout.WithVisible(mItem.Id, mShown);
    end;
  end;
  mLayout := mLayout.WithColumns(AValues.ReadInteger(cColumnsKey));
  FLayouts := FLayouts.WithCurrent(mLayout);
  ShowLayouts(False);
end;

procedure TAtlasWelcomeSettingsLayouts.Save(const AValues: IAtlasSettingsValues);
begin
  Keep;
  AValues.WriteString(cLayoutsKey, FLayouts.ToJson);
  AValues.WriteString(cActiveKey, FLayouts.ActiveName);
  AValues.WriteInteger(cColumnsKey, FLayouts.Current.Columns);
end;

procedure TAtlasWelcomeSettingsLayouts.Select(AIndex: Integer);
var
  mLayouts: TAtlasWelcomeLayouts;
begin
  if (AIndex < 0) or (AIndex > High(FLayouts.Items)) or (AIndex = FLayouts.Active) then
  begin
    Exit;
  end;
  Keep;
  if FLayouts.Activated(FLayouts.Items[AIndex].Name, mLayouts) then
  begin
    FLayouts := mLayouts;
  end;
  ShowLayouts(True);
end;

function TAtlasWelcomeSettingsLayouts.AskName(var AName: string): Boolean;
begin
  if Assigned(FOnAskName) then
  begin
    Result := FOnAskName(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeLayoutName), AName);
  end
  else
  begin
    Result := InputQuery(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeCustomize),
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeLayoutName), AName);
  end;
end;

function TAtlasWelcomeSettingsLayouts.Confirm(const AText: string; AQuestion: Boolean): Boolean;
begin
  if Assigned(FOnConfirm) then
  begin
    Result := FOnConfirm(AText, AQuestion);
  end
  else if AQuestion then
  begin
    Result := MessageDlg(AText, mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  end
  else
  begin
    MessageDlg(AText, mtInformation, [mbOK], 0);
    Result := True;
  end;
end;

procedure TAtlasWelcomeSettingsLayouts.ChoiceChange(Sender: TObject);
begin
  Select(FChoice.Choice);
end;

procedure TAtlasWelcomeSettingsLayouts.NewClick(Sender: TObject);
var
  mName: string;
  mLayouts: TAtlasWelcomeLayouts;
begin
  mName := '';
  if not AskName(mName) or (Trim(mName) = '') then
  begin
    Exit;
  end;
  Keep;
  if not FLayouts.Added(Trim(mName), mLayouts) then
  begin
    Confirm(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeArrangeLayoutTaken, [Trim(mName)]), False);
    Exit;
  end;
  // Die Kopie übernimmt die Sichtbarkeit; die Häkchen bleiben.
  FLayouts := mLayouts;
  ShowLayouts(False);
end;

procedure TAtlasWelcomeSettingsLayouts.RenameClick(Sender: TObject);
var
  mName: string;
  mLayouts: TAtlasWelcomeLayouts;
begin
  mName := FLayouts.ActiveName;
  if not AskName(mName) or (Trim(mName) = '') or (Trim(mName) = FLayouts.ActiveName) then
  begin
    Exit;
  end;
  if not FLayouts.Renamed(Trim(mName), mLayouts) then
  begin
    Confirm(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeArrangeLayoutTaken, [Trim(mName)]), False);
    Exit;
  end;
  FLayouts := mLayouts;
  ShowLayouts(False);
end;

procedure TAtlasWelcomeSettingsLayouts.DeleteClick(Sender: TObject);
var
  mLayouts: TAtlasWelcomeLayouts;
begin
  if (Length(FLayouts.Items) < 2) or
    not Confirm(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeArrangeDeleteConfirm, [FLayouts.ActiveName]),
    True) then
  begin
    Exit;
  end;
  if FLayouts.Deleted(mLayouts) then
  begin
    FLayouts := mLayouts;
    ShowLayouts(True);
  end;
end;

procedure TAtlasWelcomeSettingsLayouts.Close;
begin
  // Auswahl und Knöpfe gibt der Besitzer frei (der Abschnitt); hier nur die Verweise lösen.
  FHost := nil;
  FChoice := nil;
  FNew := nil;
  FRename := nil;
  FDelete := nil;
  FColumns := nil;
  FWhatsNew := nil;
  FSwitches := nil;
  FOnAskName := nil;
  FOnConfirm := nil;
end;

end.
