unit Atlas.UI.Problems.Explain;

// „Regel erklären“ (#909): Katalogtext einer Prüfregel aus dem Fenster
// „Atlas-Prüfung“. Oben Name und Kennung, bei experimentellen Regeln die
// Marke „Experimentell“ (#834), darunter die Beschreibung und die Beispiele
// falsch und richtig in Festbreitenschrift. Esc oder „Schließen“ schließt.
// Compilermeldungen (#54): Titel „Meldung E2003“, nach der Beschreibung die
// typische Ursache, unten links „Im DocWiki öffnen“.
// Aufbau:
// - Die Knöpfe stehen in einer eigenen Leiste am unteren Rand (alBottom, Knöpfe
//   alLeft/alRight); der Text kann sie nicht überdecken.
// - Der Inhalt liegt in einer Rollfläche (alClient, nur senkrecht rollbar). Ihre
//   Elemente stapeln mit alTop; jedes bekommt vor Align und Parent eine Oberkante
//   unter dem bisher untersten, sonst ordnet die VCL gleiche Oberkanten beliebig
//   (die Überschrift „Richtig:“ fehlte).
// - Texte brechen über TAtlasWrapLabel bei jeder Breite neu um; ein TLabel
//   behielte die Höhe der Anfangsbreite und liefe unten aus dem Fenster.
// - Die Beispiele sind so hoch wie ihre Zeilen und rollen nur waagrecht, wenn
//   die längste Zeile nicht passt. Breite, DPI-Wechsel und Ziehen rechnen das
//   in ContentResize neu.
// - Die Anfangsgröße folgt dem Inhalt: breiter für lange Codezeilen, so hoch
//   wie der Text, höchstens ein Anteil des Arbeitsbereichs des Monitors.
// Reine VCL; den Katalog und das Öffnen von Links liefert der Aufrufer.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
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
    FContent: TScrollBox;
    FButtons: TPanel;
    FTitle: TLabel;
    FMark: TLabel;
    FDescription: TLabel;
    FCause: TLabel;
    FDocWiki: TButton;
    FUrl: string;
    FOpenUrl: TProc<string>;
    FBadHeading: TLabel;
    FBad: TMemo;
    FGoodHeading: TLabel;
    FGood: TMemo;
    FClose: TButton;
    FFitting: Boolean;
    /// <summary>Beschriftung unter dem bisher Untersten der Rollfläche; bricht mit der Breite um.</summary>
    function AddText(const ACaption: string): TLabel;
    /// <summary>Überschrift AHeading in AColor und darunter das Beispiel AText.</summary>
    function AddExample(const AHeading: string; AColor: TColor; const AText: string; out AHeadingLabel: TLabel): TMemo;
    /// <summary>Oberkante unter dem bisher untersten Element der Rollfläche.</summary>
    function ContentBottom: Integer;
    /// <summary>Leiste am unteren Rand: „Schließen“ rechts, „Im DocWiki öffnen“ links (#54, nur mit Link).</summary>
    procedure AddButtonBar;
    procedure DocWikiClick(Sender: TObject);
    procedure ContentResize(Sender: TObject);
    /// <summary>Anfangsgröße nach dem Inhalt, begrenzt auf den Arbeitsbereich; kleinste Größe festlegen.</summary>
    procedure FitToContent;
    /// <summary>Titel „Regel …“ bzw. „Meldung …“ (Compilermeldungen tragen einen DocWiki-Link, #54).</summary>
    class function TitleOf(const AExplanation: TAtlasRuleExplanation): string; static;
    /// <summary>Überschrift „Typische Ursache“ und ACause (#54), nur mit Ursache.</summary>
    procedure AddCause(const ACause: string);
  protected
    /// <summary>Mausrad über dem ganzen Fenster rollt den Inhalt, auch wenn ein Knopf den Fokus hat.</summary>
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
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
    /// <summary>Rollfläche mit Text und Beispielen.</summary>
    property Content: TScrollBox read FContent;
    /// <summary>Leiste mit „Schließen“ (und „Im DocWiki öffnen“) am unteren Rand.</summary>
    property ButtonBar: TPanel read FButtons;
    property BadHeading: TLabel read FBadHeading;
    property BadMemo: TMemo read FBad;
    property GoodHeading: TLabel read FGoodHeading;
    property GoodMemo: TMemo read FGood;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Graphics,
  Atlas.UI.Foundation.WrapLabel,
  Atlas.UI.Strings,
  Atlas.UI.Problems.Strings;

