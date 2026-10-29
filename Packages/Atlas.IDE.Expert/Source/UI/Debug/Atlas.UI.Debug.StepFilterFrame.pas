unit Atlas.UI.Debug.StepFilterFrame;

// Inhalt des Fensters „Schrittfilter“ (#850): Schalter debug.stepFilters, die
// Arten mit ihren Treffern im Index, die Muster (bearbeiten mit F2 oder
// Doppelklick, hinzufügen, entfernen) mit Treffern und unten, was Atlas in
// dieser Debug-Sitzung übersprungen hat. Jede Änderung meldet OnChange mit dem
// ganzen Stand; die IDE-Schicht speichert ihn und ruft SetOptions mit dem
// gespeicherten Stand zurück. Treffer zählt die IDE-Schicht im Hintergrund
// (SetCounting, SetCounts, SetNoCounts).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Text.StepFilter,
  Atlas.Core.Debug.StepFilter;

type
  {$SCOPEDENUMS ON}
  TAtlasStepCountsState = (None, Counting, Ready, Unavailable);
  {$SCOPEDENUMS OFF}

  TAtlasStepFilterChange = reference to procedure(AEnabled: Boolean; AKinds: TStepFilterKinds;
    const APatterns: TArray<string>);

  TAtlasDebugStepFilterFrame = class(TFrame)
  private
    FTop: TPanel;
    FEnabledCheck: TCheckBox;
    FRefresh: TButton;
    FKindsHeader: TLabel;
    FKinds: array[TStepFilterKind] of TCheckBox;
    FPatternsHeader: TLabel;
    FPatternBar: TPanel;
    FPatternEdit: TEdit;
    FAdd: TButton;
    FRemove: TButton;
    FPatterns: TListView;
    FSummary: TLabel;
    FSession: TLabel;
    FShiftHint: TLabel;
    FEnabledValue: Boolean;
    FKindsValue: TStepFilterKinds;
    FPatternsValue: TArray<string>;
    FCountsState: TAtlasStepCountsState;
    FCounts: TAtlasStepCounts;
    FFilling: Boolean;
    FOnChange: TAtlasStepFilterChange;
    FOnRefresh: TProc;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    function AddLabel(AAlign: TAlign; const ACaption: string): TLabel;
    procedure FillPatterns;
    procedure UpdateCounts;
    procedure UpdateButtons;
    procedure NotifyChange;
    procedure EnabledClick(Sender: TObject);
    procedure KindClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure PatternEditChange(Sender: TObject);
    procedure PatternEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PatternsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure PatternsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PatternsEdited(Sender: TObject; Item: TListItem; var S: string);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Gespeicherter Stand; meldet nichts über OnChange. Die Liste baut sich nur neu, wenn sich die Muster
    /// geändert haben (sonst stört es ein laufendes Bearbeiten).</summary>
    procedure SetOptions(AEnabled: Boolean; AKinds: TStepFilterKinds; const APatterns: TArray<string>);
    procedure SetCounting;
    /// <summary>Treffer für die Muster in der Reihenfolge, die beim Zählen galt.</summary>
    procedure SetCounts(const ACounts: TAtlasStepCounts);
    procedure SetNoCounts;
    procedure SetSession(AStarted: Boolean; ASkipped: Integer; const ALastName, ALastReason: string);
    /// <summary>Muster aus dem Eingabefeld anfügen; False, wenn es ungültig ist oder schon darin steht.</summary>
    function AddPattern: Boolean;
    /// <summary>Gewähltes Muster entfernen; False ohne Auswahl.</summary>
    function RemoveSelected: Boolean;
    /// <summary>Muster AIndex durch AText ersetzen; False, wenn AText ungültig ist oder schon darin steht.</summary>
    function ReplacePattern(AIndex: Integer; const AText: string): Boolean;
    /// <summary>Grund eines Urteils: Beschreibung der Art bzw. „Muster X“.</summary>
    class function VerdictText(const AVerdict: TAtlasStepVerdict): string; static;
    /// <summary>Beschriftung einer Art, mit Treffern, sobald sie gezählt sind.</summary>
    class function KindCaption(AKind: TStepFilterKind; AState: TAtlasStepCountsState;
      const ACounts: TAtlasStepCounts): string; static;
    /// <summary>Treffer eines Musters ('' solange nicht gezählt).</summary>
    class function PatternHits(AIndex: Integer; AState: TAtlasStepCountsState;
      const ACounts: TAtlasStepCounts): string; static;
    class function SummaryText(AState: TAtlasStepCountsState; const ACounts: TAtlasStepCounts): string; static;
    class function SessionText(AStarted: Boolean; ASkipped: Integer; const ALastName, ALastReason: string): string;
      static;
    property EnabledCheck: TCheckBox read FEnabledCheck;
    property PatternEdit: TEdit read FPatternEdit;
    property Patterns: TListView read FPatterns;
    property AddButtonControl: TButton read FAdd;
    property RemoveButtonControl: TButton read FRemove;
    property Summary: TLabel read FSummary;
    property Session: TLabel read FSession;
    property CountsState: TAtlasStepCountsState read FCountsState;
    property OnChange: TAtlasStepFilterChange read FOnChange write FOnChange;
    property OnRefresh: TProc read FOnRefresh write FOnRefresh;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Strings;

