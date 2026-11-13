unit Atlas.UI.Tracker.SprintTile;

// Bereich „Sprint“ der Willkommensseite (#1277, Mockup IX5), ohne Open Tools
// API. Selbst gezeichnet:
//   Sprint 12 · 27.10.–07.11. · noch 4 Tage            (Klick: Board im Browser)
//   ┌ MEINE OFFEN ┐ ┌ MEINE ERLEDIGT ┐ ┌ TEAM ÜBRIG ┐
//   │ 3           │ │ 5              │ │ 21 Punkte  │
//   erledigt 5 · Vorsprint 4 am selben Tag ▲1        Velocity ▂▅▇
//   ╲ Ist (Linie), - - ideal (gestrichelt), Vorsprint blass, | heute
//   Stand vom 28.10. 09:12 · nicht erreichbar
// „meine offen“ und „meine erledigt“ filtern „Meine Issues“, „Team übrig“ und
// das Diagramm öffnen das Fenster „Atlas-Board“ (#1272), der Titel das Board
// im Browser. Tooltip über dem Diagramm mit den Werten des Tages. Farben aus
// dem IDE-Thema (clHighlight, clGrayText, clWindowText). Daten kommen fertig
// über IAtlasSprintSource aus der IDE-Schicht; hier wird nur gezeichnet.
// Ohne Board bzw. Tracker: Hinweis „Kein Board für dieses Projekt –
// zuordnen …“ als Link auf die Seite Issue-Tracker (#1261).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Sprint,
  Atlas.UI.Style.Canvas,
  Atlas.UI.Tracker.TileView;

type
{$SCOPEDENUMS ON}
  TAtlasSprintTileStatus = (NoProject, NoTracker, NoBoard, NoSprint, Loading, Failed, Ready);
  TAtlasSprintHitKind = (None, Title, MineOpen, MineDone, TeamLeft, Chart, Assign);
{$SCOPEDENUMS OFF}

  /// <summary>Was die Kachel zeigt.</summary>
  TAtlasSprintTile = record
    Status: TAtlasSprintTileStatus;
    Sprint: TAtlasSprintView;
    /// <summary>Der Stand ist alt (ohne Netz bzw. Fehler); AError nennt den Grund.</summary>
    Stale: Boolean;
    Error: TAtlasCiFetchError;
    Loading: Boolean;
    /// <summary>issues.sprint.burndown bzw. issues.sprint.compare.</summary>
    Burndown: Boolean;
    Compare: Boolean;
    /// <summary>„zuordnen …“ möglich (#1261).</summary>
    CanAssign: Boolean;
  end;

  IAtlasSprintSource = interface
    ['{2F7C9B14-6E3A-4D58-8B1F-0A4C7E2D9561}']
    function View: TAtlasSprintTile;
    /// <summary>Der Bereich wird gezeigt: bei Bedarf den Sprint im Hintergrund laden.</summary>
    procedure Shown;
    /// <summary>Fenster „Atlas-Board“ (#1272).</summary>
    procedure OpenBoard;
    procedure BrowseBoard;
    /// <summary>„Meine Issues“ auf die eigenen offenen (ADone = False) bzw. erledigten Issues des Sprints
    /// filtern.</summary>
    procedure FilterIssues(ADone: Boolean);
    procedure AssignProject;
  end;

  TAtlasTrackerSprintView = class(TAtlasTrackerTileView)
  public const
    cIndent = 8;
    cHeadHeight = 22;
    cNumberHeight = 50;
    cNumberGap = 8;
    cCompareHeight = 20;
    cChartHeight = 72;
    cStatusHeight = 20;
    cVelocityBarWidth = 8;
    cVelocityHeight = 16;
    cEmptyHeight = 40;
  private
    FSource: IAtlasSprintSource;
    FBox: TAtlasStyledCanvas;
    FTile: TAtlasSprintTile;
    FHintKey: string;
    FContentHeight: Integer;
    procedure SetSource(const AValue: IAtlasSprintSource);
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BodyResize(Sender: TObject);
    function HeightFor(AWidth: Integer): Integer;
    class procedure Post(const AAction: TThreadProcedure); static;
    procedure PaintNumbers(ACanvas: TCanvas; AWidth: Integer);
    procedure PaintChart(ACanvas: TCanvas; const ARect: TRect);
    procedure PaintVelocity(ACanvas: TCanvas; const ARect: TRect);
  public
    constructor Create(AOwner: TComponent); override;
    function BodyHeight: Integer; override;
    procedure UpdateContent; override;
    /// <summary>Zeilen von oben: Kopf, Zahlen, Vergleich, Diagramm, Stand (Breite AWidth).</summary>
    function NumberRect(AIndex, AWidth: Integer): TRect;
    function CompareTop: Integer;
    function ChartRect(AWidth: Integer): TRect;
    function StatusTop(AWidth: Integer): Integer;
    function HitTest(AX, AY: Integer): TAtlasSprintHitKind;
    /// <summary>Klick wie mit der Maus (auch für Tests).</summary>
    procedure ClickAt(AKind: TAtlasSprintHitKind);
    /// <summary>Tag des Diagramms unter X (0 … DayCount); -1 außerhalb.</summary>
    function DayAt(AX, AWidth: Integer): Integer;
    class function TitleText: string; static;
    /// <summary>„Sprint 12 · 27.10.–07.11. · noch 4 Tage“.</summary>
    class function HeadingText(const ATile: TAtlasSprintTile): string; static;
    /// <summary>Hinweis statt Inhalt (kein Projekt, kein Board, …); '' mit Sprint.</summary>
    class function NoticeText(const ATile: TAtlasSprintTile): string; static;
    /// <summary>Zeile unten: lädt, „Stand vom … · Grund“; '' sonst.</summary>
    class function StatusText(const ATile: TAtlasSprintTile): string; static;
    /// <summary>„erledigt 5 · Vorsprint 4 am selben Tag ▲1“; '' ohne Vergleich.</summary>
    class function CompareText(const ATile: TAtlasSprintTile): string; static;
    /// <summary>Wert mit höchstens einer Nachkommastelle in der Sprache der Oberfläche.</summary>
    class function NumberText(AValue: Double): string; static;
    /// <summary>Beschriftung und Wert der Zahl AIndex (0 meine offen, 1 meine erledigt, 2 Team übrig).</summary>
    class function NumberCaption(AIndex: Integer): string; static;
    class function NumberValue(const ATile: TAtlasSprintTile; AIndex: Integer): string; static;
    /// <summary>Tooltip zum Tag ADay.</summary>
    class function DayHint(const ATile: TAtlasSprintTile; ADay: Integer): string; static;
    class function ErrorText(AError: TAtlasCiFetchError): string; static;
    property Source: IAtlasSprintSource read FSource write SetSource;
    property Tile: TAtlasSprintTile read FTile;
    property PaintBox: TAtlasStyledCanvas read FBox;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  System.DateUtils,
  Vcl.Themes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Issue.Strings,
  Atlas.UI.Tracker.Sprint.Strings;

