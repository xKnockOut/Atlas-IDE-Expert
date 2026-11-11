unit Atlas.UI.Tracker.MyIssues;

// Bereich „Meine Issues“ der Willkommensseite (#765, Mockup #ws12), ohne
// Open Tools API. Selbst gezeichnet, je Issue zwei Zeilen im Raster:
//   #753     Atlas-Bereiche und Layout der Willkommens…   [Beginnen]
//            (plugin) (welcome) (PR #760 · CI grün)
//   ─────────────────────────────────────────────────────────────────
//   ATL-123  Tracker im Bereich                           [Beginnen]
//            (In Arbeit) (Hoch) (Sprint 12) (aktuell)
//   „Beginnen“ legt den Branch an und öffnet das Projekt.
// Kennung grau in Festbreitenschrift (Klick öffnet das Issue im Browser; mit
// issues.preview zeigt ein Klick auf Zeile oder Kennung das Issue im Fenster
// „Atlas-Issue“ und Strg+Klick öffnet den Browser, #1264),
// Titel abgeschnitten, darunter Felder als Chips mit Rahmen (GitHub: Labels
// und der Pull Request mit CI-Ampel, Klick öffnet ihn; YouTrack: Zustand,
// Priorität, Sprint). Rechts „Beginnen“ über beide Zeilen. Über der Liste nur
// bei Bedarf eine Zeile zum Stand (wird abgefragt, Fehler, „Stand vom …“),
// darunter die Fußzeile bzw. der Hinweis nach „Beginnen“. Kontextmenü: Im
// Browser öffnen, Pull-Request im Browser, Beginnen, Nur merken, Tracker jetzt
// abfragen, Zugang hinterlegen, Aktuelles Issue beenden.
// Ohne Tracker (weder .atlas noch Zuordnung, #1261) ist die Fußzeile der Link
// „Kein Tracker für dieses Projekt – zuordnen …“ (AssignProject).
// Abfragen (#1262): rechts in der ersten Zeile die Klappliste „Mir zugewiesen
// (3) ▾“ mit den passenden Abfragen samt Trefferzahl der letzten Abfrage und
// „Abfragen bearbeiten …“ (issues.queryPicker aus: keine Klappliste). Unter
// der Fußzeile eine Zeile mit Verbindung, Tracker-Projekt und der gesendeten
// Abfrage. Links in derselben Zeile die Klappliste „Projekt: … ▾“ (#1927,
// TAtlasTrackerProjectPicker). Bei „Alle Tracker-Projekte“ (#1928) steht vor
// jeder Gruppe eine Kopfzeile „YouTrack · KASSE (7)“ mit „+ N weitere“ bzw.
// dem Hinweis der Gruppe (kein Zugang, Fehler, keine Issues).
// Daten und Aktionen kommen über IAtlasIssuesSource aus der IDE-Schicht;
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
  Vcl.StdCtrls,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.UI.Style.Canvas,
  Atlas.UI.Tracker.ProjectPicker,
  Atlas.UI.Tracker.TileView;

type
  IAtlasIssuesSource = interface
    ['{8D3F6A21-5C4B-4E97-A1D8-2B7E9C05F364}']
    function View: TAtlasIssuesView;
    /// <summary>Der Bereich wird gezeigt: bei Bedarf den Tracker im Hintergrund fragen.</summary>
    procedure Shown;
    /// <summary>„Beginnen“ mit AMode (Branch anlegen oder nur merken).</summary>
    procedure Start(const AIssue: TAtlasTrackerIssue; AMode: TAtlasIssueStart);
    procedure Browse(const AIssue: TAtlasTrackerIssue);
    /// <summary>Issue im Fenster „Atlas-Issue“ zeigen (#1264).</summary>
    procedure Preview(const AIssue: TAtlasTrackerIssue);
    procedure BrowsePullRequest(const AIssue: TAtlasTrackerIssue);
    /// <summary>Tracker jetzt abfragen (ohne auf den Abstand zu warten).</summary>
    procedure QueryNow;
    /// <summary>„Zugang zum Issue-Tracker hinterlegen …“.</summary>
    procedure Credentials;
    /// <summary>Befehl für den Zugang eingeschaltet (Einstellung TrackerLogin).</summary>
    function CanEnterCredentials: Boolean;
    /// <summary>Aktuelles Issue beenden (mit Rückfrage).</summary>
    procedure EndActive;
    /// <summary>„zuordnen …“ (#1261): Seite Issue-Tracker mit einer Zeile für das Projekt öffnen.</summary>
    procedure AssignProject;
    /// <summary>Abfrage AName für das Projekt wählen und gleich abfragen (#1262).</summary>
    procedure SelectQuery(const AName: string);
    /// <summary>„Abfragen bearbeiten …“: Seite Issue-Tracker öffnen.</summary>
    procedure EditQueries;
    /// <summary>Filter der Sprint-Kachel aufheben (#1277): wieder alle meine Issues.</summary>
    procedure ClearFilter;
    /// <summary>Tracker-Projekt wählen (#1927): '' = automatisch, "*" = alle (#1928), sonst
    /// „projekt@verbindung“.</summary>
    procedure SelectProject(const AKey: string);
    /// <summary>„Tracker-Projekte bearbeiten …“: Seite Issue-Tracker öffnen.</summary>
    procedure EditProjects;
  end;

