unit Atlas.UI.Settings.Rules;

// Regel-Editor der Seite „Prüfregeln“ (#909): ersetzt die frühere Regeltabelle
// des Projektdialogs und steht in Tools › Optionen › Atlas › Prüfregeln im
// Hauptknoten (alle Regeln mit Suche) und in je einem Knoten pro Gruppe.
//   - Oben die Suche über Name, ID und Kategorie (nur ohne feste Gruppe) und die
//     Auswahl der Gruppe, darunter der Hauptschalter „Regeln der Gruppe … prüfen“
//     ("group:<gruppe>": "off"). Aus sperrt die Tabelle und alle Felder. In der
//     Gruppe „Compiler vorab“ darunter „Regeln der Stufe T prüfen“ (#1024,
//     "group:compiler": {"typeLevel": "off"}).
//   - Tabelle: Schalter an/aus, Regel-ID, Name, Kategorie bzw. Gruppe,
//     Schweregrad, Ausnahmen. Werte der anderen Ebene stehen als „(global: …)“.
//   - Unter der Tabelle die markierte Regel: Name, Marke „Experimentell“ (#834),
//     Katalogtext, Schweregrad (Vorgabe, Error, Warnung, Info, Hinweis, aus),
//     Ausnahmen ("exclude"), Optionen nach Typ (Zahl, Schalter, Text, Liste,
//     JSON, Tabelle von Objekten #1133) und die Beispiele falsch und richtig.
// Reine VCL; das Modell ist TAtlasRuleTable. Der Editor kennt weder Dateien
// noch Server: Er bekommt den Katalog und den Wert von "rules" und meldet
// Änderungen über OnChange; RulesJson ist der neue Wert. Tabelle und Auswahl-
// listen brauchen ein Fenster und werden erst mit Handle gefüllt (CreateWnd).
// Aufbau als Klassenkette: TAtlasRulesLayout (Stapeln, Höhe) → TAtlasRulesTable
// (Suche, Gruppe, Hauptschalter, Tabelle) → TAtlasRulesDetailsView (markierte
// Regel, Optionen, Beispiele) → TAtlasRulesEditor (Zustand, Ereignisse).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Math,
  System.UITypes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Grids,
  Atlas.Core.Settings.RuleTable;