const
  cFullPercent = 100;
  /// <summary>Drei Zahlen nebeneinander: meine offen, meine erledigt, Team übrig.</summary>
  cNumberCount = 3;
  cTeamLeftIndex = 2;
  /// <summary>Gleichstand bzw. ganze Zahl bis auf diese Abweichung.</summary>
  cWholeTolerance = 0.05;
  cDayFormat = 'dd.mm.';
  cStaleFormat = 'dd.mm. hh:nn';
  cHintKeyFormat = '%d:%d';
  cPartSeparator = ' · ';
  cRangeSeparator = '–';
  cUnknownValue = '–';
  cEqualMark = '=';
  cUpMark = '▲';
  cDownMark = '▼';
  /// <summary>Text zum Messen der Zeilenhöhe der Beschriftung.</summary>
  cMeasureText = 'Ag';
  // Abstände in logischen Pixeln.
  cChartGap = 4;
  cHeadTextTop = 3;
  cNumberPad = 8;
  cNumberRadius = 8;
  cCaptionTop = 4;
  cValueTop = 20;
  cValueFontGrow = 3;
  cDotRadius = 3;
  cVelocityBarGap = 3;
  cVelocityCaptionGap = 6;
  // Anteile der Vordergrundfarbe in Prozent.
  cFramePercent = 35;
  cBaselinePercent = 40;
  cPreviousPercent = 45;
  cTodayPercent = 60;
  cVelocityMinPercent = 50;

/// <summary>Mischfarbe: APercent Prozent von AFore auf ABack.</summary>
function Blend(AFore, ABack: TColor; APercent: Integer): TColor;
var
  mFore, mBack, mResult: TColorRec;
begin
  mFore.Color := TColor(ColorToRGB(AFore));
  mBack.Color := TColor(ColorToRGB(ABack));
  mResult.Color := 0;
  mResult.R := (mFore.R * APercent + mBack.R * (cFullPercent - APercent)) div cFullPercent;
  mResult.G := (mFore.G * APercent + mBack.G * (cFullPercent - APercent)) div cFullPercent;
  mResult.B := (mFore.B * APercent + mBack.B * (cFullPercent - APercent)) div cFullPercent;
  Result := mResult.Color;
end;

function LocalDay(AUtc: TDateTime): string;
begin
  Result := FormatDateTime(cDayFormat, TTimeZone.Local.ToLocalTime(AUtc), FormatSettings);
end;

type
  /// <summary>Burndown-Diagramm einer Zeichnung: Skala, Farben und die Linien.</summary>
  TAtlasSprintChart = record
    Canvas: TCanvas;
    Area: TRect;
    Sprint: TAtlasSprintView;
    Compare: Boolean;
    Count: Integer;
    Top: Double;
    Wide: Integer;
    Dot: Integer;
    LineColor, MutedColor, BackColor, TextColor: TColor;
    function PointOf(ADay: Integer; AValue: Double): TPoint;
    function LineOf(const AValues: TArray<Double>): TArray<TPoint>;
    procedure Scale;
    procedure PaintPrevious;
    procedure PaintIdeal;
    procedure PaintActual;
    procedure PaintToday;
  end;

function TAtlasSprintChart.PointOf(ADay: Integer; AValue: Double): TPoint;
begin
  Result.X := Area.Left;
  if Count > 1 then
  begin
    Result.X := Area.Left + Round(ADay * Area.Width / (Count - 1));
  end;
  Result.Y := Area.Bottom - Round(EnsureRange(AValue / Top, 0, 1) * Area.Height);