{$SCOPEDENUMS ON}
  TAtlasIssuesHitKind = (None, Row, Key, PullRequest, Start, Assign, Filter);
{$SCOPEDENUMS OFF}

  TAtlasIssuesHit = record
    Kind: TAtlasIssuesHitKind;
    /// <summary>Zeile; -1 sonst.</summary>
    Index: Integer;
    class function Create(AKind: TAtlasIssuesHitKind; AIndex: Integer): TAtlasIssuesHit; static;
  end;

  TAtlasTrackerIssuesView = class;

  /// <summary>Texte und Farben des Bereichs, ohne Steuerelement (auch für die Zustandskachel und Tests).</summary>
  TAtlasTrackerIssuesText = class
  private
    class function ActiveFooter(const AView: TAtlasIssuesView; out AText: string): Boolean; static;
    class function NotConfiguredFooter(const AView: TAtlasIssuesView): string; static;
    /// <summary>Was „Beginnen“ tut; '' ohne Issues.</summary>
    class function StartFooter(const AView: TAtlasIssuesView): string; static;
  public const
    /// <summary>Vor dem Titel des Bereichs, solange ein Issue einen Punkt trägt.</summary>
    cUnseenMark = '● ';
  public
    /// <summary>Zeile über der Liste: Stand, Fehler, „Stand vom …“; '' bei frischem Stand.</summary>
    class function StatusText(const AView: TAtlasIssuesView): string; static;
    /// <summary>„Gefiltert: „Sprint 12“, meine offen · alle zeigen“; '' ohne Filter (#1277).</summary>
    class function FilterText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Fußzeile: Hinweis, sonst aktuelles Issue außerhalb der Liste, sonst was „Beginnen“ tut.</summary>
    class function FooterText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Die Fußzeile ist der Link „zuordnen …“ (#1261): Projekt ohne Tracker, Zuordnen möglich.</summary>
    class function FooterIsAssign(const AView: TAtlasIssuesView): Boolean; static;
    /// <summary>Zeile unter der Fußzeile (#1262): „Firma · KASSE · Abfrage: …“; '' ohne Tracker.</summary>
    class function SourceText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Eintrag der Klappliste: „Name (3)“, ab MaxItems „Name (10+)“, ohne Abfrage nur der Name.</summary>
    class function QueryCaption(const AName: string; ACount: Integer): string; static;
    /// <summary>Klappliste sichtbar: eingeschaltet und Tracker mit Abfragen.</summary>
    class function ShowsQueryPicker(const AView: TAtlasIssuesView): Boolean; static;
    class function ErrorText(AError: TAtlasCiFetchError): string; static;
    /// <summary>Kopf einer Gruppe bei „Alle“ (#1928): „YouTrack · KASSE (7)“.</summary>
    class function GroupCaption(const AGroup: TAtlasIssuesGroup): string; static;
    /// <summary>Rechts im Kopf: „+ N weitere“, wird abgefragt, kein Zugang, Fehler bzw. keine Issues; '' sonst.
    /// </summary>
    class function GroupNote(const AGroup: TAtlasIssuesGroup): string; static;
    /// <summary>„PR #760 · CI grün“, „PR #760 (Entwurf)“; '' ohne Pull Request.</summary>
    class function PullRequestText(const APull: TAtlasTrackerPullRequest): string; static;
    class function ChecksColor(AChecks: TAtlasTrackerChecks): TColor; static;
    /// <summary>Kurztext „ATL-123 · 3 offen“ (Zustandskachel und Statusfeld); ohne aktuelles Issue „3 offen“
    /// mit dem Anbieter.</summary>
    class function TileText(const AView: TAtlasIssuesView): string; static;
    /// <summary>Hinweis auf „Beginnen“: Branch nach Muster bzw. „Merkt … als aktuelles Issue“.</summary>
    class function StartHint(const AView: TAtlasIssuesView; const AIssue: TAtlasTrackerIssue): string; static;
    /// <summary>Hinweis an der Stelle AHit; '' ohne.</summary>
    class function HintAt(const AView: TAtlasIssuesView; const AHit: TAtlasIssuesHit): string; static;
    /// <summary>Titel des Bereichs: „Meine Issues · Projekt“; ohne Projekt „Meine Issues“.</summary>
    class function TitleText(const AProjectName: string): string; overload; static;
    /// <summary>Wie oben, mit Punkt davor, wenn AUnseen (#1271: neue Änderungen an einem Issue).</summary>
    class function TitleText(const AProjectName: string; AUnseen: Boolean): string; overload; static;
  end;

  /// <summary>Zeile der Chips beim Zeichnen: Zeichenfläche, nächste linke Kante, Oberkante, rechte Grenze.</summary>
  TAtlasIssuesChipLine = record
    Canvas: TCanvas;
    Left: Integer;
    Top: Integer;
    Limit: Integer;
  end;

  /// <summary>Raster, Zeichnen und Trefferflächen der Liste.</summary>
  TAtlasTrackerIssuesPainter = class
  private
    FOwner: TAtlasTrackerIssuesView;
    FKeyRects: TArray<TRect>;
    FPullRects: TArray<TRect>;
    FStartRects: TArray<TRect>;
    /// <summary>Link „zuordnen …“ in der Fußzeile; leer ohne.</summary>
    FAssignRect: TRect;
    /// <summary>Zeile „Gefiltert: … · alle zeigen“ (#1277); leer ohne Filter.</summary>
    FFilterRect: TRect;
    function Scaled(AValue: Integer): Integer;
    function Color(ASystemColor: TColor): TColor;
    function TextArea(ATop, AHeight: Integer): TRect;
    function LinkArea(ACanvas: TCanvas; ATop: Integer; const AText: string): TRect;
    function ChipWidth(ACanvas: TCanvas; const AText: string): Integer;
    procedure PaintChip(var ALine: TAtlasIssuesChipLine; const AText: string; AColor: TColor; AFilled: Boolean;
      out ARect: TRect);
    procedure PaintStart(ACanvas: TCanvas; AIndex: Integer; ARight: Integer);
    procedure PaintKey(ACanvas: TCanvas; AIndex, ATop, ALimit: Integer);
    procedure PaintChips(ACanvas: TCanvas; AIndex: Integer; const ALine: TAtlasIssuesChipLine);
    procedure PaintRow(ACanvas: TCanvas; AIndex: Integer);
    procedure PaintStatus(ACanvas: TCanvas);
    procedure PaintFilter(ACanvas: TCanvas);
    procedure PaintSource(ACanvas: TCanvas);
    procedure PaintFooter(ACanvas: TCanvas);
    /// <summary>Kopfzeilen der Gruppen bei „Alle“ (#1928).</summary>
    procedure PaintGroups(ACanvas: TCanvas);
    /// <summary>Kopfzeilen über Zeile AIndex und davor (Gruppen mit First höchstens AIndex).</summary>
    function GroupsAbove(AIndex: Integer): Integer;
    function HitRow(AIndex: Integer; const APoint: TPoint): TAtlasIssuesHit;
  public
    constructor Create(AOwner: TAtlasTrackerIssuesView);
    /// <summary>Trefferflächen für ACount Zeilen leeren.</summary>
    procedure Reset(ACount: Integer);
    procedure Paint(ACanvas: TCanvas);
    function HitTest(AX, AY: Integer): TAtlasIssuesHit;
    /// <summary>Oberkante der Filterzeile bzw. der Liste (unter Stand- und Filterzeile).</summary>
    function FilterTop: Integer;
    function ListTop: Integer;
    function RowTop(AIndex: Integer): Integer;
    function RowHeight(AIndex: Integer): Integer;
    function FooterTop: Integer;
    function SourceTop: Integer;
    /// <summary>Höhe der Liste samt Stand-, Filter-, Fuß- und Quellzeile.</summary>
    function Height: Integer;
  end;

  /// <summary>Kontextmenü der Liste: Im Browser öffnen, Beginnen, Tracker jetzt abfragen und Weiteres.</summary>
  TAtlasTrackerIssuesMenu = class
  private
    FOwner: TAtlasTrackerIssuesView;
    FMenu: TPopupMenu;
    FPreviewItem: TMenuItem;
    FBrowseItem: TMenuItem;
    FBrowsePullItem: TMenuItem;
    FStartBranchItem: TMenuItem;
    FStartRememberItem: TMenuItem;
    FQueryItem: TMenuItem;
    FCredentialsItem: TMenuItem;
    FEndItem: TMenuItem;
    FMenuRow: Integer;
    function AddItem(const ACaption: string; const AClick: TNotifyEvent): TMenuItem;
    function MenuIssue(out AIssue: TAtlasTrackerIssue): Boolean;
    procedure StartFromMenu(AMode: TAtlasIssueStart);
    procedure MenuPopup(Sender: TObject);
    procedure PreviewClick(Sender: TObject);
    procedure BrowseClick(Sender: TObject);
    procedure BrowsePullClick(Sender: TObject);
    procedure StartBranchClick(Sender: TObject);
    procedure StartRememberClick(Sender: TObject);
    procedure QueryClick(Sender: TObject);
    procedure CredentialsClick(Sender: TObject);
    procedure EndClick(Sender: TObject);
  public
    constructor Create(AOwner: TAtlasTrackerIssuesView);
    property Menu: TPopupMenu read FMenu;
    property PreviewItem: TMenuItem read FPreviewItem;
    property BrowseItem: TMenuItem read FBrowseItem;
    property StartRememberItem: TMenuItem read FStartRememberItem;
    property QueryItem: TMenuItem read FQueryItem;
    property CredentialsItem: TMenuItem read FCredentialsItem;
    property EndItem: TMenuItem read FEndItem;
    property MenuRow: Integer read FMenuRow write FMenuRow;
  end;

  /// <summary>Klappliste der Abfragen (#1262) rechts in der ersten Zeile; die Titelzeile gehört der Seite.</summary>
  TAtlasTrackerIssuesQueries = class
  private
    FOwner: TAtlasTrackerIssuesView;
    FBar: TPanel;
    FLabel: TLabel;
    FMenu: TPopupMenu;
    FProjects: TAtlasTrackerProjectPicker;
    procedure LabelClick(Sender: TObject);
    procedure ItemClick(Sender: TObject);
    procedure EditClick(Sender: TObject);
  public
    constructor Create(AOwner: TAtlasTrackerIssuesView);
    destructor Destroy; override;
    /// <summary>Sichtbarkeit und Beschriftung nach dem Stand der Ansicht.</summary>
    procedure Update;
    /// <summary>Klappliste füllen (auch für Tests): passende Abfragen, die gewählte mit Haken, dann
    /// „Abfragen bearbeiten …“.</summary>
    procedure Fill;
    property Bar: TPanel read FBar;
    property QueryLabel: TLabel read FLabel;
    property QueryMenu: TPopupMenu read FMenu;
    /// <summary>Klappliste „Tracker-Projekt“ (#1927) links in derselben Zeile.</summary>
    property Projects: TAtlasTrackerProjectPicker read FProjects;
  end;

  /// <summary>Aktion der Quelle, nach dem eigenen Ereignis ausgeführt.</summary>
  TAtlasIssuesAction = reference to procedure(const ASource: IAtlasIssuesSource);
  TAtlasIssuesItemAction = reference to procedure(const ASource: IAtlasIssuesSource;
    const AIssue: TAtlasTrackerIssue);

  TAtlasTrackerIssuesView = class(TAtlasTrackerTileView)
  public const
    cIndent = 8;
    cKeyWidth = 76;
    cLineHeight = 20;
    cChipLineHeight = 22;
    cRowPadding = 5;
    cStatusHeight = 22;
    cFooterHeight = 24;
    cButtonHeight = 26;
    cButtonPadding = 12;
    cButtonRadius = 6;
    cChipHeight = 18;
    cChipPadding = 6;
    cChipGap = 4;
    cChipRadius = 8;
    /// <summary>Abstand nach Kennung und vor „Beginnen“.</summary>
    cKeyGap = 8;
    /// <summary>Abstand der Fuß- und Quellzeile von ihrer Oberkante.</summary>
    cFooterOffset = 4;
    /// <summary>Durchmesser des Punkts vor der Kennung eines Issues mit neuen Änderungen (#1271).</summary>
    cUnseenDot = 6;
    cMonoFont = 'Consolas';
  private
    FSource: IAtlasIssuesSource;
    FBox: TAtlasStyledCanvas;
    FView: TAtlasIssuesView;
    FPainter: TAtlasTrackerIssuesPainter;
    FMenus: TAtlasTrackerIssuesMenu;
    FQueries: TAtlasTrackerIssuesQueries;
    FHintKey: string;
    procedure SetSource(const AValue: IAtlasIssuesSource);
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; AX, AY: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; AX, AY: Integer);
    procedure ClickIssue(const AHit: TAtlasIssuesHit; ABrowse: Boolean);
    class procedure Post(const AAction: TThreadProcedure); static;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function BodyHeight: Integer; override;
    procedure UpdateContent; override;
    function HitTest(AX, AY: Integer): TAtlasIssuesHit;
    /// <summary>Klick wie mit der Maus (auch für Tests): Kennung und Pull Request öffnen den Browser, „Beginnen“
    /// beginnt mit der Einstellung issues.start.</summary>
    procedure ClickAt(const AHit: TAtlasIssuesHit); overload;
    /// <summary>ABrowse: Strg+Klick, öffnet den Browser auch mit issues.preview.</summary>
    procedure ClickAt(const AHit: TAtlasIssuesHit; ABrowse: Boolean); overload;
    /// <summary>„Beginnen“ nutzbar: Quelle da, keine laufende Aktion.</summary>
    function CanStart: Boolean;
    /// <summary>AAction mit der Quelle nach dem eigenen Ereignis; nichts ohne Quelle.</summary>
    procedure Send(const AAction: TAtlasIssuesAction);
    /// <summary>AAction mit der Quelle und dem Issue der Zeile AIndex.</summary>
    procedure SendIssue(AIndex: Integer; const AAction: TAtlasIssuesItemAction);
    property Source: IAtlasIssuesSource read FSource write SetSource;
    property View: TAtlasIssuesView read FView;
    property PaintBox: TAtlasStyledCanvas read FBox;
    property Painter: TAtlasTrackerIssuesPainter read FPainter;
    property Menus: TAtlasTrackerIssuesMenu read FMenus;
    property Queries: TAtlasTrackerIssuesQueries read FQueries;
  end;

