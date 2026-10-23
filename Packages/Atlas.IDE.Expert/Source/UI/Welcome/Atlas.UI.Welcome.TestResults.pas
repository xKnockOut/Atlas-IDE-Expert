unit Atlas.UI.Welcome.TestResults;

// Bereich „Testergebnisse“ der Willkommensseite (#763, Mockup #ws11), ohne
// Open Tools API. Selbst gezeichnet:
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
// Daten und Aktionen kommen über IAtlasTestResultsSource aus der IDE-Schicht;
// Aktionen gehen über die Nachrichtenschleife, weil die Quelle den Bereich
// daraufhin neu füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Vcl.Graphics,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Welcome.TestResults,
  Atlas.UI.Welcome.Frame;

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
    /// <summary>Der Bereich wird gezeigt: bei Bedarf den Server im Hintergrund fragen.</summary>
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

  TAtlasWelcomeTestResultsFrame = class(TAtlasWelcomeSectionFrame)
  public const
    Indent = 8;
    DotSize = 10;
    LineHeight = 22;
    CiLineHeight = 20;
    RowGap = 4;
    ListGap = 6;
    FailureHeight = 38;
    MoreHeight = 20;
    ButtonsHeight = 30;
    ButtonHeight = 24;
    ButtonPadding = 10;
    PillHeight = 18;
    PillPadding = 6;
    BarWidth = 3;
    MonoFont = 'Consolas';
  private
    FSource: IAtlasTestResultsSource;
    FBox: TAtlasWelcomeCanvas;
    FView: TAtlasTestResultsView;
    FFailure: Integer;
    FButtonRects: array[TAtlasTestResultsButton] of TRect;
    FMenu: TPopupMenu;
    FQueryItem: TMenuItem;
    FCredentialsItem: TMenuItem;
    FOpenItem: TMenuItem;
    FMenuRow: Integer;
    FHintKey: string;
    FLastMouse: TPoint;
    FDoubleDown: Boolean;
    procedure SetSource(const AValue: IAtlasTestResultsSource);
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BoxDblClick(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure QueryClick(Sender: TObject);
    procedure CredentialsClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    function MenuTarget(out ARow: TAtlasTestRow): Boolean;
    function RowTop(AIndex: Integer): Integer;
    function RowHeight(AIndex: Integer): Integer;
    function ListTop: Integer;
    function FailureTop(AIndex: Integer): Integer;
    function ButtonsTop: Integer;
    function SelectedFailure(out AItem: TAtlasTestFailureItem): Boolean;
    procedure PaintRow(ACanvas: TCanvas; AIndex: Integer; ANowUtc: TDateTime);
    procedure PaintFailure(ACanvas: TCanvas; AIndex: Integer);
    procedure PaintButtons(ACanvas: TCanvas);
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    function HitTest(X, Y: Integer): TAtlasTestResultsHit;
    /// <summary>Klick wie mit der Maus (auch für Tests): Zeile wählen, Fehlschlag wählen, Schaltfläche.</summary>
    procedure ClickAt(const AHit: TAtlasTestResultsHit);
    /// <summary>Doppelklick: auf einem Fehlschlag den Test öffnen.</summary>
    procedure DoubleClickAt(const AHit: TAtlasTestResultsHit);
    /// <summary>Schaltfläche nutzbar: Rerun mit Namen, Debug mit lokalem Fehlschlag, Browse mit Build.</summary>
    function ButtonEnabled(AButton: TAtlasTestResultsButton): Boolean;
    function ButtonVisible(AButton: TAtlasTestResultsButton): Boolean;
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
    class function EmptyText: string; static;
    class function ButtonText(AButton: TAtlasTestResultsButton): string; static;
    class function LevelColor(ALevel: TAtlasTestLevel): TColor; static;
    class function RowHint(const ARow: TAtlasTestRow): string; static;
    property Source: IAtlasTestResultsSource read FSource write SetSource;
    property View: TAtlasTestResultsView read FView;
    /// <summary>Gewählter Fehlschlag in der Liste; -1 = keiner (Im Debugger nimmt dann den ersten lokalen).
    /// </summary>
    property Failure: Integer read FFailure write FFailure;
    property PaintBox: TAtlasWelcomeCanvas read FBox;
    property Menu: TPopupMenu read FMenu;
    property QueryItem: TMenuItem read FQueryItem;
    property CredentialsItem: TMenuItem read FCredentialsItem;
    property OpenItem: TMenuItem read FOpenItem;
    property MenuRow: Integer read FMenuRow write FMenuRow;
  end;

  /// <summary>Abfrage von Benutzer und API-Token für „Zugang zum Build-Server hinterlegen …“ (#763); das Token
  /// wird verdeckt eingegeben.</summary>
  TAtlasCiLoginPrompt = class
  public
    /// <summary>AUser vorbelegt; das Token nie (es steht nur im Anmeldespeicher). False bei Abbruch. Beide leer =
    /// Zugang entfernen.</summary>
    class function Ask(const AServer: string; var AUser, AToken: string): Boolean; static;
    /// <summary>Nur ein Token, verdeckt, mit eigenem Titel und eigener Beschriftung (Issue-Tracker, #765). False bei
    /// Abbruch; leer = Zugang entfernen.</summary>
    class function AskToken(const ATitle, ALabel: string; var AToken: string): Boolean; static;
  end;

implementation

uses
  System.UITypes,
  System.Math,
  System.DateUtils,
  Vcl.Themes,
  Vcl.Dialogs,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Projects.Summary,
  Atlas.UI.Strings;

const
  Separator = ' · ';

{ TAtlasTestResultsHit }

class function TAtlasTestResultsHit.Create(AKind: TAtlasTestResultsHitKind; AIndex: Integer): TAtlasTestResultsHit;
begin
  Result.Kind := AKind;
  Result.Index := AIndex;
end;

{ TAtlasWelcomeTestResultsFrame }

constructor TAtlasWelcomeTestResultsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFailure := -1;
  FMenuRow := -1;
  FBox := TAtlasWelcomeCanvas.Create(Self);
  FBox.Parent := Body;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseDown := BoxMouseDown;
  FBox.OnMouseUp := BoxMouseUp;
  FBox.OnDblClick := BoxDblClick;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FQueryItem := TMenuItem.Create(Self);
  FQueryItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsQueryNow);
  FQueryItem.OnClick := QueryClick;
  FMenu.Items.Add(FQueryItem);
  FCredentialsItem := TMenuItem.Create(Self);
  FCredentialsItem.Caption := TAtlasStrings.Text(TAtlasTextId.CiLoginCommand);
  FCredentialsItem.OnClick := CredentialsClick;
  FMenu.Items.Add(FCredentialsItem);
  FOpenItem := TMenuItem.Create(Self);
  FOpenItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsOpenProject);
  FOpenItem.OnClick := OpenClick;
  FMenu.Items.Add(FOpenItem);
  FBox.PopupMenu := FMenu;
