unit Shell.Monitor.MainForm;

// Host-Rolle Shell von AtlasMonitor (#1900, #1901): Fenster mit dem Reiter „Prüfen“ (Läufe ohne IDE über mehrere
// Ziele, Shell.Monitor.CheckPage), dem Reiter „Server“ (alle laufenden Atlas-Server aus
// ihren Statusdateien, Einzelheiten, Beenden, Protokoll öffnen) und Symbol im Infobereich mit Zustandspunkt
// (ruht, arbeitet, hängt) und Kontextmenü. Die Liste kommt alle 2 s neu aus TServerStatusFile.List; Regeln und
// Texte stehen in Atlas.Common.Monitor.*, Systemzugriffe in TMonitorSystem. Mit Symbol im Infobereich schließt
// das Kreuz nur das Fenster; „Beenden“ beendet das Programm. Ohne Symbol beendet das Schließen das Programm.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Monitor.Servers,
  Atlas.Common.Monitor.Settings,
  Shell.Monitor.CheckPage;

type
  TAtlasMonitorForm = class(TForm)
  private
    FSettings: TMonitorSettings;
    FSettingsFile: string;
    FStatusRoot: string;
    FEntries: TArray<TServerStatusEntry>;
    FPages: TPageControl;
    FServerTab: TTabSheet;
    FCheckPage: TMonitorCheckPage;
    FServerList: TListView;
    FDetails: TMemo;
    FTimer: TTimer;
    FTray: TTrayIcon;
    FTrayMenu: TPopupMenu;
    FMainMenu: TMainMenu;
    FTrayIconItem: TMenuItem;
    FAutostartItem: TMenuItem;
    FIcons: array[TMonitorHealth] of TIcon;
    FQuitting: Boolean;
    FTrayHintShown: Boolean;
    procedure BuildServerTab;
    procedure BuildButtons(AParent: TWinControl);
    procedure BuildMenus;
    procedure BuildTray;
    procedure ReadEntries;
    procedure RefreshServers(ASender: TObject);
    procedure FillList;
    procedure ShowDetails;
    procedure UpdateTray;
    procedure FillTrayMenu(ASender: TObject);
    function SelectedEntry(out AEntry: TServerStatusEntry): Boolean;
    procedure SelectPid(APid: Cardinal);
    procedure StopSelectedClick(ASender: TObject);
    procedure StopAllClick(ASender: TObject);
    procedure OpenLogClick(ASender: TObject);
    procedure OpenLogFolderClick(ASender: TObject);
    procedure ClearCacheClick(ASender: TObject);
    procedure OpenWindowClick(ASender: TObject);
    procedure ServerItemClick(ASender: TObject);
    procedure ToggleTrayIconClick(ASender: TObject);
    procedure ToggleAutostartClick(ASender: TObject);
    procedure QuitClick(ASender: TObject);
    procedure ListSelectItem(ASender: TObject; AItem: TListItem; ASelected: Boolean);
    procedure FormCloseQuery(ASender: TObject; var ACanClose: Boolean);
    procedure SaveSettings;
    procedure ApplyAutostart(AEnabled: Boolean);
    function Confirm(const AText: string): Boolean;
    procedure Inform(const AText: string);
    function LogFolder: string;
    function InformProc: TProc<string>;
    function ConfirmFunc: TMonitorConfirm;
  protected
    procedure CreateWnd; override;
    procedure WndProc(var AMessage: TMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Zeigt das Fenster und holt es nach vorn (Doppelklick auf das Symbol, zweiter Start).</summary>
    procedure ShowFromTray;
    /// <summary>Nachricht, mit der ein zweiter Start das Fenster des ersten zeigt.</summary>
    class function ShowMessageId: Cardinal; static;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Monitor.Texts,
  Atlas.Windows.Monitor.Adapters.System;

const
  cRefreshMs = 2000;
  cButtonWidth = 170;
  cButtonGap = 8;
  cPanelHeight = 44;
  cDetailsWidth = 340;
  // Farben des Zustandspunkts als TColor ($00BBGGRR): grau, blau, rot.
  cHealthColors: array[TMonitorHealth] of TColor = ($00808080, $00D77800, $002020D0);
  cMaskColor = clFuchsia;

var
  GShowMessage: Cardinal;

/// <summary>AValue in Pixeln bei 96 dpi, umgerechnet auf die Auflösung des Bildschirms.</summary>
function Px(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Screen.PixelsPerInch, 96);
end;

/// <summary>Symbol für den Infobereich: Kreis in der Farbe des Zustands mit weißem „A“.</summary>
function HealthIcon(AHealth: TMonitorHealth): TIcon;
var
  mSize: Integer;
  mBitmap: TBitmap;
  mList: TImageList;
begin
  mSize := GetSystemMetrics(SM_CXSMICON);
  mBitmap := TBitmap.Create;
  mList := TImageList.CreateSize(mSize, mSize);
  try
    mBitmap.SetSize(mSize, mSize);
    mBitmap.Canvas.Brush.Color := cMaskColor;
    mBitmap.Canvas.FillRect(TRect.Create(0, 0, mSize, mSize));
    mBitmap.Canvas.Brush.Color := cHealthColors[AHealth];
    mBitmap.Canvas.Pen.Color := cHealthColors[AHealth];
    mBitmap.Canvas.Ellipse(0, 0, mSize, mSize);
    mBitmap.Canvas.Font.Color := clWhite;
    mBitmap.Canvas.Font.Style := [fsBold];
    mBitmap.Canvas.Font.Height := -(mSize * 3 div 4);
    mBitmap.Canvas.Brush.Style := bsClear;
    mBitmap.Canvas.TextOut((mSize - mBitmap.Canvas.TextWidth('A')) div 2,
      (mSize - mBitmap.Canvas.TextHeight('A')) div 2, 'A');
    mList.AddMasked(mBitmap, cMaskColor);
    Result := TIcon.Create;
    mList.GetIcon(0, Result);
  finally
    mList.Free;
    mBitmap.Free;
  end;
end;

/// <summary>Neuer Menüeintrag unter AParent.</summary>
function AddItem(AParent: TMenuItem; const ACaption: string; const AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AParent);
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
  AParent.Add(Result);
end;

/// <summary>Trennstrich unter AParent.</summary>
procedure AddSeparator(AParent: TMenuItem);
begin
  AddItem(AParent, '-', nil);
end;

/// <summary>Prüft für TServerStatusFile.List, ob ein Server noch läuft.</summary>
function AliveCheck: TServerAliveFunc;
begin
  Result :=
    function(APid: Cardinal): Boolean
    begin
      Result := TMonitorSystem.IsRunning(APid);
    end;
end;

/// <summary>Befehlszeile für den Start mit Windows: nur das Symbol, ohne Fenster.</summary>
function AutostartCommand: string;
begin
  Result := '"' + ParamStr(0) + '" --tray';
end;

{ TAtlasMonitorForm }

constructor TAtlasMonitorForm.Create(AOwner: TComponent);
var
  mHealth: TMonitorHealth;
begin
  inherited CreateNew(AOwner);
  Caption := TMonitorTexts.Text(TMonitorText.Caption);
  Width := Px(1180);
  Height := Px(720);
  Position := poScreenCenter;
  OnCloseQuery := FormCloseQuery;
  FStatusRoot := TIndexCacheDirectory.DefaultRoot;
  FSettingsFile := TMonitorSettings.FileIn(GetEnvironmentVariable('APPDATA'));
  FSettings := TMonitorSettings.Load(FSettingsFile);
  for mHealth := Low(TMonitorHealth) to High(TMonitorHealth) do
  begin
    FIcons[mHealth] := HealthIcon(mHealth);
  end;
  BuildMenus;
  BuildServerTab;
  FCheckPage := TMonitorCheckPage.Create(Self, FPages, FSettings.Check, FStatusRoot, InformProc, ConfirmFunc);
  BuildTray;
  // Die Einstellung gilt: ein fehlender oder veralteter Eintrag (Programm verschoben) wird nachgezogen.
  ApplyAutostart(FSettings.StartWithWindows);
  FTimer := TTimer.Create(Self);
  FTimer.Interval := cRefreshMs;
  FTimer.OnTimer := RefreshServers;
  ReadEntries;
  UpdateTray;
end;

destructor TAtlasMonitorForm.Destroy;
var
  mHealth: TMonitorHealth;
begin
  if FTray <> nil then
  begin
    FTray.Visible := False;
  end;
  // Stand des Prüffensters für den nächsten Start; ein Fehler beim Speichern bleibt hier still.
  if FCheckPage <> nil then
  begin
    FCheckPage.CancelRuns;
    FSettings.Check := FCheckPage.State;
    FSettings.Save(FSettingsFile);
  end;
  for mHealth := Low(TMonitorHealth) to High(TMonitorHealth) do
  begin
    FreeAndNil(FIcons[mHealth]);
  end;
  FEntries := nil;
  inherited;
end;

class function TAtlasMonitorForm.ShowMessageId: Cardinal;
begin
  Result := GShowMessage;
end;

procedure TAtlasMonitorForm.BuildMenus;
var
  mFile, mSettings: TMenuItem;
begin
  FMainMenu := TMainMenu.Create(Self);
  mFile := AddItem(FMainMenu.Items, TMonitorTexts.Text(TMonitorText.MenuFile), nil);
  AddItem(mFile, TMonitorTexts.Text(TMonitorText.OpenLogFolder), OpenLogFolderClick);
  AddItem(mFile, TMonitorTexts.Text(TMonitorText.ClearCache), ClearCacheClick);
  AddItem(mFile, TMonitorTexts.Text(TMonitorText.StopAllServers), StopAllClick);
  AddSeparator(mFile);
  AddItem(mFile, TMonitorTexts.Text(TMonitorText.ExitProgram), QuitClick);
  mSettings := AddItem(FMainMenu.Items, TMonitorTexts.Text(TMonitorText.MenuSettings), nil);
  FTrayIconItem := AddItem(mSettings, TMonitorTexts.Text(TMonitorText.TrayIcon), ToggleTrayIconClick);
  FTrayIconItem.Checked := FSettings.TrayIcon;
  FAutostartItem := AddItem(mSettings, TMonitorTexts.Text(TMonitorText.StartWithWindows), ToggleAutostartClick);
  FAutostartItem.Checked := FSettings.StartWithWindows;
  Menu := FMainMenu;
end;

procedure TAtlasMonitorForm.BuildServerTab;
var
  mTitle: string;
  mColumn: TListColumn;
  mSplitter: TSplitter;
begin
  FPages := TPageControl.Create(Self);
  FPages.Align := alClient;
  FPages.Parent := Self;
  FServerTab := TTabSheet.Create(Self);
  FServerTab.Caption := TMonitorTexts.Text(TMonitorText.TabServers);
  // Ohne Fenster scheitert ein sichtbarer Reiter; CreateWnd zeigt ihn.
  FServerTab.TabVisible := False;
  FServerTab.PageControl := FPages;
  BuildButtons(FServerTab);
  FDetails := TMemo.Create(Self);
  FDetails.Width := Px(cDetailsWidth);
  FDetails.Align := alRight;
  FDetails.ReadOnly := True;
  FDetails.ScrollBars := ssVertical;
  FDetails.Parent := FServerTab;
  mSplitter := TSplitter.Create(Self);
  mSplitter.Align := alRight;
  mSplitter.Parent := FServerTab;
  FServerList := TListView.Create(Self);
  FServerList.Align := alClient;
  FServerList.ViewStyle := vsReport;
  FServerList.ReadOnly := True;
  FServerList.RowSelect := True;
  FServerList.HideSelection := False;
  FServerList.OnSelectItem := ListSelectItem;
  for mTitle in TMonitorServers.ColumnTitles do
  begin
    mColumn := FServerList.Columns.Add;
    mColumn.Caption := mTitle;
    mColumn.Width := Px(110);
  end;
  // Ordner bzw. Ziel ist die breiteste Spalte.
  FServerList.Columns[1].Width := Px(280);
  FServerList.Parent := FServerTab;
end;

procedure TAtlasMonitorForm.BuildButtons(AParent: TWinControl);
var
  mPanel: TPanel;
  mLeft: Integer;

  procedure AddButton(const ACaption: string; const AOnClick: TNotifyEvent);
  var
    mButton: TButton;
  begin
    mButton := TButton.Create(Self);
    mButton.Caption := ACaption;
    mButton.OnClick := AOnClick;
    mButton.SetBounds(mLeft, Px(cButtonGap), Px(cButtonWidth), Px(cPanelHeight - 2 * cButtonGap));
    mButton.Parent := mPanel;
    mLeft := mLeft + Px(cButtonWidth + cButtonGap);
  end;

begin
  mPanel := TPanel.Create(Self);
  // Höhe vor Align und Parent, sonst kann die VCL die Reihenfolge beim Anlegen vertauschen.
  mPanel.Height := Px(cPanelHeight);
  mPanel.Align := alBottom;
  mPanel.BevelOuter := bvNone;
  mPanel.Parent := AParent;
  mLeft := Px(cButtonGap);
  AddButton(TMonitorTexts.Text(TMonitorText.StopServer), StopSelectedClick);
  AddButton(TMonitorTexts.Text(TMonitorText.OpenLog), OpenLogClick);
  AddButton(TMonitorTexts.Text(TMonitorText.OpenLogFolder), OpenLogFolderClick);
  AddButton(TMonitorTexts.Text(TMonitorText.ClearCache), ClearCacheClick);
end;

procedure TAtlasMonitorForm.BuildTray;
begin
  FTrayMenu := TPopupMenu.Create(Self);
  FTrayMenu.OnPopup := FillTrayMenu;
  FTray := TTrayIcon.Create(Self);
  FTray.PopupMenu := FTrayMenu;
  FTray.OnDblClick := OpenWindowClick;
  FTray.Icon := FIcons[TMonitorHealth.Idle];
  FTray.Visible := FSettings.TrayIcon;
end;

procedure TAtlasMonitorForm.CreateWnd;
begin
  inherited;
  if (FServerTab <> nil) and not FServerTab.TabVisible then
  begin
    FServerTab.TabVisible := True;
    FCheckPage.Activate;
    FPages.ActivePage := FServerTab;
  end;
end;

procedure TAtlasMonitorForm.WndProc(var AMessage: TMessage);
begin
  if (GShowMessage <> 0) and (AMessage.Msg = GShowMessage) then
  begin
    ShowFromTray;
    AMessage.Result := 1;
    Exit;
  end;
  inherited WndProc(AMessage);
end;

procedure TAtlasMonitorForm.ReadEntries;
begin
  FEntries := TServerStatusFile.List(FStatusRoot, Now, AliveCheck());
end;

procedure TAtlasMonitorForm.RefreshServers(ASender: TObject);
begin
  ReadEntries;
  UpdateTray;
  // Verborgen braucht die Liste kein Fenster; ShowFromTray füllt sie beim Zeigen.
  if Showing then
  begin
    FillList;
  end;
end;

procedure TAtlasMonitorForm.FillList;
var
  mEntry: TServerStatusEntry;
  mItem: TListItem;
  mCells: TArray<string>;
  mIndex: Integer;
  mSelected: Cardinal;
begin
  mSelected := 0;
  if SelectedEntry(mEntry) then
  begin
    mSelected := mEntry.Pid;
  end;
  FServerList.Items.BeginUpdate;
  try
    FServerList.Items.Clear;
    for mEntry in FEntries do
    begin
      mCells := TMonitorServers.Columns(mEntry, Now);
      mItem := FServerList.Items.Add;
      mItem.Caption := mCells[0];
      for mIndex := 1 to High(mCells) do
      begin
        mItem.SubItems.Add(mCells[mIndex]);
      end;
    end;
  finally
    FServerList.Items.EndUpdate;
  end;
  SelectPid(mSelected);
  ShowDetails;
end;

function TAtlasMonitorForm.SelectedEntry(out AEntry: TServerStatusEntry): Boolean;
var
  mIndex: Integer;
begin
  AEntry := Default(TServerStatusEntry);
  mIndex := -1;
  if FServerList.Selected <> nil then
  begin
    mIndex := FServerList.Selected.Index;
  end;
  Result := (mIndex >= 0) and (mIndex <= High(FEntries));
  if Result then
  begin
    AEntry := FEntries[mIndex];
  end;
end;

procedure TAtlasMonitorForm.SelectPid(APid: Cardinal);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FEntries) do
  begin
    if (FEntries[mIndex].Pid = APid) and (mIndex < FServerList.Items.Count) then
    begin
      FServerList.Items[mIndex].Selected := True;
      FServerList.Items[mIndex].MakeVisible(False);
      Exit;
    end;
  end;
