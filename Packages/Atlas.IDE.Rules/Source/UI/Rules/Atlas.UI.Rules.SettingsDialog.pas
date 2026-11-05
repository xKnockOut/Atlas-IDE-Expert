unit Atlas.UI.Rules.SettingsDialog;

// Regel-Editor im Dialog der Server-Einstellungen (#909), Teil des Moduls
// Prüfregeln (#1755; vorher Atlas.UI.Settings.ProjectDialog in Base). Der
// Dialog von Base (TAtlasProjectSettingsDialog) zeigt "rules" ohne Modul als
// JSON-Text; TAtlasRulesSettingsDialog leitet ab und zeigt dort den
// Regel-Editor (TAtlasRulesEditor) aus dem Regelkatalog (Catalog): auf der
// Seite alle Regeln mit Suche, darunter im Seitenbaum ein Knoten je Gruppe mit
// Hauptschalter. Schweregrad, Ausnahmen und Optionen; Werte der globalen Datei
// als „(global: …)“. Geändert wird je Regel nur ihr Wert in der Datei. Die
// Prüfregeln stehen nur hier (Projekt und „Weitere globale Einstellungen“),
// nicht in Tools › Optionen. Den Dialog öffnet Base über
// IAtlasSettingsDialogProvider (TAtlasRulesDialogProvider).

interface

uses
  System.Classes,
  Vcl.ComCtrls,
  Atlas.UI.Settings.ProjectDialog,
  Atlas.UI.Rules.Editor;

type
  /// <summary>Der Dialog mit dem Regel-Editor (#909) für das Feld "rules".</summary>
  TAtlasRulesSettingsDialog = class(TAtlasProjectSettingsDialog)
  private
    // Regel-Editor: Wert von "rules" mit den Änderungen.
    FRulesJson: string;
    /// <summary>Im Projektmodus: "rules" der globalen Einstellungen, für die Anzeige „(global: …)“.</summary>
    FGlobalRulesJson: string;
    FRuleEditor: TAtlasRulesEditor;
    /// <summary>Höhe des Regel-Editors, mit der die Felder darunter stehen (#1296).</summary>
    FRuleHeight: Integer;
    function HasRule(const AId: string): Boolean;
    function RuleTarget(const AId: string): TTreeNode;
    procedure ApplyRules(const AUpdated: string);
    procedure RuleEditorChange(Sender: TObject);
    procedure RuleEditorResize(Sender: TObject);
    function GetRuleList: TListView;
  protected
    function RuleGroups: TArray<string>; override;
    function RuleGroupCaption(const AGroup: string): string; override;
    procedure ValuesReady; override;
    procedure ShowGroup(AGroup: Integer); override;
    procedure ClearBox; override;
    procedure ResetValue(AIndex: Integer); override;
    function HasRuleEditor: Boolean; override;
    function AddRuleTable(ATop: Integer; const AGroup: string): Integer; override;
  public
    /// <summary>Schweregrad einer Regel wie über die Tabelle setzen ('' = Vorgabe); False ohne die Regel.</summary>
    function SetRuleSeverity(const AId, ASeverity: string): Boolean;
    function SelectRule(const AId: string): Boolean; override;
    property RuleList: TListView read GetRuleList;
    /// <summary>Regel-Editor auf der gezeigten Seite; nil ohne "rules".</summary>
    property RuleEditor: TAtlasRulesEditor read FRuleEditor;
  end;

  /// <summary>Anbieter der Dialogklasse für Base (IAtlasSettingsDialogProvider).</summary>
  TAtlasRulesDialogProvider = class(TInterfacedObject, IAtlasSettingsDialogProvider)
  public
    function DialogClass: TAtlasProjectSettingsDialogClass;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Graphics,
  Atlas.Core.Rules.Table;

const
  cGap = 8;

{ TAtlasRulesSettingsDialog }

function TAtlasRulesSettingsDialog.RuleGroups: TArray<string>;
var
  mIndex: Integer;
begin
  // GroupIds ist ein statisches Array; Delphi weist es nicht an TArray<string> zu (E2010), FPC schon.
  SetLength(Result, Length(TAtlasRuleTable.GroupIds));
  for mIndex := 0 to High(TAtlasRuleTable.GroupIds) do
  begin
    Result[mIndex] := TAtlasRuleTable.GroupIds[mIndex];
  end;
end;

function TAtlasRulesSettingsDialog.RuleGroupCaption(const AGroup: string): string;
begin
  Result := AtlasRuleGroupCaption(AGroup);
end;

procedure TAtlasRulesSettingsDialog.ValuesReady;
begin
  if FRuleIndex >= 0 then
  begin
    FRulesJson := FModel.Current(FRuleIndex);
    if not FModel.Global then
    begin
      FGlobalRulesJson := FModel.Inherited_(FRuleIndex);
    end;
  end;
end;

function TAtlasRulesSettingsDialog.RuleTarget(const AId: string): TTreeNode;
var
  mRow: TAtlasRuleRow;
begin
  Result := nil;
  if (FRuleIndex < 0) or (FCatalog = nil) then
  begin
    Exit;
  end;
  for mRow in TAtlasRuleTable.Rows(FCatalog, FRulesJson, FGlobalRulesJson) do
  begin
    if SameText(mRow.Id, AId) then
    begin
      // Knoten der Gruppe der Regel, sonst die Seite mit allen Regeln.
      Result := GroupNode(mRow.Group);
      if (Result = nil) and (RulePage >= 0) then
      begin
        Result := FPageNodes[RulePage];
      end;
    end;
  end;
end;

