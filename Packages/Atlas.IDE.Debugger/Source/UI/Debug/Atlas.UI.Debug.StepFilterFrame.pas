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

  /// <summary>Texte des Fensters „Schrittfilter“: Gründe, Arten und Muster mit Treffern, Zusammenfassung, Sitzung.
  /// </summary>
  TAtlasStepFilterTexts = class
  public
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
  end;

  TAtlasDebugStepFilterFrame = class(TFrame)
  private type
    /// <summary>Steuerelemente, die nach dem Aufbau noch gebraucht werden.</summary>
    TControls = record
      EnabledCheck: TCheckBox;
      Kinds: array[TStepFilterKind] of TCheckBox;
      PatternEdit: TEdit;
      Add: TButton;
      Remove: TButton;
      Patterns: TListView;
      Summary: TLabel;
      Session: TLabel;
    end;
    /// <summary>Gezeigter Stand: Schalter, Arten, Muster.</summary>
    TValue = record
      Enabled: Boolean;
      Kinds: TStepFilterKinds;
      Patterns: TArray<string>;
    end;
    /// <summary>Treffer im Index und ob sie schon gezählt sind.</summary>
    TCount = record
      State: TAtlasStepCountsState;
      Counts: TAtlasStepCounts;
    end;
    TEvents = record
      Change: TAtlasStepFilterChange;
      Refresh: TProc;
    end;
  private
    FControls: TControls;
    FValue: TValue;
    FCount: TCount;
    FFilling: Boolean;
    FEvents: TEvents;
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
    property EnabledCheck: TCheckBox read FControls.EnabledCheck;
    property PatternEdit: TEdit read FControls.PatternEdit;
    property Patterns: TListView read FControls.Patterns;
    property AddButtonControl: TButton read FControls.Add;
    property RemoveButtonControl: TButton read FControls.Remove;
    property Summary: TLabel read FControls.Summary;
    property Session: TLabel read FControls.Session;
    property CountsState: TAtlasStepCountsState read FCount.State;
    property OnChange: TAtlasStepFilterChange read FEvents.Change write FEvents.Change;
    property OnRefresh: TProc read FEvents.Refresh write FEvents.Refresh;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Strings,
  Atlas.UI.Debug.Strings;

{$R *.dfm}

const
  KindTexts: array[TStepFilterKind] of TAtlasTextId = (TAtlasTextId.StepFilterKindGetters,
    TAtlasTextId.StepFilterKindSetters, TAtlasTextId.StepFilterKindTrivial, TAtlasTextId.StepFilterKindOperators,
    TAtlasTextId.StepFilterKindEmptyConstructors);

/// <summary>Knopf rechts in AParent (Besitzer AFrame).</summary>
function AddButton(AFrame: TAtlasDebugStepFilterFrame; AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AFrame);
  Result.Parent := AParent;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := MulDiv(86, AFrame.CurrentPPI, 96);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

/// <summary>Umbrechende Beschriftung in AFrame, oben bzw. unten nach AAlign.</summary>
function AddLabel(AFrame: TAtlasDebugStepFilterFrame; AAlign: TAlign; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(AFrame);
  Result.Parent := AFrame;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
  Result.WordWrap := True;
  Result.Caption := ACaption;
end;

/// <summary>Leiste ohne Rand und Beschriftung in AParent, 30 logische Pixel hoch.</summary>
function AddBar(AFrame: TAtlasDebugStepFilterFrame; AParent: TWinControl): TPanel;
begin
  Result := TPanel.Create(AFrame);
  Result.Parent := AParent;
  Result.Align := alTop;
  Result.BevelOuter := bvNone;
  Result.ShowCaption := False;
  Result.ParentBackground := True;
  Result.Height := MulDiv(30, AFrame.CurrentPPI, 96);
end;

/// <summary>Leiste oben: Schalter debug.stepFilters und „Neu zählen“; Ergebnis: ihre Höhe.</summary>
function CreateTopBar(AFrame: TAtlasDebugStepFilterFrame): Integer;
var
  mTop: TPanel;
begin
  mTop := AddBar(AFrame, AFrame);
  AddButton(AFrame, mTop, TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterRefresh), AFrame.RefreshClick);
  AFrame.FControls.EnabledCheck := TCheckBox.Create(AFrame);
  AFrame.FControls.EnabledCheck.Parent := mTop;
  AFrame.FControls.EnabledCheck.Align := alClient;
  AFrame.FControls.EnabledCheck.AlignWithMargins := True;
  AFrame.FControls.EnabledCheck.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterEnabled);
  AFrame.FControls.EnabledCheck.OnClick := AFrame.EnabledClick;
  Result := mTop.Height;
