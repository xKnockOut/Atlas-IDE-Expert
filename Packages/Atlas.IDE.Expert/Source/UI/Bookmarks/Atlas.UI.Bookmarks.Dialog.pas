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
  Atlas.UI.Strings;

const
  Gap = 8;
  DialogWidth = 460;

{ TAtlasBookmarkDialog }

constructor TAtlasBookmarkDialog.CreateDialog(AOwner: TComponent; const ATitle, AName: string);
var
  Bottom: TPanel;
begin
  inherited CreateNew(AOwner);
  Caption := ATitle;
  BorderStyle := bsDialog;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);

  FPrompt := TLabel.Create(Self);
  FPrompt.Parent := Self;
  FPrompt.Align := alTop;
  FPrompt.AlignWithMargins := True;
  FPrompt.Margins.SetBounds(Gap, Gap, Gap, Gap div 2);
  FPrompt.ShowAccelChar := False;
  FPrompt.Caption := TAtlasStrings.Text(TAtlasTextId.BookmarksDialogPrompt);

  FEdit := TEdit.Create(Self);
  FEdit.Parent := Self;
  FEdit.Align := alTop;
  FEdit.AlignWithMargins := True;
  FEdit.Margins.SetBounds(Gap, 0, Gap, 0);
  FEdit.Top := FPrompt.Top + FPrompt.Height + 1;
  FEdit.Text := AName;
  FEdit.OnChange := EditChange;
  FPrompt.FocusControl := FEdit;

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := ScaleValue(44);
  Bottom.BevelOuter := bvNone;
  // Rechts „Abbrechen“, links davon „Setzen“.
  FCancel := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.BookmarksDialogCancel), CancelClick);
  FCancel.Cancel := True;
  FCancel.Left := Bottom.ClientWidth - FCancel.Width - ScaleValue(Gap);
  FOk := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.BookmarksDialogOk), OkClick);
  FOk.Default := True;
  FOk.Left := FCancel.Left - FOk.Width - ScaleValue(Gap);

  ClientHeight := FEdit.Top + FEdit.Height + ScaleValue(Gap) + Bottom.Height;
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
    Result.Width := ScaleValue(90);
  Result.Top := ScaleValue(Gap);
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
    Exit;
  ModalResult := mrOk;
end;

procedure TAtlasBookmarkDialog.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

class function TAtlasBookmarkDialog.Execute(const ATitle: string; var AName: string): Boolean;
var
  Dialog: TAtlasBookmarkDialog;
begin
  Dialog := TAtlasBookmarkDialog.CreateDialog(nil, ATitle, AName);
  try
    Result := (Dialog.ShowModal = mrOk) and (Dialog.BookmarkName <> '');
    if Result then
      AName := Dialog.BookmarkName;
  finally
    Dialog.Free;
  end;
end;

end.