end;

procedure TAtlasMonitorForm.ShowDetails;
var
  mEntry: TServerStatusEntry;
begin
  if SelectedEntry(mEntry) then
  begin
    FDetails.Lines.Text := string.Join(sLineBreak, TMonitorServers.Details(mEntry, Now));
  end
  else if FEntries = nil then
  begin
    FDetails.Lines.Text := TMonitorTexts.Text(TMonitorText.NoServers);
  end
  else
  begin
    FDetails.Lines.Text := TMonitorTexts.Text(TMonitorText.SelectServer);
  end;
end;

procedure TAtlasMonitorForm.ListSelectItem(ASender: TObject; AItem: TListItem; ASelected: Boolean);
begin
  ShowDetails;
end;

procedure TAtlasMonitorForm.UpdateTray;
begin
  FTray.Icon := FIcons[TMonitorServers.Overall(FEntries, Now)];
  FTray.Hint := TMonitorServers.Hint(FEntries, Now);
end;

procedure TAtlasMonitorForm.FillTrayMenu(ASender: TObject);
var
  mEntry: TServerStatusEntry;
  mItem: TMenuItem;
begin
  ReadEntries;
  FTrayMenu.Items.Clear;
  for mEntry in FEntries do
  begin
    mItem := AddItem(FTrayMenu.Items, TMonitorServers.MenuText(mEntry, Now), ServerItemClick);
    mItem.Tag := NativeInt(mEntry.Pid);
  end;
  if FEntries = nil then
  begin
    AddItem(FTrayMenu.Items, TMonitorTexts.Text(TMonitorText.NoServers), nil).Enabled := False;
  end;
  AddSeparator(FTrayMenu.Items);
  mItem := AddItem(FTrayMenu.Items, TMonitorTexts.Text(TMonitorText.OpenWindow), OpenWindowClick);
  mItem.Default := True;
  AddItem(FTrayMenu.Items, TMonitorTexts.Text(TMonitorText.StopAllServers), StopAllClick).Enabled :=
    FEntries <> nil;
  AddItem(FTrayMenu.Items, TMonitorTexts.Text(TMonitorText.ClearCache), ClearCacheClick);
  AddItem(FTrayMenu.Items, TMonitorTexts.Text(TMonitorText.OpenLogFolder), OpenLogFolderClick);
  AddItem(FTrayMenu.Items, TMonitorTexts.Text(TMonitorText.StartWithWindows), ToggleAutostartClick).Checked :=
    FSettings.StartWithWindows;
  AddSeparator(FTrayMenu.Items);
  AddItem(FTrayMenu.Items, TMonitorTexts.Text(TMonitorText.ExitProgram), QuitClick);
