unit Atlas.UI.Settings.Page;

// Seite „Atlas“ unter Tools › Optionen › Drittanbieter (#227, Teil
// Vervollständigung). Reine VCL, im Code aufgebaut: Steuerelemente
// untereinander, die IDE skaliert sie mit dem Dialog. Die DFM ist leer;
// TCustomFrame.Create verlangt für abgeleitete Frames eine Ressource. Laden und Speichern über
// TAtlasPluginSettings; die IDE-Schicht liest und schreibt die Registry.
// Die Tastenkürzel stehen auf der eigenen Seite „Tastenkonflikte“
// (Atlas.UI.Settings.Keys, #494). Unten zeigt die Seite, was die Sicherung
// nach wiederholten Fehlern abgeschaltet hat, und schaltet es wieder ein (#493).
// Abschnitt Symbolindex (#492): Verwendungen an/aus, Speichergrenze, Kennzahlen
// (Units, Deklarationen, Größe, letzte Aktualisierung), „Index neu aufbauen“ und
// „Index löschen“. Die Seite kennt den Server nicht; die IDE-Schicht liefert
// Texte und führt die Befehle über OnIndexMetrics, OnIndexRebuild, OnIndexClear aus.

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
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.SafeMode,
  Atlas.UI.Strings;

type
  TAtlasSettingsPage = class(TFrame)
  private
    FEnabled: TCheckBox;
    FServerPath: TEdit;
    FServerBrowse: TButton;
    FServerStatus: TLabel;
    FServerVersion: TLabel;
    FOnServerVersion: TFunc<string, string>;
    FDefaultServerPath: string;
    FRowsLabel: TLabel;
    FRows: TEdit;
    FRowsUpDown: TUpDown;
    FPanelCollapsed: TCheckBox;
    FAutoParentheses: TCheckBox;
    FFixCase: TCheckBox;
    // ARG-046 (#227): Commit-Zeichen, uses, Parameter-Hint, Verzögerung, automatische Breite.
    FCommitChars: TCheckBox;
    FAutoUses: TCheckBox;
    FParameterHints: TCheckBox;
    FOpenDelay: TEdit;
    FAutoWidth: TCheckBox;
    FFilterChips: TCheckBox;
    FLearning: TCheckBox;
    FGroupInherited: TCheckBox;
    FPreview: TCheckBox;
    FHoverTooltip: TCheckBox;
    FXmlDocFull: TCheckBox;
    FXmlDocMaxLines: TEdit;
    FHangThreshold: TEdit;
    FHangHint: TCheckBox;
    FProviderTimeLimit: TEdit;
    FFuseList: TListBox;
    FFuseEnableSelected: TButton;
    FFuseEnableAll: TButton;
    FReloadExternal: TCheckBox;
    FPairColors: TCheckBox;
    FInactiveDim: TCheckBox;
    FOpenForEdits: TCheckBox;
    FInlayHints: TCheckBox;
    FPairGuides: TCheckBox;
    FProblems: TCheckBox;
    FStatusField: TCheckBox;
    FStatusSummary: TCheckBox;
    FStatusHidden: TEdit;
    FIndexGroup: TCheckBox;
    FIndexSearch: TCheckBox;
    FIndexLibrary: TCheckBox;
    FIndexUsages: TCheckBox;
    FMemoryBudget: TEdit;
    FIndexInfo: TLabel;
    FIndexRefresh: TButton;
    FIndexRebuild: TButton;
    FIndexClear: TButton;
    FOnIndexMetrics: TFunc<string>;
    FOnIndexRebuild: TFunc<string>;
    FOnIndexClear: TFunc<string>;
    FConfirmClear: TFunc<Boolean>;
    FCheckOnSave: TCheckBox;
    FCheckDelay: TEdit;
    FCheckMax: TEdit;
    FActionsKey: TEdit;
    FExpandKey: TEdit;
    FShrinkKey: TEdit;
    FImplementationKey: TEdit;
    FTypeDefinitionKey: TEdit;
    FUndoKey: TEdit;
    FRedoKey: TEdit;
    FEditorKeysPriority: TCheckBox;
    FSlashCommands: TCheckBox;
    FSnippets: TCheckBox;
    FImportIdeTemplates: TCheckBox;
    FSafeAsk: TCheckBox;
    FSafeAuto: TCheckBox;
    FSafeKey: TComboBox;
    FSafeTimeout: TEdit;
    FSafeHistory: TEdit;
    FUndoEnabled: TCheckBox;
    FUndoDepth: TEdit;
    FUndoPersist: TCheckBox;
    FUndoMaxSize: TEdit;
    FUndoOnConflict: TComboBox;
    FUndoNewFiles: TComboBox;
    FUpdatesCheck: TCheckBox;
    FBugReportAnonymize: TCheckBox;
    FVersion: TLabel;
    FResetHistory: TButton;
    FResetWidths: TButton;
    FHangTest: TButton;
    FWidths: TAtlasPluginSettings;
    FNextTop: Integer;
    FOnResetHistory: TProc;
    function AddCheck(const ACaption: string): TCheckBox;
    function AddPanel(AHeight: Integer): TPanel;
    function AddNumber(const ACaption: string): TEdit;
    function AddChoice(const ACaption: string; const AItems: array of string): TComboBox;
    /// <summary>Kürzel ohne eigenen Vorrang; der gilt für die Gruppe (#399). Palette und Prüfung stehen auf der
    /// Seite „Tastenkonflikte“ (#494).</summary>
    function AddKey(const ACaption: string): TEdit;
    procedure ResetHistoryClick(Sender: TObject);
    procedure ResetWidthsClick(Sender: TObject);
    procedure HangTestClick(Sender: TObject);
    procedure FuseEnableSelectedClick(Sender: TObject);
    procedure FuseEnableAllClick(Sender: TObject);
    procedure AddFuseSection;
    procedure AddIndexSection;
    procedure AddSafeSection;
    procedure AddUndoSection;
    procedure AddUpdatesSection;
    procedure AddBugReportSection;
    procedure IndexRefreshClick(Sender: TObject);
    procedure IndexRebuildClick(Sender: TObject);
    procedure IndexClearClick(Sender: TObject);
    procedure ServerBrowseClick(Sender: TObject);
    procedure ServerPathChange(Sender: TObject);
    procedure SetDefaultServerPath(const AValue: string);
    procedure SetOnServerVersion(const AValue: TFunc<string, string>);
    procedure AutoWidthClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFrom(const ASettings: TAtlasPluginSettings);
    procedure SaveTo(var ASettings: TAtlasPluginSettings);
    /// <summary>Liste der abgeschalteten Features und Quellen neu lesen (#493).</summary>
    procedure RefreshFuse;
    /// <summary>Zum Testen: Liste und Schaltflächen der Sicherung.</summary>
    property FuseList: TListBox read FFuseList;
    property FuseEnableSelected: TButton read FFuseEnableSelected;
    property FuseEnableAll: TButton read FFuseEnableAll;
    /// <summary>Kennzahlen des Index neu holen und anzeigen (#492).</summary>
    procedure RefreshIndex;
    /// <summary>Zum Testen: Kennzahlen und Schaltflächen des Index.</summary>
    property IndexInfo: TLabel read FIndexInfo;
    property IndexRebuild: TButton read FIndexRebuild;
    property IndexClear: TButton read FIndexClear;
    /// <summary>Zum Testen: Einstellungen des Statusfelds (#591).</summary>
    property StatusField: TCheckBox read FStatusField;
    property StatusSummary: TCheckBox read FStatusSummary;
    property StatusHidden: TEdit read FStatusHidden;
    /// <summary>Zum Testen: abgesicherter Start (#722).</summary>
    property SafeAsk: TCheckBox read FSafeAsk;
    property SafeAuto: TCheckBox read FSafeAuto;
    property SafeKey: TComboBox read FSafeKey;
    property SafeTimeout: TEdit read FSafeTimeout;
    property SafeHistory: TEdit read FSafeHistory;
    /// <summary>Zum Testen: Atlas-Änderungen über mehrere Dateien (#721).</summary>
    property UndoEnabled: TCheckBox read FUndoEnabled;
    property UndoDepth: TEdit read FUndoDepth;
    property UndoPersist: TCheckBox read FUndoPersist;
    property UndoMaxSize: TEdit read FUndoMaxSize;
    property UndoOnConflict: TComboBox read FUndoOnConflict;
    property UndoNewFiles: TComboBox read FUndoNewFiles;
    property UndoKey: TEdit read FUndoKey;
    property RedoKey: TEdit read FRedoKey;
    property UpdatesCheck: TCheckBox read FUpdatesCheck;
    property BugReportAnonymize: TCheckBox read FBugReportAnonymize;
    property VersionLabel: TLabel read FVersion;
    /// <summary>Kennzahlen als Text; nil = nicht verfügbar.</summary>
    property OnIndexMetrics: TFunc<string> read FOnIndexMetrics write FOnIndexMetrics;
    /// <summary>„Index neu aufbauen“ bzw. „Index löschen“ ausführen; Ergebnis als Meldung.</summary>
    property OnIndexRebuild: TFunc<string> read FOnIndexRebuild write FOnIndexRebuild;
    property OnIndexClear: TFunc<string> read FOnIndexClear write FOnIndexClear;
    /// <summary>Rückfrage vor dem Löschen; Standard: Dialog mit Ja/Nein.</summary>
    property ConfirmClear: TFunc<Boolean> read FConfirmClear write FConfirmClear;
    /// <summary>„Verlauf zurücksetzen“ der lernenden Gewichtung (#418).</summary>
    property OnResetHistory: TProc read FOnResetHistory write FOnResetHistory;
    /// <summary>Server, der bei leerem Pfad gilt (für die Anzeige „Verwendet: …“).</summary>
    property DefaultServerPath: string read FDefaultServerPath write SetDefaultServerPath;
    /// <summary>Version des Servers unter dem Pfad als Text ('' = unbekannt); nil = keine Anzeige.</summary>
    property OnServerVersion: TFunc<string, string> read FOnServerVersion write SetOnServerVersion;
    /// <summary>Zum Testen: Optionen aus ARG-046.</summary>
    property CommitChars: TCheckBox read FCommitChars;
    property AutoUses: TCheckBox read FAutoUses;
    property ParameterHints: TCheckBox read FParameterHints;
    property OpenDelay: TEdit read FOpenDelay;
    property AutoWidth: TCheckBox read FAutoWidth;
    property ServerVersion: TLabel read FServerVersion;
  end;

