unit Atlas.UI.Settings.Page;

// Seite „Atlas“ unter Tools › Optionen › Drittanbieter (#227). Reine VCL, im Code aufgebaut: Reiter je
// Bereich, darin Steuerelemente untereinander; die IDE skaliert sie mit dem Dialog. Die DFM ist leer;
// TCustomFrame.Create verlangt für abgeleitete Frames eine Ressource. Laden und Speichern über
// TAtlasPluginSettings; die IDE-Schicht liest und schreibt die Registry.
// Die Tastenkürzel von Befehlspalette und Prüfung stehen auf der eigenen Seite „Tastenkonflikte“
// (Atlas.UI.Settings.Keys, #494). Der Reiter „Robustheit“ zeigt, was die Sicherung nach wiederholten
// Fehlern abgeschaltet hat, und schaltet es wieder ein (#493).
// Abschnitt Symbolindex (#492): Verwendungen an/aus, Speichergrenze, Kennzahlen (Units, Deklarationen,
// Größe, letzte Aktualisierung), „Index neu aufbauen“ und „Index löschen“. Die Seite kennt den Server
// nicht; die IDE-Schicht liefert Texte und führt die Befehle über OnIndexMetrics, OnIndexRebuild,
// OnIndexClear aus. Im Seitenkopf steht das Atlas-Symbol (#751) passend zu Thema und Skalierung.
// Jeder Reiter bleibt niedriger als die Seite: Sonst scrollt die IDE ihren Bereich beim Reiterwechsel
// zum Fokus, und die Seite „springt“.

interface

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Menus,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.SafeMode,
  Atlas.UI.Strings,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol;

