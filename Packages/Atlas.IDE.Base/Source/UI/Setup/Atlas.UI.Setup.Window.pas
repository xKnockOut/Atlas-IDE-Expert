unit Atlas.UI.Setup.Window;

// Fenster „Atlas-Einrichtung“ (#625, Mockup Runde 25 Z2), reine VCL: oben
// Titel und „5 von 6 erledigt“, darunter je Prüfung ein farbiger Punkt
// (grün, gelb, rot), der Text, gedämpft die Einzelheit (z. B. „AtlasServer
// 0.1.0“) und rechts der Knopf, der das Problem behebt oder erklärt. Unter
// dem Index steht je Projekt der Gruppe eine Unterzeile mit ihrem Stand
// (#619). „Warum?“ zeigt die Erklärung im Fenster, die übrigen Knöpfe rufen
// OnFix. Unten der Einstieg „Probier es aus: Strg+Leertaste in einer
// Methode“, „Beim Start zeigen …“ (ui.setupChecklist), „Bericht kopieren“,
// „Erneut prüfen“ und „Schließen“. Das Fenster ist nicht modal; es zeigt, was
// SetResults bekommt, und schließt mit Esc. Texte in der Sprache der IDE aus
// Befund und Werten der Prüfung (TAtlasSetupResult).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.StdCtrls,
  Atlas.Core.Style.Palette,
  Atlas.Core.Status.Contract,
  Atlas.Core.Setup.Checklist;

type
  /// <summary>Texte der Einrichtung in der Sprache der IDE aus Befund und Werten der Prüfung.</summary>
  TAtlasSetupTexts = class
  public
    /// <summary>Hauptzeile einer Prüfung, z. B. „Server gefunden, gestartet, Version passt“.</summary>
    class function ResultText(const AResult: TAtlasSetupResult): string; static;
    /// <summary>Gedämpfte Einzelheit hinter dem Text, z. B. „AtlasServer 0.1.0“; '' ohne.</summary>
    class function DetailText(const AResult: TAtlasSetupResult): string; static;
    /// <summary>Unterzeile je Projekt, z. B. „Kunden: fertig“.</summary>
    class function ProjectText(const AProject: TAtlasSetupProject): string; static;
    class function ProjectState(const AProject: TAtlasSetupProject): TAtlasStatusState; static;
    /// <summary>Beschriftung des Knopfs; '' für None.</summary>
    class function FixCaption(AFix: TAtlasSetupFix): string; static;
    /// <summary>Erklärung zu „Warum?“; sonst die Hauptzeile.</summary>
    class function WhyText(const AResult: TAtlasSetupResult): string; static;
    /// <summary>„5 von 6 erledigt“.</summary>
    class function ProgressText(const AResults: TArray<TAtlasSetupResult>): string; static;
    /// <summary>Zeilen für den Bericht (#108): je Prüfung Text mit Einzelheit, darunter die Projekte.</summary>
    class function ReportLines(const AResults: TArray<TAtlasSetupResult>): TArray<TAtlasSetupReportLine>; static;
  end;

  /// <summary>Gezeichnete Zeile: Prüfung (Project = -1) oder Projekt darunter.</summary>
  TAtlasSetupLine = record
    Result_: Integer;
    Project: Integer;
    Top: Integer;
    Height: Integer;
  end;

  /// <summary>Lage nach dem Layout: Zeilen, Hinweis und Fußzeile.</summary>
  TAtlasSetupGeometry = record
    Lines: TArray<TAtlasSetupLine>;
    NoteTop: Integer;
    NoteHeight: Integer;
    FooterTop: Integer;
  end;

  TAtlasSetupEvents = record
    Fix: TProc<TAtlasSetupResult>;
    Copy: TProc;
    Recheck: TProc;
    ShowAtStart: TProc<Boolean>;
  end;

  TAtlasSetupWindow = class(TForm)
  private
    FColors: TAtlasColors;
    FResults: TArray<TAtlasSetupResult>;
    FGeometry: TAtlasSetupGeometry;
    FFixButtons: TArray<TButton>;
    FCopyButton: TButton;
    FRecheckButton: TButton;
    FCloseButton: TButton;
    FShowAtStart: TCheckBox;
    FTryKey: string;
    FNote: string;
    FUpdating: Boolean;
    FEvents: TAtlasSetupEvents;
    function FixButton(AIndex: Integer): TButton;
    function NewButton(const ACaption: string): TButton;
    procedure Layout;
    procedure FixClick(Sender: TObject);
    /// <summary>Kopieren, Erneut prüfen und Schließen.</summary>
    procedure FooterClick(Sender: TObject);
    procedure ShowAtStartClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  protected
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Resize; override;
  public
    constructor CreateSetup(AOwner: TComponent; const AColors: TAtlasColors);
    /// <summary>Prüfungen setzen (auch bei offenem Fenster); Knöpfe und Höhe folgen.</summary>
    procedure SetResults(const AResults: TArray<TAtlasSetupResult>);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Taste für den Einstieg „Probier es aus“, z. B. „Strg+Leertaste“.</summary>
    procedure SetTryKey(const AKey: string);
    /// <summary>Häkchen „Beim Start zeigen …“ setzen, ohne OnShowAtStart auszulösen.</summary>
    procedure SetShowAtStart(AValue: Boolean);
    /// <summary>Hinweis über der Fußzeile (Erklärung, „Bericht in der Zwischenablage“); '' blendet ihn aus.</summary>
    procedure ShowNote(const AText: string);
    property Results: TArray<TAtlasSetupResult> read FResults;
    property Note: string read FNote;
    property TryKey: string read FTryKey;
    /// <summary>Zum Testen: Knopf der Prüfung AIndex (unsichtbar ohne Knopf).</summary>
    property FixButtons[AIndex: Integer]: TButton read FixButton;
    property CopyButton: TButton read FCopyButton;
    property RecheckButton: TButton read FRecheckButton;
    property CloseButton: TButton read FCloseButton;
    property ShowAtStartBox: TCheckBox read FShowAtStart;
    /// <summary>Knopf einer Prüfung außer „Warum?“ (das erklärt das Fenster selbst).</summary>
    property OnFix: TProc<TAtlasSetupResult> read FEvents.Fix write FEvents.Fix;
    property OnCopy: TProc read FEvents.Copy write FEvents.Copy;
    property OnRecheck: TProc read FEvents.Recheck write FEvents.Recheck;
    property OnShowAtStart: TProc<Boolean> read FEvents.ShowAtStart write FEvents.ShowAtStart;
  end;

