unit Atlas.UI.Debug.MethodBreakpoints;

// Haltepunkte auf Methoden nach Name oder Muster (#855), Fensterteil (nur VCL):
//   Haltepunkt auf Methoden
//   Muster:    [*.Validiere*                                   ] [Suchen]
//              z. B. TKunde.Speichere, TKunde.*, *.Validiere*, Unit.*, IAuftrag.Pruefe
//   [x] Überschreibungen  [x] Überladungen
//   [ ] Mitwachsen: neue Methoden beim Debug-Start ergänzen
//   Bedingung: [                                                        ]
//   [ ] Nicht anhalten, nur protokollieren
//   ┌──────────────────────────────────────────────────────────────────┐
//   │ [x] Kunden.pas:42  TKunde.Validiere                              │
//   │ [x] Kunden.pas:57  TSpezial.Validiere  ·  überschreibt TKunde.…  │
//   │ [ ] Basis.pas      TListe.Validiere  ·  ohne Quelltext (grau)    │
//   └──────────────────────────────────────────────────────────────────┘
//   12 Treffer, 11 gewählt
//                                                  [Setzen (11)] [Abbrechen]
// Suchen (auch Eingabetaste und Umschalten der beiden Schalter) fragt über ASearch den Server. Treffer ohne
// Quelltext sind grau und nicht wählbar. Zeilen zeigt der Dialog ab 1 wie der Editor.
//
// TAtlasMethodGroupsDialog listet die Gruppen des Projekts mit Zahl der Haltepunkte und Aktiven; Ein-/Ausschalten
// und Entfernen rufen die Aktionen der IDE-Seite und lesen die Liste danach neu.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.CheckLst,
  Atlas.Core.Debug.MethodBreakpoints,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Server fragen; False ohne Server oder bei Fehler (AError).</summary>
  TAtlasMethodSearch = reference to function(const AQuery: TAtlasMethodQuery; out AAnswer: TAtlasMethodAnswer;
    out AError: string): Boolean;

  /// <summary>Texte des Dialogs zu Treffern.</summary>
  TAtlasMethodBreakpointTexts = record
    /// <summary>Zeile der Liste: „Kunden.pas:42  TKunde.Validiere  ·  überschreibt TBasis.Validiere“.</summary>
    class function HitText(const AHit: TAtlasMethodHit): string; static;
    /// <summary>Fußzeile: Zahl der Treffer und der gewählten.</summary>
    class function FooterText(const AAnswer: TAtlasMethodAnswer; ASelected: Integer): string; static;
  end;

  TAtlasMethodBreakpointsDialog = class(TAtlasDialog)
  private
    FSearch: TAtlasMethodSearch;
    FInitial: TAtlasMethodGroup;
    FPattern: TEdit;
    FOverrides: TCheckBox;
    FOverloads: TCheckBox;
    FGrow: TCheckBox;
    FCondition: TEdit;
    FLogOnly: TCheckBox;
    FList: TCheckListBox;
    FNote: TAtlasNoteLabel;
    FSet: TButton;
    FAnswer: TAtlasMethodAnswer;
    FSearched: Boolean;
    FChosen: Boolean;
    /// <summary>Haken in AParent an ALeft (logische Pixel, 96 dpi).</summary>
    function AddCheck(AParent: TWinControl; const ACaption: string; ALeft: Integer; AChecked: Boolean): TCheckBox;
    function AddLabeledEdit(const ACaption: string; AHeight96: Integer): TEdit;
    procedure CreatePatternRows;
    procedure CreateOptionRows;
    procedure CreateList;
    procedure CreateButtons;
    procedure UpdateFooter;
    procedure FindClick(Sender: TObject);
    procedure SwitchClick(Sender: TObject);
    procedure ListClickCheck(Sender: TObject);
    procedure SetClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    /// <summary>AGroup gibt Muster und Schalter vor (beim ersten Aufruf das Wort am Cursor).</summary>
    constructor CreateDialog(AOwner: TComponent; const AGroup: TAtlasMethodGroup; const ASearch: TAtlasMethodSearch);
    /// <summary>Server fragen und die Liste neu füllen; braucht ein Fenster.</summary>
    procedure RunSearch;
    /// <summary>Muster, Schalter, Bedingung und alle gesehenen Treffer als Gruppe.</summary>
    function Group: TAtlasMethodGroup;
    /// <summary>Angehakte Treffer mit Quelltext.</summary>
    function Selected: TAtlasMethodHits;
    /// <summary>Zeigt den Dialog modal; True mit „Setzen“. AGroup kommt mit dem Stand des Dialogs zurück.
    /// </summary>
    class function Execute(var AGroup: TAtlasMethodGroup; const ASearch: TAtlasMethodSearch;
      out ASelected: TAtlasMethodHits): Boolean; static;
    property PatternEdit: TEdit read FPattern;
    property OverridesBox: TCheckBox read FOverrides;
    property OverloadsBox: TCheckBox read FOverloads;
    property GrowBox: TCheckBox read FGrow;
    property ConditionEdit: TEdit read FCondition;
    property LogOnlyBox: TCheckBox read FLogOnly;
    property HitList: TCheckListBox read FList;
    property Note: TAtlasNoteLabel read FNote;
    property SetButton: TButton read FSet;
  end;

  /// <summary>Stand einer Gruppe in der IDE für die Liste.</summary>
  TAtlasMethodGroupState = record
    Group: TAtlasMethodGroup;
    Breakpoints: Integer;
    Enabled: Integer;
  end;

  TAtlasMethodGroupStates = TArray<TAtlasMethodGroupState>;
  TAtlasMethodGroupStatesFunc = reference to function: TAtlasMethodGroupStates;
  TAtlasMethodGroupAction = reference to procedure(const AGroup: TAtlasMethodGroup);

  TAtlasMethodGroupsDialog = class(TAtlasDialog)
  private
    FStates: TAtlasMethodGroupStatesFunc;
    FToggle: TAtlasMethodGroupAction;
    FRemove: TAtlasMethodGroupAction;
    FItems: TAtlasMethodGroupStates;
    FList: TListBox;
    FToggleButton: TButton;
    FRemoveButton: TButton;
    procedure CreateList;
    procedure CreateButtons;
    procedure Act(const AAction: TAtlasMethodGroupAction);
    procedure ToggleClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const AStates: TAtlasMethodGroupStatesFunc;
      const AToggle, ARemove: TAtlasMethodGroupAction);
    /// <summary>Liste neu füllen (nach jeder Aktion); braucht ein Fenster.</summary>
    procedure Refill;
    class function StateText(const AState: TAtlasMethodGroupState): string; static;
    class procedure Execute(const AStates: TAtlasMethodGroupStatesFunc;
      const AToggle, ARemove: TAtlasMethodGroupAction); static;
    property GroupList: TListBox read FList;
    property ToggleButton: TButton read FToggleButton;
    property RemoveButton: TButton read FRemoveButton;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Style.Signal,
  Atlas.UI.Debug.MethodBreakpoints.Strings;

