unit Atlas.UI.Debug.ExceptionRuleList;

// Fenster „Exception-Regeln“ (#838), reine VCL: alle Regeln in der Reihenfolge,
// in der sie gelten (persönliche vor denen der Projektdatei), mit Treffern der
// laufenden Sitzung.
//   Ein | Klasse | Ort | Meldung | Aktion | Herkunft | Treffer
//   [Neu …] [Bearbeiten …] [Ein/Aus] [Löschen] [Nach oben] [Nach unten]
//   [Projektdatei öffnen]
//   Die erste passende Regel gewinnt; …
//                                            [Übernehmen] [Abbrechen]
// Persönliche Regeln und die des Projekts lassen sich ändern, löschen und
// innerhalb ihrer Gruppe verschieben (Knöpfe oder Ziehen mit der Maus); „Gilt
// für“ im Dialog wechselt die Gruppe, die Regel kommt dann an deren Ende,
// ebenso neue Regeln. Speichern übernimmt der Aufrufer (RulesOf je Herkunft).
// Bearbeitet wird über Editor (Vorgabe TAtlasExceptionRuleEditDialog.Execute).
// Aufgebaut im Code (keine DFM).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Debug.ExceptionRules,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.Debug.Exceptions.Strings;

type
  /// <summary>Knöpfe unter der Liste.</summary>
  TAtlasRuleListButton = (New, Edit, Toggle, Delete, Up, Down, OpenProject);

  /// <summary>Regel bearbeiten; ANew beim Anlegen. True nach „Übernehmen“.</summary>
  TAtlasExceptionRuleEditor = reference to function(var ARule: TAtlasExceptionRule; ANew: Boolean): Boolean;

  TAtlasExceptionRuleListDialog = class(TAtlasDialog)
  private
    FRules: TAtlasExceptionRuleList;
    FHits: TAtlasExceptionRuleHits;
    FList: TListView;
    FButtons: array[TAtlasRuleListButton] of TButton;
    FEditor: TAtlasExceptionRuleEditor;
    FOpenProject: TProc;
    procedure CreateList;
    procedure CreateButtons;
    procedure ListSelect(Sender: TObject; AItem: TListItem; ASelected: Boolean);
    procedure ListDblClick(Sender: TObject);
    procedure ListDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
    procedure ListDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure NewClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
    procedure ToggleClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure OpenProjectClick(Sender: TObject);
    /// <summary>Index hinter der letzten Regel der Herkunft AOrigin (persönliche stehen vorn).</summary>
    function GroupEnd(AOrigin: TAtlasExceptionRuleOrigin): Integer;
    /// <summary>Beide Indizes gültig und von gleicher Herkunft?</summary>
    function SameGroup(AIndex, AOther: Integer): Boolean;
    procedure MoveSelected(ADelta: Integer);
    function AddAction(ARow: TAtlasButtonRow; AId: TAtlasExceptionsTextId; AClick: TNotifyEvent): TButton;
    procedure UpdateButtons;
    function GetButton(AKind: TAtlasRuleListButton): TButton;
  protected
    procedure DoShow; override;
  public
    constructor CreateFor(AOwner: TComponent; const ARules: TAtlasExceptionRuleList;
      const AHits: TAtlasExceptionRuleHits);
    /// <summary>Liste füllen; braucht ein Fenster (DoShow, Tests nach HandleNeeded der Liste).</summary>
    procedure Fill;
    /// <summary>Zeile wählen (-1: keine).</summary>
    procedure Select(AIndex: Integer);
    function Selected: Integer;
    /// <summary>Regeln der Herkunft AOrigin nach dem Bearbeiten, in Reihenfolge.</summary>
    function RulesOf(AOrigin: TAtlasExceptionRuleOrigin): TAtlasExceptionRuleList;
    /// <summary>Gewählte Regel an die Stelle ATarget ziehen (nur in ihrer Gruppe); False sonst.</summary>
    function DropAt(ATarget: Integer): Boolean;
    /// <summary>Spalten einer Zeile: Ein, Klasse, Ort, Meldung, Aktion, Herkunft, Treffer.</summary>
    class function Cells(const ARule: TAtlasExceptionRule; AHits: Integer): TArray<string>; static;
    /// <summary>Fenster zeigen; True mit den Regeln je Herkunft nach „Übernehmen“.</summary>
    class function Execute(const ARules: TAtlasExceptionRuleList; const AHits: TAtlasExceptionRuleHits;
      const AOpenProject: TProc; out APersonal, AProject: TAtlasExceptionRuleList): Boolean; static;
    property List: TListView read FList;
    property Rules: TAtlasExceptionRuleList read FRules;
    property Editor: TAtlasExceptionRuleEditor read FEditor write FEditor;
    property OpenProject: TProc read FOpenProject write FOpenProject;
    property Buttons[AKind: TAtlasRuleListButton]: TButton read GetButton;
  end;