implementation

{$R *.dfm}

uses
  System.UITypes,
  System.Math,
  Atlas.Core.Product.Version,
  Atlas.Core.Updates.Check,
  Atlas.Core.Undo.Contract;

{ TAtlasSettingsPage }

constructor TAtlasSettingsPage.Create(AOwner: TComponent);
var
  Panel: TPanel;
  Title: TLabel;
begin
  inherited Create(AOwner);
  Name := 'AtlasSettingsPage';
  Width := 480;
  Height := 2330;
  Title := TLabel.Create(Self);
  Title.Parent := Self;
  Title.Align := alTop;
  Title.AlignWithMargins := True;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsTitle);
  Title.Font.Style := [fsBold];
  FNextTop := 100;
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
  Panel := AddPanel(18);
  FServerVersion := TLabel.Create(Self);
  FServerVersion.Parent := Panel;
  FServerVersion.Left := 180;
  FServerVersion.Top := 0;
  FServerVersion.Font.Color := clGrayText;
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
  FAutoWidth := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsAutoWidth));
  FAutoWidth.OnClick := AutoWidthClick;
  FOpenDelay := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsOpenDelay));
  FPanelCollapsed := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPanelCollapsed));
  FAutoParentheses := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsParentheses));
  FFixCase := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsFixCase));
  FCommitChars := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCommitChars));
  FAutoUses := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsAutoUses));
  FFilterChips := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsChips));
  FLearning := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsLearning));
  FGroupInherited := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGroupInherited));
  FPreview := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPreview));
  // Code-Vorlagen (#51).
  FSnippets := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSnippets));
  FImportIdeTemplates := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsImportIdeTemplates));
  FHoverTooltip := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHover));
  FParameterHints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsParameterHints));
  // XMLDoc in Tooltip und Detailpanel (#654); hints in atlas.json hat Vorrang.
  FXmlDocFull := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocFull));
  FXmlDocMaxLines := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocMaxLines));
  // Einfrier-Wächter (#501).
  FHangThreshold := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsHangThreshold));
  FHangHint := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHangHint));
  // Blockierschutz für Datenquellen (#493).
  FProviderTimeLimit := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsProviderTimeLimit));
  FReloadExternal := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReload));
  // Änderungen des Servers an nicht geöffneten Dateien (#397).
  FOpenForEdits := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOpenForEdits));
  FPairColors := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairs));
  FInactiveDim := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInactiveDim));
  FInlayHints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayHints));
  FPairGuides := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuides));
  FProblems := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblems));
  // Atlas-Statusfeld (#591).
  FStatusField := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStatusField));
  FStatusSummary := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStatusSummary));
  FStatusHidden := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsStatusHidden));
  FStatusHidden.NumbersOnly := False;
  FStatusHidden.Width := 300;
  // Umfang des Index für alle Projekte; index in atlas.json hat Vorrang (#652).
  FIndexGroup := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexGroup));
  FIndexSearch := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexSearch));
  FIndexLibrary := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexLibrary));
  AddIndexSection;
  // Compilerprüfung nach dem Speichern (#548).
  FCheckOnSave := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCheckOnSave));
  FCheckDelay := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsCheckDelay));
  FCheckMax := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsCheckMax));
  // Editorbefehle (#399): ein Vorrang für alle.
  FActionsKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorActions));
  FExpandKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorExpand));
  FShrinkKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorShrink));
  FImplementationKey := AddKey(TAtlasStrings.Text(TAtlasTextId.MenuImplementations));
  FTypeDefinitionKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorTypeDefinition));
  FUndoKey := AddKey(TAtlasStrings.Text(TAtlasTextId.UndoMenu));
  FRedoKey := AddKey(TAtlasStrings.Text(TAtlasTextId.RedoMenu));
  FEditorKeysPriority := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEditorKeysPriority));
  FSlashCommands := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSlashCommands));
  AddSafeSection;
  AddUndoSection;
  AddUpdatesSection;
  AddBugReportSection;
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
  FHangTest := TButton.Create(Self);
  FHangTest.Parent := Panel;
  FHangTest.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsHangTest);
  FHangTest.Left := 320;
  FHangTest.Top := 3;
  FHangTest.Width := 150;
  FHangTest.OnClick := HangTestClick;
  AddFuseSection;
  RefreshFuse;
