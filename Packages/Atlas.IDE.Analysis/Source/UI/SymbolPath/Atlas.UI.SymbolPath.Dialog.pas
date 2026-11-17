unit Atlas.UI.SymbolPath.Dialog;

// Eingabedialog „Weg zwischen Symbolen“ (#1117), reine VCL: zwei Felder
// „Von“ und „Nach“ mit Vervollständigung, „Höchstens Schritte“ (1–16) und
// „Alle gleich kurzen Wege“. Beim Tippen fragt der Dialog nach kurzer Pause
// OnSuggest (Symbole des Projekts, setzt die IDE-Schicht) und zeigt die
// Vorschläge in einer Liste unter dem Feld: ↓ geht in die Liste, Enter oder
// Doppelklick übernimmt, Esc schließt erst die Liste, dann den Dialog. Die
// Liste mit Pause und Übernahme hält TAtlasSymbolPathSuggestions. Ohne
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
  Vcl.Graphics,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Vorschläge zu einem Teil eines Namens; leer = keine.</summary>
  TAtlasSymbolPathSuggest = reference to function(const APattern: string): TArray<string>;

  TAtlasSymbolPathRequestInput = record
    From: string;
    To_: string;
    MaxSteps: Integer;
    All: Boolean;
  end;

  /// <summary>Vorschlagsliste unter einem Feld: holt nach kurzer Pause die Vorschläge, ↓ geht in die
  /// Liste, ↑ in der ersten Zeile zurück ins Feld, Doppelklick übernimmt.</summary>
  TAtlasSymbolPathSuggestions = class(TComponent)
  private
    FList: TListBox;
    FTimer: TTimer;
    /// <summary>Feld, zu dem die Liste gehört bzw. das zuletzt getippt wurde.</summary>
    FTarget: TEdit;
    FSuggest: TAtlasSymbolPathSuggest;
    FFilling: Boolean;
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListDblClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure FocusTarget;
  public
    /// <summary>Liste auf AParent (erst beim Tippen sichtbar) mit Breite AWidth.</summary>
    constructor CreateFor(AParent: TWinControl; AWidth: Integer; const ASuggest: TAtlasSymbolPathSuggest);
    /// <summary>In AEdit wurde getippt: nach der Pause Vorschläge holen.</summary>
    procedure Edited(AEdit: TEdit);
    /// <summary>Vorschläge für AEdit sofort holen und zeigen (ohne Pause; auch für Tests).</summary>
    procedure Show(AEdit: TEdit);
    /// <summary>Gewählten Vorschlag ins Feld übernehmen.</summary>
    procedure Take;
    procedure Hide;
    /// <summary>Liste schließen und zurück ins Feld.</summary>
    procedure Close;
    /// <summary>↓ im Feld der Liste geht in die Liste.</summary>
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function Visible: Boolean;
    property Target: TEdit read FTarget;
    /// <summary>Gerade wird ein Vorschlag ins Feld geschrieben (kein neues Tippen).</summary>
    property Filling: Boolean read FFilling;
    property List: TListBox read FList;
  end;

  TAtlasSymbolPathDialog = class(TAtlasDialog)
  private
    FFrom: TEdit;
    FTo: TEdit;
    FSteps: TEdit;
    FStepsUpDown: TUpDown;
    FAll: TCheckBox;
    FMessage: TLabel;
    FSearch: TButton;
    FCancel: TButton;
    FSuggestions: TAtlasSymbolPathSuggestions;
    FFilling: Boolean;
    procedure EditChange(Sender: TObject);
    procedure ControlEnter(Sender: TObject);
    procedure SearchClick(Sender: TObject);
    /// <summary>Enter und Esc bei offener Vorschlagsliste: übernehmen bzw. Liste schließen, statt „Suchen“
    /// oder „Abbrechen“ auszulösen (die VCL fragt Standard- und Abbrechen-Knopf vor OnKeyDown).</summary>
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    procedure Accept;
    function GetInput: TAtlasSymbolPathRequestInput;
    procedure SetInput(const AValue: TAtlasSymbolPathRequestInput);
  public
    constructor CreateDialog(AOwner: TComponent; const ASuggest: TAtlasSymbolPathSuggest);
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
    property Suggestions: TAtlasSymbolPathSuggestions read FSuggestions;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Atlas.UI.Analysis.Strings,
  Atlas.Core.Style.Signal,
  Atlas.UI.Foundation.Theme;

const
  /// <summary>Pause nach dem letzten Tastendruck, bevor Vorschläge geholt werden.</summary>
  cSuggestDelayMs = 250;
  cMaxSuggestions = 12;
  cDefaultSteps = 8;
  cMaxSteps = 16;
  /// <summary>Höhe der Vorschlagsliste bei 96 dpi.</summary>
  cListHeight96 = 160;

