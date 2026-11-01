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
    Indent = 8;
    HeadHeight = 22;
    NumberHeight = 50;
    NumberGap = 8;
    CompareHeight = 20;
    ChartHeight = 72;
    StatusHeight = 20;
    VelocityBarWidth = 8;
    VelocityHeight = 16;
    EmptyHeight = 40;
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
    procedure Post(const AAction: TThreadProcedure);
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
    function HitTest(X, Y: Integer): TAtlasSprintHitKind;
    /// <summary>Klick wie mit der Maus (auch für Tests).</summary>
    procedure ClickAt(AKind: TAtlasSprintHitKind);
    /// <summary>Tag des Diagramms unter X (0 … DayCount); -1 außerhalb.</summary>
    function DayAt(X, AWidth: Integer): Integer;
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
  Atlas.UI.Strings;

/// <summary>Mischfarbe: APercent Prozent von AFore auf ABack.</summary>
function Blend(AFore, ABack: TColor; APercent: Integer): TColor;
var
  mFore, mBack: Integer;
  mR, mG, mB: Integer;
begin
  mFore := ColorToRGB(AFore);
  mBack := ColorToRGB(ABack);
  mR := ((mFore and $FF) * APercent + (mBack and $FF) * (100 - APercent)) div 100;
  mG := (((mFore shr 8) and $FF) * APercent + ((mBack shr 8) and $FF) * (100 - APercent)) div 100;
  mB := (((mFore shr 16) and $FF) * APercent + ((mBack shr 16) and $FF) * (100 - APercent)) div 100;
  Result := TColor(mR or (mG shl 8) or (mB shl 16));
end;

function LocalDay(AUtc: TDateTime): string;
begin
  Result := FormatDateTime('dd.mm.', TTimeZone.Local.ToLocalTime(AUtc));
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
  Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintTitle);
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
  Result := ScaleValue(HeadHeight) + ScaleValue(NumberHeight) + ScaleValue(NumberGap);
end;

function TAtlasTrackerSprintView.ChartRect(AWidth: Integer): TRect;
var
  mTop: Integer;
begin
  mTop := CompareTop;
  if FTile.Compare and ((CompareText(FTile) <> '') or (Length(FTile.Sprint.Velocity) > 0)) then
  begin
    Inc(mTop, ScaleValue(CompareHeight));
  end;
  if not FTile.Burndown then
  begin
    Exit(Rect(ScaleValue(Indent), mTop, AWidth - ScaleValue(Indent), mTop));
  end;
  Result := Rect(ScaleValue(Indent), mTop + ScaleValue(4), AWidth - ScaleValue(Indent),
    mTop + ScaleValue(4) + ScaleValue(ChartHeight));
end;

function TAtlasTrackerSprintView.StatusTop(AWidth: Integer): Integer;
begin
  Result := ChartRect(AWidth).Bottom + ScaleValue(4);
end;

function TAtlasTrackerSprintView.HeightFor(AWidth: Integer): Integer;
begin
  if FTile.Status <> TAtlasSprintTileStatus.Ready then
  begin
    Result := ScaleValue(EmptyHeight);
    if StatusText(FTile) <> '' then
    begin
      Inc(Result, ScaleValue(StatusHeight));
    end;
    Exit;
  end;
  Result := StatusTop(AWidth);
  if StatusText(FTile) <> '' then
  begin
    Inc(Result, ScaleValue(StatusHeight));
  end;
end;

function TAtlasTrackerSprintView.NumberRect(AIndex, AWidth: Integer): TRect;
var
  mWidth, mLeft: Integer;
begin
  mWidth := (AWidth - 2 * ScaleValue(Indent) - 2 * ScaleValue(NumberGap)) div 3;
  mLeft := ScaleValue(Indent) + AIndex * (mWidth + ScaleValue(NumberGap));
  Result := Rect(mLeft, ScaleValue(HeadHeight), mLeft + mWidth, ScaleValue(HeadHeight) + ScaleValue(NumberHeight));
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
  if SameValue(AValue, Round(AValue), 0.05) then
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
    mDays := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSprintNotStarted, [LocalDay(ATile.Sprint.Start)]);
  end
  else if ATile.Sprint.DaysLeft <= 0 then
  begin
    mDays := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintEnded);
  end
  else if ATile.Sprint.DaysLeft = 1 then
  begin
    mDays := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintDayLeft);
  end
  else
  begin
    mDays := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSprintDaysLeft, [ATile.Sprint.DaysLeft]);
  end;
  // Ende ist exklusiv (Mitternacht danach): als letzten Tag den davor zeigen.
  Result := ATile.Sprint.Name + ' · ' + LocalDay(ATile.Sprint.Start) + '–' +
    LocalDay(ATile.Sprint.Finish - OneSecond) + ' · ' + mDays;