end;

procedure TAtlasMonitorForm.ShowFromTray;
begin
  Show;
  if WindowState = wsMinimized then
  begin
    WindowState := wsNormal;
  end;
  Application.BringToFront;
  ReadEntries;
  FillList;
  UpdateTray;
end;

procedure TAtlasMonitorForm.OpenWindowClick(ASender: TObject);
begin
  ShowFromTray;
end;

procedure TAtlasMonitorForm.ServerItemClick(ASender: TObject);
begin
  ShowFromTray;
  SelectPid(Cardinal((ASender as TMenuItem).Tag));
  ShowDetails;
end;

function TAtlasMonitorForm.Confirm(const AText: string): Boolean;
begin
  Result := Application.MessageBox(PChar(AText), PChar(Caption), MB_YESNO or MB_ICONQUESTION) = IDYES;
end;

procedure TAtlasMonitorForm.Inform(const AText: string);
begin
  Application.MessageBox(PChar(AText), PChar(Caption), MB_OK or MB_ICONINFORMATION);
end;

function TAtlasMonitorForm.InformProc: TProc<string>;
begin
  Result :=
    procedure(AText: string)
    begin
      Inform(AText);
    end;
end;

function TAtlasMonitorForm.ConfirmFunc: TMonitorConfirm;
begin
  Result :=
    function(const AText: string): Boolean
    begin
      Result := Confirm(AText);
    end;
