unit Atlas.UI.Tracker.TestResults;

// Kachel „Testergebnisse“ des Moduls Tracker (#763, Mockup #ws11; seit #1455
// Kachel über Atlas.IDE.Contracts.WelcomeTiles), ohne Open Tools API. Selbst
// gezeichnet:
//   ● Atlas.Tests  [2 fehlgeschlagen]  412 ok · 3 übersprungen · 18,4 s · 19:41
//     ● Jenkins #482 · 2 fehlgeschlagen · vor 40 Min. · main   lokal grün, Server rot
//   ● Kasse.Tests  [alle 57 ok]        2,1 s · gestern
//   ┃ Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations
//   ┃ Erwartet 3 Deklarationen, gefunden 0 · Atlas.Core.Index.Tests.pas:214
//   ┃ Atlas.Server.Tests.TServerTests.Startet                       [Server]
//   [Fehlgeschlagene erneut ausführen] [Im Debugger] [Im Browser]
// Je Projekt eine Zeile mit Ampel und Marke (lokaler Lauf), darunter bei
// eingetragenem Build-Server die Zeile des letzten Builds; „Stand vom …“, wenn
// der letzte Abruf fehlschlug. Unter den Zeilen die Fehlschläge des gewählten
// Projekts (Klick auf eine Zeile wählt), Server-Fehlschläge mit Marke
// „Server“. Klick wählt einen Fehlschlag (für „Im Debugger“), Doppelklick
// öffnet den Test. Kontextmenü: Build-Server jetzt abfragen, Zugang zum
// Build-Server hinterlegen, Projekt öffnen.
// Texte (TAtlasTrackerTestResultsText), Raster und Zeichnen
// (TAtlasTrackerTestResultsPainter) und Kontextmenü
// (TAtlasTrackerTestResultsMenu) sind eigene Klassen. Daten und Aktionen
// kommen über IAtlasTestResultsSource aus der IDE-Schicht; Aktionen gehen über
// die Nachrichtenschleife, weil die Quelle die Kachel daraufhin neu füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Menus,
  Vcl.Graphics,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.TestResults,
  Atlas.UI.Style.Canvas,
  Atlas.UI.Tracker.TileView;

