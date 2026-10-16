unit Atlas.UI.Settings.Transfer;

// Dialoge zum Exportieren und Importieren der Einstellungen (#723), ohne Open
// Tools API und ohne Dateizugriff (den macht die IDE-Schicht). Schlicht wie
// die übrigen Atlas-Dialoge:
// - Export: Bereiche zum Ankreuzen, Umgang mit Zugangsdaten, kurzer Hinweis,
//   „Speichern…“ und „Abbrechen“.
// - Import: Name und Beschreibung der Datei, „Zusammenführen“ oder
//   „Ersetzen“, Bereiche, Liste „Einstellung | Bereich | Aktuell | Neu |
//   Hinweis“ mit Kontrollkästchen je Schlüssel (nur neue Werte und
//   Zurücksetzen lassen sich wählen), Zahl der gewählten Werte, „Übernehmen“.
//   Moduswechsel und Bereiche rechnen die Vorschau über OnPreview neu.
// - Profil: Liste der eingebauten Profile mit Beschreibung.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Transfer;

type
  TAtlasImportPreviewFunc = reference to function(AMode: TAtlasImportMode;
    const AAreas: TArray<string>): TAtlasImportPreview;

  TAtlasExportDialog = class(TForm)
  private
    FAreas: TArray<TCheckBox>;
    FAreaIds: TArray<string>;
    FSecrets: TRadioGroup;
    FSave: TButton;
    FCancel: TButton;
    procedure AreaClick(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent; ACatalog: TAtlasSettingsCatalog; ASecrets: TAtlasSecretMode);
    /// <summary>Gewählte Optionen.</summary>
    function Options: TAtlasExportOptions;
    /// <summary>Modal fragen; True nach „Speichern…“.</summary>
    class function Execute(ACatalog: TAtlasSettingsCatalog; var AOptions: TAtlasExportOptions;
      const APrepare: TProc<TForm>): Boolean; static;
    property SaveButton: TButton read FSave;
    property Secrets: TRadioGroup read FSecrets;
  end;

  TAtlasImportDialog = class(TForm)
  private
    FCatalog: TAtlasSettingsCatalog;
    FPreview: TAtlasImportPreview;
    FOnPreview: TAtlasImportPreviewFunc;
    FInfo: TLabel;
    FMode: TRadioGroup;
    FAreaBoxes: TArray<TCheckBox>;
    FAreaIds: TArray<string>;
    FList: TListView;
    FCount: TLabel;
    FApply: TButton;
    FCancel: TButton;
    FFilled: Boolean;
    procedure Recalculate(Sender: TObject);
    procedure ListChanged(Sender: TObject);
    procedure ListKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SyncChecks;
    function ValueText(const AItem: TAtlasImportItem; const AJson: string): string;
    function NoteText(const AItem: TAtlasImportItem): string;
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; ACatalog: TAtlasSettingsCatalog; const AFileName: string;
      const APreview: TAtlasImportPreview; const AOnPreview: TAtlasImportPreviewFunc);
    /// <summary>Liste aus der Vorschau füllen (braucht ein Fenster).</summary>
    procedure Fill;
    /// <summary>Vorschau mit der Auswahl der Liste.</summary>
    function Result_: TAtlasImportPreview;
    /// <summary>Modal zeigen; True nach „Übernehmen“, APreview enthält dann die Auswahl.</summary>
    class function Execute(ACatalog: TAtlasSettingsCatalog; const AFileName: string;
      var APreview: TAtlasImportPreview; const AOnPreview: TAtlasImportPreviewFunc;
      const APrepare: TProc<TForm>): Boolean; static;
    property List: TListView read FList;
    property Mode: TRadioGroup read FMode;
    property CountLabel: TLabel read FCount;
    property ApplyButton: TButton read FApply;
  end;

  TAtlasProfileDialog = class(TForm)
  private
    FList: TListBox;
    FDescription: TLabel;
    FNames: TArray<string>;
    FDescriptions: TArray<string>;
    FLoad: TButton;
    FCancel: TButton;
    procedure ListClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const ANames, ADescriptions: TArray<string>);
    /// <summary>Modal wählen; True mit AIndex des Profils.</summary>
    class function Choose(const ANames, ADescriptions: TArray<string>; out AIndex: Integer;
      const APrepare: TProc<TForm>): Boolean; static;
    property List: TListBox read FList;
  end;

implementation

uses
  Vcl.Graphics,
  Vcl.Menus,
  Atlas.UI.Strings;

const
  Gap = 8;