end;

function TAtlasSprintChart.LineOf(const AValues: TArray<Double>): TArray<TPoint>;
var
  mDay: Integer;
begin
  Result := nil;
  for mDay := 0 to Min(High(AValues), Count - 1) do
  begin
    Result := Result + [PointOf(mDay, AValues[mDay])];
  end;
end;

procedure TAtlasSprintChart.Scale;
var
  mValue: Double;
begin
  // Eine Skala für alle Linien: der größte Wert, mindestens 1.
  Top := 1;
  for mValue in Sprint.Ideal do
  begin
    Top := Max(Top, mValue);
  end;
  for mValue in Sprint.Actual do
  begin
    Top := Max(Top, mValue);
  end;
  if Compare then
  begin
    for mValue in Sprint.Previous do
    begin
      Top := Max(Top, mValue);
    end;
  end;
end;

procedure TAtlasSprintChart.PaintPrevious;
var
  mPoints: TArray<TPoint>;
begin
  // Vorsprint blass.
  if Compare and Sprint.HasPrevious then
  begin
    mPoints := LineOf(Sprint.Previous);
    if Length(mPoints) > 1 then
    begin
      Canvas.Pen.Color := Blend(MutedColor, BackColor, cPreviousPercent);
      Canvas.Pen.Width := Wide;
      Canvas.Polyline(mPoints);
    end;
  end;
end;

procedure TAtlasSprintChart.PaintIdeal;
var
  mPoints: TArray<TPoint>;
begin
  // Ideallinie gestrichelt (Stiftbreite 1, sonst zeichnet Windows durchgezogen).
  mPoints := LineOf(Sprint.Ideal);
  if Length(mPoints) > 1 then
  begin
    Canvas.Pen.Width := 1;
    Canvas.Pen.Style := psDash;
    Canvas.Pen.Color := MutedColor;
    Canvas.Brush.Style := bsClear;
    Canvas.Polyline(mPoints);
    Canvas.Pen.Style := psSolid;
  end;
end;

procedure TAtlasSprintChart.PaintActual;
var
  mPoints: TArray<TPoint>;
  mLast: TPoint;
  mRadius: Integer;
begin
  mPoints := LineOf(Sprint.Actual);
  Canvas.Pen.Color := LineColor;
  Canvas.Pen.Width := Wide;
  if Length(mPoints) > 1 then
  begin
    Canvas.Polyline(mPoints);
  end;
  if Length(mPoints) > 0 then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := LineColor;
    mLast := mPoints[High(mPoints)];
    mRadius := Dot;
    Canvas.Ellipse(mLast.X - mRadius, mLast.Y - mRadius, mLast.X + mRadius + 1, mLast.Y + mRadius + 1);
    Canvas.Brush.Style := bsClear;
  end;
end;

procedure TAtlasSprintChart.PaintToday;
var
  mX: Integer;
begin
  if (Sprint.Today >= 0) and (Sprint.Today < Count) then
  begin
    mX := PointOf(Sprint.Today, 0).X;
    Canvas.Pen.Width := 1;
    Canvas.Pen.Style := psDot;
    Canvas.Pen.Color := Blend(TextColor, BackColor, cTodayPercent);
    Canvas.MoveTo(mX, Area.Top);
    Canvas.LineTo(mX, Area.Bottom);
    Canvas.Pen.Style := psSolid;
  end;
end;

{ TAtlasTrackerSprintView }

constructor TAtlasTrackerSprintView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBox := TAtlasStyledCanvas.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
  OnResize := BodyResize;
end;

class function TAtlasTrackerSprintView.TitleText: string;
begin
  Result := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintTitle);
end;

procedure TAtlasTrackerSprintView.SetSource(const AValue: IAtlasSprintSource);
begin
  FSource := AValue;
  UpdateContent;
  if FSource <> nil then
  begin
    FSource.Shown;
  end;
end;

procedure TAtlasTrackerSprintView.UpdateContent;
var
  mOldHeight: Integer;
begin
  if not HasWindow then
  begin
    Exit;
  end;
  mOldHeight := HeightFor(ClientWidth);
  FTile := Default(TAtlasSprintTile);
  if FSource <> nil then
  begin
    FTile := FSource.View;
  end;
  FHintKey := '';
  FBox.Invalidate;
  inherited;
  if mOldHeight <> HeightFor(ClientWidth) then
  begin
    HeightChanged;
  end;
end;

procedure TAtlasTrackerSprintView.BodyResize(Sender: TObject);
var
  mOldHeight: Integer;
begin
  mOldHeight := FContentHeight;
  FContentHeight := HeightFor(ClientWidth);
  if mOldHeight <> FContentHeight then
  begin
    HeightChanged;
  end;
end;

function TAtlasTrackerSprintView.BodyHeight: Integer;
begin
  FContentHeight := HeightFor(ClientWidth);
  Result := FContentHeight;
end;

function TAtlasTrackerSprintView.CompareTop: Integer;
begin
  Result := ScaleValue(cHeadHeight) + ScaleValue(cNumberHeight) + ScaleValue(cNumberGap);
