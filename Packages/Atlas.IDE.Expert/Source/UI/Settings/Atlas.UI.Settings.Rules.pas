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
//     JSON) und die Beispiele falsch und richtig.
// Reine VCL; das Modell ist TAtlasRuleTable. Der Editor kennt weder Dateien
// noch Server: Er bekommt den Katalog und den Wert von "rules" und meldet
// Änderungen über OnChange; RulesJson ist der neue Wert. Tabelle und Auswahl-
// listen brauchen ein Fenster und werden erst mit Handle gefüllt (CreateWnd).

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Settings.RuleTable;

type
  /// <summary>Behälter ohne Rahmen und Beschriftung (Zeilen und Bereiche des Editors).</summary>
  TAtlasRulesBox = class(TCustomPanel)
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TAtlasRulesEditor = class(TCustomPanel)
  private
    FCatalog: TJSONValue;
    FRulesJson: string;
    FOtherRulesJson: string;
    FRows: TArray<TAtlasRuleRow>;
    /// <summary>Zeilen der Tabelle als Index in FRows.</summary>
    FVisible: TArray<Integer>;
    FFixedGroup: string;
    FLoaded: Boolean;
    FFilling: Boolean;
    FDirty: Boolean;
    FSelectedId: string;
    FOnChange: TNotifyEvent;
    FTopBar: TAtlasRulesBox;
    FSearch: TEdit;
    FGroupChoice: TComboBox;
    FMaster: TCheckBox;
    FTypeLevel: TCheckBox;
    FStatus: TLabel;
    FList: TListView;
    FDetails: TAtlasRulesBox;
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
    FNextTop: Integer;
    function AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
    function AddMemo(AParent: TWinControl): TMemo;
    /// <summary>AControl oben in AParent unter die bisherigen (alTop ordnet nach Top).</summary>
    procedure Stack(AParent: TWinControl; AControl: TControl);
    function Group: string;
    function RowOf(const AId: string): Integer;
    function SelectedRow: Integer;
    /// <summary>Lässt der Filter (Gruppe, Suche) die Zeile ARow (Index in FRows) stehen?</summary>
    function RowShown(ARow: Integer): Boolean;
    function GroupCaption(const AGroup: string): string;
    function SeverityCaption(const ASeverity: string): string;
    function SeverityColumn(const ARow: TAtlasRuleRow): string;
    procedure FillItem(AItem: TListItem; const ARow: TAtlasRuleRow);
    procedure FillChoices;
    procedure Refill;
    procedure ShowDetails;
    procedure BuildOptions(const ARow: TAtlasRuleRow);
    procedure UpdateEnabled;
    procedure UpdateMaster;
    procedure Apply(const ARulesJson: string);
    procedure SetFixedGroup(const AValue: string);
    procedure SearchChange(Sender: TObject);
    procedure GroupChoiceChange(Sender: TObject);
    procedure MasterClick(Sender: TObject);
    procedure TypeLevelClick(Sender: TObject);
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListChecked(Sender: TObject; Item: TListItem);
    procedure SeverityChange(Sender: TObject);
    procedure ExcludeChange(Sender: TObject);
    procedure OptionChange(Sender: TObject);
  protected
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
    /// <summary>Gruppe abgeschaltet ("group:<gruppe>": "off")?</summary>
    function GroupOff: Boolean;
    function HasRule(const AId: string): Boolean;
    /// <summary>Feste Gruppe (Knoten der Optionsseite); '' = alle Regeln mit Suche und Gruppenauswahl.
    /// </summary>
    property FixedGroup: string read FFixedGroup write SetFixedGroup;
    property RulesJson: string read FRulesJson;
    property Rows: TArray<TAtlasRuleRow> read FRows;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property Search: TEdit read FSearch;
    property GroupChoice: TComboBox read FGroupChoice;
    property Master: TCheckBox read FMaster;
    /// <summary>Stufe T der Gruppe „Compiler vorab“ (#1024); nur in dieser Gruppe sichtbar.</summary>
    property TypeLevel: TCheckBox read FTypeLevel;
    property Status: TLabel read FStatus;
    property List: TListView read FList;
    property Details: TAtlasRulesBox read FDetails;
    property TitleLabel: TLabel read FTitle;
    property MarkLabel: TLabel read FMark;
    property DescriptionLabel: TLabel read FDescription;
    property SeverityChoice: TComboBox read FSeverity;
    property ExcludeEdit: TEdit read FExclude;
    property OptionControls: TArray<TControl> read FOptionControls;
    property InvalidLabel: TLabel read FInvalid;
    property BadMemo: TMemo read FBad;
    property GoodMemo: TMemo read FGood;
  end;