end;

/// <summary>Kopf und Schalter der Arten ab ATop; mit alTop ordnet die VCL nach Top, deshalb steigend.</summary>
procedure CreateKinds(AFrame: TAtlasDebugStepFilterFrame; var ATop: Integer);
var
  mKind: TStepFilterKind;
  mHeader: TLabel;
  mCheck: TCheckBox;
begin
  mHeader := AddLabel(AFrame, alTop, TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterKindsHeader));
  mHeader.Font.Style := [fsBold];
  mHeader.Top := ATop;
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    mCheck := TCheckBox.Create(AFrame);
    mCheck.Parent := AFrame;
    mCheck.Align := alTop;
    mCheck.AlignWithMargins := True;
    Inc(ATop, 100);
    mCheck.Top := ATop;
    mCheck.Tag := Ord(mKind);
    mCheck.OnClick := AFrame.KindClick;
    AFrame.FControls.Kinds[mKind] := mCheck;
  end;
end;

/// <summary>Kopf der Muster und Eingabezeile mit „Hinzufügen“ und „Entfernen“ ab ATop.</summary>
procedure CreatePatternBar(AFrame: TAtlasDebugStepFilterFrame; ATop: Integer);
var
  mHeader: TLabel;
  mBar: TPanel;
begin
  mHeader := AddLabel(AFrame, alTop, TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterPatternsHeader));
  mHeader.Font.Style := [fsBold];
  mHeader.Top := ATop + 100;
  mBar := AddBar(AFrame, AFrame);
  mBar.Top := ATop + 200;
  AFrame.FControls.Remove := AddButton(AFrame, mBar, TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterRemove),
    AFrame.RemoveClick);
  AFrame.FControls.Add := AddButton(AFrame, mBar, TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterAdd),
    AFrame.AddClick);
  AFrame.FControls.PatternEdit := TEdit.Create(AFrame);
  AFrame.FControls.PatternEdit.Parent := mBar;
  AFrame.FControls.PatternEdit.Align := alClient;
  AFrame.FControls.PatternEdit.AlignWithMargins := True;
  AFrame.FControls.PatternEdit.TextHint := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterPatternHint);
  AFrame.FControls.PatternEdit.OnChange := AFrame.PatternEditChange;
  AFrame.FControls.PatternEdit.OnKeyDown := AFrame.PatternEditKeyDown;
end;

/// <summary>Von unten: Hinweis, Sitzung, Zusammenfassung (mit alBottom liegt das größere Top weiter unten).</summary>
procedure CreateBottomLabels(AFrame: TAtlasDebugStepFilterFrame);
var
  mHint: TLabel;
begin
  mHint := AddLabel(AFrame, alBottom, TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterShiftHint));
  mHint.Font.Color := clGrayText;
  mHint.Top := 30000;
  AFrame.FControls.Session := AddLabel(AFrame, alBottom, '');
  AFrame.FControls.Session.Top := 20000;
  AFrame.FControls.Summary := AddLabel(AFrame, alBottom, '');
  AFrame.FControls.Summary.Top := 10000;
end;

/// <summary>Liste der Muster mit Treffern; füllt den Rest von AFrame.</summary>
procedure CreatePatternList(AFrame: TAtlasDebugStepFilterFrame);
var
  mList: TListView;
  mColumn: TListColumn;
