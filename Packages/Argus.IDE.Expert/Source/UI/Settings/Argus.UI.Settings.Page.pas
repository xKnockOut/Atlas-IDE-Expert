unit Argus.UI.Settings.Page;

// Seite „Argus“ unter Tools › Optionen › Drittanbieter (#227, Teil
// Vervollständigung). Reine VCL, im Code aufgebaut: Steuerelemente
// untereinander, die IDE skaliert sie mit dem Dialog. Die DFM ist leer;
// TCustomFrame.Create verlangt für abgeleitete Frames eine Ressource. Laden und Speichern über
// TArgusPluginSettings; die IDE-Schicht liest und schreibt die Registry.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Dialogs,
  Argus.Core.Settings.Plugin,
  Argus.Core.Diagnostics.Hangs,
  Argus.UI.Strings;

type
  TArgusSettingsPage = class(TFrame)
  private
    FEnabled: TCheckBox;
    FServerPath: TEdit;
    FServerBrowse: TButton;
    FServerStatus: TLabel;
    FDefaultServerPath: string;
    FRowsLabel: TLabel;
    FRows: TEdit;
    FRowsUpDown: TUpDown;
    FPanelCollapsed: TCheckBox;
    FAutoParentheses: TCheckBox;
    FFilterChips: TCheckBox;
    FLearning: TCheckBox;
    FGroupInherited: TCheckBox;
    FPreview: TCheckBox;
    FHoverTooltip: TCheckBox;
    FHangThreshold: TEdit;
    FHangHint: TCheckBox;
    FReloadExternal: TCheckBox;
    FPairColors: TCheckBox;
    FPairGuides: TCheckBox;
    FProblems: TCheckBox;
    FCheckOnSave: TCheckBox;
    FCheckDelay: TEdit;
    FCheckMax: TEdit;
    FResetHistory: TButton;
    FResetWidths: TButton;
    FHangTest: TButton;
    FWidths: TArgusPluginSettings;
    FNextTop: Integer;
    FOnResetHistory: TProc;
    function AddCheck(const ACaption: string): TCheckBox;
    function AddPanel(AHeight: Integer): TPanel;
    function AddNumber(const ACaption: string): TEdit;
    procedure ResetHistoryClick(Sender: TObject);
    procedure ResetWidthsClick(Sender: TObject);
    procedure HangTestClick(Sender: TObject);
    procedure ServerBrowseClick(Sender: TObject);
    procedure ServerPathChange(Sender: TObject);
    procedure SetDefaultServerPath(const AValue: string);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFrom(const ASettings: TArgusPluginSettings);
    procedure SaveTo(var ASettings: TArgusPluginSettings);
    /// <summary>„Verlauf zurücksetzen“ der lernenden Gewichtung (#418).</summary>
    property OnResetHistory: TProc read FOnResetHistory write FOnResetHistory;
    /// <summary>Server, der bei leerem Pfad gilt (für die Anzeige „Verwendet: …“).</summary>
    property DefaultServerPath: string read FDefaultServerPath write SetDefaultServerPath;
  end;

implementation

{$R *.dfm}

{ TArgusSettingsPage }

constructor TArgusSettingsPage.Create(AOwner: TComponent);
var
  Panel: TPanel;
  Title: TLabel;