{ TAtlasSymbolPathDialog }

type
  /// <summary>Abstände des Dialogs in Bildpunkten (nach CurrentPPI).</summary>
  TDialogLayout = record
    Gap: Integer;
    LabelWidth: Integer;
    EditWidth: Integer;
    /// <summary>Abstand zwischen zwei Zeilen.</summary>
    Spacing: Integer;
  end;

function LayoutOf(ADialog: TAtlasSymbolPathDialog): TDialogLayout;
begin
  Result.Gap := MulDiv(12, ADialog.CurrentPPI, 96);
  Result.LabelWidth := MulDiv(130, ADialog.CurrentPPI, 96);
  Result.EditWidth := MulDiv(360, ADialog.CurrentPPI, 96);
  Result.Spacing := MulDiv(8, ADialog.CurrentPPI, 96);
end;

// Nicht "AddLabel": Im Konstruktor verdeckt die geerbte Methode AddLabel des Dialogs den Namen (E2010/E2034).
function AddFieldLabel(ADialog: TAtlasSymbolPathDialog; const ALayout: TDialogLayout; const AText: string;
  ATop: Integer; AFocus: TWinControl): TLabel;
begin
  Result := TLabel.Create(ADialog);
  Result.Parent := ADialog;
  Result.Left := ALayout.Gap;
  Result.Top := ATop + MulDiv(3, ADialog.CurrentPPI, 96);
  Result.Caption := AText;
  Result.FocusControl := AFocus;
end;

function NewEdit(ADialog: TAtlasSymbolPathDialog; const ALayout: TDialogLayout; ATop: Integer): TEdit;
begin
  Result := TEdit.Create(ADialog);
  Result.Parent := ADialog;
  Result.Left := ALayout.Gap + ALayout.LabelWidth;
  Result.Top := ATop;
  Result.Width := ALayout.EditWidth;
  Result.TextHint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SymbolPathInputHint);
  Result.OnChange := ADialog.EditChange;
  Result.OnKeyDown := ADialog.FSuggestions.EditKeyDown;
  Result.OnEnter := ADialog.ControlEnter;
end;

/// <summary>„Höchstens Schritte“ mit Drehfeld und „Alle gleich kurzen Wege“ ab AY; AY steht danach darunter.</summary>
procedure BuildOptions(ADialog: TAtlasSymbolPathDialog; const ALayout: TDialogLayout; var AY: Integer);
begin
  ADialog.FSteps := TEdit.Create(ADialog);
  ADialog.FSteps.Parent := ADialog;
  ADialog.FSteps.Left := ALayout.Gap + ALayout.LabelWidth;
  ADialog.FSteps.Top := AY;
  ADialog.FSteps.Width := MulDiv(50, ADialog.CurrentPPI, 96);
  ADialog.FSteps.NumbersOnly := True;
  ADialog.FSteps.OnEnter := ADialog.ControlEnter;
  ADialog.FStepsUpDown := TUpDown.Create(ADialog);
  ADialog.FStepsUpDown.Parent := ADialog;
  ADialog.FStepsUpDown.Associate := ADialog.FSteps;
  ADialog.FStepsUpDown.Min := 1;
  ADialog.FStepsUpDown.Max := cMaxSteps;
  ADialog.FStepsUpDown.Position := cDefaultSteps;
  AddFieldLabel(ADialog, ALayout, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SymbolPathMaxSteps), AY,
    ADialog.FSteps);
  Inc(AY, ADialog.FSteps.Height + ALayout.Spacing);
  ADialog.FAll := TCheckBox.Create(ADialog);
  ADialog.FAll.Parent := ADialog;
  ADialog.FAll.Left := ALayout.Gap + ALayout.LabelWidth;
  ADialog.FAll.Top := AY;
  ADialog.FAll.Width := ALayout.EditWidth;
  ADialog.FAll.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SymbolPathAll);
  ADialog.FAll.OnEnter := ADialog.ControlEnter;
  Inc(AY, ADialog.FAll.Height + ALayout.Spacing);
end;