end;

class function TAtlasTrackerSprintView.ErrorText(AError: TAtlasCiFetchError): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorToken);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorTimeout);
    TAtlasCiFetchError.Invalid, TAtlasCiFetchError.Server:
      Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorInvalid);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.IssuePreviewErrorNetwork);
  end;
end;

class function TAtlasTrackerSprintView.NoticeText(const ATile: TAtlasSprintTile): string;
begin
  case ATile.Status of
    TAtlasSprintTileStatus.NoProject:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintNoProject);
    TAtlasSprintTileStatus.NoTracker:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintNoBoard);
    TAtlasSprintTileStatus.NoBoard:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintNoBoardFound);
    TAtlasSprintTileStatus.NoSprint:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintNoSprint);
    TAtlasSprintTileStatus.Loading:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintLoading);
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
    Exit(TAtlasStrings.Text(TAtlasTextId.WelcomeSprintLoading));
  end;
  if ATile.Stale and (ATile.Sprint.Fetched > 0) then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSprintStale, [FormatDateTime('dd.mm. hh:nn',
      TTimeZone.Local.ToLocalTime(ATile.Sprint.Fetched)), ErrorText(ATile.Error)]);
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
  if SameValue(mDelta, 0, 0.05) then
  begin
    mArrow := '=';
  end
  else if mDelta > 0 then
  begin
    mArrow := '▲' + NumberText(mDelta);
  end
  else
  begin
    mArrow := '▼' + NumberText(-mDelta);
  end;
  Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSprintCompare, [NumberText(ATile.Sprint.DoneToday),
    NumberText(ATile.Sprint.PreviousDone), mArrow]);
end;

class function TAtlasTrackerSprintView.NumberCaption(AIndex: Integer): string;
begin
  case AIndex of
    0:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintMineOpen);
    1:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintMineDone);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintTeamLeft);
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
          Exit('–');
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
        Result := Result + TAtlasStrings.Text(TAtlasTextId.WelcomeSprintPoints);
      end
      else
      begin
        Result := Result + TAtlasStrings.Text(TAtlasTextId.WelcomeSprintIssues);
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
  mLeft := '–';
  if ADay <= High(ATile.Sprint.Actual) then
  begin
    mLeft := NumberText(ATile.Sprint.Actual[ADay]);
  end;
  // Tag k ist das Ende des k-ten Arbeitstags; k = 0 der Start.
  mDate := LocalDay(ATile.Sprint.Start);
  if (ADay > 0) and (ADay <= Length(ATile.Sprint.Dates)) then
  begin
    mDate := FormatDateTime('dd.mm.', ATile.Sprint.Dates[ADay - 1]);
  end;
  Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeSprintDayHint, [ADay, mDate, mLeft,
    NumberText(ATile.Sprint.Ideal[ADay])]);
  if ATile.Compare and ATile.Sprint.HasPrevious and (ADay <= High(ATile.Sprint.Previous)) then
  begin
    Result := Result + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.WelcomeSprintDayHintPrevious,
      [NumberText(ATile.Sprint.Previous[ADay])]);
  end;
end;

function TAtlasTrackerSprintView.DayAt(X, AWidth: Integer): Integer;
var
  mArea: TRect;
  mCount: Integer;
begin
  Result := -1;
  mArea := ChartRect(AWidth);
  mCount := Length(FTile.Sprint.Ideal);
  if (mCount = 0) or (mArea.Width <= 0) or (X < mArea.Left) or (X > mArea.Right) then
  begin
    Exit;
  end;
  if mCount = 1 then
  begin
    Exit(0);
  end;
  Result := EnsureRange(Round((X - mArea.Left) * (mCount - 1) / mArea.Width), 0, mCount - 1);
end;

function TAtlasTrackerSprintView.HitTest(X, Y: Integer): TAtlasSprintHitKind;
var
  mWidth, mIndex: Integer;
  mPoint: TPoint;
