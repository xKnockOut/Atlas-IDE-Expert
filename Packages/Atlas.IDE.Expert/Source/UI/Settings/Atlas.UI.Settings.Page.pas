unit Atlas.UI.Settings.Page;

// Seite „Atlas“ unter Tools › Optionen › Drittanbieter (#227, Teil
// Vervollständigung). Reine VCL, im Code aufgebaut: Reiter je Bereich
// (Allgemein, Vervollständigung, Editor, Index, Compiler, Robustheit), darin
// Steuerelemente untereinander; die IDE skaliert sie mit dem Dialog. Die DFM ist leer;
// TCustomFrame.Create verlangt für abgeleitete Frames eine Ressource. Laden und Speichern über
// TAtlasPluginSettings; die IDE-Schicht liest und schreibt die Registry.

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
  Vcl.Menus,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.UI.Strings;

type
  TAtlasSettingsPage = class(TFrame)
  private
    FPages: TPageControl;
    FSheet: TTabSheet;
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
    FFixCase: TCheckBox;
    FFilterChips: TCheckBox;
    FLearning: TCheckBox;
    FGroupInherited: TCheckBox;
    FPreview: TCheckBox;
    FHoverTooltip: TCheckBox;
    FHangThreshold: TEdit;
    FHangHint: TCheckBox;
    FReloadExternal: TCheckBox;
    FPairColors: TCheckBox;
    FInactiveDim: TCheckBox;
    FPairGuides: TCheckBox;
    FPairOwners: TCheckBox;
    FPairGuideWidth: TEdit;
    FProblems: TCheckBox;
    FIndexGroup: TCheckBox;
    FIndexSearch: TCheckBox;
    FIndexLibrary: TCheckBox;
    FProblemsList: TCheckBox;
    FCheckOnSave: TCheckBox;
    FCheckDelay: TEdit;
    FCheckMax: TEdit;
    FPaletteKey: TEdit;
    FPaletteKeyPriority: TCheckBox;
    FCheckKey: TEdit;
    FCheckKeyPriority: TCheckBox;
    FResetHistory: TButton;
    FResetWidths: TButton;
    FHangTest: TButton;
    FWidths: TAtlasPluginSettings;
    FNextTop: Integer;
    FOnResetHistory: TProc;
    /// <summary>Neuer Reiter; die folgenden Add… setzen ihre Elemente darauf.</summary>
    procedure AddSheet(AId: TAtlasTextId);
    function AddCheck(const ACaption: string): TCheckBox;
    function AddPanel(AHeight: Integer): TPanel;
    function AddNumber(const ACaption: string): TEdit;
    /// <summary>Tastenkürzel mit Häkchen „Vorrang“ in einer Zeile (#494).</summary>
    function AddKey(const ACaption: string; out APriority: TCheckBox): TEdit;
    procedure ResetHistoryClick(Sender: TObject);
    procedure ResetWidthsClick(Sender: TObject);
    procedure HangTestClick(Sender: TObject);
    procedure PairColorsClick(Sender: TObject);
    procedure ServerBrowseClick(Sender: TObject);
    procedure ServerPathChange(Sender: TObject);
    procedure SetDefaultServerPath(const AValue: string);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFrom(const ASettings: TAtlasPluginSettings);
    procedure SaveTo(var ASettings: TAtlasPluginSettings);
    /// <summary>„Verlauf zurücksetzen“ der lernenden Gewichtung (#418).</summary>
    /// <summary>Reiter der Seite, einer je Bereich (#227).</summary>
    property Pages: TPageControl read FPages;
    property OnResetHistory: TProc read FOnResetHistory write FOnResetHistory;
    /// <summary>Server, der bei leerem Pfad gilt (für die Anzeige „Verwendet: …“).</summary>
    property DefaultServerPath: string read FDefaultServerPath write SetDefaultServerPath;
  end;

implementation

{$R *.dfm}

{ TAtlasSettingsPage }

constructor TAtlasSettingsPage.Create(AOwner: TComponent);
var
  Panel: TPanel;
  Title: TLabel;