end;

procedure TAtlasMonitorForm.StopSelectedClick(ASender: TObject);
var
  mEntry: TServerStatusEntry;
begin
  if not SelectedEntry(mEntry) then
  begin
    Inform(TMonitorTexts.Text(TMonitorText.SelectServer));
    Exit;
  end;
  if not Confirm(TMonitorTexts.Fmt(TMonitorText.ConfirmStop, [mEntry.Pid])) then
  begin
    Exit;
  end;
  if not TMonitorSystem.TerminateServer(mEntry.Pid) then
  begin
    Inform(TMonitorTexts.Fmt(TMonitorText.StopFailed, [mEntry.Pid]));
  end;
  RefreshServers(nil);
end;

procedure TAtlasMonitorForm.StopAllClick(ASender: TObject);
var
  mEntry: TServerStatusEntry;
begin
  ReadEntries;
  if (FEntries = nil) or not Confirm(TMonitorTexts.Fmt(TMonitorText.ConfirmStopAll, [Length(FEntries)])) then
  begin
    Exit;
  end;
  for mEntry in FEntries do
  begin
    if not TMonitorSystem.TerminateServer(mEntry.Pid) then
    begin
      Inform(TMonitorTexts.Fmt(TMonitorText.StopFailed, [mEntry.Pid]));
    end;
  end;
  RefreshServers(nil);
