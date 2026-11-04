unit Atlas.UI.Settings.ProjectDialog;

// Dialog der Server-Einstellungen (#227) für eine Ebene: atlas.json des
// Projekts oder die globale Datei %APPDATA%\Atlas\settings.json. Seiten und
// Bedienelemente entstehen aus dem JSON-Schema (TAtlasSettingsSchema), die
// Werte aus TAtlasSettingsModel. Jede Einstellung hat genau einen Ort (x-scope
// im Schema): Der Aufrufer reicht nur die Felder dieser Datei herein, im
// Projekt ohne globale Ebene. Je Einstellung steht, ob sie gesetzt ist oder der
// Standard gilt; „Auf Standard zurücksetzen“ entfernt den Schlüssel.
// Eigene Bedienelemente, wo Text, Zahl, Auswahl und Liste nicht reichen:
//   - Auswahl aus Werten, die die IDE-Schicht liefert (OnChoices): installierte
//     Delphi-Versionen, Konfigurationen und Plattformen der .dproj, Profile.
//   - Textfelder mit Beispielen im Schema als Auswahl mit freier Eingabe.
//   - Dateiauswahl für x-control „Datei wählen“ (logFile, traceFile).
//   - "rules" mit dem Regel-Editor (TAtlasRulesEditor, #909) aus dem
//     Regelkatalog (Catalog): auf der Seite alle Regeln mit Suche, darunter im
//     Seitenbaum ein Knoten je Gruppe mit Hauptschalter. Schweregrad, Ausnahmen
//     und Optionen; Werte der globalen Datei als „(global: …)“. Geändert wird je
//     Regel nur ihr Wert in der Datei. Die Prüfregeln stehen nur hier (Projekt
//     und „Weitere globale Einstellungen“), nicht in Tools › Optionen.
//   - Übrige Werte (profiles, overrides, dfmPropertyRules, profile als Objekt)
//     als JSON-Text.
// Vor dem Schließen mit OK prüft OnValidate den neuen Text (beim Server, sonst
// nur die Syntax). Geschrieben wird nicht hier: Der Aufrufer schreibt
// Model.ResultText.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Dialogs,
  Vcl.Graphics,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Settings.Choices,
  Atlas.Core.Settings.RuleTable,
  Atlas.Core.Settings.Validation,
  Atlas.UI.Settings.Rules;

