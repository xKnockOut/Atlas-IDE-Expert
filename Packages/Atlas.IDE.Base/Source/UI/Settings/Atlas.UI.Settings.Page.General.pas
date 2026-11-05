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
    property ServerVersion: TLabel read FServerVersion;
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
    property NotificationsSpec: string read FNotificationsSpec;
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
  Atlas.Core.Commands.ShortcutTips,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Sources,
  Atlas.UI.Notifications.Window;

{ TAtlasSettingsGeneralPart }

procedure TAtlasSettingsGeneralPart.Build;
var
  Panel: TWinControl;
  Title: TLabel;
begin
  AddSheet(TAtlasTextId.SettingsTabGeneral);
  BindCheck('Enabled', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEnabled)));
  // Wo der Server liegt; leer gilt der Standard neben dem Plugin.
  Panel := AddPanel(20);
  Title := TLabel.Create(FPage);
  Title.Parent := Panel;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsServerPath);
  Title.Left := 0;
  Title.Top := 3;
  // Pfad in eigener Zeile: Die Beschriftung ist lang, das Feld braucht die Breite.
  Panel := AddPanel(26);
  FServerPath := TEdit.Create(FPage);
  FServerPath.Parent := Panel;
  FServerPath.Left := 0;
  FServerPath.Top := 1;
  FServerPath.Width := 430;
  FServerPath.Anchors := [akLeft, akTop, akRight];
  FServerPath.OnChange := ServerPathChange;
  FServerBrowse := TButton.Create(FPage);
  FServerBrowse.Parent := Panel;
  FServerBrowse.Caption := '…';
  FServerBrowse.Left := 436;
  FServerBrowse.Top := 0;
  FServerBrowse.Width := 30;
  FServerBrowse.Anchors := [akTop, akRight];
  FServerBrowse.OnClick := ServerBrowseClick;
  Panel := AddPanel(18);
  FServerStatus := TLabel.Create(FPage);
  FServerStatus.Parent := Panel;
  FServerStatus.Left := 0;
  FServerStatus.Top := 0;
  FServerStatus.Font.Color := clGrayText;
  Panel := AddPanel(18);
  FServerVersion := TLabel.Create(FPage);
  FServerVersion.Parent := Panel;
  FServerVersion.Left := 0;
  FServerVersion.Top := 0;
  FServerVersion.Font.Color := clGrayText;
  BindCheck('ReloadExternal', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReload)));
  // Änderungen des Servers an nicht geöffneten Dateien (#397).
  BindCheck('OpenForEdits', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOpenForEdits)));
  // Atlas-Statusfeld (#591).
  BindCheck('StatusField', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStatusField)));
  BindCheck('StatusFieldSummary', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStatusSummary)));
  FStatusToggles := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsStatusToggles),
    [TAtlasStrings.Text(TAtlasTextId.SettingsStatusTogglesBoth),
    TAtlasStrings.Text(TAtlasTextId.SettingsStatusTogglesRight),
    TAtlasStrings.Text(TAtlasTextId.SettingsStatusTogglesDouble)]);
end;

procedure TAtlasSettingsGeneralPart.Build2;
begin
  FIndexProgress := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsIndexProgress),
    [TAtlasStrings.Text(TAtlasTextId.SettingsIndexProgressField),
    TAtlasStrings.Text(TAtlasTextId.SettingsIndexProgressMenu),
    TAtlasStrings.Text(TAtlasTextId.SettingsIndexProgressOff)]);
  FStatusHidden := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsStatusHidden));
  FStatusHidden.NumbersOnly := False;
  FStatusHidden.Width := 180;
  // Diagnosemodus (#479); Taste auf der Seite „Tastenkonflikte“.
  FDiagnosticMode := BindCheck('DiagnosticMode', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDiagnosticMode)));
  // Diagnose-Fenster: Zeiten des Plugins (Reiter Hauptthread, Server, Hintergrund, Hänger).
  BindCheck('DiagnosticPluginTimings', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDiagnosticPluginTimings)));
  BindText('DiagnosticSlowMs', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsDiagnosticSlowMs)));
  // Menüeintrag „Prozesse am Projekt…“ (#62).
  BindCheck('DiagnosticsProcesses', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDiagnosticsProcesses)));
  // Fenster „Atlas-Server“ (#1356).
  BindCheck('ServerStatusWindow', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsServerStatusWindow)));
  // Prüfliste der Einrichtung beim Start (#625); aus: nur auf Abruf.
  BindCheck('SetupChecklist', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSetupChecklist)));
  // Hauptschalter der experimentellen Funktionen (#834).
  FExperimentalEnabled := BindCheck('ExperimentalEnabled', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExperimentalEnabled)));
  // Tastenkürzel-Tipps (#600); Reihenfolge wie TAtlasTipScope: atlas, all.
  BindCheck('ShortcutTips', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsShortcutTips)));
  FShortcutTipsScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsShortcutTipsScope),
    [TAtlasStrings.Text(TAtlasTextId.SettingsShortcutTipsAtlas), TAtlasStrings.Text(TAtlasTextId.SettingsShortcutTipsAll)]);
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
  Path, Version: string;
