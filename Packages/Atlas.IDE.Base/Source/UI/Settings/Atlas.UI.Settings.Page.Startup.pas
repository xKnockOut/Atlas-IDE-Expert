unit Atlas.UI.Settings.Page.Startup;

// Reiter „Start“ (abgesicherter Start #722, Updates #495, Fehlerbericht #108), „Rückgängig“ und „Units suchen“
// (#777).

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Start“ (abgesicherter Start #722, Updates #495, Fehlerbericht #108), „Rückgängig“ und „Units
  /// suchen“ (#777).</summary>
  TAtlasSettingsStartupPart = class(TAtlasSettingsPagePart)
  private
    FSafeKey: TAtlasChoiceBox;
    FUndoOnConflict: TAtlasChoiceBox;
    FUndoNewFiles: TAtlasChoiceBox;
    FUnitSearchPathStyle: TAtlasChoiceBox;
    FUnitSearchGroupBy: TAtlasChoiceBox;
    FUnitSearchDefaultScope: TAtlasChoiceBox;
    FVersion: TLabel;
    procedure AddSafeSection;
    procedure AddUndoSection;
    procedure AddUnitSearchSection;
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
  end;

implementation

uses
  System.Math,
  Vcl.Controls,
  Atlas.Core.Diagnostics.SafeMode,
  Atlas.UI.Settings.Bindings,
  Atlas.UI.Settings.Page.Sheets,
  Atlas.UI.Strings,
  Atlas.Core.Product.Version,
  Atlas.Core.Updates.Check,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Undo.Names;

const
  // Reihenfolge der Auswahllisten von „Units suchen“ (#777) wie die Werte der Einstellungen.
  UnitSearchPathStyles: array[0..2] of string = ('relative', 'compact', 'absolute');
  UnitSearchGroupings: array[0..2] of string = ('project', 'folder', 'none');
  UnitSearchScopes: array[0..3] of string = ('group', 'project', 'searchPath', 'library');

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
  AddModuleSwitch('SearchEnabled');
  AddUnitSearchSection;
end;

procedure TAtlasSettingsStartupPart.BindMarks;
begin
  FPage.Marks.Bind(FSafeKey, ['SafeStartupKey']);
  FPage.Marks.Bind(FUndoOnConflict, ['UndoMultiFileOnConflict']);
  FPage.Marks.Bind(FUndoNewFiles, ['UndoMultiFileNewFiles']);
  FPage.Marks.Bind(FUnitSearchPathStyle, ['UnitSearchPathStyle']);
  FPage.Marks.Bind(FUnitSearchGroupBy, ['UnitSearchGroupBy']);
  FPage.Marks.Bind(FUnitSearchDefaultScope, ['UnitSearchDefaultScope']);
end;

procedure TAtlasSettingsStartupPart.AddSafeSection;
var
  Panel: TWinControl;
  mCaption: TLabel;
begin
  // Abgesicherter Start nach einem Absturz (#722).
  AddTitle(TAtlasTextId.SettingsSafeTitle);
  BindCheck('SafeAskAfterCrash', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSafeAsk)));
  BindCheck('SafeAutoAfterRepeatedCrash', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSafeAuto)));
  Panel := AddPanel(26);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := Panel;
  mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsSafeKey);
  mCaption.Left := 0;
  mCaption.Top := 5;
  FSafeKey := TAtlasChoiceBox.Create(FPage);
  FSafeKey.Parent := Panel;
  FSafeKey.Left := FieldLeft;
  FSafeKey.Top := 1;
  FSafeKey.Width := 120;
  // Reihenfolge wie TAtlasStartupKey ohne None vorn: Umschalt, Strg, keine.
  FSafeKey.SetChoices([TAtlasStrings.Text(TAtlasTextId.SettingsSafeKeyShift),
    TAtlasStrings.Text(TAtlasTextId.SettingsSafeKeyCtrl), TAtlasStrings.Text(TAtlasTextId.SettingsSafeKeyNone)]);
  BindText('SafeStartupTimeoutMs', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSafeTimeout)));
  BindText('SafeKeepSettingsHistory', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSafeHistory)));
end;