type
  /// <summary>Auswahl für ein Feld (Pfad); leer = keine eigene Auswahl.</summary>
  TAtlasSettingChoicesFunc = reference to function(const APath: string): TArray<TAtlasSettingChoice>;
  /// <summary>Prüft AText; AChecked = False, wenn nur die Syntax geprüft werden konnte.</summary>
  TAtlasSettingsCheckFunc = reference to function(const AText: string; out AChecked: Boolean)
    : TArray<TAtlasSettingIssue>;

  TAtlasProjectSettingsDialog = class(TForm)
  private
    FModel: TAtlasSettingsModel;
    // Getippter Text der Zahlen- und JSON-Felder; ungültige Eingaben verhindern OK.
    FRaw: TArray<string>;
    FRawValid: TArray<Boolean>;
    FStates: TArray<TLabel>;
    FResets: TArray<TButton>;
    FFileEdits: TArray<TEdit>;
    FTextChoices: TArray<TArray<TAtlasSettingChoice>>;
    FPages: TArray<string>;
    FPageTree: TTreeView;
    /// <summary>Knoten je Seite (Index wie FPages) und je Regelgruppe (Index wie FGroups).</summary>
    FPageNodes: TArray<TTreeNode>;
    FGroups: TArray<string>;
    FGroupNodes: TArray<TTreeNode>;
    /// <summary>Gezeigt: Seite FCurrentPage oder Gruppe FCurrentGroup (Index), das andere -1.</summary>
    FCurrentPage: Integer;
    FCurrentGroup: Integer;
    FSelecting: Boolean;
    FBox: TScrollBox;
    FHint: TLabel;
    FOnOpenFile: TProc;
    FOnChoices: TAtlasSettingChoicesFunc;
    FOnValidate: TAtlasSettingsCheckFunc;
    FCatalog: TJSONValue;
    FBuildHint: string;
    FProjectHint: string;
    FServerChecks: Boolean;
    // Regel-Editor: Feld "rules" und sein Wert mit den Änderungen.
    FRuleIndex: Integer;
    FRulesJson: string;
    /// <summary>Im Projektmodus: "rules" der globalen Einstellungen, für die Anzeige „(global: …)“.</summary>
    FGlobalRulesJson: string;
    FRuleEditor: TAtlasRulesEditor;
    /// <summary>Höhe des Regel-Editors, mit der die Felder darunter stehen (#1296).</summary>
    FRuleHeight: Integer;
    function ChoicesOf(AIndex: Integer): TArray<TAtlasSettingChoice>;
    function ResetCaption: string;
    function AddLabel(const AText: string; ATop: Integer): TLabel;
    procedure ClearBox;
    procedure ShowPage(APage: Integer);
    procedure ShowGroup(AGroup: Integer);
    procedure ShowCurrent;
    procedure SelectNode(ANode: TTreeNode);
    procedure UpdateState(AIndex: Integer);
    procedure UpdateHint;
    function AddRuleTable(ATop: Integer; const AGroup: string): Integer;
    procedure RuleEditorChange(Sender: TObject);
    procedure RuleEditorResize(Sender: TObject);
    function GetRuleList: TListView;
    procedure PageTreeChange(Sender: TObject; Node: TTreeNode);
    procedure CheckClick(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure ComboChange(Sender: TObject);
    procedure TextComboChange(Sender: TObject);
    procedure MemoChange(Sender: TObject);
    procedure JsonChange(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure SetBuildHint(const AValue: string);
    procedure SetProjectHint(const AValue: string);
    procedure SetServerChecks(AValue: Boolean);
  protected
    /// <summary>Höhe des Hinweises zur neuen Breite: Ein umbrechendes Label rechnet sie nur beim Setzen des
    /// Textes, vor dem Anzeigen war es noch schmal und hinterließ einen hohen leeren Streifen.</summary>
    procedure Resize; override;
  public
    /// <summary>AModel bleibt beim Aufrufer. AFileName: bearbeitete Datei für die Anzeige.</summary>
    constructor CreateDialog(AOwner: TComponent; AModel: TAtlasSettingsModel; const AFileName: string);
    /// <summary>Seite mit diesem Namen zeigen; False ohne sie.</summary>
    function SelectPage(const APage: string): Boolean;
    /// <summary>Text des Zustands eines Felds auf der gezeigten Seite; '' wenn nicht gezeigt.</summary>
    function StateText(const APath: string): string;
    /// <summary>Schweregrad einer Regel wie über die Tabelle setzen ('' = Vorgabe); False ohne die Regel.</summary>
    function SetRuleSeverity(const AId, ASeverity: string): Boolean;
    /// <summary>Knoten der Gruppe der Regel zeigen und die Regel markieren („Regel einstellen…“, #909); False
    /// ohne Katalog, ohne "rules" oder ohne die Regel.</summary>
    function SelectRule(const AId: string): Boolean;
    /// <summary>Knoten der Regelgruppe AGroup; nil ohne.</summary>
    function GroupNode(const AGroup: string): TTreeNode;
    /// <summary>Prüfen wie bei OK; True, wenn gespeichert werden darf.</summary>
    function Validate: Boolean;
    property Model: TAtlasSettingsModel read FModel;
    property Pages: TArray<string> read FPages;
    property PageTree: TTreeView read FPageTree;
    property RuleList: TListView read GetRuleList;
    /// <summary>Regel-Editor auf der gezeigten Seite; nil ohne "rules".</summary>
    property RuleEditor: TAtlasRulesEditor read FRuleEditor;
    property HintLabel: TLabel read FHint;
    property OnOpenFile: TProc read FOnOpenFile write FOnOpenFile;
    /// <summary>Vor dem ersten Anzeigen einer Seite setzen.</summary>
    property OnChoices: TAtlasSettingChoicesFunc read FOnChoices write FOnChoices;
    property OnValidate: TAtlasSettingsCheckFunc read FOnValidate write FOnValidate;
    /// <summary>Antwort von atlas.server.settingsCatalog für die Regeltabelle; bleibt beim Aufrufer.</summary>
    property Catalog: TJSONValue read FCatalog write FCatalog;
    /// <summary>Hinweis auf eine Auswahl von Konfiguration und Plattform in der IDE (selectBuild); '' ohne.</summary>
    property BuildHint: string read FBuildHint write SetBuildHint;
    /// <summary>Aktives Projekt für den Hinweis beim Feld "project"; '' ohne.</summary>
    property ProjectHint: string read FProjectHint write SetProjectHint;
    /// <summary>Der Server prüft beim Speichern; sonst steht oben ein Hinweis.</summary>
    property ServerChecks: Boolean read FServerChecks write SetServerChecks;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Settings.PageNames,
  Atlas.UI.Strings;

const
  Gap = 8;
  ControlWidth = 320;
  RulesPath = 'rules';
  /// <summary>Data der Gruppenknoten ab hier; darunter der Index der Seite.</summary>
  GroupBase = 10000;

/// <summary>Gültiger JSON-Wert (auch Zahl oder String)?</summary>
function IsJsonValue(const AText: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(TAtlasJsonText.StripComments(AText));
  Result := Value <> nil;
  Value.Free;
end;

constructor TAtlasProjectSettingsDialog.CreateDialog(AOwner: TComponent; AModel: TAtlasSettingsModel;
  const AFileName: string);
var
  Index: Integer;
  Bottom: TPanel;
  Button: TButton;
  FileLabel: TLabel;
  Group: string;
  Node: TTreeNode;
begin
  inherited CreateNew(AOwner);
  FCurrentPage := -1;
  FCurrentGroup := -1;
  FModel := AModel;
  if FModel.Global then
  begin
    Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsGlobalTitle);
  end
  else
  begin
    Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsTitle);
  end;
  BorderStyle := bsSizeable;
  Position := poMainFormCenter;
  Width := 960;
  Height := 660;
  FServerChecks := True;
  SetLength(FRaw, FModel.Count);
  SetLength(FRawValid, FModel.Count);
  SetLength(FStates, FModel.Count);
  SetLength(FResets, FModel.Count);
  SetLength(FFileEdits, FModel.Count);
  SetLength(FTextChoices, FModel.Count);
  for Index := 0 to FModel.Count - 1 do
  begin
    if FModel.Typed(Index) then
    begin
      FRaw[Index] := TAtlasSettingsSchema.Display(FModel.Current(Index));
    end
    else
    begin
      FRaw[Index] := FModel.Current(Index);
    end;
    FRawValid[Index] := True;
  end;
  FRuleIndex := FModel.IndexOf(RulesPath);
  if FRuleIndex >= 0 then
  begin
    FRulesJson := FModel.Current(FRuleIndex);
    if not FModel.Global then
    begin
      FGlobalRulesJson := FModel.Inherited_(FRuleIndex);
    end;
  end;

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 44;
  Bottom.BevelOuter := bvNone;
  FileLabel := TLabel.Create(Self);
  FileLabel.Parent := Bottom;
  FileLabel.Left := 170;
  FileLabel.Top := 14;
  FileLabel.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProjectSettingsFile, [AFileName]);
  Button := TButton.Create(Self);
  Button.Parent := Bottom;
  Button.SetBounds(Gap, 8, 150, 28);
  if FModel.Global then
  begin
    Button.Caption := TAtlasStrings.Text(TAtlasTextId.GlobalSettingsOpenFile);
  end
  else
  begin
    Button.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsOpenFile);
  end;
  Button.OnClick := OpenClick;
  Button := TButton.Create(Self);
  Button.Parent := Bottom;
  Button.SetBounds(Bottom.Width - 2 * (90 + Gap), 8, 90, 28);
  Button.Anchors := [akTop, akRight];
  Button.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsOk);
  Button.Default := True;
  Button.OnClick := OkClick;
  Button := TButton.Create(Self);
  Button.Parent := Bottom;
  Button.SetBounds(Bottom.Width - (90 + Gap), 8, 90, 28);
  Button.Anchors := [akTop, akRight];
  Button.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel);
  Button.Cancel := True;
  Button.ModalResult := mrCancel;

  // Hinweise oben: Auswahl in der IDE (selectBuild) und Prüfung ohne Server.
  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.Align := alTop;
  FHint.AlignWithMargins := True;
  FHint.WordWrap := True;
  FHint.Font.Color := clGrayText;
  FHint.Visible := False;

  FPageTree := TTreeView.Create(Self);
  FPageTree.Parent := Self;
  FPageTree.Align := alLeft;
  FPageTree.Width := 190;
  FPageTree.ReadOnly := True;
  FPageTree.HideSelection := False;
  FPageTree.ShowLines := False;
  FPageTree.RowSelect := True;
  FPageTree.OnChange := PageTreeChange;
  FPages := TAtlasSettingsSchema.Pages(FModel.AllFields);
  SetLength(FPageNodes, Length(FPages));
  FPageTree.Items.BeginUpdate;
  try
    for Index := 0 to High(FPages) do
    begin
      FPageNodes[Index] := FPageTree.Items.Add(nil,
      TAtlasSettingsPageNames.Caption(FPages[Index], TAtlasStrings.Language = TAtlasLanguage.English));
      FPageNodes[Index].Data := Pointer(NativeInt(Index));
    end;
    // Prüfregeln (#909): unter der Seite mit "rules" je Gruppe ein Knoten mit Hauptschalter und Tabelle.
    if FRuleIndex >= 0 then
    begin
      for Index := 0 to High(FPages) do
      begin
        if SameText(FPages[Index], FModel.Fields[FRuleIndex].Page) then
        begin
          for Group in TAtlasRuleTable.GroupIds do
          begin
            Node := FPageTree.Items.AddChild(FPageNodes[Index], AtlasRuleGroupCaption(Group));
            Node.Data := Pointer(NativeInt(GroupBase + Length(FGroups)));
            FGroups := FGroups + [Group];
            FGroupNodes := FGroupNodes + [Node];
          end;
          FPageNodes[Index].Expand(False);
        end;
      end;
    end;
  finally
    FPageTree.Items.EndUpdate;
  end;

  FBox := TScrollBox.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.BorderStyle := bsNone;
  FBox.VertScrollBar.Tracking := True;

  if Length(FPageNodes) > 0 then
  begin
    SelectNode(FPageNodes[0]);
  end;