/// <summary>Beschriftung der Gruppe AGroup (Kennung des Katalogs) in der Sprache der Oberfläche.</summary>
function AtlasRuleGroupCaption(const AGroup: string): string;

implementation

uses
  Atlas.UI.Strings;

const
  Gap = 6;
  ListHeight = 230;
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
    if SameText(TAtlasRuleTable.GroupIds[Index], AGroup) then
      Exit(TAtlasStrings.Text(GroupTexts[Index]));
  Result := AGroup;
end;

{ TAtlasRulesEditor }

constructor TAtlasRulesEditor.Create(AOwner: TComponent);
var
  Column: TListColumn;
  Caption: TLabel;
begin
  inherited Create(AOwner);
  AutoSize := True;
  FNextTop := 0;

  FTopBar := TAtlasRulesBox.Create(Self);
  FTopBar.Height := 26;
  Stack(Self, FTopBar);
  FSearch := TEdit.Create(Self);
  FSearch.Parent := FTopBar;
  FSearch.Align := alClient;
  FSearch.TextHint := TAtlasStrings.Text(TAtlasTextId.RulesSearchHint);
  FSearch.OnChange := SearchChange;
  FGroupChoice := TComboBox.Create(Self);
  FGroupChoice.Parent := FTopBar;
  FGroupChoice.Align := alRight;
  FGroupChoice.AlignWithMargins := True;
  FGroupChoice.Margins.SetBounds(Gap, 0, 0, 0);
  FGroupChoice.Width := 200;
  FGroupChoice.Style := csDropDownList;
  FGroupChoice.OnChange := GroupChoiceChange;

  FMaster := TCheckBox.Create(Self);
  FMaster.Height := 20;
  FMaster.Visible := False;
  FMaster.OnClick := MasterClick;
  Stack(Self, FMaster);

  FTypeLevel := TCheckBox.Create(Self);
  FTypeLevel.Height := 20;
  FTypeLevel.Visible := False;
  FTypeLevel.Caption := TAtlasStrings.Text(TAtlasTextId.RulesTypeLevel);
  FTypeLevel.AlignWithMargins := True;
  FTypeLevel.Margins.SetBounds(18, 0, 0, 0);
  FTypeLevel.OnClick := TypeLevelClick;
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
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.RulesColumnId);
  Column.Width := 190;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.RulesColumnName);
  Column.Width := 220;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.RulesColumnGroup);
  Column.Width := 120;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.RulesColumnSeverity);
  Column.Width := 150;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.RulesColumnExclude);
  Column.Width := 140;
  FList.OnSelectItem := ListSelect;
  FList.OnItemChecked := ListChecked;
  Stack(Self, FList);

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
  Caption := TLabel.Create(Self);
  Caption.Parent := FSeverityRow;
  Caption.Align := alLeft;
  Caption.Layout := tlCenter;
  Caption.Width := 160;
  Caption.AutoSize := False;
  Caption.Caption := TAtlasStrings.Text(TAtlasTextId.RulesSeverity);
  FSeverity := TComboBox.Create(Self);
  FSeverity.Parent := FSeverityRow;
  FSeverity.Align := alLeft;
  FSeverity.Width := 200;
  FSeverity.Style := csDropDownList;
  FSeverity.OnChange := SeverityChange;

  FExcludeLabel := AddLabel(FDetails, TAtlasStrings.Text(TAtlasTextId.RulesExclude));
  FExclude := TEdit.Create(Self);
  FExclude.OnChange := ExcludeChange;
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
  // Auswahl und Memos brauchen ein Fenster: CreateWnd füllt über Refill auch die Details.
  FDirty := True;