type
  /// <summary>Behälter ohne Rahmen und Beschriftung (Zeilen und Bereiche des Editors).</summary>
  TAtlasRulesBox = class(TCustomPanel)
  public
    constructor Create(AOwner: TComponent); override;
  end;

  /// <summary>Stapelt die Steuerelemente des Editors von oben nach unten und hält die Höhe am Inhalt.</summary>
  TAtlasRulesLayout = class(TCustomPanel)
  private
    FNextTop: Integer;
    /// <summary>Alle über Stack gestapelten Steuerelemente in Aufbaureihenfolge (#1296).</summary>
    FStacked: TArray<TControl>;
  protected
    /// <summary>Bereich der markierten Regel; legt TAtlasRulesDetailsView an.</summary>
    FDetails: TAtlasRulesBox;
    function AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
    function AddMemo(AParent: TWinControl): TMemo;
    /// <summary>Höhe nach Zeilenzahl, damit das Beispiel ganz zu sehen ist.</summary>
    procedure FitMemo(AMemo: TMemo);
    /// <summary>AControl oben in AParent unter die bisherigen (alTop ordnet nach Top).</summary>
    procedure Stack(AParent: TWinControl; AControl: TControl);
    procedure Restack;
    /// <summary>AutoSize regelt nur die Höhe; die Breite gibt der Behälter vor (Align oder SetBounds mit
    /// Anker). Sonst schrumpft der Editor ohne Align auf die Breite eines leeren Panels, weil alle Kinder alTop
    /// sind (Projektdialog). Die angefragte Breite bleibt: CheckNewSize fragt mit der neuen Breite, die alte
    /// (Width) hielt jedes SetBounds auf den 185 Pixeln eines frischen Panels.</summary>
    function CanAutoSize(var NewWidth, NewHeight: Integer): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Details: TAtlasRulesBox read FDetails;
  end;

  /// <summary>Oberer Teil: Suche, Gruppenauswahl, Hauptschalter, Stufe T, Stand und Tabelle der Regeln.</summary>
  TAtlasRulesTable = class(TAtlasRulesLayout)
  private
    FTopBar: TAtlasRulesBox;
    FSearch: TEdit;
    FGroupChoice: TComboBox;
    FMaster: TCheckBox;
    FTypeLevel: TCheckBox;
    FStatus: TLabel;
    FList: TListView;
  protected
    FFixedGroup: string;
    /// <summary>Felder werden gerade gefüllt: Änderungen nicht zurückschreiben.</summary>
    FFilling: Boolean;
    /// <summary>Feste Gruppe oder die gewählte; '' = alle.</summary>
    function Group: string;
    /// <summary>Feste Gruppe setzen: ohne Suche und Gruppenauswahl, die Spalte zeigt die Kategorie.</summary>
    procedure ShowFixedGroup(const AValue: string);
    /// <summary>Hauptschalter und Stufe T nach der Gruppe und dem Wert von "rules".</summary>
    procedure ShowMaster(const ARulesJson: string);
    /// <summary>Stand über der Tabelle; '' blendet ihn aus.</summary>
    procedure ShowStatus(const AText: string);
    procedure FillGroups;
  public
    constructor Create(AOwner: TComponent); override;
    property Search: TEdit read FSearch;
    property GroupChoice: TComboBox read FGroupChoice;
    property Master: TCheckBox read FMaster;
    /// <summary>Stufe T der Gruppe „Compiler vorab“ (#1024); nur in dieser Gruppe sichtbar.</summary>
    property TypeLevel: TCheckBox read FTypeLevel;
    property Status: TLabel read FStatus;
    property List: TListView read FList;
  end;

  /// <summary>Unterer Teil: Name, Marke, Beschreibung, Schweregrad, Ausnahmen, Optionen und Beispiele der
  /// markierten Regel.</summary>
  TAtlasRulesDetailsView = class(TAtlasRulesTable)
  private
    FTitle: TLabel;
    FMark: TLabel;
    FDescription: TLabel;
    FSeverityRow: TAtlasRulesBox;
    FSeverity: TComboBox;
    FExcludeLabel: TLabel;
    FExclude: TEdit;
    FOptionsTitle: TLabel;
    FOptionsBox: TAtlasRulesBox;
    FOptionControls: TArray<TControl>;
    FInvalid: TLabel;
    FBadLabel: TLabel;
    FBad: TMemo;
    FGoodLabel: TLabel;
    FGood: TMemo;
    procedure BuildOptions(const ARow: TAtlasRuleRow);
    /// <summary>Tabelle der Option AOption (Art "object-list", #1133) in ALine; Tag = AIndex.</summary>
    function BuildTable(ALine: TWinControl; const AOption: TAtlasRuleOption; AIndex: Integer): TControl;
  protected
    /// <summary>Regel ARow zeigen (APresent False: keine markiert); AOverriding nennt die Gegenregel (#1025).
    /// </summary>
    procedure ShowRow(const ARow: TAtlasRuleRow; APresent: Boolean; const AOverriding: string);
    procedure FillSeverities;
    /// <summary>Hauptschalter aus: Tabelle und alle Felder gesperrt (wie #890); ohne Auswahl nur die
    /// Beschreibung.</summary>
    procedure SetEditable(AOn, ASelected: Boolean);
    /// <summary>Eingabe in einem Feld einer Option (Tag = Index der Option).</summary>
    procedure OptionChange(Sender: TObject); virtual; abstract;
    /// <summary>Eingabe in der Tabelle einer Option (Tag = Index der Option).</summary>
    procedure OptionTableEdit(Sender: TObject; ACol, ARow: Integer; const AValue: string); virtual; abstract;
  public
    constructor Create(AOwner: TComponent); override;
    property TitleLabel: TLabel read FTitle;
    property MarkLabel: TLabel read FMark;
    property DescriptionLabel: TLabel read FDescription;
    property SeverityChoice: TComboBox read FSeverity;
    property ExcludeEdit: TEdit read FExclude;
    property OptionControls: TArray<TControl> read FOptionControls;
    property InvalidLabel: TLabel read FInvalid;
    property OptionsTitleLabel: TLabel read FOptionsTitle;
    property OptionsBox: TAtlasRulesBox read FOptionsBox;
    property BadLabel: TLabel read FBadLabel;
    property GoodLabel: TLabel read FGoodLabel;
    property BadMemo: TMemo read FBad;
    property GoodMemo: TMemo read FGood;
  end;

  TAtlasRulesEditor = class(TAtlasRulesDetailsView)
  private
    FCatalog: TJSONValue;
    FRulesJson: string;
    FOtherRulesJson: string;
    FRows: TArray<TAtlasRuleRow>;
    /// <summary>Zeilen der Tabelle als Index in FRows.</summary>
    FVisible: TArray<Integer>;
    FLoaded: Boolean;
    FDirty: Boolean;
    FSelectedId: string;
    FOnChange: TNotifyEvent;
    function RowOf(const AId: string): Integer;
    function SelectedRow: Integer;
    /// <summary>Lässt der Filter (Gruppe, Suche) die Zeile ARow (Index in FRows) stehen?</summary>
    function RowShown(ARow: Integer): Boolean;
    procedure Refill;
    procedure ShowDetails;
    procedure Apply(const ARulesJson: string);
    procedure SetFixedGroup(const AValue: string);
    /// <summary>Suche oder Gruppenauswahl geändert.</summary>
    procedure FilterChange(Sender: TObject);
    procedure MasterClick(Sender: TObject);
    procedure TypeLevelClick(Sender: TObject);
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListChecked(Sender: TObject; Item: TListItem);
    procedure SeverityChange(Sender: TObject);
    procedure ExcludeChange(Sender: TObject);
  protected
    procedure OptionChange(Sender: TObject); override;
    procedure OptionTableEdit(Sender: TObject; ACol, ARow: Integer; const AValue: string); override;
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Katalog (atlas.server.settingsCatalog, bleibt beim Aufrufer und muss leben, solange der Editor
    /// lebt; nil ohne Server), Wert von "rules" der bearbeiteten Datei und der anderen Ebene (im Projekt die
    /// globale Datei, sonst '').</summary>
    procedure SetRules(ACatalog: TJSONValue; const ARulesJson, AOtherRulesJson: string);
    /// <summary>„Regelkatalog wird geladen …“ bis SetRules.</summary>
    procedure ShowLoading;
    /// <summary>Markiert die Regel AId (setzt Suche und Gruppenauswahl zurück, wenn sie sie verbergen);
    /// False ohne sie.</summary>
    function SelectRule(const AId: string): Boolean;
    /// <summary>Schweregrad der markierten Regel setzen wie über die Auswahl ('' = Vorgabe).</summary>
    procedure SetSeverity(const ASeverity: string);
    /// <summary>Schweregrad der Regel AId setzen ('' = Vorgabe), ohne sie zu markieren; False ohne sie.</summary>
    function SetRuleSeverity(const AId, ASeverity: string): Boolean;
    /// <summary>Gruppe abgeschaltet ("group:&lt;gruppe&gt;": "off")?</summary>
    function GroupOff: Boolean;
    function HasRule(const AId: string): Boolean;
    /// <summary>Feste Gruppe (Knoten der Optionsseite); '' = alle Regeln mit Suche und Gruppenauswahl.
    /// </summary>
    property FixedGroup: string read FFixedGroup write SetFixedGroup;
    property RulesJson: string read FRulesJson;
    property Rows: TArray<TAtlasRuleRow> read FRows;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    /// <summary>Höhe oder Breite geändert; die Höhe folgt dem Inhalt der markierten Regel (#1296).</summary>
    property OnResize;
  end;

/// <summary>Beschriftung der Gruppe AGroup (Kennung des Katalogs) in der Sprache der Oberfläche.</summary>
function AtlasRuleGroupCaption(const AGroup: string): string;

implementation

uses
  Atlas.UI.Strings;

const
  Gap = 6;
  ListHeight = 230;
  /// <summary>Höhe der Beispiel-Memos bei kurzen Beispielen.</summary>
  MinMemoHeight = 72;
  /// <summary>Auswahl des Schweregrads; Eintrag 0 ist die Vorgabe.</summary>
  SeverityValues: array[0..5] of string = ('', 'error', 'warning', 'info', 'hint', 'off');
  GroupTexts: array[0..13] of TAtlasTextId = (TAtlasTextId.RulesGroupFindBugs, TAtlasTextId.RulesGroupExceptions,
    TAtlasTextId.RulesGroupThreads, TAtlasTextId.RulesGroupDatabase, TAtlasTextId.RulesGroupCompiler,
    TAtlasTextId.RulesGroupRobustness, TAtlasTextId.RulesGroupPerformance, TAtlasTextId.RulesGroupSecurity,
    TAtlasTextId.RulesGroupComponents, TAtlasTextId.RulesGroupForms, TAtlasTextId.RulesGroupArchitecture,
    TAtlasTextId.RulesGroupStyle, TAtlasTextId.RulesGroupPackages, TAtlasTextId.RulesGroupInternal);

{ TAtlasRulesBox }

constructor TAtlasRulesBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ShowCaption := False;
end;

function AtlasRuleGroupCaption(const AGroup: string): string;
var
  Index: Integer;
begin
  for Index := 0 to High(TAtlasRuleTable.GroupIds) do
  begin
    if SameText(TAtlasRuleTable.GroupIds[Index], AGroup) then
    begin
      Exit(TAtlasStrings.Text(GroupTexts[Index]));
    end;
  end;
  Result := AGroup;
end;


function SeverityCaption(const ASeverity: string): string;
begin
  if SameText(ASeverity, 'error') then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.RulesSeverityError);
  end
  else if SameText(ASeverity, 'warning') then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.RulesSeverityWarning);
  end
  else if SameText(ASeverity, 'info') or SameText(ASeverity, 'information') then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.RulesSeverityInfo);
  end
  else if SameText(ASeverity, 'hint') then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.RulesSeverityHint);
  end
  else if SameText(ASeverity, 'off') then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.RulesSeverityOff);
  end
  else
  begin
    Result := ASeverity;
  end;