implementation

uses
  System.UITypes,
  System.Math,
  System.DateUtils,
  Vcl.Themes,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.VersionControl.Contract,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Strings;

const
  cSeparator = ' · ';
  cStaleTimeFormat = 'ddddd t';
  cQueryCaptionMore = '%s (%d+)';
  cQueryCaptionCount = '%s (%d)';
  cPullRequestPrefix = 'PR #';
  cMenuLine = '-';
  cHintKeyFormat = '%d:%d';
  /// <summary>Ränder der Klappliste (links, oben, rechts).</summary>
  cQueryMargin = 4;
  cGroupTextOffset = 3;
  cQueryMarginRight = 6;
  // Dieselben Töne wie „Testergebnisse“ und „Projekte“: lesbar im hellen und im dunklen Thema.
  cGreenColor = TColor($0043A02E);
  cYellowColor = TColor($001A8CC9);
  cRedColor = TColor($002E22CF);
  cGrayColor = TColor($00817666);

/// <summary>Teile mit „ · “ verbunden; leere fallen weg.</summary>
function JoinParts(const AParts: TArray<string>): string;
var
  mPart: string;
begin
  Result := '';
  for mPart in AParts do
  begin
    if mPart = '' then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + cSeparator;
    end;
    Result := Result + mPart;
  end;
end;

function Inside(const ARects: TArray<TRect>; AIndex: Integer; const APoint: TPoint): Boolean;
begin
  Result := (AIndex <= High(ARects)) and not ARects[AIndex].IsEmpty and ARects[AIndex].Contains(APoint);
end;

{ TAtlasIssuesHit }

class function TAtlasIssuesHit.Create(AKind: TAtlasIssuesHitKind; AIndex: Integer): TAtlasIssuesHit;
begin
  Result.Kind := AKind;
  Result.Index := AIndex;
end;

{ TAtlasTrackerIssuesText }

class function TAtlasTrackerIssuesText.TitleText(const AProjectName: string): string;
begin
  if AProjectName = '' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesTitle);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesTitleProject, [AProjectName]);
  end;
end;

class function TAtlasTrackerIssuesText.TitleText(const AProjectName: string; AUnseen: Boolean): string;
begin
  Result := TitleText(AProjectName);
  if AUnseen then
  begin
    Result := cUnseenMark + Result;
  end;
end;

class function TAtlasTrackerIssuesText.ErrorText(AError: TAtlasCiFetchError): string;
begin
  case AError of
    TAtlasCiFetchError.Unauthorized:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesUnauthorized);
    TAtlasCiFetchError.NoCredentials:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesNoToken);
    TAtlasCiFetchError.NotFound:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesNotFound);
    TAtlasCiFetchError.Invalid:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesInvalid);
    TAtlasCiFetchError.Timeout:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiTimeout);
    TAtlasCiFetchError.Server:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiServerError);
    TAtlasCiFetchError.UnknownProvider, TAtlasCiFetchError.NotConfigured:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiUnknownProvider);
    TAtlasCiFetchError.None:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiNotQueried);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiUnreachable);
  end;
end;

class function TAtlasTrackerIssuesText.GroupCaption(const AGroup: TAtlasIssuesGroup): string;
begin
  Result := Format(cQueryCaptionCount, [AGroup.Caption, AGroup.Total], TFormatSettings.Invariant);
end;

class function TAtlasTrackerIssuesText.GroupNote(const AGroup: TAtlasIssuesGroup): string;
begin
  Result := '';
  if AGroup.Querying then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuesGroupQuerying);
  end
  else if (AGroup.Status = TAtlasIssuesStatus.NotConfigured) or ((AGroup.Status in [TAtlasIssuesStatus.Failed,
    TAtlasIssuesStatus.Stale]) and (AGroup.Error in [TAtlasCiFetchError.NoCredentials,
    TAtlasCiFetchError.Unauthorized])) then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuesGroupNoAccess);
  end
  else if AGroup.Status in [TAtlasIssuesStatus.Failed, TAtlasIssuesStatus.Stale] then
  begin
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuesGroupFailed, [ErrorText(AGroup.Error)]);
  end
  else if AGroup.Status = TAtlasIssuesStatus.Waiting then
  begin
    Result := ErrorText(TAtlasCiFetchError.None);
  end
  else if AGroup.Total = 0 then
  begin
    Result := TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssuesGroupEmpty);
  end
  else if AGroup.More > 0 then
  begin
    Result := TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuesGroupMore, [AGroup.More]);
  end;
end;

class function TAtlasTrackerIssuesText.StatusText(const AView: TAtlasIssuesView): string;
var
  mParts: TArray<string>;
begin
  mParts := nil;
  case AView.Status of
    TAtlasIssuesStatus.NotConfigured:
      mParts := nil;
    TAtlasIssuesStatus.Waiting:
      if AView.Querying then
      begin
        mParts := [TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQuerying)];
      end
      else
      begin
        mParts := [AView.Tracker, TAtlasStrings.Text(TAtlasTextId.WelcomeTestsCiNotQueried)];
      end;
    TAtlasIssuesStatus.Failed:
      mParts := [AView.Tracker, ErrorText(AView.Error)];
    TAtlasIssuesStatus.Stale:
      mParts := [AView.Tracker, ErrorText(AView.Error), TAtlasStrings.Fmt(TAtlasTextId.WelcomeTestsStale,
        [FormatDateTime(cStaleTimeFormat, TTimeZone.Local.ToLocalTime(AView.At), FormatSettings)])];
  else
    if AView.Querying then
    begin
      mParts := [TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQuerying)];
    end
    else if (Length(AView.Items) = 0) and (Length(AView.Groups) = 0) then
    begin
      mParts := [TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesEmpty)];
    end;
  end;
  if AView.Querying and (AView.Status in [TAtlasIssuesStatus.Failed, TAtlasIssuesStatus.Stale]) then
  begin
    mParts := mParts + [TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQuerying)];
  end;
  Result := JoinParts(mParts);
end;

class function TAtlasTrackerIssuesText.NotConfiguredFooter(const AView: TAtlasIssuesView): string;
begin
  if AView.Project = '' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesNoProject);
  end
  else if FooterIsAssign(AView) then
  begin
    // Weder .atlas noch persönliche Zuordnung: gleich zuordnen lassen (#1261).
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesAssign);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesNotConfigured);
  end;
end;

class function TAtlasTrackerIssuesText.ActiveFooter(const AView: TAtlasIssuesView; out AText: string): Boolean;
var
  mItem: TAtlasTrackerIssue;
begin
  // Aktuelles Issue, das die Liste nicht zeigt (z. B. schon geschlossen oder anderer Bearbeiter).
  AText := '';
  Result := AView.Active.Active;
  for mItem in AView.Items do
  begin
    Result := Result and not SameText(mItem.Key, AView.Active.Key);
  end;
  if Result then
  begin
    AText := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesActiveFooter,
      [Trim(AView.Active.Key + ' ' + AView.Active.Title)]);
  end;
end;