end;

procedure TAtlasSettingsPage.AddIndexSection;
var
  Panel: TPanel;
  Title: TLabel;
begin
  // Symbolindex (#492): Verwendungen, Speichergrenze, Kennzahlen und Verwaltung.
  Panel := AddPanel(20);
  Title := TLabel.Create(Self);
  Title.Parent := Panel;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIndexTitle);
  Title.Left := 0;
  Title.Top := 3;
  FIndexUsages := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexUsages));
  FMemoryBudget := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsMemoryBudget));
  Panel := AddPanel(66);
  FIndexInfo := TLabel.Create(Self);
  FIndexInfo.Parent := Panel;
  FIndexInfo.Left := 0;
  FIndexInfo.Top := 2;
  FIndexInfo.Font.Color := clGrayText;
  Panel := AddPanel(32);
  FIndexRefresh := TButton.Create(Self);
  FIndexRefresh.Parent := Panel;
  FIndexRefresh.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIndexRefresh);
  FIndexRefresh.Left := 0;
  FIndexRefresh.Top := 3;
  FIndexRefresh.Width := 150;
  FIndexRefresh.OnClick := IndexRefreshClick;
  FIndexRebuild := TButton.Create(Self);
  FIndexRebuild.Parent := Panel;
  FIndexRebuild.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIndexRebuild);
  FIndexRebuild.Left := 160;
  FIndexRebuild.Top := 3;
  FIndexRebuild.Width := 150;
  FIndexRebuild.OnClick := IndexRebuildClick;
  FIndexClear := TButton.Create(Self);
  FIndexClear.Parent := Panel;
  FIndexClear.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIndexClear);
  FIndexClear.Left := 320;
  FIndexClear.Top := 3;
  FIndexClear.Width := 150;
  FIndexClear.OnClick := IndexClearClick;
  // Ohne Server (Ereignisse nicht gesetzt) sind die Befehle aus.
  RefreshIndex;