end;

procedure TAtlasWelcomeTestResultsFrame.SetSource(const AValue: IAtlasTestResultsSource);
begin
  FSource := AValue;
  UpdateContent;
  if FSource <> nil then
    FSource.Shown;
end;

procedure TAtlasWelcomeTestResultsFrame.UpdateContent;
var
  OldHeight: Integer;
  OldProject: string;
  Row: TAtlasTestRow;
begin
  OldHeight := BodyHeight;
  OldProject := '';
  if FView.SelectedRow(Row) then
    OldProject := Row.Project;
  FView := Default(TAtlasTestResultsView);
  FView.Selected := -1;
  if FSource <> nil then
    FView := FSource.View;
  // Anderes Projekt gewählt oder Liste kürzer: Auswahl in der Liste aufheben.
  if not FView.SelectedRow(Row) or not SameText(Row.Project, OldProject) or (FFailure > High(FView.Failures)) then
    FFailure := -1;
  FHintKey := '';
  FBox.Invalidate;
  inherited;
  if OldHeight <> BodyHeight then
    HeightChanged;
end;

function TAtlasWelcomeTestResultsFrame.RowHeight(AIndex: Integer): Integer;
begin
  Result := ScaleValue(LineHeight) + ScaleValue(RowGap);
  if (AIndex >= 0) and (AIndex <= High(FView.Rows)) and FView.Rows[AIndex].HasCi then
    Inc(Result, ScaleValue(CiLineHeight));
end;

function TAtlasWelcomeTestResultsFrame.RowTop(AIndex: Integer): Integer;
var
  Index: Integer;
begin
  Result := ScaleValue(Indent) div 2;
  for Index := 0 to AIndex - 1 do
    Inc(Result, RowHeight(Index));
end;

function TAtlasWelcomeTestResultsFrame.ListTop: Integer;
begin
  Result := RowTop(Length(FView.Rows)) + ScaleValue(ListGap);
end;

function TAtlasWelcomeTestResultsFrame.FailureTop(AIndex: Integer): Integer;
begin
  Result := ListTop + AIndex * ScaleValue(FailureHeight);
end;

function TAtlasWelcomeTestResultsFrame.ButtonsTop: Integer;
begin
  Result := FailureTop(Length(FView.Failures));
  if FView.More > 0 then
    Inc(Result, ScaleValue(MoreHeight));
end;

function TAtlasWelcomeTestResultsFrame.BodyHeight: Integer;
begin
  if FView.Empty then
    Exit(ScaleValue(LineHeight) * 2 + ScaleValue(Indent));
  Result := ButtonsTop + ScaleValue(ButtonsHeight) + ScaleValue(Indent) div 2;
end;

class function TAtlasWelcomeTestResultsFrame.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasWelcomeTestResultsFrame.PillText(const ARow: TAtlasTestRow): string;
begin
  case ARow.LocalLevel of
    TAtlasTestLevel.Failed:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsFailed,
        [Max(ARow.Local.Failed + ARow.Local.Errors, Integer(Length(ARow.Local.Failures)))]);
    TAtlasTestLevel.Passed:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsAllPassed, [ARow.Local.Passed]);
    TAtlasTestLevel.Warning:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsNonePassed);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsNoLocalRun);
  end;
end;

class function TAtlasWelcomeTestResultsFrame.DurationText(AMs: Int64): string;
var
  Seconds: Int64;
begin
  if AMs < 60000 then
    Result := FormatFloat('0.0', AMs / 1000, FormatSettings) + ' s'
  else
  begin
    Seconds := AMs div 1000;
    Result := Format('%d:%.2d min', [Seconds div 60, Seconds mod 60]);
  end;
end;

class function TAtlasWelcomeTestResultsFrame.WhenText(AUtc, ANowUtc: TDateTime): string;
var
  AtLocal, NowLocal: TDateTime;