begin
  inherited Create(AOwner);
  Name := 'AtlasSettingsPage';
  Width := 480;
  Height := 740;
  Title := TLabel.Create(Self);
  Title.Parent := Self;
  Title.Align := alTop;
  Title.AlignWithMargins := True;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsTitle);
  Title.Font.Style := [fsBold];
  // Reiter je Bereich (#227); jeder stapelt seine Elemente neu von oben.
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.AlignWithMargins := True;
  FPages.Top := 100;

  AddSheet(TAtlasTextId.SettingsTabGeneral);
  FEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEnabled));
  // Wo der Server liegt; leer gilt der Standard neben dem Plugin.
  Panel := AddPanel(26);
  Title := TLabel.Create(Self);
  Title.Parent := Panel;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsServerPath);
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
  FReloadExternal := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReload));
  // Tastenkürzel (#494).
  FPaletteKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsPaletteKey), FPaletteKeyPriority);

  AddSheet(TAtlasTextId.SettingsTabCompletion);
  Panel := AddPanel(26);
  FRowsLabel := TLabel.Create(Self);
  FRowsLabel.Parent := Panel;
  FRowsLabel.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsRows);
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
  FRowsUpDown.Min := TAtlasPluginSettings.MinVisibleRows;
  FRowsUpDown.Max := TAtlasPluginSettings.MaxVisibleRows;
  FPanelCollapsed := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPanelCollapsed));
  FAutoParentheses := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsParentheses));
  FFixCase := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsFixCase));
  FFilterChips := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsChips));
  FLearning := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsLearning));
  FGroupInherited := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGroupInherited));
  FPreview := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPreview));
  Panel := AddPanel(32);
  FResetHistory := TButton.Create(Self);
  FResetHistory.Parent := Panel;
  FResetHistory.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsResetHistory);
  FResetHistory.Left := 0;
  FResetHistory.Top := 3;
  FResetHistory.Width := 150;
  FResetHistory.OnClick := ResetHistoryClick;
  FResetWidths := TButton.Create(Self);
  FResetWidths.Parent := Panel;
  FResetWidths.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsResetWidths);
  FResetWidths.Left := 160;
  FResetWidths.Top := 3;
  FResetWidths.Width := 150;
  FResetWidths.OnClick := ResetWidthsClick;

  AddSheet(TAtlasTextId.SettingsTabEditor);
  FHoverTooltip := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHover));
  FPairColors := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairs));
  FInactiveDim := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInactiveDim));
  FPairGuides := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuides));
  // Anweisungen mitfärben und Linienbreite (#653); wirken nur mit der Paarfärbung.
  FPairOwners := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairOwners));
  FPairGuideWidth := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuideWidth));
  FPairColors.OnClick := PairColorsClick;
  FProblems := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblems));
  FProblemsList := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsList));

  // Umfang des Index (#652).
  AddSheet(TAtlasTextId.SettingsTabIndex);
  // Umfang des Index für alle Projekte; index in atlas.json hat Vorrang (#652).
  FIndexGroup := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexGroup));
  FIndexSearch := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexSearch));
  FIndexLibrary := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexLibrary));

  AddSheet(TAtlasTextId.SettingsTabCompiler);
  // Compilerprüfung nach dem Speichern (#548).
  FCheckOnSave := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCheckOnSave));
  FCheckDelay := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsCheckDelay));
  FCheckMax := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsCheckMax));
  FCheckKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsCheckKey), FCheckKeyPriority);

  AddSheet(TAtlasTextId.SettingsTabRobustness);
  // Einfrier-Wächter (#501).
  FHangThreshold := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsHangThreshold));
  FHangHint := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHangHint));
  Panel := AddPanel(32);
  FHangTest := TButton.Create(Self);
  FHangTest.Parent := Panel;
  FHangTest.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsHangTest);
  FHangTest.Left := 0;
  FHangTest.Top := 3;
  FHangTest.Width := 150;
  FHangTest.OnClick := HangTestClick;
  FPages.ActivePageIndex := 0;