type
  IAtlasTestResultsSource = interface
    ['{5B7E2C94-1D3A-4F68-9E05-C4A1B8D6F273}']
    function View: TAtlasTestResultsView;
    /// <summary>Zeile wählen (Projektdatei); die Liste zeigt danach deren Fehlschläge.</summary>
    procedure Select(const AProject: string);
    /// <summary>Projekt öffnen und zum Test springen (auch für Fehlschläge vom Server).</summary>
    procedure OpenTest(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
    /// <summary>„Fehlgeschlagene erneut ausführen“: genau ATests im Testprojekt der Zeile.</summary>
    procedure RerunFailed(const ARow: TAtlasTestRow; const ATests: TArray<string>);
    /// <summary>„Im Debugger“ (#585): den Test unter dem Debugger starten.</summary>
    procedure Debug(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
    /// <summary>„Im Browser“: Seite des Builds auf dem Server.</summary>
    procedure Browse(const ARow: TAtlasTestRow);
    /// <summary>Build-Server jetzt abfragen (ohne auf den Abstand zu warten).</summary>
    procedure QueryNow(const ARow: TAtlasTestRow);
    /// <summary>„Zugang zum Build-Server hinterlegen …“.</summary>
    procedure Credentials(const ARow: TAtlasTestRow);
    procedure OpenProject(const ARow: TAtlasTestRow);
    /// <summary>Befehl für den Zugang eingeschaltet (Einstellung CiLogin).</summary>
    function CanEnterCredentials: Boolean;
    /// <summary>Die Kachel wird gezeigt: bei Bedarf den Server im Hintergrund fragen.</summary>
    procedure Shown;
  end;

{$SCOPEDENUMS ON}
  TAtlasTestResultsHitKind = (None, Row, Failure, Rerun, Debug, Browse, More);
  TAtlasTestResultsButton = (Rerun, Debug, Browse);
{$SCOPEDENUMS OFF}

  TAtlasTestResultsHit = record
    Kind: TAtlasTestResultsHitKind;
    /// <summary>Zeile bzw. Fehlschlag; -1 sonst.</summary>
    Index: Integer;
    class function Create(AKind: TAtlasTestResultsHitKind; AIndex: Integer): TAtlasTestResultsHit; static;
  end;

  /// <summary>Aktion der Quelle mit einer Zeile, nach dem eigenen Ereignis ausgeführt.</summary>
  TAtlasTestResultsRowAction = reference to procedure(const ASource: IAtlasTestResultsSource;
    const ARow: TAtlasTestRow);

  /// <summary>Texte und Farben der Kachel; reine Funktionen.</summary>
  TAtlasTrackerTestResultsText = class
  public const
    cSeparator = ' · ';
  private
    /// <summary>„Jenkins #482 · 2 fehlgeschlagen · vor 40 Min.“ bzw. „Jenkins · nicht erreichbar“.</summary>
    class function CiHead(const ARow: TAtlasTestRow; ANowUtc: TDateTime): TArray<string>; static;
    /// <summary>Ende des Builds (Start plus Dauer), sonst der Abruf.</summary>
    class function FinishedUtc(const ARow: TAtlasTestRow): TDateTime; static;
    /// <summary>„Stand vom …“ bzw. „wird abgefragt …“ hinter der Zeile; '' ohne.</summary>
    class function CiTail(const ARow: TAtlasTestRow): string; static;
    class function RunText(const ARow: TAtlasTestRow): string; static;
    class function FileNameOnly(const APath: string): string; static;
  public
    class function NowUtc: TDateTime; static;
    /// <summary>Marke des lokalen Laufs: „2 fehlgeschlagen“, „alle 57 ok“, „keine Tests gelaufen“, „noch kein Lauf“.
    /// </summary>
    class function PillText(const ARow: TAtlasTestRow): string; static;
    /// <summary>„412 ok · 3 übersprungen · 18,4 s · 19:41“ bzw. „2,1 s · gestern“.</summary>
    class function LocalText(const ARow: TAtlasTestRow; ANowUtc: TDateTime): string; static;
    /// <summary>„Jenkins #482 · 2 fehlgeschlagen · vor 40 Min. · main“, mit „Stand vom …“ nach einem Fehler.
    /// </summary>
    class function CiText(const ARow: TAtlasTestRow; ANowUtc: TDateTime): string; static;
    /// <summary>„lokal grün, Server rot“ bzw. „lokal rot, Server grün“; '' ohne Abweichung.</summary>
    class function MismatchText(AMismatch: TAtlasTestMismatch): string; static;
    /// <summary>Ergebnis eines Builds: „2 fehlgeschlagen“, „alle 410 ok“, „instabil“ …</summary>
    class function BuildText(const ABuild: TAtlasCiBuild): string; static;
    /// <summary>Grund ohne Build: „nicht erreichbar“, „Anmeldung abgelehnt“ …</summary>
    class function ErrorText(AError: TAtlasCiFetchError): string; static;
    /// <summary>„18,4 s“, „2:05 min“.</summary>
    class function DurationText(AMs: Int64): string; static;
    /// <summary>Uhrzeit heute, „gestern“, sonst Datum.</summary>
    class function WhenText(AUtc, ANowUtc: TDateTime): string; static;
    /// <summary>„vor 40 Min.“, „vor 3 Std.“, „gestern“, „vor 4 Tagen“; „gerade eben“ unter einer Minute.</summary>
    class function AgoText(AUtc, ANowUtc: TDateTime): string; static;
    /// <summary>Zweite Zeile eines Fehlschlags: „Meldung · Datei.pas:214“.</summary>
    class function FailureDetail(const AItem: TAtlasTestFailureItem): string; static;
    /// <summary>Hinweis über einem Fehlschlag.</summary>
    class function FailureHint(const AItem: TAtlasTestFailureItem): string; static;
    class function EmptyText: string; static;
    class function MoreText(ACount: Integer): string; static;
    class function ServerTag: string; static;
    class function ButtonText(AButton: TAtlasTestResultsButton): string; static;
    class function LevelColor(ALevel: TAtlasTestLevel): TColor; static;
    class function RowHint(const ARow: TAtlasTestRow): string; static;
  end;

  TAtlasTrackerTestResultsView = class;

  /// <summary>Raster, Zeichnen und Trefferflächen der Kachel.</summary>
  TAtlasTrackerTestResultsPainter = class
  public const
    cIndent = 8;
    cDotSize = 10;
    cLineHeight = 22;
    cCiLineHeight = 20;
    cRowGap = 4;
    cListGap = 6;
    cFailureHeight = 38;
    cMoreHeight = 20;
    cButtonsHeight = 30;
    cButtonHeight = 24;
    cButtonPadding = 10;
    cPillHeight = 18;
    cPillPadding = 6;
    cBarWidth = 3;
    /// <summary>Abstand zwischen Elementen einer Zeile.</summary>
    cGap = 8;
    cSmallGap = 4;
    /// <summary>Ampel: Abstand nach oben und zum Namen.</summary>
    cDotTop = 6;
    cDotGap = 6;
    /// <summary>Kleiner Punkt der Zeile des Build-Servers.</summary>
    cCiDotTop = 5;
    cMonoTop = 3;
    /// <summary>Fehlschlag: Höhe der Zeile mit dem Testnamen und Unterkante der Meldung.</summary>
    cTestHeight = 18;
    cDetailBottom = 34;
    cCorner = 6;
    cMonoFont = 'Consolas';
  private
    FOwner: TAtlasTrackerTestResultsView;
    FButtonRects: array[TAtlasTestResultsButton] of TRect;
    function Scaled(AValue: Integer): Integer;
    function Color(ASystemColor: TColor): TColor;
    function Limit: Integer;
    procedure PaintDot(ACanvas: TCanvas; const AArea: TRect; AColor: TColor);
    /// <summary>Marke mit weißer Schrift; Ergebnis ist ihre Fläche.</summary>
    function PaintPill(ACanvas: TCanvas; ALeft, ATop: Integer; const AText: string; AColor: TColor): TRect;
    procedure PaintSelection(ACanvas: TCanvas; AIndex, ATop: Integer);
    procedure PaintLocalLine(ACanvas: TCanvas; AIndex: Integer; ANowUtc: TDateTime);
    procedure PaintCiLine(ACanvas: TCanvas; AIndex: Integer; ANowUtc: TDateTime);
    procedure PaintMismatch(ACanvas: TCanvas; const ARow: TAtlasTestRow; ALeft, ATop: Integer);
    procedure PaintFailure(ACanvas: TCanvas; AIndex: Integer);
    procedure PaintButton(ACanvas: TCanvas; AButton: TAtlasTestResultsButton; var ALeft: Integer);
    procedure PaintButtons(ACanvas: TCanvas);
    procedure PaintEmpty(ACanvas: TCanvas);
    procedure PaintMore(ACanvas: TCanvas);
    function ButtonHit(const APoint: TPoint): TAtlasTestResultsHit;
  public
    constructor Create(AOwner: TAtlasTrackerTestResultsView);
    procedure Paint(ACanvas: TCanvas);
    function HitTest(AX, AY: Integer): TAtlasTestResultsHit;
    function RowHeight(AIndex: Integer): Integer;
    function RowTop(AIndex: Integer): Integer;
    function ListTop: Integer;
    function FailureTop(AIndex: Integer): Integer;
    function ButtonsTop: Integer;
    /// <summary>Höhe der Kachel ohne Titelzeile.</summary>
    function Height: Integer;
  end;

  /// <summary>Kontextmenü: Build-Server jetzt abfragen, Zugang hinterlegen, Projekt öffnen.</summary>
  TAtlasTrackerTestResultsMenu = class
  private
    FOwner: TAtlasTrackerTestResultsView;
    FMenu: TPopupMenu;
    FQueryItem: TMenuItem;
    FCredentialsItem: TMenuItem;
    FOpenItem: TMenuItem;
    FMenuRow: Integer;
    function AddItem(const ACaption: string; const AClick: TNotifyEvent): TMenuItem;
    procedure MenuPopup(Sender: TObject);
    procedure SendMenuRow(const AAction: TAtlasTestResultsRowAction);
    procedure QueryClick(Sender: TObject);
    procedure CredentialsClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
  public
    constructor Create(AOwner: TAtlasTrackerTestResultsView);
    property Menu: TPopupMenu read FMenu;
    property QueryItem: TMenuItem read FQueryItem;
    property CredentialsItem: TMenuItem read FCredentialsItem;
    property OpenItem: TMenuItem read FOpenItem;
    property MenuRow: Integer read FMenuRow write FMenuRow;
  end;

  TAtlasTrackerTestResultsView = class(TAtlasTrackerTileView)
  private
    FSource: IAtlasTestResultsSource;
    FBox: TAtlasStyledCanvas;
    FView: TAtlasTestResultsView;
    FFailure: Integer;
    FPainter: TAtlasTrackerTestResultsPainter;
    FMenus: TAtlasTrackerTestResultsMenu;
    FHintKey: string;
    FLastMouse: TPoint;
    FDoubleDown: Boolean;
    procedure SetSource(const AValue: IAtlasTestResultsSource);
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; AX, AY: Integer);
    procedure BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; AX, AY: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; AX, AY: Integer);
    procedure BoxDblClick(Sender: TObject);
    procedure ClickRow(AIndex: Integer);
    procedure ClickButton(AKind: TAtlasTestResultsHitKind; const ARow: TAtlasTestRow);
    function HintOf(const AHit: TAtlasTestResultsHit): string;
    class procedure Post(const AAction: TThreadProcedure); static;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function BodyHeight: Integer; override;
    procedure UpdateContent; override;
    function HitTest(AX, AY: Integer): TAtlasTestResultsHit;
    /// <summary>Klick wie mit der Maus (auch für Tests): Zeile wählen, Fehlschlag wählen, Schaltfläche.</summary>
    procedure ClickAt(const AHit: TAtlasTestResultsHit);
    /// <summary>Doppelklick: auf einem Fehlschlag den Test öffnen, auf einer Zeile das Projekt.</summary>
    procedure DoubleClickAt(const AHit: TAtlasTestResultsHit);
    /// <summary>Schaltfläche nutzbar: Rerun mit Namen, Debug mit lokalem Fehlschlag, Browse mit Build.</summary>
    function ButtonEnabled(AButton: TAtlasTestResultsButton): Boolean;
    function ButtonVisible(AButton: TAtlasTestResultsButton): Boolean;
    /// <summary>Gewählter Fehlschlag, ohne Wahl der erste lokale bzw. der erste überhaupt.</summary>
    function SelectedFailure(out AItem: TAtlasTestFailureItem): Boolean;
    /// <summary>AAction mit der Quelle und ARow nach dem eigenen Ereignis; nichts ohne Quelle.</summary>
    procedure SendRow(const ARow: TAtlasTestRow; const AAction: TAtlasTestResultsRowAction);
    property Source: IAtlasTestResultsSource read FSource write SetSource;
    property View: TAtlasTestResultsView read FView;
    /// <summary>Gewählter Fehlschlag in der Liste; -1 = keiner (Im Debugger nimmt dann den ersten lokalen).
    /// </summary>
    property Failure: Integer read FFailure write FFailure;
    property PaintBox: TAtlasStyledCanvas read FBox;
    property Painter: TAtlasTrackerTestResultsPainter read FPainter;
    property Menus: TAtlasTrackerTestResultsMenu read FMenus;
  end;