begin
  Result := '';
  if AUtc <= 0 then
    Exit;
  AtLocal := TTimeZone.Local.ToLocalTime(AUtc);
  NowLocal := TTimeZone.Local.ToLocalTime(ANowUtc);
  if Trunc(AtLocal) = Trunc(NowLocal) then
    Result := FormatDateTime('t', AtLocal)
  else if Trunc(AtLocal) = Trunc(NowLocal) - 1 then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsYesterday)
  else
    Result := FormatDateTime('ddddd', AtLocal);
end;

class function TAtlasWelcomeTestResultsFrame.AgoText(AUtc, ANowUtc: TDateTime): string;
var
  Minutes, Days: Int64;
  AtLocal, NowLocal: TDateTime;
begin
  Result := '';
  if AUtc <= 0 then
    Exit;
  Minutes := Max(Int64(0), Trunc((ANowUtc - AUtc) * MinsPerDay));
  AtLocal := TTimeZone.Local.ToLocalTime(AUtc);
  NowLocal := TTimeZone.Local.ToLocalTime(ANowUtc);
  Days := Trunc(NowLocal) - Trunc(AtLocal);
  if Minutes < 1 then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsJustNow)
  else if Minutes < 60 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsMinutesAgo, [Minutes])
  else if Days <= 0 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsHoursAgo, [Minutes div 60])
  else if Days = 1 then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsYesterday)
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsDaysAgo, [Days]);
end;

class function TAtlasWelcomeTestResultsFrame.LocalText(const ARow: TAtlasTestRow; ANowUtc: TDateTime): string;
var
  Parts: TArray<string>;
begin
  Result := '';
  if not ARow.Local.Known then
    Exit;
  Parts := nil;
  // Die Marke nennt bei „alle ok“ schon die Zahl.
  if ARow.LocalLevel <> TAtlasTestLevel.Passed then
    Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsPassed, [ARow.Local.Passed])];
  if ARow.Local.Skipped > 0 then
    Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsSkipped, [ARow.Local.Skipped])];
  if ARow.Local.DurationMs > 0 then
    Parts := Parts + [DurationText(ARow.Local.DurationMs)];
  if ARow.Local.At > 0 then
    Parts := Parts + [WhenText(ARow.Local.At, ANowUtc)];
  Result := string.Join(Separator, Parts);
end;

class function TAtlasWelcomeTestResultsFrame.BuildText(const ABuild: TAtlasCiBuild): string;
begin
  if ABuild.TestsKnown and ((ABuild.Failed > 0) or (Length(ABuild.Failures) > 0)) then
    Exit(TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsFailed,
      [Max(ABuild.Failed, Integer(Length(ABuild.Failures)))]));
  case ABuild.Outcome of
    TAtlasCiOutcome.Success:
      if ABuild.TestsKnown and (ABuild.Passed > 0) then
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsAllPassed, [ABuild.Passed])
      else
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsBuildSuccess);
    TAtlasCiOutcome.Failure:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsBuildFailure);
    TAtlasCiOutcome.Unstable:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsBuildUnstable);
    TAtlasCiOutcome.Aborted:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsBuildAborted);
    TAtlasCiOutcome.NotBuilt:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsBuildNotBuilt);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsBuildUnknown);
  end;
end;

class function TAtlasWelcomeTestResultsFrame.ErrorText(AError: TAtlasCiFetchError): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiUnauthorized);
    TAtlasCiFetchError.NotFound:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiNotFound);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiTimeout);
    TAtlasCiFetchError.Server, TAtlasCiFetchError.Invalid:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiServerError);
    TAtlasCiFetchError.UnknownProvider:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiUnknownProvider);
    TAtlasCiFetchError.None:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiNotQueried);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiUnreachable);
  end;
end;

class function TAtlasWelcomeTestResultsFrame.CiText(const ARow: TAtlasTestRow; ANowUtc: TDateTime): string;
var
  Parts: TArray<string>;
  Finished: TDateTime;
  Head: string;
begin
  Result := '';
  if not ARow.HasCi then
    Exit;
  Head := TAtlasWelcomeTestResults.ProviderCaption(ARow.Job.Provider);
  Parts := nil;
  if ARow.Ci.HasBuild then
  begin
    Parts := Parts + [Head + ' #' + IntToStr(ARow.Ci.Build.Number), BuildText(ARow.Ci.Build)];
    Finished := ARow.Ci.Build.StartedUtc;
    if (Finished > 0) and (ARow.Ci.Build.DurationMs > 0) then
      Finished := Finished + ARow.Ci.Build.DurationMs / MSecsPerDay;
    if Finished <= 0 then
      Finished := ARow.Ci.At;
    if Finished > 0 then
      Parts := Parts + [AgoText(Finished, ANowUtc)];
  end
  else
  begin
    Parts := Parts + [Head];
    if ARow.CiQuerying then
      Parts := Parts + [TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiQuerying)]
    else
      Parts := Parts + [ErrorText(ARow.Ci.Error)];
  end;
  // Branch des Multibranch-Jobs, sonst der Job.
  if ARow.Job.JobBranch <> '' then
    Parts := Parts + [ARow.Job.JobBranch]
  else
    Parts := Parts + [ARow.Job.Job];
  if ARow.CiStale and (ARow.Ci.At > 0) then
    Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsStale,
      [FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(ARow.Ci.At))])]
  else if ARow.CiQuerying and ARow.Ci.HasBuild then
    Parts := Parts + [TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiQuerying)];
  Result := string.Join(Separator, Parts);
end;

class function TAtlasWelcomeTestResultsFrame.MismatchText(AMismatch: TAtlasTestMismatch): string;
begin
  case AMismatch of
    TAtlasTestMismatch.LocalGreenServerRed:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsLocalGreenServerRed);
    TAtlasTestMismatch.LocalRedServerGreen:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsLocalRedServerGreen);
  else
    Result := '';
  end;