end;

function TAtlasRulesEditor.AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
  Stack(AParent, Result);
end;

function TAtlasRulesEditor.AddMemo(AParent: TWinControl): TMemo;
begin
  Result := TMemo.Create(Self);
  Result.ReadOnly := True;
  Result.ScrollBars := ssBoth;
  Result.WordWrap := False;
  Result.Font.Name := 'Consolas';
  Result.Height := 72;
  Stack(AParent, Result);
end;

procedure TAtlasRulesEditor.Stack(AParent: TWinControl; AControl: TControl);
begin
  // Ein Zähler für alle Behälter: Nur die Reihenfolge innerhalb eines Behälters zählt.
  Inc(FNextTop, 1000);
  AControl.Parent := AParent;
  AControl.Align := alTop;
  AControl.AlignWithMargins := True;
  AControl.Top := FNextTop;
end;

procedure TAtlasRulesEditor.CreateWnd;
begin
  inherited CreateWnd;
  // Auswahllisten und Tabelle brauchen ein Fenster.
  FillChoices;
  if FDirty then
    Refill;
end;

procedure TAtlasRulesEditor.SetFixedGroup(const AValue: string);
begin
  FFixedGroup := AValue;
  // Fester Knoten einer Gruppe: keine Suche und keine Gruppenauswahl; die Spalte zeigt die Kategorie.
  FTopBar.Visible := AValue = '';
  if AValue <> '' then
    FList.Columns[2].Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsColumnCategory)
  else
    FList.Columns[2].Caption := TAtlasStrings.Text(TAtlasTextId.RulesColumnGroup);
  FDirty := True;
  if HandleAllocated then
    Refill;
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
    Refill;
end;

procedure TAtlasRulesEditor.ShowLoading;
begin
  FLoaded := False;
  FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.RulesLoading);
  FStatus.Visible := True;
end;

function TAtlasRulesEditor.Group: string;
begin
  Result := FFixedGroup;
  if (Result = '') and (FGroupChoice.ItemIndex > 0) and
    (FGroupChoice.ItemIndex <= Length(TAtlasRuleTable.GroupIds)) then
    Result := TAtlasRuleTable.GroupIds[FGroupChoice.ItemIndex - 1];
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
    if SameText(FRows[Index].Id, AId) then
      Exit(Index);
  Result := -1;
end;

function TAtlasRulesEditor.HasRule(const AId: string): Boolean;
begin
  Result := RowOf(AId) >= 0;
end;

function TAtlasRulesEditor.SelectedRow: Integer;
begin
  Result := -1;
  if (FList.Selected <> nil) and (FList.Selected.Index <= High(FVisible)) then
    Result := FVisible[FList.Selected.Index];
end;

function TAtlasRulesEditor.RowShown(ARow: Integer): Boolean;
var
  Index: Integer;
begin
  for Index in TAtlasRuleTable.Filter(FRows, Group, FSearch.Text) do
    if Index = ARow then
      Exit(True);
  Result := False;
end;

function TAtlasRulesEditor.GroupCaption(const AGroup: string): string;
begin
  Result := AtlasRuleGroupCaption(AGroup);
end;

function TAtlasRulesEditor.SeverityCaption(const ASeverity: string): string;
begin
  if SameText(ASeverity, 'error') then
    Result := TAtlasStrings.Text(TAtlasTextId.RulesSeverityError)
  else if SameText(ASeverity, 'warning') then
    Result := TAtlasStrings.Text(TAtlasTextId.RulesSeverityWarning)
  else if SameText(ASeverity, 'info') or SameText(ASeverity, 'information') then
    Result := TAtlasStrings.Text(TAtlasTextId.RulesSeverityInfo)
  else if SameText(ASeverity, 'hint') then
    Result := TAtlasStrings.Text(TAtlasTextId.RulesSeverityHint)
  else if SameText(ASeverity, 'off') then
    Result := TAtlasStrings.Text(TAtlasTextId.RulesSeverityOff)
  else
    Result := ASeverity;