end;

/// <summary>Spalte Schweregrad: eingestellt, sonst „Vorgabe (…)“; ein Wert der anderen Ebene steht dahinter als
/// „(global: …)“.</summary>
function SeverityColumn(const ARow: TAtlasRuleRow): string;
begin
  if ARow.Severity <> '' then
  begin
    Result := SeverityCaption(ARow.Severity);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.RulesSeverityDefault, [SeverityCaption(ARow.DefaultSeverity)]);
  end;
  if ARow.GlobalSeverity <> '' then
  begin
    Result := Result + ' ' + TAtlasStrings.Fmt(TAtlasTextId.RulesGlobal, [SeverityCaption(ARow.GlobalSeverity)]);
  end;
end;

/// <summary>Zeile der Tabelle; mit fester Gruppe steht in der dritten Spalte die Kategorie.</summary>
procedure FillItem(AItem: TListItem; const ARow: TAtlasRuleRow; AFixedGroup: Boolean);
begin
  AItem.Caption := ARow.Id;
  AItem.SubItems.Clear;
  AItem.SubItems.Add(ARow.Name);
  if AFixedGroup then
  begin
    AItem.SubItems.Add(ARow.Category);
  end
  else
  begin
    AItem.SubItems.Add(AtlasRuleGroupCaption(ARow.Group));
  end;
  AItem.SubItems.Add(SeverityColumn(ARow));
  AItem.SubItems.Add(TAtlasRuleTable.ListText(ARow.Exclude));
  AItem.Checked := ARow.Enabled;
end;

/// <summary>Eintrag der Auswahl des Schweregrads für ARow; 0 = Vorgabe.</summary>
function SeverityIndex(const ARow: TAtlasRuleRow): Integer;
var
  mValue: Integer;
begin
  Result := 0;
  for mValue := 1 to High(SeverityValues) do
  begin
    if SameText(SeverityValues[mValue], ARow.Severity) or
      (SameText(ARow.Severity, 'information') and (SeverityValues[mValue] = 'info')) then
    begin
      Result := mValue;
    end;
  end;
end;

/// <summary>Schweregrad nach dem Haken in der Tabelle: aus "off"; an die Vorgabe, wenn sie meldet, sonst Warnung.
/// </summary>
function CheckedSeverity(const ARow: TAtlasRuleRow; AChecked: Boolean): string;
begin
  Result := 'off';
  if AChecked then
  begin
    Result := '';
    if SameText(ARow.DefaultSeverity, 'off') or SameText(ARow.GlobalSeverity, 'off') then
    begin
      Result := 'warning';
    end;
  end;
end;

/// <summary>Text über der Tabelle: lädt, kein Katalog, keine Regel; '' sonst.</summary>
function StatusText(ALoaded, AHasCatalog, AEmpty: Boolean): string;
begin
  Result := '';
  if not ALoaded then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.RulesLoading);
  end
  else if not AHasCatalog then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.RulesNoCatalog);
  end
  else if AEmpty then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.RulesEmpty);
  end;
end;

/// <summary>AControl und alle Kinder sperren bzw. freigeben.</summary>
procedure SetTreeEnabled(AControl: TControl; AEnabled: Boolean);
var
  mIndex: Integer;
begin
  AControl.Enabled := AEnabled;
  if AControl is TWinControl then
  begin
    for mIndex := 0 to TWinControl(AControl).ControlCount - 1 do
    begin
      SetTreeEnabled(TWinControl(AControl).Controls[mIndex], AEnabled);
    end;
  end;
end;

/// <summary>Zellen der Tabelle AGrid ohne Kopfzeile.</summary>
function GridCells(AGrid: TStringGrid): TArray<TArray<string>>;
var
  mRow, mCol: Integer;
  mLine: TArray<string>;
begin
  Result := nil;
  for mRow := AGrid.FixedRows to AGrid.RowCount - 1 do
  begin
    mLine := nil;
    for mCol := 0 to AGrid.ColCount - 1 do
    begin
      mLine := mLine + [AGrid.Cells[mCol, mRow]];
    end;
    Result := Result + [mLine];
  end;
end;

/// <summary>Kästchen für eine Option vom Typ boolean.</summary>
function NewOptionCheck(AOwner: TComponent; ALine: TWinControl; const AOption: TAtlasRuleOption;
  AOnClick: TNotifyEvent): TControl;
var
  mCheck: TCheckBox;