class function TAtlasTrackerIssuesText.FooterText(const AView: TAtlasIssuesView): string;
begin
  if AView.Notice <> '' then
  begin
    Result := AView.Notice;
  end
  else if AView.Status = TAtlasIssuesStatus.NotConfigured then
  begin
    Result := NotConfiguredFooter(AView);
  end
  else if not ActiveFooter(AView, Result) then
  begin
    Result := StartFooter(AView);
  end;
end;

class function TAtlasTrackerIssuesText.StartFooter(const AView: TAtlasIssuesView): string;
begin
  if Length(AView.Items) = 0 then
  begin
    Result := '';
  end
  else if (AView.Options.Start = TAtlasIssueStart.Remember) or
    ((AView.VcsKind <> TAtlasVcsKind.Git) and (AView.VcsKind <> TAtlasVcsKind.Svn)) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesFooterRemember);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesFooter);
  end;
end;

class function TAtlasTrackerIssuesText.FooterIsAssign(const AView: TAtlasIssuesView): Boolean;
begin
  Result := (AView.Notice = '') and (AView.Status = TAtlasIssuesStatus.NotConfigured) and (AView.Project <> '') and
    AView.CanAssign;
end;

class function TAtlasTrackerIssuesText.SourceText(const AView: TAtlasIssuesView): string;
begin
  Result := '';
  if (AView.Status <> TAtlasIssuesStatus.NotConfigured) and (AView.QueryText <> '') then
  begin
    Result := JoinParts([AView.Connection, AView.TrackerProject,
      TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesSource, [AView.QueryText])]);
  end;
end;

class function TAtlasTrackerIssuesText.QueryCaption(const AName: string; ACount: Integer): string;
begin
  if ACount < 0 then
  begin
    Result := AName;
  end
  else if ACount >= TAtlasMyIssues.cMaxItems then
  begin
    Result := Format(cQueryCaptionMore, [AName, TAtlasMyIssues.cMaxItems], TFormatSettings.Invariant);
  end
  else
  begin
    Result := Format(cQueryCaptionCount, [AName, ACount], TFormatSettings.Invariant);
  end;
end;

class function TAtlasTrackerIssuesText.ShowsQueryPicker(const AView: TAtlasIssuesView): Boolean;
begin
  Result := AView.Picker and (AView.Status <> TAtlasIssuesStatus.NotConfigured) and (AView.QueryIndex >= 0) and
    (AView.QueryIndex <= High(AView.Queries));
end;

class function TAtlasTrackerIssuesText.PullRequestText(const APull: TAtlasTrackerPullRequest): string;
begin
  Result := '';
  if APull.Number <= 0 then
  begin
    Exit;
  end;
  Result := cPullRequestPrefix + IntToStr(APull.Number);
  if APull.Draft then
  begin
    Result := Result + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesDraft);
  end;
  case APull.Checks of
    TAtlasTrackerChecks.Success:
      Result := Result + cSeparator + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesChecksSuccess);
    TAtlasTrackerChecks.Failure:
      Result := Result + cSeparator + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesChecksFailure);
    TAtlasTrackerChecks.Pending:
      Result := Result + cSeparator + TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesChecksPending);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TAtlasTrackerIssuesText.ChecksColor(AChecks: TAtlasTrackerChecks): TColor;
begin
  case AChecks of
    TAtlasTrackerChecks.Success:
      Result := cGreenColor;
    TAtlasTrackerChecks.Failure:
      Result := cRedColor;
    TAtlasTrackerChecks.Pending:
      Result := cYellowColor;
  else
    Result := cGrayColor;
  end;
end;

class function TAtlasTrackerIssuesText.TileText(const AView: TAtlasIssuesView): string;
var
  mHead: string;
begin
  mHead := AView.Active.Key;
  if mHead = '' then
  begin
    mHead := AView.Tracker;
  end;
  if mHead = '' then
  begin
    mHead := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesTitle);
  end;
  Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesStatusTile, [mHead, AView.OpenCount]);
end;

class function TAtlasTrackerIssuesText.StartHint(const AView: TAtlasIssuesView;
  const AIssue: TAtlasTrackerIssue): string;
var
  mPlan: TAtlasIssueStartPlan;
begin
  mPlan := TAtlasMyIssues.PlanStart(AView.VcsKind, AView.Options, AIssue);
  if (mPlan.Mode = TAtlasIssueStart.Branch) and mPlan.Valid then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesHintStart, [mPlan.Branch]);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesHintRemember, [AIssue.Key]);
  end;
end;

class function TAtlasTrackerIssuesText.HintAt(const AView: TAtlasIssuesView; const AHit: TAtlasIssuesHit): string;
begin
  case AHit.Kind of
    TAtlasIssuesHitKind.Key:
      if AView.Options.Preview then
      begin
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintKeyPreview);
      end
      else
      begin
        Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintKey);
      end;
    TAtlasIssuesHitKind.PullRequest:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintPullRequest);
    TAtlasIssuesHitKind.Start:
      Result := StartHint(AView, AView.Items[AHit.Index]);
    TAtlasIssuesHitKind.Row:
      begin
        Result := AView.Items[AHit.Index].Key + ' ' + AView.Items[AHit.Index].Title;
        if AView.IsUnseen(AView.Items[AHit.Index].Key) then
        begin
          Result := Result + sLineBreak + TAtlasStrings.Text(TAtlasTextId.IssueNotifyUnseenHint);
        end;
      end;
    TAtlasIssuesHitKind.Assign:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintAssign);
    TAtlasIssuesHitKind.Filter:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesHintFilter);
  else
    Result := '';
  end;
end;

class function TAtlasTrackerIssuesText.FilterText(const AView: TAtlasIssuesView): string;
begin
  Result := '';
  if AView.Filter <> '' then
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeIssuesFilter, [AView.Filter]);
  end;
end;

{ TAtlasTrackerIssuesPainter }

constructor TAtlasTrackerIssuesPainter.Create(AOwner: TAtlasTrackerIssuesView);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TAtlasTrackerIssuesPainter.Reset(ACount: Integer);
begin
  FKeyRects := nil;
  FPullRects := nil;
  FStartRects := nil;
  FAssignRect := TRect.Empty;
  FFilterRect := TRect.Empty;
  SetLength(FKeyRects, ACount);
  SetLength(FPullRects, ACount);
  SetLength(FStartRects, ACount);
end;

function TAtlasTrackerIssuesPainter.Scaled(AValue: Integer): Integer;
begin
  Result := FOwner.ScaleValue(AValue);
end;

function TAtlasTrackerIssuesPainter.Color(ASystemColor: TColor): TColor;
begin
  Result := StyleServices(FOwner).GetSystemColor(ASystemColor);
end;

function TAtlasTrackerIssuesPainter.TextArea(ATop, AHeight: Integer): TRect;
begin
  Result := Rect(Scaled(TAtlasTrackerIssuesView.cIndent), ATop,
    FOwner.PaintBox.Width - Scaled(TAtlasTrackerIssuesView.cIndent), ATop + AHeight);
end;

function TAtlasTrackerIssuesPainter.LinkArea(ACanvas: TCanvas; ATop: Integer; const AText: string): TRect;
var
  mLeft: Integer;
begin
  mLeft := Scaled(TAtlasTrackerIssuesView.cIndent);
  Result := Rect(mLeft, ATop, Min(mLeft + ACanvas.TextWidth(AText), FOwner.PaintBox.Width - mLeft),
    ATop + ACanvas.TextHeight(AText));
end;

function TAtlasTrackerIssuesPainter.FilterTop: Integer;
begin
  Result := Scaled(TAtlasTrackerIssuesView.cIndent) div 2;
  if TAtlasTrackerIssuesText.StatusText(FOwner.View) <> '' then
  begin
    Inc(Result, Scaled(TAtlasTrackerIssuesView.cStatusHeight));
  end;
end;

function TAtlasTrackerIssuesPainter.ListTop: Integer;
begin
  Result := FilterTop;
  if TAtlasTrackerIssuesText.FilterText(FOwner.View) <> '' then
  begin
    Inc(Result, Scaled(TAtlasTrackerIssuesView.cStatusHeight));
  end;
end;

function TAtlasTrackerIssuesPainter.RowHeight(AIndex: Integer): Integer;
var
  mItem: TAtlasTrackerIssue;
begin
  Result := 2 * Scaled(TAtlasTrackerIssuesView.cRowPadding) + Scaled(TAtlasTrackerIssuesView.cLineHeight);
  if (AIndex >= 0) and (AIndex <= High(FOwner.View.Items)) then
  begin
    mItem := FOwner.View.Items[AIndex];
    if (Length(TAtlasMyIssues.Fields(mItem)) > 0) or (mItem.PullRequest.Number > 0) or
      SameText(mItem.Key, FOwner.View.Active.Key) then
    begin
      Inc(Result, Scaled(TAtlasTrackerIssuesView.cChipLineHeight));
    end;
  end;
end;

function TAtlasTrackerIssuesPainter.GroupsAbove(AIndex: Integer): Integer;
var
  mGroup: TAtlasIssuesGroup;