const
  cGap = 8;
  cDialogWidth = 560;
  cDialogMinWidth = 360;
  cDialogMinHeight = 220;
  cButtonBarHeight = 44;
  cCloseWidth = 90;
  cDocWikiWidth = 140;
  cCodeFont = 'Consolas';
  cCodeFontSize = 9;
  /// <summary>Rand und Innenabstand eines Beispiels oben und unten bzw. links und rechts, logische Pixel.</summary>
  cMemoChrome = 10;
  /// <summary>Höchstens dieser Anteil (Prozent) des Arbeitsbereichs als Anfangsgröße.</summary>
  cMaxScreenShare = 80;
  /// <summary>Zeilen je Rastung des Mausrads.</summary>
  cWheelLines = 3;
  cBadColor = $003C3CD8;
  cGoodColor = $0050A030;
  cMarkColor = $000080C0;

/// <summary>Breite der längsten Zeile und Zeilenhöhe eines Beispiels in Gerätepixeln (0 ohne Beispiel).</summary>
procedure MeasureCode(AMemo: TMemo; out AWidth, ALineHeight: Integer);
var
  mDC: HDC;
  mCanvas: TCanvas;
  mIndex: Integer;
begin
  AWidth := 0;
  ALineHeight := 0;
  if AMemo = nil then
  begin
    Exit;
  end;
  mDC := GetDC(0);
  mCanvas := TCanvas.Create;
  try
    mCanvas.Handle := mDC;
    mCanvas.Font := AMemo.Font;
    ALineHeight := mCanvas.TextHeight('Wg');
    for mIndex := 0 to AMemo.Lines.Count - 1 do
    begin
      AWidth := Max(AWidth, mCanvas.TextWidth(AMemo.Lines[mIndex]));
    end;
  finally
    mCanvas.Handle := 0;
    mCanvas.Free;
    ReleaseDC(0, mDC);
  end;
end;

/// <summary>Höhe und waagrechte Rollleiste eines Beispiels nach Zeilen, längster Zeile und Breite.</summary>
procedure FitCode(AMemo: TMemo);
var
  mWidth, mLineHeight, mHeight, mChrome: Integer;
  mScrollBars: TScrollStyle;
begin
  if AMemo = nil then
  begin
    Exit;
  end;
  MeasureCode(AMemo, mWidth, mLineHeight);
  mChrome := MulDiv(cMemoChrome, AMemo.CurrentPPI, 96);
  mHeight := Max(1, AMemo.Lines.Count) * mLineHeight + mChrome;
  mScrollBars := ssNone;
  if mWidth > AMemo.Width - mChrome then
  begin
    mScrollBars := ssHorizontal;
    mHeight := mHeight + MulDiv(GetSystemMetrics(SM_CYHSCROLL), AMemo.CurrentPPI, Screen.PixelsPerInch);
  end;
  if AMemo.ScrollBars <> mScrollBars then
  begin
    AMemo.ScrollBars := mScrollBars;
  end;
  AMemo.Height := mHeight;
end;

{ TAtlasRuleExplainDialog }