implementation

uses
  Atlas.Core.Style.Color,
  System.Math,
  Atlas.UI.Strings,
  Atlas.UI.Setup.Strings;

const
  /// <summary>Hauptzeile je Befund; Varianten (Einheiten, gewonnene Tasten) wählt ResultTextId.</summary>
  cResultTexts: array[TAtlasSetupFinding] of TAtlasTextId = (TAtlasTextId.SetupServerReady,
    TAtlasTextId.SetupServerMissing, TAtlasTextId.SetupServerNotStarted, TAtlasTextId.SetupServerStarting,
    TAtlasTextId.SetupServerStopped, TAtlasTextId.SetupServerFailed, TAtlasTextId.SetupServerVersionUnknown,
    TAtlasTextId.SetupServerVersionMismatch, TAtlasTextId.SetupDelphiReady, TAtlasTextId.SetupDelphiNoProject,
    TAtlasTextId.SetupDelphiUnknown, TAtlasTextId.SetupIndexReady, TAtlasTextId.SetupIndexBuilding,
    TAtlasTextId.SetupIndexIncomplete, TAtlasTextId.SetupIndexNoServer, TAtlasTextId.SetupIndexNoProjects,
    TAtlasTextId.SetupLibraryReady, TAtlasTextId.SetupLibraryMissing, TAtlasTextId.SetupLibraryPending,
    TAtlasTextId.SetupLibraryUnknown, TAtlasTextId.SetupErrorInsightAtlas, TAtlasTextId.SetupErrorInsightIde,
    TAtlasTextId.SetupErrorInsightDuplicate, TAtlasTextId.SetupErrorInsightNone,
    TAtlasTextId.SetupErrorInsightRestart, TAtlasTextId.SetupKeysReady, TAtlasTextId.SetupKeysConflict);
  /// <summary>Befunde, deren Hauptzeile Werte der Prüfung einsetzt.</summary>
  cFormattedResults = [TAtlasSetupFinding.ServerVersionMismatch, TAtlasSetupFinding.DelphiReady,
    TAtlasSetupFinding.DelphiNoProject, TAtlasSetupFinding.IndexReady, TAtlasSetupFinding.IndexBuilding,
    TAtlasSetupFinding.IndexIncomplete, TAtlasSetupFinding.KeysConflict];

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function Arg(const AResult: TAtlasSetupResult; AIndex: Integer): string;
begin
  Result := '';
  if AIndex <= High(AResult.Args) then
  begin
    Result := AResult.Args[AIndex];
  end;
