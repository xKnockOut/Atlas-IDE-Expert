unit Atlas.UI.Notes.Dialog;

// Eingabe einer persönlichen Notiz (#545): Hinweis, mehrzeiliges Textfeld und
// die Knöpfe „Speichern“, „Abbrechen“ und (nur bei einer vorhandenen Notiz)
// „Löschen“. Enter beginnt eine neue Zeile, Strg+Enter speichert, Esc bricht
// ab. Wer den ganzen Text löscht und speichert, löscht die Notiz (bzw. legt
// keine an). Reine VCL; gespeichert wird vom Aufrufer.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.UI.Foundation.Dialog;

type
{$SCOPEDENUMS ON}
  TAtlasNoteChoice = (Cancel, Save, Delete);
{$SCOPEDENUMS OFF}

  TAtlasNoteDialog = class(TAtlasDialog)
  private
    FHint: TLabel;
    FMemo: TMemo;
    FSave: TButton;
    FCancel: TButton;
    FDelete: TButton;
    FCanDelete: Boolean;
    FChoice: TAtlasNoteChoice;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    procedure SaveClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure MemoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MemoKeyPress(Sender: TObject; var Key: Char);
  public
    /// <summary>ACanDelete: Es gibt die Notiz schon („Löschen“ sichtbar).</summary>
    constructor CreateDialog(AOwner: TComponent; const ATitle, AText: string; ACanDelete: Boolean);
    /// <summary>Wie „Speichern“: mit Text Save, ohne Text Delete bzw. (neue Notiz) Cancel.</summary>
    procedure Accept;
    /// <summary>Text ohne Leerraum am Rand, Zeilen mit #10 getrennt.</summary>
    function NoteText: string;
    /// <summary>Zeigt den Dialog modal; AText enthält danach den neuen Text (NoteText).</summary>
    class function Execute(const ATitle: string; var AText: string; ACanDelete: Boolean): TAtlasNoteChoice; static;
    /// <summary>Text ohne Leerraum am Rand, CRLF und CR zu #10.</summary>
    class function CleanText(const AText: string): string; static;
    property Memo: TMemo read FMemo;
    property HintLabel: TLabel read FHint;
    property SaveButton: TButton read FSave;
    property CancelButton: TButton read FCancel;
    property DeleteButton: TButton read FDelete;
    property Choice: TAtlasNoteChoice read FChoice;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Bookmarks.Strings;

const
  cGap = 8;
  cDialogWidth = 520;
  cDialogHeight = 300;

{ TAtlasNoteDialog }

constructor TAtlasNoteDialog.CreateDialog(AOwner: TComponent; const ATitle, AText: string; ACanDelete: Boolean);
var
  mBottom: TPanel;
begin
  inherited CreateDialog(AOwner, '', cDialogWidth);
  FCanDelete := ACanDelete;
  FChoice := TAtlasNoteChoice.Cancel;
  Caption := ATitle;
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  ClientHeight := ScaleValue(cDialogHeight);
  KeyPreview := False;

  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.Align := alTop;
  FHint.AlignWithMargins := True;
  FHint.Margins.SetBounds(cGap, cGap, cGap, cGap div 2);
  FHint.WordWrap := True;
  FHint.ShowAccelChar := False;
  FHint.Caption := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesDialogHint);

  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := ScaleValue(44);
  mBottom.BevelOuter := bvNone;
  // Rechts „Abbrechen“, links davon „Speichern“; „Löschen“ links außen.
  FCancel := AddButton(mBottom, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesDialogCancel), CancelClick);
  FCancel.Cancel := True;
  FCancel.Left := mBottom.ClientWidth - FCancel.Width - ScaleValue(cGap);
  FSave := AddButton(mBottom, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesDialogSave), SaveClick);
  FSave.Left := FCancel.Left - FSave.Width - ScaleValue(cGap);
  FDelete := AddButton(mBottom, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.NotesDialogDelete), DeleteClick);
  FDelete.Left := ScaleValue(cGap);
  FDelete.Anchors := [akLeft, akTop];
  FDelete.Visible := ACanDelete;

  FMemo := TMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.Align := alClient;
  FMemo.AlignWithMargins := True;
  FMemo.Margins.SetBounds(cGap, 0, cGap, 0);
  FMemo.ScrollBars := ssVertical;
  FMemo.WordWrap := True;
  FMemo.WantReturns := True;
  FMemo.WantTabs := False;
  FMemo.OnKeyDown := MemoKeyDown;
  FMemo.OnKeyPress := MemoKeyPress;
  FMemo.Lines.Text := AText.Replace(#13#10, #10).Replace(#10, #13#10);
  FHint.FocusControl := FMemo;
  ActiveControl := FMemo;
end;

function TAtlasNoteDialog.AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Canvas.Font := Font;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
  if Result.Width < ScaleValue(90) then
  begin
    Result.Width := ScaleValue(90);
  end;
  Result.Top := ScaleValue(cGap);
  Result.Height := ScaleValue(28);
  Result.Anchors := [akTop, akRight];
end;

class function TAtlasNoteDialog.CleanText(const AText: string): string;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10).Trim;
end;

function TAtlasNoteDialog.NoteText: string;
begin
  Result := CleanText(FMemo.Lines.Text);
end;

procedure TAtlasNoteDialog.Accept;
begin
  if NoteText <> '' then
  begin
    FChoice := TAtlasNoteChoice.Save;
  end
  else if FCanDelete then
  begin
    FChoice := TAtlasNoteChoice.Delete;
  end
  else
  begin
    FChoice := TAtlasNoteChoice.Cancel;
  end;
  ModalResult := mrOk;
end;

procedure TAtlasNoteDialog.SaveClick(Sender: TObject);
begin
  Accept;
end;

procedure TAtlasNoteDialog.CancelClick(Sender: TObject);
begin
  FChoice := TAtlasNoteChoice.Cancel;
  ModalResult := mrCancel;
end;

procedure TAtlasNoteDialog.DeleteClick(Sender: TObject);
begin
  FChoice := TAtlasNoteChoice.Delete;
  ModalResult := mrOk;
end;

procedure TAtlasNoteDialog.MemoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (ssCtrl in Shift) then
  begin
    Key := 0;
    Accept;
  end;
end;

procedure TAtlasNoteDialog.MemoKeyPress(Sender: TObject; var Key: Char);
begin
  // Strg+Enter erzeugt zusätzlich ein Zeichen #10; es soll keine Zeile einfügen.
  if Key = #10 then
  begin
    Key := #0;
  end;
end;

class function TAtlasNoteDialog.Execute(const ATitle: string; var AText: string;
  ACanDelete: Boolean): TAtlasNoteChoice;
var
  mDialog: TAtlasNoteDialog;
begin
  mDialog := TAtlasNoteDialog.CreateDialog(nil, ATitle, AText, ACanDelete);
  try
    mDialog.ShowModal;
    Result := mDialog.Choice;
    if Result = TAtlasNoteChoice.Save then
    begin
      AText := mDialog.NoteText;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
