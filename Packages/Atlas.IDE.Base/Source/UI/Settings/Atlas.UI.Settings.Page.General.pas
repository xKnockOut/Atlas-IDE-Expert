unit Atlas.UI.Settings.Page.General;

// Reiter „Allgemein“: Server (Pfad, Zustand, Version), Statusfeld, Diagnose, Architektur, Hinweise und
// Benachrichtigungen.

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Allgemein“: Server (Pfad, Zustand, Version), Statusfeld, Diagnose, Architektur, Hinweise und
  /// Benachrichtigungen.</summary>
  TAtlasSettingsGeneralPart = class(TAtlasSettingsPagePart)
  private
    FServerPath: TEdit;
    FServerBrowse: TButton;
    FServerStatus: TLabel;
    FServerVersion: TLabel;
    FOnServerVersion: TFunc<string, string>;
    FDefaultServerPath: string;
    FDiagnosticMode: TCheckBox;
    FShortcutTipsScope: TAtlasChoiceBox;
    FStatusToggles: TAtlasChoiceBox;
    FIndexProgress: TAtlasChoiceBox;
    FStatusHidden: TEdit;
    /// <summary>Hauptschalter der experimentellen Funktionen (#834), Hinweis darüber und Filter unten.</summary>
    FExperimentalEnabled: TCheckBox;
    procedure ServerBrowseClick(Sender: TObject);
    procedure ServerPathChange(Sender: TObject);
    procedure SetDefaultServerPath(const AValue: string);
    procedure SetOnServerVersion(const AValue: TFunc<string, string>);
  public
    procedure Build;
    procedure Build2;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    property DiagnosticMode: TCheckBox read FDiagnosticMode;
    property ExperimentalEnabled: TCheckBox read FExperimentalEnabled;
    property ShortcutTipsScope: TAtlasChoiceBox read FShortcutTipsScope;
    property StatusToggles: TAtlasChoiceBox read FStatusToggles;
    property IndexProgress: TAtlasChoiceBox read FIndexProgress;
    property StatusHidden: TEdit read FStatusHidden;
    /// <summary>Server, der bei leerem Pfad gilt (für die Anzeige „Verwendet: …“).</summary>
    property DefaultServerPath: string read FDefaultServerPath write SetDefaultServerPath;
    /// <summary>Version des Servers unter dem Pfad als Text ('' = unbekannt); nil = keine Anzeige.</summary>
    property OnServerVersion: TFunc<string, string> read FOnServerVersion write SetOnServerVersion;
  end;

  /// <summary>Benachrichtigungszentrale (#601) am Ende des Reiters „Allgemein“: Schalter, Größe und Verhalten je
  /// Quelle.</summary>
  TAtlasSettingsNotificationsPart = class(TAtlasSettingsPagePart)
  private
    FNotificationsMax: TEdit;
    FNotificationSource: TAtlasChoiceBox;
    FNotificationMode: TAtlasChoiceBox;
    FNotificationsSpec: string;
    /// <summary>Zeile „Verhalten je Quelle“ (#601): Quelle und Verhalten nebeneinander.</summary>
    procedure AddNotificationSources;
    procedure NotificationSourceChange(Sender: TObject);
    procedure NotificationModeChange(Sender: TObject);
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    property NotificationsMax: TEdit read FNotificationsMax;
    property NotificationSource: TAtlasChoiceBox read FNotificationSource;
    property NotificationMode: TAtlasChoiceBox read FNotificationMode;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Dialogs,
  Atlas.UI.Settings.Page.Sheets,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Sources,
  Atlas.UI.Notifications.Window;

{ TAtlasSettingsGeneralPart }

procedure TAtlasSettingsGeneralPart.Build;
var
  mPanel: TWinControl;
  mTitle: TLabel;
