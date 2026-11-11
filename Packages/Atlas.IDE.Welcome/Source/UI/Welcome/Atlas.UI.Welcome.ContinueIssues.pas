unit Atlas.UI.Welcome.ContinueIssues;

// Reiter „Issues“ des Bereichs „Weiterarbeiten“ (#2052), ohne Open Tools API:
// je gespeichertem Arbeitsstand eines offenen Issues eine Zeile, neueste
// zuerst, selbst gezeichnet:
//   #1926  Arbeitskopien je Tracker-Projekt hinterlegen          [Fortsetzen]
//          vor 2 Std. · 4 Reiter · zuletzt TAtlasIdeIssueStart.Branch (IssueStart.pas:212)
//          Branch claude/project-thread-h0zerj
// Ist der Zustand im Tracker unbekannt (ohne Netz), steht „Zustand unbekannt“
// hinter dem Branch. Klick auf „Fortsetzen“ (bzw. Doppelklick auf die Zeile)
// geht über die Nachrichtenschleife an die Quelle, weil sie den Bereich
// daraufhin neu füllt. Daten und Aktion kommen über
// IAtlasContinueIssuesSource aus der IDE-Schicht. Zeitangabe und Zahl der
// Reiter teilt sich der Reiter „Zuletzt“ (Atlas.UI.Welcome.Continue) mit
// diesem Reiter.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.ContinueIssues,
  Atlas.UI.Welcome.Frame;

type
  IAtlasContinueIssuesSource = interface
    ['{8D3F61B0-27C4-4A5E-9B18-E4C07A2D5F93}']
    /// <summary>Reiter „Issues“ zeigen (welcomePage.continue.issues an und Tracker vorhanden).</summary>
    function IssuesEnabled: Boolean;
    /// <summary>Gespeicherte Arbeitsstände offener Issues, neueste zuerst.</summary>
    function IssueRows: TAtlasIssueWorkRows;
    /// <summary>Hinweis unter der Liste (z. B. Branch fehlt, übersprungene Dateien); '' ohne.</summary>
    function IssuesNotice: string;
    /// <summary>„Fortsetzen“: Projekt öffnen, Branch nur nach Rückfrage wechseln, Reiter wiederherstellen.</summary>
    procedure ResumeIssue(const AProject, AKey: string);
  end;

  /// <summary>Texte der Reiter „Zuletzt“ und „Issues“, ohne Steuerelement.</summary>
  TAtlasContinueIssueTexts = class
  public
    /// <summary>„7 Reiter“ bzw. „1 Reiter“.</summary>
    class function TabsText(ACount: Integer): string; static;
    /// <summary>„gerade eben“, „vor 5 Min.“, „vor 2 Std.“, „gestern 18:40“ bzw. Datum mit Uhrzeit; '' ohne Zeit.
    /// </summary>
    class function AgeText(AAtUtc, ANowUtc: TDateTime): string; static;
    /// <summary>Erste Zeile: „#1926  Titel“.</summary>
    class function TitleText(const ARow: TAtlasIssueWorkRow): string; static;
    /// <summary>Zweite Zeile: „vor 2 Std. · 4 Reiter · zuletzt TKunde.Laden (Kunde.pas:42)“.</summary>
    class function DetailText(const ARow: TAtlasIssueWorkRow; ANowUtc: TDateTime): string; static;
    /// <summary>Dritte Zeile: „Branch …“ und ggf. „Zustand unbekannt“; '' ohne beides.</summary>
    class function BranchText(const ARow: TAtlasIssueWorkRow): string; static;
    /// <summary>Tooltip einer Zeile: Projekt, Stand und Klick.</summary>
    class function HintFor(const ARow: TAtlasIssueWorkRow): string; static;
  end;

  /// <summary>Reiter „Issues“: Zeilen der Arbeitsstände je Issue mit „Fortsetzen“, darunter der Hinweis der Quelle.
  /// </summary>
  TAtlasContinueIssuesView = class(TPanel)
  public const
    cRowHeight = 64;
    cLineHeight = 20;
    cIndent = 8;
    cButtonHeight = 22;
    cButtonPadding = 10;
    /// <summary>Rundung der Schaltfläche „Fortsetzen“.</summary>
    cButtonRadius = 6;
    /// <summary>Einzug der zweiten und dritten Zeile (unter dem Titel).</summary>
    cDetailIndent = 32;
  private
    FFrame: TAtlasWelcomeSectionFrame;
    FSource: IAtlasContinueIssuesSource;
    FBox: TAtlasWelcomeCanvas;
    FRows: TAtlasIssueWorkRows;
    FNotice: string;
    FButtonRects: TArray<TRect>;
    FHintRow: Integer;
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BoxDblClick(Sender: TObject);
  public
    /// <summary>Zeichnet mit Schrift und Skalierung von AFrame.</summary>
    constructor Create(AFrame: TAtlasWelcomeSectionFrame); reintroduce;
    /// <summary>Zeilen und Hinweis neu von der Quelle lesen.</summary>
    procedure Fill;
    /// <summary>Höhe der Zeilen und des Hinweises.</summary>
    function ContentHeight: Integer;
    /// <summary>Rechtecke der Schaltflächen „Fortsetzen“ (Koordinaten der Zeichenfläche).</summary>
    procedure LayoutButtons;
    /// <summary>Zeile an X, Y; -1 = keine. AButton: auf „Fortsetzen“.</summary>
    function HitTest(AX, AY: Integer; out AButton: Boolean): Integer;
    /// <summary>„Fortsetzen“ für die Zeile ARow (auch für Tests).</summary>
    procedure ResumeRow(ARow: Integer);
    /// <summary>Oberkante der Zeile ARow (Koordinaten der Zeichenfläche).</summary>
    function RowTop(ARow: Integer): Integer;
    property Source: IAtlasContinueIssuesSource read FSource write FSource;
    property Rows: TAtlasIssueWorkRows read FRows;
    property Notice: string read FNotice;
  end;