/// <summary>Meldungszeile und die Knöpfe „Suchen“ und „Abbrechen“ ab AY; danach die Höhe des Dialogs.</summary>
procedure BuildButtons(ADialog: TAtlasSymbolPathDialog; const ALayout: TDialogLayout; AY: Integer);
begin
  ADialog.FMessage := TLabel.Create(ADialog);
  ADialog.FMessage.Parent := ADialog;
  ADialog.FMessage.Left := ALayout.Gap;
  ADialog.FMessage.Top := AY;
  ADialog.FMessage.Font.Color := TAtlasUiTheme.TextColor(TAtlasSignalKind.Error);
  // Mit seFont übergeht der Stil Font.Color.
  ADialog.FMessage.StyleElements := ADialog.FMessage.StyleElements - [seFont];
  ADialog.FMessage.ShowAccelChar := False;
  Inc(AY, ADialog.FMessage.Height + ALayout.Spacing);
  ADialog.FCancel := TButton.Create(ADialog);
  ADialog.FCancel.Parent := ADialog;
  ADialog.FCancel.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SymbolPathCancel);
  ADialog.FCancel.Cancel := True;
  ADialog.FCancel.ModalResult := mrCancel;
  ADialog.FCancel.Top := AY;
  ADialog.FCancel.Left := ADialog.ClientWidth - ALayout.Gap - ADialog.FCancel.Width;
  ADialog.FSearch := TButton.Create(ADialog);
  ADialog.FSearch.Parent := ADialog;
  ADialog.FSearch.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SymbolPathSearch);
  ADialog.FSearch.Default := True;
  ADialog.FSearch.Top := AY;
  ADialog.FSearch.Left := ADialog.FCancel.Left - ALayout.Spacing - ADialog.FSearch.Width;
  ADialog.FSearch.OnClick := ADialog.SearchClick;
  ADialog.ClientHeight := AY + ADialog.FSearch.Height + ALayout.Gap;
end;

{ TAtlasSymbolPathSuggestions }

constructor TAtlasSymbolPathSuggestions.CreateFor(AParent: TWinControl; AWidth: Integer;
  const ASuggest: TAtlasSymbolPathSuggest);
begin
  inherited Create(AParent);
  FSuggest := ASuggest;
  FList := TListBox.Create(Self);
  FList.Parent := AParent;
  FList.Visible := False;
  FList.Width := AWidth;
  FList.Height := MulDiv(cListHeight96, AParent.CurrentPPI, 96);
  FList.OnKeyDown := ListKeyDown;
  FList.OnDblClick := ListDblClick;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := cSuggestDelayMs;
  FTimer.OnTimer := TimerTick;
end;

procedure TAtlasSymbolPathSuggestions.Edited(AEdit: TEdit);
begin
  FTarget := AEdit;
  FTimer.Enabled := False;
  FTimer.Enabled := Assigned(FSuggest);
end;

procedure TAtlasSymbolPathSuggestions.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if not FList.Visible or (Sender <> FTarget) then
  begin
    Exit;
  end;
  case Key of
    VK_DOWN:
      begin
        if FList.Showing and FList.CanFocus then
        begin
          FList.SetFocus;
        end;
        Key := 0;
      end;
  end;
end;

procedure TAtlasSymbolPathSuggestions.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
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

procedure TAtlasSymbolPathSuggestions.ListDblClick(Sender: TObject);
begin
  Take;
end;

procedure TAtlasSymbolPathSuggestions.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  if FTarget <> nil then
  begin
    Show(FTarget);
  end;
end;

procedure TAtlasSymbolPathSuggestions.FocusTarget;
begin
  if (FTarget <> nil) and FTarget.Showing and FTarget.CanFocus then
  begin
    FTarget.SetFocus;
  end;
end;

procedure TAtlasSymbolPathSuggestions.Show(AEdit: TEdit);
var
  mItems: TArray<string>;
  mItem: string;
begin
  FTarget := AEdit;
  mItems := nil;
  if Assigned(FSuggest) and (Trim(AEdit.Text) <> '') then
  begin
    mItems := FSuggest(Trim(AEdit.Text));
  end;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mItem in mItems do
    begin
      if FList.Items.Count >= cMaxSuggestions then
      begin
        Break;
      end;
      if FList.Items.IndexOf(mItem) < 0 then
      begin
        FList.Items.Add(mItem);
      end;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count = 0 then
  begin
    Hide;
    Exit;
  end;
  FList.Left := AEdit.Left;
  FList.Top := AEdit.Top + AEdit.Height;
  FList.Width := AEdit.Width;
  FList.ItemIndex := 0;
  FList.Visible := True;
  FList.BringToFront;
end;

procedure TAtlasSymbolPathSuggestions.Take;
begin
  if (FTarget = nil) or not FList.Visible or (FList.ItemIndex < 0) then
  begin
    Exit;
  end;
  FFilling := True;
  try
    FTarget.Text := FList.Items[FList.ItemIndex];
    FTarget.SelStart := Length(FTarget.Text);
  finally
    FFilling := False;
  end;
  Hide;
  FocusTarget;
end;

procedure TAtlasSymbolPathSuggestions.Hide;
begin
  FList.Visible := False;
end;

procedure TAtlasSymbolPathSuggestions.Close;
begin
  Hide;
  FocusTarget;
end;