begin
  mList := TListView.Create(AFrame);
  AFrame.FControls.Patterns := mList;
  mList.Parent := AFrame;
  mList.Align := alClient;
  mList.AlignWithMargins := True;
  mList.ViewStyle := vsReport;
  mList.RowSelect := True;
  mList.HideSelection := False;
  mList.ReadOnly := False;
  mList.MultiSelect := False;
  mList.ColumnClick := False;
  mColumn := mList.Columns.Add;
  mColumn.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterColumnPattern);
  mColumn.Width := MulDiv(260, AFrame.CurrentPPI, 96);
  mColumn := mList.Columns.Add;
  mColumn.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterColumnHits);
  mColumn.Width := MulDiv(70, AFrame.CurrentPPI, 96);
  mColumn.Alignment := taRightJustify;
  mList.OnSelectItem := AFrame.PatternsSelectItem;
  mList.OnKeyDown := AFrame.PatternsKeyDown;
  mList.OnEdited := AFrame.PatternsEdited;
end;

{ TAtlasDebugStepFilterFrame }

constructor TAtlasDebugStepFilterFrame.Create(AOwner: TComponent);
var
  mTop: Integer;
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FValue.Kinds := TStepFilterNames.DefaultKinds;
  // Von oben: Kopf der Arten, die Arten, Kopf der Muster, Eingabezeile; die Liste füllt den Rest.
  mTop := CreateTopBar(Self);
  CreateKinds(Self, mTop);
  CreatePatternBar(Self, mTop);
  CreateBottomLabels(Self);
  CreatePatternList(Self);
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

procedure TAtlasDebugStepFilterFrame.SetOptions(AEnabled: Boolean; AKinds: TStepFilterKinds;
  const APatterns: TArray<string>);
var
  mKind: TStepFilterKind;
  mRebuild: Boolean;
begin
  mRebuild := TStepFilterNames.PatternsText(APatterns) <> TStepFilterNames.PatternsText(FValue.Patterns);
  FValue.Enabled := AEnabled;
  FValue.Kinds := AKinds;
  FValue.Patterns := Copy(APatterns);
  FFilling := True;
  try
    FControls.EnabledCheck.Checked := AEnabled;
    for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
    begin
      FControls.Kinds[mKind].Checked := mKind in AKinds;
    end;
  finally
    FFilling := False;
  end;
  if mRebuild then
  begin
    FillPatterns;
  end;
  UpdateButtons;
end;

procedure TAtlasDebugStepFilterFrame.FillPatterns;
var
  mIndex: Integer;
  mItem: TListItem;
begin
  // Die Liste braucht ein Fenster; hat der Rahmen schon eines, auch die Liste anlegen (sonst füllt CreateWnd).
  if not FControls.Patterns.HandleAllocated then
  begin
    if not HandleAllocated then
    begin
      Exit;
    end;
    FControls.Patterns.HandleNeeded;
  end;
  FControls.Patterns.Items.BeginUpdate;
  try
    FControls.Patterns.Items.Clear;
    for mIndex := 0 to High(FValue.Patterns) do
    begin
      mItem := FControls.Patterns.Items.Add;
      mItem.Caption := FValue.Patterns[mIndex];
      mItem.SubItems.Add(TAtlasStepFilterTexts.PatternHits(mIndex, FCount.State, FCount.Counts));
    end;
  finally
    FControls.Patterns.Items.EndUpdate;
  end;
  UpdateButtons;
end;

procedure TAtlasDebugStepFilterFrame.SetCounting;
begin
  FCount.State := TAtlasStepCountsState.Counting;
  UpdateCounts;
end;

procedure TAtlasDebugStepFilterFrame.SetCounts(const ACounts: TAtlasStepCounts);
begin
  FCount.Counts := ACounts;
  FCount.Counts.Patterns := Copy(ACounts.Patterns);
  FCount.State := TAtlasStepCountsState.Ready;
  UpdateCounts;
end;

procedure TAtlasDebugStepFilterFrame.SetNoCounts;
begin
  FCount.Counts := Default(TAtlasStepCounts);
  FCount.State := TAtlasStepCountsState.Unavailable;
  UpdateCounts;
end;

procedure TAtlasDebugStepFilterFrame.UpdateCounts;
var
  mKind: TStepFilterKind;
  mIndex: Integer;