end;

function TAtlasProjectSettingsDialog.SelectPage(const APage: string): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to High(FPages) do
  begin
    if SameText(FPages[Index], APage) then
    begin
      SelectNode(FPageNodes[Index]);
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasProjectSettingsDialog.SelectNode(ANode: TTreeNode);
begin
  // Auch ein schon gewählter Knoten baut neu auf; OnChange käme dann nicht.
  FSelecting := True;
  try
    FPageTree.Selected := ANode;
  finally
    FSelecting := False;
  end;
  PageTreeChange(FPageTree, ANode);
end;

procedure TAtlasProjectSettingsDialog.PageTreeChange(Sender: TObject; Node: TTreeNode);
var
  Tag: NativeInt;
begin
  if FSelecting or (Node = nil) or (FBox = nil) then
  begin
    Exit;
  end;
  Tag := NativeInt(Node.Data);
  if Tag >= GroupBase then
  begin
    ShowGroup(Tag - GroupBase);
  end
  else
  begin
    ShowPage(Tag);
  end;
end;

procedure TAtlasProjectSettingsDialog.ShowCurrent;
begin
  if FCurrentGroup >= 0 then
  begin
    ShowGroup(FCurrentGroup);
  end
  else if FCurrentPage >= 0 then
  begin
    ShowPage(FCurrentPage);
  end;