end;

/// <summary>Text der Hauptzeile; AFormatted, wenn er Werte der Prüfung einsetzt.</summary>
function ResultTextId(const AResult: TAtlasSetupResult; out AFormatted: Boolean): TAtlasTextId;
begin
  Result := cResultTexts[AResult.Finding];
  AFormatted := AResult.Finding in cFormattedResults;
  if (AResult.Finding = TAtlasSetupFinding.IndexReady) and (Arg(AResult, 1) <> '') then
  begin
    Result := TAtlasTextId.SetupIndexReadyUnits;
  end
  else if (AResult.Finding = TAtlasSetupFinding.KeysReady) and (StrToIntDef(Arg(AResult, 0), 0) > 0) then
  begin
    Result := TAtlasTextId.SetupKeysReadyWins;
    AFormatted := True;
  end;
end;

{ TAtlasSetupTexts }

class function TAtlasSetupTexts.ResultText(const AResult: TAtlasSetupResult): string;
var
  mId: TAtlasTextId;
  mFormatted: Boolean;
begin
  mId := ResultTextId(AResult, mFormatted);
  if mFormatted then
  begin
    Result := TAtlasStrings.Fmt(mId, [Arg(AResult, 0), Arg(AResult, 1), Arg(AResult, 2)]);
  end
  else
  begin
    Result := TAtlasStrings.Text(mId);
  end;
end;

class function TAtlasSetupTexts.DetailText(const AResult: TAtlasSetupResult): string;
var
  mBytes: Int64;
begin
  Result := '';
  case AResult.Finding of
    TAtlasSetupFinding.ServerReady:
      Result := TAtlasSetupStrings.Fmt(TAtlasSetupTextId.SetupServerVersion, [Arg(AResult, 0)]);
    TAtlasSetupFinding.ServerFailed:
      Result := Arg(AResult, 0);
    TAtlasSetupFinding.DelphiReady:
      Result := TAtlasSetupStrings.Fmt(TAtlasSetupTextId.SetupDelphiPlatform, [Arg(AResult, 1)]);
    TAtlasSetupFinding.IndexBuilding:
      if Arg(AResult, 2) <> '' then
      begin
        Result := TAtlasSetupStrings.Fmt(TAtlasSetupTextId.SetupIndexPercent, [Arg(AResult, 2)]);
      end;
    TAtlasSetupFinding.LibraryReady:
      begin
        mBytes := StrToInt64Def(Arg(AResult, 0), 0);
        Result := TAtlasSetupStrings.Fmt(TAtlasSetupTextId.SetupLibrarySize,
          [FormatFloat('0.0', mBytes / (1024 * 1024), FormatSettings)]);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TAtlasSetupTexts.ProjectText(const AProject: TAtlasSetupProject): string;
begin
  case AProject.State of
    TAtlasSetupProjectState.Done:
      Result := TAtlasSetupStrings.Fmt(TAtlasSetupTextId.SetupProjectDone, [AProject.Name]);
    TAtlasSetupProjectState.Building:
      Result := TAtlasSetupStrings.Fmt(TAtlasSetupTextId.SetupProjectBuilding, [AProject.Name]);
  else
    Result := TAtlasSetupStrings.Fmt(TAtlasSetupTextId.SetupProjectMissing, [AProject.Name]);
  end;
end;

class function TAtlasSetupTexts.ProjectState(const AProject: TAtlasSetupProject): TAtlasStatusState;
begin
  case AProject.State of
    TAtlasSetupProjectState.Done:
      Result := TAtlasStatusState.Green;
    TAtlasSetupProjectState.Building:
      Result := TAtlasStatusState.Yellow;
  else
    Result := TAtlasStatusState.Red;
  end;
end;