implementation

uses
  Atlas.Core.Style.Signal,
  Atlas.UI.Debug.ExceptionRuleEdit;

const
  cWidth = 760;
  cListHeight = 260;
  cNoteHeight = 36;
  cColumnWidths: array[0..6] of Integer = (40, 150, 170, 160, 110, 80, 50);
  cOnMark = '✓';
  cColumnTexts: array[0..6] of TAtlasExceptionsTextId = (TAtlasExceptionsTextId.DebugRulesColumnOn,
    TAtlasExceptionsTextId.DebugRulesColumnClass, TAtlasExceptionsTextId.DebugRulesColumnPlace,
    TAtlasExceptionsTextId.DebugRulesColumnMessage, TAtlasExceptionsTextId.DebugRulesColumnAction,
    TAtlasExceptionsTextId.DebugRulesColumnOrigin, TAtlasExceptionsTextId.DebugRulesColumnHits);

function DefaultEditor: TAtlasExceptionRuleEditor;
begin
  Result :=
    function(var ARule: TAtlasExceptionRule; ANew: Boolean): Boolean
    begin
      Result := TAtlasExceptionRuleEditDialog.Execute(ARule, ANew);
    end;
end;

{ TAtlasExceptionRuleListDialog }

constructor TAtlasExceptionRuleListDialog.CreateFor(AOwner: TComponent; const ARules: TAtlasExceptionRuleList;
  const AHits: TAtlasExceptionRuleHits);
var
  mButtons: TAtlasButtonRow;
  mNote: TAtlasNoteLabel;
  mSave: TButton;
begin
  inherited CreateDialog(AOwner, TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesTitle), cWidth);
  FRules := Copy(ARules);
  FHits := AHits;
  FEditor := DefaultEditor;
  CreateList;
  CreateButtons;
  mNote := AddNote(cNoteHeight);
  mNote.ShowNote(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesNote), TAtlasSignalKind.Info);
  mButtons := AddButtonRow;
  mSave := mButtons.AddButton(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesSave),
    TAtlasButtonKind.Default);
  mSave.ModalResult := mrOk;
  mButtons.AddButton(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesCancel), TAtlasButtonKind.Cancel);
  FitHeight;
  AllowResize(FList.Parent);
  UpdateButtons;
end;

procedure TAtlasExceptionRuleListDialog.DoShow;
begin
  inherited;
  Fill;
end;

procedure TAtlasExceptionRuleListDialog.CreateList;
var
  mRow: TPanel;
  mIndex: Integer;
  mColumn: TListColumn;
begin
  mRow := AddRow(cListHeight);
  FList := TListView.Create(Self);
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.ReadOnly := True;
  FList.HideSelection := False;
  FList.Parent := mRow;
  for mIndex := Low(cColumnWidths) to High(cColumnWidths) do
  begin
    mColumn := FList.Columns.Add;
    mColumn.Caption := TAtlasExceptionsStrings.Text(cColumnTexts[mIndex]);
    mColumn.Width := ScaleValue(cColumnWidths[mIndex]);
  end;
  FList.OnSelectItem := ListSelect;
  FList.OnDblClick := ListDblClick;
  FList.DragMode := dmAutomatic;
  FList.OnDragOver := ListDragOver;
  FList.OnDragDrop := ListDragDrop;
end;

function TAtlasExceptionRuleListDialog.AddAction(ARow: TAtlasButtonRow; AId: TAtlasExceptionsTextId;
  AClick: TNotifyEvent): TButton;
begin
  Result := ARow.AddButton(TAtlasExceptionsStrings.Text(AId));
  Result.ModalResult := mrNone;
  Result.OnClick := AClick;
end;

procedure TAtlasExceptionRuleListDialog.CreateButtons;
var
  mRow: TAtlasButtonRow;
begin
  mRow := AddButtonRow;
  FButtons[TAtlasRuleListButton.New] := AddAction(mRow, TAtlasExceptionsTextId.DebugRulesNew, NewClick);
  FButtons[TAtlasRuleListButton.Edit] := AddAction(mRow, TAtlasExceptionsTextId.DebugRulesEdit, EditClick);
  FButtons[TAtlasRuleListButton.Toggle] := AddAction(mRow, TAtlasExceptionsTextId.DebugRulesToggle, ToggleClick);
  FButtons[TAtlasRuleListButton.Delete] := AddAction(mRow, TAtlasExceptionsTextId.DebugRulesDelete, DeleteClick);
  FButtons[TAtlasRuleListButton.Up] := AddAction(mRow, TAtlasExceptionsTextId.DebugRulesUp, UpClick);
  FButtons[TAtlasRuleListButton.Down] := AddAction(mRow, TAtlasExceptionsTextId.DebugRulesDown, DownClick);
  FButtons[TAtlasRuleListButton.OpenProject] := AddAction(mRow, TAtlasExceptionsTextId.DebugRulesOpenProject,
    OpenProjectClick);