end;

function TAtlasProjectSettingsDialog.GroupNode(const AGroup: string): TTreeNode;
var
  Index: Integer;
begin
  for Index := 0 to High(FGroups) do
  begin
    if SameText(FGroups[Index], AGroup) then
    begin
      Exit(FGroupNodes[Index]);
    end;
  end;
  Result := nil;
end;

function TAtlasProjectSettingsDialog.SelectRule(const AId: string): Boolean;
var
  Row: TAtlasRuleRow;
  Target: TTreeNode;
  Index: Integer;
begin
  Result := False;
  if (FRuleIndex < 0) or (FCatalog = nil) then
  begin
    Exit;
  end;
  Target := nil;
  for Row in TAtlasRuleTable.Rows(FCatalog, FRulesJson, FGlobalRulesJson) do
  begin
    if SameText(Row.Id, AId) then
    begin
      // Knoten der Gruppe der Regel, sonst die Seite mit allen Regeln.
      Target := GroupNode(Row.Group);
      if Target = nil then
      begin
        for Index := 0 to High(FPages) do
        begin
          if SameText(FPages[Index], FModel.Fields[FRuleIndex].Page) then
          begin
            Target := FPageNodes[Index];
          end;
        end;
      end;
    end;
  end;
  if Target = nil then
  begin
    Exit;
  end;
  SelectNode(Target);
  Result := (FRuleEditor <> nil) and FRuleEditor.SelectRule(AId);
end;

function TAtlasProjectSettingsDialog.StateText(const APath: string): string;
var
  Index: Integer;
begin
  Result := '';
  Index := FModel.IndexOf(APath);
  if (Index >= 0) and (FStates[Index] <> nil) then
  begin
    Result := FStates[Index].Caption;
  end;
end;

function TAtlasProjectSettingsDialog.ResetCaption: string;
begin
  // Eine Ebene je Datei: Ohne den Schlüssel gilt immer der Standard.
  Result := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsResetDefault);
end;

function TAtlasProjectSettingsDialog.ChoicesOf(AIndex: Integer): TArray<TAtlasSettingChoice>;
begin
  Result := nil;
  if Assigned(FOnChoices) then
  begin
    Result := FOnChoices(FModel.Fields[AIndex].Path);
  end;
  // Beispiele aus dem Schema als Vorschläge (encoding, config …), wenn die IDE nichts liefert.
  if (Length(Result) = 0) and (FModel.Fields[AIndex].Kind = TAtlasSettingKind.Text) then
  begin
    Result := TAtlasSettingChoices.FromTexts(FModel.Fields[AIndex].Examples);
  end;
end;

procedure TAtlasProjectSettingsDialog.UpdateHint;
var
  Lines: TArray<string>;
begin
  Lines := nil;
  if FBuildHint <> '' then
  begin
    Lines := Lines + [FBuildHint];
  end;
  if not FServerChecks then
  begin
    Lines := Lines + [TAtlasStrings.Text(TAtlasTextId.ProjectSettingsSyntaxOnly)];
  end;
  FHint.Caption := string.Join(sLineBreak, Lines);
  FHint.Visible := Length(Lines) > 0;
end;

procedure TAtlasProjectSettingsDialog.Resize;
begin
  inherited Resize;
  if (FHint <> nil) and FHint.Visible then
  begin
    FHint.AutoSize := False;
    FHint.AutoSize := True;
  end;
end;

procedure TAtlasProjectSettingsDialog.SetBuildHint(const AValue: string);
begin
  FBuildHint := AValue;
  UpdateHint;
end;

procedure TAtlasProjectSettingsDialog.SetProjectHint(const AValue: string);
begin
  FProjectHint := AValue;
  ShowCurrent;
end;

procedure TAtlasProjectSettingsDialog.SetServerChecks(AValue: Boolean);
begin
  FServerChecks := AValue;
  UpdateHint;
end;

procedure TAtlasProjectSettingsDialog.UpdateState(AIndex: Integer);
var
  mText: string;
begin
  if FStates[AIndex] = nil then
  begin
    Exit;
  end;
  case FModel.Origin(AIndex) of
    TAtlasSettingOrigin.Project:
      mText := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsFromProject);
    TAtlasSettingOrigin.Global:
      if FModel.Global then
      begin
        mText := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsFromGlobal);
      end
      else
      begin
        mText := TAtlasStrings.Fmt(TAtlasTextId.ProjectSettingsInherited,
          [Copy(TAtlasSettingsSchema.Display(FModel.Inherited_(AIndex)), 1, 60)]);
      end;
  else
    if FModel.Fields[AIndex].DefaultJson <> '' then
    begin
      mText := TAtlasStrings.Fmt(TAtlasTextId.ProjectSettingsDefault,
        [Copy(TAtlasSettingsSchema.Display(FModel.Fields[AIndex].DefaultJson), 1, 60)]);
    end
    else
    begin
      mText := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsDefaultNone);
    end;
  end;
  FStates[AIndex].Caption := mText;
  if FResets[AIndex] <> nil then
  begin
    FResets[AIndex].Enabled := FModel.Current(AIndex) <> '';
  end;
