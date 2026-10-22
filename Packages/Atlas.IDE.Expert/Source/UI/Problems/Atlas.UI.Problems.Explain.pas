unit Atlas.UI.Problems.Explain;

// „Regel erklären“ (#909): Katalogtext einer Prüfregel aus dem Fenster
// „Atlas-Prüfung“. Oben Name und Kennung, bei experimentellen Regeln die
// Marke „Experimentell“ (#834), darunter die Beschreibung und die Beispiele
// falsch und richtig in Festbreitenschrift. Esc oder „Schließen“ schließt.
// Reine VCL; den Katalog liefert der Aufrufer.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls;

type
  /// <summary>Katalogtext einer Regel (atlas.server.settingsCatalog).</summary>
  TAtlasRuleExplanation = record
    Id: string;
    Name: string;
    Description: string;
    Bad: string;
    Good: string;
    Experimental: Boolean;
  end;

  TAtlasRuleExplainDialog = class(TForm)
  private
    FTitle: TLabel;
    FMark: TLabel;
    FDescription: TLabel;
    FBad: TMemo;
    FGood: TMemo;
    FClose: TButton;
    function AddLabel(const ACaption: string): TLabel;
    function AddExample(const AText: string): TMemo;
    procedure CloseClick(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent; const AExplanation: TAtlasRuleExplanation);
    class procedure Execute(const AExplanation: TAtlasRuleExplanation); static;
    property TitleLabel: TLabel read FTitle;
    property MarkLabel: TLabel read FMark;
    property DescriptionLabel: TLabel read FDescription;
    property BadMemo: TMemo read FBad;
    property GoodMemo: TMemo read FGood;
  end;

implementation

uses
  Vcl.Graphics,
  Atlas.UI.Strings;

const
  Gap = 8;
  DialogWidth = 560;

{ TAtlasRuleExplainDialog }

constructor TAtlasRuleExplainDialog.CreateDialog(AOwner: TComponent; const AExplanation: TAtlasRuleExplanation);
var
  Bottom: TPanel;
  Heading: TLabel;
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasStrings.Fmt(TAtlasTextId.ProblemsExplainTitle, [AExplanation.Id]);
  BorderStyle := bsSizeToolWin;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  KeyPreview := True;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);
  ClientHeight := ScaleValue(420);

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := ScaleValue(44);
  Bottom.BevelOuter := bvNone;
  Bottom.ShowCaption := False;
  FClose := TButton.Create(Self);
  FClose.Parent := Bottom;
  FClose.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsExplainClose);
  FClose.Width := ScaleValue(90);
  FClose.Height := ScaleValue(28);
  FClose.Top := ScaleValue(Gap);
  FClose.Left := Bottom.ClientWidth - FClose.Width - ScaleValue(Gap);
  FClose.Anchors := [akTop, akRight];
  FClose.Cancel := True;
  FClose.Default := True;
  FClose.OnClick := CloseClick;

  FTitle := AddLabel(AExplanation.Name);
  FTitle.Font.Style := [fsBold];
  if AExplanation.Name = '' then
    FTitle.Caption := AExplanation.Id;
  FMark := AddLabel(TAtlasStrings.Text(TAtlasTextId.ProblemsExperimental));
  FMark.Font.Color := $000080C0;
  FMark.Visible := AExplanation.Experimental;
  FDescription := AddLabel(AExplanation.Description);
  FDescription.WordWrap := True;
  if AExplanation.Bad <> '' then
  begin
    Heading := AddLabel(TAtlasStrings.Text(TAtlasTextId.ProblemsExplainBad));
    Heading.Font.Color := $003C3CD8;
    FBad := AddExample(AExplanation.Bad);
  end;
  if AExplanation.Good <> '' then
  begin
    Heading := AddLabel(TAtlasStrings.Text(TAtlasTextId.ProblemsExplainGood));
    Heading.Font.Color := $0050A030;
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
  Result.Margins.SetBounds(ScaleValue(Gap), ScaleValue(Gap div 2), ScaleValue(Gap), 0);
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
  Result.Margins.SetBounds(ScaleValue(Gap), ScaleValue(2), ScaleValue(Gap), 0);
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

class procedure TAtlasRuleExplainDialog.Execute(const AExplanation: TAtlasRuleExplanation);
var
  Dialog: TAtlasRuleExplainDialog;
begin
  Dialog := TAtlasRuleExplainDialog.CreateDialog(nil, AExplanation);
  try
    Dialog.ShowModal;
  finally
    Dialog.Free;
  end;
end;

end.