class function TAtlasSetupTexts.FixCaption(AFix: TAtlasSetupFix): string;
begin
  case AFix of
    TAtlasSetupFix.Explain:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupFixExplain);
    TAtlasSetupFix.ChooseServerPath:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupFixChoosePath);
    TAtlasSetupFix.StartServer:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupFixStart);
    TAtlasSetupFix.RestartServer:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupFixRestart);
    TAtlasSetupFix.RebuildIndex:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupFixRebuild);
    TAtlasSetupFix.BuildLibraryCache:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupFixBuildLibrary);
    TAtlasSetupFix.DisableErrorInsight:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupFixDisableErrorInsight);
    TAtlasSetupFix.EnableErrorInsight:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupFixEnableErrorInsight);
    TAtlasSetupFix.OpenKeyConflicts:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupFixKeys);
  else
    Result := '';
  end;
end;

class function TAtlasSetupTexts.WhyText(const AResult: TAtlasSetupResult): string;
begin
  case AResult.Finding of
    TAtlasSetupFinding.ServerStarting:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupWhyServerStarting);
    TAtlasSetupFinding.ServerVersionUnknown:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupWhyServerVersion);
    TAtlasSetupFinding.DelphiNoProject:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupWhyDelphiNoProject);
    TAtlasSetupFinding.DelphiUnknown:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupWhyDelphiUnknown);
    TAtlasSetupFinding.IndexBuilding:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupWhyIndexBuilding);
    TAtlasSetupFinding.IndexNoProjects:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupWhyIndexNoProjects);
    TAtlasSetupFinding.LibraryPending:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupWhyLibraryPending);
    TAtlasSetupFinding.ErrorInsightRestart:
      Result := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupWhyErrorInsightRestart);
  else
    Result := ResultText(AResult);
  end;
end;

class function TAtlasSetupTexts.ProgressText(const AResults: TArray<TAtlasSetupResult>): string;
var
  mDone, mTotal: Integer;
begin
  TAtlasSetupChecklist.Progress(AResults, mDone, mTotal);
  Result := TAtlasSetupStrings.Fmt(TAtlasSetupTextId.SetupProgress, [mDone, mTotal]);
end;

class function TAtlasSetupTexts.ReportLines(const AResults: TArray<TAtlasSetupResult>):
  TArray<TAtlasSetupReportLine>;
var
  mItem: TAtlasSetupResult;
  mProject: TAtlasSetupProject;
  mText: string;
begin
  Result := nil;
  for mItem in AResults do
  begin
    mText := ResultText(mItem);
    if DetailText(mItem) <> '' then
    begin
      mText := mText + ' (' + DetailText(mItem) + ')';
    end;
    Result := Result + [TAtlasSetupReportLine.Create(mItem.State, mText, False)];
    for mProject in mItem.Projects do
    begin
      Result := Result + [TAtlasSetupReportLine.Create(ProjectState(mProject), ProjectText(mProject), True)];
    end;
  end;
end;

type
  /// <summary>Höhen der Zeilen in der Fensterschrift.</summary>
  TAtlasSetupMetrics = record
    Window: TAtlasSetupWindow;
    function RowHeight: Integer;
    function SubRowHeight: Integer;
    function HeaderHeight: Integer;
    function ButtonsHeight: Integer;
  end;

  /// <summary>Layout: Knöpfe und Zeilen je Prüfung, Hinweis, Fußzeile.</summary>
  TAtlasSetupArranger = record
    Window: TAtlasSetupWindow;
    Metrics: TAtlasSetupMetrics;
    procedure EnsureFixButtons;
    /// <summary>Zeilen ab ATop; liefert die Unterkante.</summary>
    function Lines(ATop: Integer): Integer;
    procedure Note(ATop: Integer);
    procedure Footer;
  end;

  /// <summary>Zeichnen: Kopf, Zeilen, Hinweis und Einstieg „Probier es aus“.</summary>
  TAtlasSetupPainter = record
    Window: TAtlasSetupWindow;
    Metrics: TAtlasSetupMetrics;
    procedure Dot(const ACenter: TPoint; ARadius: Integer; AState: TAtlasStatusState);
    procedure Header;
    procedure ProjectLine(const ALine: TAtlasSetupLine; const AItem: TAtlasSetupResult);
    procedure ResultLine(const ALine: TAtlasSetupLine; const AItem: TAtlasSetupResult);
    procedure Note;
    procedure TryIt;
  end;

{ TAtlasSetupMetrics }