end;

function TAtlasRulesEditor.SeverityColumn(const ARow: TAtlasRuleRow): string;
begin
  // Eingestellt, sonst „Vorgabe (…)“; ein Wert der anderen Ebene steht dahinter als „(global: …)“.
  if ARow.Severity <> '' then
    Result := SeverityCaption(ARow.Severity)
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.RulesSeverityDefault, [SeverityCaption(ARow.DefaultSeverity)]);
  if ARow.GlobalSeverity <> '' then
    Result := Result + ' ' + TAtlasStrings.Fmt(TAtlasTextId.RulesGlobal, [SeverityCaption(ARow.GlobalSeverity)]);
end;

procedure TAtlasRulesEditor.FillItem(AItem: TListItem; const ARow: TAtlasRuleRow);
var
  Third: string;
begin
  AItem.Caption := ARow.Id;
  AItem.SubItems.Clear;
  AItem.SubItems.Add(ARow.Name);
  if FFixedGroup <> '' then
    Third := ARow.Category
  else
    Third := GroupCaption(ARow.Group);
  AItem.SubItems.Add(Third);
  AItem.SubItems.Add(SeverityColumn(ARow));
  AItem.SubItems.Add(TAtlasRuleTable.ListText(ARow.Exclude));
  AItem.Checked := ARow.Enabled;
end;

procedure TAtlasRulesEditor.FillChoices;
var
  Index: Integer;
  Value: string;
begin
  if FGroupChoice.Items.Count = 0 then
  begin
    FGroupChoice.Items.Add(TAtlasStrings.Text(TAtlasTextId.RulesAllGroups));
    for Index := 0 to High(TAtlasRuleTable.GroupIds) do
      FGroupChoice.Items.Add(GroupCaption(TAtlasRuleTable.GroupIds[Index]));
    FGroupChoice.ItemIndex := 0;
  end;
  if FSeverity.Items.Count = 0 then
    for Value in SeverityValues do
      if Value = '' then
        FSeverity.Items.Add(TAtlasStrings.Fmt(TAtlasTextId.RulesSeverityDefault, ['']))
      else
        FSeverity.Items.Add(SeverityCaption(Value));
end;

procedure TAtlasRulesEditor.Refill;
var
  Index, Selected: Integer;
  Item: TListItem;
begin
  FDirty := False;
  FStatus.Visible := False;
  if not FLoaded then
  begin
    FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.RulesLoading);
    FStatus.Visible := True;
  end
  else if FCatalog = nil then
  begin
    FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.RulesNoCatalog);
    FStatus.Visible := True;
  end;
  if SelectedRow >= 0 then
    FSelectedId := FRows[SelectedRow].Id;
  FVisible := TAtlasRuleTable.Filter(FRows, Group, FSearch.Text);
  if FLoaded and (Length(FVisible) = 0) and (FCatalog <> nil) then
  begin
    FStatus.Caption := TAtlasStrings.Text(TAtlasTextId.RulesEmpty);
    FStatus.Visible := True;
  end;
  Selected := -1;
  FFilling := True;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for Index := 0 to High(FVisible) do
    begin
      Item := FList.Items.Add;
      FillItem(Item, FRows[FVisible[Index]]);
      if SameText(FRows[FVisible[Index]].Id, FSelectedId) then
        Selected := Index;
    end;
  finally
    FList.Items.EndUpdate;
    FFilling := False;
  end;
  if Selected >= 0 then
  begin
    FFilling := True;
    try
      FList.Items[Selected].Selected := True;
      FList.Items[Selected].Focused := True;
    finally
      FFilling := False;
    end;
  end;
  UpdateMaster;
  ShowDetails;
end;