end;

procedure TAtlasSettingsPage.RefreshIndex;
begin
  if Assigned(FOnIndexMetrics) then
    FIndexInfo.Caption := FOnIndexMetrics()
  else
    FIndexInfo.Caption := '';
  FIndexRebuild.Enabled := Assigned(FOnIndexRebuild);
  FIndexClear.Enabled := Assigned(FOnIndexClear);
end;

procedure TAtlasSettingsPage.IndexRefreshClick(Sender: TObject);
begin
  RefreshIndex;
end;

procedure TAtlasSettingsPage.IndexRebuildClick(Sender: TObject);
begin
  if Assigned(FOnIndexRebuild) then
    FIndexInfo.Caption := FOnIndexRebuild();
end;

procedure TAtlasSettingsPage.IndexClearClick(Sender: TObject);
var
  Confirmed: Boolean;
begin
  if not Assigned(FOnIndexClear) then
    Exit;
  if Assigned(FConfirmClear) then
    Confirmed := FConfirmClear()
  else
    Confirmed := MessageDlg(TAtlasStrings.Text(TAtlasTextId.SettingsIndexClearConfirm), mtConfirmation,
      [mbYes, mbNo], 0) = mrYes;
  if Confirmed then
    FIndexInfo.Caption := FOnIndexClear();
end;

procedure TAtlasSettingsPage.AddFuseSection;
var
  Panel: TPanel;
  Title: TLabel;
begin
  Panel := AddPanel(20);
  Title := TLabel.Create(Self);
  Title.Parent := Panel;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsFuseTitle);
  Title.Left := 0;
  Title.Top := 3;
  Panel := AddPanel(64);
  FFuseList := TListBox.Create(Self);
  FFuseList.Parent := Panel;
  FFuseList.Align := alClient;
  FFuseList.MultiSelect := True;
  Panel := AddPanel(32);
  FFuseEnableSelected := TButton.Create(Self);
  FFuseEnableSelected.Parent := Panel;
  FFuseEnableSelected.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsFuseEnableSelected);
  FFuseEnableSelected.Left := 0;
  FFuseEnableSelected.Top := 3;
  FFuseEnableSelected.Width := 150;
  FFuseEnableSelected.OnClick := FuseEnableSelectedClick;
  FFuseEnableAll := TButton.Create(Self);
  FFuseEnableAll.Parent := Panel;
  FFuseEnableAll.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsFuseEnableAll);
  FFuseEnableAll.Left := 160;
  FFuseEnableAll.Top := 3;
  FFuseEnableAll.Width := 150;
  FFuseEnableAll.OnClick := FuseEnableAllClick;