begin
  inherited Create(AOwner);
  Name := 'ArgusSettingsPage';
  Width := 480;
  Height := 660;
  Title := TLabel.Create(Self);
  Title.Parent := Self;
  Title.Align := alTop;
  Title.AlignWithMargins := True;
  Title.Caption := TArgusStrings.Text(TArgusTextId.SettingsTitle);
  Title.Font.Style := [fsBold];
  FNextTop := 100;
  FEnabled := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsEnabled));
  // Wo der Server liegt; leer gilt der Standard neben dem Plugin.
  Panel := AddPanel(26);
  Title := TLabel.Create(Self);
  Title.Parent := Panel;
  Title.Caption := TArgusStrings.Text(TArgusTextId.SettingsServerPath);
  Title.Left := 0;
  Title.Top := 5;
  FServerPath := TEdit.Create(Self);
  FServerPath.Parent := Panel;
  FServerPath.Left := 180;
  FServerPath.Top := 1;
  FServerPath.Width := 250;
  FServerPath.Anchors := [akLeft, akTop, akRight];
  FServerPath.OnChange := ServerPathChange;
  FServerBrowse := TButton.Create(Self);
  FServerBrowse.Parent := Panel;
  FServerBrowse.Caption := '…';
  FServerBrowse.Left := 436;
  FServerBrowse.Top := 0;
  FServerBrowse.Width := 30;
  FServerBrowse.Anchors := [akTop, akRight];
  FServerBrowse.OnClick := ServerBrowseClick;
  Panel := AddPanel(18);
  FServerStatus := TLabel.Create(Self);
  FServerStatus.Parent := Panel;
  FServerStatus.Left := 180;
  FServerStatus.Top := 0;
  FServerStatus.Font.Color := clGrayText;
  Panel := AddPanel(26);
  FRowsLabel := TLabel.Create(Self);
  FRowsLabel.Parent := Panel;
  FRowsLabel.Caption := TArgusStrings.Text(TArgusTextId.SettingsRows);
  FRowsLabel.Left := 0;
  FRowsLabel.Top := 5;
  FRows := TEdit.Create(Self);
  FRows.Parent := Panel;
  FRows.Left := 180;
  FRows.Top := 1;
  FRows.Width := 44;
  FRows.NumbersOnly := True;
  FRowsUpDown := TUpDown.Create(Self);
  FRowsUpDown.Parent := Panel;
  FRowsUpDown.Associate := FRows;
  FRowsUpDown.Min := TArgusPluginSettings.MinVisibleRows;
  FRowsUpDown.Max := TArgusPluginSettings.MaxVisibleRows;
  FPanelCollapsed := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsPanelCollapsed));
  FAutoParentheses := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsParentheses));
  FFilterChips := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsChips));
  FLearning := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsLearning));
  FGroupInherited := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsGroupInherited));
  FPreview := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsPreview));
  FHoverTooltip := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsHover));
  // Einfrier-Wächter (#501).
  FHangThreshold := AddNumber(TArgusStrings.Text(TArgusTextId.SettingsHangThreshold));
  FHangHint := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsHangHint));
  FReloadExternal := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsReload));
  FPairColors := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsPairs));
  FPairGuides := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsPairGuides));
  FProblems := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsProblems));
  // Compilerprüfung nach dem Speichern (#548).
  FCheckOnSave := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsCheckOnSave));
  FCheckDelay := AddNumber(TArgusStrings.Text(TArgusTextId.SettingsCheckDelay));
  FCheckMax := AddNumber(TArgusStrings.Text(TArgusTextId.SettingsCheckMax));
  Panel := AddPanel(32);
  FResetHistory := TButton.Create(Self);
  FResetHistory.Parent := Panel;
  FResetHistory.Caption := TArgusStrings.Text(TArgusTextId.SettingsResetHistory);
  FResetHistory.Left := 0;
  FResetHistory.Top := 3;
  FResetHistory.Width := 150;
  FResetHistory.OnClick := ResetHistoryClick;
  FResetWidths := TButton.Create(Self);
  FResetWidths.Parent := Panel;
  FResetWidths.Caption := TArgusStrings.Text(TArgusTextId.SettingsResetWidths);
  FResetWidths.Left := 160;
  FResetWidths.Top := 3;
  FResetWidths.Width := 150;
  FResetWidths.OnClick := ResetWidthsClick;
  FHangTest := TButton.Create(Self);
  FHangTest.Parent := Panel;
  FHangTest.Caption := TArgusStrings.Text(TArgusTextId.SettingsHangTest);
  FHangTest.Left := 320;
  FHangTest.Top := 3;
  FHangTest.Width := 150;
  FHangTest.OnClick := HangTestClick;
end;

