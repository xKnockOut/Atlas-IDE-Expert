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
  Vcl.ExtCtrls;

type
{$SCOPEDENUMS ON}
  TAtlasNoteChoice = (Cancel, Save, Delete);
{$SCOPEDENUMS OFF}

  TAtlasNoteDialog = class(TForm)
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
  Atlas.UI.Strings;

const
  Gap = 8;
  DialogWidth = 520;
  DialogHeight = 300;

{ TAtlasNoteDialog }

constructor TAtlasNoteDialog.CreateDialog(AOwner: TComponent; const ATitle, AText: string; ACanDelete: Boolean);
var
  Bottom: TPanel;
begin
  inherited CreateNew(AOwner);
  FCanDelete := ACanDelete;
  FChoice := TAtlasNoteChoice.Cancel;
  Caption := ATitle;
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);
  ClientHeight := ScaleValue(DialogHeight);
  KeyPreview := False;

  FHint := TLabel.Create(Self);
  FHint.Parent := Self;
  FHint.Align := alTop;
  FHint.AlignWithMargins := True;
  FHint.Margins.SetBounds(Gap, Gap, Gap, Gap div 2);
  FHint.WordWrap := True;
  FHint.ShowAccelChar := False;
  FHint.Caption := TAtlasStrings.Text(TAtlasTextId.NotesDialogHint);

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := ScaleValue(44);
  Bottom.BevelOuter := bvNone;
  // Rechts „Abbrechen“, links davon „Speichern“; „Löschen“ links außen.
  FCancel := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.NotesDialogCancel), CancelClick);
  FCancel.Cancel := True;
  FCancel.Left := Bottom.ClientWidth - FCancel.Width - ScaleValue(Gap);
  FSave := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.NotesDialogSave), SaveClick);
  FSave.Left := FCancel.Left - FSave.Width - ScaleValue(Gap);
  FDelete := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.NotesDialogDelete), DeleteClick);
  FDelete.Left := ScaleValue(Gap);
  FDelete.Anchors := [akLeft, akTop];
  FDelete.Visible := ACanDelete;

  FMemo := TMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.Align := alClient;
  FMemo.AlignWithMargins := True;
  FMemo.Margins.SetBounds(Gap, 0, Gap, 0);
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
    Result.Width := ScaleValue(90);
  Result.Top := ScaleValue(Gap);
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
    FChoice := TAtlasNoteChoice.Save
  else if FCanDelete then
    FChoice := TAtlasNoteChoice.Delete
  else
    FChoice := TAtlasNoteChoice.Cancel;
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
    Key := #0;
end;

class function TAtlasNoteDialog.Execute(const ATitle: string; var AText: string;
  ACanDelete: Boolean): TAtlasNoteChoice;
var
  Dialog: TAtlasNoteDialog;
begin
  Dialog := TAtlasNoteDialog.CreateDialog(nil, ATitle, AText, ACanDelete);
  try
    Dialog.ShowModal;
    Result := Dialog.Choice;
    if Result = TAtlasNoteChoice.Save then
      AText := Dialog.NoteText;
  finally
    Dialog.Free;
  end;
end;

end.