end;

function TAtlasExceptionRuleListDialog.GetButton(AKind: TAtlasRuleListButton): TButton;
begin
  Result := FButtons[AKind];
end;

class function TAtlasExceptionRuleListDialog.Cells(const ARule: TAtlasExceptionRule; AHits: Integer): TArray<string>;
var
  mPlace, mMessage, mOrigin, mOn, mClass: string;
begin
  mOn := '';
  if ARule.Enabled then
  begin
    mOn := cOnMark;
  end;
  mPlace := ARule.Location;
  if mPlace = '' then
  begin
    mPlace := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesAnywhere);
  end;
  mMessage := ARule.Message;
  if ARule.HasMessage and (ARule.MessageMatch = TAtlasMessageMatch.NotMatches) then
  begin
    mMessage := TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugRulesNotMessage, [ARule.Message]);
  end;
  mOrigin := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesOriginPersonal);
  if ARule.Origin = TAtlasExceptionRuleOrigin.Project then
  begin
    mOrigin := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugRulesOriginProject);
  end;
  mClass := ARule.ExceptionClass;
  if ARule.Descendants then
  begin
    mClass := TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugRulesClassDescendants, [mClass]);
  end;
  Result := TArray<string>.Create(mOn, mClass, mPlace, mMessage,
    TAtlasExceptionRuleEditDialog.ActionText(ARule.Action), mOrigin, IntToStr(AHits));
end;

procedure TAtlasExceptionRuleListDialog.Fill;
var
  mSelected, mCell: Integer;
  mRule: TAtlasExceptionRule;
  mCells: TArray<string>;
  mItem: TListItem;
begin
  mSelected := Selected;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mRule in FRules do
    begin
      mCells := Cells(mRule, FHits.CountOf(mRule.Key));
      mItem := FList.Items.Add;
      mItem.Caption := mCells[0];
      for mCell := 1 to High(mCells) do
      begin
        mItem.SubItems.Add(mCells[mCell]);
      end;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  Select(mSelected);
end;

procedure TAtlasExceptionRuleListDialog.Select(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FList.Items.Count) then
  begin
    FList.Items[AIndex].Selected := True;
    FList.Items[AIndex].Focused := True;
  end
  else
  begin
    FList.Selected := nil;
  end;
  UpdateButtons;
end;

function TAtlasExceptionRuleListDialog.Selected: Integer;
begin
  Result := -1;
  if (FList <> nil) and (FList.Selected <> nil) then
  begin
    Result := FList.Selected.Index;
  end;
end;

function TAtlasExceptionRuleListDialog.GroupEnd(AOrigin: TAtlasExceptionRuleOrigin): Integer;
var
  mRule: TAtlasExceptionRule;
begin
  Result := 0;
  for mRule in FRules do
  begin
    if Ord(mRule.Origin) <= Ord(AOrigin) then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasExceptionRuleListDialog.SameGroup(AIndex, AOther: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FRules)) and (AOther >= 0) and (AOther <= High(FRules)) and
    (FRules[AIndex].Origin = FRules[AOther].Origin);
end;

function TAtlasExceptionRuleListDialog.RulesOf(AOrigin: TAtlasExceptionRuleOrigin): TAtlasExceptionRuleList;
var
  mRule: TAtlasExceptionRule;
begin
  Result := nil;
  for mRule in FRules do
  begin
    if mRule.Origin = AOrigin then
    begin
      Result := Result + [mRule];
    end;
  end;
end;

procedure TAtlasExceptionRuleListDialog.UpdateButtons;
var
  mIndex: Integer;
  mAny: Boolean;
begin
  mIndex := Selected;
  mAny := (mIndex >= 0) and (mIndex <= High(FRules));
  FButtons[TAtlasRuleListButton.Edit].Enabled := mAny;
  FButtons[TAtlasRuleListButton.Toggle].Enabled := mAny;
  FButtons[TAtlasRuleListButton.Delete].Enabled := mAny;
  // Verschoben wird nur innerhalb der Gruppe: persönliche Regeln gelten immer vor denen des Projekts.
  FButtons[TAtlasRuleListButton.Up].Enabled := SameGroup(mIndex, mIndex - 1);
  FButtons[TAtlasRuleListButton.Down].Enabled := SameGroup(mIndex, mIndex + 1);
  FButtons[TAtlasRuleListButton.OpenProject].Enabled := Assigned(FOpenProject);
end;

procedure TAtlasExceptionRuleListDialog.ListSelect(Sender: TObject; AItem: TListItem; ASelected: Boolean);
begin
  UpdateButtons;