type
  /// <summary>Auswahlliste, die Einträge und Auswahl ohne Fensterhandle hält: Die IDE erzeugt und lädt die
  /// Optionsseiten, bevor sie ein übergeordnetes Fenster haben; Items.Add bräuchte dann schon eins.</summary>
  TAtlasChoiceBox = class(TComboBox)
  private
    FChoices: TArray<string>;
    FChoice: Integer;
    function GetChoice: Integer;
    procedure SetChoice(AValue: Integer);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetChoices(const AItems: array of string);
    /// <summary>Gewählter Eintrag, -1 = keiner; gilt auch ohne Fenster.</summary>
    property Choice: Integer read GetChoice write SetChoice;
  end;

  /// <summary>Zeile der Optionsseite (Beschriftung und Eingabefeld): zeichnet nichts selbst, der
  /// Hintergrund des Reiters scheint durch.</summary>
  TAtlasSettingsRow = class(TWinControl)
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TAtlasSettingsPage = class(TFrame)
  private
    FPages: TPageControl;
    FSheet: TTabSheet;
    // Reiter hängen erst mit dem Fensterhandle am PageControl (CreateWnd): Die IDE und die Tests
    // erzeugen die Seite, bevor sie ein übergeordnetes Fenster hat.
    FSheets: TArray<TTabSheet>;
    FEnabled: TCheckBox;
    FServerPath: TEdit;
    FServerBrowse: TButton;
    FServerStatus: TLabel;
    FServerVersion: TLabel;
    FSymbol: TAtlasSymbolImage;
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
    FPairOwners: TCheckBox;
    FPairGuideWidth: TEdit;
    FPairGuideOpacity: TEdit;
    // Eigene Paarfarben je Thema, eine Fläche je Tiefe.
    FLightSwatches: array[0..4] of TShape;
    FDarkSwatches: array[0..4] of TShape;
    FProblems: TCheckBox;
    FProblemsList: TCheckBox;
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
    FAfterSave: TAtlasChoiceBox;
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
    FSafeKey: TAtlasChoiceBox;
    FSafeTimeout: TEdit;
    FSafeHistory: TEdit;
    FUndoEnabled: TCheckBox;
    FUndoDepth: TEdit;
    FUndoPersist: TCheckBox;
    FUndoMaxSize: TEdit;
    FUndoOnConflict: TAtlasChoiceBox;
    FUndoNewFiles: TAtlasChoiceBox;
    FUpdatesCheck: TCheckBox;
    FBugReportAnonymize: TCheckBox;
    FWelcomeEnabled: TCheckBox;
    FWelcomeHost: TAtlasChoiceBox;
    FWelcomeLayout: TCheckBox;
    FWelcomeHeader: TCheckBox;
    FWelcomeGreeting: TCheckBox;
    FWelcomeSearch: TCheckBox;
    FWelcomeSearchSymbols: TCheckBox;
    FWelcomeSearchKey: TEdit;
    FWelcomeWhatsNew: TAtlasChoiceBox;
    FVersion: TLabel;
    FResetHistory: TButton;
    FResetWidths: TButton;
    FHangTest: TButton;
    FWidths: TAtlasPluginSettings;
    FNextTop: Integer;
    FOnResetHistory: TProc;
  protected
    procedure CreateWnd; override;
  private
    /// <summary>Neuer Reiter; die folgenden Add… setzen ihre Elemente darauf.</summary>
    procedure AddSheet(AId: TAtlasTextId);
    function AddCheck(const ACaption: string): TCheckBox;
    function AddPanel(AHeight: Integer): TWinControl;
    function AddNumber(const ACaption: string): TEdit;
    function AddChoice(const ACaption: string; const AItems: array of string): TAtlasChoiceBox;
    /// <summary>Fett gesetzte Überschrift eines Abschnitts.</summary>
    procedure AddTitle(AId: TAtlasTextId);
    /// <summary>Kürzel ohne eigenen Vorrang; der gilt für die Gruppe (#399). Palette und Prüfung stehen auf der
    /// Seite „Tastenkonflikte“ (#494).</summary>
    function AddKey(const ACaption: string): TEdit;
    procedure ResetHistoryClick(Sender: TObject);
    procedure ResetWidthsClick(Sender: TObject);
    procedure HangTestClick(Sender: TObject);
    procedure PairColorsClick(Sender: TObject);
    procedure FuseEnableSelectedClick(Sender: TObject);
    procedure FuseEnableAllClick(Sender: TObject);
    procedure AddFuseSection;
    procedure AddIndexSection;
    procedure AddSafeSection;
    procedure AddUndoSection;
    procedure AddWelcomeSection;
    procedure AddUpdatesSection;
    procedure AddBugReportSection;
    procedure IndexRefreshClick(Sender: TObject);
    procedure IndexRebuildClick(Sender: TObject);
    procedure IndexClearClick(Sender: TObject);
    /// <summary>Zeile mit Beschriftung und fünf Farbflächen.</summary>
    procedure AddSwatches(const ACaption: string; var ASwatches: array of TShape);
    procedure SwatchMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ResetColorsClick(Sender: TObject);
    class procedure ShowPairs(const ASwatches: array of TShape; const APairs: TAtlasPairColors); static;
    /// <summary>Farben der Flächen als Einstellung; gleich der Palette = leer.</summary>
    class function PairsSetting(const ASwatches: array of TShape; const ADefault: TAtlasPairColors): string; static;
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
    /// <summary>Kennzahlen des Index neu holen und anzeigen (#492).</summary>
    procedure RefreshIndex;
    /// <summary>Reiter der Seite, einer je Bereich (#227).</summary>
    property Pages: TPageControl read FPages;
    /// <summary>Zum Testen: Liste und Schaltflächen der Sicherung.</summary>
    property FuseList: TListBox read FFuseList;
    property FuseEnableSelected: TButton read FFuseEnableSelected;
    property FuseEnableAll: TButton read FFuseEnableAll;
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
    property SafeKey: TAtlasChoiceBox read FSafeKey;
    property SafeTimeout: TEdit read FSafeTimeout;
    property SafeHistory: TEdit read FSafeHistory;
    /// <summary>Zum Testen: Atlas-Änderungen über mehrere Dateien (#721).</summary>
    property UndoEnabled: TCheckBox read FUndoEnabled;
    property UndoDepth: TEdit read FUndoDepth;
    property UndoPersist: TCheckBox read FUndoPersist;
    property UndoMaxSize: TEdit read FUndoMaxSize;
    property UndoOnConflict: TAtlasChoiceBox read FUndoOnConflict;
    property UndoNewFiles: TAtlasChoiceBox read FUndoNewFiles;
    property UndoKey: TEdit read FUndoKey;
    property RedoKey: TEdit read FRedoKey;
    property UpdatesCheck: TCheckBox read FUpdatesCheck;
    property BugReportAnonymize: TCheckBox read FBugReportAnonymize;
    /// <summary>Zum Testen: Willkommensseite (#753).</summary>
    property WelcomeEnabled: TCheckBox read FWelcomeEnabled;
    property WelcomeHost: TAtlasChoiceBox read FWelcomeHost;
    property WelcomeLayout: TCheckBox read FWelcomeLayout;
    property WelcomeHeader: TCheckBox read FWelcomeHeader;
    property WelcomeGreeting: TCheckBox read FWelcomeGreeting;
    property WelcomeSearch: TCheckBox read FWelcomeSearch;
    property WelcomeSearchSymbols: TCheckBox read FWelcomeSearchSymbols;
    property WelcomeSearchKey: TEdit read FWelcomeSearchKey;
    property WelcomeWhatsNew: TAtlasChoiceBox read FWelcomeWhatsNew;
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
    property Symbol: TAtlasSymbolImage read FSymbol;
    property ServerVersion: TLabel read FServerVersion;
  end;