end;

/// <summary>Dateiname ohne Pfad; auch mit „/“.</summary>
function FileNameOnly(const APath: string): string;
var
  Index: Integer;
begin
  Result := APath;
  for Index := Length(Result) downto 1 do
    if CharInSet(Result[Index], ['\', '/']) then
      Exit(Copy(Result, Index + 1, MaxInt));
end;

class function TAtlasWelcomeTestResultsFrame.FailureDetail(const AItem: TAtlasTestFailureItem): string;
var
  Place: string;
begin
  Place := '';
  if AItem.FileName <> '' then
  begin
    Place := FileNameOnly(AItem.FileName);
    if AItem.Line > 0 then
      Place := Place + ':' + IntToStr(AItem.Line);
  end;
  Result := AItem.Message;
  if (Result <> '') and (Place <> '') then
    Result := Result + Separator + Place
  else if Place <> '' then
    Result := Place;
end;

class function TAtlasWelcomeTestResultsFrame.EmptyText: string;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsEmpty);
end;

class function TAtlasWelcomeTestResultsFrame.ButtonText(AButton: TAtlasTestResultsButton): string;
begin
  case AButton of
    TAtlasTestResultsButton.Rerun:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsRerun);
    TAtlasTestResultsButton.Debug:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsDebug);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsBrowse);
  end;
end;

class function TAtlasWelcomeTestResultsFrame.LevelColor(ALevel: TAtlasTestLevel): TColor;
begin
  // Dieselben Töne wie die Marken im Bereich „Projekte“: lesbar im hellen und im dunklen Thema.
  case ALevel of
    TAtlasTestLevel.Passed:
      Result := TColor($0043A02E);
    TAtlasTestLevel.Warning:
      Result := TColor($001A8CC9);
    TAtlasTestLevel.Failed:
      Result := TColor($002E22CF);
  else
    Result := TColor($00817666);
  end;
end;

class function TAtlasWelcomeTestResultsFrame.RowHint(const ARow: TAtlasTestRow): string;
var
  Lines: TStringList;
  Run: string;
begin
  Lines := TStringList.Create;
  try
    if ARow.TestProject <> '' then
      Lines.Add(ARow.TestProject)
    else
      Lines.Add(ARow.Project);
    if ARow.Local.Known then
    begin
      Run := string.Join(' ', [ARow.Local.Configuration, ARow.Local.Platform]).Trim;
      if Run <> '' then
        Run := '(' + Run + ')';
      Lines.Add(Trim(TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsHintLocal, [ARow.Local.Passed,
        ARow.Local.Failed + ARow.Local.Errors, ARow.Local.Skipped, Run])));
    end;
    if ARow.HasCi then
    begin
      Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsHintJob,
        [TAtlasWelcomeTestResults.ProviderCaption(ARow.Job.Provider), ARow.Job.Job]));
      if ARow.Ci.Error <> TAtlasCiFetchError.None then
        Lines.Add(ErrorText(ARow.Ci.Error));
      if ARow.Ci.Attempt > 0 then
        Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsHintAttempt,
          [FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(ARow.Ci.Attempt))]));
    end;
    Lines.Add(TAtlasStrings.Text(TAtlasTextId.WelcomeTestsHintClick));
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

function TAtlasWelcomeTestResultsFrame.SelectedFailure(out AItem: TAtlasTestFailureItem): Boolean;
var
  Index: Integer;
begin
  AItem := Default(TAtlasTestFailureItem);
  if (FFailure >= 0) and (FFailure <= High(FView.Failures)) then
  begin
    AItem := FView.Failures[FFailure];
    Exit(True);
  end;
  // Ohne Wahl: der erste Fehlschlag (zuerst lokale, sie haben Datei und Zeile).
  for Index := 0 to High(FView.Failures) do
    if FView.Failures[Index].Local then
    begin
      AItem := FView.Failures[Index];
      Exit(True);
    end;
  Result := Length(FView.Failures) > 0;
  if Result then
    AItem := FView.Failures[0];
end;

function TAtlasWelcomeTestResultsFrame.ButtonVisible(AButton: TAtlasTestResultsButton): Boolean;
var
  Row: TAtlasTestRow;
begin
  Result := FView.SelectedRow(Row);
  if Result and (AButton = TAtlasTestResultsButton.Browse) then
    Result := Row.HasCi;
end;

function TAtlasWelcomeTestResultsFrame.ButtonEnabled(AButton: TAtlasTestResultsButton): Boolean;
var
  Row: TAtlasTestRow;
  Item: TAtlasTestFailureItem;
begin
  Result := (FSource <> nil) and ButtonVisible(AButton) and FView.SelectedRow(Row);
  if not Result then
    Exit;
  case AButton of
    TAtlasTestResultsButton.Rerun:
      Result := Length(FView.Rerun) > 0;
    TAtlasTestResultsButton.Debug:
      Result := SelectedFailure(Item);
  else
    Result := Row.Ci.HasBuild;
  end;
end;

procedure TAtlasWelcomeTestResultsFrame.PaintRow(ACanvas: TCanvas; AIndex: Integer; ANowUtc: TDateTime);
var
  Data: TAtlasTestRow;
  mTop, mLeft, Dot, Limit, mWidth, Radius: Integer;
  mText, Mismatch: string;
  TextColor, MutedColor: TColor;
  Pill: TRect;