end;

procedure TAtlasSettingsPage.AddSheet(AId: TAtlasTextId);
begin
  FSheet := TTabSheet.Create(Self);
  FSheet.PageControl := FPages;
  FSheet.Caption := TAtlasStrings.Text(AId);
  FNextTop := 100;
end;

function TAtlasSettingsPage.AddCheck(const ACaption: string): TCheckBox;
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

function TAtlasSettingsPage.AddPanel(AHeight: Integer): TPanel;
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

function TAtlasSettingsPage.AddKey(const ACaption: string; out APriority: TCheckBox): TEdit;
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
  // Als Text wie im Menü ("Strg+Umschalt+P"); leer = keine Taste.
  Result := TEdit.Create(Self);
  Result.Parent := Panel;
  Result.Left := 180;
  Result.Top := 1;
  Result.Width := 140;
  APriority := TCheckBox.Create(Self);
  APriority.Parent := Panel;
  APriority.Left := 330;
  APriority.Top := 3;
  APriority.Width := 220;
  APriority.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsKeyPriority);
end;

procedure TAtlasSettingsPage.PairColorsClick(Sender: TObject);
begin
  FPairOwners.Enabled := FPairColors.Checked;
  FPairGuides.Enabled := FPairColors.Checked;
  FPairGuideWidth.Enabled := FPairColors.Checked;
end;

function TAtlasSettingsPage.AddNumber(const ACaption: string): TEdit;
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

procedure TAtlasSettingsPage.LoadFrom(const ASettings: TAtlasPluginSettings);
begin
  FWidths := ASettings;
  FEnabled.Checked := ASettings.Enabled;
  FServerPath.Text := ASettings.ServerPath;
  FPaletteKey.Text := ShortCutToText(TShortCut(ASettings.PaletteKey));
  FPaletteKeyPriority.Checked := ASettings.PaletteKeyPriority;
  FCheckKey.Text := ShortCutToText(TShortCut(ASettings.CheckKey));
  FCheckKeyPriority.Checked := ASettings.CheckKeyPriority;
  ServerPathChange(nil);
  FRowsUpDown.Position := ASettings.VisibleRows;
  FPanelCollapsed.Checked := ASettings.PanelCollapsed;
  FAutoParentheses.Checked := ASettings.AutoParentheses;
  FFixCase.Checked := ASettings.FixCase;
  FFilterChips.Checked := ASettings.FilterChips;
  FLearning.Checked := ASettings.Learning;
  FGroupInherited.Checked := ASettings.GroupInherited;
  FPreview.Checked := ASettings.Preview;
  FHoverTooltip.Checked := ASettings.HoverTooltip;
  FHangThreshold.Text := IntToStr(ASettings.HangThresholdMs);
  FHangHint.Checked := ASettings.HangHint;
  FReloadExternal.Checked := ASettings.ReloadExternal;
  FPairColors.Checked := ASettings.PairColors;
  FInactiveDim.Checked := ASettings.InactiveDim;
  FPairGuides.Checked := ASettings.PairGuides;
  FPairOwners.Checked := ASettings.PairOwners;
  FPairGuideWidth.Text := IntToStr(ASettings.PairGuideWidth);
  PairColorsClick(nil);
  FProblems.Checked := ASettings.Problems;
  FIndexGroup.Checked := ASettings.IndexProjectGroup;
  FIndexSearch.Checked := ASettings.IndexSearchPaths;
  FIndexLibrary.Checked := ASettings.IndexLibraryPaths;
  FProblemsList.Checked := ASettings.ProblemsList;
  FCheckOnSave.Checked := ASettings.CheckOnSave;
  FCheckDelay.Text := IntToStr(ASettings.CheckOnSaveDelayMs);
  FCheckMax.Text := IntToStr(ASettings.CheckOnSaveMaxMs);
end;