begin
  AddSheet(TAtlasTextId.SettingsTabGeneral);
  BindCheck('Enabled', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsEnabled)));
  // Wo der Server liegt; leer gilt der Standard neben dem Plugin.
  mPanel := AddPanel(20);
  mTitle := TLabel.Create(FPage);
  mTitle.Parent := mPanel;
  mTitle.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsServerPath);
  mTitle.Left := 0;
  mTitle.Top := mTitle.ScaleValue(3);
  // Pfad in eigener Zeile: Die Beschriftung ist lang, das Feld braucht die Breite.
  mPanel := AddPanel(26);
  FServerPath := TEdit.Create(FPage);
  FServerPath.Parent := mPanel;
  FServerPath.Left := 0;
  FServerPath.Top := 1;
  FServerPath.Width := FServerPath.ScaleValue(430);
  FServerPath.Anchors := [akLeft, akTop, akRight];
  FServerPath.OnChange := ServerPathChange;
  FServerBrowse := TButton.Create(FPage);
  FServerBrowse.Parent := mPanel;
  FServerBrowse.Caption := '…';
  FServerBrowse.Left := FServerBrowse.ScaleValue(436);
  FServerBrowse.Top := 0;
  FServerBrowse.Width := FServerBrowse.ScaleValue(30);
  FServerBrowse.Anchors := [akTop, akRight];
  FServerBrowse.OnClick := ServerBrowseClick;
  mPanel := AddPanel(18);
  FServerStatus := TLabel.Create(FPage);
  FServerStatus.Parent := mPanel;
  FServerStatus.Left := 0;
  FServerStatus.Top := 0;
  FServerStatus.Font.Color := clGrayText;
  mPanel := AddPanel(18);
  FServerVersion := TLabel.Create(FPage);
  FServerVersion.Parent := mPanel;
  FServerVersion.Left := 0;
  FServerVersion.Top := 0;
  FServerVersion.Font.Color := clGrayText;
  BindCheck('ReloadExternal', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReload)));
  // Änderungen des Servers an nicht geöffneten Dateien (#397).
  BindCheck('OpenForEdits', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsOpenForEdits)));
  // Atlas-Statusfeld (#591).
  BindCheck('StatusField', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStatusField)));
  BindCheck('StatusFieldSummary', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStatusSummary)));
  FStatusToggles := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStatusToggles),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStatusTogglesBoth),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStatusTogglesRight),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStatusTogglesDouble)]);
end;

procedure TAtlasSettingsGeneralPart.Build2;
begin
  FIndexProgress := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexProgress),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexProgressField),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexProgressMenu),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsIndexProgressOff)]);
  FStatusHidden := AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStatusHidden));
  FStatusHidden.NumbersOnly := False;
  FStatusHidden.Width := FStatusHidden.ScaleValue(180);
  // Diagnosemodus (#479); Taste auf der Seite „Tastenkonflikte“.
  FDiagnosticMode := BindCheck('DiagnosticMode',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsDiagnosticMode)));
  // Diagnose-Fenster: Zeiten des Plugins (Reiter Hauptthread, Server, Hintergrund, Hänger).
  BindCheck('DiagnosticPluginTimings',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsDiagnosticPluginTimings)));
  BindText('DiagnosticSlowMs', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsDiagnosticSlowMs)));
  // Menüeintrag „Prozesse am Projekt…“ (#62).
  BindCheck('DiagnosticsProcesses',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsDiagnosticsProcesses)));
  // Fenster „Atlas-Server“ (#1356).
  BindCheck('ServerStatusWindow',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsServerStatusWindow)));
  // Prüfliste der Einrichtung beim Start (#625); aus: nur auf Abruf.
  BindCheck('SetupChecklist', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSetupChecklist)));
  // Hauptschalter der experimentellen Funktionen (#834).
  FExperimentalEnabled := BindCheck('ExperimentalEnabled',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsExperimentalEnabled)));
  // Tastenkürzel-Tipps (#600); Reihenfolge wie TAtlasTipScope: atlas, all.
  BindCheck('ShortcutTips', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsShortcutTips)));
  FShortcutTipsScope := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsShortcutTipsScope),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsShortcutTipsAtlas),
      TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsShortcutTipsAll)]);
end;

procedure TAtlasSettingsGeneralPart.BindMarks;
begin
  FPage.Marks.Bind(FShortcutTipsScope, ['ShortcutTipsScope']);
  FPage.Marks.Bind(FStatusToggles, ['StatusFieldToggles']);
  FPage.Marks.Bind(FIndexProgress, ['IndexProgressPlace']);
  FPage.Marks.Bind(FStatusHidden, ['StatusFieldHidden']);
end;