const
  cDialogWidth = 640;
  cGroupsWidth = 520;
  cRowHeight = 26;
  cHintHeight = 18;
  cLabelWidth = 80;
  cListHeight = 240;
  cNoteHeight = 22;
  cCheckWidth = 180;

{ TAtlasMethodBreakpointsDialog }

constructor TAtlasMethodBreakpointsDialog.CreateDialog(AOwner: TComponent; const AGroup: TAtlasMethodGroup;
  const ASearch: TAtlasMethodSearch);
begin
  inherited CreateDialog(AOwner,
    TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodBreakpointsTitle), cDialogWidth);
  FSearch := ASearch;
  FInitial := AGroup;
  CreatePatternRows;
  CreateOptionRows;
  CreateList;
  FNote := AddNote(cNoteHeight);
  CreateButtons;
  FitHeight;
  // Größer ziehen: Die Liste nimmt die Höhe auf.
  AllowResize(FList);
  ActiveControl := FPattern;
  UpdateFooter;
end;

procedure TAtlasMethodBreakpointsDialog.DoShow;
begin
  inherited;
  // Die Liste braucht ein Fenster: erst hier suchen und füllen.
  if (Trim(FPattern.Text) <> '') and not FSearched then
  begin
    RunSearch;
  end;
end;

function TAtlasMethodBreakpointsDialog.AddCheck(AParent: TWinControl; const ACaption: string; ALeft: Integer;
  AChecked: Boolean): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ScaleValue(ALeft);
  Result.Top := ScaleValue(cRowLabelTop);
  Result.Width := ScaleValue(cCheckWidth);
  Result.Checked := AChecked;