begin
  mCheck := TCheckBox.Create(AOwner);
  mCheck.Parent := ALine;
  mCheck.Align := alClient;
  mCheck.Caption := AOption.Name;
  mCheck.Hint := AOption.Description;
  mCheck.ShowHint := AOption.Description <> '';
  mCheck.Checked := SameText(TAtlasRuleTable.OptionText(AOption), 'true');
  mCheck.OnClick := AOnClick;
  Result := mCheck;
end;

/// <summary>Beschriftung und Feld für eine Option (Zahl, Text, Liste, JSON).</summary>
function NewOptionEdit(AOwner: TComponent; ALine: TWinControl; const AOption: TAtlasRuleOption;
  AOnChange: TNotifyEvent): TControl;
var
  mCaption: TLabel;
  mEdit: TEdit;
begin
  mCaption := TLabel.Create(AOwner);
  mCaption.Parent := ALine;
  mCaption.Align := alLeft;
  mCaption.AutoSize := False;
  mCaption.Width := 160;
  mCaption.Layout := tlCenter;
  mCaption.ShowAccelChar := False;
  mCaption.Caption := AOption.Name + ':';
  mCaption.Hint := AOption.Description;
  mCaption.ShowHint := AOption.Description <> '';
  mEdit := TEdit.Create(AOwner);
  mEdit.Parent := ALine;
  mEdit.Align := alClient;
  mEdit.Text := TAtlasRuleTable.OptionText(AOption);
  mEdit.NumbersOnly := SameText(AOption.Kind, 'integer');
  mEdit.Hint := AOption.Description;
  mEdit.ShowHint := AOption.Description <> '';
  mEdit.OnChange := AOnChange;
  Result := mEdit;
end;

{ TAtlasRulesLayout }

constructor TAtlasRulesLayout.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AutoSize := True;
  FNextTop := 0;
end;

function TAtlasRulesLayout.AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
  Stack(AParent, Result);
end;

function TAtlasRulesLayout.AddMemo(AParent: TWinControl): TMemo;
begin
  Result := TMemo.Create(Self);
  Result.ReadOnly := True;
  Result.ScrollBars := ssHorizontal;
  Result.WordWrap := False;
  Result.Font.Name := 'Consolas';
  Result.Height := MinMemoHeight;
  Stack(AParent, Result);
end;

procedure TAtlasRulesLayout.FitMemo(AMemo: TMemo);
const
  MaxLines = 20;
var
  Lines, LineHeight: Integer;
  Bars: System.UITypes.TScrollStyle;
begin
  // Das ganze Beispiel zeigen statt vier Zeilen mit Rollbalken; sehr lange Beispiele bleiben rollbar.
  Lines := EnsureRange(AMemo.Lines.Count, 1, MaxLines);
  LineHeight := MulDiv(Abs(AMemo.Font.Height), 5, 4);
  Bars := ssHorizontal;
  if AMemo.Lines.Count > MaxLines then
  begin
    Bars := ssBoth;
  end;
  // Nur bei Änderung: ScrollBars legt das Fenster des Memos neu an.
  if AMemo.ScrollBars <> Bars then
  begin
    AMemo.ScrollBars := Bars;
  end;
  // Nie kleiner als bisher: Kurze Beispiele behalten ihre gewohnte Höhe.
  AMemo.Height := Max(MinMemoHeight, Lines * LineHeight + GetSystemMetrics(SM_CYHSCROLL) + 8);
end;

procedure TAtlasRulesLayout.Stack(AParent: TWinControl; AControl: TControl);
begin
  // Ein Zähler für alle Behälter: Nur die Reihenfolge innerhalb eines Behälters zählt.
  Inc(FNextTop, 1000);
  AControl.Parent := AParent;
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Top := FNextTop;
  FStacked := FStacked + [AControl];
end;

procedure TAtlasRulesLayout.Restack;
var
  Control: TControl;
  Next: Integer;
begin
  // alTop ordnet nach Top. Ausgeblendete Steuerelemente behalten ihr Top aus dem Aufbau, das größer ist als das
  // der inzwischen ausgerichteten Geschwister; eingeblendet rutschten sie ans Ende (#1296). Darum alle in
  // Aufbaureihenfolge neu durchnummerieren, jedes hinter alle bisherigen. In Einerschritten: Mit 1000er-Schritten
  // kamen die Memos über 32767, dort kappt Windows ihre Koordinaten (die Beschriftungen ohne Fenster nicht), und
  // „Falsch“/„Richtig“ standen unter statt über ihrem Memo.
  Next := FNextTop;
  DisableAlign;
  FDetails.DisableAlign;
  try
    for Control in FStacked do
    begin
      Inc(Next);
      Control.Top := Next;
    end;
  finally
    FDetails.EnableAlign;
    EnableAlign;
  end;
  // Höhe ausdrücklich nachziehen: Nach DisableAlign/EnableAlign rechnet AutoSize sie nicht neu, der Editor
  // behielt seine alte Höhe und überdeckte die Felder darunter (DialogRuleEditorPushesFieldsDown).
  FDetails.AdjustSize;
  AdjustSize;
end;

function TAtlasRulesLayout.CanAutoSize(var NewWidth, NewHeight: Integer): Boolean;
var
  Requested: Integer;
begin
  Requested := NewWidth;
  Result := inherited CanAutoSize(NewWidth, NewHeight);
  NewWidth := Requested;
end;

{ TAtlasRulesTable }

constructor TAtlasRulesTable.Create(AOwner: TComponent);
var
  mColumn: TListColumn;
  mIndex: Integer;
const
  cColumns: array[0..4] of TAtlasTextId = (TAtlasTextId.RulesColumnId, TAtlasTextId.RulesColumnName,
    TAtlasTextId.RulesColumnGroup, TAtlasTextId.RulesColumnSeverity, TAtlasTextId.RulesColumnExclude);
  cWidths: array[0..4] of Integer = (190, 220, 120, 150, 140);