end;

procedure TAtlasSettingsPage.RefreshFuse;
var
  Feature: TAtlasFeature;
  Name: string;
  Any: Boolean;
begin
  FFuseList.Items.BeginUpdate;
  try
    FFuseList.Items.Clear;
    // Objects: Feature + 1; nil bei einer Quelle (Name im Text).
    for Feature in TAtlasGuard.DisabledSet do
      FFuseList.Items.AddObject(TAtlasGuard.FeatureName(Feature), TObject(NativeInt(Ord(Feature) + 1)));
    for Name in TAtlasGuard.DisabledProviders do
      FFuseList.Items.AddObject(Name, nil);
    Any := FFuseList.Items.Count > 0;
    if not Any then
      FFuseList.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsFuseNone));
  finally
    FFuseList.Items.EndUpdate;
  end;
  FFuseList.Enabled := Any;
  FFuseEnableSelected.Enabled := Any;
  FFuseEnableAll.Enabled := Any;
end;

procedure TAtlasSettingsPage.FuseEnableSelectedClick(Sender: TObject);
var
  Index: Integer;
  Tag: NativeInt;
begin
  for Index := 0 to FFuseList.Items.Count - 1 do
    if FFuseList.Selected[Index] then
    begin
      Tag := NativeInt(FFuseList.Items.Objects[Index]);
      if Tag > 0 then
        TAtlasGuard.Enable(TAtlasFeature(Tag - 1))
      else
        TAtlasGuard.EnableProvider(FFuseList.Items[Index]);
    end;
  RefreshFuse;
end;

procedure TAtlasSettingsPage.FuseEnableAllClick(Sender: TObject);
begin
  TAtlasGuard.EnableAll;
  RefreshFuse;
end;

procedure TAtlasSettingsPage.AddSafeSection;
var
  Panel: TPanel;
  Caption: TLabel;
begin
  // Abgesicherter Start nach einem Absturz (#722).
  Panel := AddPanel(22);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsSafeTitle);
  Caption.Font.Style := [fsBold];
  Caption.Left := 0;
  Caption.Top := 4;
  FSafeAsk := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSafeAsk));
  FSafeAuto := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSafeAuto));
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsSafeKey);
  Caption.Left := 0;
  Caption.Top := 5;
  FSafeKey := TComboBox.Create(Self);
  FSafeKey.Parent := Panel;
  FSafeKey.Style := csDropDownList;
  FSafeKey.Left := 180;
  FSafeKey.Top := 1;
  FSafeKey.Width := 120;
  // Reihenfolge wie TAtlasStartupKey ohne None vorn: Umschalt, Strg, keine.
  FSafeKey.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsSafeKeyShift));
  FSafeKey.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsSafeKeyCtrl));
  FSafeKey.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsSafeKeyNone));
  FSafeTimeout := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSafeTimeout));
  FSafeHistory := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSafeHistory));
end;

procedure TAtlasSettingsPage.AddUndoSection;
var
  Panel: TPanel;
  Caption: TLabel;
begin
  // Atlas-Änderungen über mehrere Dateien zurücknehmen (#721).
  Panel := AddPanel(22);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsUndoTitle);
  Caption.Font.Style := [fsBold];
  Caption.Left := 0;
  Caption.Top := 4;
  FUndoEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUndoEnabled));
  FUndoDepth := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsUndoDepth));
  FUndoPersist := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUndoPersist));
  FUndoMaxSize := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsUndoMaxSize));
  // Reihenfolge wie TAtlasUndoConflictMode und TAtlasNewFilesMode.
  FUndoOnConflict := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsUndoOnConflict),
    [TAtlasStrings.Text(TAtlasTextId.SettingsUndoPartial), TAtlasStrings.Text(TAtlasTextId.SettingsUndoAbort)]);
  FUndoNewFiles := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsUndoNewFiles),
    [TAtlasStrings.Text(TAtlasTextId.SettingsUndoRecycle), TAtlasStrings.Text(TAtlasTextId.SettingsUndoDelete),
    TAtlasStrings.Text(TAtlasTextId.SettingsUndoKeep)]);
end;

procedure TAtlasSettingsPage.AddUpdatesSection;
var
  Panel: TPanel;
  Caption: TLabel;
begin
  // Version und Update-Prüfung (#495).
  Panel := AddPanel(22);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsUpdatesTitle);
  Caption.Font.Style := [fsBold];
  Caption.Left := 0;
  Caption.Top := 4;
  Panel := AddPanel(20);
  FVersion := TLabel.Create(Self);
  FVersion.Parent := Panel;
  FVersion.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsVersion, [TAtlasPluginVersion.Version,
    TAtlasUpdates.IdeVersion]);
  FVersion.Left := 0;
  FVersion.Top := 2;
  FUpdatesCheck := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUpdatesCheck));
