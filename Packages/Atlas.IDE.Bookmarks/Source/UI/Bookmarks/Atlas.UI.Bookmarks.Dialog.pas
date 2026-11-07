unit Atlas.UI.Bookmarks.Dialog;

// Name eines benannten Lesezeichens (#622): kleines Eingabefeld mit dem
// Vorschlag (kurzer Methodenname und Zeilenbeginn, ganz markiert, sodass
// Tippen ihn ersetzt), „Setzen“ und „Abbrechen“. Enter setzt, Esc bricht ab;
// ohne Namen bleibt „Setzen“ gesperrt. Reine VCL; gespeichert wird vom
// Aufrufer. Auch zum Umbenennen aus der Befehlspalette nutzbar.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls;

type
  TAtlasBookmarkDialog = class(TForm)
  private
    FPrompt: TLabel;
    FEdit: TEdit;
    FOk: TButton;
    FCancel: TButton;
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    procedure EditChange(Sender: TObject);
    procedure OkClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent; const ATitle, AName: string);
    /// <summary>Name ohne Leerraum am Rand.</summary>
    function BookmarkName: string;
    /// <summary>Zeigt den Dialog modal; True mit Namen in AName, False bei Abbrechen.</summary>
    class function Execute(const ATitle: string; var AName: string): Boolean; static;
    property Prompt: TLabel read FPrompt;
    property Edit: TEdit read FEdit;
    property OkButton: TButton read FOk;
    property CancelButton: TButton read FCancel;
  end;

implementation

uses
  Atlas.UI.Bookmarks.Strings;

const
  cGap = 8;
  cDialogWidth = 460;

{ TAtlasBookmarkDialog }

constructor TAtlasBookmarkDialog.CreateDialog(AOwner: TComponent; const ATitle, AName: string);
var
  mBottom: TPanel;
begin
  inherited CreateNew(AOwner);
  Caption := ATitle;
  BorderStyle := bsDialog;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);

  FPrompt := TLabel.Create(Self);
  FPrompt.Parent := Self;
  FPrompt.Align := alTop;
  FPrompt.AlignWithMargins := True;
  FPrompt.Margins.SetBounds(cGap, cGap, cGap, cGap div 2);
  FPrompt.ShowAccelChar := False;
  FPrompt.Caption := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksDialogPrompt);

  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Align := alTop;
  FEdit.AlignWithMargins := True;
  FEdit.Margins.SetBounds(cGap, 0, cGap, 0);
  FEdit.Top := FPrompt.Top + FPrompt.Height + 1;
  FEdit.Text := AName;
  FEdit.OnChange := EditChange;
  FPrompt.FocusControl := FEdit;

  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := ScaleValue(44);
  mBottom.BevelOuter := bvNone;
  // Rechts „Abbrechen“, links davon „Setzen“.
  FCancel := AddButton(mBottom, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksDialogCancel), CancelClick);
  FCancel.Cancel := True;
  FCancel.Left := mBottom.ClientWidth - FCancel.Width - ScaleValue(cGap);
  FOk := AddButton(mBottom, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksDialogOk), OkClick);
  FOk.Default := True;
  FOk.Left := FCancel.Left - FOk.Width - ScaleValue(cGap);

  ClientHeight := FEdit.Top + FEdit.Height + ScaleValue(cGap) + mBottom.Height;
  // Vorschlag beim Öffnen ganz markiert (AutoSelect): Tippen ersetzt ihn, Enter übernimmt ihn.
  FEdit.AutoSelect := True;
  ActiveControl := FEdit;
  EditChange(FEdit);
end;

function TAtlasBookmarkDialog.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
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

function TAtlasBookmarkDialog.BookmarkName: string;
begin
  Result := Trim(FEdit.Text);
end;

procedure TAtlasBookmarkDialog.EditChange(Sender: TObject);
begin
  FOk.Enabled := BookmarkName <> '';
end;

procedure TAtlasBookmarkDialog.OkClick(Sender: TObject);
begin
  if BookmarkName = '' then
  begin
    Exit;
  end;
  ModalResult := mrOk;
end;

procedure TAtlasBookmarkDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

class function TAtlasBookmarkDialog.Execute(const ATitle: string; var AName: string): Boolean;
var
  mDialog: TAtlasBookmarkDialog;
begin
  mDialog := TAtlasBookmarkDialog.CreateDialog(nil, ATitle, AName);
  try
    Result := (mDialog.ShowModal = mrOk) and (mDialog.BookmarkName <> '');
    if Result then
    begin
      AName := mDialog.BookmarkName;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