begin
  Result := 0;
  for mGroup in FOwner.View.Groups do
  begin
    if mGroup.First <= AIndex then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasTrackerIssuesPainter.RowTop(AIndex: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := ListTop + GroupsAbove(AIndex) * Scaled(TAtlasTrackerIssuesView.cStatusHeight);
  for mIndex := 0 to AIndex - 1 do
  begin
    Inc(Result, RowHeight(mIndex));
  end;
end;

function TAtlasTrackerIssuesPainter.FooterTop: Integer;
begin
  Result := RowTop(Length(FOwner.View.Items));
end;

function TAtlasTrackerIssuesPainter.SourceTop: Integer;
begin
  Result := FooterTop + Scaled(TAtlasTrackerIssuesView.cFooterHeight);
end;

function TAtlasTrackerIssuesPainter.Height: Integer;
begin
  Result := SourceTop + Scaled(TAtlasTrackerIssuesView.cIndent) div 2;
  if TAtlasTrackerIssuesText.SourceText(FOwner.View) <> '' then
  begin
    Inc(Result, Scaled(TAtlasTrackerIssuesView.cFooterHeight));
  end;
end;

function TAtlasTrackerIssuesPainter.ChipWidth(ACanvas: TCanvas; const AText: string): Integer;
begin
  Result := ACanvas.TextWidth(AText) + 2 * Scaled(TAtlasTrackerIssuesView.cChipPadding);
end;

procedure TAtlasTrackerIssuesPainter.PaintChip(var ALine: TAtlasIssuesChipLine; const AText: string;
  AColor: TColor; AFilled: Boolean; out ARect: TRect);
var
  mCanvas: TCanvas;
  mWidth, mRadius: Integer;
begin
  ARect := TRect.Empty;
  mCanvas := ALine.Canvas;
  mWidth := ChipWidth(mCanvas, AText);
  if ALine.Left + mWidth > ALine.Limit then
  begin
    Exit;
  end;
  ARect := Rect(ALine.Left, ALine.Top, ALine.Left + mWidth, ALine.Top + Scaled(TAtlasTrackerIssuesView.cChipHeight));
  mRadius := 2 * Scaled(TAtlasTrackerIssuesView.cChipRadius);
  mCanvas.Pen.Color := AColor;
  mCanvas.Brush.Style := bsClear;
  mCanvas.Font.Color := AColor;
  if AFilled then
  begin
    mCanvas.Brush.Style := bsSolid;
    mCanvas.Brush.Color := AColor;
    mCanvas.Font.Color := clWhite;
  end;
  mCanvas.RoundRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, mRadius, mRadius);
  mCanvas.Brush.Style := bsClear;
  mCanvas.TextOut(ARect.Left + Scaled(TAtlasTrackerIssuesView.cChipPadding),
    ARect.Top + (ARect.Height - mCanvas.TextHeight(AText)) div 2, AText);
  ALine.Left := ARect.Right + Scaled(TAtlasTrackerIssuesView.cChipGap);
end;

procedure TAtlasTrackerIssuesPainter.PaintStart(ACanvas: TCanvas; AIndex: Integer; ARight: Integer);
var
  mText: string;
  mArea: TRect;
  mTop, mWidth, mHeight, mRadius: Integer;
begin
  ACanvas.Font.Assign(FOwner.Font);
  mText := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesStart);
  mWidth := ACanvas.TextWidth(mText) + 2 * Scaled(TAtlasTrackerIssuesView.cButtonPadding);
  mHeight := Scaled(TAtlasTrackerIssuesView.cButtonHeight);
  // Über beide Zeilen der Zeile mittig (Mockup).
  mTop := RowTop(AIndex) + (RowHeight(AIndex) - mHeight) div 2;
  mArea := Rect(ARight - mWidth, mTop, ARight, mTop + mHeight);
  FStartRects[AIndex] := mArea;
  mRadius := Scaled(TAtlasTrackerIssuesView.cButtonRadius);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := Color(clBtnShadow);
  ACanvas.RoundRect(mArea.Left, mArea.Top, mArea.Right, mArea.Bottom, mRadius, mRadius);
  if FOwner.CanStart then
  begin
    ACanvas.Font.Color := Color(clWindowText);
  end
  else
  begin
    ACanvas.Font.Color := Color(clGrayText);
  end;
  ACanvas.TextOut(mArea.Left + (mArea.Width - ACanvas.TextWidth(mText)) div 2,
    mArea.Top + (mArea.Height - ACanvas.TextHeight(mText)) div 2, mText);
end;

procedure TAtlasTrackerIssuesPainter.PaintKey(ACanvas: TCanvas; AIndex, ATop, ALimit: Integer);
var
  mKey: string;
  mLeft, mDot, mLine: Integer;
begin
  // Kennung grau in Festbreitenschrift.
  mKey := FOwner.View.Items[AIndex].Key;
  mLeft := Scaled(TAtlasTrackerIssuesView.cIndent);
  mLine := Scaled(TAtlasTrackerIssuesView.cLineHeight);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Assign(FOwner.Font);
  ACanvas.Font.Name := TAtlasTrackerIssuesView.cMonoFont;
  ACanvas.Font.Color := Color(clGrayText);
  FKeyRects[AIndex] := Rect(mLeft, ATop, Min(mLeft + ACanvas.TextWidth(mKey), ALimit), ATop + mLine);
  ACanvas.TextRect(FKeyRects[AIndex], mLeft, ATop + Scaled(1), mKey);
  // Neue Änderungen seit dem letzten Öffnen (#1271): Punkt im Rand vor der Kennung.
  if FOwner.View.IsUnseen(mKey) then
  begin
    mDot := Scaled(TAtlasTrackerIssuesView.cUnseenDot);
    ACanvas.Brush.Style := bsSolid;
    ACanvas.Brush.Color := Color(clHighlight);
    ACanvas.Pen.Color := ACanvas.Brush.Color;
    ACanvas.Ellipse(Rect((mLeft - mDot) div 2, ATop + (mLine - mDot) div 2, (mLeft + mDot) div 2,
      ATop + (mLine + mDot) div 2));
    ACanvas.Brush.Style := bsClear;
  end;
end;

procedure TAtlasTrackerIssuesPainter.PaintChips(ACanvas: TCanvas; AIndex: Integer;
  const ALine: TAtlasIssuesChipLine);
var
  mItem: TAtlasTrackerIssue;
  mLine: TAtlasIssuesChipLine;
  mField, mText: string;
  mChip: TRect;
begin
  // Zweite Zeile: Felder als Chips mit Rahmen, dann der Pull Request mit CI-Ampel.
  mItem := FOwner.View.Items[AIndex];
  mLine := ALine;
  ACanvas.Font.Size := FOwner.Font.Size - 1;
  FPullRects[AIndex] := TRect.Empty;
  if SameText(mItem.Key, FOwner.View.Active.Key) then
  begin
    PaintChip(mLine, TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesActive), Color(clHighlight), True, mChip);
  end;
  for mField in TAtlasMyIssues.Fields(mItem) do
  begin
    PaintChip(mLine, mField, Color(clGrayText), False, mChip);
  end;
  mText := TAtlasTrackerIssuesText.PullRequestText(mItem.PullRequest);
  if mText <> '' then
  begin
    PaintChip(mLine, mText, TAtlasTrackerIssuesText.ChecksColor(mItem.PullRequest.Checks), False, mChip);
    FPullRects[AIndex] := mChip;
  end;
  ACanvas.Font.Assign(FOwner.Font);
end;

procedure TAtlasTrackerIssuesPainter.PaintRow(ACanvas: TCanvas; AIndex: Integer);
var
  mItem: TAtlasTrackerIssue;
  mTop, mLeft, mLimit, mRight, mLine: Integer;
  mChips: TAtlasIssuesChipLine;
begin
  mItem := FOwner.View.Items[AIndex];
  mTop := RowTop(AIndex);
  mLeft := Scaled(TAtlasTrackerIssuesView.cIndent);
  mRight := FOwner.PaintBox.Width - mLeft;
  mLine := Scaled(TAtlasTrackerIssuesView.cLineHeight);
  // Trennlinie zwischen den Zeilen (Mockup).
  if AIndex > 0 then
  begin
    ACanvas.Pen.Color := Color(clBtnFace);
    ACanvas.MoveTo(mLeft, mTop);
    ACanvas.LineTo(mRight, mTop);
  end;
  PaintStart(ACanvas, AIndex, mRight);
  mLimit := FStartRects[AIndex].Left - Scaled(TAtlasTrackerIssuesView.cKeyGap);
  Inc(mTop, Scaled(TAtlasTrackerIssuesView.cRowPadding));
  PaintKey(ACanvas, AIndex, mTop, mLimit);
  mLeft := mLeft + Max(Scaled(TAtlasTrackerIssuesView.cKeyWidth),
    ACanvas.TextWidth(mItem.Key) + Scaled(TAtlasTrackerIssuesView.cKeyGap));
  // Titel, abgeschnitten.
  ACanvas.Font.Assign(FOwner.Font);
  ACanvas.Font.Color := Color(clWindowText);
  if SameText(mItem.Key, FOwner.View.Active.Key) then
  begin
    ACanvas.Font.Style := [fsBold];
  end;
  if mLeft < mLimit then
  begin
    ACanvas.TextRect(Rect(mLeft, mTop, mLimit, mTop + mLine), mLeft, mTop + Scaled(1), mItem.Title);
  end;
  ACanvas.Font.Style := [];
  mChips.Canvas := ACanvas;
  mChips.Left := mLeft;
  mChips.Top := mTop + mLine + (Scaled(TAtlasTrackerIssuesView.cChipLineHeight) -
    Scaled(TAtlasTrackerIssuesView.cChipHeight)) div 2;
  mChips.Limit := mLimit;
  PaintChips(ACanvas, AIndex, mChips);