implementation

{$R *.dfm}

uses
  System.Math,
  Atlas.Core.Product.Version,
  Atlas.Core.Updates.Check,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Welcome.WhatsNew;

{ TAtlasChoiceBox }

constructor TAtlasChoiceBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Style := csDropDownList;
  FChoice := -1;
end;

procedure TAtlasChoiceBox.SetChoices(const AItems: array of string);
var
  Index: Integer;
begin
  SetLength(FChoices, Length(AItems));
  for Index := 0 to High(AItems) do
    FChoices[Index] := AItems[Index];
  if HandleAllocated then
  begin
    Items.Clear;
    for Index := 0 to High(FChoices) do
      Items.Add(FChoices[Index]);
    ItemIndex := FChoice;
  end;
end;

procedure TAtlasChoiceBox.CreateWnd;
var
  Item: string;
begin
  inherited CreateWnd;
  if Items.Count = 0 then
    for Item in FChoices do
      Items.Add(Item);
  ItemIndex := FChoice;
end;

function TAtlasChoiceBox.GetChoice: Integer;
begin
  if HandleAllocated then
    FChoice := ItemIndex;
  Result := FChoice;
end;

procedure TAtlasChoiceBox.SetChoice(AValue: Integer);
begin
  FChoice := AValue;
  if HandleAllocated then
    ItemIndex := AValue;
end;

{ TAtlasSettingsRow }

constructor TAtlasSettingsRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csParentBackground] - [csOpaque];
  ParentBackground := True;
  ParentColor := True;
end;

const
  // Linke Kante der Eingabefelder; Platz für die längste Beschriftung („Breite der Blocklinien …“).
  FieldLeft = 280;

{ TAtlasSettingsPage }

constructor TAtlasSettingsPage.Create(AOwner: TComponent);
var
  Panel: TWinControl;
  Title: TLabel;
  Button: TButton;