end;

function TAtlasProjectSettingsDialog.AddLabel(const AText: string; ATop: Integer): TLabel;
begin
  Result := TLabel.Create(FBox);
  Result.Parent := FBox;
  Result.WordWrap := True;
  Result.AutoSize := True;
  Result.SetBounds(Gap * 2, ATop, FBox.ClientWidth - Gap * 5, 16);
  Result.Caption := AText;
end;

procedure TAtlasProjectSettingsDialog.ShowPage(APage: Integer);
var
  Index, Y, Choice, Width_: Integer;
  mName, Note: TLabel;
  Check: TCheckBox;
  Edit: TEdit;
  Combo: TComboBox;
  Memo: TMemo;
  Reset, Browse: TButton;
  Value: TJSONValue;
  Item: TJSONValue;
  Control: TControl;
  Field: TAtlasSettingField;
  Choices: TArray<TAtlasSettingChoice>;
begin
  ClearBox;
  FCurrentPage := APage;
  FCurrentGroup := -1;
  Y := Gap;
  for Index := 0 to FModel.Count - 1 do
  begin
    Field := FModel.Fields[Index];
    if not SameText(Field.Page, FPages[APage]) then
    begin
      Continue;
    end;
    mName := TLabel.Create(FBox);
    mName.Parent := FBox;
    mName.SetBounds(Gap * 2, Y, 400, 16);
    mName.Font.Style := [fsBold];
    mName.Caption := Field.Path;
    if Field.Experimental then
    begin
      mName.Caption := mName.Caption + '  [' + TAtlasStrings.Text(TAtlasTextId.SettingsExperimentalTag) + ']';
    end;
    Inc(Y, 20);
    if Field.DescriptionFor(TAtlasStrings.Language = TAtlasLanguage.English) <> '' then
    begin
      Inc(Y, AddLabel(Field.DescriptionFor(TAtlasStrings.Language = TAtlasLanguage.English), Y).Height + 4);
    end;
    if Field.Restart then
    begin
      Note := AddLabel(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsRestart), Y);
      Note.Font.Color := clGrayText;
      Inc(Y, Note.Height + 4);
    end;
    if (Field.Path = 'project') and (FProjectHint <> '') then
    begin
      Note := AddLabel(TAtlasStrings.Fmt(TAtlasTextId.ProjectSettingsActiveProject, [FProjectHint]), Y);
      Note.Font.Color := clGrayText;
      Inc(Y, Note.Height + 4);
    end;
    Control := nil;
    Width_ := ControlWidth;
    if Index = FRuleIndex then
    begin
      // Regeltabelle aus dem Katalog; der Zustand gilt für "rules" als Ganzes.
      Y := AddRuleTable(Y, '');
    end
    else if not FModel.Typed(Index) then
    begin
      // JSON-Text für alles, was mehr als ein einfacher Wert ist.
      Note := AddLabel(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsJsonHint), Y);
      Note.Font.Color := clGrayText;
      Inc(Y, Note.Height + 4);
      Memo := TMemo.Create(FBox);
      Memo.Parent := FBox;
      Memo.Height := 120;
      Memo.ScrollBars := ssBoth;
      Memo.WordWrap := False;
      Memo.Font.Name := 'Consolas';
      Memo.Text := FRaw[Index];
      Memo.OnChange := JsonChange;
      Control := Memo;
      Width_ := Max(ControlWidth, FBox.ClientWidth - Gap * 5 - 300);
    end
    else
      case Field.Kind of
        TAtlasSettingKind.Boolean_:
          begin
            Check := TCheckBox.Create(FBox);
            Check.Parent := FBox;
            Check.Caption := Field.Path;
            Check.Checked := FModel.Effective(Index) = 'true';
            Check.OnClick := CheckClick;
            Control := Check;
          end;
        TAtlasSettingKind.Integer_:
          begin
            Edit := TEdit.Create(FBox);
            Edit.Parent := FBox;
            if FModel.Current(Index) <> '' then
            begin
              Edit.Text := FRaw[Index];
            end
            else
            begin
              Edit.TextHint := TAtlasSettingsSchema.Display(FModel.Fallback(Index));
            end;
            Edit.OnChange := EditChange;
            Control := Edit;
          end;
        TAtlasSettingKind.Text:
          begin
            Choices := ChoicesOf(Index);
            if Length(Choices) > 0 then
            begin
              // Auswahl mit freier Eingabe: Anzeige der Auswahl, gespeichert wird ihr JSON-Text.
              FTextChoices[Index] := Choices;
              Combo := TComboBox.Create(FBox);
              Combo.Parent := FBox;
              Combo.Style := csDropDown;
              for Choice := 0 to High(Choices) do
              begin
                Combo.Items.Add(Choices[Choice].Caption);
              end;
              Choice := TAtlasSettingChoices.IndexOf(Choices, FModel.Current(Index));
              if Choice >= 0 then
              begin
                Combo.ItemIndex := Choice;
              end
              else if FModel.Current(Index) <> '' then
              begin
                Combo.Text := FRaw[Index];
              end
              else
              begin
                Combo.TextHint := TAtlasSettingsSchema.Display(FModel.Fallback(Index));
              end;
              Combo.OnChange := TextComboChange;
              Control := Combo;
            end
            else
            begin
              Edit := TEdit.Create(FBox);
              Edit.Parent := FBox;
              if FModel.Current(Index) <> '' then
              begin
                Edit.Text := FRaw[Index];
              end
              else
              begin
                Edit.TextHint := TAtlasSettingsSchema.Display(FModel.Fallback(Index));
              end;
              Edit.OnChange := EditChange;
              Control := Edit;
              if Field.PicksFile then
              begin
                FFileEdits[Index] := Edit;
                Width_ := ControlWidth - 34;
                Browse := TButton.Create(FBox);
                Browse.Parent := FBox;
                Browse.SetBounds(Gap * 2 + ControlWidth - 30, Y, 30, 24);
                Browse.Caption := '…';
                Browse.Tag := Index;
                Browse.OnClick := BrowseClick;
              end;
            end;
          end;
        TAtlasSettingKind.Choice:
          begin
            Combo := TComboBox.Create(FBox);
            Combo.Parent := FBox;
            Combo.Style := csDropDownList;
            for Choice := 0 to High(Field.Choices) do
            begin
              Combo.Items.Add(TAtlasSettingsSchema.Display(Field.Choices[Choice]));
              if Field.Choices[Choice] = FModel.Effective(Index) then
              begin
                Combo.ItemIndex := Choice;
              end;
            end;
            Combo.OnChange := ComboChange;
            Control := Combo;
          end;
        TAtlasSettingKind.List:
          begin
            Memo := TMemo.Create(FBox);
            Memo.Parent := FBox;
            Memo.Height := 72;
            Memo.ScrollBars := ssVertical;
            Value := TJSONObject.ParseJSONValue(FModel.Effective(Index));
            try
              if Value is TJSONArray then
              begin
                for Item in TJSONArray(Value) do
                begin
                  if Item is TJSONString then
                  begin
                    Memo.Lines.Add(TJSONString(Item).Value);
                  end;
                end;
              end;
            finally
              Value.Free;
            end;
            Memo.OnChange := MemoChange;
            Control := Memo;
          end;
      else
        // Übrige Werte bewusst ohne Wirkung.
      end;
    if Control <> nil then
    begin
      Control.Tag := Index;
      Control.SetBounds(Gap * 2, Y, Width_, Control.Height);
    end;
    FStates[Index] := TLabel.Create(FBox);
    FStates[Index].Parent := FBox;
    if Control <> nil then
    begin
      FStates[Index].SetBounds(Gap * 2 + Width_ + Gap, Y + 4, 150, 16);
    end
    else
    begin
      FStates[Index].SetBounds(Gap * 2, Y, 150, 16);
    end;
    FStates[Index].Font.Color := clGrayText;
    Reset := TButton.Create(FBox);
    Reset.Parent := FBox;
    Reset.SetBounds(FStates[Index].Left + 150 + Gap, FStates[Index].Top - 4, 140, 24);
    Reset.Caption := ResetCaption;
    Reset.Tag := Index;
    Reset.OnClick := ResetClick;
    FResets[Index] := Reset;
    UpdateState(Index);
    if Control <> nil then
    begin
      Inc(Y, Control.Height + Gap * 2);
    end
    else
    begin
      Inc(Y, 24 + Gap * 2);
    end;
  end;
