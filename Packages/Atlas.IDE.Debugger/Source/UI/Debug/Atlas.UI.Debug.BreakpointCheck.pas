unit Atlas.UI.Debug.BreakpointCheck;

// Haltepunkte, die nicht greifen werden (#577), Fensterteil (nur VCL):
//   Haltepunkte, die nicht greifen werden
//   3 Haltepunkte werden voraussichtlich nicht halten. Doppelklick springt …
//   ┌───────────────────────────────────────────────────────────────┐
//   │ Kunden.pas:42  Zeile ohne Code, nächste Codezeile 44          │
//   │ Kunden.pas:88  Inaktiver Zweig der bedingten Kompilierung (…) │
//   │ Werkzeug.pas:7 Unit gehört nicht zum gestarteten Projekt      │
//   └───────────────────────────────────────────────────────────────┘
//   [Auf nächste Codezeile verschieben (1)] [Trotzdem starten] [Abbrechen]
// Vor dem Start (Launch) entscheidet der Dialog über den Start: Trotzdem
// starten, Verschieben und starten, Abbrechen (Start unterbleibt). Aus dem
// Befehl „Haltepunkte prüfen“ (Command) gibt es nur Verschieben und Schließen.
// Doppelklick bzw. Eingabe auf einem Eintrag ruft AJump; der Dialog bleibt
// offen. Zeilen zeigt er ab 1 wie der Editor.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.BreakpointCheck,
  Atlas.UI.Foundation.Dialog;

type
  {$SCOPEDENUMS ON}
  TAtlasBreakpointCheckMode = (Launch, Command);
  /// <summary>Start: trotzdem starten bzw. schließen; Move: verschieben (und starten); Cancel: Start abbrechen.
  /// </summary>
  TAtlasBreakpointCheckChoice = (Start, Move, Cancel);
  {$SCOPEDENUMS OFF}

  TAtlasBreakpointJump = reference to procedure(const AProblem: TAtlasBreakpointProblem);

  TAtlasBreakpointCheckDialog = class(TAtlasDialog)
  private
    FProblems: TAtlasBreakpointProblems;
    FMode: TAtlasBreakpointCheckMode;
    FJump: TAtlasBreakpointJump;
    FSummary: TLabel;
    FList: TListBox;
    FMove: TButton;
    FStart: TButton;
    FCancel: TButton;
    FChoice: TAtlasBreakpointCheckChoice;
    procedure CreateSummary;
    procedure CreateList;
    procedure CreateButtons;
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyPress(Sender: TObject; var Key: Char);
    procedure MoveClick(Sender: TObject);
    procedure StartClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const AProblems: TAtlasBreakpointProblems;
      AMode: TAtlasBreakpointCheckMode; const AJump: TAtlasBreakpointJump);
    /// <summary>Liste füllen; braucht ein Fenster (DoShow, Tests nach HandleNeeded). Einmal.</summary>
    procedure Fill;
    /// <summary>Eintrag AIndex anspringen (wie Doppelklick).</summary>
    procedure JumpTo(AIndex: Integer);
    /// <summary>Text eines Eintrags: „Kunden.pas:42  Zeile ohne Code, nächste Codezeile 44“.</summary>
    class function ProblemText(const AProblem: TAtlasBreakpointProblem): string; static;
    /// <summary>Grund allein, Zeilen ab 1.</summary>
    class function ReasonText(const AProblem: TAtlasBreakpointProblem): string; static;
    /// <summary>Zeigt den Dialog modal.</summary>
    class function Execute(const AProblems: TAtlasBreakpointProblems; AMode: TAtlasBreakpointCheckMode;
      const AJump: TAtlasBreakpointJump): TAtlasBreakpointCheckChoice; static;
    property Choice: TAtlasBreakpointCheckChoice read FChoice;
    property SummaryLabel: TLabel read FSummary;
    property ProblemList: TListBox read FList;
    property MoveButton: TButton read FMove;
    property StartButton: TButton read FStart;
    property CancelButton: TButton read FCancel;
  end;

implementation

uses
  Atlas.UI.Debug.Strings;

const
  cDialogWidth = 620;
  cSummaryHeight = 22;
  cListHeight = 220;

{ TAtlasBreakpointCheckDialog }

constructor TAtlasBreakpointCheckDialog.CreateDialog(AOwner: TComponent; const AProblems: TAtlasBreakpointProblems;
  AMode: TAtlasBreakpointCheckMode; const AJump: TAtlasBreakpointJump);
begin
  inherited CreateDialog(AOwner, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointCheckTitle), cDialogWidth);
  FProblems := AProblems;
  FMode := AMode;
  FJump := AJump;
  FChoice := TAtlasBreakpointCheckChoice.Cancel;
  if FMode = TAtlasBreakpointCheckMode.Command then
  begin
    // Schließen ohne Verschieben ist im Befehl „nichts tun“.
    FChoice := TAtlasBreakpointCheckChoice.Start;
  end;
  CreateSummary;
  CreateList;
  CreateButtons;
  FitHeight;
  // Größer ziehen: Die Liste nimmt die Höhe auf.
  AllowResize(FList);
  ActiveControl := FList;