begin
  Data := FView.Rows[AIndex];
  TextColor := StyleServices(Self).GetSystemColor(clWindowText);
  MutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  mTop := RowTop(AIndex);
  mLeft := ScaleValue(Indent);
  Dot := ScaleValue(DotSize);
  Limit := FBox.Width - ScaleValue(Indent);
  // Gewählte Zeile mit einem Balken in der Markierungsfarbe des Themas (wie „Projekte“, #758).
  if (AIndex = FView.Selected) and (Length(FView.Rows) > 1) then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := StyleServices(Self).GetSystemColor(clHighlight);
    ACanvas.FillRect(Rect(0, mTop, ScaleValue(BarWidth), mTop + RowHeight(AIndex) - ScaleValue(RowGap)));
  end;
  // Ampel des lokalen Laufs (ohne lokalen Lauf die des Servers).
  ACanvas.Brush.Style := bsSolid;
  if Data.Local.Known then
    ACanvas.Brush.Color := LevelColor(Data.LocalLevel)
  else
    ACanvas.Brush.Color := LevelColor(Data.CiLevel);
  ACanvas.Pen.Color := ACanvas.Brush.Color;
  ACanvas.Ellipse(mLeft, mTop + ScaleValue(6), mLeft + Dot, mTop + ScaleValue(6) + Dot);
  ACanvas.Brush.Style := bsClear;
  Inc(mLeft, Dot + ScaleValue(6));
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Color := TextColor;
  ACanvas.Font.Style := [fsBold];
  ACanvas.TextRect(Rect(mLeft, mTop + ScaleValue(2), Limit, mTop + ScaleValue(LineHeight)), mLeft, mTop + ScaleValue(2),
    Data.Name);
  Inc(mLeft, ACanvas.TextWidth(Data.Name) + ScaleValue(8));
  ACanvas.Font.Style := [];
  // Marke des lokalen Laufs.
  if Data.Local.Known and (mLeft < Limit) then
  begin
    ACanvas.Font.Size := Font.Size - 1;
    mText := PillText(Data);
    mWidth := ACanvas.TextWidth(mText) + 2 * ScaleValue(PillPadding);
    Pill := Rect(mLeft, mTop + ScaleValue(2), mLeft + mWidth, mTop + ScaleValue(2) + ScaleValue(PillHeight));
    Radius := ScaleValue(PillHeight);
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := LevelColor(Data.LocalLevel);
    ACanvas.Pen.Color := ACanvas.Brush.Color;
    ACanvas.RoundRect(Pill.Left, Pill.Top, Pill.Right, Pill.Bottom, Radius, Radius);
    ACanvas.Brush.Style := bsClear;
    ACanvas.Font.Color := clWhite;
    ACanvas.TextOut(Pill.Left + ScaleValue(PillPadding), Pill.Top + (Pill.Height - ACanvas.TextHeight(mText)) div 2,
      mText);
    ACanvas.Font.Size := Font.Size;
    mLeft := Pill.Right + ScaleValue(8);
  end;
  // Zahlen, Dauer und Zeit in gedämpfter Schrift (Mockup: mono).
  mText := LocalText(Data, ANowUtc);
  if (mText <> '') and (mLeft < Limit) then
  begin
    ACanvas.Font.Name := MonoFont;
    ACanvas.Font.Size := Font.Size - 1;
    ACanvas.Font.Color := MutedColor;
    ACanvas.TextRect(Rect(mLeft, mTop + ScaleValue(3), Limit, mTop + ScaleValue(LineHeight)), mLeft,
      mTop + ScaleValue(3), mText);
    ACanvas.Font.Assign(Font);
  end;
  if not Data.HasCi then
    Exit;
  // Zeile des Build-Servers: kleiner Punkt, Text, Abweichung hervorgehoben.
  mTop := mTop + ScaleValue(LineHeight);
  mLeft := ScaleValue(Indent) + Dot + ScaleValue(6);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := LevelColor(Data.CiLevel);
  ACanvas.Pen.Color := ACanvas.Brush.Color;
  ACanvas.Ellipse(mLeft, mTop + ScaleValue(5), mLeft + Dot - ScaleValue(2), mTop + ScaleValue(5) + Dot - ScaleValue(2));
  ACanvas.Brush.Style := bsClear;
  Inc(mLeft, Dot + ScaleValue(4));
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Size := Font.Size - 1;
  ACanvas.Font.Color := MutedColor;
  mText := CiText(Data, ANowUtc);
  ACanvas.TextRect(Rect(mLeft, mTop + ScaleValue(1), Limit, mTop + ScaleValue(CiLineHeight)), mLeft,
    mTop + ScaleValue(1), mText);
  Mismatch := MismatchText(Data.Mismatch);
  if Mismatch <> '' then
  begin
    Inc(mLeft, ACanvas.TextWidth(mText) + ScaleValue(10));
    if mLeft < Limit then
    begin
      ACanvas.Font.Style := [fsBold];
      if Data.Mismatch = TAtlasTestMismatch.LocalGreenServerRed then
        ACanvas.Font.Color := LevelColor(TAtlasTestLevel.Failed)
      else
        ACanvas.Font.Color := LevelColor(TAtlasTestLevel.Warning);
      ACanvas.TextRect(Rect(mLeft, mTop + ScaleValue(1), Limit, mTop + ScaleValue(CiLineHeight)), mLeft,
        mTop + ScaleValue(1), Mismatch);
    end;
  end;
  ACanvas.Font.Assign(Font);
end;