begin
  inherited Create(AOwner);
  Name := 'AtlasSettingsPage';
  Width := 480;
  // Die Reiter tragen den Inhalt; scrollt die Seite selbst, springt sie beim Reiterwechsel zum Fokus.
  AutoScroll := False;
  // Mit Reitern reicht die Höhe des längsten Reiters; höher, und die IDE scrollt ihren Bereich beim
  // Reiterwechsel zum Fokus (die Seite „springt“).
  Height := 440;
  // Kopf mit Symbol (#751) und Titel.
  Panel := TAtlasSettingsRow.Create(Self);
  Panel.Parent := Self;
  Panel.Align := alTop;
  Panel.Height := 40;
  FSymbol := TAtlasSymbolImage.Create(Self);
  FSymbol.Parent := Panel;
  FSymbol.LogicalSize := TAtlasSymbol.HeaderSize;
  FSymbol.Left := 4;
  FSymbol.Top := 4;
  Title := TLabel.Create(Self);
  Title.Parent := Panel;
  Title.Left := 44;
  Title.Top := 12;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsTitle);
  Title.Font.Style := [fsBold];
  // Reiter je Bereich (#227); jeder stapelt seine Elemente neu von oben. Viele Reiter: in Zeilen.
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.AlignWithMargins := True;
  FPages.MultiLine := True;
  FPages.Top := 100;

  AddSheet(TAtlasTextId.SettingsTabGeneral);
  FEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEnabled));
  // Wo der Server liegt; leer gilt der Standard neben dem Plugin.
  Panel := AddPanel(20);
  Title := TLabel.Create(Self);
  Title.Parent := Panel;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsServerPath);
  Title.Left := 0;
  Title.Top := 3;
  // Pfad in eigener Zeile: Die Beschriftung ist lang, das Feld braucht die Breite.
  Panel := AddPanel(26);
  FServerPath := TEdit.Create(Self);
  FServerPath.Parent := Panel;
  FServerPath.Left := 0;
  FServerPath.Top := 1;
  FServerPath.Width := 430;
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
  FServerStatus.Left := 0;
  FServerStatus.Top := 0;
  FServerStatus.Font.Color := clGrayText;
  Panel := AddPanel(18);
  FServerVersion := TLabel.Create(Self);
  FServerVersion.Parent := Panel;
  FServerVersion.Left := 0;
  FServerVersion.Top := 0;
  FServerVersion.Font.Color := clGrayText;
  FReloadExternal := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReload));
  // Änderungen des Servers an nicht geöffneten Dateien (#397).
  FOpenForEdits := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOpenForEdits));
  // Atlas-Statusfeld (#591).
  FStatusField := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStatusField));
  FStatusSummary := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStatusSummary));
  FStatusHidden := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsStatusHidden));
  FStatusHidden.NumbersOnly := False;
  FStatusHidden.Width := 180;

  // Liste der Vervollständigung.
  AddSheet(TAtlasTextId.SettingsTabCompletion);
  Panel := AddPanel(26);
  FRowsLabel := TLabel.Create(Self);
  FRowsLabel.Parent := Panel;
  FRowsLabel.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsRows);
  FRowsLabel.Left := 0;
  FRowsLabel.Top := 5;
  FRows := TEdit.Create(Self);
  FRows.Parent := Panel;
  FRows.Left := FieldLeft;
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

  // Was beim Übernehmen eingefügt wird.
  AddSheet(TAtlasTextId.SettingsTabInsert);
  FAutoParentheses := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsParentheses));
  FFixCase := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsFixCase));
  FCommitChars := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCommitChars));
  FAutoUses := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsAutoUses));
  FParameterHints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsParameterHints));
  // Code-Vorlagen (#51).
  FSnippets := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSnippets));
  FImportIdeTemplates := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsImportIdeTemplates));

  AddSheet(TAtlasTextId.SettingsTabEditor);
  FHoverTooltip := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHover));
  // XMLDoc in Tooltip und Detailpanel (#654); gespeichert in settings.json (hints.*, #227).
  FXmlDocFull := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocFull));
  FXmlDocMaxLines := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocMaxLines));
  FPairColors := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairs));
  FPairGuides := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuides));
  // Anweisungen mitfärben, Linienbreite und Deckkraft (#653); wirken nur mit der Paarfärbung.
  FPairOwners := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairOwners));
  FPairGuideWidth := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuideWidth));
  FPairGuideOpacity := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuideOpacity));
  FPairColors.OnClick := PairColorsClick;
  FInactiveDim := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInactiveDim));
  FInlayHints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayHints));

  // Eigene Paarfarben und deren Reihenfolge je Thema.
  AddSheet(TAtlasTextId.SettingsTabColors);
  AddSwatches(TAtlasStrings.Text(TAtlasTextId.SettingsPairColorsLight), FLightSwatches);
  AddSwatches(TAtlasStrings.Text(TAtlasTextId.SettingsPairColorsDark), FDarkSwatches);
  Panel := AddPanel(22);
  Title := TLabel.Create(Self);
  Title.Parent := Panel;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsPairColorsHint);
  Title.Left := 0;
  Title.Top := 3;
  Title.Font.Color := clGrayText;
  Panel := AddPanel(32);
  Button := TButton.Create(Self);
  Button.Parent := Panel;
  Button.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsPairColorsReset);
  Button.Left := 0;
  Button.Top := 3;
  Button.Width := 150;
  Button.OnClick := ResetColorsClick;

  // Umfang des Index für alle Projekte, gespeichert in settings.json (index.*, #652, #227).
  AddSheet(TAtlasTextId.SettingsTabIndex);
  FIndexGroup := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexGroup));
  FIndexSearch := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexSearch));
  FIndexLibrary := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexLibrary));
  AddIndexSection;

  // Probleme im Editor und eine Aktion nach dem Speichern (#398, #548): Syntaxprüfung der IDE oder
  // Kompilieren durch den Server (compiler.onSave in settings.json), nie beides.
  AddSheet(TAtlasTextId.SettingsTabCompiler);
  FProblems := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblems));
  FProblemsList := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsList));
  // Reihenfolge: nichts, Syntaxprüfung (CheckOnSave), Kompilieren (CompileOnSave).
  FAfterSave := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsCheckOnSave),
    [TAtlasStrings.Text(TAtlasTextId.SettingsAfterSaveNone), TAtlasStrings.Text(TAtlasTextId.SettingsAfterSaveCheck),
    TAtlasStrings.Text(TAtlasTextId.SettingsAfterSaveCompile)]);
  FCheckDelay := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsCheckDelay));
  FCheckMax := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsCheckMax));

  // Editorbefehle (#399): ein Vorrang für alle.
  AddSheet(TAtlasTextId.SettingsTabCommands);
  FActionsKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorActions));
  FExpandKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorExpand));
  FShrinkKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorShrink));
  FImplementationKey := AddKey(TAtlasStrings.Text(TAtlasTextId.MenuImplementations));
  FTypeDefinitionKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorTypeDefinition));
  FUndoKey := AddKey(TAtlasStrings.Text(TAtlasTextId.UndoMenu));
  FRedoKey := AddKey(TAtlasStrings.Text(TAtlasTextId.RedoMenu));
  FEditorKeysPriority := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEditorKeysPriority));
  FSlashCommands := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSlashCommands));

  AddSheet(TAtlasTextId.SettingsTabRobustness);
  // Einfrier-Wächter (#501).
  FHangThreshold := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsHangThreshold));
  FHangHint := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHangHint));
  // Blockierschutz für Datenquellen (#493).
  FProviderTimeLimit := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsProviderTimeLimit));
  Panel := AddPanel(32);
  FHangTest := TButton.Create(Self);
  FHangTest.Parent := Panel;
  FHangTest.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsHangTest);
  FHangTest.Left := 0;
  FHangTest.Top := 3;
  FHangTest.Width := 150;
  FHangTest.OnClick := HangTestClick;
  AddFuseSection;

  // Abgesicherter Start, Updates und Fehlerbericht (#722, #495, #108).
  AddSheet(TAtlasTextId.SettingsTabStartup);
  AddSafeSection;
  AddUpdatesSection;
  AddBugReportSection;

  AddSheet(TAtlasTextId.SettingsTabUndo);
  AddUndoSection;

  AddSheet(TAtlasTextId.SettingsTabWelcome);
  AddWelcomeSection;