end;

function TAtlasMethodBreakpointsDialog.AddLabeledEdit(const ACaption: string; AHeight96: Integer): TEdit;
var
  mRow: TPanel;
begin
  mRow := AddRow(AHeight96);
  AddLabel(mRow, ACaption).ShowAccelChar := False;
  Result := TEdit.Create(Self);
  Result.Parent := mRow;
  Result.Left := ScaleValue(cLabelWidth);
  Result.Top := 0;
  FitRight(Result);
end;

procedure TAtlasMethodBreakpointsDialog.CreatePatternRows;
var
  mFind: TButton;
  mRow: TPanel;
  mHint: TLabel;
begin
  FPattern := AddLabeledEdit(TAtlasMethodBreakpointsStrings.Text(
    TAtlasMethodBreakpointsTextId.MethodBreakpointsPattern), cRowHeight);
  FPattern.Text := FInitial.Pattern;
  // „Suchen“ rechts in derselben Zeile; Vorgabeknopf, damit die Eingabetaste sucht statt zu setzen.
  mFind := TButton.Create(Self);
  mFind.Parent := FPattern.Parent;
  mFind.Caption := TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodBreakpointsSearch);
  mFind.Default := True;
  mFind.Width := Max(ScaleValue(TAtlasButtonRow.cButtonMinWidth),
    Canvas.TextWidth(mFind.Caption) + ScaleValue(TAtlasButtonRow.cButtonPadding));
  mFind.Top := 0;
  mFind.Height := FPattern.Height;
  mFind.Left := FPattern.Parent.ClientWidth - mFind.Width;
  mFind.Anchors := [akTop, akRight];
  mFind.OnClick := FindClick;
  FPattern.Width := mFind.Left - FPattern.Left - ScaleValue(cRowGap);
  mRow := AddRow(cHintHeight);
  mHint := AddLabel(mRow,
    TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodBreakpointsPatternHint));
  mHint.ShowAccelChar := False;
  mHint.Left := ScaleValue(cLabelWidth);
  mHint.Top := 0;
  mHint.Enabled := False;
end;

procedure TAtlasMethodBreakpointsDialog.CreateOptionRows;
var
  mRow: TPanel;
begin
  mRow := AddRow(cRowHeight);
  FOverrides := AddCheck(mRow,
    TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodBreakpointsOverrides), 0,
    FInitial.Overrides);
  FOverrides.OnClick := SwitchClick;
  FOverloads := AddCheck(mRow,
    TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodBreakpointsOverloads),
    cCheckWidth, FInitial.Overloads);
  FOverloads.OnClick := SwitchClick;
  mRow := AddRow(cRowHeight);
  FGrow := AddCheck(mRow, TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodBreakpointsGrow), 0,
    FInitial.Grow);
  FitRight(FGrow);
  FCondition := AddLabeledEdit(TAtlasMethodBreakpointsStrings.Text(
    TAtlasMethodBreakpointsTextId.MethodBreakpointsCondition), cRowHeight);
  FCondition.Text := FInitial.Condition;
  mRow := AddRow(cRowHeight);
  FLogOnly := AddCheck(mRow,
    TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodBreakpointsLogOnly), 0,
    FInitial.LogOnly);
  FitRight(FLogOnly);
end;

