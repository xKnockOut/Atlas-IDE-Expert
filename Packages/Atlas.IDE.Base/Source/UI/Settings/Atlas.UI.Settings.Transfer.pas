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
  begin
    if SameText(Area, AArea) then
    begin
      Exit(True);
    end;
  end;
end;

function English: Boolean;
begin
  Result := TAtlasStrings.Language = TAtlasLanguage.English;
end;

/// <summary>Beschriftung oben im Dialog; ATop ordnet sie unter die vorigen.</summary>
function NewTopLabel(AOwner: TForm; const ACaption: string; ATop: Integer): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AOwner;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(Gap, Gap, Gap, 0);
  Result.Top := ATop;
  Result.Caption := ACaption;
end;

/// <summary>Hinweistext oben im Dialog: umgebrochen, ohne Tastenkürzel.</summary>
function NewInfoLabel(AOwner: TForm; const ACaption: string): TLabel;
begin
  Result := NewTopLabel(AOwner, ACaption, 0);
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
end;

/// <summary>Auswahl mit zwei Einträgen oben im Dialog.</summary>
function NewChoice(AOwner: TForm; const ACaption: string; ATop: Integer;
  const AItems: TArray<string>): TRadioGroup;
var
  mItem: string;
begin
  Result := TRadioGroup.Create(AOwner);
  Result.Parent := AOwner;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(Gap, Gap, Gap, 0);
  Result.Top := ATop;
  Result.Height := AOwner.ScaleValue(64);
  Result.Caption := ACaption;
  Result.Items.BeginUpdate;
  try
    for mItem in AItems do
    begin
      Result.Items.Add(mItem);
    end;
  finally
    Result.Items.EndUpdate;
  end;
end;

/// <summary>Kontrollkästchen je Bereich des Katalogs in einer Leiste oben im Dialog; angekreuzt sind alle (AAll)
/// oder die in AChecked. AIds bekommt die Bereiche in derselben Reihenfolge.</summary>
function NewAreaBoxes(AOwner: TForm; ACatalog: TAtlasSettingsCatalog; const AChecked: TArray<string>;
  AAll: Boolean; const AOnClick: TNotifyEvent; out AIds: TArray<string>): TArray<TCheckBox>;
var
  mPanel: TFlowPanel;
  mArea: TAtlasCatalogArea;
  mBox: TCheckBox;
begin
  Result := nil;
  AIds := nil;
  mPanel := TFlowPanel.Create(AOwner);
  mPanel.Parent := AOwner;
  mPanel.Align := alTop;
  mPanel.AutoSize := True;
  mPanel.BevelOuter := bvNone;
  mPanel.AlignWithMargins := True;
  mPanel.Margins.SetBounds(Gap, 4, Gap, 0);
  mPanel.Top := 2000;
  for mArea in ACatalog.Areas do
  begin
    mBox := TCheckBox.Create(AOwner);
    mBox.Parent := mPanel;
    mBox.Width := AOwner.ScaleValue(140);
    mBox.Caption := ACatalog.AreaCaption(mArea.Id, English);
    mBox.Checked := AAll or HasArea(AChecked, mArea.Id);
    mBox.OnClick := AOnClick;
    Result := Result + [mBox];
    AIds := AIds + [mArea.Id];
  end;
end;

/// <summary>Knopf ADefault („Speichern…“, „Übernehmen“) und „Abbrechen“ unten im Dialog; ACancel bekommt den
/// zweiten Knopf, Ergebnis ist die Leiste.</summary>
function NewDialogButtons(AOwner: TForm; const ACaption: string; out ADefault, ACancel: TButton): TFlowPanel;
begin
  Result := NewButtons(AOwner);
  ADefault := NewButton(AOwner, Result, ACaption);
  ADefault.ModalResult := mrOk;
  ADefault.Default := True;
  ACancel := NewButton(AOwner, Result, TAtlasStrings.Text(TAtlasTextId.SettingsDialogCancel));
  ACancel.ModalResult := mrCancel;
  ACancel.Cancel := True;
end;

/// <summary>Name und Beschreibung der Datei (Profile) in der Sprache der Oberfläche, Hinweis auf eine neuere
/// Version.</summary>
function ImportInfo(const APreview: TAtlasImportPreview): string;
begin
  Result := APreview.Source.Name;
  if English and (APreview.Source.NameEn <> '') then
  begin
    Result := APreview.Source.NameEn;
  end;
  if English and (APreview.Source.DescriptionEn <> '') then
  begin
    Result := Trim(Result + sLineBreak + APreview.Source.DescriptionEn);
  end
  else if APreview.Source.Description <> '' then
  begin
    Result := Trim(Result + sLineBreak + APreview.Source.Description);
  end;
  if APreview.Newer then
  begin
    Result := Trim(Result + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.SettingsImportNewer,
      [APreview.Source.AtlasVersion]));
  end;