function TAtlasRulesSettingsDialog.SelectRule(const AId: string): Boolean;
var
  mTarget: TTreeNode;
begin
  Result := False;
  mTarget := RuleTarget(AId);
  if mTarget <> nil then
  begin
    SelectNode(mTarget);
    Result := (FRuleEditor <> nil) and FRuleEditor.SelectRule(AId);
  end;
end;

procedure TAtlasRulesSettingsDialog.ClearBox;
begin
  inherited ClearBox;
  FRuleEditor := nil;
end;

procedure TAtlasRulesSettingsDialog.ResetValue(AIndex: Integer);
begin
  inherited ResetValue(AIndex);
  if AIndex = FRuleIndex then
  begin
    FRulesJson := '';
  end;
end;

procedure TAtlasRulesSettingsDialog.ShowGroup(AGroup: Integer);
var
  mTitle: TLabel;
begin
  ClearBox;
  FCurrentPage := -1;
  FCurrentGroup := AGroup;
  mTitle := TLabel.Create(FBox);
  mTitle.Parent := FBox;
  mTitle.SetBounds(cGap * 2, cGap, 400, 16);
  mTitle.Font.Style := [fsBold];
  mTitle.Caption := AtlasRuleGroupCaption(FGroups[AGroup]);
  AddRuleTable(cGap + 24, FGroups[AGroup]);
end;

function TAtlasRulesSettingsDialog.HasRuleEditor: Boolean;
begin
  Result := True;
end;

function TAtlasRulesSettingsDialog.AddRuleTable(ATop: Integer; const AGroup: string): Integer;
begin
  // Regel-Editor (#909); er braucht für Tabelle und Auswahllisten ein Fenster. Mit AGroup nur diese Gruppe mit
  // ihrem Hauptschalter.
  FRuleEditor := TAtlasRulesEditor.Create(FBox);
  FRuleEditor.Parent := FBox;
  FRuleEditor.SetBounds(cGap * 2, ATop, FBox.ClientWidth - cGap * 5, 400);
  FRuleEditor.Anchors := [akLeft, akTop, akRight];
  FRuleEditor.FixedGroup := AGroup;
  FRuleEditor.SetRules(FCatalog, FRulesJson, FGlobalRulesJson);
  FRuleEditor.OnChange := RuleEditorChange;
  FRuleEditor.HandleNeeded;
  FRuleHeight := FRuleEditor.Height;
  FRuleEditor.OnResize := RuleEditorResize;
  Result := ATop + FRuleHeight + cGap;
end;

procedure TAtlasRulesSettingsDialog.RuleEditorResize(Sender: TObject);
var
  mIndex, mShift, mBottom: Integer;
  mControl: TControl;
begin
  // Die Seite steht mit festen Positionen; der Editor wächst mit der markierten Regel (Optionen, Beispiele) und
  // überdeckte sonst die Felder darunter (#1296). Alles unter seiner alten Unterkante rückt um die Differenz.
  if (FRuleEditor = nil) or (csDestroying in FRuleEditor.ComponentState) then
  begin
    Exit;
  end;
  mShift := FRuleEditor.Height - FRuleHeight;
  if mShift = 0 then
  begin
    Exit;
  end;
  mBottom := FRuleEditor.Top + FRuleHeight;
  FRuleHeight := FRuleEditor.Height;
  FBox.DisableAlign;
  try
    for mIndex := 0 to FBox.ControlCount - 1 do
    begin
      mControl := FBox.Controls[mIndex];
      if (mControl <> FRuleEditor) and (mControl.Top >= mBottom) then
      begin
        mControl.Top := mControl.Top + mShift;
      end;
    end;
  finally
    FBox.EnableAlign;
  end;
end;

function TAtlasRulesSettingsDialog.GetRuleList: TListView;
begin
  Result := nil;
  if FRuleEditor <> nil then
  begin
    Result := FRuleEditor.List;
  end;
end;

procedure TAtlasRulesSettingsDialog.ApplyRules(const AUpdated: string);
var
  mChange: TPair<string, string>;
begin
  // Nur die geänderten Regeln in die Datei: Kommentare und andere Regeln bleiben.
  for mChange in TAtlasRuleTable.Changes(FRulesJson, AUpdated) do
  begin
    FModel.SetPath(mChange.Key, mChange.Value);
  end;
  FRulesJson := AUpdated;
end;

procedure TAtlasRulesSettingsDialog.RuleEditorChange(Sender: TObject);
begin
  ApplyRules(FRuleEditor.RulesJson);
  UpdateState(FRuleIndex);
end;

function TAtlasRulesSettingsDialog.HasRule(const AId: string): Boolean;
var
  mRow: TAtlasRuleRow;
begin
  Result := False;
  for mRow in TAtlasRuleTable.Rows(FCatalog, FRulesJson, FGlobalRulesJson) do
  begin
    if SameText(mRow.Id, AId) then
    begin
      Result := True;
    end;
  end;
end;

function TAtlasRulesSettingsDialog.SetRuleSeverity(const AId, ASeverity: string): Boolean;
begin
  if FRuleEditor <> nil then
  begin
    Exit(FRuleEditor.SetRuleSeverity(AId, ASeverity));
  end;
  Result := HasRule(AId);
  if Result then
  begin
    ApplyRules(TAtlasRuleTable.WithSeverity(FRulesJson, AId, ASeverity));
  end;
end;

{ TAtlasRulesDialogProvider }

function TAtlasRulesDialogProvider.DialogClass: TAtlasProjectSettingsDialogClass;
begin
  Result := TAtlasRulesSettingsDialog;
end;

end.