implementation

uses
  System.DateUtils,
  System.UITypes,
  Vcl.Forms,
  Vcl.Themes,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Welcome.Strings;

const
  cSeparator = ' · ';
  cNoticeColor = TColor($001A8CC9);

type
  /// <summary>Farben des IDE-Themas (hell oder dunkel) für den Reiter „Issues“.</summary>
  TIssueColors = record
    Text: TColor;
    Muted: TColor;
    Line: TColor;
    Warning: TColor;
  end;

  /// <summary>Zeichnet den Reiter „Issues“.</summary>
  TIssuesPainter = record
    View: TAtlasContinueIssuesView;
    Canvas: TCanvas;
    Colors: TIssueColors;
    Stamp: TDateTime;
    function Scaled(AValue: Integer): Integer;
    procedure PlainFont;
    procedure PaintLine(const ARect: TRect; AColor: TColor; const AText: string);
    procedure PaintButton(ARow: Integer);
    procedure PaintRow(ARow: Integer);
    procedure Paint;
  end;

{ TAtlasContinueIssueTexts }

class function TAtlasContinueIssueTexts.TabsText(ACount: Integer): string;
begin
  if ACount = 1 then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueTabsOne);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueTabs, [ACount]);
  end;
end;

class function TAtlasContinueIssueTexts.AgeText(AAtUtc, ANowUtc: TDateTime): string;
var
  mAtLocal: TDateTime;
  mValue: Integer;
begin
  Result := '';
  if AAtUtc <= 0 then
  begin
    Exit;
  end;
  mAtLocal := TTimeZone.Local.ToLocalTime(AAtUtc);
  case TAtlasWelcomeContinue.Age(mAtLocal, TTimeZone.Local.ToLocalTime(ANowUtc), mValue) of
    TAtlasContinueAge.JustNow:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueJustNow);
    TAtlasContinueAge.Minutes:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueMinutes, [mValue]);
    TAtlasContinueAge.Hours:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueHours, [mValue]);
    TAtlasContinueAge.Yesterday:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueYesterday, [FormatDateTime('t', mAtLocal)]);
  else
    Result := FormatDateTime('ddddd t', mAtLocal);
  end;
end;

class function TAtlasContinueIssueTexts.TitleText(const ARow: TAtlasIssueWorkRow): string;
begin
  Result := ARow.Entry.Key;
  if ARow.Entry.Title <> '' then
  begin
    Result := Result + '  ' + ARow.Entry.Title;
  end;
end;