{$R *.dfm}

const
  KindTexts: array[TStepFilterKind] of TAtlasTextId = (TAtlasTextId.StepFilterKindGetters,
    TAtlasTextId.StepFilterKindSetters, TAtlasTextId.StepFilterKindTrivial, TAtlasTextId.StepFilterKindOperators,
    TAtlasTextId.StepFilterKindEmptyConstructors);

{ TAtlasDebugStepFilterFrame }

constructor TAtlasDebugStepFilterFrame.Create(AOwner: TComponent);
var
  mKind: TStepFilterKind;
  mColumn: TListColumn;
  mTop: Integer;
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FKindsValue := TStepFilterNames.DefaultKinds;

  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.BevelOuter := bvNone;
  FTop.ShowCaption := False;
  FTop.ParentBackground := True;
  FTop.Height := MulDiv(30, CurrentPPI, 96);

  FRefresh := AddButton(FTop, TAtlasStrings.Text(TAtlasTextId.StepFilterRefresh), RefreshClick);

  FEnabledCheck := TCheckBox.Create(Self);
  FEnabledCheck.Parent := FTop;
  FEnabledCheck.Align := alClient;
  FEnabledCheck.AlignWithMargins := True;
  FEnabledCheck.Caption := TAtlasStrings.Text(TAtlasTextId.StepFilterEnabled);
  FEnabledCheck.OnClick := EnabledClick;

  // Von oben: Kopf der Arten, die Arten, Kopf der Muster, Eingabezeile; die Liste füllt den Rest. Mit alTop
  // ordnet die VCL nach Top, deshalb steigend.
  mTop := FTop.Height;
  FKindsHeader := AddLabel(alTop, TAtlasStrings.Text(TAtlasTextId.StepFilterKindsHeader));
  FKindsHeader.Font.Style := [fsBold];
  FKindsHeader.Top := mTop;
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    FKinds[mKind] := TCheckBox.Create(Self);
    FKinds[mKind].Parent := Self;
    FKinds[mKind].Align := alTop;
    FKinds[mKind].AlignWithMargins := True;
    Inc(mTop, 100);
    FKinds[mKind].Top := mTop;
    FKinds[mKind].Tag := Ord(mKind);
    FKinds[mKind].OnClick := KindClick;
  end;
  FPatternsHeader := AddLabel(alTop, TAtlasStrings.Text(TAtlasTextId.StepFilterPatternsHeader));
  FPatternsHeader.Font.Style := [fsBold];
  Inc(mTop, 100);
  FPatternsHeader.Top := mTop;

  FPatternBar := TPanel.Create(Self);
  FPatternBar.Parent := Self;
  FPatternBar.Align := alTop;
  Inc(mTop, 100);
  FPatternBar.Top := mTop;
  FPatternBar.BevelOuter := bvNone;
  FPatternBar.ShowCaption := False;
  FPatternBar.ParentBackground := True;
  FPatternBar.Height := MulDiv(30, CurrentPPI, 96);
  FRemove := AddButton(FPatternBar, TAtlasStrings.Text(TAtlasTextId.StepFilterRemove), RemoveClick);
  FAdd := AddButton(FPatternBar, TAtlasStrings.Text(TAtlasTextId.StepFilterAdd), AddClick);
  FPatternEdit := TEdit.Create(Self);
  FPatternEdit.Parent := FPatternBar;
  FPatternEdit.Align := alClient;
  FPatternEdit.AlignWithMargins := True;
  FPatternEdit.TextHint := TAtlasStrings.Text(TAtlasTextId.StepFilterPatternHint);
  FPatternEdit.OnChange := PatternEditChange;
  FPatternEdit.OnKeyDown := PatternEditKeyDown;

  // Von unten: Hinweis, Sitzung, Zusammenfassung (mit alBottom liegt das größere Top weiter unten).
  FShiftHint := AddLabel(alBottom, TAtlasStrings.Text(TAtlasTextId.StepFilterShiftHint));
  FShiftHint.Font.Color := clGrayText;
  FShiftHint.Top := 30000;
  FSession := AddLabel(alBottom, '');
  FSession.Top := 20000;
  FSummary := AddLabel(alBottom, '');
  FSummary.Top := 10000;

  FPatterns := TListView.Create(Self);
  FPatterns.Parent := Self;
  FPatterns.Align := alClient;
  FPatterns.AlignWithMargins := True;
  FPatterns.ViewStyle := vsReport;
  FPatterns.RowSelect := True;
  FPatterns.HideSelection := False;
  FPatterns.ReadOnly := False;
  FPatterns.MultiSelect := False;
  FPatterns.ColumnClick := False;
  mColumn := FPatterns.Columns.Add;
  mColumn.Caption := TAtlasStrings.Text(TAtlasTextId.StepFilterColumnPattern);
  mColumn.Width := MulDiv(260, CurrentPPI, 96);
  mColumn := FPatterns.Columns.Add;
  mColumn.Caption := TAtlasStrings.Text(TAtlasTextId.StepFilterColumnHits);
  mColumn.Width := MulDiv(70, CurrentPPI, 96);
  mColumn.Alignment := taRightJustify;
  FPatterns.OnSelectItem := PatternsSelectItem;
  FPatterns.OnKeyDown := PatternsKeyDown;
  FPatterns.OnEdited := PatternsEdited;

  SetOptions(False, TStepFilterNames.DefaultKinds, nil);
  SetSession(False, 0, '', '');
  UpdateCounts;