end;

function TAtlasTrackerSprintView.ChartRect(AWidth: Integer): TRect;
var
  mTop: Integer;
begin
  mTop := CompareTop;
  if FTile.Compare and ((CompareText(FTile) <> '') or (Length(FTile.Sprint.Velocity) > 0)) then
  begin
    Inc(mTop, ScaleValue(cCompareHeight));
  end;
  if FTile.Burndown then
  begin
    Inc(mTop, ScaleValue(cChartGap));
    Result := Rect(ScaleValue(cIndent), mTop, AWidth - ScaleValue(cIndent), mTop + ScaleValue(cChartHeight));
  end
  else
  begin
    Result := Rect(ScaleValue(cIndent), mTop, AWidth - ScaleValue(cIndent), mTop);
  end;
end;

function TAtlasTrackerSprintView.StatusTop(AWidth: Integer): Integer;
begin
  Result := ChartRect(AWidth).Bottom + ScaleValue(cChartGap);
end;

function TAtlasTrackerSprintView.HeightFor(AWidth: Integer): Integer;
begin
  if FTile.Status <> TAtlasSprintTileStatus.Ready then
  begin
    Result := ScaleValue(cEmptyHeight);
    if StatusText(FTile) <> '' then
    begin
      Inc(Result, ScaleValue(cStatusHeight));
    end;
    Exit;
  end;
  Result := StatusTop(AWidth);
  if StatusText(FTile) <> '' then
  begin
    Inc(Result, ScaleValue(cStatusHeight));
  end;
end;

function TAtlasTrackerSprintView.NumberRect(AIndex, AWidth: Integer): TRect;
var
  mWidth, mLeft: Integer;
begin
  mWidth := (AWidth - 2 * ScaleValue(cIndent) - (cNumberCount - 1) * ScaleValue(cNumberGap)) div cNumberCount;
  mLeft := ScaleValue(cIndent) + AIndex * (mWidth + ScaleValue(cNumberGap));
  Result := Rect(mLeft, ScaleValue(cHeadHeight), mLeft + mWidth, ScaleValue(cHeadHeight) + ScaleValue(cNumberHeight));
end;

class function TAtlasTrackerSprintView.NumberText(AValue: Double): string;
var
  mSettings: TFormatSettings;
begin
  mSettings := TFormatSettings.Invariant;
  if TAtlasStrings.Language = TAtlasLanguage.German then
  begin
    mSettings.DecimalSeparator := ',';
  end;
  // Ganze Zahlen ohne Nachkommastelle, sonst eine.
  if SameValue(AValue, Round(AValue), cWholeTolerance) then
  begin
    Result := IntToStr(Round(AValue));
  end
  else
  begin
    Result := FormatFloat('0.0', AValue, mSettings);
  end;
end;

class function TAtlasTrackerSprintView.HeadingText(const ATile: TAtlasSprintTile): string;
var
  mDays: string;
  mNow: TDateTime;
begin
  Result := '';
  if not ATile.Sprint.Known then
  begin
    Exit;
  end;
  mNow := TTimeZone.Local.ToUniversalTime(Now);
  if mNow < ATile.Sprint.Start then
  begin
    mDays := TAtlasSprintStrings.Fmt(TAtlasSprintTextId.WelcomeSprintNotStarted, [LocalDay(ATile.Sprint.Start)]);
  end
  else if ATile.Sprint.DaysLeft <= 0 then
  begin
    mDays := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintEnded);
  end
  else if ATile.Sprint.DaysLeft = 1 then
  begin
    mDays := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintDayLeft);
  end
  else
  begin
    mDays := TAtlasSprintStrings.Fmt(TAtlasSprintTextId.WelcomeSprintDaysLeft, [ATile.Sprint.DaysLeft]);
  end;
  // Ende ist exklusiv (Mitternacht danach): als letzten Tag den davor zeigen.
  Result := ATile.Sprint.Name + cPartSeparator + LocalDay(ATile.Sprint.Start) + cRangeSeparator +
    LocalDay(ATile.Sprint.Finish - OneSecond) + cPartSeparator + mDays;
end;

class function TAtlasTrackerSprintView.ErrorText(AError: TAtlasCiFetchError): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorToken);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorTimeout);
    TAtlasCiFetchError.Invalid, TAtlasCiFetchError.Server:
      Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorInvalid);
  else
    Result := TAtlasIssueStrings.Text(TAtlasIssueTextId.IssuePreviewErrorNetwork);
  end;
end;

class function TAtlasTrackerSprintView.NoticeText(const ATile: TAtlasSprintTile): string;
begin
  case ATile.Status of
    TAtlasSprintTileStatus.NoProject:
      Result := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintNoProject);
    TAtlasSprintTileStatus.NoTracker:
      Result := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintNoBoard);
    TAtlasSprintTileStatus.NoBoard:
      Result := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintNoBoardFound);
    TAtlasSprintTileStatus.NoSprint:
      Result := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintNoSprint);
    TAtlasSprintTileStatus.Loading:
      Result := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintLoading);
    // Noch nie geladen und keine Antwort: der Grund statt „lädt …“.
    TAtlasSprintTileStatus.Failed:
      Result := ErrorText(ATile.Error);
  else
    Result := '';
  end;