procedure TAtlasRulesEditor.UpdateMaster;
begin
  FMaster.Visible := Group <> '';
  FTypeLevel.Visible := SameText(Group, TAtlasRuleTable.CompilerGroup);
  if Group = '' then
    Exit;
  FMaster.Caption := TAtlasStrings.Fmt(TAtlasTextId.RulesGroupMaster, [GroupCaption(Group)]);
  FFilling := True;
  try
    FMaster.Checked := not GroupOff;
    FTypeLevel.Checked := not SameText(TAtlasRuleTable.GroupOption(FRulesJson, Group, 'typeLevel'), 'off');
  finally
    FFilling := False;
  end;
end;

procedure TAtlasRulesEditor.UpdateEnabled;

  procedure SetTree(AControl: TControl; AEnabled: Boolean);
  var
    Index: Integer;
  begin
    AControl.Enabled := AEnabled;
    if AControl is TWinControl then
      for Index := 0 to TWinControl(AControl).ControlCount - 1 do
        SetTree(TWinControl(AControl).Controls[Index], AEnabled);
  end;

var
  IsOn: Boolean;
begin
  // Hauptschalter aus: Tabelle und alle Felder gesperrt (wie #890); ohne Auswahl nur die Beschreibung.
  IsOn := not GroupOff;
  FTypeLevel.Enabled := IsOn;
  FList.Enabled := IsOn;
  SetTree(FDetails, IsOn and (SelectedRow >= 0));
  FTitle.Enabled := True;
  FDescription.Enabled := True;
end;

procedure TAtlasRulesEditor.ShowDetails;
var
  Index, Value, Choice: Integer;
  Row: TAtlasRuleRow;
  Present: Boolean;
  Overriding: string;
begin
  Index := SelectedRow;
  Present := Index >= 0;
  Row := Default(TAtlasRuleRow);
  FFilling := True;
  try
    if not Present then
    begin
      FTitle.Caption := TAtlasStrings.Text(TAtlasTextId.RulesNoSelection);
      FMark.Visible := False;
      FDescription.Caption := '';
      FExclude.Text := '';
      if FSeverity.Items.Count > 0 then
        FSeverity.ItemIndex := -1;
      BuildOptions(Default(TAtlasRuleRow));
      FBad.Lines.Text := '';
      FGood.Lines.Text := '';
    end
    else
    begin
      Row := FRows[Index];
      FTitle.Caption := Row.Id;
      if Row.Name <> '' then
        FTitle.Caption := Row.Name + '  ·  ' + Row.Id;
      FMark.Visible := Row.Experimental;
      FDescription.Caption := Row.Description;
      // Gegenregel an (#1025): z. B. redundant-begin-end schweigt, solange missing-begin-end an ist.
      Overriding := TAtlasRuleTable.OverridingRule(FRows, Row);
      if Overriding <> '' then
        FDescription.Caption := Trim(Row.Description + sLineBreak + sLineBreak +
          TAtlasStrings.Fmt(TAtlasTextId.RulesOverriddenBy, [Overriding]));
      if FSeverity.Items.Count > 0 then
      begin
        FSeverity.Items[0] := TAtlasStrings.Fmt(TAtlasTextId.RulesSeverityDefault,
          [SeverityCaption(Row.DefaultSeverity)]);
        Choice := 0;
        for Value := 1 to High(SeverityValues) do
          if SameText(SeverityValues[Value], Row.Severity) or
            (SameText(Row.Severity, 'information') and (SeverityValues[Value] = 'info')) then
            Choice := Value;
        FSeverity.ItemIndex := Choice;
      end;
      FExclude.Text := TAtlasRuleTable.ListText(Row.Exclude);
      BuildOptions(Row);
      FBad.Lines.Text := Row.Bad;
      FGood.Lines.Text := Row.Good;
    end;
    FBadLabel.Visible := Present and (Row.Bad <> '');
    FBad.Visible := FBadLabel.Visible;
    FGoodLabel.Visible := Present and (Row.Good <> '');
    FGood.Visible := FGoodLabel.Visible;
    FInvalid.Visible := False;
  finally
    FFilling := False;
  end;
  UpdateEnabled;
end;

procedure TAtlasRulesEditor.BuildOptions(const ARow: TAtlasRuleRow);
var
  Index: Integer;
  Option: TAtlasRuleOption;
  Line: TAtlasRulesBox;
  Caption: TLabel;
  Check: TCheckBox;
  Edit: TEdit;
  Control: TControl;