end;

function TAtlasMonitorForm.LogFolder: string;
begin
  Result := TPath.Combine(FStatusRoot, 'Logs');
end;

procedure TAtlasMonitorForm.OpenLogClick(ASender: TObject);
var
  mEntry: TServerStatusEntry;
begin
  // Ohne eigene Protokolldatei (Server ohne --log) der Protokollordner.
  if not SelectedEntry(mEntry) or not TMonitorSystem.OpenFile(mEntry.LogFile) then
  begin
    OpenLogFolderClick(ASender);
  end;
end;

procedure TAtlasMonitorForm.OpenLogFolderClick(ASender: TObject);
begin
  ForceDirectories(LogFolder);
  TMonitorSystem.OpenFile(LogFolder);
end;

procedure TAtlasMonitorForm.ClearCacheClick(ASender: TObject);
begin
  Inform(TMonitorTexts.Fmt(TMonitorText.CacheCleared, [TIndexCacheDirectory.Clear(FStatusRoot)]));
end;

procedure TAtlasMonitorForm.SaveSettings;
begin
  FSettings.Check := FCheckPage.State;
  if not FSettings.Save(FSettingsFile) then
  begin
    Inform(TMonitorTexts.Fmt(TMonitorText.SaveFailed, [FSettingsFile]));
  end;