end;

class function TAtlasTrackerSprintView.StatusText(const ATile: TAtlasSprintTile): string;
begin
  Result := '';
  if ATile.Loading and (ATile.Status = TAtlasSprintTileStatus.Ready) then
  begin
    Exit(TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintLoading));
  end;
  if ATile.Stale and (ATile.Sprint.Fetched > 0) then
  begin
    Result := TAtlasSprintStrings.Fmt(TAtlasSprintTextId.WelcomeSprintStale, [FormatDateTime(cStaleFormat,
      TTimeZone.Local.ToLocalTime(ATile.Sprint.Fetched), FormatSettings), ErrorText(ATile.Error)]);
  end
  else if ATile.Stale and not (ATile.Status in [TAtlasSprintTileStatus.Loading, TAtlasSprintTileStatus.Failed]) then
  begin
    Result := ErrorText(ATile.Error);
  end;
end;

class function TAtlasTrackerSprintView.CompareText(const ATile: TAtlasSprintTile): string;
var
  mDelta: Double;
  mArrow: string;
begin
  Result := '';
  if not ATile.Compare or not ATile.Sprint.HasPrevious then
  begin
    Exit;
  end;
  mDelta := ATile.Sprint.DoneToday - ATile.Sprint.PreviousDone;
  if SameValue(mDelta, 0, cWholeTolerance) then
  begin
    mArrow := cEqualMark;
  end
  else if mDelta > 0 then
  begin
    mArrow := cUpMark + NumberText(mDelta);
  end
  else
  begin
    mArrow := cDownMark + NumberText(-mDelta);
  end;
  Result := TAtlasSprintStrings.Fmt(TAtlasSprintTextId.WelcomeSprintCompare, [NumberText(ATile.Sprint.DoneToday),
    NumberText(ATile.Sprint.PreviousDone), mArrow]);
end;

class function TAtlasTrackerSprintView.NumberCaption(AIndex: Integer): string;
begin
  case AIndex of
    0:
      Result := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintMineOpen);
    1:
      Result := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintMineDone);
  else
    Result := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintTeamLeft);
  end;
end;

class function TAtlasTrackerSprintView.NumberValue(const ATile: TAtlasSprintTile; AIndex: Integer): string;
begin
  case AIndex of
    0, 1:
      begin
        // Ohne Anmeldename sind „meine“ Zahlen unbekannt.
        if not ATile.Sprint.MineKnown then
        begin
          Exit(cUnknownValue);
        end;
        if AIndex = 0 then
        begin
          Result := IntToStr(Length(ATile.Sprint.MineOpen));
        end
        else
        begin
          Result := IntToStr(Length(ATile.Sprint.MineDone));
        end;
      end;
  else
    begin
      Result := NumberText(ATile.Sprint.TeamLeft) + ' ';
      if ATile.Sprint.UsesPoints then
      begin
        Result := Result + TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintPoints);
      end
      else
      begin
        Result := Result + TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintIssues);
      end;
    end;
  end;
end;

class function TAtlasTrackerSprintView.DayHint(const ATile: TAtlasSprintTile; ADay: Integer): string;
var
  mLeft, mDate: string;
begin
  Result := '';
  if (ADay < 0) or (ADay > High(ATile.Sprint.Ideal)) then
  begin
    Exit;
  end;
  mLeft := cUnknownValue;
  if ADay <= High(ATile.Sprint.Actual) then
  begin
    mLeft := NumberText(ATile.Sprint.Actual[ADay]);
  end;
  // Tag k ist das Ende des k-ten Arbeitstags; k = 0 der Start.
  mDate := LocalDay(ATile.Sprint.Start);
  if (ADay > 0) and (ADay <= Length(ATile.Sprint.Dates)) then
  begin
    mDate := FormatDateTime(cDayFormat, ATile.Sprint.Dates[ADay - 1], FormatSettings);
  end;
  Result := TAtlasSprintStrings.Fmt(TAtlasSprintTextId.WelcomeSprintDayHint, [ADay, mDate, mLeft,
    NumberText(ATile.Sprint.Ideal[ADay])]);
  if ATile.Compare and ATile.Sprint.HasPrevious and (ADay <= High(ATile.Sprint.Previous)) then
  begin
    Result := Result + cPartSeparator + TAtlasSprintStrings.Fmt(TAtlasSprintTextId.WelcomeSprintDayHintPrevious,
      [NumberText(ATile.Sprint.Previous[ADay])]);
  end;
end;

function TAtlasTrackerSprintView.DayAt(AX, AWidth: Integer): Integer;
var
  mArea: TRect;
  mCount: Integer;
begin
  Result := -1;
  mArea := ChartRect(AWidth);
  mCount := Length(FTile.Sprint.Ideal);
  if (mCount = 0) or (mArea.Width <= 0) or (AX < mArea.Left) or (AX > mArea.Right) then
  begin
    Exit;
  end;
  if mCount = 1 then
  begin
    Exit(0);
  end;
  Result := EnsureRange(Round((AX - mArea.Left) * (mCount - 1) / mArea.Width), 0, mCount - 1);
end;