begin
  inherited Create(AOwner);
  FTopBar := TAtlasRulesBox.Create(Self);
  FTopBar.Height := 26;
  Stack(Self, FTopBar);
  FSearch := TEdit.Create(Self);
  FSearch.Parent := FTopBar;
  FSearch.Align := alClient;
  FSearch.TextHint := TAtlasStrings.Text(TAtlasTextId.RulesSearchHint);
  FGroupChoice := TComboBox.Create(Self);
  FGroupChoice.Parent := FTopBar;
  FGroupChoice.Align := alRight;
  FGroupChoice.AlignWithMargins := True;
  FGroupChoice.Margins.SetBounds(Gap, 0, 0, 0);
  FGroupChoice.Width := 200;
  FGroupChoice.Style := csDropDownList;
  FMaster := TCheckBox.Create(Self);
  FMaster.Height := 20;
  FMaster.Visible := False;
  Stack(Self, FMaster);
  FTypeLevel := TCheckBox.Create(Self);
  FTypeLevel.Height := 20;
  FTypeLevel.Visible := False;
  FTypeLevel.Caption := TAtlasStrings.Text(TAtlasTextId.RulesTypeLevel);
  FTypeLevel.AlignWithMargins := True;
  FTypeLevel.Margins.SetBounds(18, 0, 0, 0);
  Stack(Self, FTypeLevel);
  FStatus := AddLabel(Self, '');
  FStatus.Font.Color := clGrayText;
  FStatus.Visible := False;
  FList := TListView.Create(Self);
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.Checkboxes := True;
  FList.Height := ListHeight;
  for mIndex := 0 to High(cColumns) do
  begin
    mColumn := FList.Columns.Add;
    mColumn.Caption := TAtlasStrings.Text(cColumns[mIndex]);
    mColumn.Width := cWidths[mIndex];
  end;
  Stack(Self, FList);
end;

function TAtlasRulesTable.Group: string;
begin
  Result := FFixedGroup;
  if (Result = '') and (FGroupChoice.ItemIndex > 0) and
    (FGroupChoice.ItemIndex <= Length(TAtlasRuleTable.GroupIds)) then
  begin
    Result := TAtlasRuleTable.GroupIds[FGroupChoice.ItemIndex - 1];
  end;
end;

procedure TAtlasRulesTable.ShowFixedGroup(const AValue: string);
begin
  FFixedGroup := AValue;
  // Fester Knoten einer Gruppe: keine Suche und keine Gruppenauswahl; die Spalte zeigt die Kategorie.
  FTopBar.Visible := AValue = '';
  if AValue <> '' then
  begin
    FList.Columns[2].Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsColumnCategory);
  end
  else
  begin
    FList.Columns[2].Caption := TAtlasStrings.Text(TAtlasTextId.RulesColumnGroup);
  end;
end;

procedure TAtlasRulesTable.ShowMaster(const ARulesJson: string);
begin
  FMaster.Visible := Group <> '';
  FTypeLevel.Visible := SameText(Group, TAtlasRuleTable.CompilerGroup);
  if Group = '' then
  begin
    Exit;
  end;
  FMaster.Caption := TAtlasStrings.Fmt(TAtlasTextId.RulesGroupMaster, [AtlasRuleGroupCaption(Group)]);
  FFilling := True;
  try
    FMaster.Checked := not TAtlasRuleTable.GroupOff(ARulesJson, Group);
    FTypeLevel.Checked := not SameText(TAtlasRuleTable.GroupOption(ARulesJson, Group, 'typeLevel'), 'off');
  finally
    FFilling := False;
  end;
end;

procedure TAtlasRulesTable.ShowStatus(const AText: string);
begin
  FStatus.Caption := AText;
  FStatus.Visible := AText <> '';
end;

procedure TAtlasRulesTable.FillGroups;
var
  mIndex: Integer;
begin
  if FGroupChoice.Items.Count > 0 then
  begin
    Exit;
  end;
  FGroupChoice.Items.BeginUpdate;
  try
    FGroupChoice.Items.Add(TAtlasStrings.Text(TAtlasTextId.RulesAllGroups));
    for mIndex := 0 to High(TAtlasRuleTable.GroupIds) do
    begin
      FGroupChoice.Items.Add(AtlasRuleGroupCaption(TAtlasRuleTable.GroupIds[mIndex]));
    end;
  finally
    FGroupChoice.Items.EndUpdate;
  end;
  FGroupChoice.ItemIndex := 0;
end;

{ TAtlasRulesDetailsView }

constructor TAtlasRulesDetailsView.Create(AOwner: TComponent);
var
  mCaption: TLabel;
begin
  inherited Create(AOwner);
  FDetails := TAtlasRulesBox.Create(Self);
  FDetails.AutoSize := True;
  Stack(Self, FDetails);
  FTitle := AddLabel(FDetails, TAtlasStrings.Text(TAtlasTextId.RulesNoSelection));
  FTitle.Font.Style := [fsBold];
  FMark := AddLabel(FDetails, TAtlasStrings.Text(TAtlasTextId.ProblemsExperimental));
  FMark.Font.Color := $000080C0;
  FMark.Visible := False;
  FDescription := AddLabel(FDetails, '');
  FDescription.WordWrap := True;
  FSeverityRow := TAtlasRulesBox.Create(Self);
  FSeverityRow.Height := 24;
  Stack(FDetails, FSeverityRow);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := FSeverityRow;
  mCaption.Align := alLeft;
  mCaption.Layout := tlCenter;
  mCaption.Width := 160;
  mCaption.AutoSize := False;
  mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.RulesSeverity);
  FSeverity := TComboBox.Create(Self);
  FSeverity.Parent := FSeverityRow;
  FSeverity.Align := alLeft;
  FSeverity.Width := 200;
  FSeverity.Style := csDropDownList;
  FExcludeLabel := AddLabel(FDetails, TAtlasStrings.Text(TAtlasTextId.RulesExclude));
  FExclude := TEdit.Create(Self);
  Stack(FDetails, FExclude);
  FOptionsTitle := AddLabel(FDetails, TAtlasStrings.Text(TAtlasTextId.RulesOptions));
  FOptionsTitle.Font.Style := [fsBold];
  FOptionsBox := TAtlasRulesBox.Create(Self);
  FOptionsBox.AutoSize := True;
  Stack(FDetails, FOptionsBox);
  FInvalid := AddLabel(FDetails, '');
  FInvalid.Font.Color := clRed;
  FInvalid.Visible := False;
  FBadLabel := AddLabel(FDetails, TAtlasStrings.Text(TAtlasTextId.ProblemsExplainBad));
  FBadLabel.Font.Color := $003C3CD8;
  FBad := AddMemo(FDetails);
  FGoodLabel := AddLabel(FDetails, TAtlasStrings.Text(TAtlasTextId.ProblemsExplainGood));
  FGoodLabel.Font.Color := $0050A030;
  FGood := AddMemo(FDetails);