implementation

uses
  System.UITypes,
  System.Math,
  System.DateUtils,
  Vcl.Forms,
  Vcl.Themes,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Strings;

const
  // Dieselben Töne wie die Marken im Bereich „Projekte“: lesbar im hellen und im dunklen Thema.
  cPassedColor = TColor($0043A02E);
  cWarningColor = TColor($001A8CC9);
  cFailedColor = TColor($002E22CF);
  cUnknownColor = TColor($00817666);
  cMsPerMinute = 60000;
  cMinutesPerHour = 60;
  cDateTimeFormat = 'ddddd t';
  cMinutesFormat = '%d:%.2d min';

{ TAtlasTestResultsHit }

class function TAtlasTestResultsHit.Create(AKind: TAtlasTestResultsHitKind; AIndex: Integer): TAtlasTestResultsHit;
begin
  Result.Kind := AKind;
  Result.Index := AIndex;
end;

{ TAtlasTrackerTestResultsText }

class function TAtlasTrackerTestResultsText.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasTrackerTestResultsText.PillText(const ARow: TAtlasTestRow): string;
begin
  case ARow.LocalLevel of
    TAtlasTestLevel.Failed:
      begin
        Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsFailed,
          [Max(ARow.Local.Failed + ARow.Local.Errors, Integer(Length(ARow.Local.Failures)))]);
      end;
    TAtlasTestLevel.Passed:
      begin
        Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsAllPassed, [ARow.Local.Passed]);
      end;
    TAtlasTestLevel.Warning:
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsNonePassed);
      end;
  else
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsNoLocalRun);
  end;
end;

class function TAtlasTrackerTestResultsText.DurationText(AMs: Int64): string;
var
  mSeconds: Int64;
begin
  if AMs < cMsPerMinute then
  begin
    Result := FormatFloat('0.0', AMs / MSecsPerSec, FormatSettings) + ' s';
  end
  else
  begin
    mSeconds := AMs div MSecsPerSec;
    Result := Format(cMinutesFormat, [mSeconds div SecsPerMin, mSeconds mod SecsPerMin]);
  end;
end;

class function TAtlasTrackerTestResultsText.WhenText(AUtc, ANowUtc: TDateTime): string;
var
  mAtLocal, mNowLocal: TDateTime;
begin
  Result := '';
  if AUtc <= 0 then
  begin
    Exit;
  end;
  mAtLocal := TTimeZone.Local.ToLocalTime(AUtc);
  mNowLocal := TTimeZone.Local.ToLocalTime(ANowUtc);
  if Trunc(mAtLocal) = Trunc(mNowLocal) then
  begin
    Result := FormatDateTime('t', mAtLocal);
  end
  else if Trunc(mAtLocal) = Trunc(mNowLocal) - 1 then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsYesterday);
  end
  else
  begin
    Result := FormatDateTime('ddddd', mAtLocal);
  end;
end;

class function TAtlasTrackerTestResultsText.AgoText(AUtc, ANowUtc: TDateTime): string;
var
  mMinutes, mDays: Int64;
begin
  Result := '';
  if AUtc <= 0 then
  begin
    Exit;
  end;
  mMinutes := Max(Int64(0), Trunc((ANowUtc - AUtc) * MinsPerDay));
  mDays := Trunc(TTimeZone.Local.ToLocalTime(ANowUtc)) - Trunc(TTimeZone.Local.ToLocalTime(AUtc));
  if mMinutes < 1 then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsJustNow);
  end
  else if mMinutes < cMinutesPerHour then
  begin
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsMinutesAgo, [mMinutes]);
  end
  else if mDays <= 0 then
  begin
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsHoursAgo, [mMinutes div cMinutesPerHour]);
  end
  else if mDays = 1 then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsYesterday);
  end
  else
  begin
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsDaysAgo, [mDays]);
  end;
end;

class function TAtlasTrackerTestResultsText.LocalText(const ARow: TAtlasTestRow; ANowUtc: TDateTime): string;
var
  mParts: TArray<string>;
begin
  Result := '';
  if not ARow.Local.Known then
  begin
    Exit;
  end;
  mParts := nil;
  // Die Marke nennt bei „alle ok“ schon die Zahl.
  if ARow.LocalLevel <> TAtlasTestLevel.Passed then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsPassed, [ARow.Local.Passed])];
  end;
  if ARow.Local.Skipped > 0 then
  begin
    mParts := mParts + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsSkipped, [ARow.Local.Skipped])];
  end;
  if ARow.Local.DurationMs > 0 then
  begin
    mParts := mParts + [DurationText(ARow.Local.DurationMs)];
  end;
  if ARow.Local.At > 0 then
  begin
    mParts := mParts + [WhenText(ARow.Local.At, ANowUtc)];
  end;
  Result := string.Join(cSeparator, mParts);
end;

class function TAtlasTrackerTestResultsText.BuildText(const ABuild: TAtlasCiBuild): string;
begin
  if ABuild.TestsKnown and ((ABuild.Failed > 0) or (Length(ABuild.Failures) > 0)) then
  begin
    Exit(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsFailed,
      [Max(ABuild.Failed, Integer(Length(ABuild.Failures)))]));
  end;
  case ABuild.Outcome of
    TAtlasCiOutcome.Success:
      begin
        if ABuild.TestsKnown and (ABuild.Passed > 0) then
        begin
          Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsAllPassed, [ABuild.Passed]);
        end
        else
        begin
          Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsBuildSuccess);
        end;
      end;
    TAtlasCiOutcome.Failure:
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsBuildFailure);
      end;
    TAtlasCiOutcome.Unstable:
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsBuildUnstable);
      end;
    TAtlasCiOutcome.Aborted:
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsBuildAborted);
      end;
    TAtlasCiOutcome.NotBuilt:
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsBuildNotBuilt);
      end;
  else
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsBuildUnknown);
  end;
end;

class function TAtlasTrackerTestResultsText.ErrorText(AError: TAtlasCiFetchError): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized, TAtlasCiFetchError.NoCredentials:
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsCiUnauthorized);
      end;
    TAtlasCiFetchError.NotFound:
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsCiNotFound);
      end;
    TAtlasCiFetchError.Timeout:
      begin
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiTimeout);
      end;
    TAtlasCiFetchError.Server, TAtlasCiFetchError.Invalid:
      begin
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiServerError);
      end;
    TAtlasCiFetchError.UnknownProvider:
      begin
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiUnknownProvider);
      end;
    TAtlasCiFetchError.None:
      begin
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiNotQueried);
      end;
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiUnreachable);
  end;
end;

class function TAtlasTrackerTestResultsText.FinishedUtc(const ARow: TAtlasTestRow): TDateTime;
begin
  Result := ARow.Ci.Build.StartedUtc;
  if (Result > 0) and (ARow.Ci.Build.DurationMs > 0) then
  begin
    Result := Result + ARow.Ci.Build.DurationMs / MSecsPerDay;
  end;
  if Result <= 0 then
  begin
    Result := ARow.Ci.At;
  end;
end;

class function TAtlasTrackerTestResultsText.CiHead(const ARow: TAtlasTestRow; ANowUtc: TDateTime): TArray<string>;
var
  mHead: string;
  mFinished: TDateTime;
begin
  mHead := TAtlasTestResults.ProviderCaption(ARow.Job.Provider);
  if ARow.Ci.HasBuild then
  begin
    Result := [mHead + ' #' + IntToStr(ARow.Ci.Build.Number), BuildText(ARow.Ci.Build)];
    mFinished := FinishedUtc(ARow);
    if mFinished > 0 then
    begin
      Result := Result + [AgoText(mFinished, ANowUtc)];
    end;
  end
  else if ARow.CiQuerying then
  begin
    Result := [mHead, TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsCiQuerying)];
  end
  else
  begin
    Result := [mHead, ErrorText(ARow.Ci.Error)];
  end;
