unit Argus.UI.Settings.Page;

// Seite „Argus“ unter Tools › Optionen › Drittanbieter (#227, Teil
// Vervollständigung). Reine VCL, im Code aufgebaut: Reiter je Bereich
// (Allgemein, Vervollständigung, Editor, Compiler, Robustheit wie x-page im
// Schema), darin Steuerelemente untereinander; die IDE skaliert sie mit dem
// Dialog. Die DFM ist leer; TCustomFrame.Create verlangt für abgeleitete
// Frames eine Ressource. Laden und Speichern über
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
  Argus.Core.Settings.Plugin,
  Argus.Core.Diagnostics.Hangs,
  Argus.UI.Strings;

type
  TArgusSettingsPage = class(TFrame)
  private
    FPages: TPageControl;
    FSheet: TTabSheet;
    FEnabled: TCheckBox;
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
    procedure AddSheet(AId: TArgusTextId);
    function AddCheck(const ACaption: string): TCheckBox;
    function AddPanel(AHeight: Integer): TPanel;
    function AddNumber(const ACaption: string): TEdit;
    procedure ResetHistoryClick(Sender: TObject);
    procedure ResetWidthsClick(Sender: TObject);
    procedure HangTestClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFrom(const ASettings: TArgusPluginSettings);
    procedure SaveTo(var ASettings: TArgusPluginSettings);
    /// <summary>Reiter der Seite, einer je Bereich.</summary>
    property Pages: TPageControl read FPages;
    /// <summary>„Verlauf zurücksetzen“ der lernenden Gewichtung (#418).</summary>
    property OnResetHistory: TProc read FOnResetHistory write FOnResetHistory;
  end;

implementation

{$R *.dfm}

const
  // Linke Kante der Zahlenfelder; Platz für „Wartezeit nach dem Speichern (ms):“.
  NumberLeft = 230;

{ TArgusSettingsPage }

constructor TArgusSettingsPage.Create(AOwner: TComponent);
var
  Panel: TPanel;
  Title: TLabel;
begin
  inherited Create(AOwner);
  Name := 'ArgusSettingsPage';
  Width := 480;
  Height := 590;
  Title := TLabel.Create(Self);
  Title.Parent := Self;
  Title.Align := alTop;
  Title.AlignWithMargins := True;
  Title.Caption := TArgusStrings.Text(TArgusTextId.SettingsTitle);
  Title.Font.Style := [fsBold];
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.AlignWithMargins := True;
  FPages.Top := 100;

  AddSheet(TArgusTextId.SettingsTabGeneral);
  FEnabled := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsEnabled));
  FReloadExternal := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsReload));

  AddSheet(TArgusTextId.SettingsTabCompletion);
  Panel := AddPanel(26);
  FRowsLabel := TLabel.Create(Self);
  FRowsLabel.Parent := Panel;
  FRowsLabel.Caption := TArgusStrings.Text(TArgusTextId.SettingsRows);
  FRowsLabel.Left := 0;
  FRowsLabel.Top := 5;
  FRows := TEdit.Create(Self);
  FRows.Parent := Panel;
  FRows.Left := NumberLeft;
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

  AddSheet(TArgusTextId.SettingsTabEditor);
  FHoverTooltip := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsHover));
  FPairColors := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsPairs));
  FPairGuides := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsPairGuides));
  FProblems := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsProblems));

  // Compilerprüfung nach dem Speichern (#548).
  AddSheet(TArgusTextId.SettingsTabCompiler);
  FCheckOnSave := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsCheckOnSave));
  FCheckDelay := AddNumber(TArgusStrings.Text(TArgusTextId.SettingsCheckDelay));
  FCheckMax := AddNumber(TArgusStrings.Text(TArgusTextId.SettingsCheckMax));

  // Einfrier-Wächter (#501).
  AddSheet(TArgusTextId.SettingsTabRobustness);
  FHangThreshold := AddNumber(TArgusStrings.Text(TArgusTextId.SettingsHangThreshold));
  FHangHint := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsHangHint));
  Panel := AddPanel(32);
  FHangTest := TButton.Create(Self);
  FHangTest.Parent := Panel;
  FHangTest.Caption := TArgusStrings.Text(TArgusTextId.SettingsHangTest);
  FHangTest.Left := 0;
  FHangTest.Top := 3;
  FHangTest.Width := 150;
  FHangTest.OnClick := HangTestClick;
  FPages.ActivePageIndex := 0;
end;

procedure TArgusSettingsPage.AddSheet(AId: TArgusTextId);
begin
  FSheet := TTabSheet.Create(Self);
  FSheet.PageControl := FPages;
  FSheet.Caption := TArgusStrings.Text(AId);
  // Jeder Reiter stapelt seine Elemente neu von oben.
  FNextTop := 100;
end;

function TArgusSettingsPage.AddCheck(const ACaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := FSheet;
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
  Result.Parent := FSheet;
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
  Result.Left := NumberLeft;
  Result.Top := 1;
  Result.Width := 60;
  Result.NumbersOnly := True;
end;

procedure TArgusSettingsPage.LoadFrom(const ASettings: TArgusPluginSettings);
begin
  FWidths := ASettings;
  FEnabled.Checked := ASettings.Enabled;
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