begin
  for mKind := Low(TStepFilterKind) to High(TStepFilterKind) do
  begin
    FControls.Kinds[mKind].Caption := TAtlasStepFilterTexts.KindCaption(mKind, FCount.State, FCount.Counts);
  end;
  FControls.Summary.Caption := TAtlasStepFilterTexts.SummaryText(FCount.State, FCount.Counts);
  if not FControls.Patterns.HandleAllocated then
  begin
    Exit;
  end;
  for mIndex := 0 to FControls.Patterns.Items.Count - 1 do
  begin
    if FControls.Patterns.Items[mIndex].SubItems.Count > 0 then
    begin
      FControls.Patterns.Items[mIndex].SubItems[0] := TAtlasStepFilterTexts.PatternHits(mIndex, FCount.State,
        FCount.Counts);
    end;
  end;
end;

procedure TAtlasDebugStepFilterFrame.SetSession(AStarted: Boolean; ASkipped: Integer;
  const ALastName, ALastReason: string);
begin
  FControls.Session.Caption := TAtlasStepFilterTexts.SessionText(AStarted, ASkipped, ALastName, ALastReason);
end;

procedure TAtlasDebugStepFilterFrame.UpdateButtons;
var
  mText: string;
begin
  mText := Trim(FControls.PatternEdit.Text);
  FControls.Add.Enabled := TStepFilterNames.IsValidPattern(mText) and
    (TStepFilterNames.IndexOfPattern(FValue.Patterns, mText) < 0) and
    (Length(FValue.Patterns) < TStepFilterNames.MaxPatterns);
  FControls.Remove.Enabled := FControls.Patterns.HandleAllocated and (FControls.Patterns.Selected <> nil);
end;

procedure TAtlasDebugStepFilterFrame.NotifyChange;
begin
  UpdateButtons;
  if Assigned(FEvents.Change) then
  begin
    FEvents.Change(FValue.Enabled, FValue.Kinds, Copy(FValue.Patterns));
  end;
end;

procedure TAtlasDebugStepFilterFrame.EnabledClick(Sender: TObject);
begin
  if FFilling then
  begin
    Exit;
  end;
  FValue.Enabled := FControls.EnabledCheck.Checked;
  NotifyChange;
end;

procedure TAtlasDebugStepFilterFrame.KindClick(Sender: TObject);
var
  mKind: TStepFilterKind;
begin
  if FFilling then
  begin
    Exit;
  end;
  mKind := TStepFilterKind((Sender as TCheckBox).Tag);
  if FControls.Kinds[mKind].Checked then
  begin
    Include(FValue.Kinds, mKind);
  end
  else
  begin
    Exclude(FValue.Kinds, mKind);
  end;
  NotifyChange;
end;

procedure TAtlasDebugStepFilterFrame.RefreshClick(Sender: TObject);
begin
  if Assigned(FEvents.Refresh) then
  begin
    FEvents.Refresh();
  end;
end;

function TAtlasDebugStepFilterFrame.AddPattern: Boolean;
var
  mText: string;
begin
  mText := Trim(FControls.PatternEdit.Text);
  Result := TStepFilterNames.IsValidPattern(mText) and (TStepFilterNames.IndexOfPattern(FValue.Patterns, mText) < 0)
    and (Length(FValue.Patterns) < TStepFilterNames.MaxPatterns);
  if not Result then
  begin
    Exit;
  end;
  FValue.Patterns := TStepFilterNames.WithPattern(FValue.Patterns, mText);
  FControls.PatternEdit.Text := '';
  FillPatterns;
  NotifyChange;
end;