function TAtlasSymbolPathSuggestions.Visible: Boolean;
begin
  Result := FList.Visible;
end;

{ TAtlasSymbolPathDialog }

constructor TAtlasSymbolPathDialog.CreateDialog(AOwner: TComponent; const ASuggest: TAtlasSymbolPathSuggest);
var
  mLayout: TDialogLayout;
  mY: Integer;
begin
  inherited CreateDialog(AOwner, '', 0);
  Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SymbolPathCaption);
  mLayout := LayoutOf(Self);
  ClientWidth := mLayout.Gap * 2 + mLayout.LabelWidth + mLayout.EditWidth;
  // Vor den Feldern: deren Tasten gehen an die Liste.
  FSuggestions := TAtlasSymbolPathSuggestions.CreateFor(Self, mLayout.EditWidth, ASuggest);
  mY := mLayout.Gap;
  FFrom := NewEdit(Self, mLayout, mY);
  AddFieldLabel(Self, mLayout, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SymbolPathFrom), mY, FFrom);
  Inc(mY, FFrom.Height + mLayout.Spacing);
  FTo := NewEdit(Self, mLayout, mY);
  AddFieldLabel(Self, mLayout, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SymbolPathTo), mY, FTo);
  Inc(mY, FTo.Height + mLayout.Spacing);
  BuildOptions(Self, mLayout, mY);
  BuildButtons(Self, mLayout, mY);
  ActiveControl := FFrom;
end;

function TAtlasSymbolPathDialog.GetInput: TAtlasSymbolPathRequestInput;
begin
  Result.From := Trim(FFrom.Text);
  Result.To_ := Trim(FTo.Text);
  Result.MaxSteps := EnsureRange(StrToIntDef(FSteps.Text, cDefaultSteps), 1, cMaxSteps);
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
  if (AValue.MaxSteps >= 1) and (AValue.MaxSteps <= cMaxSteps) then
  begin
    FStepsUpDown.Position := AValue.MaxSteps;
  end
  else
  begin
    FStepsUpDown.Position := cDefaultSteps;
  end;
  // Ohne Fenster schreibt TUpDown nicht ins verbundene Feld; GetInput liest das Feld.
  FSteps.Text := IntToStr(FStepsUpDown.Position);
  FAll.Checked := AValue.All;
end;

procedure TAtlasSymbolPathDialog.EditChange(Sender: TObject);
begin
  if FFilling or FSuggestions.Filling or not (Sender is TEdit) then
  begin
    Exit;
  end;
  FMessage.Caption := '';
  FSuggestions.Edited(TEdit(Sender));
end;

procedure TAtlasSymbolPathDialog.ControlEnter(Sender: TObject);
begin
  // Ein anderes Feld: die Liste gehört nicht dazu und verdeckte es sonst.
  if Sender <> FSuggestions.Target then
  begin
    FSuggestions.Hide;
  end;
end;

procedure TAtlasSymbolPathDialog.SearchClick(Sender: TObject);
begin
  Accept;
end;

procedure TAtlasSymbolPathDialog.CMDialogKey(var Message: TCMDialogKey);
begin
  if FSuggestions.Visible and ((Message.CharCode = VK_RETURN) or (Message.CharCode = VK_ESCAPE)) then
  begin
    if Message.CharCode = VK_RETURN then
    begin
      FSuggestions.Take;
    end
    else
    begin
      FSuggestions.Close;
    end;
    Message.Result := 1;
    Exit;
  end;
  inherited;
end;

procedure TAtlasSymbolPathDialog.Accept;
begin
  FSuggestions.Hide;
  if Validate then
  begin
    ModalResult := mrOk;
  end;
end;

function TAtlasSymbolPathDialog.Validate: Boolean;
begin
  Result := (Trim(FFrom.Text) <> '') and (Trim(FTo.Text) <> '');
  if Result then
  begin
    Exit;
  end;
  FMessage.Caption := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SymbolPathMissing);
  if Trim(FFrom.Text) = '' then
  begin
    ActiveControl := FFrom;
  end
  else
  begin
    ActiveControl := FTo;
  end;
end;

class function TAtlasSymbolPathDialog.Execute(const ASuggest: TAtlasSymbolPathSuggest;
  var AInput: TAtlasSymbolPathRequestInput): Boolean;
var
  mDialog: TAtlasSymbolPathDialog;
begin
  mDialog := TAtlasSymbolPathDialog.CreateDialog(Application, ASuggest);
  try
    mDialog.Input := AInput;
    // Von schon gefüllt („Weg von hier nach …“): gleich ins Ziel.
    if mDialog.FFrom.Text <> '' then
    begin
      mDialog.ActiveControl := mDialog.FTo;
    end;
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AInput := mDialog.Input;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