end;

/// <summary>Spalte ACaption mit der (schon skalierten) Breite AWidth an AList anhängen.</summary>
procedure AddColumn(AList: TListView; const ACaption: string; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := ACaption;
  mColumn.Width := AWidth;
end;

{ TAtlasExportDialog }

constructor TAtlasExportDialog.CreateDialog(AOwner: TComponent; ACatalog: TAtlasSettingsCatalog;
  ASecrets: TAtlasSecretMode);
var
  mTitle: TLabel;
begin
  inherited CreateNew(AOwner);
  SetupForm(Self, TAtlasStrings.Text(TAtlasTextId.SettingsExportTitle), 460);
  NewDialogButtons(Self, TAtlasStrings.Text(TAtlasTextId.SettingsExportSave), FSave, FCancel);
  NewInfoLabel(Self, TAtlasStrings.Text(TAtlasTextId.SettingsExportInfo));
  mTitle := NewTopLabel(Self, TAtlasStrings.Text(TAtlasTextId.SettingsExportAreas), 1000);
  mTitle.Font.Style := [fsBold];
  FAreas := NewAreaBoxes(Self, ACatalog, nil, True, AreaClick, FAreaIds);
  FSecrets := NewChoice(Self, TAtlasStrings.Text(TAtlasTextId.SettingsExportSecrets), 3000,
    [TAtlasStrings.Text(TAtlasTextId.SettingsExportSecretsOmit),
    TAtlasStrings.Text(TAtlasTextId.SettingsExportSecretsPlaceholder)]);
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
  begin
    if Box.Checked then
    begin
      FSave.Enabled := True;
    end;
  end;
end;

function TAtlasExportDialog.Options: TAtlasExportOptions;
var
  Index: Integer;
  Areas: TArray<string>;
  mSecrets: TAtlasSecretMode;
begin
  Areas := nil;
  for Index := 0 to High(FAreas) do
  begin
    if FAreas[Index].Checked then
    begin
      Areas := Areas + [FAreaIds[Index]];
    end;
  end;
  mSecrets := smOmit;
  if FSecrets.ItemIndex = 1 then
  begin
    mSecrets := smPlaceholder;
  end;
  Result := TAtlasExportOptions.Create(Areas, mSecrets);
end;

class function TAtlasExportDialog.Execute(ACatalog: TAtlasSettingsCatalog; var AOptions: TAtlasExportOptions;
  const APrepare: TProc<TForm>): Boolean;
var
  Dialog: TAtlasExportDialog;
begin
  Dialog := TAtlasExportDialog.CreateDialog(nil, ACatalog, AOptions.Secrets);
  try
    if Assigned(APrepare) then
    begin
      APrepare(Dialog);
    end;
    Result := Dialog.ShowModal = mrOk;
    if Result then
    begin
      AOptions := Dialog.Options;
    end;
  finally
    Dialog.Free;
  end;
end;

{ TAtlasImportDialog }

constructor TAtlasImportDialog.CreateDialog(AOwner: TComponent; ACatalog: TAtlasSettingsCatalog;
  const AFileName: string; const APreview: TAtlasImportPreview; const AOnPreview: TAtlasImportPreviewFunc);
var
  mButtons: TFlowPanel;
begin
  inherited CreateNew(AOwner);
  FCatalog := ACatalog;
  FPreview := APreview;
  FOnPreview := AOnPreview;
  SetupForm(Self, TAtlasStrings.Fmt(TAtlasTextId.SettingsImportTitle, [ExtractFileName(AFileName)]), 760);
  mButtons := NewDialogButtons(Self, TAtlasStrings.Text(TAtlasTextId.SettingsImportApply), FApply, FCancel);
  FCount := TLabel.Create(Self);
  FCount.Parent := mButtons;
  FCount.AlignWithMargins := True;
  FCount.Margins.SetBounds(Gap, 4, 0, 0);
  FInfo := NewInfoLabel(Self, ImportInfo(APreview));
  FInfo.Visible := FInfo.Caption <> '';
  FMode := NewChoice(Self, '', 1000, [TAtlasStrings.Text(TAtlasTextId.SettingsImportMerge),
    TAtlasStrings.Text(TAtlasTextId.SettingsImportReplace)]);
  FMode.ItemIndex := Ord(APreview.Mode);
  FMode.OnClick := Recalculate;
  FAreaBoxes := NewAreaBoxes(Self, ACatalog, APreview.Areas, False, Recalculate, FAreaIds);
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
  AddColumn(FList, TAtlasStrings.Text(TAtlasTextId.SettingsImportColKey), ScaleValue(220));
  AddColumn(FList, TAtlasStrings.Text(TAtlasTextId.SettingsImportColArea), ScaleValue(100));
  AddColumn(FList, TAtlasStrings.Text(TAtlasTextId.SettingsImportColCurrent), ScaleValue(110));
  AddColumn(FList, TAtlasStrings.Text(TAtlasTextId.SettingsImportColNew), ScaleValue(110));
  AddColumn(FList, TAtlasStrings.Text(TAtlasTextId.SettingsImportColNote), ScaleValue(180));

  ClientHeight := ScaleValue(520);
end;

procedure TAtlasImportDialog.DoShow;
begin
  inherited;
  if not FFilled then
  begin
    Fill;
  end;
end;

function TAtlasImportDialog.ValueText(const AItem: TAtlasImportItem; const AJson: string): string;
var
  Value: Integer;
begin
  if AJson = '' then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.SettingsImportDefault));
  end;
  Result := TAtlasJsonValues.Display(AJson);
  // Tastenkürzel wie im Menü.
  if (AItem.Entry >= 0) and (FCatalog[AItem.Entry].Format = 'shortcut') and TryStrToInt(Result, Value) then
  begin
    Result := ShortCutToText(TShortCut(Value));
    if Result = '' then
    begin
      Result := '–';
    end;
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
      begin
        Result := TAtlasStrings.Text(TAtlasTextId.SettingsImportUnknownNewer);
      end
      else
      begin
        Result := TAtlasStrings.Text(TAtlasTextId.SettingsImportUnknown);
      end;
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
  begin
    Result := Trim(Result + ' ' + TAtlasStrings.Fmt(TAtlasTextId.SettingsImportMigrated, [AItem.SourceKey]));
  end;
  if AItem.Covered <> '' then
  begin
    Result := Trim(Result + ' ' + TAtlasStrings.Fmt(TAtlasTextId.SettingsImportCovered, [AItem.Covered]));
  end;
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
      begin
        Area := FCatalog.AreaCaption(Item.Area, English);
      end;
      Row.SubItems.Add(Area);
      Row.SubItems.Add(ValueText(Item, Item.CurrentJson));
      if Item.Selectable then
      begin
        Row.SubItems.Add(ValueText(Item, Item.NewJson));
      end
      else
      begin
        Row.SubItems.Add(TAtlasJsonValues.Display(Item.NewJson));
      end;
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
    begin
      Continue;
    end;
    // Übersprungene Einträge lassen sich nicht wählen.
    if not FPreview.Items[Index].Selectable then
    begin
      if Row.Checked then
      begin
        Row.Checked := False;
      end;
      Continue;
    end;
    Inc(Selectable);
    FPreview.Items[Index].Selected := Row.Checked;
    if Row.Checked then
    begin
      Inc(Selected);
    end;
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
  mMode: TAtlasImportMode;