function TAtlasDebugStepFilterFrame.RemoveSelected: Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if not FControls.Patterns.HandleAllocated or (FControls.Patterns.Selected = nil) then
  begin
    Exit;
  end;
  mIndex := FControls.Patterns.Selected.Index;
  if (mIndex < 0) or (mIndex > High(FValue.Patterns)) then
  begin
    Exit;
  end;
  Delete(FValue.Patterns, mIndex, 1);
  FillPatterns;
  // Auswahl bleibt an derselben Stelle, damit Entf mehrfach hintereinander geht.
  if FControls.Patterns.Items.Count > 0 then
  begin
    if mIndex >= FControls.Patterns.Items.Count then
    begin
      mIndex := FControls.Patterns.Items.Count - 1;
    end;
    FControls.Patterns.Items[mIndex].Selected := True;
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
  if (AIndex < 0) or (AIndex > High(FValue.Patterns)) then
  begin
    Exit;
  end;
  mText := Trim(AText);
  if not TStepFilterNames.IsValidPattern(mText) then
  begin
    Exit;
  end;
  mOther := TStepFilterNames.IndexOfPattern(FValue.Patterns, mText);
  if (mOther >= 0) and (mOther <> AIndex) then
  begin
    Exit;
  end;
  Result := True;
  if FValue.Patterns[AIndex] = mText then
  begin
    Exit;
  end;
  FValue.Patterns[AIndex] := mText;
  // Die Treffer gelten für das alte Muster; die IDE-Schicht zählt nach dem Speichern neu.
  if FControls.Patterns.HandleAllocated and (AIndex < FControls.Patterns.Items.Count) and
    (FControls.Patterns.Items[AIndex].SubItems.Count > 0) then
  begin
    FControls.Patterns.Items[AIndex].SubItems[0] := '';
  end;
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
  if FControls.Patterns.IsEditing then
  begin
    Exit;
  end;
  if (Key = VK_DELETE) and (Shift = []) then
  begin
    RemoveSelected;
    Key := 0;
  end
  else if (Key = VK_F2) and (Shift = []) and (FControls.Patterns.Selected <> nil) then
  begin
    FControls.Patterns.Selected.EditCaption;
    Key := 0;
  end;
end;

procedure TAtlasDebugStepFilterFrame.PatternsEdited(Sender: TObject; Item: TListItem; var S: string);
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

{ TAtlasStepFilterTexts }

class function TAtlasStepFilterTexts.VerdictText(const AVerdict: TAtlasStepVerdict): string;
begin
  case AVerdict.Kind of
    TAtlasStepVerdictKind.Kind:
      Result := TAtlasStrings.Text(KindTexts[AVerdict.FilterKind]);
    TAtlasStepVerdictKind.Pattern:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepFilterByPattern, [AVerdict.Pattern]);
  else
    Result := '';
  end;
end;

class function TAtlasStepFilterTexts.KindCaption(AKind: TStepFilterKind; AState: TAtlasStepCountsState;
  const ACounts: TAtlasStepCounts): string;
begin
  Result := TAtlasStrings.Text(KindTexts[AKind]);
  if AState = TAtlasStepCountsState.Ready then
  begin
    Result := Result + ' – ' + IntToStr(ACounts.Kinds[AKind]);
  end;
end;

class function TAtlasStepFilterTexts.PatternHits(AIndex: Integer; AState: TAtlasStepCountsState;
  const ACounts: TAtlasStepCounts): string;
begin
  Result := '';
  if (AState = TAtlasStepCountsState.Ready) and (AIndex >= 0) and (AIndex <= High(ACounts.Patterns)) then
  begin
    Result := IntToStr(ACounts.Patterns[AIndex]);
  end;
end;

class function TAtlasStepFilterTexts.SummaryText(AState: TAtlasStepCountsState;
  const ACounts: TAtlasStepCounts): string;
begin
  case AState of
    TAtlasStepCountsState.Counting:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterCounting);
    TAtlasStepCountsState.Ready:
      begin
        Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepFilterSummary, [ACounts.Routines, ACounts.Files]);
        if ACounts.Truncated then
        begin
          Result := Result + TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepFilterTruncated, [ACounts.Files]);
        end;
      end;
    TAtlasStepCountsState.Unavailable:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterNoCounts);
  else
    Result := '';
  end;
end;

class function TAtlasStepFilterTexts.SessionText(AStarted: Boolean; ASkipped: Integer;
  const ALastName, ALastReason: string): string;
begin
  if not AStarted then
  begin
    Exit(TAtlasDebugStrings.Text(TAtlasDebugTextId.StepFilterInactive));
  end;
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepFilterSession, [ASkipped]);
  if ALastName <> '' then
  begin
    Result := Result + TAtlasDebugStrings.Fmt(TAtlasDebugTextId.StepFilterLast, [ALastName, ALastReason]);
  end;
end;

end.
