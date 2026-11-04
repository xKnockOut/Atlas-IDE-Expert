unit Atlas.UI.Settings.Page.Transfer;

// Übertragen der Einstellungen (#723): Export, Import, Profile, Zurücksetzen; Leiste unten über die ganze Seite.

interface

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Import (#723): AProfile True = erst ein eingebautes Profil wählen. True, wenn AResult gilt (die
  /// IDE hat schon gespeichert).</summary>
  TAtlasSettingsImportEvent = reference to function(const ACurrent: TAtlasPluginSettings; AProfile: Boolean;
    out AResult: TAtlasPluginSettings): Boolean;
  /// <summary>„Alles zurücksetzen“ (#723) mit Rückfrage; True, wenn AResult gilt.</summary>
  TAtlasSettingsResetEvent = reference to function(const ACurrent: TAtlasPluginSettings;
    out AResult: TAtlasPluginSettings): Boolean;

type
  /// <summary>Übertragen der Einstellungen (#723): Export, Import, Profile, Zurücksetzen; Leiste unten über die ganze
  /// Seite.</summary>
  TAtlasSettingsTransferPart = class(TAtlasSettingsPagePart)
  private
    // Einstellungen übertragen (#723): Schalter, Knöpfe unten, Punkte an geänderten Werten.
    FSettingsExportImport: TCheckBox;
    FSettingsMarkModified: TCheckBox;
    FSettingsExportSecrets: TAtlasChoiceBox;
    FTransferBar: TWinControl;
    FExportButton: TButton;
    FImportButton: TButton;
    FProfileButton: TButton;
    FResetPageButton: TButton;
    FResetAllButton: TButton;
    FOnExportSettings: TProc<TAtlasPluginSettings>;
    FOnImportSettings: TAtlasSettingsImportEvent;
    FOnResetAllSettings: TAtlasSettingsResetEvent;
    procedure AddTransferSection;
    procedure ResetPageClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
    procedure ProfileClick(Sender: TObject);
    procedure ResetAllClick(Sender: TObject);
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    procedure ShowModified;
    /// <summary>„Exportieren…“ mit den Werten der Seite (#723).</summary>
    property OnExportSettings: TProc<TAtlasPluginSettings> read FOnExportSettings write FOnExportSettings;
    /// <summary>„Importieren…“ und „Profil laden…“ (#723).</summary>
    property OnImportSettings: TAtlasSettingsImportEvent read FOnImportSettings write FOnImportSettings;
    /// <summary>„Alles zurücksetzen…“ (#723).</summary>
    property OnResetAllSettings: TAtlasSettingsResetEvent read FOnResetAllSettings write FOnResetAllSettings;
    property TransferBar: TWinControl read FTransferBar;
    property SettingsExportImportCheck: TCheckBox read FSettingsExportImport;
    property SettingsMarkModifiedCheck: TCheckBox read FSettingsMarkModified;
    property SettingsExportSecretsChoice: TAtlasChoiceBox read FSettingsExportSecrets;
    property ExportButton: TButton read FExportButton;
    property ImportButton: TButton read FImportButton;
    property ResetPageButton: TButton read FResetPageButton;
    property ResetAllButton: TButton read FResetAllButton;
  end;

implementation

uses
  System.Classes,
  Atlas.UI.Settings.Page.Sheets,
  Atlas.UI.Strings,
  Atlas.Core.Settings.Transfer;

{ TAtlasSettingsTransferPart }

procedure TAtlasSettingsTransferPart.Build;
begin
  // Einstellungen exportieren, importieren und zurücksetzen (#723).
  AddTransferSection;
end;

procedure TAtlasSettingsTransferPart.AddTransferSection;
const
  BarHeight = 66;
  ButtonHeight = 25;
  Row2 = 34;

  function AddButton(const ACaption: string; ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(FPage);
    Result.Parent := FTransferBar;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, AWidth, ButtonHeight);
    Result.OnClick := AClick;
  end;

begin
  AddTitle(TAtlasTextId.SettingsTransferTitle);
  FSettingsExportImport := BindCheck('SettingsExportImport', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExportImport)));
  FSettingsMarkModified := BindCheck('SettingsMarkModified', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMarkModified)));
  BindCheck('SettingsBackupBeforeImport', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBackupBeforeImport)));
  FSettingsExportSecrets := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsExportSecrets),
    [TAtlasStrings.Text(TAtlasTextId.SettingsExportSecretsOmit),
    TAtlasStrings.Text(TAtlasTextId.SettingsExportSecretsPlaceholder)]);
  // Knöpfe unten über die ganze Seite; ohne settings.exportImport ausgeblendet (RefreshMarks).
  FTransferBar := TAtlasSettingsRow.Create(FPage);
  FTransferBar.Parent := FPage;
  FTransferBar.Align := alBottom;
  FTransferBar.AlignWithMargins := True;
  FTransferBar.Height := BarHeight;
  FExportButton := AddButton(TAtlasStrings.Text(TAtlasTextId.SettingsExportButton), 0, 4, 120, ExportClick);
  FImportButton := AddButton(TAtlasStrings.Text(TAtlasTextId.SettingsImportButton), 126, 4, 120, ImportClick);
  FProfileButton := AddButton(TAtlasStrings.Text(TAtlasTextId.SettingsProfileButton), 252, 4, 120, ProfileClick);
  FResetPageButton := AddButton(TAtlasStrings.Text(TAtlasTextId.SettingsResetPageButton), 0, Row2, 150,
    ResetPageClick);
  FResetAllButton := AddButton(TAtlasStrings.Text(TAtlasTextId.SettingsResetAllButton), 156, Row2, 150,
    ResetAllClick);