begin
  Result := TAtlasSprintHitKind.None;
  mWidth := ClientWidth;
  mPoint := Point(X, Y);
  if FTile.Status = TAtlasSprintTileStatus.NoTracker then
  begin
    if FTile.CanAssign and (Y < ScaleValue(EmptyHeight)) then
    begin
      Result := TAtlasSprintHitKind.Assign;
    end;
    Exit;
  end;
  if FTile.Status <> TAtlasSprintTileStatus.Ready then
  begin
    Exit;
  end;
  if Y < ScaleValue(HeadHeight) then
  begin
    if FTile.Sprint.Page <> '' then
    begin
      Result := TAtlasSprintHitKind.Title;
    end;
    Exit;
  end;
  for mIndex := 0 to 2 do
  begin
    if NumberRect(mIndex, mWidth).Contains(mPoint) then
    begin
      case mIndex of
        0:
          if FTile.Sprint.MineKnown then
          begin
            Result := TAtlasSprintHitKind.MineOpen;
          end;
        1:
          if FTile.Sprint.MineKnown then
          begin
            Result := TAtlasSprintHitKind.MineDone;
          end
      else
      begin
        Result := TAtlasSprintHitKind.TeamLeft;
      end;
      end;
      Exit;
    end;
  end;
  // Übrige Kachel (Vergleich, Diagramm): öffnet das Board.
  if Y < StatusTop(mWidth) then
  begin
    Result := TAtlasSprintHitKind.Chart;
  end;
end;

procedure TAtlasTrackerSprintView.Post(const AAction: TThreadProcedure);
begin
  // Die Quelle füllt Bereiche danach neu: nicht im eigenen Mausereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage, AAction);
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
  mPad := ScaleValue(8);
  for mIndex := 0 to 2 do
  begin
    mRect := NumberRect(mIndex, AWidth);
    ACanvas.Brush.Style := bsClear;
    ACanvas.Pen.Style := psSolid;
    ACanvas.Pen.Width := 1;
    ACanvas.Pen.Color := Blend(mMuted, mBack, 35);
    ACanvas.RoundRect(mRect.Left, mRect.Top, mRect.Right, mRect.Bottom, ScaleValue(8), ScaleValue(8));
    ACanvas.Font.Assign(Font);
    ACanvas.Font.Size := Font.Size - 1;
    ACanvas.Font.Color := mMuted;
    ACanvas.TextRect(Rect(mRect.Left + mPad, mRect.Top + ScaleValue(4), mRect.Right - mPad,
      mRect.Top + ScaleValue(4) + ACanvas.TextHeight('Ag')), mRect.Left + mPad, mRect.Top + ScaleValue(4),
      AnsiUpperCase(NumberCaption(mIndex)));
    ACanvas.Font.Assign(Font);
    ACanvas.Font.Size := Font.Size + 3;
    ACanvas.Font.Style := [fsBold];
    // Klickbare Zahlen in Akzentfarbe.
    if (mIndex = 2) or FTile.Sprint.MineKnown then
    begin
      ACanvas.Font.Color := mAccent;
    end
    else
    begin
      ACanvas.Font.Color := mText;
    end;
    ACanvas.TextRect(Rect(mRect.Left + mPad, mRect.Top + ScaleValue(20), mRect.Right - mPad, mRect.Bottom - 2),
      mRect.Left + mPad, mRect.Top + ScaleValue(20), NumberValue(FTile, mIndex));
  end;
  ACanvas.Font.Assign(Font);
end;

procedure TAtlasTrackerSprintView.PaintChart(ACanvas: TCanvas; const ARect: TRect);
var
  mSprint: TAtlasSprintView;
  mTop, mValue: Double;
  mCount, mIndex, mX: Integer;
  mPoints: TArray<TPoint>;
  mLine, mMuted, mBack, mText: TColor;

  function PointOf(ADay: Integer; AValue: Double): TPoint;
  begin
    Result.X := ARect.Left;
    if mCount > 1 then
    begin
      Result.X := ARect.Left + Round(ADay * ARect.Width / (mCount - 1));
    end;
    Result.Y := ARect.Bottom - Round(EnsureRange(AValue / mTop, 0, 1) * ARect.Height);
  end;

  function LineOf(const AValues: TArray<Double>): TArray<TPoint>;
  var
    mDay: Integer;
  begin
    Result := nil;
    for mDay := 0 to Min(High(AValues), mCount - 1) do
    begin
      Result := Result + [PointOf(mDay, AValues[mDay])];
    end;
  end;