function NewButton(AOwner: TForm; AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  AOwner.Canvas.Font := AOwner.Font;
  Result.Width := AOwner.Canvas.TextWidth(ACaption) + AOwner.ScaleValue(32);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, Gap, Gap div 2);
end;

function NewButtons(AOwner: TForm): TFlowPanel;
begin
  Result := TFlowPanel.Create(AOwner);
  Result.Parent := AOwner;
  Result.Align := alBottom;
  Result.AutoSize := True;
  Result.BevelOuter := bvNone;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(Gap, Gap, Gap, Gap);
end;

procedure SetupForm(AForm: TForm; const ACaption: string; AWidth: Integer);
begin
  AForm.Caption := ACaption;
  AForm.BorderStyle := bsDialog;
  AForm.Position := poMainFormCenter;
  AForm.Font.Name := 'Segoe UI';
  AForm.Font.Size := 9;
  AForm.ClientWidth := AForm.ScaleValue(AWidth);
end;

function HasArea(const AAreas: TArray<string>; const AArea: string): Boolean;
var
  Area: string;
begin
  Result := False;
  for Area in AAreas do
    if SameText(Area, AArea) then
      Exit(True);
end;

function English: Boolean;
begin
  Result := TAtlasStrings.Language = TAtlasLanguage.English;
end;

{ TAtlasExportDialog }

constructor TAtlasExportDialog.CreateDialog(AOwner: TComponent; ACatalog: TAtlasSettingsCatalog;
  ASecrets: TAtlasSecretMode);
var
  Info, Title: TLabel;
  Areas: TFlowPanel;
  Box: TCheckBox;
  Area: TAtlasCatalogArea;
  Buttons: TFlowPanel;
begin
  inherited CreateNew(AOwner);
  SetupForm(Self, TAtlasStrings.Text(TAtlasTextId.SettingsExportTitle), 460);
  Buttons := NewButtons(Self);
  FSave := NewButton(Self, Buttons, TAtlasStrings.Text(TAtlasTextId.SettingsExportSave));
  FSave.ModalResult := mrOk;
  FSave.Default := True;
  FCancel := NewButton(Self, Buttons, TAtlasStrings.Text(TAtlasTextId.SettingsDialogCancel));
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;

  Info := TLabel.Create(Self);
  Info.Parent := Self;
  Info.Align := alTop;
  Info.AlignWithMargins := True;
  Info.Margins.SetBounds(Gap, Gap, Gap, 0);
  Info.WordWrap := True;
  Info.ShowAccelChar := False;
  Info.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsExportInfo);

  Title := TLabel.Create(Self);
  Title.Parent := Self;
  Title.Align := alTop;
  Title.AlignWithMargins := True;
  Title.Margins.SetBounds(Gap, Gap, Gap, 0);
  Title.Top := 1000;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsExportAreas);
  Title.Font.Style := [fsBold];

  Areas := TFlowPanel.Create(Self);
  Areas.Parent := Self;
  Areas.Align := alTop;
  Areas.AutoSize := True;
  Areas.BevelOuter := bvNone;
  Areas.AlignWithMargins := True;
  Areas.Margins.SetBounds(Gap, 4, Gap, 0);
  Areas.Top := 2000;
  for Area in ACatalog.Areas do
  begin
    Box := TCheckBox.Create(Self);
    Box.Parent := Areas;
    Box.Width := ScaleValue(140);
    Box.Caption := ACatalog.AreaCaption(Area.Id, English);
    Box.Checked := True;
    Box.OnClick := AreaClick;
    FAreas := FAreas + [Box];
    FAreaIds := FAreaIds + [Area.Id];
  end;

  FSecrets := TRadioGroup.Create(Self);
  FSecrets.Parent := Self;
  FSecrets.Align := alTop;
  FSecrets.AlignWithMargins := True;
  FSecrets.Margins.SetBounds(Gap, Gap, Gap, 0);
  FSecrets.Top := 3000;
  FSecrets.Height := ScaleValue(64);
  FSecrets.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsExportSecrets);
  FSecrets.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsExportSecretsOmit));
  FSecrets.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsExportSecretsPlaceholder));
  FSecrets.ItemIndex := Ord(ASecrets);
  FSecrets.Columns := 2;

  // Feste Höhe: vier Zeilen Bereiche bei 11 Bereichen und drei Spalten.
  ClientHeight := ScaleValue(360);
end;

procedure TAtlasExportDialog.AreaClick(Sender: TObject);
var
  Box: TCheckBox;
begin
  FSave.Enabled := False;
  for Box in FAreas do
    if Box.Checked then
      FSave.Enabled := True;
end;

