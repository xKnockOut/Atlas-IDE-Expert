unit Atlas.UI.Tracker.MoveDialog;

// Rückfrage beim Ziehen einer Karte im „Atlas-Board“ (#1272), reine VCL:
//   ATL-123 → Zur Prüfung?
//   Kommentar (optional, Markdown):
//   [                                   ]
//   [ ] Nicht mehr fragen
//                          [Verschieben] [Abbrechen]
// Wie der Dialog „Beenden …“ (#1266) mit Kommentarfeld; geschrieben wird erst
// nach „Verschieben“ in der IDE-Schicht, Fehlertexte kommen aus
// TAtlasTrackerEndDialog.ErrorText. Strg+Enter verschiebt.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls;

type
  TAtlasBoardMoveDialog = class(TForm)
  public const
    DialogWidth = 460;
    CommentHeight = 110;
  private
    FQuestion: TLabel;
    FComment: TMemo;
    FDontAsk: TCheckBox;
    FMove: TButton;
    FCancel: TButton;
    procedure DialogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor CreateDialog(AOwner: TComponent; const AKey, AColumn: string);
    /// <summary>Kommentar ohne Leerzeilen am Ende; '' = keiner.</summary>
    function Comment: string;
    /// <summary>Modal zeigen; True nach „Verschieben“ mit Kommentar und „Nicht mehr fragen“.</summary>
    class function Execute(const AKey, AColumn: string; out AComment: string; out ADontAsk: Boolean): Boolean;
      static;
    property QuestionLabel: TLabel read FQuestion;
    property CommentMemo: TMemo read FComment;
    property DontAskCheck: TCheckBox read FDontAsk;
    property MoveButton: TButton read FMove;
    property CancelButton: TButton read FCancel;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Graphics,
  Atlas.UI.Strings;

const
  Gap = 10;

{ TAtlasBoardMoveDialog }

constructor TAtlasBoardMoveDialog.CreateDialog(AOwner: TComponent; const AKey, AColumn: string);
var
  mLabel: TLabel;
  mButtons: TFlowPanel;
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasStrings.Text(TAtlasTextId.BoardMoveTitle);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);
  KeyPreview := True;
  OnKeyDown := DialogKeyDown;

  FQuestion := TLabel.Create(Self);
  FQuestion.Parent := Self;
  FQuestion.Align := alTop;
  FQuestion.AlignWithMargins := True;
  FQuestion.Margins.SetBounds(Gap, Gap, Gap, 0);
  FQuestion.Font.Style := [fsBold];
  FQuestion.WordWrap := True;
  FQuestion.Caption := TAtlasStrings.Fmt(TAtlasTextId.BoardMoveQuestion, [AKey, AColumn]);

  mLabel := TLabel.Create(Self);
  mLabel.Parent := Self;
  mLabel.Align := alTop;
  mLabel.AlignWithMargins := True;
  mLabel.Margins.SetBounds(Gap, Gap, Gap, 0);
  mLabel.Top := FQuestion.Top + FQuestion.Height + 1;
  mLabel.Caption := TAtlasStrings.Text(TAtlasTextId.BoardMoveComment);

  FComment := TMemo.Create(Self);
  FComment.Parent := Self;
  FComment.Align := alTop;
  FComment.AlignWithMargins := True;
  FComment.Margins.SetBounds(Gap, Gap div 2, Gap, 0);
  FComment.Top := mLabel.Top + mLabel.Height + 1;
  FComment.Height := ScaleValue(CommentHeight);
  FComment.ScrollBars := ssVertical;
  FComment.WantReturns := True;

  FDontAsk := TCheckBox.Create(Self);
  FDontAsk.Parent := Self;
  FDontAsk.Align := alTop;
  FDontAsk.AlignWithMargins := True;
  FDontAsk.Margins.SetBounds(Gap, Gap div 2, Gap, 0);
  FDontAsk.Top := FComment.Top + FComment.Height + 1;
  FDontAsk.Caption := TAtlasStrings.Text(TAtlasTextId.BoardMoveDontAsk);

  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alTop;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(Gap, Gap, Gap, Gap);
  mButtons.Top := FDontAsk.Top + FDontAsk.Height + 1;
  Canvas.Font := Font;
  FMove := TButton.Create(Self);
  FMove.Parent := mButtons;
  FMove.Caption := TAtlasStrings.Text(TAtlasTextId.BoardMoveOk);
  FMove.Width := Canvas.TextWidth(FMove.Caption) + ScaleValue(32);
  FMove.AlignWithMargins := True;
  FMove.Margins.SetBounds(0, 0, Gap, 0);
  FMove.Default := True;
  FMove.ModalResult := mrOk;
  FCancel := TButton.Create(Self);
  FCancel.Parent := mButtons;
  FCancel.Caption := TAtlasStrings.Text(TAtlasTextId.IssueDialogCancel);
  FCancel.Width := Canvas.TextWidth(FCancel.Caption) + ScaleValue(32);
  FCancel.AlignWithMargins := True;
  FCancel.Margins.SetBounds(0, 0, Gap, 0);
  FCancel.Cancel := True;
  FCancel.ModalResult := mrCancel;
  ActiveControl := FComment;
  ClientHeight := mButtons.Top + mButtons.Height + Gap;
end;

procedure TAtlasBoardMoveDialog.DialogKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Im Kommentar ist Enter ein Zeilenumbruch; Strg+Enter verschiebt.
  if (Key = VK_RETURN) and (ssCtrl in Shift) then
  begin
    Key := 0;
    ModalResult := mrOk;
  end;
end;

function TAtlasBoardMoveDialog.Comment: string;
begin
  Result := TrimRight(FComment.Text);
end;

class function TAtlasBoardMoveDialog.Execute(const AKey, AColumn: string; out AComment: string;
  out ADontAsk: Boolean): Boolean;
var
  mDialog: TAtlasBoardMoveDialog;
begin
  mDialog := TAtlasBoardMoveDialog.CreateDialog(nil, AKey, AColumn);
  try
    Result := mDialog.ShowModal = mrOk;
    AComment := mDialog.Comment;
    ADontAsk := Result and mDialog.DontAskCheck.Checked;
  finally
    mDialog.Free;
  end;
end;

end.