end;

procedure TAtlasProjectSettingsDialog.ClearBox;
var
  Index: Integer;
begin
  FBox.VertScrollBar.Position := 0;
  while FBox.ControlCount > 0 do
  begin
    FBox.Controls[0].Free;
  end;
  FRuleEditor := nil;
  for Index := 0 to High(FStates) do
  begin
    FStates[Index] := nil;
    FResets[Index] := nil;
    FFileEdits[Index] := nil;
  end;
end;

procedure TAtlasProjectSettingsDialog.ShowGroup(AGroup: Integer);
var
  Title: TLabel;
begin
  ClearBox;
  FCurrentPage := -1;
  FCurrentGroup := AGroup;
  Title := TLabel.Create(FBox);
  Title.Parent := FBox;
  Title.SetBounds(Gap * 2, Gap, 400, 16);
  Title.Font.Style := [fsBold];
  Title.Caption := AtlasRuleGroupCaption(FGroups[AGroup]);
  AddRuleTable(Gap + 24, FGroups[AGroup]);
end;

function TAtlasProjectSettingsDialog.AddRuleTable(ATop: Integer; const AGroup: string): Integer;
begin
  // Regel-Editor (#909); er braucht für Tabelle und Auswahllisten ein Fenster. Mit AGroup nur diese Gruppe mit
  // ihrem Hauptschalter.
  FRuleEditor := TAtlasRulesEditor.Create(FBox);
  FRuleEditor.Parent := FBox;
  FRuleEditor.SetBounds(Gap * 2, ATop, FBox.ClientWidth - Gap * 5, 400);
  FRuleEditor.Anchors := [akLeft, akTop, akRight];
  FRuleEditor.FixedGroup := AGroup;
  FRuleEditor.SetRules(FCatalog, FRulesJson, FGlobalRulesJson);
  FRuleEditor.OnChange := RuleEditorChange;
  FRuleEditor.HandleNeeded;
  FRuleHeight := FRuleEditor.Height;
  FRuleEditor.OnResize := RuleEditorResize;
  Result := ATop + FRuleHeight + Gap;