end;

procedure TAtlasExceptionRuleListDialog.ListDblClick(Sender: TObject);
begin
  if FButtons[TAtlasRuleListButton.Edit].Enabled then
  begin
    EditClick(Sender);
  end;
end;

procedure TAtlasExceptionRuleListDialog.ListDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState;
  var Accept: Boolean);
var
  mItem: TListItem;
begin
  mItem := FList.GetItemAt(X, Y);
  Accept := (Source = FList) and (mItem <> nil) and SameGroup(Selected, mItem.Index);
end;

procedure TAtlasExceptionRuleListDialog.ListDragDrop(Sender, Source: TObject; X, Y: Integer);
var
  mItem: TListItem;
begin
  mItem := FList.GetItemAt(X, Y);
  if (Source = FList) and (mItem <> nil) then
  begin
    DropAt(mItem.Index);
  end;
end;

function TAtlasExceptionRuleListDialog.DropAt(ATarget: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := Selected;
  Result := (ATarget <> mIndex) and SameGroup(mIndex, ATarget) and
    TAtlasExceptionRules.MoveRule(FRules, mIndex, ATarget - mIndex);
  if Result then
  begin
    Fill;
    Select(ATarget);
  end;
end;

procedure TAtlasExceptionRuleListDialog.NewClick(Sender: TObject);
var
  mRule: TAtlasExceptionRule;
  mAt: Integer;
begin
  mRule := TAtlasExceptionRule.Create('', '', TAtlasMessageMatch.Matches, TAtlasExceptionAction.Log);
  if not FEditor(mRule, True) then
  begin
    Exit;
  end;
  mAt := GroupEnd(mRule.Origin);
  Insert(mRule, FRules, mAt);
  Fill;
  Select(mAt);
end;

procedure TAtlasExceptionRuleListDialog.EditClick(Sender: TObject);
var
  mIndex: Integer;
  mRule: TAtlasExceptionRule;
begin
  mIndex := Selected;
  if not FButtons[TAtlasRuleListButton.Edit].Enabled then
  begin
    Exit;
  end;
  mRule := FRules[mIndex];
  if not FEditor(mRule, False) then
  begin
    Exit;
  end;
  if mRule.Origin = FRules[mIndex].Origin then
  begin
    FRules[mIndex] := mRule;
  end
  else
  begin
    // Andere Herkunft: ans Ende der anderen Gruppe.
    Delete(FRules, mIndex, 1);
    mIndex := GroupEnd(mRule.Origin);
    Insert(mRule, FRules, mIndex);
  end;
  Fill;
  Select(mIndex);
end;

procedure TAtlasExceptionRuleListDialog.ToggleClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := Selected;
  if FButtons[TAtlasRuleListButton.Toggle].Enabled then
  begin
    FRules[mIndex].Enabled := not FRules[mIndex].Enabled;
    Fill;
  end;
end;

procedure TAtlasExceptionRuleListDialog.DeleteClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := Selected;
  if FButtons[TAtlasRuleListButton.Delete].Enabled then
  begin
    Delete(FRules, mIndex, 1);
    Fill;
    Select(mIndex - 1);
  end;
end;

procedure TAtlasExceptionRuleListDialog.MoveSelected(ADelta: Integer);
begin
  DropAt(Selected + ADelta);
end;

procedure TAtlasExceptionRuleListDialog.UpClick(Sender: TObject);
begin
  if FButtons[TAtlasRuleListButton.Up].Enabled then
  begin
    MoveSelected(-1);
  end;
end;

procedure TAtlasExceptionRuleListDialog.DownClick(Sender: TObject);
begin
  if FButtons[TAtlasRuleListButton.Down].Enabled then
  begin
    MoveSelected(1);
  end;
end;

procedure TAtlasExceptionRuleListDialog.OpenProjectClick(Sender: TObject);
begin
  if Assigned(FOpenProject) then
  begin
    FOpenProject();
  end;
end;

class function TAtlasExceptionRuleListDialog.Execute(const ARules: TAtlasExceptionRuleList;
  const AHits: TAtlasExceptionRuleHits; const AOpenProject: TProc; out APersonal, AProject: TAtlasExceptionRuleList):
  Boolean;
var
  mDialog: TAtlasExceptionRuleListDialog;
begin
  APersonal := nil;
  AProject := nil;
  mDialog := TAtlasExceptionRuleListDialog.CreateFor(nil, ARules, AHits);
  try
    mDialog.OpenProject := AOpenProject;
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      APersonal := mDialog.RulesOf(TAtlasExceptionRuleOrigin.Personal);
      AProject := mDialog.RulesOf(TAtlasExceptionRuleOrigin.Project);
    end;
  finally
    mDialog.Free;
  end;
end;

end.