/// <summary>Treffer in der Zahl AIndex; „meine“ nur mit bekanntem Anmeldenamen.</summary>
function NumberHit(const ATile: TAtlasSprintTile; AIndex: Integer): TAtlasSprintHitKind;
begin
  Result := TAtlasSprintHitKind.None;
  if AIndex = cTeamLeftIndex then
  begin
    Result := TAtlasSprintHitKind.TeamLeft;
  end
  else if ATile.Sprint.MineKnown and (AIndex = 0) then
  begin
    Result := TAtlasSprintHitKind.MineOpen;
  end
  else if ATile.Sprint.MineKnown then
  begin
    Result := TAtlasSprintHitKind.MineDone;
  end;
end;

/// <summary>Treffer unter dem Kopf einer bereiten Kachel: Zahlen, sonst Vergleich und Diagramm (Board).</summary>
function BodyHit(AView: TAtlasTrackerSprintView; const APoint: TPoint): TAtlasSprintHitKind;
var
  mIndex, mFound: Integer;
begin
  mFound := -1;
  for mIndex := 0 to cNumberCount - 1 do
  begin
    if AView.NumberRect(mIndex, AView.ClientWidth).Contains(APoint) then
    begin
      mFound := mIndex;
    end;
  end;
  if mFound >= 0 then
  begin
    Result := NumberHit(AView.Tile, mFound);
  end
  else if APoint.Y < AView.StatusTop(AView.ClientWidth) then
  begin
    Result := TAtlasSprintHitKind.Chart;
  end
  else
  begin
    Result := TAtlasSprintHitKind.None;
  end;
end;

function TAtlasTrackerSprintView.HitTest(AX, AY: Integer): TAtlasSprintHitKind;
begin
  Result := TAtlasSprintHitKind.None;
  if FTile.Status = TAtlasSprintTileStatus.NoTracker then
  begin
    if FTile.CanAssign and (AY < ScaleValue(cEmptyHeight)) then
    begin
      Result := TAtlasSprintHitKind.Assign;
    end;
  end
  else if FTile.Status <> TAtlasSprintTileStatus.Ready then
  begin
    Result := TAtlasSprintHitKind.None;
  end
  else if AY < ScaleValue(cHeadHeight) then
  begin
    if FTile.Sprint.Page <> '' then
    begin
      Result := TAtlasSprintHitKind.Title;
    end;
  end
  else
  begin
    Result := BodyHit(Self, Point(AX, AY));
  end;
end;

class procedure TAtlasTrackerSprintView.Post(const AAction: TThreadProcedure);
begin
  // Die Quelle füllt Bereiche danach neu: nicht im eigenen Mausereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Tracker, AAction);
end;

procedure TAtlasTrackerSprintView.ClickAt(AKind: TAtlasSprintHitKind);
var
  mSource: IAtlasSprintSource;
begin
  if FSource = nil then
  begin
    Exit;
  end;
  mSource := FSource;
  case AKind of
    TAtlasSprintHitKind.Title:
      Post(
        procedure
        begin
          mSource.BrowseBoard;
        end);
    TAtlasSprintHitKind.MineOpen:
      Post(
        procedure
        begin
          mSource.FilterIssues(False);
        end);
    TAtlasSprintHitKind.MineDone:
      Post(
        procedure
        begin
          mSource.FilterIssues(True);
        end);
    TAtlasSprintHitKind.TeamLeft, TAtlasSprintHitKind.Chart:
      Post(
        procedure
        begin
          mSource.OpenBoard;
        end);
    TAtlasSprintHitKind.Assign:
      Post(
        procedure
        begin
          mSource.AssignProject;
        end);
  else
    // Leerraum: nichts.
  end;
end;

procedure TAtlasTrackerSprintView.PaintNumbers(ACanvas: TCanvas; AWidth: Integer);
var
  mIndex, mPad: Integer;
  mRect: TRect;
  mText, mMuted, mBack, mAccent: TColor;
begin
  mText := StyleServices(Self).GetSystemColor(clWindowText);
  mMuted := StyleServices(Self).GetSystemColor(clGrayText);
  mBack := StyleServices(Self).GetSystemColor(clWindow);
  mAccent := StyleServices(Self).GetSystemColor(clHighlight);
  mPad := ScaleValue(cNumberPad);
  for mIndex := 0 to cNumberCount - 1 do
  begin
    mRect := NumberRect(mIndex, AWidth);
    ACanvas.Brush.Style := bsClear;
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Width := 1;
    ACanvas.Pen.Color := Blend(mMuted, mBack, cFramePercent);
    ACanvas.RoundRect(mRect.Left, mRect.Top, mRect.Right, mRect.Bottom, ScaleValue(cNumberRadius),
      ScaleValue(cNumberRadius));
    ACanvas.Font.Assign(Font);
    ACanvas.Font.Size := Font.Size - 1;
    ACanvas.Font.Color := mMuted;
    ACanvas.TextRect(Rect(mRect.Left + mPad, mRect.Top + ScaleValue(cCaptionTop), mRect.Right - mPad,
      mRect.Top + ScaleValue(cCaptionTop) + ACanvas.TextHeight(cMeasureText)), mRect.Left + mPad,
      mRect.Top + ScaleValue(cCaptionTop), AnsiUpperCase(NumberCaption(mIndex)));
    ACanvas.Font.Assign(Font);
    ACanvas.Font.Size := Font.Size + cValueFontGrow;
    ACanvas.Font.Style := [fsBold];
    // Klickbare Zahlen in Akzentfarbe.
    if (mIndex = cTeamLeftIndex) or FTile.Sprint.MineKnown then
    begin
      ACanvas.Font.Color := mAccent;
    end
    else
    begin
      ACanvas.Font.Color := mText;
    end;
    ACanvas.TextRect(Rect(mRect.Left + mPad, mRect.Top + ScaleValue(cValueTop), mRect.Right - mPad,
      mRect.Bottom - 2), mRect.Left + mPad, mRect.Top + ScaleValue(cValueTop), NumberValue(FTile, mIndex));
  end;
  ACanvas.Font.Assign(Font);