begin
  mSprint := FTile.Sprint;
  mCount := Length(mSprint.Ideal);
  if (mCount = 0) or (ARect.Height <= 0) then
  begin
    Exit;
  end;
  mLine := StyleServices(Self).GetSystemColor(clHighlight);
  mMuted := StyleServices(Self).GetSystemColor(clGrayText);
  mBack := StyleServices(Self).GetSystemColor(clWindow);
  mText := StyleServices(Self).GetSystemColor(clWindowText);
  // Eine Skala für alle Linien: der größte Wert, mindestens 1.
  mTop := 1;
  for mValue in mSprint.Ideal do
  begin
    mTop := Max(mTop, mValue);
  end;
  for mValue in mSprint.Actual do
  begin
    mTop := Max(mTop, mValue);
  end;
  if FTile.Compare then
  begin
    for mValue in mSprint.Previous do
    begin
      mTop := Max(mTop, mValue);
    end;
  end;
  // Grundlinie.
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;
  ACanvas.Pen.Color := Blend(mMuted, mBack, 40);
  ACanvas.MoveTo(ARect.Left, ARect.Bottom);
  ACanvas.LineTo(ARect.Right, ARect.Bottom);
  // Vorsprint blass.
  if FTile.Compare and mSprint.HasPrevious then
  begin
    mPoints := LineOf(mSprint.Previous);
    if Length(mPoints) > 1 then
    begin
      ACanvas.Pen.Color := Blend(mMuted, mBack, 45);
      ACanvas.Pen.Width := ScaleValue(2);
      ACanvas.Polyline(mPoints);
    end;
  end;
  // Ideallinie gestrichelt (Stiftbreite 1, sonst zeichnet Windows durchgezogen).
  mPoints := LineOf(mSprint.Ideal);
  if Length(mPoints) > 1 then
  begin
    ACanvas.Pen.Width := 1;
    ACanvas.Pen.Style := psDash;
    ACanvas.Pen.Color := mMuted;
    ACanvas.Brush.Style := bsClear;
    ACanvas.Polyline(mPoints);
    ACanvas.Pen.Style := psSolid;
  end;
  // Ist-Linie.
  mPoints := LineOf(mSprint.Actual);
  ACanvas.Pen.Color := mLine;
  ACanvas.Pen.Width := ScaleValue(2);
  if Length(mPoints) > 1 then
  begin
    ACanvas.Polyline(mPoints);
  end;
  if Length(mPoints) > 0 then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := mLine;
    mIndex := ScaleValue(3);
    ACanvas.Ellipse(mPoints[High(mPoints)].X - mIndex, mPoints[High(mPoints)].Y - mIndex,
      mPoints[High(mPoints)].X + mIndex + 1, mPoints[High(mPoints)].Y + mIndex + 1);
    ACanvas.Brush.Style := bsClear;
  end;
  // Marke „heute“.
  if (mSprint.Today >= 0) and (mSprint.Today < mCount) then
  begin
    mX := PointOf(mSprint.Today, 0).X;
    ACanvas.Pen.Width := 1;
    ACanvas.Pen.Style := psDot;
    ACanvas.Pen.Color := Blend(mText, mBack, 60);
    ACanvas.MoveTo(mX, ARect.Top);
    ACanvas.LineTo(mX, ARect.Bottom);
    ACanvas.Pen.Style := psSolid;
  end;
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
  mCaption := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintVelocity);
  mBar := ScaleValue(VelocityBarWidth);
  mLeft := ARect.Right - Length(FTile.Sprint.Velocity) * (mBar + ScaleValue(3));
  ACanvas.TextOut(mLeft - ACanvas.TextWidth(mCaption) - ScaleValue(6), ARect.Top + ScaleValue(2), mCaption);
  ACanvas.Pen.Style := psClear;
  ACanvas.Brush.Style := bsSolid;
  for mIndex := 0 to High(FTile.Sprint.Velocity) do
  begin
    mHeight := Max(1, Round(FTile.Sprint.Velocity[mIndex] / mTop * ScaleValue(VelocityHeight)));
    // Ältere Sprints blasser.
    ACanvas.Brush.Color := Blend(mColor, mBack, 50 + 50 * (mIndex + 1) div Length(FTile.Sprint.Velocity));
    ACanvas.Rectangle(mLeft, ARect.Bottom - mHeight, mLeft + mBar, ARect.Bottom);
    Inc(mLeft, mBar + ScaleValue(3));
  end;
  ACanvas.Pen.Style := psSolid;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Assign(Font);