procedure TAtlasSettingsGeneralPart.Load(const ASettings: TAtlasPluginSettings);
begin
  FServerPath.Text := ASettings.ServerPath;
  ServerPathChange(nil);
  FShortcutTipsScope.Choice := Ord(TAtlasShortcutTips.ScopeOf(ASettings.ShortcutTipsScope));
  if not ASettings.StatusTogglesOnDoubleClick then
  begin
    FStatusToggles.Choice := 1;
  end
  else if not ASettings.StatusTogglesOnRightClick then
  begin
    FStatusToggles.Choice := 2;
  end
  else
  begin
    FStatusToggles.Choice := 0;
  end;
  if SameText(ASettings.IndexProgressPlace, 'menu') then
  begin
    FIndexProgress.Choice := 1;
  end
  else if SameText(ASettings.IndexProgressPlace, 'off') then
  begin
    FIndexProgress.Choice := 2;
  end
  else
  begin
    FIndexProgress.Choice := 0;
  end;
  FStatusHidden.Text := ASettings.StatusFieldHidden;
end;

procedure TAtlasSettingsGeneralPart.Save(var ASettings: TAtlasPluginSettings);
begin
  ASettings.ServerPath := Trim(FServerPath.Text);
  ASettings.ShortcutTipsScope := TAtlasShortcutTips.ScopeName(TAtlasTipScope(EnsureRange(FShortcutTipsScope.Choice,
    Ord(Low(TAtlasTipScope)), Ord(High(TAtlasTipScope)))));
  case FStatusToggles.Choice of
    1:
      ASettings.StatusFieldToggles := 'rightClick';
    2:
      ASettings.StatusFieldToggles := 'doubleClick';
  else
    ASettings.StatusFieldToggles := 'both';
  end;
  case FIndexProgress.Choice of
    1:
      ASettings.IndexProgressPlace := 'menu';
    2:
      ASettings.IndexProgressPlace := 'off';
  else
    ASettings.IndexProgressPlace := 'statusField';
  end;
  ASettings.StatusFieldHidden := Trim(FStatusHidden.Text);
end;

procedure TAtlasSettingsGeneralPart.SetDefaultServerPath(const AValue: string);
begin
  FDefaultServerPath := AValue;
  ServerPathChange(nil);
end;

procedure TAtlasSettingsGeneralPart.ServerPathChange(Sender: TObject);
var
  mPath, mVersion: string;
begin
  mPath := Trim(FServerPath.Text);
  if mPath = '' then
  begin
    mPath := FDefaultServerPath;
  end;
  if mPath = '' then
  begin
    FServerStatus.Caption := '';
  end
  else if FileExists(mPath) then
  begin
    FServerStatus.Caption := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsServerFound, [mPath]);
  end
  else
  begin
    FServerStatus.Caption := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsServerMissing, [mPath]);
  end;
  // Version des Servers (#227): aus der Datei bzw. vom laufenden Server.
  mVersion := '';
  if Assigned(FOnServerVersion) and (mPath <> '') and FileExists(mPath) then
  begin
    mVersion := FOnServerVersion(mPath);
    if mVersion = '' then
    begin
      mVersion := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsServerVersionUnknown);
    end
    else
    begin
      mVersion := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsServerVersion, [mVersion]);
    end;
  end;
  FServerVersion.Caption := mVersion;
end;

procedure TAtlasSettingsGeneralPart.SetOnServerVersion(const AValue: TFunc<string, string>);
begin
  FOnServerVersion := AValue;
  ServerPathChange(nil);
end;

procedure TAtlasSettingsGeneralPart.ServerBrowseClick(Sender: TObject);
var
  mDialog: TOpenDialog;
begin
  mDialog := TOpenDialog.Create(nil);
  try
    mDialog.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsServerFilter);
    mDialog.Options := mDialog.Options + [ofFileMustExist];
    if Trim(FServerPath.Text) <> '' then
    begin
      mDialog.FileName := Trim(FServerPath.Text);
    end
    else if FDefaultServerPath <> '' then
    begin
      mDialog.InitialDir := ExtractFilePath(FDefaultServerPath);
    end;
    if mDialog.Execute then
    begin
      FServerPath.Text := mDialog.FileName;
    end;
  finally
    mDialog.Free;
  end;
end;

{ TAtlasSettingsNotificationsPart }