constructor TAtlasRuleExplainDialog.CreateDialog(AOwner: TComponent; const AExplanation: TAtlasRuleExplanation);
begin
  inherited CreateDialog(AOwner, TitleOf(AExplanation), cDialogWidth);
  FUrl := AExplanation.DocWiki;
  BorderStyle := bsSizeToolWin;
  BorderIcons := [biSystemMenu];
  KeyPreview := True;
  ClientHeight := ScaleValue(420);
  AddButtonBar;

  FContent := TScrollBox.Create(Self);
  FContent.BorderStyle := bsNone;
  FContent.ParentColor := True;
  FContent.HorzScrollBar.Visible := False;
  FContent.VertScrollBar.Tracking := True;
  FContent.Align := alClient;
  FContent.Parent := Self;

  FTitle := AddText(AExplanation.Name);
  FTitle.Font.Style := [fsBold];
  if AExplanation.Name = '' then
  begin
    FTitle.Caption := AExplanation.Id;
  end;
  FMark := AddText(TAtlasStrings.Text(TAtlasTextId.ProblemsExperimental));
  FMark.Font.Color := cMarkColor;
  FMark.Visible := AExplanation.Experimental;
  FDescription := AddText(AExplanation.Description);
  AddCause(AExplanation.Cause);
  if AExplanation.Bad <> '' then
  begin
    FBad := AddExample(TAtlasStrings.Text(TAtlasTextId.ProblemsExplainBad), cBadColor, AExplanation.Bad, FBadHeading);
  end;
  if AExplanation.Good <> '' then
  begin
    FGood := AddExample(TAtlasStrings.Text(TAtlasTextId.ProblemsExplainGood), cGoodColor, AExplanation.Good,
      FGoodHeading);
  end;
  FContent.OnResize := ContentResize;
  FitToContent;
  ActiveControl := FClose;
end;

procedure TAtlasRuleExplainDialog.AddButtonBar;
begin
  FButtons := TPanel.Create(Self);
  // Lage vor Align und Parent, siehe AddText.
  FButtons.Top := ClientHeight;
  FButtons.Height := ScaleValue(cButtonBarHeight);
  FButtons.BevelOuter := bvNone;
  FButtons.ShowCaption := False;
  FButtons.Align := alBottom;
  FButtons.Parent := Self;
  FClose := TButton.Create(Self);
  FClose.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsExplainClose);
  FClose.Width := ScaleValue(cCloseWidth);
  FClose.AlignWithMargins := True;
  FClose.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap));
  FClose.Align := alRight;
  FClose.Parent := FButtons;
  FClose.Cancel := True;
  FClose.Default := True;
  FClose.ModalResult := mrOk;
  if FUrl = '' then
  begin
    Exit;
  end;
  FDocWiki := TButton.Create(Self);
  FDocWiki.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsExplainDocWiki);
  FDocWiki.Width := ScaleValue(cDocWikiWidth);
  FDocWiki.AlignWithMargins := True;
  FDocWiki.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap), ScaleValue(cGap));
  FDocWiki.Align := alLeft;
  FDocWiki.Parent := FButtons;
  FDocWiki.OnClick := DocWikiClick;
end;

function TAtlasRuleExplainDialog.ContentBottom: Integer;
var
  mIndex: Integer;
  mControl: TControl;
begin
  Result := 0;
  for mIndex := 0 to FContent.ControlCount - 1 do
  begin
    mControl := FContent.Controls[mIndex];
    Result := Max(Result, mControl.Top + mControl.Height + mControl.Margins.Bottom + 1);
  end;
end;

function TAtlasRuleExplainDialog.AddText(const ACaption: string): TLabel;
begin
  Result := TAtlasWrapLabel.Create(Self);
  // Lage vor Align und Parent: alTop ordnet nach der Oberkante, gleiche Oberkanten in beliebiger Reihenfolge.
  Result.Top := ContentBottom;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(cGap), ScaleValue(cGap div 2), ScaleValue(cGap), 0);
  Result.Caption := ACaption;
  Result.Align := alTop;
  Result.Parent := FContent;