procedure TAtlasMethodBreakpointsDialog.CreateList;
begin
  FList := TCheckListBox.Create(Self);
  // Lage vor Align und Parent wie bei AddRow.
  FList.Top := NextTop;
  FList.Height := ScaleValue(cListHeight);
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(ScaleValue(cRowGap), ScaleValue(cRowGap div 2), ScaleValue(cRowGap), 0);
  FList.Align := alTop;
  FList.Parent := Self;
  FList.OnClickCheck := ListClickCheck;
end;

procedure TAtlasMethodBreakpointsDialog.CreateButtons;
var
  mButtons: TAtlasButtonRow;
begin
  mButtons := AddButtonRow;
  FSet := mButtons.AddButton(TAtlasMethodBreakpointsStrings.Fmt(TAtlasMethodBreakpointsTextId.MethodBreakpointsSet,
    [0]));
  FSet.OnClick := SetClick;
  mButtons.AddButton(TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodBreakpointsCancel),
    TAtlasButtonKind.Cancel);
end;

{ TAtlasMethodBreakpointTexts }

class function TAtlasMethodBreakpointTexts.HitText(const AHit: TAtlasMethodHit): string;
var
  mFile, mExtra: string;
begin
  mFile := ExtractFileName(AHit.FileName.Replace('/', PathDelim));
  if AHit.HasSource then
  begin
    Result := TAtlasMethodBreakpointsStrings.Fmt(TAtlasMethodBreakpointsTextId.MethodBreakpointsHitLine, [mFile,
      AHit.Line + 1,
      AHit.DisplayName]);
  end
  else
  begin
    Result := mFile + '  ' + AHit.DisplayName;
  end;
  case AHit.Reason of
    TAtlasMethodHitReason.Override_:
      mExtra := TAtlasMethodBreakpointsStrings.Fmt(TAtlasMethodBreakpointsTextId.MethodBreakpointsOverride, [AHit.Via]);
    TAtlasMethodHitReason.Implementation_:
      mExtra := TAtlasMethodBreakpointsStrings.Fmt(TAtlasMethodBreakpointsTextId.MethodBreakpointsImplements,
        [AHit.Via]);
  else
    // Passt selbst: kein Zusatz.
    mExtra := '';
  end;
  if not AHit.HasSource then
  begin
    if mExtra <> '' then
    begin
      mExtra := mExtra + ', ';
    end;
    mExtra := mExtra + TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodBreakpointsNoSource);
  end;
  if mExtra <> '' then
  begin
    Result := Result + '  ·  ' + mExtra;
  end;
end;

class function TAtlasMethodBreakpointTexts.FooterText(const AAnswer: TAtlasMethodAnswer;
  ASelected: Integer): string;
begin
  if AAnswer.Truncated then
  begin
    Result := TAtlasMethodBreakpointsStrings.Fmt(TAtlasMethodBreakpointsTextId.MethodBreakpointsTruncated,
      [Length(AAnswer.Hits),
      ASelected]);
  end
  else
  begin
    Result := TAtlasMethodBreakpointsStrings.Fmt(TAtlasMethodBreakpointsTextId.MethodBreakpointsFooter,
      [Length(AAnswer.Hits), ASelected]);
  end;
end;

procedure TAtlasMethodBreakpointsDialog.UpdateFooter;
var
  mCount: Integer;
begin
  mCount := Length(Selected);
  FSet.Caption := TAtlasMethodBreakpointsStrings.Fmt(TAtlasMethodBreakpointsTextId.MethodBreakpointsSet, [mCount]);
  FSet.Enabled := mCount > 0;
  if not FSearched then
  begin
    FNote.ShowNote('', TAtlasSignalKind.Info);
  end
  else if FAnswer.Hits = nil then
  begin
    FNote.ShowNote(TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodBreakpointsNone),
      TAtlasSignalKind.Warn);
  end
  else
  begin
    FNote.ShowNote(TAtlasMethodBreakpointTexts.FooterText(FAnswer, mCount), TAtlasSignalKind.Info);
  end;
end;