procedure TAtlasSettingsNotificationsPart.Build;
begin
  // Benachrichtigungszentrale (#601); Taste auf dem Reiter Befehle.
  BindCheck('Notifications', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNotifications)));
  FNotificationsMax := AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNotificationsMax));
  AddNotificationSources;
end;

procedure TAtlasSettingsNotificationsPart.Load(const ASettings: TAtlasPluginSettings);
begin
  FNotificationsMax.Text := IntToStr(ASettings.NotificationsMaxEntries);
  FNotificationsSpec := ASettings.NotificationsSources;
  NotificationSourceChange(nil);
end;

procedure TAtlasSettingsNotificationsPart.Save(var ASettings: TAtlasPluginSettings);
begin
  ASettings.NotificationsMaxEntries := StrToIntDef(Trim(FNotificationsMax.Text), ASettings.NotificationsMaxEntries);
  ASettings.NotificationsSources := TAtlasNotificationSources.Normalize(FNotificationsSpec);
end;

procedure TAtlasSettingsNotificationsPart.BindMarks;
begin
  FPage.Marks.Bind(FNotificationsMax, ['NotificationsMaxEntries']);
  FPage.Marks.Bind(FNotificationSource, ['NotificationsSources']);
end;

procedure TAtlasSettingsNotificationsPart.AddNotificationSources;
var
  mPanel: TWinControl;
  mCaption: TLabel;
  mNames: TArray<string>;
  mSource: string;
begin
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := mPanel;
  mCaption.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNotificationsSources);
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(5);
  mNames := nil;
  for mSource in TAtlasNotificationSources.Known do
  begin
    mNames := mNames + [TAtlasNotificationTexts.SourceCaption(mSource)];
  end;
  FNotificationSource := TAtlasChoiceBox.Create(FPage);
  FNotificationSource.Parent := mPanel;
  FNotificationSource.Left := cFieldLeft;
  FNotificationSource.Top := 1;
  FNotificationSource.Width := FNotificationSource.ScaleValue(180);
  FNotificationSource.SetChoices(mNames);
  FNotificationSource.Choice := 0;
  FNotificationSource.OnChange := NotificationSourceChange;
  // Reihenfolge wie TAtlasNotificationMode: einblenden und sammeln, nur sammeln, aus.
  FNotificationMode := TAtlasChoiceBox.Create(FPage);
  FNotificationMode.Parent := mPanel;
  FNotificationMode.Left := cFieldLeft + FNotificationMode.ScaleValue(186);
  FNotificationMode.Top := 1;
  FNotificationMode.Width := FNotificationMode.ScaleValue(170);
  FNotificationMode.SetChoices([TAtlasStrings.Text(TAtlasTextId.NotificationsModeShow),
    TAtlasStrings.Text(TAtlasTextId.NotificationsModeCollect), TAtlasStrings.Text(TAtlasTextId.NotificationsModeOff)]);
  FNotificationMode.Choice := 0;
  FNotificationMode.OnChange := NotificationModeChange;
end;

procedure TAtlasSettingsNotificationsPart.NotificationSourceChange(Sender: TObject);
var
  mKnown: TArray<string>;
begin
  mKnown := TAtlasNotificationSources.Known;
  if (FNotificationSource.Choice < 0) or (FNotificationSource.Choice > High(mKnown)) then
  begin
    Exit;
  end;
  FNotificationMode.Choice := Ord(TAtlasNotificationSources.ModeIn(FNotificationsSpec,
    mKnown[FNotificationSource.Choice]));
end;

procedure TAtlasSettingsNotificationsPart.NotificationModeChange(Sender: TObject);
var
  mKnown: TArray<string>;
begin
  mKnown := TAtlasNotificationSources.Known;
  if (FNotificationSource.Choice < 0) or (FNotificationSource.Choice > High(mKnown)) or
    (FNotificationMode.Choice < Ord(Low(TAtlasNotificationMode))) or
    (FNotificationMode.Choice > Ord(High(TAtlasNotificationMode))) then
  begin
    Exit;
  end;
  FNotificationsSpec := TAtlasNotificationSources.WithMode(FNotificationsSpec, mKnown[FNotificationSource.Choice],
    TAtlasNotificationMode(FNotificationMode.Choice));
end;

end.