function TAtlasSetupMetrics.RowHeight: Integer;
begin
  Window.Canvas.Font := Window.Font;
  Result := Max(Window.Canvas.TextHeight('Wg') + Window.ScaleValue(12), Window.ScaleValue(31));
end;

function TAtlasSetupMetrics.SubRowHeight: Integer;
begin
  Window.Canvas.Font := Window.Font;
  Result := Window.Canvas.TextHeight('Wg') + Window.ScaleValue(4);
end;

function TAtlasSetupMetrics.HeaderHeight: Integer;
begin
  Result := RowHeight + Window.ScaleValue(4);
end;

function TAtlasSetupMetrics.ButtonsHeight: Integer;
begin
  Result := Window.ScaleValue(44);
end;

{ TAtlasSetupArranger }

procedure TAtlasSetupArranger.EnsureFixButtons;
var
  mButton: TButton;
  mIndex: Integer;
begin
  // Je Prüfung ein Knopf; überzählige ausblenden.
  while Length(Window.FFixButtons) < Length(Window.FResults) do
  begin
    mButton := TButton.Create(Window);
    mButton.Parent := Window;
    mButton.Tag := Length(Window.FFixButtons);
    mButton.OnClick := Window.FixClick;
    Window.FFixButtons := Window.FFixButtons + [mButton];
  end;
  for mIndex := 0 to High(Window.FFixButtons) do
  begin
    Window.FFixButtons[mIndex].Visible := False;
  end;
end;

function TAtlasSetupArranger.Lines(ATop: Integer): Integer;
var
  mIndex, mProject, mWidth: Integer;
  mLine: TAtlasSetupLine;
  mButton: TButton;
  mText: string;
begin
  Window.FGeometry.Lines := nil;
  Result := ATop;
  for mIndex := 0 to High(Window.FResults) do
  begin
    mLine.Result_ := mIndex;
    mLine.Project := -1;
    mLine.Top := Result;
    mLine.Height := Metrics.RowHeight;
    Window.FGeometry.Lines := Window.FGeometry.Lines + [mLine];
    mButton := Window.FFixButtons[mIndex];
    mText := TAtlasSetupTexts.FixCaption(Window.FResults[mIndex].Fix);
    mButton.Caption := mText;
    mButton.Visible := mText <> '';
    mWidth := Max(Window.Canvas.TextWidth(mText) + Window.ScaleValue(24), Window.ScaleValue(90));
    mButton.SetBounds(Window.ClientWidth - mWidth - Window.ScaleValue(12),
      Result + (mLine.Height - Window.ScaleValue(25)) div 2, mWidth, Window.ScaleValue(25));
    Inc(Result, mLine.Height);
    for mProject := 0 to High(Window.FResults[mIndex].Projects) do
    begin
      mLine.Project := mProject;
      mLine.Top := Result;
      mLine.Height := Metrics.SubRowHeight;
      Window.FGeometry.Lines := Window.FGeometry.Lines + [mLine];
      Inc(Result, mLine.Height);
    end;
  end;
end;

procedure TAtlasSetupArranger.Note(ATop: Integer);
var
  mArea: TRect;