begin
  for Control in FOptionControls do
    Control.Parent.Free;
  FOptionControls := nil;
  FOptionsTitle.Visible := Length(ARow.Options) > 0;
  for Index := 0 to High(ARow.Options) do
  begin
    Option := ARow.Options[Index];
    Line := TAtlasRulesBox.Create(Self);
    Line.Parent := FOptionsBox;
    Line.Align := alTop;
    Line.AlignWithMargins := True;
    Line.Height := 24;
    Line.Top := Index * 30;
    if SameText(Option.Kind, 'boolean') then
    begin
      Check := TCheckBox.Create(Self);
      Check.Parent := Line;
      Check.Align := alClient;
      Check.Caption := Option.Name;
      Check.Hint := Option.Description;
      Check.ShowHint := Option.Description <> '';
      Check.Checked := SameText(TAtlasRuleTable.OptionText(Option), 'true');
      Check.OnClick := OptionChange;
      Control := Check;
    end
    else
    begin
      Caption := TLabel.Create(Self);
      Caption.Parent := Line;
      Caption.Align := alLeft;
      Caption.AutoSize := False;
      Caption.Width := 160;
      Caption.Layout := tlCenter;
      Caption.ShowAccelChar := False;
      Caption.Caption := Option.Name + ':';
      Caption.Hint := Option.Description;
      Caption.ShowHint := Option.Description <> '';
      Edit := TEdit.Create(Self);
      Edit.Parent := Line;
      Edit.Align := alClient;
      Edit.Text := TAtlasRuleTable.OptionText(Option);
      Edit.NumbersOnly := SameText(Option.Kind, 'integer');
      Edit.Hint := Option.Description;
      Edit.ShowHint := Option.Description <> '';
      Edit.OnChange := OptionChange;
      Control := Edit;
    end;
    Control.Tag := Index;
    FOptionControls := FOptionControls + [Control];
  end;
end;

procedure TAtlasRulesEditor.Apply(const ARulesJson: string);
var
  Index, Visible: Integer;
begin
  // Zeilen aus dem neuen Wert; die Tabelle wird nur nachgeführt, damit Fokus und Eingabe bleiben.
  FRulesJson := ARulesJson;
  FRows := TAtlasRuleTable.Rows(FCatalog, FRulesJson, FOtherRulesJson);
  FFilling := True;
  try
    for Visible := 0 to High(FVisible) do
    begin
      Index := FVisible[Visible];
      if (Index <= High(FRows)) and (Visible < FList.Items.Count) then
        FillItem(FList.Items[Visible], FRows[Index]);
    end;
  finally
    FFilling := False;
  end;
  UpdateMaster;
  UpdateEnabled;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TAtlasRulesEditor.SelectRule(const AId: string): Boolean;
var
  Index, Row: Integer;
begin
  Row := RowOf(AId);
  Result := Row >= 0;
  if not Result then
    Exit;
  FSelectedId := FRows[Row].Id;
  if HandleAllocated then
  begin
    // Suche und Gruppenauswahl, die die Regel verbergen, zurücksetzen.
    if (FFixedGroup = '') and not RowShown(Row) then
    begin
      FFilling := True;
      try
        FSearch.Text := '';
        FGroupChoice.ItemIndex := 0;
      finally
        FFilling := False;
      end;
    end;
    Refill;
    for Index := 0 to High(FVisible) do
      if FVisible[Index] = Row then
      begin
        FList.Items[Index].Selected := True;
        FList.Items[Index].Focused := True;
        FList.Items[Index].MakeVisible(False);
      end;
  end
  else
    FDirty := True;
end;

procedure TAtlasRulesEditor.SetSeverity(const ASeverity: string);
var
  Row: Integer;
begin
  Row := SelectedRow;
  if Row < 0 then
    Exit;
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
    Exit;
  Apply(TAtlasRuleTable.WithSeverity(FRulesJson, FRows[Row].Id, ASeverity));
  if Row = SelectedRow then
    ShowDetails;
