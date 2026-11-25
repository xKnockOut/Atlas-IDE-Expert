unit Atlas.UI.Commands.KeyAssign;

// Dialog „Tastenkürzel für …“ (#2938), reine VCL: Zeile mit dem Feld, das den
// nächsten Tastendruck als Taste nimmt (TAtlasCommandKeys.Capture: Strg oder
// Alt nötig, F1–F24 auch allein), darunter der Hinweis, ob die Taste frei ist
// oder wer sie hat (HoldersOf vom Aufrufer), dann „OK“, „Entfernen“ und
// „Abbrechen“. Enter und Esc ohne Umschaltung bleiben beim Dialog. Grundlage
// ist TAtlasDialog: Fläche und Knöpfe zeichnet das IDE-Thema.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.Vcl.Forms.Dialog;

type
  TAtlasKeyAssignDialog = class(TAtlasDialog)
  private
    FKey: Word;
    FHoldersOf: TFunc<Word, string>;
    FEdit: TEdit;
    FNote: TAtlasNoteLabel;
    FOk: TButton;
    FRemove: TButton;
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditKeyPress(Sender: TObject; var Key: Char);
    procedure RemoveClick(Sender: TObject);
    /// <summary>Taste im Feld und Hinweis zur Belegung zeigen.</summary>
    procedure ShowKey;
  public
    /// <summary>Dialog für den Befehl ACommand mit der bisherigen Taste AKey (0 = keine). AHoldersOf nennt die
    /// anderen Belegungen einer Taste ('' = frei); nil prüft nicht.</summary>
    constructor CreateFor(AOwner: TComponent; const ACommand: string; AKey: Word;
      const AHoldersOf: TFunc<Word, string>);
    /// <summary>Tastendruck wie im Feld (virtuelle Taste und Umschaltung); True, wenn er als Taste gilt.</summary>
    function Press(AVirtualKey: Word; AShift: TShiftState): Boolean;
    /// <summary>Modal zeigen; True, wenn „OK“ oder „Entfernen“ gewählt wurde, AKey ist dann die neue Taste
    /// (0 = entfernt).</summary>
    class function Execute(const ACommand: string; var AKey: Word;
      const AHoldersOf: TFunc<Word, string>): Boolean; static;
    property Key: Word read FKey;
    property KeyEdit: TEdit read FEdit;
    property Note: TAtlasNoteLabel read FNote;
    property OkButton: TButton read FOk;
    property RemoveButton: TButton read FRemove;
  end;

implementation

uses
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Plugin.Style.Signal,
  Atlas.Core.Commands.CustomKeys,
  Atlas.UI.Commands.Strings;

const
  // Maße in logischen Pixeln (96 dpi).
  cDialogWidth = 440;
  cRowHeight = 24;
  cLabelWidth = 110;
  cNoteHeight = 20;

{ TAtlasKeyAssignDialog }

constructor TAtlasKeyAssignDialog.CreateFor(AOwner: TComponent; const ACommand: string; AKey: Word;
  const AHoldersOf: TFunc<Word, string>);
var
  mRow: TPanel;
  mButtons: TAtlasButtonRow;
begin
  inherited CreateDialog(AOwner, TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.KeyAssignTitle, [ACommand]),
    cDialogWidth);
  FKey := AKey;
  FHoldersOf := AHoldersOf;
  mRow := AddRow(cRowHeight);
  AddLabel(mRow, TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyAssignPrompt));
  FEdit := TEdit.Create(Self);
  FEdit.Parent := mRow;
  FEdit.Left := ScaleValue(cLabelWidth);
  FEdit.Top := 0;
  FEdit.Width := ScaleValue(cDialogWidth - cLabelWidth);
  // Nur lesen: Das Feld zeigt die Taste, getippt wird nichts.
  FEdit.ReadOnly := True;
  FEdit.OnKeyDown := EditKeyDown;
  FEdit.OnKeyPress := EditKeyPress;
  FitRight(FEdit);
  FNote := AddNote(cNoteHeight);
  mButtons := AddButtonRow;
  FOk := mButtons.AddButton(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyAssignOk), TAtlasButtonKind.Default);
  FOk.ModalResult := mrOk;
  FRemove := mButtons.AddButton(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyAssignRemove));
  FRemove.OnClick := RemoveClick;
  mButtons.AddButton(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyAssignCancel), TAtlasButtonKind.Cancel);
  FitHeight;
  ActiveControl := FEdit;
  ShowKey;
end;

function TAtlasKeyAssignDialog.Press(AVirtualKey: Word; AShift: TShiftState): Boolean;
var
  mModifiers, mKey: Word;
begin
  mModifiers := 0;
  if ssShift in AShift then
  begin
    mModifiers := mModifiers or TAtlasCommandKeys.cScShift;
  end;
  if ssCtrl in AShift then
  begin
    mModifiers := mModifiers or TAtlasCommandKeys.cScCtrl;
  end;
  if ssAlt in AShift then
  begin
    mModifiers := mModifiers or TAtlasCommandKeys.cScAlt;
  end;
  Result := TAtlasCommandKeys.Capture(AVirtualKey, mModifiers, mKey);
  if Result then
  begin
    FKey := mKey;
    ShowKey;
  end;
end;

procedure TAtlasKeyAssignDialog.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Press(Key, Shift) then
  begin
    Key := 0;
  end;
end;

procedure TAtlasKeyAssignDialog.EditKeyPress(Sender: TObject; var Key: Char);
begin
  // Kein Piepen und kein Zeichen: Das Feld zeigt nur die Taste.
  Key := #0;
end;

procedure TAtlasKeyAssignDialog.RemoveClick(Sender: TObject);
begin
  FKey := 0;
  ModalResult := mrOk;
end;

procedure TAtlasKeyAssignDialog.ShowKey;
var
  mHolders: string;
begin
  FRemove.Enabled := FKey <> 0;
  if FKey = 0 then
  begin
    FEdit.Text := TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyMapNoKey);
    FNote.ShowNote('', TAtlasSignalKind.Info);
    Exit;
  end;
  FEdit.Text := ShortCutToText(TShortCut(FKey));
  mHolders := '';
  if Assigned(FHoldersOf) then
  begin
    mHolders := FHoldersOf(FKey);
  end;
  if mHolders = '' then
  begin
    FNote.ShowNote(TAtlasCommandsStrings.Text(TAtlasCommandsTextId.KeyAssignFree), TAtlasSignalKind.Ok);
  end
  else
  begin
    FNote.ShowNote(TAtlasCommandsStrings.Fmt(TAtlasCommandsTextId.KeyAssignTaken, [mHolders]), TAtlasSignalKind.Warn);
  end;
end;

class function TAtlasKeyAssignDialog.Execute(const ACommand: string; var AKey: Word;
  const AHoldersOf: TFunc<Word, string>): Boolean;
var
  mDialog: TAtlasKeyAssignDialog;
begin
  mDialog := TAtlasKeyAssignDialog.CreateFor(Application, ACommand, AKey, AHoldersOf);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AKey := mDialog.Key;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
