unit Atlas.UI.SymbolPath.Dialog;

// Eingabedialog „Weg zwischen Symbolen“ (#1117), reine VCL: zwei Felder
// „Von“ und „Nach“ mit Vervollständigung, „Höchstens Schritte“ (1–16) und
// „Alle gleich kurzen Wege“. Die Vorschläge beim Tippen (Symbole des
// Projekts, setzt die IDE-Schicht) zeigt TAtlasSymbolPathSuggestions in einer
// Liste unter dem Feld; Esc schließt erst die Liste, dann den Dialog. Ohne
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
  Vcl.Graphics,
  Atlas.UI.Foundation.Dialog,
  Atlas.UI.SymbolPath.Suggestions;

type
  TAtlasSymbolPathRequestInput = record
    From: string;
    To_: string;
    MaxSteps: Integer;
    All: Boolean;
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
    /// <summary>Vorschlagsliste der Felder „Von“ und „Nach“.</summary>
    FSuggestions: TAtlasSymbolPathSuggestions;
    procedure Typing(Sender: TObject);
    procedure SearchClick(Sender: TObject);
    /// <summary>Enter und Esc bei offener Vorschlagsliste: übernehmen bzw. Liste schließen, statt „Suchen“
    /// oder „Abbrechen“ auszulösen (die VCL fragt Standard- und Abbrechen-Knopf vor OnKeyDown).</summary>
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
    procedure Accept;
    function GetInput: TAtlasSymbolPathRequestInput;
    procedure SetInput(const AValue: TAtlasSymbolPathRequestInput);
    function GetSuggestionList: TListBox;
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
    property SuggestionList: TListBox read GetSuggestionList;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Atlas.UI.Analysis.Strings,
  Atlas.Core.Style.Signal,
  Atlas.UI.Foundation.Theme;

const
  cDefaultSteps = 8;
  cMaxSteps = 16;
  // Höhe der Vorschlagsliste bei 96 dpi.
  cSuggestionsHeight = 160;

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

function NewEdit(ADialog: TAtlasSymbolPathDialog; const ALayout: TDialogLayout; ATop: Integer;
  ASuggestions: TAtlasSymbolPathSuggestions): TEdit;
begin
  Result := TEdit.Create(ADialog);
  Result.Parent := ADialog;
  Result.Left := ALayout.Gap + ALayout.LabelWidth;
  Result.Top := ATop;
  Result.Width := ALayout.EditWidth;
  Result.TextHint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SymbolPathInputHint);
  ASuggestions.Attach(Result);
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
  ADialog.FSteps.OnEnter := ADialog.FSuggestions.ControlEnter;
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
  ADialog.FAll.OnEnter := ADialog.FSuggestions.ControlEnter;
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
  // Liste über den Feldern darunter, erst beim Tippen sichtbar.
  FSuggestions := TAtlasSymbolPathSuggestions.CreateIn(Self, ASuggest, mLayout.EditWidth,
    MulDiv(cSuggestionsHeight, CurrentPPI, 96));
  FSuggestions.OnTyping := Typing;
  mY := mLayout.Gap;
  FFrom := NewEdit(Self, mLayout, mY, FSuggestions);
  AddFieldLabel(Self, mLayout, TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.SymbolPathFrom), mY, FFrom);
  Inc(mY, FFrom.Height + mLayout.Spacing);
  FTo := NewEdit(Self, mLayout, mY, FSuggestions);
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
  FSuggestions.Fill(FFrom, AValue.From);
  FSuggestions.Fill(FTo, AValue.To_);
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

function TAtlasSymbolPathDialog.GetSuggestionList: TListBox;
begin
  Result := FSuggestions.List;
end;

procedure TAtlasSymbolPathDialog.Typing(Sender: TObject);
begin
  FMessage.Caption := '';
end;

procedure TAtlasSymbolPathDialog.SearchClick(Sender: TObject);
begin
  Accept;
end;

procedure TAtlasSymbolPathDialog.CMDialogKey(var Message: TCMDialogKey);
begin
  if FSuggestions.HandleDialogKey(Message.CharCode) then
  begin
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

procedure TAtlasSymbolPathDialog.Suggest(AEdit: TEdit);
begin
  FSuggestions.Show(AEdit);
end;

procedure TAtlasSymbolPathDialog.TakeSuggestion;
begin
  FSuggestions.Take;
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