begin
  // Erklärung bzw. Hinweis, umbrochen.
  Window.FGeometry.NoteTop := ATop + Window.ScaleValue(4);
  Window.FGeometry.NoteHeight := 0;
  if Window.FNote <> '' then
  begin
    mArea := Rect(0, 0, Window.ClientWidth - Window.ScaleValue(40), 0);
    DrawText(Window.Canvas.Handle, PChar(Window.FNote), -1, mArea, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
    Window.FGeometry.NoteHeight := mArea.Height + Window.ScaleValue(8);
  end;
  Window.FGeometry.FooterTop := Window.FGeometry.NoteTop + Window.FGeometry.NoteHeight + Window.ScaleValue(4);
end;

procedure TAtlasSetupArranger.Footer;
var
  mBottom, mWidth, mHeight: Integer;
begin
  Window.ClientHeight := Window.FGeometry.FooterTop + Metrics.RowHeight + Metrics.ButtonsHeight;
  mBottom := Window.ClientHeight - Metrics.ButtonsHeight + Window.ScaleValue(10);
  mHeight := Window.ScaleValue(25);
  mWidth := Max(Max(Window.Canvas.TextWidth(Window.FCopyButton.Caption),
    Window.Canvas.TextWidth(Window.FRecheckButton.Caption)), Window.Canvas.TextWidth(Window.FCloseButton.Caption)) +
    Window.ScaleValue(24);
  Window.FCloseButton.SetBounds(Window.ClientWidth - mWidth - Window.ScaleValue(12), mBottom, mWidth, mHeight);
  Window.FRecheckButton.SetBounds(Window.FCloseButton.Left - mWidth - Window.ScaleValue(8), mBottom, mWidth,
    mHeight);
  Window.FCopyButton.SetBounds(Window.FRecheckButton.Left - mWidth - Window.ScaleValue(8), mBottom, mWidth, mHeight);
  Window.FShowAtStart.SetBounds(Window.ScaleValue(12), mBottom + Window.ScaleValue(4), Max(Window.ScaleValue(80),
    Window.FCopyButton.Left - Window.ScaleValue(24)), Window.ScaleValue(19));
end;

{ TAtlasSetupPainter }

procedure TAtlasSetupPainter.Dot(const ACenter: TPoint; ARadius: Integer; AState: TAtlasStatusState);
begin
  // Signalfarbe mit Rand (#1255), nicht die Textfarben Add/Warn/Error.
  Window.Canvas.Pen.Color := ToColor(Window.FColors.Signals.ForStatus(AState).Ring);
  Window.Canvas.Brush.Color := ToColor(Window.FColors.Signals.ForStatus(AState).Fill);
  Window.Canvas.Brush.Style := bsSolid;
  Window.Canvas.Ellipse(ACenter.X - ARadius, ACenter.Y - ARadius, ACenter.X + ARadius + 1, ACenter.Y + ARadius + 1);
end;

procedure TAtlasSetupPainter.Header;
var
  mPart: TRect;
  mText: string;
begin
  // Kopf: Titel und Fortschritt.
  Window.Canvas.Brush.Style := bsClear;
  mPart := Rect(Window.ScaleValue(12), 0, Window.ClientWidth - Window.ScaleValue(12), Metrics.HeaderHeight);
  Window.Canvas.Font.Style := [fsBold];
  Window.Canvas.Font.Color := ToColor(Window.FColors.Text);
  mText := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupTitle);
  DrawText(Window.Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Window.Canvas.Font.Style := [];
  Window.Canvas.Font.Color := ToColor(Window.FColors.Muted);
  mText := TAtlasSetupTexts.ProgressText(Window.FResults);
  DrawText(Window.Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_RIGHT or DT_NOPREFIX);
  Window.Canvas.Pen.Color := ToColor(Window.FColors.Line);
  Window.Canvas.MoveTo(0, Metrics.HeaderHeight - Window.ScaleValue(2));
  Window.Canvas.LineTo(Window.ClientWidth, Metrics.HeaderHeight - Window.ScaleValue(2));
end;

procedure TAtlasSetupPainter.ProjectLine(const ALine: TAtlasSetupLine; const AItem: TAtlasSetupResult);
var
  mPart: TRect;
  mText: string;
begin
  // Unterzeile je Projekt (#619): kleiner Punkt, gedämpfter Text.
  Dot(Point(Window.ScaleValue(40), ALine.Top + ALine.Height div 2), Window.ScaleValue(3),
    TAtlasSetupTexts.ProjectState(AItem.Projects[ALine.Project]));
  Window.Canvas.Brush.Style := bsClear;
  Window.Canvas.Font.Color := ToColor(Window.FColors.Muted);
  mPart := Rect(Window.ScaleValue(50), ALine.Top, Window.ClientWidth - Window.ScaleValue(12), ALine.Top + ALine.Height);
  mText := TAtlasSetupTexts.ProjectText(AItem.Projects[ALine.Project]);
  DrawText(Window.Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
    DT_END_ELLIPSIS);
end;

procedure TAtlasSetupPainter.ResultLine(const ALine: TAtlasSetupLine; const AItem: TAtlasSetupResult);
var
  mPart: TRect;
  mText, mDetail: string;
  mRight: Integer;
  mButton: TButton;
begin
  Dot(Point(Window.ScaleValue(20), ALine.Top + ALine.Height div 2), Window.ScaleValue(5), AItem.State);
  Window.Canvas.Brush.Style := bsClear;
  mRight := Window.ClientWidth - Window.ScaleValue(12);
  mButton := Window.FixButton(ALine.Result_);
  if (mButton <> nil) and mButton.Visible then
  begin
    mRight := mButton.Left - Window.ScaleValue(8);
  end;
  mPart := Rect(Window.ScaleValue(34), ALine.Top, mRight, ALine.Top + ALine.Height);
  mText := TAtlasSetupTexts.ResultText(AItem);
  Window.Canvas.Font.Color := ToColor(Window.FColors.Text);
  DrawText(Window.Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  mDetail := TAtlasSetupTexts.DetailText(AItem);
  mPart.Left := mPart.Left + Window.Canvas.TextWidth(mText) + Window.ScaleValue(10);
  if (mDetail <> '') and (mPart.Left < mPart.Right) then
  begin
    Window.Canvas.Font.Color := ToColor(Window.FColors.Muted);
    DrawText(Window.Canvas.Handle, PChar(mDetail), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
      DT_END_ELLIPSIS);
  end;
end;

procedure TAtlasSetupPainter.Note;
var
  mPart: TRect;
begin
  // Erklärung bzw. Hinweis.
  if Window.FNote = '' then
  begin
    Exit;
  end;
  mPart := Rect(Window.ScaleValue(20), Window.FGeometry.NoteTop + Window.ScaleValue(4),
    Window.ClientWidth - Window.ScaleValue(20), Window.FGeometry.NoteTop + Window.FGeometry.NoteHeight);
  Window.Canvas.Font.Color := ToColor(Window.FColors.Muted);
  DrawText(Window.Canvas.Handle, PChar(Window.FNote), -1, mPart, DT_WORDBREAK or DT_NOPREFIX);
end;

procedure TAtlasSetupPainter.TryIt;
var
  mPart: TRect;
  mText, mBefore, mAfter, mKey: string;
  mKeyAt, mTop: Integer;
begin
  // Einstieg: „Probier es aus: Strg+Leertaste in einer Methode“, die Taste fett.
  mTop := Window.FGeometry.FooterTop;
  mKey := Window.FTryKey;
  Window.Canvas.Pen.Color := ToColor(Window.FColors.Line);
  Window.Canvas.MoveTo(0, mTop);
  Window.Canvas.LineTo(Window.ClientWidth, mTop);
  mText := TAtlasSetupStrings.Fmt(TAtlasSetupTextId.SetupTryIt, [mKey]);
  mKeyAt := Pos(mKey, mText);
  mBefore := mText;
  mAfter := '';
  if mKeyAt > 0 then
  begin
    mBefore := Copy(mText, 1, mKeyAt - 1);
    mAfter := Copy(mText, mKeyAt + Length(mKey), MaxInt);
  end;
  mPart := Rect(Window.ScaleValue(12), mTop, Window.ClientWidth - Window.ScaleValue(12), mTop + Metrics.RowHeight);
  Window.Canvas.Font.Color := ToColor(Window.FColors.Text);
  DrawText(Window.Canvas.Handle, PChar(mBefore), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  if mKeyAt > 0 then
  begin
    mPart.Left := mPart.Left + Window.Canvas.TextWidth(mBefore);
    Window.Canvas.Font.Style := [fsBold];
    DrawText(Window.Canvas.Handle, PChar(mKey), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
    mPart.Left := mPart.Left + Window.Canvas.TextWidth(mKey);
    Window.Canvas.Font.Style := [];
    DrawText(Window.Canvas.Handle, PChar(mAfter), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  end;
end;

{ TAtlasSetupWindow }

constructor TAtlasSetupWindow.CreateSetup(AOwner: TComponent; const AColors: TAtlasColors);
begin
  inherited CreateNew(AOwner);
  FColors := AColors;
  Caption := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupTitle);
  BorderStyle := bsSingle;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  KeyPreview := True;
  DoubleBuffered := True;
  Color := ToColor(FColors.Surface);
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  OnClose := FormClose;
  FCopyButton := NewButton(TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupCopy));
  FRecheckButton := NewButton(TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupRecheck));
  FCloseButton := NewButton(TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupClose));
  FCloseButton.Cancel := True;
  FShowAtStart := TCheckBox.Create(Self);
  FShowAtStart.Parent := Self;
  FShowAtStart.Caption := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupShowAtStart);
  FShowAtStart.Checked := True;
  FShowAtStart.OnClick := ShowAtStartClick;
  FTryKey := 'Strg+Leertaste';
  Layout;