procedure TAtlasSettingsStartupPart.AddUnitSearchSection;
begin
  BindCheck('UnitSearchEnabled', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchEnabled)));
  BindCheck('UnitSearchReplaceIdeDialog', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchReplace)));
  BindCheck('UnitSearchReplaceUseUnitDialog', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchReplaceUseUnit)));
  BindCheck('UnitSearchReplaceFormsDialog', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchReplaceForms)));
  BindKey('UnitSearchKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchKey)));
  FUnitSearchPathStyle := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPathStyle),
    [TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPathRelative),
    TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPathCompact),
    TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPathAbsolute)]);
  FUnitSearchGroupBy := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchGroupBy),
    [TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupProject), TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupFolder),
    TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupNone)]);
  BindCheck('UnitSearchRememberCollapsed', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchRememberCollapsed)));
  BindCheck('UnitSearchFilters', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchFilters)));
  FUnitSearchDefaultScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchDefaultScope),
    [TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginGroup), TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginActive),
    TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginSearchPath),
    TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginLibrary)]);
  BindCheck('UnitSearchFilterSyntax', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchFilterSyntax)));
  BindCheck('UnitSearchFormCaptions', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchFormCaptions)));
  BindCheck('UnitSearchPreview', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPreview)));
  BindCheck('UnitSearchPreviewForm', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPreviewForm)));
  BindCheck('UnitSearchPreviewUsedBy', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPreviewUsedBy)));
  BindCheck('UnitSearchPreviewAutoCollapse', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPreviewAutoCollapse)));
  BindCheck('UnitSearchMultiSelect', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchMultiSelect)));
  BindCheck('UnitSearchActions', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchActions)));
  BindCheck('UnitSearchActionsAddUses', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchAddUses)));
  // Datei und Symbol schnell öffnen (#503).
  AddTitle(TAtlasTextId.QuickOpenTitle);
  BindCheck('QuickOpen', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickOpen)));
  BindCheck('QuickOpenLibrary', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickOpenLibrary)));
  BindKey('QuickOpenKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsQuickOpenKey)));
  // Suchleiste im Editor (#878).
  AddTitle(TAtlasTextId.SettingsSearchTitle);
  BindCheck('SearchReplaceIde', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSearchReplace)));
  BindCheck('SearchResultsInMessages', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSearchMessages)));
  // Ersetzen, Regex, Verlauf und Bereiche über Dateien (#893).
  BindCheck('SearchReplace', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSearchReplaceBar)));
  BindCheck('SearchRegex', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSearchRegex)));
  BindText('SearchHistory', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSearchHistory)));
  BindCheck('SearchMultiFile', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSearchMultiFile)));
  BindCheck('SearchFromFirstHit', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSearchFromFirst)));
end;

procedure TAtlasSettingsStartupPart.AddUndoSection;
begin
  // Atlas-Änderungen über mehrere Dateien zurücknehmen (#721).
  AddTitle(TAtlasTextId.SettingsUndoTitle);
  BindCheck('UndoMultiFile', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUndoEnabled)));
  BindText('UndoMultiFileDepth', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsUndoDepth)));
  BindCheck('UndoMultiFilePersist', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUndoPersist)));
  BindText('UndoMultiFileMaxSizeMb', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsUndoMaxSize)));
  // Reihenfolge wie TAtlasUndoConflictMode und TAtlasNewFilesMode.
  FUndoOnConflict := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsUndoOnConflict),
    [TAtlasStrings.Text(TAtlasTextId.SettingsUndoPartial), TAtlasStrings.Text(TAtlasTextId.SettingsUndoAbort)]);
  FUndoNewFiles := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsUndoNewFiles),
    [TAtlasStrings.Text(TAtlasTextId.SettingsUndoRecycle), TAtlasStrings.Text(TAtlasTextId.SettingsUndoDelete),
    TAtlasStrings.Text(TAtlasTextId.SettingsUndoKeep)]);
end;

procedure TAtlasSettingsStartupPart.AddUpdatesSection;
var
  Panel: TWinControl;
begin
  // Version und Update-Prüfung (#495).
  AddTitle(TAtlasTextId.SettingsUpdatesTitle);
  Panel := AddPanel(20);
  FVersion := TLabel.Create(FPage);
  FVersion.Parent := Panel;
  FVersion.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsVersion, [TAtlasPluginVersion.Version,
    TAtlasUpdates.IdeVersion]);
  FVersion.Left := 0;
  FVersion.Top := 2;
  BindCheck('UpdatesCheck', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUpdatesCheck)));
end;

procedure TAtlasSettingsStartupPart.AddBugReportSection;
begin
  // Fehlerbericht (#108).
  AddTitle(TAtlasTextId.SettingsBugReportTitle);
  BindCheck('BugReportAnonymize', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBugReportAnonymize)));
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
  FUnitSearchPathStyle.Choice := TAtlasSettingsBindings.ChoiceOf(ASettings.UnitSearchPathStyle, UnitSearchPathStyles);
  FUnitSearchGroupBy.Choice := TAtlasSettingsBindings.ChoiceOf(ASettings.UnitSearchGroupBy, UnitSearchGroupings);
  FUnitSearchDefaultScope.Choice := TAtlasSettingsBindings.ChoiceOf(ASettings.UnitSearchDefaultScope, UnitSearchScopes);
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
  ASettings.UnitSearchPathStyle := UnitSearchPathStyles[EnsureRange(FUnitSearchPathStyle.Choice, 0, 2)];
  ASettings.UnitSearchGroupBy := UnitSearchGroupings[EnsureRange(FUnitSearchGroupBy.Choice, 0, 2)];
  ASettings.UnitSearchDefaultScope := UnitSearchScopes[EnsureRange(FUnitSearchDefaultScope.Choice, 0, 3)];
end;

end.