end;

class function TAtlasTrackerTestResultsText.CiTail(const ARow: TAtlasTestRow): string;
begin
  Result := '';
  if ARow.CiStale and (ARow.Ci.At > 0) then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsStale,
      [FormatDateTime(cDateTimeFormat, TTimeZone.Local.ToLocalTime(ARow.Ci.At), FormatSettings)]);
  end
  else if ARow.CiQuerying and ARow.Ci.HasBuild then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsCiQuerying);
  end;
end;

class function TAtlasTrackerTestResultsText.CiText(const ARow: TAtlasTestRow; ANowUtc: TDateTime): string;
var
  mParts: TArray<string>;
  mTail: string;
begin
  Result := '';
  if not ARow.HasCi then
  begin
    Exit;
  end;
  mParts := CiHead(ARow, ANowUtc);
  // Branch des Multibranch-Jobs, sonst der Job.
  if ARow.Job.JobBranch <> '' then
  begin
    mParts := mParts + [ARow.Job.JobBranch];
  end
  else
  begin
    mParts := mParts + [ARow.Job.Job];
  end;
  mTail := CiTail(ARow);
  if mTail <> '' then
  begin
    mParts := mParts + [mTail];
  end;
  Result := string.Join(cSeparator, mParts);
end;

class function TAtlasTrackerTestResultsText.MismatchText(AMismatch: TAtlasTestMismatch): string;
begin
  case AMismatch of
    TAtlasTestMismatch.LocalGreenServerRed:
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsLocalGreenServerRed);
      end;
    TAtlasTestMismatch.LocalRedServerGreen:
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsLocalRedServerGreen);
      end;
  else
    Result := '';
  end;
end;

class function TAtlasTrackerTestResultsText.FileNameOnly(const APath: string): string;
var
  mIndex: Integer;
begin
  Result := APath;
  for mIndex := Length(Result) downto 1 do
  begin
    if CharInSet(Result[mIndex], ['\', '/']) then
    begin
      Exit(Copy(Result, mIndex + 1, MaxInt));
    end;
  end;
end;

class function TAtlasTrackerTestResultsText.FailureDetail(const AItem: TAtlasTestFailureItem): string;
var
  mPlace: string;
begin
  mPlace := '';
  if AItem.FileName <> '' then
  begin
    mPlace := FileNameOnly(AItem.FileName);
    if AItem.Line > 0 then
    begin
      mPlace := mPlace + ':' + IntToStr(AItem.Line);
    end;
  end;
  Result := AItem.Message;
  if (Result <> '') and (mPlace <> '') then
  begin
    Result := Result + cSeparator + mPlace;
  end
  else if mPlace <> '' then
  begin
    Result := mPlace;
  end;
end;

class function TAtlasTrackerTestResultsText.FailureHint(const AItem: TAtlasTestFailureItem): string;
begin
  Result := AItem.Test + sLineBreak + AItem.Message + sLineBreak +
    TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsHintFailure);
end;

class function TAtlasTrackerTestResultsText.EmptyText: string;
begin
  Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsEmpty);
end;

class function TAtlasTrackerTestResultsText.MoreText(ACount: Integer): string;
begin
  Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsMore, [ACount]);
end;

class function TAtlasTrackerTestResultsText.ServerTag: string;
begin
  Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsServerTag);
end;

class function TAtlasTrackerTestResultsText.ButtonText(AButton: TAtlasTestResultsButton): string;
begin
  case AButton of
    TAtlasTestResultsButton.Rerun:
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsRerun);
      end;
    TAtlasTestResultsButton.Debug:
      begin
        Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsDebug);
      end;
  else
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsBrowse);
  end;
end;

class function TAtlasTrackerTestResultsText.LevelColor(ALevel: TAtlasTestLevel): TColor;
begin
  case ALevel of
    TAtlasTestLevel.Passed:
      begin
        Result := cPassedColor;
      end;
    TAtlasTestLevel.Warning:
      begin
        Result := cWarningColor;
      end;
    TAtlasTestLevel.Failed:
      begin
        Result := cFailedColor;
      end;
  else
    Result := cUnknownColor;
  end;
end;

class function TAtlasTrackerTestResultsText.RunText(const ARow: TAtlasTestRow): string;
var
  mRun: string;
begin
  mRun := string.Join(' ', [ARow.Local.Configuration, ARow.Local.Platform]).Trim;
  if mRun <> '' then
  begin
    mRun := '(' + mRun + ')';
  end;
  Result := Trim(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsHintLocal, [ARow.Local.Passed,
    ARow.Local.Failed + ARow.Local.Errors, ARow.Local.Skipped, mRun]));
end;

class function TAtlasTrackerTestResultsText.RowHint(const ARow: TAtlasTestRow): string;
var
  mLines: TArray<string>;
begin
  mLines := [ARow.TestProject];
  if ARow.TestProject = '' then
  begin
    mLines := [ARow.Project];
  end;
  if ARow.Local.Known then
  begin
    mLines := mLines + [RunText(ARow)];
  end;
  if ARow.HasCi then
  begin
    mLines := mLines + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsHintJob,
      [TAtlasTestResults.ProviderCaption(ARow.Job.Provider), ARow.Job.Job])];
    if ARow.Ci.Error <> TAtlasCiFetchError.None then
    begin
      mLines := mLines + [ErrorText(ARow.Ci.Error)];
    end;
    if ARow.Ci.Attempt > 0 then
    begin
      mLines := mLines + [TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.WelcomeTestsHintAttempt,
        [FormatDateTime(cDateTimeFormat, TTimeZone.Local.ToLocalTime(ARow.Ci.Attempt), FormatSettings)])];
    end;
  end;
  mLines := mLines + [TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsHintClick)];
  Result := string.Join(sLineBreak, mLines);
end;

{ TAtlasTrackerTestResultsPainter }

constructor TAtlasTrackerTestResultsPainter.Create(AOwner: TAtlasTrackerTestResultsView);
begin
  inherited Create;
  FOwner := AOwner;
end;

function TAtlasTrackerTestResultsPainter.Scaled(AValue: Integer): Integer;
begin
  Result := FOwner.ScaleValue(AValue);
end;

function TAtlasTrackerTestResultsPainter.Color(ASystemColor: TColor): TColor;
begin
  Result := StyleServices(FOwner).GetSystemColor(ASystemColor);
end;

function TAtlasTrackerTestResultsPainter.Limit: Integer;
begin
  Result := FOwner.PaintBox.Width - Scaled(cIndent);
end;

function TAtlasTrackerTestResultsPainter.RowHeight(AIndex: Integer): Integer;
begin
  Result := Scaled(cLineHeight) + Scaled(cRowGap);
  if (AIndex >= 0) and (AIndex <= High(FOwner.View.Rows)) and FOwner.View.Rows[AIndex].HasCi then
  begin
    Inc(Result, Scaled(cCiLineHeight));
  end;
end;