end;

procedure TAtlasSettingsTransferPart.BindMarks;
begin
  FPage.Marks.Bind(FSettingsExportSecrets, ['SettingsExportSecrets']);
end;

procedure TAtlasSettingsTransferPart.ShowModified;
var
  Modified: TArray<string>;
begin
  FTransferBar.Visible := FSettingsExportImport.Checked;
  Modified := nil;
  if FSettingsMarkModified.Checked then
  begin
    Modified := TAtlasSettingsTransfer.ModifiedNames(FPage.Catalog, FPage.CurrentSettings);
  end;
  FPage.Marks.Show(Modified, FSettingsMarkModified.Checked);
end;

procedure TAtlasSettingsTransferPart.ResetPageClick(Sender: TObject);
begin
  FPage.ResetPage;
end;

procedure TAtlasSettingsTransferPart.ExportClick(Sender: TObject);
begin
  if Assigned(FOnExportSettings) then
  begin
    FOnExportSettings(FPage.CurrentSettings);
  end;
end;

procedure TAtlasSettingsTransferPart.ImportClick(Sender: TObject);
var
  Imported: TAtlasPluginSettings;
begin
  if Assigned(FOnImportSettings) and FOnImportSettings(FPage.CurrentSettings, False, Imported) then
  begin
    FPage.LoadFrom(Imported);
  end;
end;

procedure TAtlasSettingsTransferPart.ProfileClick(Sender: TObject);
var
  Imported: TAtlasPluginSettings;
begin
  if Assigned(FOnImportSettings) and FOnImportSettings(FPage.CurrentSettings, True, Imported) then
  begin
    FPage.LoadFrom(Imported);
  end;
end;

procedure TAtlasSettingsTransferPart.ResetAllClick(Sender: TObject);
var
  Reset: TAtlasPluginSettings;
begin
  if Assigned(FOnResetAllSettings) and FOnResetAllSettings(FPage.CurrentSettings, Reset) then
  begin
    FPage.LoadFrom(Reset);
  end;
end;

procedure TAtlasSettingsTransferPart.Load(const ASettings: TAtlasPluginSettings);
begin
  FSettingsExportSecrets.Choice := Ord(ASettings.SettingsExportSecrets = 'placeholder');
end;

procedure TAtlasSettingsTransferPart.Save(var ASettings: TAtlasPluginSettings);
begin
  ASettings.SettingsExportSecrets := 'omit';
  if FSettingsExportSecrets.Choice = 1 then
  begin
    ASettings.SettingsExportSecrets := 'placeholder';
  end;
end;

end.