end;

procedure TAtlasDebugStepFilterFrame.CreateWnd;
begin
  inherited CreateWnd;
  // TListView.Items braucht ein Fenster.
  FillPatterns;
end;

function TAtlasDebugStepFilterFrame.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := MulDiv(86, CurrentPPI, 96);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

function TAtlasDebugStepFilterFrame.AddLabel(AAlign: TAlign; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
  Result.WordWrap := True;
  Result.Caption := ACaption;
end;

procedure TAtlasDebugStepFilterFrame.SetOptions(AEnabled: Boolean; AKinds: TStepFilterKinds;
  const APatterns: TArray<string>);
var
  mKind: TStepFilterKind;
  mRebuild: Boolean;
begin
  mRebuild := TStepFilterNames.PatternsText(APatterns) <> TStepFilterNames.PatternsText(FPatternsValue);
  FEnabledValue := AEnabled;
  FKindsValue := AKinds;
  FPatternsValue := Copy(APatterns);
  FFilling := True;
  try
    FEnabledCheck.Checked := AEnabled;
    for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
      FKinds[mKind].Checked := mKind in AKinds;
  finally
    FFilling := False;
  end;
  if mRebuild then
    FillPatterns;
  UpdateButtons;
end;

procedure TAtlasDebugStepFilterFrame.FillPatterns;
var
  mIndex: Integer;
  mItem: TListItem;
begin
  // Die Liste braucht ein Fenster; hat der Rahmen schon eines, auch die Liste anlegen (sonst füllt CreateWnd).
  if not FPatterns.HandleAllocated then
  begin
    if not HandleAllocated then
      Exit;
    FPatterns.HandleNeeded;
  end;
  FPatterns.Items.BeginUpdate;
  try
    FPatterns.Items.Clear;
    for mIndex := 0 to High(FPatternsValue) do
    begin
      mItem := FPatterns.Items.Add;
      mItem.Caption := FPatternsValue[mIndex];
      mItem.SubItems.Add(PatternHits(mIndex, FCountsState, FCounts));
    end;
  finally
    FPatterns.Items.EndUpdate;
  end;
  UpdateButtons;
end;

procedure TAtlasDebugStepFilterFrame.SetCounting;
begin
  FCountsState := TAtlasStepCountsState.Counting;
  UpdateCounts;
end;

procedure TAtlasDebugStepFilterFrame.SetCounts(const ACounts: TAtlasStepCounts);
begin
  FCounts := ACounts;
  FCounts.Patterns := Copy(ACounts.Patterns);
  FCountsState := TAtlasStepCountsState.Ready;
  UpdateCounts;
end;

procedure TAtlasDebugStepFilterFrame.SetNoCounts;
begin
  FCounts := Default(TAtlasStepCounts);
  FCountsState := TAtlasStepCountsState.Unavailable;
  UpdateCounts;
end;

procedure TAtlasDebugStepFilterFrame.UpdateCounts;
var
  mKind: TStepFilterKind;
  mIndex: Integer;
begin
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
    FKinds[mKind].Caption := KindCaption(mKind, FCountsState, FCounts);
  FSummary.Caption := SummaryText(FCountsState, FCounts);
  if not FPatterns.HandleAllocated then
    Exit;
  for mIndex := 0 to FPatterns.Items.Count - 1 do
    if FPatterns.Items[mIndex].SubItems.Count > 0 then
      FPatterns.Items[mIndex].SubItems[0] := PatternHits(mIndex, FCountsState, FCounts);
end;

procedure TAtlasDebugStepFilterFrame.SetSession(AStarted: Boolean; ASkipped: Integer;
  const ALastName, ALastReason: string);
begin
  FSession.Caption := SessionText(AStarted, ASkipped, ALastName, ALastReason);
end;

procedure TAtlasDebugStepFilterFrame.UpdateButtons;
var
  mText: string;
begin
  mText := Trim(FPatternEdit.Text);
  FAdd.Enabled := TStepFilterNames.IsValidPattern(mText) and
    (TStepFilterNames.IndexOfPattern(FPatternsValue, mText) < 0) and
    (Length(FPatternsValue) < TStepFilterNames.MaxPatterns);
  FRemove.Enabled := FPatterns.HandleAllocated and (FPatterns.Selected <> nil);
end;

procedure TAtlasDebugStepFilterFrame.NotifyChange;
begin
  UpdateButtons;
  if Assigned(FOnChange) then
    FOnChange(FEnabledValue, FKindsValue, Copy(FPatternsValue));
end;

procedure TAtlasDebugStepFilterFrame.EnabledClick(Sender: TObject);
begin
  if FFilling then
    Exit;
  FEnabledValue := FEnabledCheck.Checked;
  NotifyChange;
end;

procedure TAtlasDebugStepFilterFrame.KindClick(Sender: TObject);
var
  mKind: TStepFilterKind;
begin
  if FFilling then
    Exit;
  mKind := TStepFilterKind((Sender as TCheckBox).Tag);
  if FKinds[mKind].Checked then
    Include(FKindsValue, mKind)
  else
    Exclude(FKindsValue, mKind);
  NotifyChange;
end;

procedure TAtlasDebugStepFilterFrame.RefreshClick(Sender: TObject);
begin
  if Assigned(FOnRefresh) then
    FOnRefresh();
end;

function TAtlasDebugStepFilterFrame.AddPattern: Boolean;
var
  mText: string;
begin
  mText := Trim(FPatternEdit.Text);
  Result := TStepFilterNames.IsValidPattern(mText) and (TStepFilterNames.IndexOfPattern(FPatternsValue, mText) < 0)
    and (Length(FPatternsValue) < TStepFilterNames.MaxPatterns);
  if not Result then
    Exit;
  FPatternsValue := TStepFilterNames.WithPattern(FPatternsValue, mText);
  FPatternEdit.Text := '';
  FillPatterns;
  NotifyChange;
end;

function TAtlasDebugStepFilterFrame.RemoveSelected: Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if not FPatterns.HandleAllocated or (FPatterns.Selected = nil) then
    Exit;
  mIndex := FPatterns.Selected.Index;
  if (mIndex < 0) or (mIndex > High(FPatternsValue)) then
    Exit;
  Delete(FPatternsValue, mIndex, 1);
  FillPatterns;
  // Auswahl bleibt an derselben Stelle, damit Entf mehrfach hintereinander geht.
  if FPatterns.Items.Count > 0 then
  begin
    if mIndex >= FPatterns.Items.Count then
      mIndex := FPatterns.Items.Count - 1;
    FPatterns.Items[mIndex].Selected := True;
  end;
  NotifyChange;
  Result := True;
end;

function TAtlasDebugStepFilterFrame.ReplacePattern(AIndex: Integer; const AText: string): Boolean;
var
  mText: string;
  mOther: Integer;
begin
  Result := False;
  if (AIndex < 0) or (AIndex > High(FPatternsValue)) then
    Exit;
  mText := Trim(AText);
  if not TStepFilterNames.IsValidPattern(mText) then
    Exit;
  mOther := TStepFilterNames.IndexOfPattern(FPatternsValue, mText);
  if (mOther >= 0) and (mOther <> AIndex) then
    Exit;
  Result := True;
  if FPatternsValue[AIndex] = mText then
    Exit;
  FPatternsValue[AIndex] := mText;
  // Die Treffer gelten für das alte Muster; die IDE-Schicht zählt nach dem Speichern neu.
  if FPatterns.HandleAllocated and (AIndex < FPatterns.Items.Count) and
    (FPatterns.Items[AIndex].SubItems.Count > 0) then
    FPatterns.Items[AIndex].SubItems[0] := '';
  NotifyChange;
end;

procedure TAtlasDebugStepFilterFrame.AddClick(Sender: TObject);
begin
  AddPattern;
end;

procedure TAtlasDebugStepFilterFrame.RemoveClick(Sender: TObject);
begin
  RemoveSelected;
end;

procedure TAtlasDebugStepFilterFrame.PatternEditChange(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TAtlasDebugStepFilterFrame.PatternEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    AddPattern;
    Key := 0;
  end;
end;

procedure TAtlasDebugStepFilterFrame.PatternsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
end;

procedure TAtlasDebugStepFilterFrame.PatternsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FPatterns.IsEditing then
    Exit;
  if (Key = VK_DELETE) and (Shift = []) then
  begin
    RemoveSelected;
    Key := 0;
  end
  else if (Key = VK_F2) and (Shift = []) and (FPatterns.Selected <> nil) then
  begin
    FPatterns.Selected.EditCaption;
    Key := 0;
  end;
end;

procedure TAtlasDebugStepFilterFrame.PatternsEdited(Sender: TObject; Item: TListItem; var S: string);
begin
  // Ungültig oder doppelt: Das alte Muster bleibt stehen.
  if ReplacePattern(Item.Index, S) then
    S := Trim(S)
  else
    S := Item.Caption;
end;

class function TAtlasDebugStepFilterFrame.VerdictText(const AVerdict: TAtlasStepVerdict): string;
begin
  case AVerdict.Kind of
    TAtlasStepVerdictKind.Kind:
      Result := TAtlasStrings.Text(KindTexts[AVerdict.FilterKind]);
    TAtlasStepVerdictKind.Pattern:
      Result := TAtlasStrings.Fmt(TAtlasTextId.StepFilterByPattern, [AVerdict.Pattern]);
  else
    Result := '';
  end;
end;

class function TAtlasDebugStepFilterFrame.KindCaption(AKind: TStepFilterKind; AState: TAtlasStepCountsState;
  const ACounts: TAtlasStepCounts): string;
begin
  Result := TAtlasStrings.Text(KindTexts[AKind]);
  if AState = TAtlasStepCountsState.Ready then
    Result := Result + ' – ' + IntToStr(ACounts.Kinds[AKind]);
end;

class function TAtlasDebugStepFilterFrame.PatternHits(AIndex: Integer; AState: TAtlasStepCountsState;
  const ACounts: TAtlasStepCounts): string;
begin
  Result := '';
  if (AState = TAtlasStepCountsState.Ready) and (AIndex >= 0) and (AIndex <= High(ACounts.Patterns)) then
    Result := IntToStr(ACounts.Patterns[AIndex]);
end;

class function TAtlasDebugStepFilterFrame.SummaryText(AState: TAtlasStepCountsState;
  const ACounts: TAtlasStepCounts): string;
begin
  case AState of
    TAtlasStepCountsState.Counting:
      Result := TAtlasStrings.Text(TAtlasTextId.StepFilterCounting);
    TAtlasStepCountsState.Ready:
      begin
        Result := TAtlasStrings.Fmt(TAtlasTextId.StepFilterSummary, [ACounts.Routines, ACounts.Files]);
        if ACounts.Truncated then
          Result := Result + TAtlasStrings.Fmt(TAtlasTextId.StepFilterTruncated, [ACounts.Files]);
      end;
    TAtlasStepCountsState.Unavailable:
      Result := TAtlasStrings.Text(TAtlasTextId.StepFilterNoCounts);
  else
    Result := '';
  end;
end;

class function TAtlasDebugStepFilterFrame.SessionText(AStarted: Boolean; ASkipped: Integer;
  const ALastName, ALastReason: string): string;
begin
  if not AStarted then
    Exit(TAtlasStrings.Text(TAtlasTextId.StepFilterInactive));
  Result := TAtlasStrings.Fmt(TAtlasTextId.StepFilterSession, [ASkipped]);
  if ALastName <> '' then
    Result := Result + TAtlasStrings.Fmt(TAtlasTextId.StepFilterLast, [ALastName, ALastReason]);
end;

end.
