unit Atlas.UI.Debug.StepFilterPatterns;

// Muster im Fenster „Schrittfilter“ (#850), reine VCL: Eingabezeile mit
// „Hinzufügen“ und „Entfernen“ und darunter die Liste der Muster mit ihren
// Treffern. Bearbeiten mit F2 oder Doppelklick, Entf entfernt, Enter in der
// Eingabezeile fügt an. Was gültig ist, entscheidet TAtlasStepFilterEdit; jede
// Änderung der Muster meldet OnChange. Die Treffertexte setzt der Frame
// (SetHits), sobald die IDE-Schicht gezählt hat.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls;

type
  TAtlasStepFilterPatterns = class(TPanel)
  private
    FEdit: TEdit;
    FAdd: TButton;
    FRemove: TButton;
    FList: TListView;
    FPatterns: TArray<string>;
    /// <summary>Treffer je Muster als Text, in der Reihenfolge der Muster ('' solange nicht gezählt).</summary>
    FHits: TArray<string>;
    FOnChange: TNotifyEvent;
    procedure BuildList(AFrame: TWinControl);
    procedure UpdateButtons;
    procedure Changed;
    function HitText(AIndex: Integer): string;
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListEdited(Sender: TObject; Item: TListItem; var S: string);
  public
    /// <summary>Eingabezeile oben in AFrame an ATop, die Liste füllt den Rest von AFrame. AFrame ist Besitzer;
    /// seine Auflösung bestimmt die Größen.</summary>
    constructor CreateIn(AFrame: TWinControl; ATop: Integer; AOnChange: TNotifyEvent);
    /// <summary>Knopf rechts in AParent (Besitzer AOwner), Breite nach APPI.</summary>
    class function AddButton(AOwner: TComponent; AParent: TWinControl; APPI: Integer; const ACaption: string;
      AClick: TNotifyEvent): TButton; static;
    /// <summary>Gespeicherte Muster; die Liste baut sich nur neu, wenn sie sich geändert haben (sonst stört es ein
    /// laufendes Bearbeiten). Meldet nichts über OnChange.</summary>
    procedure SetPatterns(const APatterns: TArray<string>);
    /// <summary>Treffertexte je Muster, in der Reihenfolge der Muster.</summary>
    procedure SetHits(const AHits: TArray<string>);
    /// <summary>Liste neu füllen; braucht ein Fenster, legt es an, sobald AFrame eines hat.</summary>
    procedure Fill;
    /// <summary>Muster aus dem Eingabefeld anfügen; False, wenn es ungültig ist oder schon darin steht.</summary>
    function AddPattern: Boolean;
    /// <summary>Gewähltes Muster entfernen; False ohne Auswahl.</summary>
    function RemoveSelected: Boolean;
    /// <summary>Muster AIndex durch AText ersetzen; False, wenn AText ungültig ist oder schon darin steht.</summary>
    function ReplacePattern(AIndex: Integer; const AText: string): Boolean;
    property Edit: TEdit read FEdit;
    property AddButtonControl: TButton read FAdd;
    property RemoveButtonControl: TButton read FRemove;
    property List: TListView read FList;
    property Patterns: TArray<string> read FPatterns;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Atlas.Text.StepFilter,
  Atlas.Core.Debug.StepFilterEdit,
  Atlas.UI.Debug.Stepping.Strings;

const
  /// <summary>Höhe der Eingabezeile bei 96 dpi.</summary>
  cBarHeight = 30;
  /// <summary>Breite der Knöpfe bei 96 dpi.</summary>
  cButtonWidth = 86;
  /// <summary>Spaltenbreiten bei 96 dpi.</summary>
  cPatternWidth = 260;
  cHitsWidth = 70;

{ TAtlasStepFilterPatterns }

constructor TAtlasStepFilterPatterns.CreateIn(AFrame: TWinControl; ATop: Integer; AOnChange: TNotifyEvent);
begin
  inherited Create(AFrame);
  FOnChange := AOnChange;
  Top := ATop;
  Height := MulDiv(cBarHeight, AFrame.CurrentPPI, 96);
  Align := alTop;
  Parent := AFrame;
  BevelOuter := bvNone;
  ShowCaption := False;
  ParentBackground := True;
  FRemove := AddButton(AFrame, Self, AFrame.CurrentPPI,
    TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterRemove), RemoveClick);
  FAdd := AddButton(AFrame, Self, AFrame.CurrentPPI, TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterAdd),
    AddClick);
  FEdit := TEdit.Create(AFrame);
  FEdit.Parent := Self;
  FEdit.Align := alClient;
  FEdit.AlignWithMargins := True;
  FEdit.TextHint := TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterPatternHint);
  FEdit.OnChange := EditChange;
  FEdit.OnKeyDown := EditKeyDown;
  BuildList(AFrame);
end;

class function TAtlasStepFilterPatterns.AddButton(AOwner: TComponent; AParent: TWinControl; APPI: Integer;
  const ACaption: string; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AParent;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := MulDiv(cButtonWidth, APPI, 96);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

procedure TAtlasStepFilterPatterns.BuildList(AFrame: TWinControl);
var
  mColumn: TListColumn;
begin
  FList := TListView.Create(Self);
  FList.Parent := AFrame;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := False;
  FList.MultiSelect := False;
  FList.ColumnClick := False;
  mColumn := FList.Columns.Add;
  mColumn.Caption := TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterColumnPattern);
  mColumn.Width := MulDiv(cPatternWidth, AFrame.CurrentPPI, 96);
  mColumn := FList.Columns.Add;
  mColumn.Caption := TAtlasSteppingStrings.Text(TAtlasSteppingTextId.StepFilterColumnHits);
  mColumn.Width := MulDiv(cHitsWidth, AFrame.CurrentPPI, 96);
  mColumn.Alignment := taRightJustify;
  FList.OnSelectItem := ListSelectItem;
  FList.OnKeyDown := ListKeyDown;
  FList.OnEdited := ListEdited;