end;

procedure TAtlasRulesDetailsView.FillSeverities;
var
  mValue: string;
begin
  if FSeverity.Items.Count > 0 then
  begin
    Exit;
  end;
  for mValue in SeverityValues do
  begin
    if mValue = '' then
    begin
      FSeverity.Items.Add(TAtlasStrings.Fmt(TAtlasTextId.RulesSeverityDefault, ['']));
    end
    else
    begin
      FSeverity.Items.Add(SeverityCaption(mValue));
    end;
  end;
end;

procedure TAtlasRulesDetailsView.SetEditable(AOn, ASelected: Boolean);
begin
  TypeLevel.Enabled := AOn;
  List.Enabled := AOn;
  SetTreeEnabled(FDetails, AOn and ASelected);
  FTitle.Enabled := True;
  FDescription.Enabled := True;
end;

procedure TAtlasRulesDetailsView.ShowRow(const ARow: TAtlasRuleRow; APresent: Boolean; const AOverriding: string);
begin
  FTitle.Caption := TAtlasStrings.Text(TAtlasTextId.RulesNoSelection);
  if APresent then
  begin
    FTitle.Caption := ARow.Id;
  end;
  if APresent and (ARow.Name <> '') then
  begin
    FTitle.Caption := ARow.Name + '  ·  ' + ARow.Id;
  end;
  FMark.Visible := APresent and ARow.Experimental;
  FDescription.Caption := ARow.Description;
  // Gegenregel an (#1025): z. B. redundant-begin-end schweigt, solange missing-begin-end an ist.
  if AOverriding <> '' then
  begin
    FDescription.Caption := Trim(ARow.Description + sLineBreak + sLineBreak +
      TAtlasStrings.Fmt(TAtlasTextId.RulesOverriddenBy, [AOverriding]));
  end;
  if FSeverity.Items.Count > 0 then
  begin
    FSeverity.ItemIndex := -1;
  end;
  if APresent and (FSeverity.Items.Count > 0) then
  begin
    FSeverity.Items[0] := TAtlasStrings.Fmt(TAtlasTextId.RulesSeverityDefault,
      [SeverityCaption(ARow.DefaultSeverity)]);
    FSeverity.ItemIndex := SeverityIndex(ARow);
  end;
  FExclude.Text := TAtlasRuleTable.ListText(ARow.Exclude);
  BuildOptions(ARow);
  FBad.Lines.Text := ARow.Bad;
  FGood.Lines.Text := ARow.Good;
  if APresent then
  begin
    FitMemo(FBad);
    FitMemo(FGood);
  end;
  FBadLabel.Visible := APresent and (ARow.Bad <> '');
  FBad.Visible := FBadLabel.Visible;
  FGoodLabel.Visible := APresent and (ARow.Good <> '');
  FGood.Visible := FGoodLabel.Visible;
  FInvalid.Visible := False;
end;

procedure TAtlasRulesDetailsView.BuildOptions(const ARow: TAtlasRuleRow);
var
  mIndex: Integer;
  mOption: TAtlasRuleOption;
  mLine: TAtlasRulesBox;
  mControl: TControl;
begin
  for mControl in FOptionControls do
  begin
    mControl.Parent.Free;
  end;
  FOptionControls := nil;
  FOptionsTitle.Visible := Length(ARow.Options) > 0;
  for mIndex := 0 to High(ARow.Options) do
  begin
    mOption := ARow.Options[mIndex];
    mLine := TAtlasRulesBox.Create(Self);
    mLine.Parent := FOptionsBox;
    mLine.Align := alTop;
    mLine.AlignWithMargins := True;
    mLine.Height := 24;
    mLine.Top := mIndex * 30;
    if SameText(mOption.Kind, 'boolean') then
    begin
      mControl := NewOptionCheck(Self, mLine, mOption, OptionChange);
    end
    else if SameText(mOption.Kind, 'object-list') and (mOption.Columns <> nil) then
    begin
      mLine.Height := 150;
      mControl := BuildTable(mLine, mOption, mIndex);
    end
    else
    begin
      mControl := NewOptionEdit(Self, mLine, mOption, OptionChange);
    end;
    mControl.Tag := mIndex;
    FOptionControls := FOptionControls + [mControl];
  end;
end;

function TAtlasRulesDetailsView.BuildTable(ALine: TWinControl; const AOption: TAtlasRuleOption;
  AIndex: Integer): TControl;
var
  mCaption: TLabel;
  mGrid: TStringGrid;
  mCells: TArray<TArray<string>>;
  mRow, mCol: Integer;
begin
  mCaption := TLabel.Create(Self);
  mCaption.Parent := ALine;
  mCaption.Align := alTop;
  mCaption.ShowAccelChar := False;
  mCaption.Caption := AOption.Name + ':';
  mCaption.Hint := AOption.Description;
  mCaption.ShowHint := AOption.Description <> '';
  // Eine Zeile je Eintrag und unten eine leere für den nächsten; eine geleerte Zeile entfällt beim Speichern.
  mCells := TAtlasRuleTable.TableCells(AOption);
  mGrid := TStringGrid.Create(Self);
  mGrid.Parent := ALine;
  mGrid.Align := alClient;
  mGrid.ColCount := Length(AOption.Columns);
  mGrid.RowCount := Length(mCells) + 2;
  mGrid.FixedCols := 0;
  mGrid.FixedRows := 1;
  mGrid.Options := mGrid.Options + [goEditing, goTabs, goColSizing, goThumbTracking];
  mGrid.Hint := AOption.Description;
  mGrid.ShowHint := AOption.Description <> '';
  for mCol := 0 to High(AOption.Columns) do
  begin
    mGrid.Cells[mCol, 0] := AOption.Columns[mCol].Name;
    mGrid.ColWidths[mCol] := 120;
  end;
  for mRow := 0 to High(mCells) do
  begin
    for mCol := 0 to High(mCells[mRow]) do
    begin
      mGrid.Cells[mCol, mRow + 1] := mCells[mRow][mCol];
    end;
  end;
  mGrid.OnSetEditText := OptionTableEdit;
  mGrid.Tag := AIndex;
  Result := mGrid;
end;

{ TAtlasRulesEditor }