end;

procedure TAtlasTrackerIssuesPainter.PaintStatus(ACanvas: TCanvas);
var
  mText: string;
  mTop: Integer;
begin
  mText := TAtlasTrackerIssuesText.StatusText(FOwner.View);
  if mText = '' then
  begin
    Exit;
  end;
  ACanvas.Font.Size := FOwner.Font.Size - 1;
  if FOwner.View.Status in [TAtlasIssuesStatus.Failed, TAtlasIssuesStatus.Stale] then
  begin
    ACanvas.Font.Color := cYellowColor;
  end
  else
  begin
    ACanvas.Font.Color := Color(clGrayText);
  end;
  mTop := Scaled(TAtlasTrackerIssuesView.cIndent) div 2;
  ACanvas.TextRect(TextArea(mTop, Scaled(TAtlasTrackerIssuesView.cStatusHeight)),
    Scaled(TAtlasTrackerIssuesView.cIndent), mTop + Scaled(2), mText);
  ACanvas.Font.Assign(FOwner.Font);
end;

procedure TAtlasTrackerIssuesPainter.PaintGroups(ACanvas: TCanvas);
var
  mIndex, mTop, mHeight, mRow: Integer;
  mGroup: TAtlasIssuesGroup;
  mArea: TRect;
  mNote: string;
begin
  mHeight := Scaled(TAtlasTrackerIssuesView.cStatusHeight);
  for mIndex := 0 to High(FOwner.View.Groups) do
  begin
    mGroup := FOwner.View.Groups[mIndex];
    // Über der ersten Zeile der Gruppe, unter den Köpfen davor.
    mTop := ListTop + mIndex * mHeight;
    for mRow := 0 to mGroup.First - 1 do
    begin
      Inc(mTop, RowHeight(mRow));
    end;
    mArea := TextArea(mTop, mHeight);
    ACanvas.Font.Assign(FOwner.Font);
    ACanvas.Font.Size := FOwner.Font.Size - 1;
    ACanvas.Font.Style := [fsBold];
    ACanvas.Font.Color := Color(clGrayText);
    ACanvas.TextRect(mArea, mArea.Left, mTop + Scaled(cGroupTextOffset),
      TAtlasTrackerIssuesText.GroupCaption(mGroup));
    mNote := TAtlasTrackerIssuesText.GroupNote(mGroup);
    ACanvas.Font.Style := [];
    if mNote <> '' then
    begin
      if mGroup.Status in [TAtlasIssuesStatus.Failed, TAtlasIssuesStatus.Stale, TAtlasIssuesStatus.NotConfigured] then
      begin
        ACanvas.Font.Color := cYellowColor;
      end;
      ACanvas.TextOut(Max(mArea.Left, mArea.Right - ACanvas.TextWidth(mNote)), mTop + Scaled(cGroupTextOffset),
        mNote);
    end;
  end;
  ACanvas.Font.Assign(FOwner.Font);
end;

procedure TAtlasTrackerIssuesPainter.PaintFilter(ACanvas: TCanvas);
var
  mText: string;
  mTop: Integer;
begin
  // Filter der Sprint-Kachel (#1277): Link, der ihn aufhebt.
  FFilterRect := TRect.Empty;
  mText := TAtlasTrackerIssuesText.FilterText(FOwner.View);
  if mText = '' then
  begin
    Exit;
  end;
  mTop := FilterTop + Scaled(2);
  ACanvas.Font.Size := FOwner.Font.Size - 1;
  ACanvas.Font.Color := Color(clHotLight);
  FFilterRect := LinkArea(ACanvas, mTop, mText);
  ACanvas.TextRect(TextArea(mTop, Scaled(TAtlasTrackerIssuesView.cStatusHeight)),
    Scaled(TAtlasTrackerIssuesView.cIndent), mTop, mText);
  ACanvas.Font.Assign(FOwner.Font);
end;

procedure TAtlasTrackerIssuesPainter.PaintSource(ACanvas: TCanvas);
var
  mText: string;
  mTop: Integer;
begin
  // Woher die Liste kommt (#1262): Verbindung, Tracker-Projekt, gesendete Abfrage.
  mText := TAtlasTrackerIssuesText.SourceText(FOwner.View);
  if mText = '' then
  begin
    Exit;
  end;
  mTop := SourceTop + Scaled(TAtlasTrackerIssuesView.cFooterOffset);
  ACanvas.Font.Size := FOwner.Font.Size - 1;
  ACanvas.Font.Color := Color(clGrayText);
  ACanvas.TextRect(TextArea(mTop, Scaled(TAtlasTrackerIssuesView.cFooterHeight)),
    Scaled(TAtlasTrackerIssuesView.cIndent), mTop, mText);
  ACanvas.Font.Assign(FOwner.Font);
end;

procedure TAtlasTrackerIssuesPainter.PaintFooter(ACanvas: TCanvas);
var
  mText: string;
  mTop: Integer;
begin
  mText := TAtlasTrackerIssuesText.FooterText(FOwner.View);
  if mText = '' then
  begin
    Exit;
  end;
  mTop := FooterTop + Scaled(TAtlasTrackerIssuesView.cFooterOffset);
  ACanvas.Font.Assign(FOwner.Font);
  ACanvas.Font.Size := FOwner.Font.Size - 1;
  if FOwner.View.NoticeFailed then
  begin
    ACanvas.Font.Color := cRedColor;
  end
  else if TAtlasTrackerIssuesText.FooterIsAssign(FOwner.View) then
  begin
    // Link „zuordnen …“: Akzentfarbe, Klickfläche nur über dem Text.
    ACanvas.Font.Color := Color(clHotLight);
    FAssignRect := LinkArea(ACanvas, mTop, mText);
  end
  else
  begin
    ACanvas.Font.Color := Color(clGrayText);
  end;
  ACanvas.TextRect(TextArea(mTop, Scaled(TAtlasTrackerIssuesView.cFooterHeight)),
    Scaled(TAtlasTrackerIssuesView.cIndent), mTop, mText);
  ACanvas.Font.Assign(FOwner.Font);
end;

procedure TAtlasTrackerIssuesPainter.Paint(ACanvas: TCanvas);
var
  mIndex: Integer;
begin
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Assign(FOwner.Font);
  PaintStatus(ACanvas);
  PaintFilter(ACanvas);
  if Length(FStartRects) = Length(FOwner.View.Items) then
  begin
    for mIndex := 0 to High(FOwner.View.Items) do
    begin
      PaintRow(ACanvas, mIndex);
    end;
    PaintGroups(ACanvas);
    PaintSource(ACanvas);
    PaintFooter(ACanvas);
  end;
end;

function TAtlasTrackerIssuesPainter.HitRow(AIndex: Integer; const APoint: TPoint): TAtlasIssuesHit;
begin
  if Inside(FStartRects, AIndex, APoint) then
  begin
    Result := TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Start, AIndex);
  end
  else if Inside(FKeyRects, AIndex, APoint) then
  begin
    Result := TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Key, AIndex);
  end
  else if Inside(FPullRects, AIndex, APoint) then
  begin
    Result := TAtlasIssuesHit.Create(TAtlasIssuesHitKind.PullRequest, AIndex);
  end
  else
  begin
    Result := TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Row, AIndex);
  end;
end;

function TAtlasTrackerIssuesPainter.HitTest(AX, AY: Integer): TAtlasIssuesHit;
var
  mIndex, mTop: Integer;
  mPoint: TPoint;
begin
  Result := TAtlasIssuesHit.Create(TAtlasIssuesHitKind.None, -1);
  mPoint := Point(AX, AY);
  if not FAssignRect.IsEmpty and FAssignRect.Contains(mPoint) then
  begin
    Result := TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Assign, -1);
  end
  else if not FFilterRect.IsEmpty and FFilterRect.Contains(mPoint) then
  begin
    Result := TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Filter, -1);
  end
  else
  begin
    for mIndex := 0 to High(FOwner.View.Items) do
    begin
      // RowTop zählt die Köpfe der Gruppen (#1928) mit.
      mTop := RowTop(mIndex);
      if (Result.Kind = TAtlasIssuesHitKind.None) and (AY >= mTop) and (AY < mTop + RowHeight(mIndex)) then
      begin
        Result := HitRow(mIndex, mPoint);
      end;
    end;
  end;