procedure TAtlasMethodBreakpointsDialog.FindClick(Sender: TObject);
begin
  RunSearch;
end;

procedure TAtlasMethodBreakpointsDialog.SwitchClick(Sender: TObject);
begin
  if FSearched and (Trim(FPattern.Text) <> '') then
  begin
    RunSearch;
  end;
end;

procedure TAtlasMethodBreakpointsDialog.ListClickCheck(Sender: TObject);
begin
  UpdateFooter;
end;

procedure TAtlasMethodBreakpointsDialog.SetClick(Sender: TObject);
begin
  FChosen := Selected <> nil;
  if FChosen then
  begin
    ModalResult := mrOk;
  end;
end;

procedure TAtlasMethodBreakpointsDialog.RunSearch;
var
  mAnswer: TAtlasMethodAnswer;
  mError: string;
  mIndex: Integer;
begin
  FSearched := True;
  FAnswer := Default(TAtlasMethodAnswer);
  FList.Items.Clear;
  if not Assigned(FSearch) or not FSearch(TAtlasMethodQuery.Create(Trim(FPattern.Text), FOverrides.Checked,
    FOverloads.Checked), mAnswer, mError) then
  begin
    FNote.ShowNote(TAtlasMethodBreakpointsStrings.Fmt(TAtlasMethodBreakpointsTextId.MethodBreakpointsNoServer,
      [mError]),
      TAtlasSignalKind.Error);
    UpdateFooter;
    Exit;
  end;
  if mAnswer.Error <> '' then
  begin
    FNote.ShowNote(mAnswer.Error, TAtlasSignalKind.Error);
    FSet.Enabled := False;
    Exit;
  end;
  FAnswer := mAnswer;
  FList.Items.BeginUpdate;
  try
    for mIndex := 0 to High(FAnswer.Hits) do
    begin
      FList.Items.Add(TAtlasMethodBreakpointTexts.HitText(FAnswer.Hits[mIndex]));
      FList.Checked[mIndex] := FAnswer.Hits[mIndex].HasSource;
      FList.ItemEnabled[mIndex] := FAnswer.Hits[mIndex].HasSource;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  UpdateFooter;
end;

function TAtlasMethodBreakpointsDialog.Group: TAtlasMethodGroup;
begin
  Result := FInitial;
  Result.Pattern := Trim(FPattern.Text);
  Result.Overrides := FOverrides.Checked;
  Result.Overloads := FOverloads.Checked;
  Result.Grow := FGrow.Checked;
  Result.Condition := Trim(FCondition.Text);
  Result.LogOnly := FLogOnly.Checked;
  // Auch abgewählte Treffer gelten als gesehen: „Mitwachsen“ bringt sie nicht wieder.
  Result.Learn(FAnswer.Hits);
end;

function TAtlasMethodBreakpointsDialog.Selected: TAtlasMethodHits;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(FAnswer.Hits) do
  begin
    if FAnswer.Hits[mIndex].HasSource and (mIndex < FList.Items.Count) and FList.Checked[mIndex] then
    begin
      Result := Result + [FAnswer.Hits[mIndex]];
    end;
  end;
end;

class function TAtlasMethodBreakpointsDialog.Execute(var AGroup: TAtlasMethodGroup;
  const ASearch: TAtlasMethodSearch; out ASelected: TAtlasMethodHits): Boolean;
var
  mDialog: TAtlasMethodBreakpointsDialog;
begin
  ASelected := nil;
  mDialog := TAtlasMethodBreakpointsDialog.CreateDialog(nil, AGroup, ASearch);
  try
    Result := (mDialog.ShowModal = mrOk) and mDialog.FChosen;
    if Result then
    begin
      AGroup := mDialog.Group;
      ASelected := mDialog.Selected;
    end;
  finally
    mDialog.Free;
  end;
end;

{ TAtlasMethodGroupsDialog }

constructor TAtlasMethodGroupsDialog.CreateDialog(AOwner: TComponent; const AStates: TAtlasMethodGroupStatesFunc;
  const AToggle, ARemove: TAtlasMethodGroupAction);