end;

procedure TAtlasRulesEditor.SearchChange(Sender: TObject);
begin
  if not FFilling then
    Refill;
end;

procedure TAtlasRulesEditor.GroupChoiceChange(Sender: TObject);
begin
  if not FFilling then
    Refill;
end;

procedure TAtlasRulesEditor.MasterClick(Sender: TObject);
begin
  if FFilling or (Group = '') then
    Exit;
  Apply(TAtlasRuleTable.WithGroup(FRulesJson, Group, FMaster.Checked));
end;

procedure TAtlasRulesEditor.TypeLevelClick(Sender: TObject);
var
  Value: string;
begin
  if FFilling or (Group = '') then
    Exit;
  Value := '';
  if not FTypeLevel.Checked then
    Value := 'off';
  Apply(TAtlasRuleTable.WithGroupOption(FRulesJson, Group, 'typeLevel', Value));
end;

procedure TAtlasRulesEditor.ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FFilling then
    Exit;
  if SelectedRow >= 0 then
    FSelectedId := FRows[SelectedRow].Id;
  ShowDetails;
end;

procedure TAtlasRulesEditor.ListChecked(Sender: TObject; Item: TListItem);
var
  Row: Integer;
  Severity: string;
begin
  if FFilling or (Item = nil) or (Item.Index > High(FVisible)) then
    Exit;
  Row := FVisible[Item.Index];
  if Item.Checked = FRows[Row].Enabled then
    Exit;
  // Aus: "off". An: Vorgabe, wenn sie meldet; sonst Warnung.
  Severity := 'off';
  if Item.Checked then
  begin
    Severity := '';
    if SameText(FRows[Row].DefaultSeverity, 'off') or SameText(FRows[Row].GlobalSeverity, 'off') then
      Severity := 'warning';
  end;
  Apply(TAtlasRuleTable.WithSeverity(FRulesJson, FRows[Row].Id, Severity));
  if Row = SelectedRow then
    ShowDetails;
end;

procedure TAtlasRulesEditor.SeverityChange(Sender: TObject);
begin
  if FFilling or (FSeverity.ItemIndex < 0) or (FSeverity.ItemIndex > High(SeverityValues)) then
    Exit;
  SetSeverity(SeverityValues[FSeverity.ItemIndex]);
end;

procedure TAtlasRulesEditor.ExcludeChange(Sender: TObject);
var
  Row: Integer;
begin
  Row := SelectedRow;
  if FFilling or (Row < 0) then
    Exit;
  Apply(TAtlasRuleTable.WithExclude(FRulesJson, FRows[Row].Id, TAtlasRuleTable.ParseList(FExclude.Text)));
end;

procedure TAtlasRulesEditor.OptionChange(Sender: TObject);
var
  Row, Index: Integer;
  Option: TAtlasRuleOption;
  Text, Json: string;
begin
  Row := SelectedRow;
  if FFilling or (Row < 0) or not (Sender is TControl) then
    Exit;
  Index := TControl(Sender).Tag;
  if (Index < 0) or (Index > High(FRows[Row].Options)) then
    Exit;
  Option := FRows[Row].Options[Index];
  if Sender is TCheckBox then
  begin
    Text := 'false';
    if TCheckBox(Sender).Checked then
      Text := 'true';
  end
  else
    Text := TEdit(Sender).Text;
  // Ungültige Eingabe bleibt im Feld stehen, wird aber nicht übernommen.
  if not TAtlasRuleTable.OptionJson(Option.Kind, Text, Json) then
  begin
    FInvalid.Caption := TAtlasStrings.Fmt(TAtlasTextId.RulesOptionInvalid, [Option.Name]);
    FInvalid.Visible := True;
    Exit;
  end;
  FInvalid.Visible := False;
  // Gleich der Vorgabe: Option entfernen.
  if Json = Option.DefaultJson then
    Json := '';
  Apply(TAtlasRuleTable.WithOption(FRulesJson, FRows[Row].Id, Option.Name, Json));
end;

end.