end;

procedure TAtlasProjectSettingsDialog.RuleEditorResize(Sender: TObject);
var
  Index, Shift, Bottom: Integer;
  Control: TControl;
begin
  // Die Seite steht mit festen Positionen; der Editor wächst mit der markierten Regel (Optionen, Beispiele) und
  // überdeckte sonst die Felder darunter (#1296). Alles unter seiner alten Unterkante rückt um die Differenz.
  if (FRuleEditor = nil) or (csDestroying in FRuleEditor.ComponentState) then
  begin
    Exit;
  end;
  Shift := FRuleEditor.Height - FRuleHeight;
  if Shift = 0 then
  begin
    Exit;
  end;
  Bottom := FRuleEditor.Top + FRuleHeight;
  FRuleHeight := FRuleEditor.Height;
  FBox.DisableAlign;
  try
    for Index := 0 to FBox.ControlCount - 1 do
    begin
      Control := FBox.Controls[Index];
      if (Control <> FRuleEditor) and (Control.Top >= Bottom) then
      begin
        Control.Top := Control.Top + Shift;
      end;
    end;
  finally
    FBox.EnableAlign;
  end;
end;

function TAtlasProjectSettingsDialog.GetRuleList: TListView;
begin
  Result := nil;
  if FRuleEditor <> nil then
  begin
    Result := FRuleEditor.List;
  end;
end;

procedure TAtlasProjectSettingsDialog.RuleEditorChange(Sender: TObject);
var
  Change: TPair<string, string>;
begin
  // Nur die geänderten Regeln in die Datei: Kommentare und andere Regeln bleiben.
  for Change in TAtlasRuleTable.Changes(FRulesJson, FRuleEditor.RulesJson) do
  begin
    FModel.SetPath(Change.Key, Change.Value);
  end;
  FRulesJson := FRuleEditor.RulesJson;
  UpdateState(FRuleIndex);
end;

function TAtlasProjectSettingsDialog.SetRuleSeverity(const AId, ASeverity: string): Boolean;
var
  Change: TPair<string, string>;
  Rows: TArray<TAtlasRuleRow>;
  Row: TAtlasRuleRow;
  Updated: string;
begin
  if FRuleEditor <> nil then
  begin
    Exit(FRuleEditor.SetRuleSeverity(AId, ASeverity));
  end;
  Rows := TAtlasRuleTable.Rows(FCatalog, FRulesJson, FGlobalRulesJson);
  Result := False;
  for Row in Rows do
  begin
    if SameText(Row.Id, AId) then
    begin
      Result := True;
    end;
  end;
  if not Result then
  begin
    Exit;
  end;
  Updated := TAtlasRuleTable.WithSeverity(FRulesJson, AId, ASeverity);
  for Change in TAtlasRuleTable.Changes(FRulesJson, Updated) do
  begin
    FModel.SetPath(Change.Key, Change.Value);
  end;
  FRulesJson := Updated;
end;

procedure TAtlasProjectSettingsDialog.CheckClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := TCheckBox(Sender).Tag;
  if TCheckBox(Sender).Checked then
  begin
    FModel.SetValue(Index, 'true');
  end
  else
  begin
    FModel.SetValue(Index, 'false');
  end;
  UpdateState(Index);
end;

procedure TAtlasProjectSettingsDialog.EditChange(Sender: TObject);
var
  Index, Number: Integer;
  mText: string;
begin
  Index := TEdit(Sender).Tag;
  mText := Trim(TEdit(Sender).Text);
  FRaw[Index] := mText;
  FRawValid[Index] := True;
  if mText = '' then
  begin
    FModel.SetValue(Index, '');
  end
  else if FModel.Fields[Index].Kind = TAtlasSettingKind.Text then
  begin
    FModel.SetValue(Index, TAtlasJsonText.Quote(mText));
  end
  else if TryStrToInt(mText, Number) then
  begin
    FModel.SetValue(Index, IntToStr(Number));
  end
  else
  begin
    FRawValid[Index] := False;
  end;
  UpdateState(Index);
end;

procedure TAtlasProjectSettingsDialog.ComboChange(Sender: TObject);
var
  Index: Integer;
begin
  Index := TComboBox(Sender).Tag;
  if TComboBox(Sender).ItemIndex >= 0 then
  begin
    FModel.SetValue(Index, FModel.Fields[Index].Choices[TComboBox(Sender).ItemIndex]);
  end;
  UpdateState(Index);
end;

procedure TAtlasProjectSettingsDialog.TextComboChange(Sender: TObject);
var
  Index, Choice: Integer;
  mText: string;
begin
  Index := TComboBox(Sender).Tag;
  mText := Trim(TComboBox(Sender).Text);
  FRaw[Index] := mText;
  // Eine Anzeige aus der Liste speichert ihren Wert ("Delphi 12 (23.0)" → "23.0"), sonst den Text.
  for Choice := 0 to High(FTextChoices[Index]) do
  begin
    if FTextChoices[Index][Choice].Caption = mText then
    begin
      FModel.SetValue(Index, FTextChoices[Index][Choice].Json);
      UpdateState(Index);
      Exit;
    end;
  end;
  if mText = '' then
  begin
    FModel.SetValue(Index, '');
  end
  else
  begin
    FModel.SetValue(Index, TAtlasJsonText.Quote(mText));
  end;
  UpdateState(Index);