end;

procedure TAtlasTrackerSprintView.PaintChart(ACanvas: TCanvas; const ARect: TRect);
var
  mChart: TAtlasSprintChart;
begin
  mChart := Default(TAtlasSprintChart);
  mChart.Canvas := ACanvas;
  mChart.Area := ARect;
  mChart.Sprint := FTile.Sprint;
  mChart.Compare := FTile.Compare;
  mChart.Count := Length(FTile.Sprint.Ideal);
  if (mChart.Count = 0) or (ARect.Height <= 0) then
  begin
    Exit;
  end;
  mChart.Wide := ScaleValue(2);
  mChart.Dot := ScaleValue(cDotRadius);
  mChart.LineColor := StyleServices(Self).GetSystemColor(clHighlight);
  mChart.MutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  mChart.BackColor := StyleServices(Self).GetSystemColor(clWindow);
  mChart.TextColor := StyleServices(Self).GetSystemColor(clWindowText);
  mChart.Scale;
  // Grundlinie.
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Color := Blend(mChart.MutedColor, mChart.BackColor, cBaselinePercent);
  ACanvas.MoveTo(ARect.Left, ARect.Bottom);
  ACanvas.LineTo(ARect.Right, ARect.Bottom);
  mChart.PaintPrevious;
  mChart.PaintIdeal;
  mChart.PaintActual;
  // Marke „heute“.
  mChart.PaintToday;
  ACanvas.Pen.Width := 1;
end;

procedure TAtlasTrackerSprintView.PaintVelocity(ACanvas: TCanvas; const ARect: TRect);
var
  mIndex, mLeft, mHeight, mBar: Integer;
  mTop: Double;
  mColor, mBack: TColor;
  mCaption: string;
begin
  if Length(FTile.Sprint.Velocity) = 0 then
  begin
    Exit;
  end;
  mColor := StyleServices(Self).GetSystemColor(clHighlight);
  mBack := StyleServices(Self).GetSystemColor(clWindow);
  mTop := 1;
  for mIndex := 0 to High(FTile.Sprint.Velocity) do
  begin
    mTop := Max(mTop, FTile.Sprint.Velocity[mIndex]);
  end;
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Size := Font.Size - 1;
  ACanvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
  mCaption := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintVelocity);
  mBar := ScaleValue(cVelocityBarWidth);
  mLeft := ARect.Right - Length(FTile.Sprint.Velocity) * (mBar + ScaleValue(cVelocityBarGap));
  ACanvas.TextOut(mLeft - ACanvas.TextWidth(mCaption) - ScaleValue(cVelocityCaptionGap), ARect.Top + ScaleValue(2),
    mCaption);
  ACanvas.Pen.Style := psClear;
  ACanvas.Brush.Style := bsSolid;
  for mIndex := 0 to High(FTile.Sprint.Velocity) do
  begin
    mHeight := Max(1, Round(FTile.Sprint.Velocity[mIndex] / mTop * ScaleValue(cVelocityHeight)));
    // Ältere Sprints blasser.
    ACanvas.Brush.Color := Blend(mColor, mBack, cVelocityMinPercent + (cFullPercent - cVelocityMinPercent) *
      (mIndex + 1) div Length(FTile.Sprint.Velocity));
    ACanvas.Rectangle(mLeft, ARect.Bottom - mHeight, mLeft + mBar, ARect.Bottom);
    Inc(mLeft, mBar + ScaleValue(cVelocityBarGap));
  end;
  ACanvas.Pen.Style := psSolid;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Assign(Font);
end;

/// <summary>Kachel ohne Sprint: Hinweis bzw. Link „zuordnen …“ in Akzentfarbe, darunter der Stand.</summary>
procedure PaintNotice(AView: TAtlasTrackerSprintView; ACanvas: TCanvas);
var
  mText: string;
  mMuted: TColor;
begin
  mMuted := StyleServices(AView).GetSystemColor(clGrayText);
  if (AView.Tile.Status = TAtlasSprintTileStatus.NoTracker) and AView.Tile.CanAssign then
  begin
    ACanvas.Font.Color := StyleServices(AView).GetSystemColor(clHotLight);
  end
  else
  begin
    ACanvas.Font.Color := mMuted;
  end;
  ACanvas.TextOut(AView.ScaleValue(TAtlasTrackerSprintView.cIndent), AView.ScaleValue(TAtlasTrackerSprintView.cIndent),
    TAtlasTrackerSprintView.NoticeText(AView.Tile));
  mText := TAtlasTrackerSprintView.StatusText(AView.Tile);
  if mText <> '' then
  begin
    ACanvas.Font.Color := mMuted;
    ACanvas.TextOut(AView.ScaleValue(TAtlasTrackerSprintView.cIndent),
      AView.ScaleValue(TAtlasTrackerSprintView.cEmptyHeight), mText);
  end;