procedure TAtlasWelcomeTestResultsFrame.PaintFailure(ACanvas: TCanvas; AIndex: Integer);
var
  Item: TAtlasTestFailureItem;
  mTop, mLeft, Limit, mWidth, Radius: Integer;
  mTag: TRect;
  mText: string;
  TextColor, MutedColor: TColor;
begin
  Item := FView.Failures[AIndex];
  TextColor := StyleServices(Self).GetSystemColor(clWindowText);
  MutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  mTop := FailureTop(AIndex);
  mLeft := ScaleValue(Indent);
  Limit := FBox.Width - ScaleValue(Indent);
  if AIndex = FFailure then
  begin
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := StyleServices(Self).GetSystemColor(clBtnFace);
    ACanvas.FillRect(Rect(mLeft, mTop, Limit, mTop + ScaleValue(FailureHeight) - ScaleValue(4)));
  end;
  // Roter Balken links (Mockup).
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := LevelColor(TAtlasTestLevel.Failed);
  ACanvas.FillRect(Rect(mLeft, mTop, mLeft + ScaleValue(BarWidth), mTop + ScaleValue(FailureHeight) - ScaleValue(4)));
  ACanvas.Brush.Style := bsClear;
  Inc(mLeft, ScaleValue(BarWidth) + ScaleValue(8));
  // Marke „Server“ rechts.
  if Item.Server then
  begin
    ACanvas.Font.Assign(Font);
    ACanvas.Font.Size := Font.Size - 2;
    mText := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsServerTag);
    mWidth := ACanvas.TextWidth(mText) + 2 * ScaleValue(PillPadding);
    mTag := Rect(Limit - mWidth, mTop + ScaleValue(2), Limit, mTop + ScaleValue(2) + ScaleValue(PillHeight) - 2);
    Radius := ScaleValue(PillHeight);
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := LevelColor(TAtlasTestLevel.Unknown);
    ACanvas.Pen.Color := ACanvas.Brush.Color;
    ACanvas.RoundRect(mTag.Left, mTag.Top, mTag.Right, mTag.Bottom, Radius, Radius);
    ACanvas.Brush.Style := bsClear;
    ACanvas.Font.Color := clWhite;
    ACanvas.TextOut(mTag.Left + ScaleValue(PillPadding), mTag.Top + (mTag.Height - ACanvas.TextHeight(mText)) div 2,
      mText);
    Limit := mTag.Left - ScaleValue(6);
  end;
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Name := MonoFont;
  ACanvas.Font.Color := TextColor;
  ACanvas.TextRect(Rect(mLeft, mTop + ScaleValue(1), Limit, mTop + ScaleValue(18)), mLeft, mTop + ScaleValue(1),
    Item.Test);
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Size := Font.Size - 1;
  ACanvas.Font.Color := MutedColor;
  ACanvas.TextRect(Rect(mLeft, mTop + ScaleValue(18), FBox.Width - ScaleValue(Indent), mTop + ScaleValue(34)), mLeft,
    mTop + ScaleValue(18), FailureDetail(Item));
  ACanvas.Font.Assign(Font);
end;

procedure TAtlasWelcomeTestResultsFrame.PaintButtons(ACanvas: TCanvas);
var
  Button: TAtlasTestResultsButton;
  mLeft, mTop, mWidth: Integer;
  mText: string;
  Area: TRect;
  mEnabled: Boolean;
  Accent, TextColor, MutedColor, LineColor: TColor;
begin
  Accent := StyleServices(Self).GetSystemColor(clHighlight);
  TextColor := StyleServices(Self).GetSystemColor(clWindowText);
  MutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  LineColor := StyleServices(Self).GetSystemColor(clBtnShadow);
  mLeft := ScaleValue(Indent);
  mTop := ButtonsTop + (ScaleValue(ButtonsHeight) - ScaleValue(ButtonHeight)) div 2;
  ACanvas.Font.Assign(Font);
  for Button := Low(TAtlasTestResultsButton) to High(TAtlasTestResultsButton) do
  begin
    FButtonRects[Button] := TRect.Empty;
    if not ButtonVisible(Button) then
      Continue;
    mText := ButtonText(Button);
    mWidth := ACanvas.TextWidth(mText) + 2 * ScaleValue(ButtonPadding);
    Area := Rect(mLeft, mTop, mLeft + mWidth, mTop + ScaleValue(ButtonHeight));
    FButtonRects[Button] := Area;
    mEnabled := ButtonEnabled(Button);
    // „Fehlgeschlagene erneut ausführen“ ist die Hauptaktion (Mockup: primary).
    if (Button = TAtlasTestResultsButton.Rerun) and mEnabled then
    begin
      ACanvas.Brush.Style := bsSolid;
      ACanvas.Brush.Color := Accent;
      ACanvas.Pen.Color := Accent;
      ACanvas.RoundRect(Area.Left, Area.Top, Area.Right, Area.Bottom, ScaleValue(6), ScaleValue(6));
      ACanvas.Font.Color := StyleServices(Self).GetSystemColor(clHighlightText);
    end
    else
    begin
      ACanvas.Brush.Style := bsClear;
      ACanvas.Pen.Color := LineColor;
      ACanvas.RoundRect(Area.Left, Area.Top, Area.Right, Area.Bottom, ScaleValue(6), ScaleValue(6));
      if mEnabled then
        ACanvas.Font.Color := TextColor
      else
        ACanvas.Font.Color := MutedColor;
    end;
    ACanvas.Brush.Style := bsClear;
    ACanvas.TextOut(Area.Left + (Area.Width - ACanvas.TextWidth(mText)) div 2,
      Area.Top + (Area.Height - ACanvas.TextHeight(mText)) div 2, mText);
    mLeft := Area.Right + ScaleValue(8);
  end;