function TAtlasTrackerTestResultsPainter.RowTop(AIndex: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := Scaled(cIndent) div 2;
  for mIndex := 0 to AIndex - 1 do
  begin
    Inc(Result, RowHeight(mIndex));
  end;
end;

function TAtlasTrackerTestResultsPainter.ListTop: Integer;
begin
  Result := RowTop(Length(FOwner.View.Rows)) + Scaled(cListGap);
end;

function TAtlasTrackerTestResultsPainter.FailureTop(AIndex: Integer): Integer;
begin
  Result := ListTop + AIndex * Scaled(cFailureHeight);
end;

function TAtlasTrackerTestResultsPainter.ButtonsTop: Integer;
begin
  Result := FailureTop(Length(FOwner.View.Failures));
  if FOwner.View.More > 0 then
  begin
    Inc(Result, Scaled(cMoreHeight));
  end;
end;

function TAtlasTrackerTestResultsPainter.Height: Integer;
begin
  if FOwner.View.Empty then
  begin
    Exit(Scaled(cLineHeight) * 2 + Scaled(cIndent));
  end;
  Result := ButtonsTop + Scaled(cButtonsHeight) + Scaled(cIndent) div 2;
end;

procedure TAtlasTrackerTestResultsPainter.PaintDot(ACanvas: TCanvas; const AArea: TRect; AColor: TColor);
begin
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := AColor;
  ACanvas.Pen.Color := AColor;
  ACanvas.Ellipse(AArea.Left, AArea.Top, AArea.Right, AArea.Bottom);
  ACanvas.Brush.Style := bsClear;
end;

function TAtlasTrackerTestResultsPainter.PaintPill(ACanvas: TCanvas; ALeft, ATop: Integer; const AText: string;
  AColor: TColor): TRect;
var
  mRadius: Integer;
begin
  Result := Rect(ALeft, ATop, ALeft + ACanvas.TextWidth(AText) + 2 * Scaled(cPillPadding), ATop + Scaled(cPillHeight));
  mRadius := Scaled(cPillHeight);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := AColor;
  ACanvas.Pen.Color := AColor;
  ACanvas.RoundRect(Result.Left, Result.Top, Result.Right, Result.Bottom, mRadius, mRadius);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Color := clWhite;
  ACanvas.TextOut(Result.Left + Scaled(cPillPadding), Result.Top + (Result.Height - ACanvas.TextHeight(AText)) div 2,
    AText);
end;

procedure TAtlasTrackerTestResultsPainter.PaintSelection(ACanvas: TCanvas; AIndex, ATop: Integer);
begin
  // Gewählte Zeile mit einem Balken in der Markierungsfarbe des Themas (wie „Projekte“, #758).
  if (AIndex = FOwner.View.Selected) and (Length(FOwner.View.Rows) > 1) then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := Color(clHighlight);
    ACanvas.FillRect(Rect(0, ATop, Scaled(cBarWidth), ATop + RowHeight(AIndex) - Scaled(cRowGap)));
  end;
end;

procedure TAtlasTrackerTestResultsPainter.PaintLocalLine(ACanvas: TCanvas; AIndex: Integer; ANowUtc: TDateTime);
var
  mRow: TAtlasTestRow;
  mTop, mLeft, mDot: Integer;
  mText: string;
  mLevel: TAtlasTestLevel;
begin
  mRow := FOwner.View.Rows[AIndex];
  mTop := RowTop(AIndex);
  mLeft := Scaled(cIndent);
  mDot := Scaled(cDotSize);
  PaintSelection(ACanvas, AIndex, mTop);
  // Ampel des lokalen Laufs (ohne lokalen Lauf die des Servers).
  mLevel := mRow.CiLevel;
  if mRow.Local.Known then
  begin
    mLevel := mRow.LocalLevel;
  end;
  PaintDot(ACanvas, Rect(mLeft, mTop + Scaled(cDotTop), mLeft + mDot, mTop + Scaled(cDotTop) + mDot),
    TAtlasTrackerTestResultsText.LevelColor(mLevel));
  Inc(mLeft, mDot + Scaled(cDotGap));
  ACanvas.Font.Assign(FOwner.Font);
  ACanvas.Font.Color := Color(clWindowText);
  ACanvas.Font.Style := [fsBold];
  ACanvas.TextRect(Rect(mLeft, mTop + Scaled(2), Limit, mTop + Scaled(cLineHeight)), mLeft, mTop + Scaled(2),
    mRow.Name);
  Inc(mLeft, ACanvas.TextWidth(mRow.Name) + Scaled(cGap));
  ACanvas.Font.Style := [];
  // Marke des lokalen Laufs.
  if mRow.Local.Known and (mLeft < Limit) then
  begin
    ACanvas.Font.Size := FOwner.Font.Size - 1;
    mLeft := PaintPill(ACanvas, mLeft, mTop + Scaled(2), TAtlasTrackerTestResultsText.PillText(mRow),
      TAtlasTrackerTestResultsText.LevelColor(mRow.LocalLevel)).Right + Scaled(cGap);
    ACanvas.Font.Size := FOwner.Font.Size;
  end;
  // Zahlen, Dauer und Zeit in gedämpfter Schrift (Mockup: mono).
  mText := TAtlasTrackerTestResultsText.LocalText(mRow, ANowUtc);
  if (mText <> '') and (mLeft < Limit) then
  begin
    ACanvas.Font.Name := cMonoFont;
    ACanvas.Font.Size := FOwner.Font.Size - 1;
    ACanvas.Font.Color := Color(clGrayText);
    ACanvas.TextRect(Rect(mLeft, mTop + Scaled(cMonoTop), Limit, mTop + Scaled(cLineHeight)), mLeft,
      mTop + Scaled(cMonoTop), mText);
  end;
  ACanvas.Font.Assign(FOwner.Font);
end;

procedure TAtlasTrackerTestResultsPainter.PaintMismatch(ACanvas: TCanvas; const ARow: TAtlasTestRow; ALeft,
  ATop: Integer);
var
  mText: string;
begin
  mText := TAtlasTrackerTestResultsText.MismatchText(ARow.Mismatch);
  if (mText = '') or (ALeft >= Limit) then
  begin
    Exit;
  end;
  ACanvas.Font.Style := [fsBold];
  if ARow.Mismatch = TAtlasTestMismatch.LocalGreenServerRed then
  begin
    ACanvas.Font.Color := TAtlasTrackerTestResultsText.LevelColor(TAtlasTestLevel.Failed);
  end
  else
  begin
    ACanvas.Font.Color := TAtlasTrackerTestResultsText.LevelColor(TAtlasTestLevel.Warning);
  end;
  ACanvas.TextRect(Rect(ALeft, ATop + Scaled(1), Limit, ATop + Scaled(cCiLineHeight)), ALeft, ATop + Scaled(1), mText);
end;

procedure TAtlasTrackerTestResultsPainter.PaintCiLine(ACanvas: TCanvas; AIndex: Integer; ANowUtc: TDateTime);
var
  mRow: TAtlasTestRow;
  mTop, mLeft, mDot: Integer;
  mText: string;
begin
  mRow := FOwner.View.Rows[AIndex];
  if not mRow.HasCi then
  begin
    Exit;
  end;
  // Zeile des Build-Servers: kleiner Punkt, Text, Abweichung hervorgehoben.
  mTop := RowTop(AIndex) + Scaled(cLineHeight);
  mDot := Scaled(cDotSize);
  mLeft := Scaled(cIndent) + mDot + Scaled(cDotGap);
  PaintDot(ACanvas, Rect(mLeft, mTop + Scaled(cCiDotTop), mLeft + mDot - Scaled(2),
    mTop + Scaled(cCiDotTop) + mDot - Scaled(2)),
    TAtlasTrackerTestResultsText.LevelColor(mRow.CiLevel));
  Inc(mLeft, mDot + Scaled(cSmallGap));
  ACanvas.Font.Assign(FOwner.Font);
  ACanvas.Font.Size := FOwner.Font.Size - 1;
  ACanvas.Font.Color := Color(clGrayText);
  mText := TAtlasTrackerTestResultsText.CiText(mRow, ANowUtc);
  ACanvas.TextRect(Rect(mLeft, mTop + Scaled(1), Limit, mTop + Scaled(cCiLineHeight)), mLeft, mTop + Scaled(1), mText);
  PaintMismatch(ACanvas, mRow, mLeft + ACanvas.TextWidth(mText) + Scaled(10), mTop);
  ACanvas.Font.Assign(FOwner.Font);
end;

procedure TAtlasTrackerTestResultsPainter.PaintFailure(ACanvas: TCanvas; AIndex: Integer);
var
  mItem: TAtlasTestFailureItem;
  mTop, mLeft, mLimit: Integer;
begin
  mItem := FOwner.View.Failures[AIndex];
  mTop := FailureTop(AIndex);
  mLeft := Scaled(cIndent);
  mLimit := Limit;
  ACanvas.Brush.Style := bsSolid;
  if AIndex = FOwner.Failure then
  begin
    ACanvas.Brush.Color := Color(clBtnFace);
    ACanvas.FillRect(Rect(mLeft, mTop, mLimit, mTop + Scaled(cFailureHeight) - Scaled(cSmallGap)));
  end;
  // Roter Balken links (Mockup).
  ACanvas.Brush.Color := TAtlasTrackerTestResultsText.LevelColor(TAtlasTestLevel.Failed);
  ACanvas.FillRect(Rect(mLeft, mTop, mLeft + Scaled(cBarWidth), mTop + Scaled(cFailureHeight) - Scaled(cSmallGap)));
  ACanvas.Brush.Style := bsClear;
  Inc(mLeft, Scaled(cBarWidth) + Scaled(cGap));
  // Marke „Server“ rechts.
  if mItem.Server then
  begin
    ACanvas.Font.Assign(FOwner.Font);
    ACanvas.Font.Size := FOwner.Font.Size - 2;
    mLimit := PaintPill(ACanvas, mLimit - ACanvas.TextWidth(TAtlasTrackerTestResultsText.ServerTag) -
      2 * Scaled(cPillPadding), mTop + Scaled(2), TAtlasTrackerTestResultsText.ServerTag,
      TAtlasTrackerTestResultsText.LevelColor(TAtlasTestLevel.Unknown)).Left - Scaled(cDotGap);
  end;
  ACanvas.Font.Assign(FOwner.Font);
  ACanvas.Font.Name := cMonoFont;
  ACanvas.Font.Color := Color(clWindowText);
  ACanvas.TextRect(Rect(mLeft, mTop + Scaled(1), mLimit, mTop + Scaled(cTestHeight)), mLeft, mTop + Scaled(1),
    mItem.Test);
  ACanvas.Font.Assign(FOwner.Font);
  ACanvas.Font.Size := FOwner.Font.Size - 1;
  ACanvas.Font.Color := Color(clGrayText);
  ACanvas.TextRect(Rect(mLeft, mTop + Scaled(cTestHeight), Limit, mTop + Scaled(cDetailBottom)), mLeft,
    mTop + Scaled(cTestHeight),
    TAtlasTrackerTestResultsText.FailureDetail(mItem));
  ACanvas.Font.Assign(FOwner.Font);
end;

procedure TAtlasTrackerTestResultsPainter.PaintButton(ACanvas: TCanvas; AButton: TAtlasTestResultsButton;
  var ALeft: Integer);
var
  mText: string;
  mArea: TRect;
  mTop: Integer;
  mEnabled: Boolean;
begin
  mText := TAtlasTrackerTestResultsText.ButtonText(AButton);
  mTop := ButtonsTop + (Scaled(cButtonsHeight) - Scaled(cButtonHeight)) div 2;
  mArea := Rect(ALeft, mTop, ALeft + ACanvas.TextWidth(mText) + 2 * Scaled(cButtonPadding),
    mTop + Scaled(cButtonHeight));
  FButtonRects[AButton] := mArea;
  mEnabled := FOwner.ButtonEnabled(AButton);
  // „Fehlgeschlagene erneut ausführen“ ist die Hauptaktion (Mockup: primary).
  if (AButton = TAtlasTestResultsButton.Rerun) and mEnabled then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := Color(clHighlight);
    ACanvas.Pen.Color := Color(clHighlight);
    ACanvas.Font.Color := Color(clHighlightText);
  end
  else
  begin
    ACanvas.Brush.Style := bsClear;
    ACanvas.Pen.Color := Color(clBtnShadow);
    ACanvas.Font.Color := Color(clGrayText);
    if mEnabled then
    begin
      ACanvas.Font.Color := Color(clWindowText);
    end;
  end;
  ACanvas.RoundRect(mArea.Left, mArea.Top, mArea.Right, mArea.Bottom, Scaled(cCorner), Scaled(cCorner));
  ACanvas.Brush.Style := bsClear;
  ACanvas.TextOut(mArea.Left + (mArea.Width - ACanvas.TextWidth(mText)) div 2,
    mArea.Top + (mArea.Height - ACanvas.TextHeight(mText)) div 2, mText);
  ALeft := mArea.Right + Scaled(cGap);
end;

procedure TAtlasTrackerTestResultsPainter.PaintButtons(ACanvas: TCanvas);
var
  mButton: TAtlasTestResultsButton;
  mLeft: Integer;
begin
  mLeft := Scaled(cIndent);
  ACanvas.Font.Assign(FOwner.Font);
  for mButton := Low(TAtlasTestResultsButton) to High(TAtlasTestResultsButton) do
  begin
    FButtonRects[mButton] := TRect.Empty;
    if FOwner.ButtonVisible(mButton) then
    begin
      PaintButton(ACanvas, mButton, mLeft);
    end;
  end;
end;

procedure TAtlasTrackerTestResultsPainter.PaintEmpty(ACanvas: TCanvas);
begin
  ACanvas.Font.Color := Color(clGrayText);
  ACanvas.TextRect(Rect(Scaled(cIndent), Scaled(cSmallGap), Limit, Height), Scaled(cIndent), Scaled(cSmallGap),
    TAtlasTrackerTestResultsText.EmptyText);
end;

procedure TAtlasTrackerTestResultsPainter.PaintMore(ACanvas: TCanvas);
begin
  if FOwner.View.More > 0 then
  begin
    ACanvas.Font.Assign(FOwner.Font);
    ACanvas.Font.Color := Color(clGrayText);
    ACanvas.TextOut(Scaled(cIndent) + Scaled(cBarWidth) + Scaled(cGap), FailureTop(Length(FOwner.View.Failures)) +
      Scaled(1), TAtlasTrackerTestResultsText.MoreText(FOwner.View.More));
  end;
end;

procedure TAtlasTrackerTestResultsPainter.Paint(ACanvas: TCanvas);
var
  mIndex: Integer;
  mStamp: TDateTime;
begin
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Assign(FOwner.Font);
  if FOwner.View.Empty then
  begin
    PaintEmpty(ACanvas);
    Exit;
  end;
  mStamp := TAtlasTrackerTestResultsText.NowUtc;
  for mIndex := 0 to High(FOwner.View.Rows) do
  begin
    PaintLocalLine(ACanvas, mIndex, mStamp);
    PaintCiLine(ACanvas, mIndex, mStamp);
  end;
  for mIndex := 0 to High(FOwner.View.Failures) do
  begin
    PaintFailure(ACanvas, mIndex);
  end;
  PaintMore(ACanvas);
  PaintButtons(ACanvas);
end;

function TAtlasTrackerTestResultsPainter.ButtonHit(const APoint: TPoint): TAtlasTestResultsHit;
const
  cKinds: array[TAtlasTestResultsButton] of TAtlasTestResultsHitKind = (TAtlasTestResultsHitKind.Rerun,
    TAtlasTestResultsHitKind.Debug, TAtlasTestResultsHitKind.Browse);
var
  mButton: TAtlasTestResultsButton;
begin
  Result := TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.None, -1);
  for mButton := Low(TAtlasTestResultsButton) to High(TAtlasTestResultsButton) do
  begin
    if not FButtonRects[mButton].IsEmpty and FButtonRects[mButton].Contains(APoint) then
    begin
      Result := TAtlasTestResultsHit.Create(cKinds[mButton], -1);
    end;
  end;