begin
  if not Assigned(FOnPreview) then
  begin
    Exit;
  end;
  Areas := nil;
  for Index := 0 to High(FAreaBoxes) do
  begin
    if FAreaBoxes[Index].Checked then
    begin
      Areas := Areas + [FAreaIds[Index]];
    end;
  end;
  mMode := imMerge;
  if FMode.ItemIndex = 1 then
  begin
    mMode := imReplace;
  end;
  // Keine Bereiche gewählt: leere Vorschau statt „alle“.
  if Length(Areas) = 0 then
  begin
    FPreview.Items := nil;
    FPreview.Areas := nil;
    FPreview.Mode := mMode;
  end
  else
  begin
    FPreview := FOnPreview(mMode, Areas);
  end;
  if HandleAllocated then
  begin
    Fill;
  end;
end;

function TAtlasImportDialog.Result_: TAtlasImportPreview;
begin
  if FFilled then
  begin
    SyncChecks;
  end;
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
    begin
      APrepare(Dialog);
    end;
    Result := Dialog.ShowModal = mrOk;
    if Result then
    begin
      APreview := Dialog.Result_;
    end;
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
  begin
    ModalResult := mrOk;
  end;
end;

procedure TAtlasProfileDialog.DoShow;
var
  mName: string;
begin
  inherited;
  if FList.Items.Count = 0 then
  begin
    for mName in FNames do
    begin
      FList.Items.Add(mName);
    end;
    if FList.Items.Count > 0 then
    begin
      FList.ItemIndex := 0;
    end;
    ListClick(nil);
  end;
end;

procedure TAtlasProfileDialog.ListClick(Sender: TObject);
begin
  FDescription.Caption := '';
  if (FList.ItemIndex >= 0) and (FList.ItemIndex <= High(FDescriptions)) then
  begin
    FDescription.Caption := FDescriptions[FList.ItemIndex];
  end;
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
    begin
      APrepare(Dialog);
    end;
    Result := (Dialog.ShowModal = mrOk) and (Dialog.List.ItemIndex >= 0);
    if Result then
    begin
      AIndex := Dialog.List.ItemIndex;
    end;
  finally
    Dialog.Free;
  end;
end;

end.