end;

{ TAtlasTrackerIssuesMenu }

constructor TAtlasTrackerIssuesMenu.Create(AOwner: TAtlasTrackerIssuesView);
var
  mLine: TMenuItem;
begin
  inherited Create;
  FOwner := AOwner;
  FMenuRow := -1;
  FMenu := TPopupMenu.Create(AOwner);
  FMenu.OnPopup := MenuPopup;
  FPreviewItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesPreview), PreviewClick);
  FBrowseItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesBrowse), BrowseClick);
  FBrowsePullItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesBrowsePullRequest), BrowsePullClick);
  FStartBranchItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesStartBranch), StartBranchClick);
  FStartRememberItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesStartRemember), StartRememberClick);
  mLine := TMenuItem.Create(AOwner);
  mLine.Caption := cMenuLine;
  FMenu.Items.Add(mLine);
  FQueryItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQueryNow), QueryClick);
  FCredentialsItem := AddItem(TAtlasStrings.Text(TAtlasTextId.TrackerLoginCommand), CredentialsClick);
  FEndItem := AddItem(TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesEnd), EndClick);
end;

function TAtlasTrackerIssuesMenu.AddItem(const ACaption: string; const AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FOwner);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  FMenu.Items.Add(Result);
end;

procedure TAtlasTrackerIssuesMenu.MenuPopup(Sender: TObject);
var
  mPosition: TPoint;
  mView: TAtlasIssuesView;
  mItem: TAtlasTrackerIssue;
  mHasItem, mBranching, mConfigured: Boolean;
begin
  mPosition := FOwner.PaintBox.ScreenToClient(FMenu.PopupPoint);
  FMenuRow := FOwner.HitTest(mPosition.X, mPosition.Y).Index;
  mView := FOwner.View;
  mHasItem := MenuIssue(mItem);
  mBranching := (mView.VcsKind = TAtlasVcsKind.Git) or (mView.VcsKind = TAtlasVcsKind.Svn);
  mConfigured := mView.Status <> TAtlasIssuesStatus.NotConfigured;
  FPreviewItem.Visible := mHasItem and mView.Options.Preview;
  FPreviewItem.Default := FPreviewItem.Visible;
  FBrowseItem.Visible := mHasItem;
  FBrowsePullItem.Visible := mHasItem and (mItem.PullRequest.Number > 0);
  FStartBranchItem.Visible := mHasItem and mBranching;
  FStartBranchItem.Enabled := FOwner.CanStart;
  FStartRememberItem.Visible := mHasItem;
  FStartRememberItem.Enabled := FOwner.CanStart;
  FQueryItem.Visible := mConfigured;
  FQueryItem.Enabled := not mView.Querying;
  FCredentialsItem.Visible := mConfigured and (FOwner.Source <> nil) and FOwner.Source.CanEnterCredentials;
  FEndItem.Visible := mView.Active.Active;
end;

function TAtlasTrackerIssuesMenu.MenuIssue(out AIssue: TAtlasTrackerIssue): Boolean;
begin
  AIssue := TAtlasTrackerIssue.Empty;
  Result := (FOwner.Source <> nil) and (FMenuRow >= 0) and (FMenuRow <= High(FOwner.View.Items));
  if Result then
  begin
    AIssue := FOwner.View.Items[FMenuRow];
  end;
end;

procedure TAtlasTrackerIssuesMenu.StartFromMenu(AMode: TAtlasIssueStart);
var
  mItem: TAtlasTrackerIssue;
  mMode: TAtlasIssueStart;
begin
  if FOwner.CanStart and MenuIssue(mItem) then
  begin
    mMode := AMode;
    FOwner.SendIssue(FMenuRow,
      procedure(const ASource: IAtlasIssuesSource; const AIssue: TAtlasTrackerIssue)
      begin
        ASource.Start(AIssue, mMode);
      end);
  end;
end;

procedure TAtlasTrackerIssuesMenu.PreviewClick(Sender: TObject);
begin
  FOwner.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Row, FMenuRow), False);
end;

procedure TAtlasTrackerIssuesMenu.BrowseClick(Sender: TObject);
begin
  FOwner.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.Key, FMenuRow), True);
end;

procedure TAtlasTrackerIssuesMenu.BrowsePullClick(Sender: TObject);
begin
  FOwner.ClickAt(TAtlasIssuesHit.Create(TAtlasIssuesHitKind.PullRequest, FMenuRow));
end;

procedure TAtlasTrackerIssuesMenu.StartBranchClick(Sender: TObject);
begin
  StartFromMenu(TAtlasIssueStart.Branch);
end;

procedure TAtlasTrackerIssuesMenu.StartRememberClick(Sender: TObject);
begin
  StartFromMenu(TAtlasIssueStart.Remember);
end;

procedure TAtlasTrackerIssuesMenu.QueryClick(Sender: TObject);
begin
  FOwner.Send(
    procedure(const ASource: IAtlasIssuesSource)
    begin
      ASource.QueryNow;
    end);
end;

procedure TAtlasTrackerIssuesMenu.CredentialsClick(Sender: TObject);
begin
  FOwner.Send(
    procedure(const ASource: IAtlasIssuesSource)
    begin
      ASource.Credentials;
    end);
end;

procedure TAtlasTrackerIssuesMenu.EndClick(Sender: TObject);
begin
  FOwner.Send(
    procedure(const ASource: IAtlasIssuesSource)
    begin
      ASource.EndActive;
    end);
end;

{ TAtlasTrackerIssuesQueries }

constructor TAtlasTrackerIssuesQueries.Create(AOwner: TAtlasTrackerIssuesView);
begin
  inherited Create;
  FOwner := AOwner;
  // Über der Liste, nur bei Bedarf sichtbar.
  FBar := TPanel.Create(AOwner);
  FBar.Parent := AOwner;
  FBar.Align := alTop;
  FBar.BevelOuter := bvNone;
  FBar.ShowCaption := False;
  FBar.ParentBackground := True;
  FBar.Height := AOwner.ScaleValue(TAtlasTrackerIssuesView.cStatusHeight);
  FBar.Visible := False;
  FMenu := TPopupMenu.Create(AOwner);
  FLabel := TLabel.Create(AOwner);
  FLabel.Parent := FBar;
  FLabel.Align := alRight;
  FLabel.AlignWithMargins := True;
  FLabel.Margins.SetBounds(cQueryMargin, cQueryMargin, cQueryMarginRight, 0);
  FLabel.Cursor := crHandPoint;
  FLabel.ShowHint := True;
  FLabel.Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQueryHint);
  FLabel.Font.Color := clHotLight;
  FLabel.Visible := False;
  FLabel.OnClick := LabelClick;
  FProjects := TAtlasTrackerProjectPicker.Create(AOwner, FBar,
    procedure(AKey: string)
    begin
      FOwner.Send(
        procedure(const ASource: IAtlasIssuesSource)
        begin
          ASource.SelectProject(AKey);
        end);
    end,
    procedure
    begin
      FOwner.Send(
        procedure(const ASource: IAtlasIssuesSource)
        begin
          ASource.EditProjects;
        end);
    end);
end;

destructor TAtlasTrackerIssuesQueries.Destroy;
begin
  // Beschriftung und Menü gehören der Ansicht (Owner).
  FProjects.Free;
  inherited Destroy;
end;

procedure TAtlasTrackerIssuesQueries.Update;
var
  mView: TAtlasIssuesView;
  mCount: Integer;
begin
  mView := FOwner.View;
  FLabel.Visible := TAtlasTrackerIssuesText.ShowsQueryPicker(mView);
  FProjects.Update(mView, FOwner.HasWindow);
  FBar.Visible := FLabel.Visible or FProjects.Visible;
  // Die Beschriftung misst ihren Text: erst mit Fenster (CreateWnd holt UpdateContent nach).
  if FLabel.Visible and FOwner.HasWindow then
  begin
    mCount := -1;
    if mView.QueryIndex <= High(mView.QueryCounts) then
    begin
      mCount := mView.QueryCounts[mView.QueryIndex];
    end;
    FLabel.Caption := TAtlasTrackerIssuesText.QueryCaption(mView.Queries[mView.QueryIndex].Name, mCount) + ' ' +
      #$25BE;
  end;
end;

procedure TAtlasTrackerIssuesQueries.Fill;
var
  mView: TAtlasIssuesView;
  mIndex, mCount: Integer;
  mItem: TMenuItem;