begin
  Path := Trim(FServerPath.Text);
  if Path = '' then
  begin
    Path := FDefaultServerPath;
  end;
  if Path = '' then
  begin
    FServerStatus.Caption := '';
  end
  else if FileExists(Path) then
  begin
    FServerStatus.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsServerFound, [Path]);
  end
  else
  begin
    FServerStatus.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsServerMissing, [Path]);
  end;
  // Version des Servers (#227): aus der Datei bzw. vom laufenden Server.
  Version := '';
  if Assigned(FOnServerVersion) and (Path <> '') and FileExists(Path) then
  begin
    Version := FOnServerVersion(Path);
    if Version = '' then
    begin
      Version := TAtlasStrings.Text(TAtlasTextId.SettingsServerVersionUnknown);
    end
    else
    begin
      Version := TAtlasStrings.Fmt(TAtlasTextId.SettingsServerVersion, [Version]);
    end;
  end;
  FServerVersion.Caption := Version;
end;

procedure TAtlasSettingsGeneralPart.SetOnServerVersion(const AValue: TFunc<string, string>);
begin
  FOnServerVersion := AValue;
  ServerPathChange(nil);
end;

procedure TAtlasSettingsGeneralPart.ServerBrowseClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsServerFilter);
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    if Trim(FServerPath.Text) <> '' then
    begin
      Dialog.FileName := Trim(FServerPath.Text);
    end
    else if FDefaultServerPath <> '' then
    begin
      Dialog.InitialDir := ExtractFilePath(FDefaultServerPath);
    end;
    if Dialog.Execute then
    begin
      FServerPath.Text := Dialog.FileName;
    end;
  finally
    Dialog.Free;
  end;
end;

{ TAtlasSettingsNotificationsPart }

procedure TAtlasSettingsNotificationsPart.Build;
begin
  // Benachrichtigungszentrale (#601); Taste auf dem Reiter Befehle.
  BindCheck('Notifications', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsNotifications)));
  FNotificationsMax := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsNotificationsMax));
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
  Panel: TWinControl;
  mCaption: TLabel;
  Names: TArray<string>;
  Source: string;
begin
  Panel := AddPanel(26);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := Panel;
  mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsNotificationsSources);
  mCaption.Left := 0;
  mCaption.Top := 5;
  Names := nil;
  for Source in TAtlasNotificationSources.Known do
  begin
    Names := Names + [TAtlasNotificationTexts.SourceCaption(Source)];
  end;
  FNotificationSource := TAtlasChoiceBox.Create(FPage);
  FNotificationSource.Parent := Panel;
  FNotificationSource.Left := FieldLeft;
  FNotificationSource.Top := 1;
  FNotificationSource.Width := 180;
  FNotificationSource.SetChoices(Names);
  FNotificationSource.Choice := 0;
  FNotificationSource.OnChange := NotificationSourceChange;
  // Reihenfolge wie TAtlasNotificationMode: einblenden und sammeln, nur sammeln, aus.
  FNotificationMode := TAtlasChoiceBox.Create(FPage);
  FNotificationMode.Parent := Panel;
  FNotificationMode.Left := FieldLeft + 186;
  FNotificationMode.Top := 1;
  FNotificationMode.Width := 170;
  FNotificationMode.SetChoices([TAtlasStrings.Text(TAtlasTextId.NotificationsModeShow),
    TAtlasStrings.Text(TAtlasTextId.NotificationsModeCollect), TAtlasStrings.Text(TAtlasTextId.NotificationsModeOff)]);
  FNotificationMode.Choice := 0;
  FNotificationMode.OnChange := NotificationModeChange;
end;

procedure TAtlasSettingsNotificationsPart.NotificationSourceChange(Sender: TObject);
var
  Known: TArray<string>;
begin
  Known := TAtlasNotificationSources.Known;
  if (FNotificationSource.Choice < 0) or (FNotificationSource.Choice > High(Known)) then
  begin
    Exit;
  end;
  FNotificationMode.Choice := Ord(TAtlasNotificationSources.ModeIn(FNotificationsSpec,
    Known[FNotificationSource.Choice]));
end;

procedure TAtlasSettingsNotificationsPart.NotificationModeChange(Sender: TObject);
var
  Known: TArray<string>;
begin
  Known := TAtlasNotificationSources.Known;
  if (FNotificationSource.Choice < 0) or (FNotificationSource.Choice > High(Known)) or
    (FNotificationMode.Choice < Ord(Low(TAtlasNotificationMode))) or
    (FNotificationMode.Choice > Ord(High(TAtlasNotificationMode))) then
  begin
    Exit;
  end;
  FNotificationsSpec := TAtlasNotificationSources.WithMode(FNotificationsSpec, Known[FNotificationSource.Choice],
    TAtlasNotificationMode(FNotificationMode.Choice));
end;

end.