end;

function TAtlasTrackerTestResultsPainter.HitTest(AX, AY: Integer): TAtlasTestResultsHit;
var
  mIndex: Integer;
begin
  Result := TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.None, -1);
  if FOwner.View.Empty then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FOwner.View.Rows) do
  begin
    if (AY >= RowTop(mIndex)) and (AY < RowTop(mIndex) + RowHeight(mIndex)) then
    begin
      Exit(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Row, mIndex));
    end;
  end;
  for mIndex := 0 to High(FOwner.View.Failures) do
  begin
    if (AY >= FailureTop(mIndex)) and (AY < FailureTop(mIndex + 1)) then
    begin
      Exit(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Failure, mIndex));
    end;
  end;
  if (FOwner.View.More > 0) and (AY >= FailureTop(Length(FOwner.View.Failures))) and (AY < ButtonsTop) then
  begin
    Exit(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.More, -1));
  end;
  Result := ButtonHit(Point(AX, AY));
end;

{ TAtlasTrackerTestResultsMenu }

constructor TAtlasTrackerTestResultsMenu.Create(AOwner: TAtlasTrackerTestResultsView);
begin
  inherited Create;
  FOwner := AOwner;
  FMenuRow := -1;
  FMenu := TPopupMenu.Create(AOwner);
  FMenu.OnPopup := MenuPopup;
  FQueryItem := AddItem(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsQueryNow), QueryClick);
  FCredentialsItem := AddItem(TAtlasStrings.Text(TAtlasTextId.CiLoginCommand), CredentialsClick);
  FOpenItem := AddItem(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.WelcomeTestsOpenProject), OpenClick);