begin
  inherited CreateDialog(AOwner, TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodGroupsTitle),
    cGroupsWidth);
  FStates := AStates;
  FToggle := AToggle;
  FRemove := ARemove;
  CreateList;
  CreateButtons;
  FitHeight;
  AllowResize(FList);
  ActiveControl := FList;
end;

procedure TAtlasMethodGroupsDialog.DoShow;
begin
  inherited;
  Refill;
end;

procedure TAtlasMethodGroupsDialog.CreateList;
begin
  FList := TListBox.Create(Self);
  FList.Top := NextTop;
  FList.Height := ScaleValue(cListHeight);
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(ScaleValue(cRowGap), ScaleValue(cRowGap), ScaleValue(cRowGap), 0);
  FList.Align := alTop;
  FList.Parent := Self;
end;

procedure TAtlasMethodGroupsDialog.CreateButtons;
var
  mButtons: TAtlasButtonRow;
begin
  mButtons := AddButtonRow;
  FToggleButton := mButtons.AddButton(TAtlasMethodBreakpointsStrings.Text(
    TAtlasMethodBreakpointsTextId.MethodGroupsToggle));
  FToggleButton.OnClick := ToggleClick;
  FRemoveButton := mButtons.AddButton(TAtlasMethodBreakpointsStrings.Text(
    TAtlasMethodBreakpointsTextId.MethodGroupsRemove));
  FRemoveButton.OnClick := RemoveClick;
  mButtons.AddButton(TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodGroupsClose),
    TAtlasButtonKind.Cancel);
end;

procedure TAtlasMethodGroupsDialog.Act(const AAction: TAtlasMethodGroupAction);
var
  mIndex: Integer;
begin
  mIndex := FList.ItemIndex;
  if not Assigned(AAction) or (mIndex < 0) or (mIndex > High(FItems)) then
  begin
    Exit;
  end;
  AAction(FItems[mIndex].Group);
  Refill;
end;

procedure TAtlasMethodGroupsDialog.ToggleClick(Sender: TObject);
begin
  Act(FToggle);
end;

procedure TAtlasMethodGroupsDialog.RemoveClick(Sender: TObject);
begin
  Act(FRemove);
end;

procedure TAtlasMethodGroupsDialog.Refill;
var
  mState: TAtlasMethodGroupState;
  mIndex: Integer;
begin
  mIndex := Max(FList.ItemIndex, 0);
  FItems := nil;
  if Assigned(FStates) then
  begin
    FItems := FStates();
  end;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mState in FItems do
    begin
      FList.Items.Add(StateText(mState));
    end;
    if FItems = nil then
    begin
      FList.Items.Add(TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodGroupsEmpty));
    end;
  finally
    FList.Items.EndUpdate;
  end;
  FToggleButton.Enabled := FItems <> nil;
  FRemoveButton.Enabled := FItems <> nil;
  if FItems <> nil then
  begin
    FList.ItemIndex := Min(mIndex, High(FItems));
  end;
end;

class function TAtlasMethodGroupsDialog.StateText(const AState: TAtlasMethodGroupState): string;
begin
  Result := TAtlasMethodBreakpointsStrings.Fmt(TAtlasMethodBreakpointsTextId.MethodGroupsItem, [AState.Group.Pattern,
    AState.Breakpoints,
    AState.Enabled]);
  if AState.Group.Grow then
  begin
    Result := Result + TAtlasMethodBreakpointsStrings.Text(TAtlasMethodBreakpointsTextId.MethodGroupsGrowing);
  end;
end;

class procedure TAtlasMethodGroupsDialog.Execute(const AStates: TAtlasMethodGroupStatesFunc;
  const AToggle, ARemove: TAtlasMethodGroupAction);
var
  mDialog: TAtlasMethodGroupsDialog;
begin
  mDialog := TAtlasMethodGroupsDialog.CreateDialog(nil, AStates, AToggle, ARemove);
  try
    mDialog.ShowModal;
  finally
    mDialog.Free;
  end;
end;

end.