end;

procedure TAtlasWelcomeTestResultsFrame.BoxPaint(Sender: TObject);
var
  Canvas: TCanvas;
  Index: Integer;
  Stamp: TDateTime;
begin
  Canvas := FBox.Canvas;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  if FView.Empty then
  begin
    Canvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
    Canvas.TextRect(Rect(ScaleValue(Indent), ScaleValue(4), FBox.Width - ScaleValue(Indent), BodyHeight),
      ScaleValue(Indent), ScaleValue(4), EmptyText);
    Exit;
  end;
  Stamp := NowUtc;
  for Index := 0 to High(FView.Rows) do
    PaintRow(Canvas, Index, Stamp);
  for Index := 0 to High(FView.Failures) do
    PaintFailure(Canvas, Index);
  if FView.More > 0 then
  begin
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := StyleServices(Self).GetSystemColor(clGrayText);
    Canvas.TextOut(ScaleValue(Indent) + ScaleValue(BarWidth) + ScaleValue(8),
      FailureTop(Length(FView.Failures)) + ScaleValue(1), TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsMore,
      [FView.More]));
  end;
  PaintButtons(Canvas);
end;

function TAtlasWelcomeTestResultsFrame.HitTest(X, Y: Integer): TAtlasTestResultsHit;
var
  Index: Integer;
  Button: TAtlasTestResultsButton;
begin
  Result := TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.None, -1);
  if FView.Empty then
    Exit;
  for Index := 0 to High(FView.Rows) do
    if (Y >= RowTop(Index)) and (Y < RowTop(Index) + RowHeight(Index)) then
      Exit(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Row, Index));
  for Index := 0 to High(FView.Failures) do
    if (Y >= FailureTop(Index)) and (Y < FailureTop(Index + 1)) then
      Exit(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Failure, Index));
  if (FView.More > 0) and (Y >= FailureTop(Length(FView.Failures))) and (Y < ButtonsTop) then
    Exit(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.More, -1));
  for Button := Low(TAtlasTestResultsButton) to High(TAtlasTestResultsButton) do
    if not FButtonRects[Button].IsEmpty and FButtonRects[Button].Contains(Point(X, Y)) then
      case Button of
        TAtlasTestResultsButton.Rerun:
          Exit(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Rerun, -1));
        TAtlasTestResultsButton.Debug:
          Exit(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Debug, -1));
      else
        Exit(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Browse, -1));
      end;
end;

procedure TAtlasWelcomeTestResultsFrame.ClickAt(const AHit: TAtlasTestResultsHit);
var
  mSource: IAtlasTestResultsSource;
  Row: TAtlasTestRow;
  Item: TAtlasTestFailureItem;
  Tests: TArray<string>;
  Project: string;
begin
  if (FSource = nil) or not FView.SelectedRow(Row) then
    Exit;
  mSource := FSource;
  case AHit.Kind of
    // Leerraum und die Zeile „… weitere“ sind keine Schaltflächen.
    TAtlasTestResultsHitKind.None, TAtlasTestResultsHitKind.More: ;
    TAtlasTestResultsHitKind.Row:
      begin
        if (AHit.Index < 0) or (AHit.Index > High(FView.Rows)) or (AHit.Index = FView.Selected) then
          Exit;
        Project := FView.Rows[AHit.Index].Project;
        FFailure := -1;
        // Die Quelle füllt den Bereich danach neu: nicht im eigenen Mausereignis.
        TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
          procedure
          begin
            mSource.Select(Project);
          end);
      end;
    TAtlasTestResultsHitKind.Failure:
      if (AHit.Index >= 0) and (AHit.Index <= High(FView.Failures)) then
      begin
        FFailure := AHit.Index;
        FBox.Invalidate;
      end;
    TAtlasTestResultsHitKind.Rerun:
      if ButtonEnabled(TAtlasTestResultsButton.Rerun) then
      begin
        Tests := FView.Rerun;
        TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
          procedure
          begin
            mSource.RerunFailed(Row, Tests);
          end);
      end;
    TAtlasTestResultsHitKind.Debug:
      if ButtonEnabled(TAtlasTestResultsButton.Debug) and SelectedFailure(Item) then
        TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
          procedure
          begin
            mSource.Debug(Row, Item);
          end);
    TAtlasTestResultsHitKind.Browse:
      if ButtonEnabled(TAtlasTestResultsButton.Browse) then
        TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
          procedure
          begin
            mSource.Browse(Row);
          end);
  end;
end;

procedure TAtlasWelcomeTestResultsFrame.DoubleClickAt(const AHit: TAtlasTestResultsHit);
var
  mSource: IAtlasTestResultsSource;
  Row: TAtlasTestRow;
  Item: TAtlasTestFailureItem;
begin
  if (FSource = nil) or not FView.SelectedRow(Row) then
    Exit;
  mSource := FSource;
  if (AHit.Kind = TAtlasTestResultsHitKind.Failure) and (AHit.Index >= 0) and
    (AHit.Index <= High(FView.Failures)) then
  begin
    FFailure := AHit.Index;
    Item := FView.Failures[AHit.Index];
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      begin
        mSource.OpenTest(Row, Item);
      end);
  end
  else if (AHit.Kind = TAtlasTestResultsHitKind.Row) and (AHit.Index >= 0) and (AHit.Index <= High(FView.Rows)) then
  begin
    Row := FView.Rows[AHit.Index];
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      begin
        mSource.OpenProject(Row);
      end);
  end;