/// <summary>„TKunde.Laden (Kunde.pas:42)“, ohne Methode „Kunde.pas:42“; '' ohne Datei.</summary>
function PlaceText(const ATab: TAtlasWorkTab): string;
begin
  Result := TAtlasWelcomeContinue.FileNameOf(ATab.FileName);
  if Result = '' then
  begin
    Exit;
  end;
  if ATab.Line > 0 then
  begin
    Result := Result + ':' + IntToStr(ATab.Line);
  end;
  if ATab.Method <> '' then
  begin
    Result := ATab.Method + ' (' + Result + ')';
  end;
end;

class function TAtlasContinueIssueTexts.DetailText(const ARow: TAtlasIssueWorkRow; ANowUtc: TDateTime): string;
var
  mParts: TArray<string>;
  mAge, mPlace: string;
begin
  mParts := nil;
  mAge := AgeText(ARow.Entry.State.At, ANowUtc);
  if mAge <> '' then
  begin
    mParts := mParts + [mAge];
  end;
  mParts := mParts + [TabsText(ARow.Entry.State.TabCount)];
  mPlace := PlaceText(ARow.LastTab);
  if mPlace <> '' then
  begin
    mParts := mParts + [TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeIssuesLast, [mPlace])];
  end;
  Result := string.Join(cSeparator, mParts);
end;

class function TAtlasContinueIssueTexts.BranchText(const ARow: TAtlasIssueWorkRow): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  if ARow.Entry.Branch <> '' then
  begin
    mParts := mParts + [TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeIssuesBranch, [ARow.Entry.Branch])];
  end;
  if ARow.Status = TAtlasIssueStateKind.Unknown then
  begin
    mParts := mParts + [TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeIssuesStateUnknown)];
  end;
  Result := string.Join(cSeparator, mParts);
end;

class function TAtlasContinueIssueTexts.HintFor(const ARow: TAtlasIssueWorkRow): string;
var
  mLines: TStringList;
  mPlace: string;
begin
  mLines := TStringList.Create;
  try
    mLines.Add(TitleText(ARow));
    mLines.Add(ARow.Project);
    mPlace := PlaceText(ARow.LastTab);
    if mPlace <> '' then
    begin
      mLines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueHintLast, [mPlace]));
    end;
    mLines.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeIssuesHintResume));
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

{ TIssuesPainter }

function TIssuesPainter.Scaled(AValue: Integer): Integer;
begin
  Result := View.FFrame.ScaleValue(AValue);
end;

procedure TIssuesPainter.PlainFont;
begin
  Canvas.Font.Assign(View.FFrame.Font);
end;

procedure TIssuesPainter.PaintLine(const ARect: TRect; AColor: TColor; const AText: string);
begin
  Canvas.Font.Color := AColor;
  Canvas.TextRect(ARect, ARect.Left, ARect.Top, AText);
end;

procedure TIssuesPainter.PaintButton(ARow: Integer);
var
  mButton: TRect;
  mText: string;
  mRadius: Integer;
begin
  mButton := View.FButtonRects[ARow];
  PlainFont;
  Canvas.Pen.Color := Colors.Line;
  Canvas.Brush.Style := bsClear;
  mRadius := Scaled(TAtlasContinueIssuesView.cButtonRadius);
  Canvas.RoundRect(mButton.Left, mButton.Top, mButton.Right, mButton.Bottom, mRadius, mRadius);
  Canvas.Font.Color := Colors.Text;
  mText := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueResume);
  Canvas.TextOut(mButton.Left + (mButton.Width - Canvas.TextWidth(mText)) div 2,
    mButton.Top + (mButton.Height - Canvas.TextHeight(mText)) div 2, mText);
end;

procedure TIssuesPainter.PaintRow(ARow: Integer);
var
  mRow: TAtlasIssueWorkRow;
  mTop, mLeft, mLimit, mLine: Integer;
  mColor: TColor;
