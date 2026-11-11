unit Atlas.UI.Settings.Page.Startup;

// Reiter „Start“ (abgesicherter Start #722, Updates #495 und #1519, Fehlerbericht #108), „Rückgängig“ und
// „Units suchen“ (hier nur schnell öffnen #503; die Units-Suche #777 baut ihr Modul als Abschnitt dazu).

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Start“ (abgesicherter Start #722, Updates #495, Fehlerbericht #108), „Rückgängig“ und „Units
  /// suchen“ (schnell öffnen #503).</summary>
  TAtlasSettingsStartupPart = class(TAtlasSettingsPagePart)
  private
    FSafeKey: TAtlasChoiceBox;
    FUndoOnConflict: TAtlasChoiceBox;
    FUndoNewFiles: TAtlasChoiceBox;
    FVersion: TLabel;
    FUpdatesInstall: TAtlasChoiceBox;
    FUpdatesChannel: TAtlasChoiceBox;
    FUpdatesNewModules: TAtlasChoiceBox;
    procedure AddSafeSection;
    procedure AddUndoSection;
    procedure AddQuickOpenSection;
    procedure AddUpdatesSection;
    procedure AddBugReportSection;
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    property SafeKey: TAtlasChoiceBox read FSafeKey;
    property UndoOnConflict: TAtlasChoiceBox read FUndoOnConflict;
    property UndoNewFiles: TAtlasChoiceBox read FUndoNewFiles;
    property VersionLabel: TLabel read FVersion;
    property UpdatesInstall: TAtlasChoiceBox read FUpdatesInstall;
  end;

implementation

uses
  System.Math,
  Vcl.Controls,
  Atlas.Core.Diagnostics.SafeMode,
  Atlas.UI.Settings.Bindings,
  Atlas.UI.Settings.Page.Sheets,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings,
  Atlas.UI.Updates.Strings,
  Atlas.UI.Diagnostics.Strings,
  Atlas.Core.Product.Version,
  Atlas.Core.Updates.Check,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Undo.Names;

const
  // Auswahllisten der Updates (#1519) in der Reihenfolge der Anzeige.
  cUpdatesInstallModes: array[0..2] of string = ('ask', 'auto', 'off');
  cUpdatesChannels: array[0..1] of string = ('stable', 'prerelease');
  cUpdatesNewModulesModes: array[0..2] of string = ('ask', 'install', 'skip');

{ TAtlasSettingsStartupPart }

procedure TAtlasSettingsStartupPart.Build;
begin
  // Abgesicherter Start, Updates und Fehlerbericht (#722, #495, #108).
  AddSheet(TAtlasTextId.SettingsTabStartup);
  AddSafeSection;
  AddUpdatesSection;
  AddBugReportSection;

  AddSheet(TAtlasTextId.SettingsTabUndo);
  AddUndoSection;

  AddSheet(TAtlasTextId.SettingsTabUnitSearch);
  AddQuickOpenSection;
end;

procedure TAtlasSettingsStartupPart.BindMarks;
begin
  FPage.Marks.Bind(FSafeKey, ['SafeStartupKey']);
  FPage.Marks.Bind(FUndoOnConflict, ['UndoMultiFileOnConflict']);
  FPage.Marks.Bind(FUndoNewFiles, ['UndoMultiFileNewFiles']);
  FPage.Marks.Bind(FUpdatesInstall, ['UpdatesInstall']);
  FPage.Marks.Bind(FUpdatesChannel, ['UpdatesChannel']);
  FPage.Marks.Bind(FUpdatesNewModules, ['UpdatesNewModules']);
end;

procedure TAtlasSettingsStartupPart.AddSafeSection;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  // Abgesicherter Start nach einem Absturz (#722).
  AddTitle(TAtlasTextId.SettingsSafeTitle);
  BindCheck('SafeAskAfterCrash', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSafeAsk)));
  BindCheck('SafeAutoAfterRepeatedCrash', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSafeAuto)));
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := mPanel;
  mCaption.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSafeKey);
  mCaption.Left := 0;
  mCaption.Top := 5;
  FSafeKey := TAtlasChoiceBox.Create(FPage);
  FSafeKey.Parent := mPanel;
  FSafeKey.Left := cFieldLeft;
  FSafeKey.Top := 1;
  FSafeKey.Width := 120;
  // Reihenfolge wie TAtlasStartupKey ohne None vorn: Umschalt, Strg, keine.
  FSafeKey.SetChoices([TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSafeKeyShift),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSafeKeyCtrl),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSafeKeyNone)]);
  BindText('SafeStartupTimeoutMs', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSafeTimeout)));
  BindText('SafeKeepSettingsHistory', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSafeHistory)));
end;

procedure TAtlasSettingsStartupPart.AddQuickOpenSection;
begin
  // Datei und Symbol schnell öffnen (#503); die Units-Suche baut ihr Modul als Abschnitt in diesen Reiter (#1455).
  AddTitle(TAtlasTextId.QuickOpenTitle);
  BindCheck('QuickOpen', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsQuickOpen)));
  BindCheck('QuickOpenLibrary', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsQuickOpenLibrary)));
  BindKey('QuickOpenKey', AddKey(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsQuickOpenKey)));
end;