constructor TAtlasRulesEditor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Search.OnChange := FilterChange;
  GroupChoice.OnChange := FilterChange;
  Master.OnClick := MasterClick;
  TypeLevel.OnClick := TypeLevelClick;
  List.OnSelectItem := ListSelect;
  List.OnItemChecked := ListChecked;
  SeverityChoice.OnChange := SeverityChange;
  ExcludeEdit.OnChange := ExcludeChange;
  // Auswahl und Memos brauchen ein Fenster: CreateWnd füllt über Refill auch die Details.
  FDirty := True;
end;

procedure TAtlasRulesEditor.CreateWnd;
begin
  inherited CreateWnd;
  // Auswahllisten und Tabelle brauchen ein Fenster.
  FillGroups;
  FillSeverities;
  if FDirty then
  begin
    Refill;
  end;
end;

procedure TAtlasRulesEditor.SetFixedGroup(const AValue: string);
begin
  ShowFixedGroup(AValue);
  FDirty := True;
  if HandleAllocated then
  begin
    Refill;
  end;
end;

procedure TAtlasRulesEditor.SetRules(ACatalog: TJSONValue; const ARulesJson, AOtherRulesJson: string);
begin
  FCatalog := ACatalog;
  FRulesJson := ARulesJson;
  FOtherRulesJson := AOtherRulesJson;
  FRows := TAtlasRuleTable.Rows(FCatalog, FRulesJson, FOtherRulesJson);
  FLoaded := True;
  FDirty := True;
  if HandleAllocated then
  begin
    Refill;
  end;
end;

procedure TAtlasRulesEditor.ShowLoading;
begin
  FLoaded := False;
  ShowStatus(TAtlasStrings.Text(TAtlasTextId.RulesLoading));
  Restack;
end;

function TAtlasRulesEditor.GroupOff: Boolean;
begin
  Result := (Group <> '') and TAtlasRuleTable.GroupOff(FRulesJson, Group);
end;

function TAtlasRulesEditor.RowOf(const AId: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FRows) do
  begin
    if SameText(FRows[Index].Id, AId) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function TAtlasRulesEditor.HasRule(const AId: string): Boolean;
begin
  Result := RowOf(AId) >= 0;
end;

function TAtlasRulesEditor.SelectedRow: Integer;
begin
  Result := -1;
  if (List.Selected <> nil) and (List.Selected.Index <= High(FVisible)) then
  begin
    Result := FVisible[List.Selected.Index];
  end;
end;

function TAtlasRulesEditor.RowShown(ARow: Integer): Boolean;
var
  Index: Integer;
begin
  for Index in TAtlasRuleTable.Filter(FRows, Group, Search.Text) do
  begin
    if Index = ARow then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasRulesEditor.Refill;
var
  mIndex, mSelected: Integer;
begin
  FDirty := False;
  if SelectedRow >= 0 then
  begin
    FSelectedId := FRows[SelectedRow].Id;
  end;
  FVisible := TAtlasRuleTable.Filter(FRows, Group, Search.Text);
  ShowStatus(StatusText(FLoaded, FCatalog <> nil, Length(FVisible) = 0));
  mSelected := -1;
  FFilling := True;
  List.Items.BeginUpdate;
  try
    List.Items.Clear;
    for mIndex := 0 to High(FVisible) do
    begin
      FillItem(List.Items.Add, FRows[FVisible[mIndex]], FFixedGroup <> '');
      if SameText(FRows[FVisible[mIndex]].Id, FSelectedId) then
      begin
        mSelected := mIndex;
      end;
    end;
  finally
    List.Items.EndUpdate;
    FFilling := False;
  end;
  if mSelected >= 0 then
  begin
    FFilling := True;
    try
      List.Items[mSelected].Selected := True;
      List.Items[mSelected].Focused := True;
    finally
      FFilling := False;
    end;
  end;
  ShowMaster(FRulesJson);
  ShowDetails;
end;

procedure TAtlasRulesEditor.ShowDetails;
var
  mIndex: Integer;
  mRow: TAtlasRuleRow;
  mOverriding: string;
begin
  mIndex := SelectedRow;
  mRow := Default(TAtlasRuleRow);
  mOverriding := '';
  if mIndex >= 0 then
  begin
    mRow := FRows[mIndex];
    mOverriding := TAtlasRuleTable.OverridingRule(FRows, mRow);
  end;
  FFilling := True;
  try
    ShowRow(mRow, mIndex >= 0, mOverriding);
  finally
    FFilling := False;
  end;
  Restack;
  SetEditable(not GroupOff, SelectedRow >= 0);
end;

procedure TAtlasRulesEditor.Apply(const ARulesJson: string);
var
  mIndex, mVisible: Integer;
begin
  // Zeilen aus dem neuen Wert; die Tabelle wird nur nachgeführt, damit Fokus und Eingabe bleiben.
  FRulesJson := ARulesJson;
  FRows := TAtlasRuleTable.Rows(FCatalog, FRulesJson, FOtherRulesJson);
  FFilling := True;
  try
    for mVisible := 0 to High(FVisible) do
    begin
      mIndex := FVisible[mVisible];
      if (mIndex <= High(FRows)) and (mVisible < List.Items.Count) then
      begin
        FillItem(List.Items[mVisible], FRows[mIndex], FFixedGroup <> '');
      end;
    end;
  finally
    FFilling := False;
  end;
  ShowMaster(FRulesJson);
  SetEditable(not GroupOff, SelectedRow >= 0);
  if Assigned(FOnChange) then
  begin
    FOnChange(Self);
  end;
end;

function TAtlasRulesEditor.SelectRule(const AId: string): Boolean;
var
  Index, Row: Integer;
begin
  Row := RowOf(AId);
  Result := Row >= 0;
  if not Result then
  begin
    Exit;
  end;
  FSelectedId := FRows[Row].Id;
  if HandleAllocated then
  begin
    // Suche und Gruppenauswahl, die die Regel verbergen, zurücksetzen.
    if (FFixedGroup = '') and not RowShown(Row) then
    begin
      FFilling := True;
      try
        Search.Text := '';
        GroupChoice.ItemIndex := 0;
      finally
        FFilling := False;
      end;
    end;
    Refill;
    for Index := 0 to High(FVisible) do
    begin
      if FVisible[Index] = Row then
      begin
        List.Items[Index].Selected := True;
        List.Items[Index].Focused := True;
        List.Items[Index].MakeVisible(False);
      end;
    end;
  end
  else
  begin
    FDirty := True;
  end;