end;

procedure TAtlasSettingsPage.AddBugReportSection;
var
  Panel: TPanel;
  Caption: TLabel;
begin
  // Fehlerbericht (#108).
  Panel := AddPanel(22);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsBugReportTitle);
  Caption.Font.Style := [fsBold];
  Caption.Left := 0;
  Caption.Top := 4;
  FBugReportAnonymize := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBugReportAnonymize));
end;

function TAtlasSettingsPage.AddChoice(const ACaption: string; const AItems: array of string): TComboBox;
var
  Panel: TPanel;
  Caption: TLabel;
  Item: string;
begin
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := ACaption;
  Caption.Left := 0;
  Caption.Top := 5;
  Result := TComboBox.Create(Self);
  Result.Parent := Panel;
  Result.Style := csDropDownList;
  Result.Left := 180;
  Result.Top := 1;
  Result.Width := 240;
  for Item in AItems do
    Result.Items.Add(Item);
end;

function TAtlasSettingsPage.AddCheck(const ACaption: string): TCheckBox;
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

function TAtlasSettingsPage.AddPanel(AHeight: Integer): TPanel;
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

function TAtlasSettingsPage.AddKey(const ACaption: string): TEdit;
var
  Panel: TPanel;
  Caption: TLabel;
begin
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := StringReplace(ACaption, '…', '', []);
  Caption.Left := 0;
  Caption.Top := 5;
  Result := TEdit.Create(Self);
  Result.Parent := Panel;
  Result.Left := 180;
  Result.Top := 1;
  Result.Width := 140;
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
  FActionsKey.Text := ShortCutToText(TShortCut(ASettings.ActionsKey));
  FExpandKey.Text := ShortCutToText(TShortCut(ASettings.ExpandKey));
  FShrinkKey.Text := ShortCutToText(TShortCut(ASettings.ShrinkKey));
  FImplementationKey.Text := ShortCutToText(TShortCut(ASettings.ImplementationKey));
  FTypeDefinitionKey.Text := ShortCutToText(TShortCut(ASettings.TypeDefinitionKey));
  FEditorKeysPriority.Checked := ASettings.EditorKeysPriority;
  FSlashCommands.Checked := ASettings.SlashCommands;
  ServerPathChange(nil);
  FRowsUpDown.Position := ASettings.VisibleRows;
  FPanelCollapsed.Checked := ASettings.PanelCollapsed;
  FAutoParentheses.Checked := ASettings.AutoParentheses;
  FFixCase.Checked := ASettings.FixCase;
  FCommitChars.Checked := ASettings.CommitCharacters;
  FAutoUses.Checked := ASettings.AutoUses;
  FParameterHints.Checked := ASettings.ParameterHints;
  FOpenDelay.Text := IntToStr(ASettings.OpenDelayMs);
  FAutoWidth.OnClick := nil;
  FAutoWidth.Checked := ASettings.ListWidth = 0;
  FAutoWidth.OnClick := AutoWidthClick;
  FFilterChips.Checked := ASettings.FilterChips;
  FLearning.Checked := ASettings.Learning;
  FGroupInherited.Checked := ASettings.GroupInherited;
  FPreview.Checked := ASettings.Preview;
  FSnippets.Checked := ASettings.Snippets;
  FImportIdeTemplates.Checked := ASettings.ImportIdeTemplates;
  FHoverTooltip.Checked := ASettings.HoverTooltip;
  FXmlDocFull.Checked := ASettings.XmlDocFull;
  FXmlDocMaxLines.Text := IntToStr(ASettings.XmlDocMaxLines);
  FHangThreshold.Text := IntToStr(ASettings.HangThresholdMs);
  FProviderTimeLimit.Text := IntToStr(ASettings.ProviderTimeLimitMs);
  FHangHint.Checked := ASettings.HangHint;
  FReloadExternal.Checked := ASettings.ReloadExternal;
  FOpenForEdits.Checked := ASettings.OpenForEdits;
  FPairColors.Checked := ASettings.PairColors;
  FInactiveDim.Checked := ASettings.InactiveDim;
  FInlayHints.Checked := ASettings.InlayHints;
  FPairGuides.Checked := ASettings.PairGuides;
  FProblems.Checked := ASettings.Problems;
  FStatusField.Checked := ASettings.StatusField;
  FStatusSummary.Checked := ASettings.StatusFieldSummary;
  FStatusHidden.Text := ASettings.StatusFieldHidden;
  FIndexGroup.Checked := ASettings.IndexProjectGroup;
  FIndexSearch.Checked := ASettings.IndexSearchPaths;
  FIndexLibrary.Checked := ASettings.IndexLibraryPaths;
  FIndexUsages.Checked := ASettings.IndexUsages;
  FMemoryBudget.Text := IntToStr(ASettings.MemoryBudgetMb);
  FCheckOnSave.Checked := ASettings.CheckOnSave;
  FCheckDelay.Text := IntToStr(ASettings.CheckOnSaveDelayMs);
  FCheckMax.Text := IntToStr(ASettings.CheckOnSaveMaxMs);
  FSafeAsk.Checked := ASettings.SafeAskAfterCrash;
  FSafeAuto.Checked := ASettings.SafeAutoAfterRepeatedCrash;
  case TAtlasSafeMode.KeyOf(ASettings.SafeStartupKey) of
    TAtlasStartupKey.Ctrl:
      FSafeKey.ItemIndex := 1;
    TAtlasStartupKey.None:
      FSafeKey.ItemIndex := 2;
  else
    FSafeKey.ItemIndex := 0;
  end;
  FSafeTimeout.Text := IntToStr(ASettings.SafeStartupTimeoutMs);
  FSafeHistory.Text := IntToStr(ASettings.SafeKeepSettingsHistory);
  FUndoEnabled.Checked := ASettings.UndoMultiFile;
  FUndoDepth.Text := IntToStr(ASettings.UndoMultiFileDepth);
  FUndoPersist.Checked := ASettings.UndoMultiFilePersist;
  FUndoMaxSize.Text := IntToStr(ASettings.UndoMultiFileMaxSizeMb);
  FUndoOnConflict.ItemIndex := Ord(TAtlasUndoNames.ParseConflictMode(ASettings.UndoMultiFileOnConflict));
  FUndoNewFiles.ItemIndex := Ord(TAtlasUndoNames.ParseNewFiles(ASettings.UndoMultiFileNewFiles));
  FUndoKey.Text := ShortCutToText(TShortCut(ASettings.UndoKey));
  FRedoKey.Text := ShortCutToText(TShortCut(ASettings.RedoKey));
  FUpdatesCheck.Checked := ASettings.UpdatesCheck;
  FBugReportAnonymize.Checked := ASettings.BugReportAnonymize;
  RefreshFuse;
  RefreshIndex;