end;

procedure TAtlasMonitorForm.ApplyAutostart(AEnabled: Boolean);
begin
  if (AEnabled or TMonitorSystem.StartsWithWindows) and
    not TMonitorSystem.SetStartWithWindows(AEnabled, AutostartCommand) then
  begin
    Inform(TMonitorTexts.Text(TMonitorText.AutostartFailed));
  end;
end;

procedure TAtlasMonitorForm.ToggleTrayIconClick(ASender: TObject);
begin
  FSettings.TrayIcon := not FSettings.TrayIcon;
  FTrayIconItem.Checked := FSettings.TrayIcon;
  FTray.Visible := FSettings.TrayIcon;
  SaveSettings;
end;

procedure TAtlasMonitorForm.ToggleAutostartClick(ASender: TObject);
begin
  FSettings.StartWithWindows := not FSettings.StartWithWindows;
  FAutostartItem.Checked := FSettings.StartWithWindows;
  ApplyAutostart(FSettings.StartWithWindows);
  SaveSettings;
end;

procedure TAtlasMonitorForm.QuitClick(ASender: TObject);
begin
  FQuitting := True;
  Close;
end;

procedure TAtlasMonitorForm.FormCloseQuery(ASender: TObject; var ACanClose: Boolean);
begin
  if FQuitting or not FSettings.TrayIcon then
  begin
    // Beim Beenden laufen keine Kindprozesse weiter; laufende Befehle erst nach Rückfrage abbrechen.
    ACanClose := not FCheckPage.Busy or Confirm(TMonitorTexts.Text(TMonitorText.ConfirmQuitRunning));
    FQuitting := FQuitting and ACanClose;
    Exit;
  end;
  // Mit Symbol im Infobereich schließt das Kreuz nur das Fenster.
  ACanClose := False;
  Hide;
  if not FTrayHintShown then
  begin
    FTrayHintShown := True;
    FTray.BalloonTitle := Caption;
    FTray.BalloonHint := TMonitorTexts.Text(TMonitorText.CloseToTray);
    FTray.ShowBalloonHint;
  end;
end;

initialization
  GShowMessage := RegisterWindowMessage('AtlasMonitor.Show');

end.