end;

procedure TAtlasSettingsPage.AddWelcomeSection;
begin
  // Atlas-Bereiche auf der Willkommensseite (#753).
  FWelcomeEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeEnabled));
  // Reihenfolge wie welcomePage.host: welcomePage, dockWindow.
  FWelcomeHost := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHost),
    [TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHostPage),
    TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHostWindow)]);
  FWelcomeLayout := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeLayout));
  FWelcomeHeader := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHeader));
  FWelcomeGreeting := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeGreeting));
  FWelcomeSearch := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeSearch));
  FWelcomeSearchSymbols := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeSearchSymbols));
  FWelcomeSearchKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeSearchKey));
  // Karte „Neu in Atlas“ (#756); Reihenfolge wie TAtlasWhatsNewMode: off, afterUpdate, always.
  FWelcomeWhatsNew := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeWhatsNew),
    [TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeWhatsNewOff),
    TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeWhatsNewAfterUpdate),
    TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeWhatsNewAlways)]);
end;

procedure TAtlasSettingsPage.AddSheet(AId: TAtlasTextId);
begin
  FSheet := TTabSheet.Create(Self);
  FSheet.Caption := TAtlasStrings.Text(AId);
  FSheets := FSheets + [FSheet];
  FNextTop := 100;
end;

procedure TAtlasSettingsPage.CreateWnd;
var
  Sheet: TTabSheet;
begin
  inherited CreateWnd;
  for Sheet in FSheets do
    if Sheet.PageControl = nil then
      Sheet.PageControl := FPages;
  if FPages.PageCount > 0 then
    FPages.ActivePageIndex := 0;
  // Die Liste der Sicherung braucht ein Fenster; vorher bleibt sie leer.
  RefreshFuse;
end;

procedure TAtlasSettingsPage.AddTitle(AId: TAtlasTextId);
var
  Panel: TWinControl;
  Caption: TLabel;
begin
  Panel := AddPanel(22);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := TAtlasStrings.Text(AId);
  Caption.Font.Style := [fsBold];
  Caption.Left := 0;
  Caption.Top := 4;
end;

procedure TAtlasSettingsPage.AddIndexSection;
var
  Panel: TWinControl;
begin
  // Symbolindex (#492): Verwendungen, Speichergrenze, Kennzahlen und Verwaltung.
  AddTitle(TAtlasTextId.SettingsIndexTitle);
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
  Panel: TWinControl;
begin
  AddTitle(TAtlasTextId.SettingsFuseTitle);
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
  // Ohne Fenster (IDE erzeugt die Seite vor dem Einhängen) folgt das in CreateWnd.
  if not HandleAllocated then
    Exit;
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
  Panel: TWinControl;
  Caption: TLabel;