end;

procedure TAtlasSettingsPage.SaveTo(var ASettings: TAtlasPluginSettings);
begin
  ASettings.Enabled := FEnabled.Checked;
  ASettings.ServerPath := Trim(FServerPath.Text);
  ASettings.ActionsKey := Integer(TextToShortCut(Trim(FActionsKey.Text)));
  ASettings.ExpandKey := Integer(TextToShortCut(Trim(FExpandKey.Text)));
  ASettings.ShrinkKey := Integer(TextToShortCut(Trim(FShrinkKey.Text)));
  ASettings.ImplementationKey := Integer(TextToShortCut(Trim(FImplementationKey.Text)));
  ASettings.TypeDefinitionKey := Integer(TextToShortCut(Trim(FTypeDefinitionKey.Text)));
  ASettings.UndoKey := Integer(TextToShortCut(Trim(FUndoKey.Text)));
  ASettings.RedoKey := Integer(TextToShortCut(Trim(FRedoKey.Text)));
  ASettings.UpdatesCheck := FUpdatesCheck.Checked;
  ASettings.BugReportAnonymize := FBugReportAnonymize.Checked;
  ASettings.EditorKeysPriority := FEditorKeysPriority.Checked;
  ASettings.SlashCommands := FSlashCommands.Checked;
  ASettings.VisibleRows := FRowsUpDown.Position;
  ASettings.PanelCollapsed := FPanelCollapsed.Checked;
  ASettings.AutoParentheses := FAutoParentheses.Checked;
  ASettings.FixCase := FFixCase.Checked;
  ASettings.CommitCharacters := FCommitChars.Checked;
  ASettings.AutoUses := FAutoUses.Checked;
  ASettings.ParameterHints := FParameterHints.Checked;
  ASettings.OpenDelayMs := StrToIntDef(FOpenDelay.Text, ASettings.OpenDelayMs);
  ASettings.FilterChips := FFilterChips.Checked;
  ASettings.Learning := FLearning.Checked;
  ASettings.GroupInherited := FGroupInherited.Checked;
  ASettings.Preview := FPreview.Checked;
  ASettings.Snippets := FSnippets.Checked;
  ASettings.ImportIdeTemplates := FImportIdeTemplates.Checked;
  ASettings.HoverTooltip := FHoverTooltip.Checked;
  ASettings.XmlDocFull := FXmlDocFull.Checked;
  ASettings.XmlDocMaxLines := StrToIntDef(FXmlDocMaxLines.Text, ASettings.XmlDocMaxLines);
  ASettings.HangThresholdMs := StrToIntDef(FHangThreshold.Text, ASettings.HangThresholdMs);
  ASettings.ProviderTimeLimitMs := StrToIntDef(FProviderTimeLimit.Text, ASettings.ProviderTimeLimitMs);
  ASettings.HangHint := FHangHint.Checked;
  ASettings.ReloadExternal := FReloadExternal.Checked;
  ASettings.OpenForEdits := FOpenForEdits.Checked;
  ASettings.PairColors := FPairColors.Checked;
  ASettings.InactiveDim := FInactiveDim.Checked;
  ASettings.InlayHints := FInlayHints.Checked;
  ASettings.PairGuides := FPairGuides.Checked;
  ASettings.Problems := FProblems.Checked;
  ASettings.StatusField := FStatusField.Checked;
  ASettings.StatusFieldSummary := FStatusSummary.Checked;
  ASettings.StatusFieldHidden := Trim(FStatusHidden.Text);
  ASettings.IndexProjectGroup := FIndexGroup.Checked;
  ASettings.IndexSearchPaths := FIndexSearch.Checked;
  ASettings.IndexLibraryPaths := FIndexLibrary.Checked;
  ASettings.IndexUsages := FIndexUsages.Checked;
  ASettings.MemoryBudgetMb := StrToIntDef(FMemoryBudget.Text, ASettings.MemoryBudgetMb);
  ASettings.CheckOnSave := FCheckOnSave.Checked;
  ASettings.CheckOnSaveDelayMs := StrToIntDef(FCheckDelay.Text, ASettings.CheckOnSaveDelayMs);
  ASettings.CheckOnSaveMaxMs := StrToIntDef(FCheckMax.Text, ASettings.CheckOnSaveMaxMs);
  ASettings.SafeAskAfterCrash := FSafeAsk.Checked;
  ASettings.SafeAutoAfterRepeatedCrash := FSafeAuto.Checked;
  case FSafeKey.ItemIndex of
    1:
      ASettings.SafeStartupKey := TAtlasSafeMode.KeyText(TAtlasStartupKey.Ctrl);
    2:
      ASettings.SafeStartupKey := TAtlasSafeMode.KeyText(TAtlasStartupKey.None);
  else
    ASettings.SafeStartupKey := TAtlasSafeMode.KeyText(TAtlasStartupKey.Shift);
  end;
  ASettings.SafeStartupTimeoutMs := StrToIntDef(FSafeTimeout.Text, ASettings.SafeStartupTimeoutMs);
  ASettings.SafeKeepSettingsHistory := StrToIntDef(FSafeHistory.Text, ASettings.SafeKeepSettingsHistory);
  ASettings.UndoMultiFile := FUndoEnabled.Checked;
  ASettings.UndoMultiFileDepth := StrToIntDef(FUndoDepth.Text, ASettings.UndoMultiFileDepth);
  ASettings.UndoMultiFilePersist := FUndoPersist.Checked;
  ASettings.UndoMultiFileMaxSizeMb := StrToIntDef(FUndoMaxSize.Text, ASettings.UndoMultiFileMaxSizeMb);
  ASettings.UndoMultiFileOnConflict := TAtlasUndoNames.ConflictModeName(TAtlasUndoConflictMode(
    Max(0, FUndoOnConflict.ItemIndex)));
  ASettings.UndoMultiFileNewFiles := TAtlasUndoNames.NewFilesName(TAtlasNewFilesMode(Max(0, FUndoNewFiles.ItemIndex)));
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
  Path, Version: string;
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
  // Version des Servers (#227): aus der Datei bzw. vom laufenden Server.
  Version := '';
  if Assigned(FOnServerVersion) and (Path <> '') and FileExists(Path) then
  begin
    Version := FOnServerVersion(Path);
    if Version = '' then
      Version := TAtlasStrings.Text(TAtlasTextId.SettingsServerVersionUnknown)
    else
      Version := TAtlasStrings.Fmt(TAtlasTextId.SettingsServerVersion, [Version]);
  end;
  FServerVersion.Caption := Version;
end;

procedure TAtlasSettingsPage.SetOnServerVersion(const AValue: TFunc<string, string>);
begin
  FOnServerVersion := AValue;
  ServerPathChange(nil);
end;

procedure TAtlasSettingsPage.AutoWidthClick(Sender: TObject);
begin
  // Automatisch: gezogene Breite vergessen; aus: die zuletzt gezogene bzw. die Vorgabe.
  if FAutoWidth.Checked then
    FWidths.ListWidth := 0
  else if FWidths.ListWidth = 0 then
    FWidths.ListWidth := TAtlasPluginSettings.MinListWidth + 160;
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
  FAutoWidth.OnClick := nil;
  FAutoWidth.Checked := FWidths.ListWidth = 0;
  FAutoWidth.OnClick := AutoWidthClick;
  FResetWidths.Enabled := False;
end;

end.