end;

function TAtlasSetupWindow.NewButton(const ACaption: string): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Self;
  Result.Caption := ACaption;
  Result.OnClick := FooterClick;
end;

function TAtlasSetupWindow.FixButton(AIndex: Integer): TButton;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FFixButtons)) then
  begin
    Result := FFixButtons[AIndex];
  end;
end;

procedure TAtlasSetupWindow.Layout;
var
  mArranger: TAtlasSetupArranger;
begin
  mArranger.Window := Self;
  mArranger.Metrics.Window := Self;
  Canvas.Font := Font;
  ClientWidth := ScaleValue(620);
  mArranger.EnsureFixButtons;
  mArranger.Note(mArranger.Lines(mArranger.Metrics.HeaderHeight));
  mArranger.Footer;
  Invalidate;
end;

procedure TAtlasSetupWindow.Resize;
begin
  inherited;
  Invalidate;
end;

procedure TAtlasSetupWindow.SetResults(const AResults: TArray<TAtlasSetupResult>);
begin
  FResults := AResults;
  Layout;
end;

procedure TAtlasSetupWindow.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Color := ToColor(FColors.Surface);
  FShowAtStart.Font.Color := ToColor(FColors.Text);
  Invalidate;
end;

procedure TAtlasSetupWindow.SetTryKey(const AKey: string);
begin
  if AKey <> '' then
  begin
    FTryKey := AKey;
  end;
  Invalidate;