begin
  // Abgesicherter Start nach einem Absturz (#722).
  AddTitle(TAtlasTextId.SettingsSafeTitle);
  FSafeAsk := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSafeAsk));
  FSafeAuto := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSafeAuto));
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsSafeKey);
  Caption.Left := 0;
  Caption.Top := 5;
  FSafeKey := TAtlasChoiceBox.Create(Self);
  FSafeKey.Parent := Panel;
  FSafeKey.Left := FieldLeft;
  FSafeKey.Top := 1;
  FSafeKey.Width := 120;
  // Reihenfolge wie TAtlasStartupKey ohne None vorn: Umschalt, Strg, keine.
  FSafeKey.SetChoices([TAtlasStrings.Text(TAtlasTextId.SettingsSafeKeyShift),
    TAtlasStrings.Text(TAtlasTextId.SettingsSafeKeyCtrl), TAtlasStrings.Text(TAtlasTextId.SettingsSafeKeyNone)]);
  FSafeTimeout := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSafeTimeout));
  FSafeHistory := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSafeHistory));
end;

procedure TAtlasSettingsPage.AddUndoSection;
begin
  // Atlas-Änderungen über mehrere Dateien zurücknehmen (#721).
  AddTitle(TAtlasTextId.SettingsUndoTitle);
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
  Panel: TWinControl;
begin
  // Version und Update-Prüfung (#495).
  AddTitle(TAtlasTextId.SettingsUpdatesTitle);
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
begin
  // Fehlerbericht (#108).
  AddTitle(TAtlasTextId.SettingsBugReportTitle);
  FBugReportAnonymize := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBugReportAnonymize));
end;

function TAtlasSettingsPage.AddChoice(const ACaption: string; const AItems: array of string): TAtlasChoiceBox;
var
  Panel: TWinControl;
  Caption: TLabel;
begin
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := ACaption;
  Caption.Left := 0;
  Caption.Top := 5;
  Result := TAtlasChoiceBox.Create(Self);
  Result.Parent := Panel;
  Result.Left := FieldLeft;
  Result.Top := 1;
  Result.Width := 180;
  Result.SetChoices(AItems);
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

function TAtlasSettingsPage.AddPanel(AHeight: Integer): TWinControl;
begin
  // Kein TPanel: Das zeichnet im IDE-Thema einen eigenen Hintergrund (dunkle Streifen im Reiter).
  Result := TAtlasSettingsRow.Create(Self);
  Result.Parent := FSheet;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Height := AHeight;
  Result.Top := FNextTop;
  Inc(FNextTop, 100);
end;

function TAtlasSettingsPage.AddKey(const ACaption: string): TEdit;
var
  Panel: TWinControl;
  Caption: TLabel;
begin
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := StringReplace(ACaption, '…', '', []);
  Caption.Left := 0;
  Caption.Top := 5;
  // Als Text wie im Menü ("Strg+Umschalt+P"); leer = keine Taste.
  Result := TEdit.Create(Self);
  Result.Parent := Panel;
  Result.Left := FieldLeft;
  Result.Top := 1;
  Result.Width := 140;
end;

procedure TAtlasSettingsPage.PairColorsClick(Sender: TObject);
begin
  FPairOwners.Enabled := FPairColors.Checked;
  FPairGuides.Enabled := FPairColors.Checked;
  FPairGuideWidth.Enabled := FPairColors.Checked;
  FPairGuideOpacity.Enabled := FPairColors.Checked;
end;

procedure TAtlasSettingsPage.AddSwatches(const ACaption: string; var ASwatches: array of TShape);
var
  Panel: TWinControl;
  Caption: TLabel;
  Index: Integer;
begin
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := ACaption;
  Caption.Left := 0;
  Caption.Top := 5;
  for Index := 0 to High(ASwatches) do
  begin
    ASwatches[Index] := TShape.Create(Self);
    ASwatches[Index].Parent := Panel;
    ASwatches[Index].SetBounds(FieldLeft + Index * 34, 1, 28, 22);
    ASwatches[Index].Pen.Color := clGray;
    ASwatches[Index].Cursor := crHandPoint;
    ASwatches[Index].Hint := IntToStr(Index + 1);
    ASwatches[Index].ShowHint := True;
    ASwatches[Index].OnMouseDown := SwatchMouseDown;
  end;
end;