end;

function TAtlasRuleExplainDialog.AddExample(const AHeading: string; AColor: TColor; const AText: string;
  out AHeadingLabel: TLabel): TMemo;
begin
  AHeadingLabel := AddText(AHeading);
  AHeadingLabel.Font.Color := AColor;
  Result := TMemo.Create(Self);
  Result.Top := ContentBottom;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(cGap), ScaleValue(2), ScaleValue(cGap), 0);
  Result.ReadOnly := True;
  Result.ScrollBars := ssNone;
  Result.WordWrap := False;
  Result.Font.Name := cCodeFont;
  Result.Font.Size := cCodeFontSize;
  Result.Align := alTop;
  Result.Parent := FContent;
  Result.Lines.Text := AText;
  FitCode(Result);
end;

procedure TAtlasRuleExplainDialog.ContentResize(Sender: TObject);
begin
  // Neue Höhe der Beispiele kann die senkrechte Rollleiste ein- oder ausblenden und damit die Breite wieder ändern.
  if FFitting then
  begin
    Exit;
  end;
  FFitting := True;
  try
    FitCode(FBad);
    FitCode(FGood);
  finally
    FFitting := False;
  end;
end;

procedure TAtlasRuleExplainDialog.FitToContent;
var
  mArea: TRect;
  mBad, mGood, mLineHeight, mCodeWidth, mWidth, mHeight, mPass: Integer;
begin
  mArea := MainFormWorkArea;
  // Breiter, damit die längste Codezeile ohne Rollen passt; Rand, Rollleiste und Rahmen dazu.
  MeasureCode(FBad, mBad, mLineHeight);
  MeasureCode(FGood, mGood, mLineHeight);
  mCodeWidth := Max(mBad, mGood) + ScaleValue(2 * cGap + cMemoChrome) +
    MulDiv(GetSystemMetrics(SM_CXVSCROLL), CurrentPPI, Screen.PixelsPerInch);
  mWidth := Min(Max(ClientWidth, mCodeWidth), mArea.Width * cMaxScreenShare div 100);
  ClientWidth := Max(mWidth, ScaleValue(cDialogMinWidth));
  // Ohne Fenster ordnet die VCL nicht an: Breiten und damit Umbruch und Höhen wären die vorläufigen.
  HandleNeeded;
  Realign;
  ContentResize(nil);
  // Zweimal: Fällt mit der neuen Höhe die Rollleiste weg, wird der Inhalt breiter und damit niedriger.
  for mPass := 1 to 2 do
  begin
    mHeight := ContentBottom + ScaleValue(cGap) + FButtons.Height;
    ClientHeight := Max(Min(mHeight, mArea.Height * cMaxScreenShare div 100), ScaleValue(cDialogMinHeight));
  end;
  Constraints.MinWidth := Width - ClientWidth + ScaleValue(cDialogMinWidth);
  Constraints.MinHeight := Height - ClientHeight + ScaleValue(cDialogMinHeight);
end;

function TAtlasRuleExplainDialog.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  mStep: Integer;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result or (FContent = nil) then
  begin
    Exit;
  end;
  mStep := Canvas.TextHeight('Wg') * cWheelLines;
  FContent.VertScrollBar.Position := FContent.VertScrollBar.Position - (WheelDelta div WHEEL_DELTA) * mStep;
  Result := True;
end;

procedure TAtlasRuleExplainDialog.DocWikiClick(Sender: TObject);
begin
  if Assigned(FOpenUrl) then
  begin
    FOpenUrl(FUrl);
  end;
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

procedure TAtlasRuleExplainDialog.AddCause(const ACause: string);
var
  mHeading: TLabel;
begin
  if ACause = '' then
  begin
    Exit;
  end;
  mHeading := AddText(TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsExplainCause));
  mHeading.Font.Style := [fsBold];
  FCause := AddText(ACause);
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