begin
  mRow := View.FRows[ARow];
  mTop := View.RowTop(ARow);
  mLine := Scaled(TAtlasContinueIssuesView.cLineHeight);
  mLeft := Scaled(TAtlasContinueIssuesView.cIndent);
  mLimit := View.FButtonRects[ARow].Left - Scaled(TAtlasContinueIssuesView.cIndent);
  PlainFont;
  Canvas.Font.Style := [fsBold];
  PaintLine(Rect(mLeft, mTop + Scaled(2), mLimit, mTop + Scaled(2) + mLine), Colors.Text, mRow.Entry.Key);
  mLeft := mLeft + Canvas.TextWidth(mRow.Entry.Key + '  ');
  Canvas.Font.Style := [];
  if mLeft < mLimit then
  begin
    PaintLine(Rect(mLeft, mTop + Scaled(2), mLimit, mTop + Scaled(2) + mLine), Colors.Text, mRow.Entry.Title);
  end;
  // Zweite und dritte Zeile eingerückt wie im Entwurf, bis vor „Fortsetzen“.
  mLeft := Scaled(TAtlasContinueIssuesView.cDetailIndent);
  PaintLine(Rect(mLeft, mTop + Scaled(2) + mLine, mLimit, mTop + Scaled(2) + 2 * mLine), Colors.Muted,
    TAtlasContinueIssueTexts.DetailText(mRow, Stamp));
  mColor := Colors.Muted;
  if mRow.Status = TAtlasIssueStateKind.Unknown then
  begin
    mColor := Colors.Warning;
  end;
  PaintLine(Rect(mLeft, mTop + Scaled(2) + 2 * mLine, mLimit, mTop + Scaled(2) + 2 * mLine + mLine), mColor,
    TAtlasContinueIssueTexts.BranchText(mRow));
  PaintButton(ARow);
end;

procedure TIssuesPainter.Paint;
var
  mRow, mTop: Integer;
begin
  Canvas.Brush.Style := bsClear;
  PlainFont;
  if Length(View.FRows) = 0 then
  begin
    Canvas.Font.Color := Colors.Muted;
    Canvas.TextOut(Scaled(TAtlasContinueIssuesView.cIndent),
      View.RowTop(0) + Scaled(TAtlasContinueIssuesView.cIndent) div 2,
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeIssuesEmpty));
  end;
  View.LayoutButtons;
  for mRow := 0 to High(View.FRows) do
  begin
    PaintRow(mRow);
  end;
  // Hinweis der Quelle (z. B. Branch fehlt, übersprungene Dateien).
  if View.FNotice <> '' then
  begin
    PlainFont;
    mTop := View.RowTop(Length(View.FRows)) + Scaled(TAtlasContinueIssuesView.cIndent);
    if Length(View.FRows) = 0 then
    begin
      mTop := View.RowTop(1);
    end;
    PaintLine(Rect(Scaled(TAtlasContinueIssuesView.cIndent), mTop,
      View.FBox.Width - Scaled(TAtlasContinueIssuesView.cIndent), mTop + Scaled(TAtlasContinueIssuesView.cLineHeight)),
      cNoticeColor, View.FNotice);
  end;
end;

{ TAtlasContinueIssuesView }

constructor TAtlasContinueIssuesView.Create(AFrame: TAtlasWelcomeSectionFrame);
begin
  inherited Create(AFrame);
  FFrame := AFrame;
  FHintRow := -1;
  BevelOuter := bvNone;
  ParentBackground := True;
  ShowCaption := False;

  FBox := TAtlasWelcomeCanvas.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
  FBox.OnDblClick := BoxDblClick;
end;

procedure TAtlasContinueIssuesView.Fill;
begin
  FRows := nil;
  FNotice := '';
  if FSource <> nil then
  begin
    FRows := FSource.IssueRows;
    FNotice := FSource.IssuesNotice;
  end;
  // Die Rechtecke der Schaltflächen entstehen beim Zeichnen (LayoutButtons).
  FButtonRects := nil;
  FHintRow := -1;
  FBox.Invalidate;
end;

function TAtlasContinueIssuesView.ContentHeight: Integer;
var
  mRows: Integer;
begin
  mRows := Length(FRows);
  if mRows < 1 then
  begin
    mRows := 1;
  end;
  Result := RowTop(mRows) + FFrame.ScaleValue(cIndent);
  if FNotice <> '' then
  begin
    Inc(Result, FFrame.ScaleValue(cLineHeight) + FFrame.ScaleValue(cIndent));
  end;
end;

function TAtlasContinueIssuesView.RowTop(ARow: Integer): Integer;
begin
  Result := FFrame.ScaleValue(cIndent) div 2 + ARow * FFrame.ScaleValue(cRowHeight);