end;

procedure TAtlasTrackerSprintView.BoxPaint(Sender: TObject);
var
  mCanvas: TCanvas;
  mWidth, mTop: Integer;
  mText: string;
  mMuted: TColor;
begin
  mCanvas := FBox.Canvas;
  mCanvas.Brush.Style := bsClear;
  mCanvas.Font.Assign(Font);
  mMuted := StyleServices(Self).GetSystemColor(clGrayText);
  mWidth := ClientWidth;
  if FTile.Status <> TAtlasSprintTileStatus.Ready then
  begin
    // Link „zuordnen …“ in Akzentfarbe, sonst grauer Hinweis.
    if (FTile.Status = TAtlasSprintTileStatus.NoTracker) and FTile.CanAssign then
    begin
      mCanvas.Font.Color := StyleServices(Self).GetSystemColor(clHotLight);
    end
    else
    begin
      mCanvas.Font.Color := mMuted;
    end;
    mCanvas.TextOut(ScaleValue(Indent), ScaleValue(Indent), NoticeText(FTile));
    mText := StatusText(FTile);
    if mText <> '' then
    begin
      mCanvas.Font.Color := mMuted;
      mCanvas.TextOut(ScaleValue(Indent), ScaleValue(EmptyHeight), mText);
    end;
    Exit;
  end;
  // Kopf: Name, Zeitraum, Resttage; mit Seite als Link.
  mCanvas.Font.Style := [fsBold];
  if FTile.Sprint.Page <> '' then
  begin
    mCanvas.Font.Color := StyleServices(Self).GetSystemColor(clHotLight);
  end
  else
  begin
    mCanvas.Font.Color := StyleServices(Self).GetSystemColor(clWindowText);
  end;
  mCanvas.TextRect(Rect(ScaleValue(Indent), 0, mWidth - ScaleValue(Indent), ScaleValue(HeadHeight)),
    ScaleValue(Indent), ScaleValue(3), HeadingText(FTile));
  mCanvas.Font.Assign(Font);
  PaintNumbers(mCanvas, mWidth);
  mTop := CompareTop;
  if FTile.Compare then
  begin
    mText := CompareText(FTile);
    mCanvas.Font.Size := Font.Size - 1;
    mCanvas.Font.Color := mMuted;
    if mText <> '' then
    begin
      mCanvas.TextOut(ScaleValue(Indent), mTop + ScaleValue(2), mText);
    end;
    mCanvas.Font.Assign(Font);
    PaintVelocity(mCanvas, Rect(ScaleValue(Indent), mTop, mWidth - ScaleValue(Indent),
      mTop + ScaleValue(CompareHeight)));
  end;
  if FTile.Burndown then
  begin
    PaintChart(mCanvas, ChartRect(mWidth));
  end;
  mText := StatusText(FTile);
  if mText <> '' then
  begin
    mCanvas.Font.Assign(Font);
    mCanvas.Font.Size := Font.Size - 1;
    mCanvas.Font.Color := mMuted;
    mCanvas.TextOut(ScaleValue(Indent), StatusTop(mWidth), mText);
  end;
  mCanvas.Font.Assign(Font);
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
  mKey := IntToStr(Ord(mHit)) + ':' + IntToStr(mDay);
  if mKey = FHintKey then
  begin
    Exit;
  end;
  FHintKey := mKey;
  case mHit of
    TAtlasSprintHitKind.Title:
      FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintHintBrowse);
    TAtlasSprintHitKind.MineOpen:
      FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintHintOpen);
    TAtlasSprintHitKind.MineDone:
      FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintHintDone);
    TAtlasSprintHitKind.TeamLeft:
      FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintHintBoard);
    TAtlasSprintHitKind.Chart:
      if mDay >= 0 then
      begin
        FBox.Hint := DayHint(FTile, mDay);
      end
      else
      begin
        FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintHintBoard);
      end;
    TAtlasSprintHitKind.Assign:
      FBox.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeSprintHintAssign);
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