procedure TAtlasSettingsPage.SaveTo(var ASettings: TAtlasPluginSettings);
begin
  ASettings.Enabled := FEnabled.Checked;
  ASettings.ServerPath := Trim(FServerPath.Text);
  ASettings.PaletteKey := Integer(TextToShortCut(Trim(FPaletteKey.Text)));
  ASettings.PaletteKeyPriority := FPaletteKeyPriority.Checked;
  ASettings.CheckKey := Integer(TextToShortCut(Trim(FCheckKey.Text)));
  ASettings.CheckKeyPriority := FCheckKeyPriority.Checked;
  ASettings.VisibleRows := FRowsUpDown.Position;
  ASettings.PanelCollapsed := FPanelCollapsed.Checked;
  ASettings.AutoParentheses := FAutoParentheses.Checked;
  ASettings.FixCase := FFixCase.Checked;
  ASettings.FilterChips := FFilterChips.Checked;
  ASettings.Learning := FLearning.Checked;
  ASettings.GroupInherited := FGroupInherited.Checked;
  ASettings.Preview := FPreview.Checked;
  ASettings.HoverTooltip := FHoverTooltip.Checked;
  ASettings.HangThresholdMs := StrToIntDef(FHangThreshold.Text, ASettings.HangThresholdMs);
  ASettings.HangHint := FHangHint.Checked;
  ASettings.ReloadExternal := FReloadExternal.Checked;
  ASettings.PairColors := FPairColors.Checked;
  ASettings.InactiveDim := FInactiveDim.Checked;
  ASettings.PairGuides := FPairGuides.Checked;
  ASettings.PairOwners := FPairOwners.Checked;
  ASettings.PairGuideWidth := StrToIntDef(FPairGuideWidth.Text, ASettings.PairGuideWidth);
  ASettings.Problems := FProblems.Checked;
  ASettings.IndexProjectGroup := FIndexGroup.Checked;
  ASettings.IndexSearchPaths := FIndexSearch.Checked;
  ASettings.IndexLibraryPaths := FIndexLibrary.Checked;
  ASettings.ProblemsList := FProblemsList.Checked;
  ASettings.CheckOnSave := FCheckOnSave.Checked;
  ASettings.CheckOnSaveDelayMs := StrToIntDef(FCheckDelay.Text, ASettings.CheckOnSaveDelayMs);
  ASettings.CheckOnSaveMaxMs := StrToIntDef(FCheckMax.Text, ASettings.CheckOnSaveMaxMs);
  ASettings.ListWidth := FWidths.ListWidth;
  ASettings.PanelWidth := FWidths.PanelWidth;
  ASettings.Normalize;
end;

procedure TAtlasSettingsPage.SetDefaultServerPath(const AValue: string);
begin
  FDefaultServerPath := AValue;
  ServerPathChange(nil);
end;

procedure TAtlasSettingsPage.ServerPathChange(Sender: TObject);
var
  Path: string;
begin
  Path := Trim(FServerPath.Text);
  if Path = '' then
    Path := FDefaultServerPath;
  if Path = '' then
    FServerStatus.Caption := ''
  else if FileExists(Path) then
    FServerStatus.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsServerFound, [Path])
  else
    FServerStatus.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsServerMissing, [Path]);
end;

procedure TAtlasSettingsPage.ServerBrowseClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsServerFilter);
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

procedure TAtlasSettingsPage.ResetHistoryClick(Sender: TObject);
begin
  if Assigned(FOnResetHistory) then
    FOnResetHistory();
  FResetHistory.Enabled := False;
end;

procedure TAtlasSettingsPage.HangTestClick(Sender: TObject);
var
  Activity: IInterface;
begin
  // Künstlicher Hänger für den Einfrier-Wächter (#501): erscheint im Protokoll mit dieser Aktion.
  Activity := TAtlasActivity.Scope('Wächter-Test');
  Sleep(1000);
end;

procedure TAtlasSettingsPage.ResetWidthsClick(Sender: TObject);
begin
  FWidths.ListWidth := TAtlasPluginSettings.Defaults.ListWidth;
  FWidths.PanelWidth := TAtlasPluginSettings.Defaults.PanelWidth;
  FResetWidths.Enabled := False;
end;

end.
