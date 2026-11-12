unit Atlas.UI.Problems.Explain;

// „Regel erklären“ (#909): Katalogtext einer Prüfregel aus dem Fenster
// „Atlas-Prüfung“. Oben Name und Kennung, bei experimentellen Regeln die
// Marke „Experimentell“ (#834), darunter die Beschreibung und die Beispiele
// falsch und richtig in Festbreitenschrift. Esc oder „Schließen“ schließt.
// Compilermeldungen (#54): Titel „Meldung E2003“, nach der Beschreibung die
// typische Ursache, unten links „Im DocWiki öffnen“.
// Reine VCL; den Katalog und das Öffnen von Links liefert der Aufrufer.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Problems.Explanation,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Katalogtext einer Regel (Atlas.Core.Problems.Explanation).</summary>
  TAtlasRuleExplanation = Atlas.Core.Problems.Explanation.TAtlasRuleExplanation;

  TAtlasRuleExplainDialog = class(TAtlasDialog)
  private
    FTitle: TLabel;
    FMark: TLabel;
    FDescription: TLabel;
    FCause: TLabel;
    FDocWiki: TButton;
    FUrl: string;
    FOpenUrl: TProc<string>;
    FBad: TMemo;
    FGood: TMemo;
    FClose: TButton;
    function AddLabel(const ACaption: string): TLabel;
    function AddExample(const AText: string): TMemo;
    procedure CloseClick(Sender: TObject);
    procedure DocWikiClick(Sender: TObject);
    /// <summary>Titel „Regel …“ bzw. „Meldung …“ (Compilermeldungen tragen einen DocWiki-Link, #54).</summary>
    class function TitleOf(const AExplanation: TAtlasRuleExplanation): string; static;
    /// <summary>„Im DocWiki öffnen“ links in ABottom (#54), nur mit Link.</summary>
    procedure AddDocWiki(ABottom: TWinControl);
    /// <summary>Überschrift „Typische Ursache“ und ACause (#54), nur mit Ursache.</summary>
    procedure AddCause(const ACause: string);
  public
    constructor CreateDialog(AOwner: TComponent; const AExplanation: TAtlasRuleExplanation);
    /// <summary>Dialog zeigen; AOpenUrl öffnet den DocWiki-Link (#54).</summary>
    class procedure Execute(const AExplanation: TAtlasRuleExplanation; const AOpenUrl: TProc<string>); static;
    property TitleLabel: TLabel read FTitle;
    property MarkLabel: TLabel read FMark;
    property DescriptionLabel: TLabel read FDescription;
    /// <summary>Typische Ursache einer Compilermeldung (#54); nil ohne.</summary>
    property CauseLabel: TLabel read FCause;
    /// <summary>„Im DocWiki öffnen“ (#54); nil ohne Link.</summary>
    property DocWikiButton: TButton read FDocWiki;
    /// <summary>Öffnet den DocWiki-Link (#54); ohne Zuweisung tut der Knopf nichts.</summary>
    property OpenUrl: TProc<string> read FOpenUrl write FOpenUrl;
    property BadMemo: TMemo read FBad;
    property GoodMemo: TMemo read FGood;
  end;

implementation

uses
  Vcl.Graphics,
  Atlas.UI.Strings,
  Atlas.UI.Problems.Strings;

const
  cGap = 8;
  cDialogWidth = 560;
  cButtonHeight = 28;
  cDocWikiWidth = 140;

{ TAtlasRuleExplainDialog }

constructor TAtlasRuleExplainDialog.CreateDialog(AOwner: TComponent; const AExplanation: TAtlasRuleExplanation);
var
  mBottom: TPanel;
  mHeading: TLabel;