end;

procedure TAtlasBreakpointCheckDialog.CreateSummary;
var
  mRow: TPanel;
begin
  mRow := AddRow(cSummaryHeight);
  FSummary := AddLabel(mRow, TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointCheckSummary, [Length(FProblems)]));
  FSummary.ShowAccelChar := False;
end;

procedure TAtlasBreakpointCheckDialog.CreateList;
begin
  FList := TListBox.Create(Self);
  // Lage vor Align und Parent wie bei AddRow.
  FList.Top := NextTop;
  FList.Height := ScaleValue(cListHeight);
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(ScaleValue(cRowGap), 0, ScaleValue(cRowGap), 0);
  FList.Align := alTop;
  FList.Parent := Self;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyPress := ListKeyPress;
end;

procedure TAtlasBreakpointCheckDialog.CreateButtons;
var
  mButtons: TAtlasButtonRow;
  mMovable: Integer;
begin
  mButtons := AddButtonRow;
  mMovable := TAtlasBreakpointCheck.Movable(FProblems);
  FMove := mButtons.AddButton(TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointCheckMove, [mMovable]));
  FMove.Enabled := mMovable > 0;
  FMove.OnClick := MoveClick;
  if FMode = TAtlasBreakpointCheckMode.Launch then
  begin
    FStart := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointCheckStart),
      TAtlasButtonKind.Default);
    FStart.OnClick := StartClick;
    FCancel := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointCheckCancel),
      TAtlasButtonKind.Cancel);
    FCancel.OnClick := CancelClick;
  end
  else
  begin
    FStart := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointCheckClose),
      TAtlasButtonKind.Cancel);
    FStart.OnClick := StartClick;
  end;
end;

procedure TAtlasBreakpointCheckDialog.Fill;
var
  mProblem: TAtlasBreakpointProblem;
begin
  if FList.Items.Count > 0 then
  begin
    Exit;
  end;
  FList.Items.BeginUpdate;
  try
    for mProblem in FProblems do
    begin
      FList.Items.Add(ProblemText(mProblem));
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count > 0 then
  begin
    FList.ItemIndex := 0;
  end;
end;

procedure TAtlasBreakpointCheckDialog.DoShow;
begin
  inherited;
  // Die Liste braucht ein Fenster: erst hier füllen.
  Fill;
end;

class function TAtlasBreakpointCheckDialog.ReasonText(const AProblem: TAtlasBreakpointProblem): string;
begin
  case AProblem.Reason of
    TAtlasBreakpointReason.NoCode:
      if AProblem.CanMove then
      begin
        Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointCheckNoCodeNext, [AProblem.NextLine + 1]);
      end
      else
      begin
        Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointCheckNoCode);
      end;
    TAtlasBreakpointReason.Inactive:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointCheckInactive, [AProblem.Detail]);
    TAtlasBreakpointReason.NoDebugInfo:
      Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointCheckNoDebugInfo, [AProblem.Detail]);
    TAtlasBreakpointReason.NotInProject:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointCheckNotInProject);
  else
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointCheckUnreadable);
  end;
end;

class function TAtlasBreakpointCheckDialog.ProblemText(const AProblem: TAtlasBreakpointProblem): string;
begin
  Result := Format('%s:%d  %s', [ExtractFileName(AProblem.FileName.Replace('/', PathDelim)), AProblem.Line + 1,
    ReasonText(AProblem)]);
end;

procedure TAtlasBreakpointCheckDialog.JumpTo(AIndex: Integer);
begin
  if Assigned(FJump) and (AIndex >= 0) and (AIndex <= High(FProblems)) then
  begin
    FJump(FProblems[AIndex]);
  end;
end;

procedure TAtlasBreakpointCheckDialog.ListDblClick(Sender: TObject);
begin
  JumpTo(FList.ItemIndex);
end;

procedure TAtlasBreakpointCheckDialog.ListKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    JumpTo(FList.ItemIndex);
  end;
end;

procedure TAtlasBreakpointCheckDialog.MoveClick(Sender: TObject);
begin
  FChoice := TAtlasBreakpointCheckChoice.Move;
  ModalResult := mrRetry;
end;

procedure TAtlasBreakpointCheckDialog.StartClick(Sender: TObject);
begin
  FChoice := TAtlasBreakpointCheckChoice.Start;
  ModalResult := mrOk;
end;

procedure TAtlasBreakpointCheckDialog.CancelClick(Sender: TObject);
begin
  FChoice := TAtlasBreakpointCheckChoice.Cancel;
  ModalResult := mrCancel;
end;

class function TAtlasBreakpointCheckDialog.Execute(const AProblems: TAtlasBreakpointProblems;
  AMode: TAtlasBreakpointCheckMode; const AJump: TAtlasBreakpointJump): TAtlasBreakpointCheckChoice;
var
  mDialog: TAtlasBreakpointCheckDialog;
begin
  mDialog := TAtlasBreakpointCheckDialog.CreateDialog(nil, AProblems, AMode, AJump);
  try
    mDialog.ShowModal;
    Result := mDialog.Choice;
  finally
    mDialog.Free;
  end;
end;

end.