end;

function TAtlasTrackerTestResultsMenu.AddItem(const ACaption: string; const AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  FMenu.Items.Add(Result);
end;

procedure TAtlasTrackerTestResultsMenu.MenuPopup(Sender: TObject);
var
  mPosition: TPoint;
  mHit: TAtlasTestResultsHit;
  mRow: TAtlasTestRow;
begin
  mPosition := FOwner.PaintBox.ScreenToClient(FMenu.PopupPoint);
  mHit := FOwner.HitTest(mPosition.X, mPosition.Y);
  FMenuRow := FOwner.View.Selected;
  if mHit.Kind = TAtlasTestResultsHitKind.Row then
  begin
    FMenuRow := mHit.Index;
  end;
  mRow := Default(TAtlasTestRow);
  if (FMenuRow >= 0) and (FMenuRow <= High(FOwner.View.Rows)) then
  begin
    mRow := FOwner.View.Rows[FMenuRow];
  end;
  FQueryItem.Visible := mRow.HasCi;
  FCredentialsItem.Visible := mRow.HasCi and (FOwner.Source <> nil) and FOwner.Source.CanEnterCredentials;
  FOpenItem.Enabled := FMenuRow >= 0;
end;

procedure TAtlasTrackerTestResultsMenu.SendMenuRow(const AAction: TAtlasTestResultsRowAction);
begin
  if (FMenuRow >= 0) and (FMenuRow <= High(FOwner.View.Rows)) then
  begin
    FOwner.SendRow(FOwner.View.Rows[FMenuRow], AAction);
  end;
end;

procedure TAtlasTrackerTestResultsMenu.QueryClick(Sender: TObject);
begin
  SendMenuRow(
    procedure(const ASource: IAtlasTestResultsSource; const ARow: TAtlasTestRow)
    begin
      ASource.QueryNow(ARow);
    end);
end;

procedure TAtlasTrackerTestResultsMenu.CredentialsClick(Sender: TObject);
begin
  SendMenuRow(
    procedure(const ASource: IAtlasTestResultsSource; const ARow: TAtlasTestRow)
    begin
      ASource.Credentials(ARow);
    end);
end;

procedure TAtlasTrackerTestResultsMenu.OpenClick(Sender: TObject);
begin
  SendMenuRow(
    procedure(const ASource: IAtlasTestResultsSource; const ARow: TAtlasTestRow)
    begin
      ASource.OpenProject(ARow);
    end);
end;

{ TAtlasTrackerTestResultsView }

constructor TAtlasTrackerTestResultsView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFailure := -1;
  FView := Default(TAtlasTestResultsView);
  FView.Selected := -1;
  FPainter := TAtlasTrackerTestResultsPainter.Create(Self);
  FBox := TAtlasStyledCanvas.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseDown := BoxMouseDown;
  FBox.OnMouseUp := BoxMouseUp;
  FBox.OnDblClick := BoxDblClick;
  FMenus := TAtlasTrackerTestResultsMenu.Create(Self);
  FBox.PopupMenu := FMenus.Menu;
end;

destructor TAtlasTrackerTestResultsView.Destroy;
begin
  // Steuerelemente und Menü gehören der Ansicht (Owner) und gehen mit inherited; die Helfer nur sich selbst.
  FreeAndNil(FMenus);
  FreeAndNil(FPainter);
  inherited;
end;

procedure TAtlasTrackerTestResultsView.SetSource(const AValue: IAtlasTestResultsSource);
begin
  FSource := AValue;
  UpdateContent;
  if FSource <> nil then
  begin
    FSource.Shown;
  end;
end;

procedure TAtlasTrackerTestResultsView.UpdateContent;
var
  mOldHeight: Integer;
  mOldProject: string;
  mRow: TAtlasTestRow;
begin
  if not HasWindow then
  begin
    Exit;
  end;
  mOldHeight := BodyHeight;
  mOldProject := '';
  if FView.SelectedRow(mRow) then
  begin
    mOldProject := mRow.Project;
  end;
  FView := Default(TAtlasTestResultsView);
  FView.Selected := -1;
  if FSource <> nil then
  begin
    FView := FSource.View;
  end;
  // Anderes Projekt gewählt oder Liste kürzer: Auswahl in der Liste aufheben.
  if not FView.SelectedRow(mRow) or not SameText(mRow.Project, mOldProject) or (FFailure > High(FView.Failures)) then
  begin
    FFailure := -1;
  end;
  FHintKey := '';
  FBox.Invalidate;
  inherited;
  if mOldHeight <> BodyHeight then
  begin
    HeightChanged;
  end;
end;

function TAtlasTrackerTestResultsView.BodyHeight: Integer;
begin
  Result := FPainter.Height;
end;

procedure TAtlasTrackerTestResultsView.BoxPaint(Sender: TObject);
begin
  FPainter.Paint(FBox.Canvas);
end;

function TAtlasTrackerTestResultsView.HitTest(AX, AY: Integer): TAtlasTestResultsHit;
begin
  Result := FPainter.HitTest(AX, AY);
end;

function TAtlasTrackerTestResultsView.SelectedFailure(out AItem: TAtlasTestFailureItem): Boolean;
var
  mIndex: Integer;
begin
  AItem := Default(TAtlasTestFailureItem);
  if (FFailure >= 0) and (FFailure <= High(FView.Failures)) then
  begin
    AItem := FView.Failures[FFailure];
    Exit(True);
  end;
  // Ohne Wahl: der erste Fehlschlag (zuerst lokale, sie haben Datei und Zeile).
  for mIndex := High(FView.Failures) downto 0 do
  begin
    if FView.Failures[mIndex].Local or ((mIndex = 0) and not AItem.Local) then
    begin
      AItem := FView.Failures[mIndex];
    end;
  end;
  Result := Length(FView.Failures) > 0;
end;

function TAtlasTrackerTestResultsView.ButtonVisible(AButton: TAtlasTestResultsButton): Boolean;
var
  mRow: TAtlasTestRow;
begin
  Result := FView.SelectedRow(mRow);
  if Result and (AButton = TAtlasTestResultsButton.Browse) then
  begin
    Result := mRow.HasCi;
  end;
end;

function TAtlasTrackerTestResultsView.ButtonEnabled(AButton: TAtlasTestResultsButton): Boolean;
var
  mRow: TAtlasTestRow;
  mItem: TAtlasTestFailureItem;
begin
  Result := (FSource <> nil) and ButtonVisible(AButton) and FView.SelectedRow(mRow);
  if Result then
  begin
    case AButton of
      TAtlasTestResultsButton.Rerun:
        begin
          Result := Length(FView.Rerun) > 0;
        end;
      TAtlasTestResultsButton.Debug:
        begin
          Result := SelectedFailure(mItem);
        end;
    else
      Result := mRow.Ci.HasBuild;
    end;
  end;
end;

class procedure TAtlasTrackerTestResultsView.Post(const AAction: TThreadProcedure);
begin
  // Die Quelle füllt die Kachel danach neu: nicht im eigenen Maus- bzw. Menüereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Tracker, AAction);
end;

procedure TAtlasTrackerTestResultsView.SendRow(const ARow: TAtlasTestRow; const AAction: TAtlasTestResultsRowAction);
var
  mSource: IAtlasTestResultsSource;
  mRow: TAtlasTestRow;
  mAction: TAtlasTestResultsRowAction;
begin
  mSource := FSource;
  mRow := ARow;
  mAction := AAction;
  if mSource <> nil then
  begin
    Post(
      procedure
      begin
        mAction(mSource, mRow);
      end);
  end;
end;

procedure TAtlasTrackerTestResultsView.ClickRow(AIndex: Integer);
var
  mProject: string;
  mSource: IAtlasTestResultsSource;
begin
  if (AIndex < 0) or (AIndex > High(FView.Rows)) or (AIndex = FView.Selected) then
  begin
    Exit;
  end;
  mProject := FView.Rows[AIndex].Project;
  mSource := FSource;
  FFailure := -1;
  Post(
    procedure
    begin
      mSource.Select(mProject);
    end);
end;

procedure TAtlasTrackerTestResultsView.ClickButton(AKind: TAtlasTestResultsHitKind; const ARow: TAtlasTestRow);
var
  mItem: TAtlasTestFailureItem;
  mTests: TArray<string>;
begin
  mTests := FView.Rerun;
  if (AKind = TAtlasTestResultsHitKind.Rerun) and ButtonEnabled(TAtlasTestResultsButton.Rerun) then
  begin
    SendRow(ARow,
      procedure(const ASource: IAtlasTestResultsSource; const ARow: TAtlasTestRow)
      begin
        ASource.RerunFailed(ARow, mTests);
      end);
  end
  else if (AKind = TAtlasTestResultsHitKind.Debug) and ButtonEnabled(TAtlasTestResultsButton.Debug) and
    SelectedFailure(mItem) then
  begin
    SendRow(ARow,
      procedure(const ASource: IAtlasTestResultsSource; const ARow: TAtlasTestRow)
      begin
        ASource.Debug(ARow, mItem);
      end);
  end
  else if (AKind = TAtlasTestResultsHitKind.Browse) and ButtonEnabled(TAtlasTestResultsButton.Browse) then
  begin
    SendRow(ARow,
      procedure(const ASource: IAtlasTestResultsSource; const ARow: TAtlasTestRow)
      begin
        ASource.Browse(ARow);
      end);
  end;
end;

procedure TAtlasTrackerTestResultsView.ClickAt(const AHit: TAtlasTestResultsHit);
var
  mRow: TAtlasTestRow;
begin
  if (FSource = nil) or not FView.SelectedRow(mRow) then
  begin
    Exit;
  end;
  case AHit.Kind of
    TAtlasTestResultsHitKind.Row:
      begin
        ClickRow(AHit.Index);
      end;
    TAtlasTestResultsHitKind.Failure:
      begin
        if (AHit.Index >= 0) and (AHit.Index <= High(FView.Failures)) then
        begin
          FFailure := AHit.Index;
          FBox.Invalidate;
        end;
      end;
    TAtlasTestResultsHitKind.Rerun, TAtlasTestResultsHitKind.Debug, TAtlasTestResultsHitKind.Browse:
      begin
        ClickButton(AHit.Kind, mRow);
      end;
    TAtlasTestResultsHitKind.None, TAtlasTestResultsHitKind.More:
      begin
        // Leerraum und die Zeile „… weitere“ sind keine Schaltflächen.
      end;
  end;
end;

procedure TAtlasTrackerTestResultsView.DoubleClickAt(const AHit: TAtlasTestResultsHit);
var
  mRow: TAtlasTestRow;
  mItem: TAtlasTestFailureItem;
begin
  if (FSource = nil) or not FView.SelectedRow(mRow) then
  begin
    Exit;
  end;
  if (AHit.Kind = TAtlasTestResultsHitKind.Failure) and (AHit.Index >= 0) and (AHit.Index <= High(FView.Failures)) then
  begin
    FFailure := AHit.Index;
    mItem := FView.Failures[AHit.Index];
    SendRow(mRow,
      procedure(const ASource: IAtlasTestResultsSource; const ARow: TAtlasTestRow)
      begin
        ASource.OpenTest(ARow, mItem);
      end);
  end
  else if (AHit.Kind = TAtlasTestResultsHitKind.Row) and (AHit.Index >= 0) and (AHit.Index <= High(FView.Rows)) then
  begin
    SendRow(FView.Rows[AHit.Index],
      procedure(const ASource: IAtlasTestResultsSource; const ARow: TAtlasTestRow)
      begin
        ASource.OpenProject(ARow);
      end);
  end;
end;

function TAtlasTrackerTestResultsView.HintOf(const AHit: TAtlasTestResultsHit): string;
begin
  case AHit.Kind of
    TAtlasTestResultsHitKind.Row:
      begin
        Result := TAtlasTrackerTestResultsText.RowHint(FView.Rows[AHit.Index]);
      end;
    TAtlasTestResultsHitKind.Failure:
      begin
        Result := TAtlasTrackerTestResultsText.FailureHint(FView.Failures[AHit.Index]);
      end;
  else
    Result := '';
  end;
end;

procedure TAtlasTrackerTestResultsView.BoxMouseMove(Sender: TObject; Shift: TShiftState; AX, AY: Integer);
var
  mHit: TAtlasTestResultsHit;
  mKey: string;
begin
  mHit := HitTest(AX, AY);
  FBox.Cursor := crDefault;
  if mHit.Kind in [TAtlasTestResultsHitKind.Rerun, TAtlasTestResultsHitKind.Debug, TAtlasTestResultsHitKind.Browse,
    TAtlasTestResultsHitKind.Row, TAtlasTestResultsHitKind.Failure] then
  begin
    FBox.Cursor := crHandPoint;
  end;
  mKey := IntToStr(Ord(mHit.Kind)) + ':' + IntToStr(mHit.Index);
  if mKey <> FHintKey then
  begin
    FHintKey := mKey;
    FBox.Hint := HintOf(mHit);
    Application.CancelHint;
  end;
end;

procedure TAtlasTrackerTestResultsView.BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; AX,
  AY: Integer);
begin
  FLastMouse := Point(AX, AY);
  FDoubleDown := ssDouble in Shift;
end;

procedure TAtlasTrackerTestResultsView.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; AX,
  AY: Integer);
begin
  // Der zweite Klick eines Doppelklicks löst nichts noch einmal aus: BoxDblClick öffnet.
  if (Button = mbLeft) and not FDoubleDown then
  begin
    ClickAt(HitTest(AX, AY));
  end;
  FDoubleDown := False;
end;

procedure TAtlasTrackerTestResultsView.BoxDblClick(Sender: TObject);
begin
  DoubleClickAt(HitTest(FLastMouse.X, FLastMouse.Y));
end;

end.