end;

procedure TAtlasContinueIssuesView.LayoutButtons;
var
  mRow, mWidth, mTop, mRight: Integer;
  mCanvas: TCanvas;
begin
  // „Fortsetzen“ rechts in der ersten Zeile; die Rechtecke dienen auch dem Treffertest.
  SetLength(FButtonRects, Length(FRows));
  mCanvas := FBox.Canvas;
  mCanvas.Font.Assign(FFrame.Font);
  mWidth := mCanvas.TextWidth(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueResume)) +
    2 * FFrame.ScaleValue(cButtonPadding);
  mRight := FBox.Width - FFrame.ScaleValue(cIndent);
  for mRow := 0 to High(FRows) do
  begin
    mTop := RowTop(mRow) + FFrame.ScaleValue(2);
    FButtonRects[mRow] := Rect(mRight - mWidth, mTop, mRight, mTop + FFrame.ScaleValue(cButtonHeight));
  end;
end;

function TAtlasContinueIssuesView.HitTest(AX, AY: Integer; out AButton: Boolean): Integer;
begin
  Result := -1;
  AButton := False;
  if (Length(FRows) = 0) or (AY < RowTop(0)) or (AY >= RowTop(Length(FRows))) then
  begin
    Exit;
  end;
  Result := (AY - RowTop(0)) div FFrame.ScaleValue(cRowHeight);
  if (Result >= 0) and (Result <= High(FButtonRects)) then
  begin
    AButton := FButtonRects[Result].Contains(Point(AX, AY));
  end;
end;

procedure TAtlasContinueIssuesView.ResumeRow(ARow: Integer);
var
  mSource: IAtlasContinueIssuesSource;
  mProject, mKey: string;
begin
  if (FSource = nil) or (ARow < 0) or (ARow > High(FRows)) then
  begin
    Exit;
  end;
  mSource := FSource;
  mProject := FRows[ARow].Project;
  mKey := FRows[ARow].Entry.Key;
  // Die Quelle füllt den Bereich danach neu: nicht im eigenen Mausereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.ResumeIssue(mProject, mKey);
    end);
end;

procedure TAtlasContinueIssuesView.BoxPaint(Sender: TObject);
var
  mPainter: TIssuesPainter;
begin
  mPainter.View := Self;
  mPainter.Canvas := FBox.Canvas;
  mPainter.Colors.Text := StyleServices(FFrame).GetSystemColor(clWindowText);
  mPainter.Colors.Muted := StyleServices(FFrame).GetSystemColor(clGrayText);
  mPainter.Colors.Line := StyleServices(FFrame).GetSystemColor(clBtnShadow);
  mPainter.Colors.Warning := cNoticeColor;
  mPainter.Stamp := TTimeZone.Local.ToUniversalTime(Now);
  mPainter.Paint;
end;

procedure TAtlasContinueIssuesView.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  mRow: Integer;
  mButton: Boolean;
begin
  mRow := HitTest(X, Y, mButton);
  FBox.Cursor := crDefault;
  if mButton then
  begin
    FBox.Cursor := crHandPoint;
  end;
  if mRow = FHintRow then
  begin
    Exit;
  end;
  FHintRow := mRow;
  FBox.Hint := '';
  if mRow >= 0 then
  begin
    FBox.Hint := TAtlasContinueIssueTexts.HintFor(FRows[mRow]);
  end;
  Application.CancelHint;
end;

procedure TAtlasContinueIssuesView.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
var
  mRow: Integer;
  mButton: Boolean;
begin
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mRow := HitTest(X, Y, mButton);
  if mButton then
  begin
    ResumeRow(mRow);
  end;
end;

procedure TAtlasContinueIssuesView.BoxDblClick(Sender: TObject);
var
  mPosition: TPoint;
  mButton: Boolean;
  mRow: Integer;
begin
  mPosition := FBox.ScreenToClient(Mouse.CursorPos);
  mRow := HitTest(mPosition.X, mPosition.Y, mButton);
  // Doppelklick auf die Schaltfläche hat schon beim ersten Klick fortgesetzt.
  if not mButton then
  begin
    ResumeRow(mRow);
  end;
end;

end.