function TAtlasExportDialog.Options: TAtlasExportOptions;
var
  Index: Integer;
  Areas: TArray<string>;
  Secrets: TAtlasSecretMode;
begin
  Areas := nil;
  for Index := 0 to High(FAreas) do
    if FAreas[Index].Checked then
      Areas := Areas + [FAreaIds[Index]];
  Secrets := smOmit;
  if FSecrets.ItemIndex = 1 then
    Secrets := smPlaceholder;
  Result := TAtlasExportOptions.Create(Areas, Secrets);
end;

class function TAtlasExportDialog.Execute(ACatalog: TAtlasSettingsCatalog; var AOptions: TAtlasExportOptions;
  const APrepare: TProc<TForm>): Boolean;
var
  Dialog: TAtlasExportDialog;
begin
  Dialog := TAtlasExportDialog.CreateDialog(nil, ACatalog, AOptions.Secrets);
  try
    if Assigned(APrepare) then
      APrepare(Dialog);
    Result := Dialog.ShowModal = mrOk;
    if Result then
      AOptions := Dialog.Options;
  finally
    Dialog.Free;
  end;
end;

{ TAtlasImportDialog }

constructor TAtlasImportDialog.CreateDialog(AOwner: TComponent; ACatalog: TAtlasSettingsCatalog;
  const AFileName: string; const APreview: TAtlasImportPreview; const AOnPreview: TAtlasImportPreviewFunc);
var
  Buttons, Areas: TFlowPanel;
  Area: TAtlasCatalogArea;
  Box: TCheckBox;
  Info: string;
  Column: TListColumn;
begin
  inherited CreateNew(AOwner);
  FCatalog := ACatalog;
  FPreview := APreview;
  FOnPreview := AOnPreview;
  SetupForm(Self, TAtlasStrings.Fmt(TAtlasTextId.SettingsImportTitle, [ExtractFileName(AFileName)]), 760);

  Buttons := NewButtons(Self);
  FApply := NewButton(Self, Buttons, TAtlasStrings.Text(TAtlasTextId.SettingsImportApply));
  FApply.ModalResult := mrOk;
  FApply.Default := True;
  FCancel := NewButton(Self, Buttons, TAtlasStrings.Text(TAtlasTextId.SettingsDialogCancel));
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;
  FCount := TLabel.Create(Self);
  FCount.Parent := Buttons;
  FCount.AlignWithMargins := True;
  FCount.Margins.SetBounds(Gap, 4, 0, 0);

  // Name und Beschreibung (Profile), Hinweis auf eine neuere Version.
  Info := APreview.Source.Name;
  if English and (APreview.Source.NameEn <> '') then
    Info := APreview.Source.NameEn;
  if English and (APreview.Source.DescriptionEn <> '') then
    Info := Trim(Info + sLineBreak + APreview.Source.DescriptionEn)
  else if APreview.Source.Description <> '' then
    Info := Trim(Info + sLineBreak + APreview.Source.Description);
  if APreview.Newer then
    Info := Trim(Info + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.SettingsImportNewer,
      [APreview.Source.AtlasVersion]));
  FInfo := TLabel.Create(Self);
  FInfo.Parent := Self;
  FInfo.Align := alTop;
  FInfo.AlignWithMargins := True;
  FInfo.Margins.SetBounds(Gap, Gap, Gap, 0);
  FInfo.WordWrap := True;
  FInfo.ShowAccelChar := False;
  FInfo.Caption := Info;
  FInfo.Visible := Info <> '';

  FMode := TRadioGroup.Create(Self);
  FMode.Parent := Self;
  FMode.Align := alTop;
  FMode.AlignWithMargins := True;
  FMode.Margins.SetBounds(Gap, Gap, Gap, 0);
  FMode.Top := 1000;
  FMode.Height := ScaleValue(64);
  FMode.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsImportMerge));
  FMode.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsImportReplace));
  FMode.ItemIndex := Ord(APreview.Mode);
  FMode.OnClick := Recalculate;

  Areas := TFlowPanel.Create(Self);
  Areas.Parent := Self;
  Areas.Align := alTop;
  Areas.AutoSize := True;
  Areas.BevelOuter := bvNone;
  Areas.AlignWithMargins := True;
  Areas.Margins.SetBounds(Gap, 4, Gap, 0);
  Areas.Top := 2000;
  for Area in ACatalog.Areas do
  begin
    Box := TCheckBox.Create(Self);
    Box.Parent := Areas;
    Box.Width := ScaleValue(140);
    Box.Caption := ACatalog.AreaCaption(Area.Id, English);
    Box.Checked := HasArea(APreview.Areas, Area.Id);
    Box.OnClick := Recalculate;
    FAreaBoxes := FAreaBoxes + [Box];
    FAreaIds := FAreaIds + [Area.Id];
  end;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(Gap, Gap, Gap, 0);
  FList.ViewStyle := vsReport;
  FList.Checkboxes := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.OnClick := ListChanged;
  FList.OnKeyUp := ListKeyUp;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsImportColKey);
  Column.Width := ScaleValue(220);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsImportColArea);
  Column.Width := ScaleValue(100);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsImportColCurrent);
  Column.Width := ScaleValue(110);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsImportColNew);
  Column.Width := ScaleValue(110);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsImportColNote);
  Column.Width := ScaleValue(180);

  ClientHeight := ScaleValue(520);
