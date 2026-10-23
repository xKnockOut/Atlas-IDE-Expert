unit Atlas.UI.SymbolPath.Dialog;

// Eingabedialog „Weg zwischen Symbolen“ (#1117), reine VCL: zwei Felder
// „Von“ und „Nach“ mit Vervollständigung, „Höchstens Schritte“ (1–16) und
// „Alle gleich kurzen Wege“. Beim Tippen fragt der Dialog nach kurzer Pause
// OnSuggest (Symbole des Projekts, setzt die IDE-Schicht) und zeigt die
// Vorschläge in einer Liste unter dem Feld: ↓ geht in die Liste, Enter oder
// Doppelklick übernimmt, Esc schließt erst die Liste, dann den Dialog. Ohne
// beide Angaben bleibt der Dialog offen und sagt, was fehlt. Aufgebaut wird
// im Code (keine DFM), damit der Dialog ohne Ressource entsteht.

interface

uses
  System.SysUtils,
  System.Classes,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics;

type
  /// <summary>Vorschläge zu einem Teil eines Namens; leer = keine.</summary>
  TAtlasSymbolPathSuggest = reference to function(const APattern: string): TArray<string>;

  TAtlasSymbolPathRequestInput = record
    From: string;
    To_: string;
    MaxSteps: Integer;
    All: Boolean;
  end;

  TAtlasSymbolPathDialog = class(TForm)
  private
    FFrom: TEdit;
    FTo: TEdit;
    FSteps: TEdit;
    FStepsUpDown: TUpDown;
    FAll: TCheckBox;
    FMessage: TLabel;
    FSearch: TButton;
    FCancel: TButton;
    FList: TListBox;
    FTimer: TTimer;
    /// <summary>Feld, zu dem die Liste gehört bzw. das zuletzt getippt wurde.</summary>
    FTarget: TEdit;
    FSuggest: TAtlasSymbolPathSuggest;
    FFilling: Boolean;
    procedure EditChange(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ControlEnter(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListDblClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure SearchClick(Sender: TObject);
    /// <summary>Enter und Esc bei offener Vorschlagsliste: übernehmen bzw. Liste schließen, statt „Suchen“
    /// oder „Abbrechen“ auszulösen (die VCL fragt Standard- und Abbrechen-Knopf vor OnKeyDown).</summary>
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    procedure Accept;
    procedure HideList;
    function GetInput: TAtlasSymbolPathRequestInput;
    procedure SetInput(const AValue: TAtlasSymbolPathRequestInput);
  public
    constructor CreateDialog(AOwner: TComponent; const ASuggest: TAtlasSymbolPathSuggest);
    /// <summary>Vorschläge für AEdit sofort holen und zeigen (ohne Pause; auch für Tests).</summary>
    procedure Suggest(AEdit: TEdit);
    /// <summary>Gewählten Vorschlag ins Feld übernehmen.</summary>
    procedure TakeSuggestion;
    /// <summary>Beide Angaben vorhanden; sonst Hinweis und Fokus ins leere Feld.</summary>
    function Validate: Boolean;
    /// <summary>Modal zeigen; True mit AInput, wenn „Suchen“ gewählt wurde.</summary>
    class function Execute(const ASuggest: TAtlasSymbolPathSuggest; var AInput: TAtlasSymbolPathRequestInput): Boolean;
      static;
    property Input: TAtlasSymbolPathRequestInput read GetInput write SetInput;
    property FromEdit: TEdit read FFrom;
    property ToEdit: TEdit read FTo;
    property StepsEdit: TEdit read FSteps;
    property AllCheck: TCheckBox read FAll;
    property MessageLabel: TLabel read FMessage;
    property SuggestionList: TListBox read FList;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Atlas.UI.Strings;

const
  /// <summary>Pause nach dem letzten Tastendruck, bevor Vorschläge geholt werden.</summary>
  SuggestDelayMs = 250;
  MaxSuggestions = 12;
  DefaultSteps = 8;
  MaxSteps = 16;

{ TAtlasSymbolPathDialog }

constructor TAtlasSymbolPathDialog.CreateDialog(AOwner: TComponent; const ASuggest: TAtlasSymbolPathSuggest);
var
  Y, Gap, LabelWidth, EditWidth: Integer;

  function AddLabel(const AText: string; ATop: Integer; AFocus: TWinControl): TLabel;
  begin
    Result := TLabel.Create(Self);
    Result.Parent := Self;
    Result.Left := Gap;
    Result.Top := ATop + MulDiv(3, CurrentPPI, 96);
    Result.Caption := AText;
    Result.FocusControl := AFocus;
  end;

  function NewEdit(ATop: Integer): TEdit;
  begin
    Result := TEdit.Create(Self);
    Result.Parent := Self;
    Result.Left := Gap + LabelWidth;
    Result.Top := ATop;
    Result.Width := EditWidth;
    Result.TextHint := TAtlasStrings.Text(TAtlasTextId.SymbolPathInputHint);
    Result.OnChange := EditChange;
    Result.OnKeyDown := EditKeyDown;
    Result.OnEnter := ControlEnter;
  end;

begin
  inherited CreateNew(AOwner);
  FSuggest := ASuggest;
  Caption := TAtlasStrings.Text(TAtlasTextId.SymbolPathCaption);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Gap := MulDiv(12, CurrentPPI, 96);
  LabelWidth := MulDiv(130, CurrentPPI, 96);
  EditWidth := MulDiv(360, CurrentPPI, 96);
  ClientWidth := Gap * 2 + LabelWidth + EditWidth;
  Y := Gap;
  FFrom := NewEdit(Y);
  AddLabel(TAtlasStrings.Text(TAtlasTextId.SymbolPathFrom), Y, FFrom);
  Inc(Y, FFrom.Height + MulDiv(8, CurrentPPI, 96));
  FTo := NewEdit(Y);
  AddLabel(TAtlasStrings.Text(TAtlasTextId.SymbolPathTo), Y, FTo);
  Inc(Y, FTo.Height + MulDiv(8, CurrentPPI, 96));
  FSteps := TEdit.Create(Self);
  FSteps.Parent := Self;
  FSteps.Left := Gap + LabelWidth;
  FSteps.Top := Y;
  FSteps.Width := MulDiv(50, CurrentPPI, 96);
  FSteps.NumbersOnly := True;
  FSteps.OnEnter := ControlEnter;
  FStepsUpDown := TUpDown.Create(Self);
  FStepsUpDown.Parent := Self;
  FStepsUpDown.Associate := FSteps;
  FStepsUpDown.Min := 1;
  FStepsUpDown.Max := MaxSteps;
  FStepsUpDown.Position := DefaultSteps;
  AddLabel(TAtlasStrings.Text(TAtlasTextId.SymbolPathMaxSteps), Y, FSteps);
  Inc(Y, FSteps.Height + MulDiv(8, CurrentPPI, 96));
  FAll := TCheckBox.Create(Self);
  FAll.Parent := Self;
  FAll.Left := Gap + LabelWidth;
  FAll.Top := Y;
  FAll.Width := EditWidth;
  FAll.Caption := TAtlasStrings.Text(TAtlasTextId.SymbolPathAll);
  FAll.OnEnter := ControlEnter;
  Inc(Y, FAll.Height + MulDiv(8, CurrentPPI, 96));
  FMessage := TLabel.Create(Self);
  FMessage.Parent := Self;
  FMessage.Left := Gap;
  FMessage.Top := Y;
  FMessage.Font.Color := clRed;
  FMessage.ShowAccelChar := False;
  Inc(Y, FMessage.Height + MulDiv(8, CurrentPPI, 96));
  FCancel := TButton.Create(Self);
  FCancel.Parent := Self;
  FCancel.Caption := TAtlasStrings.Text(TAtlasTextId.SymbolPathCancel);
  FCancel.Cancel := True;
  FCancel.ModalResult := mrCancel;
  FCancel.Top := Y;
  FCancel.Left := ClientWidth - Gap - FCancel.Width;
  FSearch := TButton.Create(Self);
  FSearch.Parent := Self;
  FSearch.Caption := TAtlasStrings.Text(TAtlasTextId.SymbolPathSearch);
  FSearch.Default := True;
  FSearch.Top := Y;
  FSearch.Left := FCancel.Left - MulDiv(8, CurrentPPI, 96) - FSearch.Width;
  FSearch.OnClick := SearchClick;
  ClientHeight := Y + FSearch.Height + Gap;
  // Vorschlagsliste über den Feldern darunter; erst beim Tippen sichtbar.
  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.Visible := False;
  FList.Width := EditWidth;
  FList.Height := MulDiv(160, CurrentPPI, 96);
  FList.OnKeyDown := ListKeyDown;
  FList.OnDblClick := ListDblClick;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := SuggestDelayMs;
  FTimer.OnTimer := TimerTick;
  ActiveControl := FFrom;
end;

class function TAtlasSymbolPathDialog.Execute(const ASuggest: TAtlasSymbolPathSuggest;
  var AInput: TAtlasSymbolPathRequestInput): Boolean;
var
  Dialog: TAtlasSymbolPathDialog;
begin
  Dialog := TAtlasSymbolPathDialog.CreateDialog(Application, ASuggest);
  try
    Dialog.Input := AInput;
    // Von schon gefüllt („Weg von hier nach …“): gleich ins Ziel.
    if Dialog.FFrom.Text <> '' then
      Dialog.ActiveControl := Dialog.FTo;
    Result := Dialog.ShowModal = mrOk;
    if Result then
      AInput := Dialog.Input;
  finally
    Dialog.Free;
  end;
end;

function TAtlasSymbolPathDialog.GetInput: TAtlasSymbolPathRequestInput;
begin
  Result.From := Trim(FFrom.Text);
  Result.To_ := Trim(FTo.Text);
  Result.MaxSteps := EnsureRange(StrToIntDef(FSteps.Text, DefaultSteps), 1, MaxSteps);
  Result.All := FAll.Checked;
end;

procedure TAtlasSymbolPathDialog.SetInput(const AValue: TAtlasSymbolPathRequestInput);
begin
  FFilling := True;
  try
    FFrom.Text := AValue.From;
    FTo.Text := AValue.To_;
  finally
    FFilling := False;
  end;
  if (AValue.MaxSteps >= 1) and (AValue.MaxSteps <= MaxSteps) then
    FStepsUpDown.Position := AValue.MaxSteps
  else
    FStepsUpDown.Position := DefaultSteps;
  FAll.Checked := AValue.All;
end;

procedure TAtlasSymbolPathDialog.EditChange(Sender: TObject);
begin
  if FFilling or not (Sender is TEdit) then
    Exit;
  FTarget := TEdit(Sender);
  FMessage.Caption := '';
  FTimer.Enabled := False;
  FTimer.Enabled := Assigned(FSuggest);
end;

procedure TAtlasSymbolPathDialog.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  if FTarget <> nil then
    Suggest(FTarget);
end;

procedure TAtlasSymbolPathDialog.Suggest(AEdit: TEdit);
var
  Items: TArray<string>;
  Item: string;
begin
  FTarget := AEdit;
  Items := nil;
  if Assigned(FSuggest) and (Trim(AEdit.Text) <> '') then
    Items := FSuggest(Trim(AEdit.Text));
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for Item in Items do
    begin
      if FList.Items.Count >= MaxSuggestions then
        Break;
      if FList.Items.IndexOf(Item) < 0 then
        FList.Items.Add(Item);
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count = 0 then
  begin
    HideList;
    Exit;
  end;
  FList.Left := AEdit.Left;
  FList.Top := AEdit.Top + AEdit.Height;
  FList.Width := AEdit.Width;
  FList.ItemIndex := 0;
  FList.Visible := True;
  FList.BringToFront;
end;

procedure TAtlasSymbolPathDialog.HideList;
begin
  FList.Visible := False;
end;

procedure TAtlasSymbolPathDialog.TakeSuggestion;
begin
  if (FTarget = nil) or not FList.Visible or (FList.ItemIndex < 0) then
    Exit;
  FFilling := True;
  try
    FTarget.Text := FList.Items[FList.ItemIndex];
    FTarget.SelStart := Length(FTarget.Text);
  finally
    FFilling := False;
  end;
  HideList;
  if FTarget.Showing and FTarget.CanFocus then
    FTarget.SetFocus;
end;

procedure TAtlasSymbolPathDialog.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if not FList.Visible or (Sender <> FTarget) then
    Exit;
  case Key of
    VK_DOWN:
      begin
        if FList.Showing and FList.CanFocus then
          FList.SetFocus;
        Key := 0;
      end;
  end;
end;

procedure TAtlasSymbolPathDialog.ControlEnter(Sender: TObject);
begin
  // Ein anderes Feld: die Liste gehört nicht dazu und verdeckte es sonst.
  if Sender <> FTarget then
    HideList;
end;

procedure TAtlasSymbolPathDialog.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_UP:
      if (FList.ItemIndex <= 0) and (FTarget <> nil) and FTarget.Showing and FTarget.CanFocus then
      begin
        FTarget.SetFocus;
        Key := 0;
      end;
  end;
end;

procedure TAtlasSymbolPathDialog.ListDblClick(Sender: TObject);
begin
  TakeSuggestion;
end;

procedure TAtlasSymbolPathDialog.CMDialogKey(var Message: TCMDialogKey);
begin
  if FList.Visible and ((Message.CharCode = VK_RETURN) or (Message.CharCode = VK_ESCAPE)) then
  begin
    if Message.CharCode = VK_RETURN then
      TakeSuggestion
    else
    begin
      HideList;
      if (FTarget <> nil) and FTarget.Showing and FTarget.CanFocus then
        FTarget.SetFocus;
    end;
    Message.Result := 1;
    Exit;
  end;
  inherited;
end;

function TAtlasSymbolPathDialog.Validate: Boolean;
begin
  Result := (Trim(FFrom.Text) <> '') and (Trim(FTo.Text) <> '');
  if Result then
    Exit;
  FMessage.Caption := TAtlasStrings.Text(TAtlasTextId.SymbolPathMissing);
  if Trim(FFrom.Text) = '' then
    ActiveControl := FFrom
  else
    ActiveControl := FTo;
end;

procedure TAtlasSymbolPathDialog.Accept;
begin
  HideList;
  if Validate then
    ModalResult := mrOk;
end;

procedure TAtlasSymbolPathDialog.SearchClick(Sender: TObject);
begin
  Accept;
end;

end.