end;

function TAtlasStepFilterPatterns.HitText(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(FHits)) then
  begin
    Result := FHits[AIndex];
  end;
end;

procedure TAtlasStepFilterPatterns.Fill;
var
  mIndex: Integer;
  mItem: TListItem;
begin
  // Die Liste braucht ein Fenster; hat der Rahmen schon eines, auch die Liste anlegen (sonst füllt CreateWnd).
  if not FList.HandleAllocated then
  begin
    if not FList.Parent.HandleAllocated then
    begin
      Exit;
    end;
    FList.HandleNeeded;
  end;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mIndex := 0 to High(FPatterns) do
    begin
      mItem := FList.Items.Add;
      mItem.Caption := FPatterns[mIndex];
      mItem.SubItems.Add(HitText(mIndex));
    end;
  finally
    FList.Items.EndUpdate;
  end;
  UpdateButtons;
end;

procedure TAtlasStepFilterPatterns.SetPatterns(const APatterns: TArray<string>);
var
  mRebuild: Boolean;
begin
  mRebuild := TStepFilterNames.PatternsText(APatterns) <> TStepFilterNames.PatternsText(FPatterns);
  FPatterns := Copy(APatterns);
  if mRebuild then
  begin
    Fill;
  end;
  UpdateButtons;
end;

procedure TAtlasStepFilterPatterns.SetHits(const AHits: TArray<string>);
var
  mIndex: Integer;
begin
  FHits := Copy(AHits);
  if not FList.HandleAllocated then
  begin
    Exit;
  end;
  for mIndex := 0 to FList.Items.Count - 1 do
  begin
    if FList.Items[mIndex].SubItems.Count > 0 then
    begin
      FList.Items[mIndex].SubItems[0] := HitText(mIndex);
    end;
  end;
end;

procedure TAtlasStepFilterPatterns.UpdateButtons;
begin
  FAdd.Enabled := TAtlasStepFilterEdit.CanAddPattern(FPatterns, FEdit.Text);
  FRemove.Enabled := FList.HandleAllocated and (FList.Selected <> nil);
end;

procedure TAtlasStepFilterPatterns.Changed;
begin
  UpdateButtons;
  if Assigned(FOnChange) then
  begin
    FOnChange(Self);
  end;
end;

procedure TAtlasStepFilterPatterns.AddClick(Sender: TObject);
begin
  AddPattern;
end;

procedure TAtlasStepFilterPatterns.RemoveClick(Sender: TObject);
begin
  RemoveSelected;
end;

procedure TAtlasStepFilterPatterns.EditChange(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TAtlasStepFilterPatterns.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    AddPattern;
    Key := 0;
  end;
end;

procedure TAtlasStepFilterPatterns.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
end;

procedure TAtlasStepFilterPatterns.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FList.IsEditing then
  begin
    Exit;
  end;
  if (Key = VK_DELETE) and (Shift = []) then
  begin
    RemoveSelected;
    Key := 0;
  end
  else if (Key = VK_F2) and (Shift = []) and (FList.Selected <> nil) then
  begin
    FList.Selected.EditCaption;
    Key := 0;
  end;
end;

procedure TAtlasStepFilterPatterns.ListEdited(Sender: TObject; Item: TListItem; var S: string);
begin
  // Ungültig oder doppelt: Das alte Muster bleibt stehen.
  if ReplacePattern(Item.Index, S) then
  begin
    S := Trim(S);
  end
  else
  begin
    S := Item.Caption;
  end;
end;

function TAtlasStepFilterPatterns.AddPattern: Boolean;
begin
  Result := TAtlasStepFilterEdit.CanAddPattern(FPatterns, FEdit.Text);
  if not Result then
  begin
    Exit;
  end;
  FPatterns := TStepFilterNames.WithPattern(FPatterns, Trim(FEdit.Text));
  FEdit.Text := '';
  Fill;
  Changed;
end;

function TAtlasStepFilterPatterns.RemoveSelected: Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if not FList.HandleAllocated or (FList.Selected = nil) then
  begin
    Exit;
  end;
  mIndex := FList.Selected.Index;
  if (mIndex < 0) or (mIndex > High(FPatterns)) then
  begin
    Exit;
  end;
  Delete(FPatterns, mIndex, 1);
  if mIndex <= High(FHits) then
  begin
    Delete(FHits, mIndex, 1);
  end;
  Fill;
  // Auswahl bleibt an derselben Stelle, damit Entf mehrfach hintereinander geht.
  if FList.Items.Count > 0 then
  begin
    if mIndex >= FList.Items.Count then
    begin
      mIndex := FList.Items.Count - 1;
    end;
    FList.Items[mIndex].Selected := True;
  end;
  Changed;
  Result := True;
end;

function TAtlasStepFilterPatterns.ReplacePattern(AIndex: Integer; const AText: string): Boolean;
var
  mText: string;
begin
  Result := TAtlasStepFilterEdit.CanReplacePattern(FPatterns, AIndex, AText);
  mText := Trim(AText);
  if not Result or (FPatterns[AIndex] = mText) then
  begin
    Exit;
  end;
  FPatterns[AIndex] := mText;
  // Die Treffer gelten für das alte Muster; die IDE-Schicht zählt nach dem Speichern neu.
  if AIndex <= High(FHits) then
  begin
    FHits[AIndex] := '';
  end;
  if FList.HandleAllocated and (AIndex < FList.Items.Count) and (FList.Items[AIndex].SubItems.Count > 0) then
  begin
    FList.Items[AIndex].SubItems[0] := '';
  end;
  Changed;
end;

end.