end;

/// <summary>Kopf: Name, Zeitraum, Resttage; mit Seite als Link.</summary>
procedure PaintHead(AView: TAtlasTrackerSprintView; ACanvas: TCanvas);
var
  mIndent: Integer;
begin
  mIndent := AView.ScaleValue(TAtlasTrackerSprintView.cIndent);
  ACanvas.Font.Style := [fsBold];
  if AView.Tile.Sprint.Page <> '' then
  begin
    ACanvas.Font.Color := StyleServices(AView).GetSystemColor(clHotLight);
  end
  else
  begin
    ACanvas.Font.Color := StyleServices(AView).GetSystemColor(clWindowText);
  end;
  ACanvas.TextRect(Rect(mIndent, 0, AView.ClientWidth - mIndent, AView.ScaleValue(TAtlasTrackerSprintView.cHeadHeight)),
    mIndent, AView.ScaleValue(cHeadTextTop), TAtlasTrackerSprintView.HeadingText(AView.Tile));
  ACanvas.Font.Assign(AView.Font);
end;

/// <summary>Kleine graue Zeile ab ATop.</summary>
procedure PaintSmall(AView: TAtlasTrackerSprintView; ACanvas: TCanvas; ATop: Integer; const AText: string);
begin
  ACanvas.Font.Assign(AView.Font);
  ACanvas.Font.Size := AView.Font.Size - 1;
  ACanvas.Font.Color := StyleServices(AView).GetSystemColor(clGrayText);
  if AText <> '' then
  begin
    ACanvas.TextOut(AView.ScaleValue(TAtlasTrackerSprintView.cIndent), ATop, AText);
  end;
  ACanvas.Font.Assign(AView.Font);
end;

procedure TAtlasTrackerSprintView.BoxPaint(Sender: TObject);
var
  mCanvas: TCanvas;
  mWidth, mTop: Integer;
begin
  mCanvas := FBox.Canvas;
  mCanvas.Brush.Style := bsClear;
  mCanvas.Font.Assign(Font);
  mWidth := ClientWidth;
  if FTile.Status <> TAtlasSprintTileStatus.Ready then
  begin
    PaintNotice(Self, mCanvas);
    Exit;
  end;
  PaintHead(Self, mCanvas);
  PaintNumbers(mCanvas, mWidth);
  mTop := CompareTop;
  if FTile.Compare then
  begin
    PaintSmall(Self, mCanvas, mTop + ScaleValue(2), CompareText(FTile));
    PaintVelocity(mCanvas, Rect(ScaleValue(cIndent), mTop, mWidth - ScaleValue(cIndent),
      mTop + ScaleValue(cCompareHeight)));
  end;
  if FTile.Burndown then
  begin
    PaintChart(mCanvas, ChartRect(mWidth));
  end;
  PaintSmall(Self, mCanvas, StatusTop(mWidth), StatusText(FTile));
end;

procedure TAtlasTrackerSprintView.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  mHit: TAtlasSprintHitKind;
  mDay: Integer;
  mKey: string;
begin
  mHit := HitTest(X, Y);
  if mHit <> TAtlasSprintHitKind.None then
  begin
    FBox.Cursor := crHandPoint;
  end
  else
  begin
    FBox.Cursor := crDefault;
  end;
  mDay := -1;
  if (mHit = TAtlasSprintHitKind.Chart) and FTile.Burndown and (Y >= ChartRect(ClientWidth).Top) then
  begin
    mDay := DayAt(X, ClientWidth);
  end;
  mKey := Format(cHintKeyFormat, [Ord(mHit), mDay], TFormatSettings.Invariant);
  if mKey = FHintKey then
  begin
    Exit;
  end;
  FHintKey := mKey;
  case mHit of
    TAtlasSprintHitKind.Title:
      FBox.Hint := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintHintBrowse);
    TAtlasSprintHitKind.MineOpen:
      FBox.Hint := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintHintOpen);
    TAtlasSprintHitKind.MineDone:
      FBox.Hint := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintHintDone);
    TAtlasSprintHitKind.TeamLeft:
      FBox.Hint := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintHintBoard);
    TAtlasSprintHitKind.Chart:
      if mDay >= 0 then
      begin
        FBox.Hint := DayHint(FTile, mDay);
      end
      else
      begin
        FBox.Hint := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintHintBoard);
      end;
    TAtlasSprintHitKind.Assign:
      FBox.Hint := TAtlasSprintStrings.Text(TAtlasSprintTextId.WelcomeSprintHintAssign);
  else
    FBox.Hint := '';
  end;
  Application.CancelHint;
end;

procedure TAtlasTrackerSprintView.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if Button = mbLeft then
  begin
    ClickAt(HitTest(X, Y));
  end;
end;

end.