begin
  mView := FOwner.View;
  FMenu.Items.Clear;
  for mIndex := 0 to High(mView.Queries) do
  begin
    mCount := -1;
    if mIndex <= High(mView.QueryCounts) then
    begin
      mCount := mView.QueryCounts[mIndex];
    end;
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasTrackerIssuesText.QueryCaption(mView.Queries[mIndex].Name, mCount);
    mItem.RadioItem := True;
    mItem.Checked := mIndex = mView.QueryIndex;
    mItem.Tag := mIndex;
    mItem.OnClick := ItemClick;
    FMenu.Items.Add(mItem);
  end;
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := cMenuLine;
  FMenu.Items.Add(mItem);
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeIssuesQueriesEdit);
  mItem.OnClick := EditClick;
  FMenu.Items.Add(mItem);
end;

procedure TAtlasTrackerIssuesQueries.LabelClick(Sender: TObject);
var
  mPoint: TPoint;
begin
  Fill;
  mPoint := FLabel.ClientToScreen(Point(0, FLabel.Height));
  FMenu.Popup(mPoint.X, mPoint.Y);
end;

procedure TAtlasTrackerIssuesQueries.ItemClick(Sender: TObject);
var
  mName: string;
  mIndex: Integer;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (mIndex >= 0) and (mIndex <= High(FOwner.View.Queries)) then
  begin
    mName := FOwner.View.Queries[mIndex].Name;
    FOwner.Send(
      procedure(const ASource: IAtlasIssuesSource)
      begin
        ASource.SelectQuery(mName);
      end);
  end;
end;

procedure TAtlasTrackerIssuesQueries.EditClick(Sender: TObject);
begin
  FOwner.Send(
    procedure(const ASource: IAtlasIssuesSource)
    begin
      ASource.EditQueries;
    end);
end;

{ TAtlasTrackerIssuesView }

constructor TAtlasTrackerIssuesView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FView := Default(TAtlasIssuesView);
  FPainter := TAtlasTrackerIssuesPainter.Create(Self);
  // Klappliste der Abfragen (#1262) über der Liste.
  FQueries := TAtlasTrackerIssuesQueries.Create(Self);
  FBox := TAtlasStyledCanvas.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
  FMenus := TAtlasTrackerIssuesMenu.Create(Self);
  FBox.PopupMenu := FMenus.Menu;
end;

destructor TAtlasTrackerIssuesView.Destroy;
begin
  // Steuerelemente und Menüs gehören der Ansicht (Owner) und gehen mit inherited; die Helfer nur sich selbst.
  FreeAndNil(FMenus);
  FreeAndNil(FQueries);
  FreeAndNil(FPainter);
  inherited;
end;

procedure TAtlasTrackerIssuesView.SetSource(const AValue: IAtlasIssuesSource);
begin
  FSource := AValue;
  UpdateContent;
  if FSource <> nil then
  begin
    FSource.Shown;
  end;
end;

procedure TAtlasTrackerIssuesView.UpdateContent;
var
  mOldHeight: Integer;
begin
  if not HasWindow then
  begin
    Exit;
  end;
  mOldHeight := BodyHeight;
  FView := Default(TAtlasIssuesView);
  if FSource <> nil then
  begin
    FView := FSource.View;
  end;
  FPainter.Reset(Length(FView.Items));
  FHintKey := '';
  FQueries.Update;
  FBox.Invalidate;
  inherited;
  if mOldHeight <> BodyHeight then
  begin
    HeightChanged;
  end;
end;

function TAtlasTrackerIssuesView.CanStart: Boolean;
begin
  Result := (FSource <> nil) and not FView.Starting;
end;

function TAtlasTrackerIssuesView.BodyHeight: Integer;
begin
  Result := FPainter.Height;
  if FQueries.Bar.Visible then
  begin
    Inc(Result, FQueries.Bar.Height);
  end;
end;

procedure TAtlasTrackerIssuesView.BoxPaint(Sender: TObject);
begin
  FPainter.Paint(FBox.Canvas);
end;

function TAtlasTrackerIssuesView.HitTest(AX, AY: Integer): TAtlasIssuesHit;
begin
  Result := FPainter.HitTest(AX, AY);
end;

class procedure TAtlasTrackerIssuesView.Post(const AAction: TThreadProcedure);
begin
  // Die Quelle füllt den Bereich danach neu: nicht im eigenen Maus- bzw. Menüereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.Tracker, AAction);
end;

procedure TAtlasTrackerIssuesView.Send(const AAction: TAtlasIssuesAction);
var
  mSource: IAtlasIssuesSource;
  mAction: TAtlasIssuesAction;
begin
  mSource := FSource;
  mAction := AAction;
  if mSource <> nil then
  begin
    Post(
      procedure
      begin
        mAction(mSource);
      end);
  end;
end;

procedure TAtlasTrackerIssuesView.SendIssue(AIndex: Integer; const AAction: TAtlasIssuesItemAction);
var
  mItem: TAtlasTrackerIssue;
  mAction: TAtlasIssuesItemAction;
begin
  if (AIndex >= 0) and (AIndex <= High(FView.Items)) then
  begin
    mItem := FView.Items[AIndex];
    mAction := AAction;
    Send(
      procedure(const ASource: IAtlasIssuesSource)
      begin
        mAction(ASource, mItem);
      end);
  end;
end;

procedure TAtlasTrackerIssuesView.ClickAt(const AHit: TAtlasIssuesHit);
begin
  ClickAt(AHit, False);
end;

procedure TAtlasTrackerIssuesView.ClickAt(const AHit: TAtlasIssuesHit; ABrowse: Boolean);
begin
  case AHit.Kind of
    TAtlasIssuesHitKind.Assign:
      Send(
        procedure(const ASource: IAtlasIssuesSource)
        begin
          ASource.AssignProject;
        end);
    TAtlasIssuesHitKind.Filter:
      Send(
        procedure(const ASource: IAtlasIssuesSource)
        begin
          ASource.ClearFilter;
        end);
  else
    if (FSource <> nil) and (AHit.Index >= 0) and (AHit.Index <= High(FView.Items)) then
    begin
      ClickIssue(AHit, ABrowse);
    end;
  end;
end;

procedure TAtlasTrackerIssuesView.ClickIssue(const AHit: TAtlasIssuesHit; ABrowse: Boolean);
var
  mPreview: Boolean;
  mMode: TAtlasIssueStart;
begin
  mPreview := FView.Options.Preview;
  // Leerraum und Zeilentext lösen ohne Vorschau nichts aus; sie zeigen nur den Hinweis (BoxMouseMove).
  if (AHit.Kind in [TAtlasIssuesHitKind.Row, TAtlasIssuesHitKind.Key]) and mPreview and not ABrowse then
  begin
    SendIssue(AHit.Index,
      procedure(const ASource: IAtlasIssuesSource; const AIssue: TAtlasTrackerIssue)
      begin
        ASource.Preview(AIssue);
      end);
  end
  else if (AHit.Kind = TAtlasIssuesHitKind.Key) or ((AHit.Kind = TAtlasIssuesHitKind.Row) and ABrowse and mPreview) then
  begin
    SendIssue(AHit.Index,
      procedure(const ASource: IAtlasIssuesSource; const AIssue: TAtlasTrackerIssue)
      begin
        ASource.Browse(AIssue);
      end);
  end
  else if AHit.Kind = TAtlasIssuesHitKind.PullRequest then
  begin
    SendIssue(AHit.Index,
      procedure(const ASource: IAtlasIssuesSource; const AIssue: TAtlasTrackerIssue)
      begin
        ASource.BrowsePullRequest(AIssue);
      end);
  end
  else if (AHit.Kind = TAtlasIssuesHitKind.Start) and CanStart then
  begin
    mMode := FView.Options.Start;
    SendIssue(AHit.Index,
      procedure(const ASource: IAtlasIssuesSource; const AIssue: TAtlasTrackerIssue)
      begin
        ASource.Start(AIssue, mMode);
      end);
  end;
end;

procedure TAtlasTrackerIssuesView.BoxMouseMove(Sender: TObject; Shift: TShiftState; AX, AY: Integer);
var
  mHit: TAtlasIssuesHit;
  mKey: string;
begin
  mHit := HitTest(AX, AY);
  if (mHit.Kind in [TAtlasIssuesHitKind.Key, TAtlasIssuesHitKind.PullRequest, TAtlasIssuesHitKind.Start,
    TAtlasIssuesHitKind.Assign, TAtlasIssuesHitKind.Filter]) or
    ((mHit.Kind = TAtlasIssuesHitKind.Row) and FView.Options.Preview) then
  begin
    FBox.Cursor := crHandPoint;
  end
  else
  begin
    FBox.Cursor := crDefault;
  end;
  mKey := Format(cHintKeyFormat, [Ord(mHit.Kind), mHit.Index], TFormatSettings.Invariant);
  if mKey <> FHintKey then
  begin
    FHintKey := mKey;
    FBox.Hint := TAtlasTrackerIssuesText.HintAt(FView, mHit);
    Application.CancelHint;
  end;
end;

procedure TAtlasTrackerIssuesView.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; AX,
  AY: Integer);
begin
  if Button = mbLeft then
  begin
    ClickAt(HitTest(AX, AY), ssCtrl in Shift);
  end;
end;

end.
