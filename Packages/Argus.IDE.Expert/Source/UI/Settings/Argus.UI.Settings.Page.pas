unit Argus.UI.Settings.Page;

// Seite „Argus“ unter Tools › Optionen › Drittanbieter (#227, Teil
// Vervollständigung). Reine VCL, im Code aufgebaut (kein DFM): Steuerelemente
// untereinander, die IDE skaliert sie mit dem Dialog. Laden und Speichern über
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
  Argus.UI.Strings;

type
  TArgusSettingsPage = class(TFrame)
  private
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
    FResetHistory: TButton;
    FResetWidths: TButton;
    FWidths: TArgusPluginSettings;
    FNextTop: Integer;
    FOnResetHistory: TProc;
    function AddCheck(const ACaption: string): TCheckBox;
    function AddPanel(AHeight: Integer): TPanel;
    procedure ResetHistoryClick(Sender: TObject);
    procedure ResetWidthsClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFrom(const ASettings: TArgusPluginSettings);
    procedure SaveTo(var ASettings: TArgusPluginSettings);
    /// <summary>„Verlauf zurücksetzen“ der lernenden Gewichtung (#418).</summary>
    property OnResetHistory: TProc read FOnResetHistory write FOnResetHistory;
  end;

implementation

{ TArgusSettingsPage }

constructor TArgusSettingsPage.Create(AOwner: TComponent);
var
  Panel: TPanel;
  Title: TLabel;
begin
  inherited Create(AOwner);
  Name := 'ArgusSettingsPage';
  Width := 480;
  Height := 360;
  Title := TLabel.Create(Self);
  Title.Parent := Self;
  Title.Align := alTop;
  Title.AlignWithMargins := True;
  Title.Caption := TArgusStrings.Text(TArgusTextId.SettingsTitle);
  Title.Font.Style := [fsBold];
  FNextTop := 100;
  FEnabled := AddCheck(TArgusStrings.Text(TArgusTextId.SettingsEnabled));
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

procedure TArgusSettingsPage.ResetWidthsClick(Sender: TObject);
begin
  FWidths.ListWidth := TArgusPluginSettings.Defaults.ListWidth;
  FWidths.PanelWidth := TArgusPluginSettings.Defaults.PanelWidth;
  FResetWidths.Enabled := False;
end;

end.