begin
  inherited CreateDialog(AOwner, TitleOf(AExplanation), cDialogWidth);
  FUrl := AExplanation.DocWiki;
  BorderStyle := bsSizeToolWin;
  BorderIcons := [biSystemMenu];
  KeyPreview := True;
  ClientHeight := ScaleValue(420);

  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := ScaleValue(44);
  mBottom.BevelOuter := bvNone;
  mBottom.ShowCaption := False;
  FClose := TButton.Create(Self);
  FClose.Parent := mBottom;
  FClose.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsExplainClose);
  FClose.Width := ScaleValue(90);
  FClose.Height := ScaleValue(28);
  FClose.Top := ScaleValue(cGap);
  FClose.Left := mBottom.ClientWidth - FClose.Width - ScaleValue(cGap);
  FClose.Anchors := [akTop, akRight];
  FClose.Cancel := True;
  FClose.Default := True;
  FClose.OnClick := CloseClick;
  AddDocWiki(mBottom);

  FTitle := AddLabel(AExplanation.Name);
  FTitle.Font.Style := [fsBold];
  if AExplanation.Name = '' then
  begin
    FTitle.Caption := AExplanation.Id;
  end;
  FMark := AddLabel(TAtlasStrings.Text(TAtlasTextId.ProblemsExperimental));
  FMark.Font.Color := $000080C0;
  FMark.Visible := AExplanation.Experimental;
  FDescription := AddLabel(AExplanation.Description);
  FDescription.WordWrap := True;
  AddCause(AExplanation.Cause);
  if AExplanation.Bad <> '' then
  begin
    mHeading := AddLabel(TAtlasStrings.Text(TAtlasTextId.ProblemsExplainBad));
    mHeading.Font.Color := $003C3CD8;
    FBad := AddExample(AExplanation.Bad);
  end;
  if AExplanation.Good <> '' then
  begin
    mHeading := AddLabel(TAtlasStrings.Text(TAtlasTextId.ProblemsExplainGood));
    mHeading.Font.Color := $0050A030;
    FGood := AddExample(AExplanation.Good);
  end;
  ActiveControl := FClose;
end;

function TAtlasRuleExplainDialog.AddLabel(const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap div 2), ScaleValue(cGap), 0);
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
  // Unter die bisherigen: alTop ordnet nach Top.
  Result.Top := ClientHeight;
end;

function TAtlasRuleExplainDialog.AddExample(const AText: string): TMemo;
begin
  Result := TMemo.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(cGap), ScaleValue(2), ScaleValue(cGap), 0);
  Result.ReadOnly := True;
  Result.ScrollBars := ssBoth;
  Result.WordWrap := False;
  Result.Font.Name := 'Consolas';
  Result.Font.Size := 9;
  Result.Height := ScaleValue(96);
  Result.Lines.Text := AText;
  Result.Top := ClientHeight;
end;

procedure TAtlasRuleExplainDialog.CloseClick(Sender: TObject);
begin
  ModalResult := mrOk;
end;

class function TAtlasRuleExplainDialog.TitleOf(const AExplanation: TAtlasRuleExplanation): string;
begin
  if AExplanation.DocWiki <> '' then
  begin
    Result := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsExplainMessageTitle, [AExplanation.Id]);
  end
  else
  begin
    Result := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsExplainTitle, [AExplanation.Id]);
  end;
end;

procedure TAtlasRuleExplainDialog.AddDocWiki(ABottom: TWinControl);
begin
  if FUrl = '' then
  begin
    Exit;
  end;
  FDocWiki := TButton.Create(Self);
  FDocWiki.Parent := ABottom;
  FDocWiki.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsExplainDocWiki);
  FDocWiki.Width := ScaleValue(cDocWikiWidth);
  FDocWiki.Height := ScaleValue(cButtonHeight);
  FDocWiki.Top := ScaleValue(cGap);
  FDocWiki.Left := ScaleValue(cGap);
  FDocWiki.OnClick := DocWikiClick;
end;

procedure TAtlasRuleExplainDialog.AddCause(const ACause: string);
var
  mHeading: TLabel;
begin
  if ACause = '' then
  begin
    Exit;
  end;
  mHeading := AddLabel(TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsExplainCause));
  mHeading.Font.Style := [fsBold];
  FCause := AddLabel(ACause);
  FCause.WordWrap := True;
end;

procedure TAtlasRuleExplainDialog.DocWikiClick(Sender: TObject);
begin
  if Assigned(FOpenUrl) then
  begin
    FOpenUrl(FUrl);
  end;
end;

class procedure TAtlasRuleExplainDialog.Execute(const AExplanation: TAtlasRuleExplanation;
  const AOpenUrl: TProc<string>);
var
  mDialog: TAtlasRuleExplainDialog;
begin
  mDialog := TAtlasRuleExplainDialog.CreateDialog(nil, AExplanation);
  mDialog.OpenUrl := AOpenUrl;
  try
    mDialog.ShowModal;
  finally
    mDialog.Free;
  end;
end;

end.