procedure TAtlasSettingsPage.SwatchMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Dialog: TColorDialog;
begin
  if Button <> mbLeft then
    Exit;
  Dialog := TColorDialog.Create(nil);
  try
    Dialog.Color := TShape(Sender).Brush.Color;
    Dialog.Options := Dialog.Options + [cdFullOpen];
    if Dialog.Execute then
      TShape(Sender).Brush.Color := Dialog.Color;
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasSettingsPage.ResetColorsClick(Sender: TObject);
begin
  ShowPairs(FLightSwatches, TAtlasColors.Light.Pairs);
  ShowPairs(FDarkSwatches, TAtlasColors.Dark.Pairs);
end;

class procedure TAtlasSettingsPage.ShowPairs(const ASwatches: array of TShape; const APairs: TAtlasPairColors);
var
  Index: Integer;
begin
  for Index := 0 to High(ASwatches) do
    ASwatches[Index].Brush.Color := TColor(APairs[Index]);
end;

class function TAtlasSettingsPage.PairsSetting(const ASwatches: array of TShape;
  const ADefault: TAtlasPairColors): string;
var
  Pairs: TAtlasPairColors;
  Index: Integer;
begin
  for Index := 0 to High(Pairs) do
    Pairs[Index] := TAtlasColor(ColorToRGB(ASwatches[Index].Brush.Color));
  Result := TAtlasColors.PairsText(Pairs);
  if Result = TAtlasColors.PairsText(ADefault) then
    Result := '';
end;