end;

procedure TAtlasProjectSettingsDialog.MemoChange(Sender: TObject);
var
  Index: Integer;
  Line: string;
  List: TJSONArray;
begin
  Index := TMemo(Sender).Tag;
  List := TJSONArray.Create;
  try
    for Line in TMemo(Sender).Lines do
    begin
      if Trim(Line) <> '' then
      begin
        List.Add(Trim(Line));
      end;
    end;
    if List.Count = 0 then
    begin
      FModel.SetValue(Index, '');
    end
    else
    begin
      FModel.SetValue(Index, List.ToJSON);
    end;
  finally
    List.Free;
  end;
  UpdateState(Index);
end;

procedure TAtlasProjectSettingsDialog.JsonChange(Sender: TObject);
var
  Index: Integer;
  mText: string;
begin
  Index := TMemo(Sender).Tag;
  mText := Trim(TMemo(Sender).Text);
  FRaw[Index] := mText;
  FRawValid[Index] := (mText = '') or IsJsonValue(mText);
  if mText = '' then
  begin
    FModel.SetValue(Index, '');
  end
  else if FRawValid[Index] then
  begin
    FModel.SetValue(Index, mText);
  end;
  if FRawValid[Index] then
  begin
    TMemo(Sender).Font.Color := clWindowText;
  end
  else
  begin
    TMemo(Sender).Font.Color := clRed;
  end;
  UpdateState(Index);
end;

procedure TAtlasProjectSettingsDialog.BrowseClick(Sender: TObject);
var
  Index: Integer;
  Dialog: TSaveDialog;
begin
  Index := TButton(Sender).Tag;
  Dialog := TSaveDialog.Create(nil);
  try
    Dialog.Filter := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsFileFilter);
    Dialog.Options := Dialog.Options - [ofOverwritePrompt];
    if FRaw[Index] <> '' then
    begin
      Dialog.FileName := FRaw[Index];
    end;
    if Dialog.Execute and (FFileEdits[Index] <> nil) then
    begin
      FFileEdits[Index].Text := Dialog.FileName;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasProjectSettingsDialog.ResetClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := TButton(Sender).Tag;
  FModel.Reset(Index);
  FRaw[Index] := '';
  FRawValid[Index] := True;
  if Index = FRuleIndex then
  begin
    FRulesJson := '';
  end;
  // Nicht im Klick des Knopfs neu aufbauen: ShowPage gibt ihn frei.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Settings,
    procedure
    begin
      ShowCurrent;
    end);
end;

procedure TAtlasProjectSettingsDialog.OpenClick(Sender: TObject);
begin
  if Assigned(FOnOpenFile) then
  begin
    ModalResult := mrCancel;
    FOnOpenFile();
  end;
end;

function TAtlasProjectSettingsDialog.Validate: Boolean;
var
  Index, Number: Integer;
  Issues: TArray<TAtlasSettingIssue>;
  Issue: TAtlasSettingIssue;
  Checked, Errors: Boolean;
  Lines: string;
begin
  Result := False;
  for Index := 0 to FModel.Count - 1 do
  begin
    if (FModel.Fields[Index].Kind = TAtlasSettingKind.Integer_) and FModel.Typed(Index) and (FRaw[Index] <> '') and
      not TryStrToInt(FRaw[Index], Number) then
    begin
      MessageBox(Handle, PChar(TAtlasStrings.Fmt(TAtlasTextId.ProjectSettingsBadNumber,
        [FModel.Fields[Index].Path, FRaw[Index]])), PChar(Caption), MB_ICONWARNING or MB_OK);
      Exit;
    end;
    if not FRawValid[Index] then
    begin
      MessageBox(Handle, PChar(TAtlasStrings.Fmt(TAtlasTextId.ProjectSettingsJsonInvalid,
        [FModel.Fields[Index].Path])), PChar(Caption), MB_ICONWARNING or MB_OK);
      Exit;
    end;
  end;
  if not FModel.Modified or not Assigned(FOnValidate) then
  begin
    Exit(True);
  end;
  // Derselbe Parser wie im Server; Fehler verhindern das Speichern, Hinweise fragen nach.
  Issues := FOnValidate(FModel.ResultText, Checked);
  if Length(Issues) = 0 then
  begin
    Exit(True);
  end;
  Errors := False;
  for Issue in Issues do
  begin
    if Issue.Error then
    begin
      Errors := True;
    end;
  end;
  Lines := string.Join(sLineBreak, TAtlasSettingsValidation.Lines(Issues));
  if Errors then
  begin
    MessageBox(Handle, PChar(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCheckErrors) + sLineBreak + sLineBreak +
      Lines), PChar(Caption), MB_ICONWARNING or MB_OK);
    Exit;
  end;
  Result := MessageBox(Handle, PChar(TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCheckWarnings) + sLineBreak +
    sLineBreak + Lines), PChar(Caption), MB_ICONQUESTION or MB_YESNO) = IDYES;
end;

procedure TAtlasProjectSettingsDialog.OkClick(Sender: TObject);
begin
  if Validate then
  begin
    ModalResult := mrOk;
  end;
end;

end.