end;

procedure TAtlasImportDialog.DoShow;
begin
  inherited;
  if not FFilled then
    Fill;
end;

function TAtlasImportDialog.ValueText(const AItem: TAtlasImportItem; const AJson: string): string;
var
  Value: Integer;
begin
  if AJson = '' then
    Exit(TAtlasStrings.Text(TAtlasTextId.SettingsImportDefault));
  Result := TAtlasJsonValues.Display(AJson);
  // Tastenkürzel wie im Menü.
  if (AItem.Entry >= 0) and (FCatalog[AItem.Entry].Format = 'shortcut') and TryStrToInt(Result, Value) then
  begin
    Result := ShortCutToText(TShortCut(Value));
    if Result = '' then
      Result := '–';
  end;
end;

function TAtlasImportDialog.NoteText(const AItem: TAtlasImportItem): string;
begin
  case AItem.Status of
    isSame:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsImportSame);
    isReset:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsImportReset);
    isUnknown:
      if FPreview.Newer then
        Result := TAtlasStrings.Text(TAtlasTextId.SettingsImportUnknownNewer)
      else
        Result := TAtlasStrings.Text(TAtlasTextId.SettingsImportUnknown);
    isInvalid:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsImportInvalid, [string.Join('; ', AItem.Issues)]);
    isSecret:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsImportSecret);
    isSkipped:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsImportSkipped);
  else
    Result := '';
  end;
  if AItem.Migrated then
    Result := Trim(Result + ' ' + TAtlasStrings.Fmt(TAtlasTextId.SettingsImportMigrated, [AItem.SourceKey]));
  if AItem.Covered <> '' then
    Result := Trim(Result + ' ' + TAtlasStrings.Fmt(TAtlasTextId.SettingsImportCovered, [AItem.Covered]));
end;

procedure TAtlasImportDialog.Fill;
var
  Index: Integer;
  Item: TAtlasImportItem;
  Row: TListItem;
  Area: string;
begin
  FFilled := True;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for Index := 0 to High(FPreview.Items) do
    begin
      Item := FPreview.Items[Index];
      Row := FList.Items.Add;
      Row.Caption := Item.Key;
      Area := '';
      if Item.Area <> '' then
        Area := FCatalog.AreaCaption(Item.Area, English);
      Row.SubItems.Add(Area);
      Row.SubItems.Add(ValueText(Item, Item.CurrentJson));
      if Item.Selectable then
        Row.SubItems.Add(ValueText(Item, Item.NewJson))
      else
        Row.SubItems.Add(TAtlasJsonValues.Display(Item.NewJson));
      Row.SubItems.Add(NoteText(Item));
      Row.Data := Pointer(NativeInt(Index));
      Row.Checked := Item.Selected and Item.Selectable;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  SyncChecks;
end;

procedure TAtlasImportDialog.SyncChecks;
var
  Row: TListItem;
  Index, Selected, Selectable: Integer;
begin
  Selected := 0;
  Selectable := 0;
  for Row in FList.Items do
  begin
    Index := NativeInt(Row.Data);
    if (Index < 0) or (Index > High(FPreview.Items)) then
      Continue;
    // Übersprungene Einträge lassen sich nicht wählen.
    if not FPreview.Items[Index].Selectable then
    begin
      if Row.Checked then
        Row.Checked := False;
      Continue;
    end;
    Inc(Selectable);
    FPreview.Items[Index].Selected := Row.Checked;
    if Row.Checked then
      Inc(Selected);
  end;
  FCount.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsImportCount, [Selected, Selectable]);
  FApply.Enabled := Selected > 0;
end;

procedure TAtlasImportDialog.ListChanged(Sender: TObject);
begin
  SyncChecks;
end;

procedure TAtlasImportDialog.ListKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  SyncChecks;
end;

procedure TAtlasImportDialog.Recalculate(Sender: TObject);
var
  Areas: TArray<string>;
  Index: Integer;
  Mode: TAtlasImportMode;
