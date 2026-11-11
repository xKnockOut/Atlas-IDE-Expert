unit Atlas.UI.Settings.Page.Robustness;

// Reiter „Robustheit“: Einfrier-Wächter (#501), Blockierschutz und Sicherung (#493).

interface

uses
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Robustheit“: Einfrier-Wächter (#501), Blockierschutz und Sicherung (#493).</summary>
  TAtlasSettingsRobustnessPart = class(TAtlasSettingsPagePart)
  private
    FFuseList: TListBox;
    FFuseEnableSelected: TButton;
    FFuseEnableAll: TButton;
    FHangTest: TButton;
    FHangTestRow: TWinControl;
    procedure HangTestClick(Sender: TObject);
    procedure DiagnosticModeClick(Sender: TObject);
    procedure FuseEnableSelectedClick(Sender: TObject);
    procedure FuseEnableAllClick(Sender: TObject);
    procedure AddFuseSection;
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure WindowReady; override;
    /// <summary>Liste der abgeschalteten Features und Quellen neu lesen (#493).</summary>
    procedure RefreshFuse;
    /// <summary>Zum Testen: Liste und Schaltflächen der Sicherung.</summary>
    property FuseList: TListBox read FFuseList;
    property FuseEnableSelected: TButton read FFuseEnableSelected;
    property FuseEnableAll: TButton read FFuseEnableAll;
    /// <summary>Zeile mit „Wächter testen“; nur im Diagnosemodus sichtbar.</summary>
    property HangTestRow: TWinControl read FHangTestRow;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Page.General;

{ TAtlasSettingsRobustnessPart }

procedure TAtlasSettingsRobustnessPart.Build;
var
  mPanel: TWinControl;
begin
  AddSheet(TAtlasTextId.SettingsTabRobustness);
  // Einfrier-Wächter (#501).
  BindText('HangThresholdMs', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsHangThreshold)));
  BindCheck('HangHint', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHangHint)));
  // Blockierschutz für Datenquellen (#493).
  BindText('ProviderTimeLimitMs', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsProviderTimeLimit)));
  mPanel := AddPanel(32);
  // Künstlicher Hänger (#501) nur im Diagnosemodus (#479), nicht neben den regulären Einstellungen.
  FHangTestRow := mPanel;
  FHangTestRow.Visible := False;
  FPage.Part<TAtlasSettingsGeneralPart>.DiagnosticMode.OnClick := DiagnosticModeClick;
  FHangTest := TButton.Create(FPage);
  FHangTest.Parent := mPanel;
  FHangTest.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsHangTest);
  FHangTest.Left := 0;
  FHangTest.Top := 3;
  FHangTest.Width := 150;
  FHangTest.OnClick := HangTestClick;
  AddFuseSection;
end;

procedure TAtlasSettingsRobustnessPart.WindowReady;
begin
  // Die Liste der Sicherung braucht ein Fenster; vorher bleibt sie leer.
  RefreshFuse;
end;

procedure TAtlasSettingsRobustnessPart.AddFuseSection;
var
  mPanel: TWinControl;
begin
  AddTitle(TAtlasTextId.SettingsFuseTitle);
  mPanel := AddPanel(64);
  FFuseList := TListBox.Create(FPage);
  FFuseList.Parent := mPanel;
  FFuseList.Align := alClient;
  FFuseList.MultiSelect := True;
  mPanel := AddPanel(32);
  FFuseEnableSelected := TButton.Create(FPage);
  FFuseEnableSelected.Parent := mPanel;
  FFuseEnableSelected.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsFuseEnableSelected);
  FFuseEnableSelected.Left := 0;
  FFuseEnableSelected.Top := 3;
  FFuseEnableSelected.Width := 150;
  FFuseEnableSelected.OnClick := FuseEnableSelectedClick;
  FFuseEnableAll := TButton.Create(FPage);
  FFuseEnableAll.Parent := mPanel;
  FFuseEnableAll.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsFuseEnableAll);
  FFuseEnableAll.Left := 160;
  FFuseEnableAll.Top := 3;
  FFuseEnableAll.Width := 150;
  FFuseEnableAll.OnClick := FuseEnableAllClick;
end;

procedure TAtlasSettingsRobustnessPart.RefreshFuse;
var
  mFeature: TAtlasFeature;
  mName: string;
  mAny: Boolean;
begin
  // Ohne Fenster (IDE erzeugt die Seite vor dem Einhängen) folgt das in CreateWnd.
  if not FPage.HandleAllocated then
  begin
    Exit;
  end;
  FFuseList.Items.BeginUpdate;
  try
    FFuseList.Items.Clear;
    // Objects: Feature + 1; nil bei einer Quelle (Name im Text).
    for mFeature in TAtlasGuard.DisabledSet do
    begin
      FFuseList.Items.AddObject(TAtlasGuard.FeatureName(mFeature), TObject(NativeInt(Ord(mFeature) + 1)));
    end;
    for mName in TAtlasGuard.DisabledProviders do
    begin
      FFuseList.Items.AddObject(mName, nil);
    end;
    mAny := FFuseList.Items.Count > 0;
    if not mAny then
    begin
      FFuseList.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsFuseNone));
    end;
  finally
    FFuseList.Items.EndUpdate;
  end;
  Allow(FFuseList, mAny);
  Allow(FFuseEnableSelected, mAny);
  Allow(FFuseEnableAll, mAny);
end;

procedure TAtlasSettingsRobustnessPart.FuseEnableSelectedClick(Sender: TObject);
var
  mIndex: Integer;
  mTag: NativeInt;
begin
  for mIndex := 0 to FFuseList.Items.Count - 1 do
  begin
    if FFuseList.Selected[mIndex] then
    begin
      mTag := NativeInt(FFuseList.Items.Objects[mIndex]);
      if mTag > 0 then
      begin
        TAtlasGuard.Enable(TAtlasFeature(mTag - 1));
      end
      else
      begin
        TAtlasGuard.EnableProvider(FFuseList.Items[mIndex]);
      end;
    end;
  end;
  RefreshFuse;
end;

procedure TAtlasSettingsRobustnessPart.FuseEnableAllClick(Sender: TObject);
begin
  TAtlasGuard.EnableAll;
  RefreshFuse;
end;

procedure TAtlasSettingsRobustnessPart.Load(const ASettings: TAtlasPluginSettings);
begin
  // Checked löst OnClick nur bei einer Änderung aus.
  FHangTestRow.Visible := ASettings.DiagnosticMode;
  RefreshFuse;
end;

procedure TAtlasSettingsRobustnessPart.HangTestClick(Sender: TObject);
var
  mActivity: IInterface;
begin
  // Künstlicher Hänger für den Einfrier-Wächter (#501): erscheint im Protokoll mit dieser Aktion.
  mActivity := TAtlasActivity.Scope('Wächter-Test');
  Sleep(1000); // lsp-ignore: blocking-call-in-main-thread
end;

procedure TAtlasSettingsRobustnessPart.DiagnosticModeClick(Sender: TObject);
begin
  FHangTestRow.Visible := FPage.Part<TAtlasSettingsGeneralPart>.DiagnosticMode.Checked;
end;

end.