end;

procedure TAtlasWelcomeTestResultsFrame.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Hit: TAtlasTestResultsHit;
  Key: string;
begin
  Hit := HitTest(X, Y);
  if Hit.Kind in [TAtlasTestResultsHitKind.Rerun, TAtlasTestResultsHitKind.Debug,
    TAtlasTestResultsHitKind.Browse, TAtlasTestResultsHitKind.Row, TAtlasTestResultsHitKind.Failure] then
    FBox.Cursor := crHandPoint
  else
    FBox.Cursor := crDefault;
  Key := IntToStr(Ord(Hit.Kind)) + ':' + IntToStr(Hit.Index);
  if Key = FHintKey then
    Exit;
  FHintKey := Key;
  case Hit.Kind of
    TAtlasTestResultsHitKind.Row:
      FBox.Hint := RowHint(FView.Rows[Hit.Index]);
    TAtlasTestResultsHitKind.Failure:
      FBox.Hint := FView.Failures[Hit.Index].Test + sLineBreak + FView.Failures[Hit.Index].Message + sLineBreak +
        TAtlasStrings.Text(TAtlasTextId.WelcomeTestsHintFailure);
  else
    FBox.Hint := '';
  end;
  Application.CancelHint;
end;

procedure TAtlasWelcomeTestResultsFrame.BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  FLastMouse := Point(X, Y);
  FDoubleDown := ssDouble in Shift;
end;

procedure TAtlasWelcomeTestResultsFrame.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  // Der zweite Klick eines Doppelklicks löst nichts noch einmal aus: BoxDblClick öffnet.
  if (Button = mbLeft) and not FDoubleDown then
    ClickAt(HitTest(X, Y));
  FDoubleDown := False;
end;

procedure TAtlasWelcomeTestResultsFrame.BoxDblClick(Sender: TObject);
begin
  DoubleClickAt(HitTest(FLastMouse.X, FLastMouse.Y));
end;

procedure TAtlasWelcomeTestResultsFrame.MenuPopup(Sender: TObject);
var
  Position: TPoint;
  Hit: TAtlasTestResultsHit;
  Row: TAtlasTestRow;
begin
  Position := FBox.ScreenToClient(FMenu.PopupPoint);
  Hit := HitTest(Position.X, Position.Y);
  FMenuRow := FView.Selected;
  if Hit.Kind = TAtlasTestResultsHitKind.Row then
    FMenuRow := Hit.Index;
  Row := Default(TAtlasTestRow);
  if (FMenuRow >= 0) and (FMenuRow <= High(FView.Rows)) then
    Row := FView.Rows[FMenuRow];
  FQueryItem.Visible := Row.HasCi;
  FCredentialsItem.Visible := Row.HasCi and (FSource <> nil) and FSource.CanEnterCredentials;
  FOpenItem.Enabled := FMenuRow >= 0;
end;

function TAtlasWelcomeTestResultsFrame.MenuTarget(out ARow: TAtlasTestRow): Boolean;
begin
  ARow := Default(TAtlasTestRow);
  Result := (FSource <> nil) and (FMenuRow >= 0) and (FMenuRow <= High(FView.Rows));
  if Result then
    ARow := FView.Rows[FMenuRow];
end;

procedure TAtlasWelcomeTestResultsFrame.QueryClick(Sender: TObject);
var
  mSource: IAtlasTestResultsSource;
  Row: TAtlasTestRow;
begin
  if not MenuTarget(Row) then
    Exit;
  mSource := FSource;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.QueryNow(Row);
    end);
end;

procedure TAtlasWelcomeTestResultsFrame.CredentialsClick(Sender: TObject);
var
  mSource: IAtlasTestResultsSource;
  Row: TAtlasTestRow;
begin
  if not MenuTarget(Row) then
    Exit;
  mSource := FSource;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.Credentials(Row);
    end);
end;

procedure TAtlasWelcomeTestResultsFrame.OpenClick(Sender: TObject);
var
  mSource: IAtlasTestResultsSource;
  Row: TAtlasTestRow;
begin
  if not MenuTarget(Row) then
    Exit;
  mSource := FSource;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.OpenProject(Row);
    end);
end;

{ TAtlasCiLoginPrompt }

class function TAtlasCiLoginPrompt.Ask(const AServer: string; var AUser, AToken: string): Boolean;
var
  Values: array of string;
begin
  SetLength(Values, 2);
  Values[0] := AUser;
  Values[1] := '';
  // Ein Steuerzeichen am Anfang der Beschriftung lässt InputQuery das Feld verdecken.
  Result := InputQuery(TAtlasStrings.Fmt(TAtlasTextId.CiLoginTitle, [AServer]),
    [TAtlasStrings.Text(TAtlasTextId.CiLoginUser), #31 + TAtlasStrings.Text(TAtlasTextId.CiLoginToken)], Values);
  if not Result then
    Exit;
  AUser := Trim(Values[0]);
  AToken := Trim(Values[1]);
  Values[1] := '';
end;

class function TAtlasCiLoginPrompt.AskToken(const ATitle, ALabel: string; var AToken: string): Boolean;
var
  Values: array of string;
begin
  SetLength(Values, 1);
  Values[0] := '';
  Result := InputQuery(ATitle, [#31 + ALabel], Values);
  if not Result then
    Exit;
  AToken := Trim(Values[0]);
  Values[0] := '';
end;

end.