begin
  if not Assigned(FOnPreview) then
    Exit;
  Areas := nil;
  for Index := 0 to High(FAreaBoxes) do
    if FAreaBoxes[Index].Checked then
      Areas := Areas + [FAreaIds[Index]];
  Mode := imMerge;
  if FMode.ItemIndex = 1 then
    Mode := imReplace;
  // Keine Bereiche gewählt: leere Vorschau statt „alle“.
  if Length(Areas) = 0 then
  begin
    FPreview.Items := nil;
    FPreview.Areas := nil;
    FPreview.Mode := Mode;
  end
  else
    FPreview := FOnPreview(Mode, Areas);
  if HandleAllocated then
    Fill;
end;

function TAtlasImportDialog.Result_: TAtlasImportPreview;
begin
  if FFilled then
    SyncChecks;
  Result := FPreview;
end;

class function TAtlasImportDialog.Execute(ACatalog: TAtlasSettingsCatalog; const AFileName: string;
  var APreview: TAtlasImportPreview; const AOnPreview: TAtlasImportPreviewFunc; const APrepare: TProc<TForm>): Boolean;
var
  Dialog: TAtlasImportDialog;
begin
  Dialog := TAtlasImportDialog.CreateDialog(nil, ACatalog, AFileName, APreview, AOnPreview);
  try
    if Assigned(APrepare) then
      APrepare(Dialog);
    Result := Dialog.ShowModal = mrOk;
    if Result then
      APreview := Dialog.Result_;
  finally
    Dialog.Free;
  end;
end;

{ TAtlasProfileDialog }

constructor TAtlasProfileDialog.CreateDialog(AOwner: TComponent; const ANames, ADescriptions: TArray<string>);
var
  Buttons: TFlowPanel;
begin
  inherited CreateNew(AOwner);
  SetupForm(Self, TAtlasStrings.Text(TAtlasTextId.SettingsProfileTitle), 420);
  FDescriptions := ADescriptions;
  Buttons := NewButtons(Self);
  FLoad := NewButton(Self, Buttons, TAtlasStrings.Text(TAtlasTextId.SettingsImportButton));
  FLoad.ModalResult := mrOk;
  FLoad.Default := True;
  FCancel := NewButton(Self, Buttons, TAtlasStrings.Text(TAtlasTextId.SettingsDialogCancel));
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;
  FDescription := TLabel.Create(Self);
  FDescription.Parent := Self;
  FDescription.Align := alBottom;
  FDescription.AlignWithMargins := True;
  FDescription.Margins.SetBounds(Gap, Gap, Gap, 0);
  FDescription.WordWrap := True;
  FDescription.ShowAccelChar := False;
  FDescription.AutoSize := False;
  FDescription.Height := ScaleValue(48);
  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(Gap, Gap, Gap, 0);
  FList.OnClick := ListClick;
  FList.OnDblClick := ListDblClick;
  ClientHeight := ScaleValue(240);
  // Einträge erst mit Fenster (DoShow); die Namen bis dahin merken.
  FNames := ANames;
end;

procedure TAtlasProfileDialog.ListDblClick(Sender: TObject);
begin
  if FList.ItemIndex >= 0 then
    ModalResult := mrOk;
end;

procedure TAtlasProfileDialog.DoShow;
var
  Name: string;
begin
  inherited;
  if FList.Items.Count = 0 then
  begin
    for Name in FNames do
      FList.Items.Add(Name);
    if FList.Items.Count > 0 then
      FList.ItemIndex := 0;
    ListClick(nil);
  end;
end;

procedure TAtlasProfileDialog.ListClick(Sender: TObject);
begin
  FDescription.Caption := '';
  if (FList.ItemIndex >= 0) and (FList.ItemIndex <= High(FDescriptions)) then
    FDescription.Caption := FDescriptions[FList.ItemIndex];
  FLoad.Enabled := FList.ItemIndex >= 0;
end;

class function TAtlasProfileDialog.Choose(const ANames, ADescriptions: TArray<string>; out AIndex: Integer;
  const APrepare: TProc<TForm>): Boolean;
var
  Dialog: TAtlasProfileDialog;
begin
  AIndex := -1;
  Dialog := TAtlasProfileDialog.CreateDialog(nil, ANames, ADescriptions);
  try
    if Assigned(APrepare) then
      APrepare(Dialog);
    Result := (Dialog.ShowModal = mrOk) and (Dialog.List.ItemIndex >= 0);
    if Result then
      AIndex := Dialog.List.ItemIndex;
  finally
    Dialog.Free;
  end;
end;

end.