end;

procedure TAtlasRulesEditor.SetSeverity(const ASeverity: string);
var
  Row: Integer;
begin
  Row := SelectedRow;
  if Row < 0 then
  begin
    Exit;
  end;
  Apply(TAtlasRuleTable.WithSeverity(FRulesJson, FRows[Row].Id, ASeverity));
  ShowDetails;
end;

function TAtlasRulesEditor.SetRuleSeverity(const AId, ASeverity: string): Boolean;
var
  Row: Integer;
begin
  Row := RowOf(AId);
  Result := Row >= 0;
  if not Result then
  begin
    Exit;
  end;
  Apply(TAtlasRuleTable.WithSeverity(FRulesJson, FRows[Row].Id, ASeverity));
  if Row = SelectedRow then
  begin
    ShowDetails;
  end;
end;

procedure TAtlasRulesEditor.FilterChange(Sender: TObject);
begin
  if not FFilling then
  begin
    Refill;
  end;
end;

procedure TAtlasRulesEditor.MasterClick(Sender: TObject);
begin
  if FFilling or (Group = '') then
  begin
    Exit;
  end;
  Apply(TAtlasRuleTable.WithGroup(FRulesJson, Group, Master.Checked));
end;

procedure TAtlasRulesEditor.TypeLevelClick(Sender: TObject);
var
  mValue: string;
begin
  if FFilling or (Group = '') then
  begin
    Exit;
  end;
  mValue := '';
  if not TypeLevel.Checked then
  begin
    mValue := 'off';
  end;
  Apply(TAtlasRuleTable.WithGroupOption(FRulesJson, Group, 'typeLevel', mValue));
end;

procedure TAtlasRulesEditor.ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FFilling then
  begin
    Exit;
  end;
  if SelectedRow >= 0 then
  begin
    FSelectedId := FRows[SelectedRow].Id;
  end;
  ShowDetails;
end;

procedure TAtlasRulesEditor.ListChecked(Sender: TObject; Item: TListItem);
var
  mRow: Integer;
begin
  if FFilling or (Item = nil) or (Item.Index > High(FVisible)) then
  begin
    Exit;
  end;
  mRow := FVisible[Item.Index];
  if Item.Checked = FRows[mRow].Enabled then
  begin
    Exit;
  end;
  Apply(TAtlasRuleTable.WithSeverity(FRulesJson, FRows[mRow].Id, CheckedSeverity(FRows[mRow], Item.Checked)));
  if mRow = SelectedRow then
  begin
    ShowDetails;
  end;
end;

procedure TAtlasRulesEditor.SeverityChange(Sender: TObject);
begin
  if FFilling or (SeverityChoice.ItemIndex < 0) or (SeverityChoice.ItemIndex > High(SeverityValues)) then
  begin
    Exit;
  end;
  SetSeverity(SeverityValues[SeverityChoice.ItemIndex]);
end;

procedure TAtlasRulesEditor.ExcludeChange(Sender: TObject);
var
  mRow: Integer;
begin
  mRow := SelectedRow;
  if FFilling or (mRow < 0) then
  begin
    Exit;
  end;
  Apply(TAtlasRuleTable.WithExclude(FRulesJson, FRows[mRow].Id, TAtlasRuleTable.ParseList(ExcludeEdit.Text)));
end;

procedure TAtlasRulesEditor.OptionChange(Sender: TObject);
var
  Row, Index: Integer;
  Option: TAtlasRuleOption;
  mText, Json: string;
begin
  Row := SelectedRow;
  if FFilling or (Row < 0) or not (Sender is TControl) then
  begin
    Exit;
  end;
  Index := TControl(Sender).Tag;
  if (Index < 0) or (Index > High(FRows[Row].Options)) then
  begin
    Exit;
  end;
  Option := FRows[Row].Options[Index];
  if Sender is TCheckBox then
  begin
    mText := 'false';
    if TCheckBox(Sender).Checked then
    begin
      mText := 'true';
    end;
  end
  else
  begin
    mText := TEdit(Sender).Text;
  end;
  // Ungültige Eingabe bleibt im Feld stehen, wird aber nicht übernommen.
  if not TAtlasRuleTable.OptionJson(Option.Kind, mText, Json) then
  begin
    InvalidLabel.Caption := TAtlasStrings.Fmt(TAtlasTextId.RulesOptionInvalid, [Option.Name]);
    if not InvalidLabel.Visible then
    begin
      InvalidLabel.Visible := True;
      Restack;
    end;
    Exit;
  end;
  if InvalidLabel.Visible then
  begin
    InvalidLabel.Visible := False;
    Restack;
  end;
  // Gleich der Vorgabe: Option entfernen.
  if Json = Option.DefaultJson then
  begin
    Json := '';
  end;
  Apply(TAtlasRuleTable.WithOption(FRulesJson, FRows[Row].Id, Option.Name, Json));
end;

procedure TAtlasRulesEditor.OptionTableEdit(Sender: TObject; ACol, ARow: Integer; const AValue: string);
var
  mGrid: TStringGrid;
  mRuleRow, mIndex: Integer;
  mOption: TAtlasRuleOption;
  mJson: string;
begin
  mRuleRow := SelectedRow;
  if FFilling or (mRuleRow < 0) or not (Sender is TStringGrid) then
  begin
    Exit;
  end;
  mGrid := TStringGrid(Sender);
  mIndex := mGrid.Tag;
  if (mIndex < 0) or (mIndex > High(FRows[mRuleRow].Options)) then
  begin
    Exit;
  end;
  mOption := FRows[mRuleRow].Options[mIndex];
  // Unten bleibt immer eine leere Zeile für den nächsten Eintrag.
  if (ARow = mGrid.RowCount - 1) and (Trim(AValue) <> '') then
  begin
    mGrid.RowCount := mGrid.RowCount + 1;
  end;
  mJson := TAtlasRuleTable.TableJson(mOption, GridCells(mGrid));
  // Gleich der Vorgabe: Option entfernen.
  if mJson = mOption.DefaultJson then
  begin
    mJson := '';
  end;
  InvalidLabel.Visible := False;
  Apply(TAtlasRuleTable.WithOption(FRulesJson, FRows[mRuleRow].Id, mOption.Name, mJson));
end;

end.