function TAtlasSettingsPage.AddNumber(const ACaption: string): TEdit;
var
  Panel: TWinControl;
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
  Result.Left := FieldLeft;
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
  FPairOwners.Checked := ASettings.PairOwners;
  FPairGuideWidth.Text := IntToStr(ASettings.PairGuideWidth);
  FPairGuideOpacity.Text := IntToStr(ASettings.PairGuideOpacity);
  PairColorsClick(nil);
  ShowPairs(FLightSwatches, TAtlasColors.Light.WithPairs(ASettings.PairColorsLight).Pairs);
  ShowPairs(FDarkSwatches, TAtlasColors.Dark.WithPairs(ASettings.PairColorsDark).Pairs);
  FProblems.Checked := ASettings.Problems;
  FProblemsList.Checked := ASettings.ProblemsList;
  FStatusField.Checked := ASettings.StatusField;
  FStatusSummary.Checked := ASettings.StatusFieldSummary;
  FStatusHidden.Text := ASettings.StatusFieldHidden;
  FIndexGroup.Checked := ASettings.IndexProjectGroup;
  FIndexSearch.Checked := ASettings.IndexSearchPaths;
  FIndexLibrary.Checked := ASettings.IndexLibraryPaths;
  FIndexUsages.Checked := ASettings.IndexUsages;
  FMemoryBudget.Text := IntToStr(ASettings.MemoryBudgetMb);
  FAfterSave.Choice := 0;
  if ASettings.CheckOnSave then
    FAfterSave.Choice := 1
  else if ASettings.CompileOnSave then
    FAfterSave.Choice := 2;
  FCheckDelay.Text := IntToStr(ASettings.CheckOnSaveDelayMs);
  FCheckMax.Text := IntToStr(ASettings.CheckOnSaveMaxMs);
  FSafeAsk.Checked := ASettings.SafeAskAfterCrash;
  FSafeAuto.Checked := ASettings.SafeAutoAfterRepeatedCrash;
  case TAtlasSafeMode.KeyOf(ASettings.SafeStartupKey) of
    TAtlasStartupKey.Ctrl:
      FSafeKey.Choice := 1;
    TAtlasStartupKey.None:
      FSafeKey.Choice := 2;
  else
    FSafeKey.Choice := 0;
  end;
  FSafeTimeout.Text := IntToStr(ASettings.SafeStartupTimeoutMs);
  FSafeHistory.Text := IntToStr(ASettings.SafeKeepSettingsHistory);
  FUndoEnabled.Checked := ASettings.UndoMultiFile;
  FUndoDepth.Text := IntToStr(ASettings.UndoMultiFileDepth);
  FUndoPersist.Checked := ASettings.UndoMultiFilePersist;
  FUndoMaxSize.Text := IntToStr(ASettings.UndoMultiFileMaxSizeMb);
  FUndoOnConflict.Choice := Ord(TAtlasUndoNames.ParseConflictMode(ASettings.UndoMultiFileOnConflict));
  FUndoNewFiles.Choice := Ord(TAtlasUndoNames.ParseNewFiles(ASettings.UndoMultiFileNewFiles));
  FUndoKey.Text := ShortCutToText(TShortCut(ASettings.UndoKey));
  FRedoKey.Text := ShortCutToText(TShortCut(ASettings.RedoKey));
  FUpdatesCheck.Checked := ASettings.UpdatesCheck;
  FBugReportAnonymize.Checked := ASettings.BugReportAnonymize;
  FWelcomeEnabled.Checked := ASettings.WelcomePage;
  FWelcomeHost.Choice := 0;
  if ASettings.WelcomePageHost = 'dockWindow' then
    FWelcomeHost.Choice := 1;
  FWelcomeLayout.Checked := ASettings.WelcomePageLayout = 'atlas';
  FWelcomeHeader.Checked := ASettings.WelcomePageHeader;
  FWelcomeGreeting.Checked := ASettings.WelcomePageGreeting;
  FWelcomeSearch.Checked := ASettings.WelcomePageSearch;
  FWelcomeSearchSymbols.Checked := ASettings.WelcomePageSearchSymbols;
  FWelcomeSearchKey.Text := ShortCutToText(TShortCut(ASettings.WelcomePageSearchKey));
  FWelcomeWhatsNew.Choice := Ord(TAtlasWhatsNew.ModeOf(ASettings.WelcomePageWhatsNew));
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
  ASettings.PairOwners := FPairOwners.Checked;
  ASettings.PairGuideWidth := StrToIntDef(FPairGuideWidth.Text, ASettings.PairGuideWidth);
  ASettings.PairGuideOpacity := StrToIntDef(FPairGuideOpacity.Text, ASettings.PairGuideOpacity);
  ASettings.PairColorsLight := PairsSetting(FLightSwatches, TAtlasColors.Light.Pairs);
  ASettings.PairColorsDark := PairsSetting(FDarkSwatches, TAtlasColors.Dark.Pairs);
  ASettings.Problems := FProblems.Checked;
  ASettings.ProblemsList := FProblemsList.Checked;
  ASettings.StatusField := FStatusField.Checked;
  ASettings.StatusFieldSummary := FStatusSummary.Checked;
  ASettings.StatusFieldHidden := Trim(FStatusHidden.Text);
  ASettings.IndexProjectGroup := FIndexGroup.Checked;
  ASettings.IndexSearchPaths := FIndexSearch.Checked;
  ASettings.IndexLibraryPaths := FIndexLibrary.Checked;
  ASettings.IndexUsages := FIndexUsages.Checked;
  ASettings.MemoryBudgetMb := StrToIntDef(FMemoryBudget.Text, ASettings.MemoryBudgetMb);
  ASettings.CheckOnSave := FAfterSave.Choice = 1;
  ASettings.CompileOnSave := FAfterSave.Choice = 2;
  ASettings.CheckOnSaveDelayMs := StrToIntDef(FCheckDelay.Text, ASettings.CheckOnSaveDelayMs);
  ASettings.CheckOnSaveMaxMs := StrToIntDef(FCheckMax.Text, ASettings.CheckOnSaveMaxMs);
  ASettings.SafeAskAfterCrash := FSafeAsk.Checked;
  ASettings.SafeAutoAfterRepeatedCrash := FSafeAuto.Checked;
  case FSafeKey.Choice of
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
    Max(0, FUndoOnConflict.Choice)));
  ASettings.UndoMultiFileNewFiles := TAtlasUndoNames.NewFilesName(TAtlasNewFilesMode(Max(0, FUndoNewFiles.Choice)));
  ASettings.WelcomePage := FWelcomeEnabled.Checked;
  ASettings.WelcomePageHost := 'welcomePage';
  if FWelcomeHost.Choice = 1 then
    ASettings.WelcomePageHost := 'dockWindow';
  ASettings.WelcomePageLayout := 'off';
  if FWelcomeLayout.Checked then
    ASettings.WelcomePageLayout := 'atlas';
  ASettings.WelcomePageHeader := FWelcomeHeader.Checked;
  ASettings.WelcomePageGreeting := FWelcomeGreeting.Checked;
  ASettings.WelcomePageSearch := FWelcomeSearch.Checked;
  ASettings.WelcomePageSearchSymbols := FWelcomeSearchSymbols.Checked;
  ASettings.WelcomePageSearchKey := Integer(TextToShortCut(Trim(FWelcomeSearchKey.Text)));
  ASettings.WelcomePageWhatsNew := TAtlasWhatsNew.ModeName(TAtlasWhatsNewMode(EnsureRange(FWelcomeWhatsNew.Choice,
    Ord(Low(TAtlasWhatsNewMode)), Ord(High(TAtlasWhatsNewMode)))));
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