procedure TAtlasSettingsStartupPart.AddUndoSection;
begin
  // Atlas-Änderungen über mehrere Dateien zurücknehmen (#721).
  AddTitle(TAtlasTextId.SettingsUndoTitle);
  BindCheck('UndoMultiFile', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUndoEnabled)));
  BindText('UndoMultiFileDepth', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUndoDepth)));
  BindCheck('UndoMultiFilePersist', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUndoPersist)));
  BindText('UndoMultiFileMaxSizeMb', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUndoMaxSize)));
  // Reihenfolge wie TAtlasUndoConflictMode und TAtlasNewFilesMode.
  FUndoOnConflict := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUndoOnConflict),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUndoPartial),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUndoAbort)]);
  FUndoNewFiles := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUndoNewFiles),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUndoRecycle),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUndoDelete),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUndoKeep)]);
end;

procedure TAtlasSettingsStartupPart.AddUpdatesSection;
var
  mPanel: TWinControl;
begin
  // Version und Update-Prüfung (#495).
  AddTitle(TAtlasTextId.SettingsUpdatesTitle);
  mPanel := AddPanel(20);
  FVersion := TLabel.Create(FPage);
  FVersion.Parent := mPanel;
  FVersion.Caption := TAtlasSettingsStrings.Fmt(TAtlasSettingsTextId.SettingsVersion, [TAtlasPluginVersion.cVersion,
    TAtlasUpdates.IdeVersion]);
  FVersion.Left := 0;
  FVersion.Top := 2;
  BindCheck('UpdatesCheck', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUpdatesCheck)));
  // Update installieren (#1519): anbieten, ohne Frage vorbereiten oder nur melden; Kanal und neue Module.
  FUpdatesInstall := AddChoice(TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.SettingsUpdatesInstall),
    [TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.SettingsUpdatesInstallAsk),
    TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.SettingsUpdatesInstallAuto),
    TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.SettingsUpdatesInstallOff)]);
  FUpdatesChannel := AddChoice(TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.SettingsUpdatesChannel),
    [TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.SettingsUpdatesChannelStable),
    TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.SettingsUpdatesChannelPrerelease)]);
  FUpdatesNewModules := AddChoice(TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.SettingsUpdatesNewModules),
    [TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.SettingsUpdatesNewModulesAsk),
    TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.SettingsUpdatesNewModulesInstall),
    TAtlasUpdatesStrings.Text(TAtlasUpdatesTextId.SettingsUpdatesNewModulesSkip)]);
end;

procedure TAtlasSettingsStartupPart.AddBugReportSection;
begin
  // Fehlerbericht (#108).
  AddTitle(TAtlasTextId.SettingsBugReportTitle);
  BindCheck('BugReportAnonymize',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBugReportAnonymize)));
  // Protokoll des Plugins mit Klarnamen (#1478, diagnostics.log.names); Vorgabe anonym.
  BindCheck('LogNames', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsLogNames)));
  // Kommandozeilen-Compiler prüfen (#1822, diagnostics.editionCheck).
  BindCheck('DiagnosticsEditionCheck',
    AddCheck(TAtlasDiagnosticsStrings.Text(TAtlasDiagnosticsTextId.SettingsEditionCheck)));
end;

procedure TAtlasSettingsStartupPart.Load(const ASettings: TAtlasPluginSettings);
begin
  case TAtlasSafeMode.KeyOf(ASettings.SafeStartupKey) of
    TAtlasStartupKey.Ctrl:
      FSafeKey.Choice := 1;
    TAtlasStartupKey.None:
      FSafeKey.Choice := 2;
  else
    FSafeKey.Choice := 0;
  end;
  FUndoOnConflict.Choice := Ord(TAtlasUndoNames.ParseConflictMode(ASettings.UndoMultiFileOnConflict));
  FUndoNewFiles.Choice := Ord(TAtlasUndoNames.ParseNewFiles(ASettings.UndoMultiFileNewFiles));
  FUpdatesInstall.Choice := TAtlasSettingsBindings.ChoiceOf(ASettings.UpdatesInstall, cUpdatesInstallModes);
  FUpdatesChannel.Choice := TAtlasSettingsBindings.ChoiceOf(ASettings.UpdatesChannel, cUpdatesChannels);
  FUpdatesNewModules.Choice := TAtlasSettingsBindings.ChoiceOf(ASettings.UpdatesNewModules, cUpdatesNewModulesModes);
end;

procedure TAtlasSettingsStartupPart.Save(var ASettings: TAtlasPluginSettings);
begin
  case FSafeKey.Choice of
    1:
      ASettings.SafeStartupKey := TAtlasSafeMode.KeyText(TAtlasStartupKey.Ctrl);
    2:
      ASettings.SafeStartupKey := TAtlasSafeMode.KeyText(TAtlasStartupKey.None);
  else
    ASettings.SafeStartupKey := TAtlasSafeMode.KeyText(TAtlasStartupKey.Shift);
  end;
  ASettings.UndoMultiFileOnConflict := TAtlasUndoNames.ConflictModeName(TAtlasUndoConflictMode(
    Max(0, FUndoOnConflict.Choice)));
  ASettings.UndoMultiFileNewFiles := TAtlasUndoNames.NewFilesName(TAtlasNewFilesMode(Max(0, FUndoNewFiles.Choice)));
  ASettings.UpdatesInstall := cUpdatesInstallModes[EnsureRange(FUpdatesInstall.Choice, 0, 2)];
  ASettings.UpdatesChannel := cUpdatesChannels[EnsureRange(FUpdatesChannel.Choice, 0, 1)];
  ASettings.UpdatesNewModules := cUpdatesNewModulesModes[EnsureRange(FUpdatesNewModules.Choice, 0, 2)];
end;

end.