function TArgusSettingsPage.AddCheck(const ACaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Caption := ACaption;
  // alTop stapelt nach Top: jedes neue Element unter das vorige.
  Result.Top := FNextTop;
  Inc(FNextTop, 100);
end;

function TArgusSettingsPage.AddPanel(AHeight: Integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.BevelOuter := bvNone;
  Result.Height := AHeight;
  Result.Top := FNextTop;
  Inc(FNextTop, 100);
  Result.ParentBackground := True;
end;

function TArgusSettingsPage.AddNumber(const ACaption: string): TEdit;
var
  Panel: TPanel;
  Caption: TLabel;
begin
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := ACaption;
  Caption.Left := 0;
  Caption.Top := 5;
  Result := TEdit.Create(Self);
  Result.Parent := Panel;
  Result.Left := 180;
  Result.Top := 1;
  Result.Width := 60;
  Result.NumbersOnly := True;
end;

procedure TArgusSettingsPage.LoadFrom(const ASettings: TArgusPluginSettings);
begin
  FWidths := ASettings;
  FEnabled.Checked := ASettings.Enabled;
  FServerPath.Text := ASettings.ServerPath;
  ServerPathChange(nil);
  FRowsUpDown.Position := ASettings.VisibleRows;
  FPanelCollapsed.Checked := ASettings.PanelCollapsed;
  FAutoParentheses.Checked := ASettings.AutoParentheses;
  FFilterChips.Checked := ASettings.FilterChips;
  FLearning.Checked := ASettings.Learning;
  FGroupInherited.Checked := ASettings.GroupInherited;
  FPreview.Checked := ASettings.Preview;
  FHoverTooltip.Checked := ASettings.HoverTooltip;
  FHangThreshold.Text := IntToStr(ASettings.HangThresholdMs);
  FHangHint.Checked := ASettings.HangHint;
  FReloadExternal.Checked := ASettings.ReloadExternal;
  FPairColors.Checked := ASettings.PairColors;
  FPairGuides.Checked := ASettings.PairGuides;
  FProblems.Checked := ASettings.Problems;
  FCheckOnSave.Checked := ASettings.CheckOnSave;
  FCheckDelay.Text := IntToStr(ASettings.CheckOnSaveDelayMs);
  FCheckMax.Text := IntToStr(ASettings.CheckOnSaveMaxMs);
end;

procedure TArgusSettingsPage.SaveTo(var ASettings: TArgusPluginSettings);
begin
  ASettings.Enabled := FEnabled.Checked;
  ASettings.ServerPath := Trim(FServerPath.Text);
  ASettings.VisibleRows := FRowsUpDown.Position;
  ASettings.PanelCollapsed := FPanelCollapsed.Checked;
  ASettings.AutoParentheses := FAutoParentheses.Checked;
  ASettings.FilterChips := FFilterChips.Checked;
  ASettings.Learning := FLearning.Checked;
  ASettings.GroupInherited := FGroupInherited.Checked;
  ASettings.Preview := FPreview.Checked;
  ASettings.HoverTooltip := FHoverTooltip.Checked;
  ASettings.HangThresholdMs := StrToIntDef(FHangThreshold.Text, ASettings.HangThresholdMs);
  ASettings.HangHint := FHangHint.Checked;
  ASettings.ReloadExternal := FReloadExternal.Checked;
  ASettings.PairColors := FPairColors.Checked;
  ASettings.PairGuides := FPairGuides.Checked;
  ASettings.Problems := FProblems.Checked;
  ASettings.CheckOnSave := FCheckOnSave.Checked;
  ASettings.CheckOnSaveDelayMs := StrToIntDef(FCheckDelay.Text, ASettings.CheckOnSaveDelayMs);
  ASettings.CheckOnSaveMaxMs := StrToIntDef(FCheckMax.Text, ASettings.CheckOnSaveMaxMs);
  ASettings.ListWidth := FWidths.ListWidth;
  ASettings.PanelWidth := FWidths.PanelWidth;
  ASettings.Normalize;
end;

procedure TArgusSettingsPage.SetDefaultServerPath(const AValue: string);
begin
  FDefaultServerPath := AValue;
  ServerPathChange(nil);
end;

procedure TArgusSettingsPage.ServerPathChange(Sender: TObject);
var
  Path: string;
begin
  Path := Trim(FServerPath.Text);
  if Path = '' then
    Path := FDefaultServerPath;
  if Path = '' then
    FServerStatus.Caption := ''
  else if FileExists(Path) then
    FServerStatus.Caption := TArgusStrings.Fmt(TArgusTextId.SettingsServerFound, [Path])
  else
    FServerStatus.Caption := TArgusStrings.Fmt(TArgusTextId.SettingsServerMissing, [Path]);
end;

procedure TArgusSettingsPage.ServerBrowseClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Filter := TArgusStrings.Text(TArgusTextId.SettingsServerFilter);
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    if Trim(FServerPath.Text) <> '' then
      Dialog.FileName := Trim(FServerPath.Text)
    else if FDefaultServerPath <> '' then
      Dialog.InitialDir := ExtractFilePath(FDefaultServerPath);
    if Dialog.Execute then
      FServerPath.Text := Dialog.FileName;
  finally
    Dialog.Free;
  end;
end;

procedure TArgusSettingsPage.ResetHistoryClick(Sender: TObject);
begin
  if Assigned(FOnResetHistory) then
    FOnResetHistory();
  FResetHistory.Enabled := False;
end;

procedure TArgusSettingsPage.HangTestClick(Sender: TObject);
var
  Activity: IInterface;
begin
  // Künstlicher Hänger für den Einfrier-Wächter (#501): erscheint im Protokoll mit dieser Aktion.
  Activity := TArgusActivity.Scope('Wächter-Test');
  Sleep(1000);
end;

procedure TArgusSettingsPage.ResetWidthsClick(Sender: TObject);
begin
  FWidths.ListWidth := TArgusPluginSettings.Defaults.ListWidth;
  FWidths.PanelWidth := TArgusPluginSettings.Defaults.PanelWidth;
  FResetWidths.Enabled := False;
end;

end.