end;

procedure TAtlasSetupWindow.SetShowAtStart(AValue: Boolean);
begin
  FUpdating := True;
  try
    FShowAtStart.Checked := AValue;
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasSetupWindow.ShowNote(const AText: string);
begin
  FNote := AText;
  Layout;
end;

procedure TAtlasSetupWindow.FixClick(Sender: TObject);
var
  mIndex: Integer;
  mItem: TAtlasSetupResult;
begin
  mIndex := TButton(Sender).Tag;
  if (mIndex < 0) or (mIndex > High(FResults)) then
  begin
    Exit;
  end;
  mItem := FResults[mIndex];
  if mItem.Fix = TAtlasSetupFix.Explain then
  begin
    ShowNote(TAtlasSetupTexts.WhyText(mItem));
    Exit;
  end;
  ShowNote('');
  if Assigned(FEvents.Fix) then
  begin
    FEvents.Fix(mItem);
  end;
end;

procedure TAtlasSetupWindow.FooterClick(Sender: TObject);
begin
  if Sender = FCloseButton then
  begin
    Close;
  end
  else if Sender = FRecheckButton then
  begin
    ShowNote('');
    if Assigned(FEvents.Recheck) then
    begin
      FEvents.Recheck();
    end;
  end
  else if Assigned(FEvents.Copy) then
  begin
    FEvents.Copy();
  end;
end;

procedure TAtlasSetupWindow.ShowAtStartClick(Sender: TObject);
begin
  if not FUpdating and Assigned(FEvents.ShowAtStart) then
  begin
    FEvents.ShowAtStart(FShowAtStart.Checked);
  end;
end;

procedure TAtlasSetupWindow.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // Die IDE-Schicht behält das Fenster und zeigt es beim nächsten Abruf wieder.
  Action := caHide;
end;

procedure TAtlasSetupWindow.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Close;
    Exit;
  end;
  inherited;
end;

procedure TAtlasSetupWindow.Paint;
var
  mPainter: TAtlasSetupPainter;
  mLine: TAtlasSetupLine;
begin
  mPainter.Window := Self;
  mPainter.Metrics.Window := Self;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  mPainter.Header;
  for mLine in FGeometry.Lines do
  begin
    if mLine.Project >= 0 then
    begin
      mPainter.ProjectLine(mLine, FResults[mLine.Result_]);
    end
    else
    begin
      mPainter.ResultLine(mLine, FResults[mLine.Result_]);
    end;
  end;
  mPainter.Note;
  mPainter.TryIt;
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, ClientHeight - mPainter.Metrics.ButtonsHeight);
  Canvas.LineTo(ClientWidth, ClientHeight - mPainter.Metrics.ButtonsHeight);
  Canvas.Brush.Style := bsSolid;
end;

end.
