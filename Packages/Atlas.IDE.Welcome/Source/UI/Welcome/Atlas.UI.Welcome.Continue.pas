unit Atlas.UI.Welcome.Continue;

// Bereich „Weiterarbeiten“ der Willkommensseite (#755), ohne Open Tools API.
// Zwei Reiter (der zweite nur mit welcomePage.saved):
// - „Zuletzt“: je Arbeitsstand eine Zeile, neueste zuerst, selbst gezeichnet:
//     Atlas · 7 Reiter                              vor 2 Std.  [Fortsetzen]
//     Kunde.pas › TKunde.Laden
//   Darunter für den obersten Eintrag „Neu seit deinem letzten Öffnen
//   (origin/main)“ mit je Commit Kurz-Hash, Betreff, Autor und betroffener
//   Datei; Klick zeigt die Dateien des Commits. Ohne Arbeitskopie oder
//   verfolgten Branch fehlt der Abschnitt. Ganz unten ein Hinweis der Quelle
//   (z. B. übersprungene Dateien nach „Fortsetzen“).
// - „Gemerkt“: Filterfeld und Liste mit Art, Text bzw. Name, Datei und Zeile,
//   Projekt; Doppelklick oder Enter springt hin.
// Schnellaktionen (#764, Atlas.UI.Welcome.QuickActions): In der Zeile unter
// der Maus bzw. in der mit der Tastatur gewählten Zeile (hinterlegt) stehen
// links von „Fortsetzen“ die Knöpfe „Öffnen und bauen“, „Tests“,
// „Startprofil ▾“, „Pull“, „Ordner“, „Konsole“ statt des Zeitpunkts; ein
// laufender oder beendeter Lauf steht dort als Marke („baut … 12 s“).
// Tastatur: ↑/↓ Zeile, ←/→ Knopf, Enter führt aus bzw. setzt fort, Strg+B
// baut, Strg+T testet; Kontextmenütaste öffnet das Menü der Zeile.
// Daten und Aktionen kommen über IAtlasContinueSource aus der IDE-Schicht;
// Klicks gehen über die Nachrichtenschleife, weil die Quelle den Bereich
// daraufhin neu füllt.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Graphics,
  Vcl.Menus,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.Saved,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.QuickActions;

type
  IAtlasContinueSource = interface
    ['{2B7E9C41-5D3A-4E86-9F1B-C4A07D2E8B95}']
    /// <summary>Gezeigte Arbeitsstände, neueste zuerst.</summary>
    function Entries: TAtlasContinueEntries;
    /// <summary>Eingehende Commits zum obersten Eintrag; Available = False: kein Abschnitt.</summary>
    function Incoming: TAtlasContinueIncoming;
    /// <summary>Die Abfrage der eingehenden Commits läuft gerade.</summary>
    function IncomingQuerying: Boolean;
    /// <summary>Reiter „Gemerkt“ zeigen (welcomePage.saved).</summary>
    function SavedEnabled: Boolean;
    /// <summary>Notizen, Lesezeichen und Favoriten aller Projekte.</summary>
    function Saved: TAtlasSavedItems;
    /// <summary>Hinweis unter der Liste (z. B. übersprungene Dateien); '' ohne.</summary>
    function Notice: string;
    /// <summary>„Fortsetzen“: Projekt öffnen, Reiter in ihrer Reihenfolge, Cursor an die letzte Änderung.</summary>
    procedure Resume(const AProject: string);
    /// <summary>Dateien eines eingehenden Commits zeigen.</summary>
    procedure ShowCommit(const AProject: string; const ACommit: TAtlasContinueCommit);
    /// <summary>Projekt öffnen und zum gemerkten Eintrag springen.</summary>
    procedure OpenSaved(const AItem: TAtlasSavedItem);
    /// <summary>„Anmeldung am Server nötig – prüfen …“ (#1287): Seite Versionsverwaltung für AProject öffnen.
    /// </summary>
    procedure ShowServerAccess(const AProject: string);
    /// <summary>Der Bereich wird gezeigt: eingehende Commits bei Bedarf im Hintergrund abfragen.</summary>
    procedure Shown;
  end;

  TAtlasContinueHit = record
    /// <summary>Zeile eines Arbeitsstands; -1 = keine.</summary>
    Row: Integer;
    /// <summary>Auf „Fortsetzen“ der Zeile.</summary>
    Button: Boolean;
    /// <summary>Eingehender Commit; -1 = keiner.</summary>
    Commit: Integer;
    /// <summary>Auf „Anmeldung am Server nötig – prüfen …“ (#1287).</summary>
    Login: Boolean;
  end;

  /// <summary>Texte des Bereichs „Weiterarbeiten“, ohne Steuerelement.</summary>
  TAtlasContinueTexts = class
  public
    /// <summary>Kopfzeile: „Name · 7 Reiter“.</summary>
    class function TitleText(const AEntry: TAtlasContinueEntry): string; static;
    /// <summary>Zweite Zeile: zuletzt bearbeitete Datei und Methode, z. B. „Kunde.pas › TKunde.Laden“.</summary>
    class function DetailText(const AEntry: TAtlasContinueEntry): string; static;
    /// <summary>„7 Reiter“ bzw. „1 Reiter“.</summary>
    class function TabsText(ACount: Integer): string; static;
    /// <summary>„gerade eben“, „vor 5 Min.“, „vor 2 Std.“, „gestern 18:40“ bzw. Datum mit Uhrzeit.</summary>
    class function AgeText(AAtUtc, ANowUtc: TDateTime): string; static;
    /// <summary>Zeile eines Commits: „abc1234 Betreff — Autor · Kunde.pas“.</summary>
    class function CommitText(const ACommit: TAtlasContinueCommit): string; static;
    class function CommitHint(const ACommit: TAtlasContinueCommit): string; static;
    class function HintFor(const AEntry: TAtlasContinueEntry): string; static;
    /// <summary>Spalten einer Zeile der Liste „Gemerkt“: Art, Text, Datei und Zeile, Projekt.</summary>
    class function SavedCells(const AItem: TAtlasSavedItem): TArray<string>; static;
    class function KindText(AKind: TAtlasSavedKind): string; static;
    class function NowUtc: TDateTime; static;
    class function LocalText(AUtc: TDateTime): string; static;
  end;

  /// <summary>Reiter „Gemerkt“: Filterfeld und Liste der Notizen, Lesezeichen und Favoriten; Doppelklick oder
  /// Enter springt hin.</summary>
  TAtlasContinueSavedPage = class(TPanel)
  private
    FSource: IAtlasContinueSource;
    FFilter: TEdit;
    FList: TListView;
    FSavedEmpty: TLabel;
    FSaved: TAtlasSavedItems;
    FShownSaved: TAtlasSavedItems;
    FSavedLoaded: Boolean;
    procedure FilterChange(Sender: TObject);
    procedure FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure RefillSaved;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Spalten Art, Text, Ort und Projekt mit den Breiten AWidths (Pixel).</summary>
    procedure AddColumns(const AWidths: array of Integer);
    /// <summary>Einträge neu von der Quelle lesen und die Liste füllen.</summary>
    procedure LoadSaved;
    /// <summary>Gewählten Eintrag öffnen (Doppelklick, Enter).</summary>
    procedure OpenSelected;
    property Source: IAtlasContinueSource read FSource write FSource;
    /// <summary>Seit dem letzten Füllen des Bereichs gelesen; False: beim Zeigen neu lesen.</summary>
    property Loaded: Boolean read FSavedLoaded write FSavedLoaded;
    property Filter: TEdit read FFilter;
    property List: TListView read FList;
    property EmptyLabel: TLabel read FSavedEmpty;
    /// <summary>Gezeigte Einträge in der Reihenfolge der Zeilen.</summary>
    property ShownSaved: TAtlasSavedItems read FShownSaved;
  end;

  /// <summary>Reiter „Zuletzt“: Zeilen der Arbeitsstände mit „Fortsetzen“ und Schnellaktionen, darunter „Neu seit
  /// …“ und der Hinweis der Quelle; selbst gezeichnet.</summary>
  TAtlasContinueRecentView = class(TPanel)
  public const
    RowHeight = 44;
    LineHeight = 20;
    Indent = 8;
    ButtonHeight = 22;
    ButtonPadding = 10;
  private
    FFrame: TAtlasWelcomeSectionFrame;
    FSource: IAtlasContinueSource;
    FBox: TAtlasWelcomeCanvas;
    FEntries: TAtlasContinueEntries;
    FIncoming: TAtlasContinueIncoming;
    FQuerying: Boolean;
    FNotice: string;
    FButtonRects: TArray<TRect>;
    FHintKey: string;
    FQuick: TAtlasQuickActionsBar;
    FMenu: TPopupMenu;
    FResumeItem: TMenuItem;
    FMenuRow: Integer;
    procedure QuickOpenRow(ARow: Integer);
    procedure QuickRowMenu(ARow: Integer);
    procedure MenuPopup(Sender: TObject);
    procedure ResumeClick(Sender: TObject);
    procedure LayoutButtons;
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseLeave(Sender: TObject);
  public
    /// <summary>Zeichnet mit Schrift und Skalierung von AFrame.</summary>
    constructor Create(AFrame: TAtlasWelcomeSectionFrame); reintroduce;
    /// <summary>Arbeitsstände, eingehende Commits und Hinweis neu von der Quelle lesen.</summary>
    procedure Fill;
    /// <summary>Höhe der Zeilen, des Abschnitts „Neu seit …“ und des Hinweises.</summary>
    function ContentHeight: Integer;
    /// <summary>Zeile, Schaltfläche bzw. Commit an X, Y (Koordinaten der Zeichenfläche).</summary>
    function HitTest(X, Y: Integer): TAtlasContinueHit;
    /// <summary>Klick wie mit der Maus (auch für Tests): „Fortsetzen“ bzw. Commit.</summary>
    procedure ClickAt(const AHit: TAtlasContinueHit);
    /// <summary>Oberkante der Zeile ARow (Koordinaten der Zeichenfläche).</summary>
    function RowTop(ARow: Integer): Integer;
    /// <summary>Oberkante des Abschnitts „Neu seit …“ (unter den Zeilen).</summary>
    function IncomingTop: Integer;
    property Source: IAtlasContinueSource read FSource write FSource;
    /// <summary>Knopfleiste, Stand und Tastatur der Schnellaktionen (auch für Tests).</summary>
    property Quick: TAtlasQuickActionsBar read FQuick;
    /// <summary>Kontextmenü der Zeilen: „Fortsetzen“ und die Schnellaktionen.</summary>
    property Menu: TPopupMenu read FMenu;
    property Entries: TAtlasContinueEntries read FEntries;
    property IncomingView: TAtlasContinueIncoming read FIncoming;
    property PaintBox: TAtlasWelcomeCanvas read FBox;
  end;

  TAtlasWelcomeContinueFrame = class(TAtlasWelcomeSectionFrame)
  public const
    RowHeight = TAtlasContinueRecentView.RowHeight;
    LineHeight = TAtlasContinueRecentView.LineHeight;
    Indent = TAtlasContinueRecentView.Indent;
    TabHeight = 26;
    FilterHeight = 28;
    /// <summary>Sichtbare Zeilen der Liste „Gemerkt“ (logische Pixel je Zeile: LineHeight).</summary>
    SavedRows = 8;
    PageRecent = 0;
    PageSaved = 1;
  private
    FSource: IAtlasContinueSource;
    FTabs: TTabControl;
    FRecent: TAtlasContinueRecentView;
    FSavedPage: TAtlasContinueSavedPage;
    procedure SetSource(const AValue: IAtlasContinueSource);
    function GetQuickActions: IAtlasQuickActionsSource;
    procedure SetQuickActions(const AValue: IAtlasQuickActionsSource);
    function GetPage: Integer;
    procedure SetPage(AValue: Integer);
    procedure TabsChange(Sender: TObject);
    procedure ShowPage;
    function TabsShown: Boolean;
  protected
    function BodyHeight: Integer; override;
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    property Source: IAtlasContinueSource read FSource write SetSource;
    /// <summary>Schnellaktionen (#764); nil = keine Knöpfe.</summary>
    property QuickActions: IAtlasQuickActionsSource read GetQuickActions write SetQuickActions;
    property Tabs: TTabControl read FTabs;
    /// <summary>Reiter „Zuletzt“.</summary>
    property Recent: TAtlasContinueRecentView read FRecent;
    /// <summary>Reiter „Gemerkt“.</summary>
    property SavedPage: TAtlasContinueSavedPage read FSavedPage;
    /// <summary>PageRecent oder PageSaved.</summary>
    property Page: Integer read GetPage write SetPage;
  end;

implementation

uses
  System.DateUtils,
  System.UITypes,
  Winapi.Windows,
  Vcl.Themes,
  Atlas.Core.Welcome.QuickActions,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Welcome.Strings;

const
  Separator = ' · ';
  Arrow = ' ' + #$203A + ' ';
  Dash = ' ' + #$2014 + ' ';
  NoticeColor = TColor($001A8CC9);

type
  /// <summary>Farben des IDE-Themas (hell oder dunkel) für den Reiter „Zuletzt“.</summary>
  TContinueColors = record
    Text: TColor;
    Muted: TColor;
    Line: TColor;
    Link: TColor;
  end;

  /// <summary>Zeichnet den Reiter „Zuletzt“: Zeilen, Abschnitt „Neu seit …“ und Hinweis der Quelle.</summary>
  TContinuePainter = record
    View: TAtlasContinueRecentView;
    Canvas: TCanvas;
    Colors: TContinueColors;
    Stamp: TDateTime;
    Active: Integer;
    function Scaled(AValue: Integer): Integer;
    procedure PlainFont;
    procedure SmallFont;
    function PaintBadge(ATop, ALimit: Integer; const AText: string; const AState: TAtlasQuickActionState): Integer;
    function PaintAge(ARow, ATop, ALimit: Integer): Integer;
    /// <summary>Rechts vor „Fortsetzen“: Knöpfe (aktive Zeile), Marke des Laufs oder Zeitpunkt; liefert die neue
    /// rechte Grenze der Texte.</summary>
    function PaintRight(ARow, ATop, ALimit: Integer): Integer;
    procedure PaintTexts(ARow, ATop, ALimit: Integer);
    procedure PaintButton(ARow: Integer);
    procedure PaintRow(ARow: Integer);
    /// <summary>Zeile ALine unter IncomingTop, ab AX, rechts begrenzt.</summary>
    procedure PaintLine(ALine, AX: Integer; AColor: TColor; const AText: string);
    procedure PaintIncomingTail(var ALine: Integer);
    /// <summary>Abschnitt „Neu seit …“; liefert die Zahl der gezeichneten Zeilen.</summary>
    function PaintIncoming: Integer;
    procedure Paint;
  end;

function ShowsIncoming(AView: TAtlasContinueRecentView): Boolean;
begin
  Result := (Length(AView.FEntries) > 0) and (AView.FIncoming.Available or AView.FQuerying);
end;

/// <summary>Zeilen des Abschnitts „Neu seit …“ samt Überschrift; 0 ohne Abschnitt.</summary>
function IncomingLines(AView: TAtlasContinueRecentView): Integer;
begin
  Result := 0;
  if not ShowsIncoming(AView) then
  begin
    Exit;
  end;
  // Überschrift und je Commit eine Zeile; ohne Commits eine Zeile „Keine …“ bzw. „wird abgefragt …“.
  Result := 1 + Length(AView.FIncoming.Commits);
  if Length(AView.FIncoming.Commits) = 0 then
  begin
    Inc(Result);
  end;
  if AView.FIncoming.More then
  begin
    Inc(Result);
  end;
  if AView.FIncoming.FetchFailed then
  begin
    Inc(Result);
  end;
end;

/// <summary>Zeile des Hinweises „Anmeldung nötig“ unter der Überschrift (0 = erste Zeile darunter).</summary>
function LoginLine(const AIncoming: TAtlasContinueIncoming): Integer;
begin
  Result := Length(AIncoming.Commits);
  if Result = 0 then
  begin
    Result := 1;
  end;
  if AIncoming.More then
  begin
    Inc(Result);
  end;
end;

function ProjectNames(const AEntries: TAtlasContinueEntries): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AEntries));
  for mIndex := 0 to High(AEntries) do
  begin
    Result[mIndex] := AEntries[mIndex].Project;
  end;
end;

{ TAtlasContinueTexts }

class function TAtlasContinueTexts.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasContinueTexts.LocalText(AUtc: TDateTime): string;
begin
  Result := '';
  if AUtc > 0 then
  begin
    Result := FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(AUtc));
  end;
end;

class function TAtlasContinueTexts.TabsText(ACount: Integer): string;
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

class function TAtlasContinueTexts.AgeText(AAtUtc, ANowUtc: TDateTime): string;
var
  AtLocal: TDateTime;
  Value: Integer;
begin
  Result := '';
  if AAtUtc <= 0 then
  begin
    Exit;
  end;
  AtLocal := TTimeZone.Local.ToLocalTime(AAtUtc);
  case TAtlasWelcomeContinue.Age(AtLocal, TTimeZone.Local.ToLocalTime(ANowUtc), Value) of
    TAtlasContinueAge.JustNow:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueJustNow);
    TAtlasContinueAge.Minutes:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueMinutes, [Value]);
    TAtlasContinueAge.Hours:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueHours, [Value]);
    TAtlasContinueAge.Yesterday:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueYesterday, [FormatDateTime('t', AtLocal)]);
  else
    Result := FormatDateTime('ddddd t', AtLocal);
  end;
end;

class function TAtlasContinueTexts.TitleText(const AEntry: TAtlasContinueEntry): string;
begin
  Result := AEntry.Name + Separator + TabsText(AEntry.State.TabCount);
end;

class function TAtlasContinueTexts.DetailText(const AEntry: TAtlasContinueEntry): string;
var
  Tab: TAtlasWorkTab;
begin
  Tab := AEntry.LastTab;
  Result := TAtlasWelcomeContinue.FileNameOf(Tab.FileName);
  if Tab.Method <> '' then
  begin
    Result := Result + Arrow + Tab.Method;
  end;
end;

class function TAtlasContinueTexts.CommitText(const ACommit: TAtlasContinueCommit): string;
var
  Names: TArray<string>;
  FileName: string;
begin
  Names := nil;
  for FileName in ACommit.Files do
  begin
    Names := Names + [TAtlasWelcomeContinue.FileNameOf(FileName)];
  end;
  Result := ACommit.Commit.ShortHash + '  ' + ACommit.Commit.Summary + Dash + ACommit.Commit.Author;
  if Length(Names) > 0 then
  begin
    Result := Result + Separator + string.Join(', ', Names);
  end;
end;

class function TAtlasContinueTexts.CommitHint(const ACommit: TAtlasContinueCommit): string;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Add(ACommit.Commit.ShortHash + ' ' + ACommit.Commit.Summary);
    Lines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueCommitAuthor, [ACommit.Commit.Author]));
    Lines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueCommitDate,
      [LocalText(ACommit.Commit.Date)]));
    Lines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueCommitAffects,
      [string.Join(', ', ACommit.Files)]));
    Lines.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueCommitClick));
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

class function TAtlasContinueTexts.HintFor(const AEntry: TAtlasContinueEntry): string;
var
  Lines: TStringList;
  Tab: TAtlasWorkTab;
  Place: string;
begin
  Lines := TStringList.Create;
  try
    Lines.Add(AEntry.Project);
    Lines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueHintSaved, [TabsText(AEntry.State.TabCount),
      LocalText(AEntry.State.At)]));
    Tab := AEntry.LastTab;
    if Tab.FileName <> '' then
    begin
      Place := Tab.FileName;
      if Tab.Line > 0 then
      begin
        Place := Place + ':' + IntToStr(Tab.Line);
      end;
      if Tab.Method <> '' then
      begin
        Place := Place + Arrow + Tab.Method;
      end;
      Lines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueHintLast, [Place]));
    end;
    Lines.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueHintResume));
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

class function TAtlasContinueTexts.KindText(AKind: TAtlasSavedKind): string;
begin
  case AKind of
    TAtlasSavedKind.Note:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedNote);
    TAtlasSavedKind.Bookmark:
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedBookmark);
  else
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedFavorite);
  end;
end;

class function TAtlasContinueTexts.SavedCells(const AItem: TAtlasSavedItem): TArray<string>;
var
  mText, Project: string;
begin
  mText := AItem.Text;
  if AItem.Lost then
  begin
    mText := mText + ' ' + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedLost);
  end;
  Project := AItem.ProjectName;
  if AItem.Kind = TAtlasSavedKind.Favorite then
  begin
    Project := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedAllProjects);
  end;
  Result := [KindText(AItem.Kind), mText, AItem.Place, Project];
end;


{ TContinuePainter }

function TContinuePainter.Scaled(AValue: Integer): Integer;
begin
  Result := View.FFrame.ScaleValue(AValue);
end;

procedure TContinuePainter.PlainFont;
begin
  Canvas.Font.Assign(View.FFrame.Font);
end;

procedure TContinuePainter.SmallFont;
begin
  PlainFont;
  Canvas.Font.Size := View.FFrame.Font.Size - 1;
end;

function TContinuePainter.PaintBadge(ATop, ALimit: Integer; const AText: string;
  const AState: TAtlasQuickActionState): Integer;
var
  mRect: TRect;
begin
  mRect := Rect(ALimit - Canvas.TextWidth(AText) - Scaled(12), ATop + Scaled(3), ALimit, ATop + Scaled(19));
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TAtlasQuickActionsBar.StateColor(AState);
  Canvas.Pen.Color := Canvas.Brush.Color;
  Canvas.RoundRect(mRect.Left, mRect.Top, mRect.Right, mRect.Bottom, Scaled(16), Scaled(16));
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := clWhite;
  Canvas.TextOut(mRect.Left + Scaled(6), mRect.Top + (mRect.Height - Canvas.TextHeight(AText)) div 2, AText);
  Result := mRect.Left - Scaled(TAtlasContinueRecentView.Indent);
end;

function TContinuePainter.PaintAge(ARow, ATop, ALimit: Integer): Integer;
var
  mAge: string;
begin
  // Zeitpunkt rechts vor der Schaltfläche.
  Result := ALimit;
  PlainFont;
  Canvas.Font.Color := Colors.Muted;
  mAge := TAtlasContinueTexts.AgeText(View.FEntries[ARow].State.At, Stamp);
  if mAge <> '' then
  begin
    Canvas.TextOut(ALimit - Canvas.TextWidth(mAge), ATop + Scaled(3), mAge);
    Result := ALimit - Canvas.TextWidth(mAge) - Scaled(TAtlasContinueRecentView.Indent);
  end;
end;

function TContinuePainter.PaintRight(ARow, ATop, ALimit: Integer): Integer;
var
  mText: string;
begin
  SmallFont;
  if ARow = Active then
  begin
    // Schnellaktionen (#764): Knöpfe statt des Zeitpunkts links von „Fortsetzen“.
    Result := View.FQuick.LayoutRow(Canvas, ARow, Rect(Scaled(TAtlasContinueRecentView.Indent) + Scaled(80), ATop,
      ALimit, ATop + Scaled(TAtlasContinueRecentView.RowHeight) - Scaled(2))) -
      Scaled(TAtlasContinueRecentView.Indent);
    Exit;
  end;
  // Stand der letzten Schnellaktion als Marke („baut … 12 s“), sonst der Zeitpunkt.
  mText := TAtlasQuickRowTexts.StateText(View.FQuick, ARow);
  if mText <> '' then
  begin
    Result := PaintBadge(ATop, ALimit, mText, View.FQuick.StateOf(ARow));
  end
  else
  begin
    Result := PaintAge(ARow, ATop, ALimit);
  end;
end;

procedure TContinuePainter.PaintTexts(ARow, ATop, ALimit: Integer);
var
  mEntry: TAtlasContinueEntry;
  mLeft, mDetailLimit: Integer;
begin
  mEntry := View.FEntries[ARow];
  mLeft := Scaled(TAtlasContinueRecentView.Indent);
  PlainFont;
  Canvas.Font.Color := Colors.Text;
  Canvas.Font.Style := [fsBold];
  Canvas.TextRect(Rect(mLeft, ATop + Scaled(3), ALimit, ATop + Scaled(21)), mLeft, ATop + Scaled(3), mEntry.Name);
  Inc(mLeft, Canvas.TextWidth(mEntry.Name));
  Canvas.Font.Style := [];
  if mLeft < ALimit then
  begin
    Canvas.Font.Color := Colors.Muted;
    Canvas.TextRect(Rect(mLeft, ATop + Scaled(3), ALimit, ATop + Scaled(21)), mLeft, ATop + Scaled(3),
      Separator + TAtlasContinueTexts.TabsText(mEntry.State.TabCount));
  end;
  // Zweite Zeile: Datei und Methode; ohne Knöpfe bis vor „Fortsetzen“.
  mLeft := Scaled(TAtlasContinueRecentView.Indent);
  mDetailLimit := ALimit;
  if ARow <> Active then
  begin
    mDetailLimit := View.FButtonRects[ARow].Left - Scaled(TAtlasContinueRecentView.Indent);
  end;
  Canvas.Font.Color := Colors.Muted;
  Canvas.TextRect(Rect(mLeft, ATop + Scaled(23), mDetailLimit, ATop + Scaled(41)), mLeft, ATop + Scaled(23),
    TAtlasContinueTexts.DetailText(mEntry));
end;

procedure TContinuePainter.PaintButton(ARow: Integer);
var
  mButton: TRect;
  mText: string;
begin
  mButton := View.FButtonRects[ARow];
  Canvas.Pen.Color := Colors.Line;
  Canvas.Brush.Style := bsClear;
  Canvas.RoundRect(mButton.Left, mButton.Top, mButton.Right, mButton.Bottom, Scaled(6), Scaled(6));
  Canvas.Font.Color := Colors.Text;
  mText := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueResume);
  Canvas.TextOut(mButton.Left + (mButton.Width - Canvas.TextWidth(mText)) div 2,
    mButton.Top + (mButton.Height - Canvas.TextHeight(mText)) div 2, mText);
end;

procedure TContinuePainter.PaintRow(ARow: Integer);
var
  mTop, mLimit: Integer;
begin
  mTop := View.RowTop(ARow);
  mLimit := View.FButtonRects[ARow].Left - Scaled(TAtlasContinueRecentView.Indent);
  // Schnellaktionen (#764): aktive Zeile hinterlegt.
  View.FQuick.PaintBackground(Canvas, ARow, Rect(0, mTop, View.FBox.Width,
    mTop + Scaled(TAtlasContinueRecentView.RowHeight) - Scaled(2)));
  mLimit := PaintRight(ARow, mTop, mLimit);
  PaintTexts(ARow, mTop, mLimit);
  PaintButton(ARow);
  if ARow = Active then
  begin
    SmallFont;
    View.FQuick.PaintRow(Canvas, ARow);
  end;
end;

procedure TContinuePainter.PaintLine(ALine, AX: Integer; AColor: TColor; const AText: string);
var
  mTop, mLine: Integer;
begin
  mTop := View.IncomingTop;
  mLine := Scaled(TAtlasContinueRecentView.LineHeight);
  Canvas.Font.Color := AColor;
  Canvas.TextRect(Rect(Scaled(TAtlasContinueRecentView.Indent), mTop + ALine * mLine,
    View.FBox.Width - Scaled(TAtlasContinueRecentView.Indent), mTop + (ALine + 1) * mLine), AX, mTop + ALine * mLine,
    AText);
end;

procedure TContinuePainter.PaintIncomingTail(var ALine: Integer);
var
  mX: Integer;
begin
  mX := 2 * Scaled(TAtlasContinueRecentView.Indent);
  if View.FIncoming.More then
  begin
    PaintLine(ALine, mX, Colors.Muted, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueIncomingMore));
    Inc(ALine);
  end;
  // Fehlt die Anmeldung, die Ursache als Link statt nur „ohne Abruf“ (#1287).
  if View.FIncoming.LoginNeeded then
  begin
    PaintLine(ALine, mX, Colors.Link, TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueIncomingLogin));
    Inc(ALine);
  end
  else if View.FIncoming.FetchFailed then
  begin
    PaintLine(ALine, mX, Colors.Muted,
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueIncomingFetchFailed));
    Inc(ALine);
  end;
end;

function TContinuePainter.PaintIncoming: Integer;
var
  mUpstream, mText: string;
  mCommit: TAtlasContinueCommit;
  mX: Integer;
begin
  // Neu seit deinem letzten Öffnen (für den obersten Eintrag).
  Result := 0;
  if not ShowsIncoming(View) then
  begin
    Exit;
  end;
  mUpstream := View.FIncoming.Upstream;
  if mUpstream = '' then
  begin
    mUpstream := '…';
  end;
  PlainFont;
  Canvas.Font.Style := [fsBold];
  PaintLine(0, Scaled(TAtlasContinueRecentView.Indent), Colors.Text,
    TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeContinueIncomingTitle, [mUpstream]));
  Result := 1;
  Canvas.Font.Style := [];
  mX := 2 * Scaled(TAtlasContinueRecentView.Indent);
  for mCommit in View.FIncoming.Commits do
  begin
    PaintLine(Result, mX, Colors.Link, TAtlasContinueTexts.CommitText(mCommit));
    Inc(Result);
  end;
  if Length(View.FIncoming.Commits) = 0 then
  begin
    mText := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueIncomingNone);
    if View.FQuerying then
    begin
      mText := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueIncomingQuerying);
    end;
    PaintLine(Result, mX, Colors.Muted, mText);
    Inc(Result);
  end;
  PaintIncomingTail(Result);
end;

procedure TContinuePainter.Paint;
var
  mRow, mLine: Integer;
begin
  Canvas.Brush.Style := bsClear;
  PlainFont;
  if Length(View.FEntries) = 0 then
  begin
    Canvas.Font.Color := Colors.Muted;
    Canvas.TextOut(Scaled(TAtlasContinueRecentView.Indent), View.RowTop(0) + Scaled(4),
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueEmpty));
  end;
  View.LayoutButtons;
  for mRow := 0 to High(View.FEntries) do
  begin
    PaintRow(mRow);
  end;
  mLine := PaintIncoming;
  // Hinweis der Quelle (z. B. übersprungene Dateien).
  if View.FNotice <> '' then
  begin
    PlainFont;
    PaintLine(mLine, Scaled(TAtlasContinueRecentView.Indent), NoticeColor, View.FNotice);
  end;
end;

{ TAtlasContinueSavedPage }

constructor TAtlasContinueSavedPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  ParentBackground := True;
  ShowCaption := False;

  FFilter := TEdit.Create(Self);
  FFilter.Parent := Self;
  FFilter.Align := alTop;
  FFilter.AlignWithMargins := True;
  FFilter.TextHint := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedFilter);
  FFilter.OnChange := FilterChange;
  FFilter.OnKeyDown := FilterKeyDown;

  FSavedEmpty := TLabel.Create(Self);
  FSavedEmpty.Parent := Self;
  FSavedEmpty.Align := alTop;
  FSavedEmpty.AlignWithMargins := True;
  FSavedEmpty.ShowAccelChar := False;
  FSavedEmpty.WordWrap := True;
  FSavedEmpty.Font.Color := clGrayText;
  FSavedEmpty.Visible := False;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := True;
  FList.MultiSelect := False;
  FList.ColumnClick := False;
  FList.ShowHint := True;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
end;

procedure TAtlasContinueSavedPage.AddColumns(const AWidths: array of Integer);
const
  cCaptions: array[0..3] of TAtlasWelcomeTextId = (TAtlasWelcomeTextId.WelcomeSavedColKind,
    TAtlasWelcomeTextId.WelcomeSavedColText, TAtlasWelcomeTextId.WelcomeSavedColPlace,
    TAtlasWelcomeTextId.WelcomeSavedColProject);
var
  mIndex: Integer;
  mColumn: TListColumn;
begin
  for mIndex := 0 to High(cCaptions) do
  begin
    mColumn := FList.Columns.Add;
    mColumn.Caption := TAtlasWelcomeStrings.Text(cCaptions[mIndex]);
    if mIndex <= High(AWidths) then
    begin
      mColumn.Width := AWidths[mIndex];
    end;
  end;
end;

procedure TAtlasContinueSavedPage.LoadSaved;
begin
  FSaved := nil;
  if FSource <> nil then
  begin
    FSaved := FSource.Saved;
  end;
  FSavedLoaded := True;
  RefillSaved;
end;

procedure TAtlasContinueSavedPage.RefillSaved;
var
  Item: TAtlasSavedItem;
  Row: TListItem;
  Cells: TArray<string>;
  Index: Integer;
begin
  FShownSaved := TAtlasWelcomeSaved.Filter(FSaved, FFilter.Text);
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for Item in FShownSaved do
    begin
      Cells := TAtlasContinueTexts.SavedCells(Item);
      Row := FList.Items.Add;
      Row.Caption := Cells[0];
      for Index := 1 to High(Cells) do
      begin
        Row.SubItems.Add(Cells[Index]);
      end;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count > 0 then
  begin
    FList.Items[0].Selected := True;
    FList.Items[0].Focused := True;
  end;
  FSavedEmpty.Visible := Length(FShownSaved) = 0;
  if Length(FSaved) = 0 then
  begin
    FSavedEmpty.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedEmpty);
  end
  else
  begin
    FSavedEmpty.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeSavedNoMatch);
  end;
  FList.Visible := not FSavedEmpty.Visible;
end;

procedure TAtlasContinueSavedPage.FilterChange(Sender: TObject);
begin
  RefillSaved;
end;

procedure TAtlasContinueSavedPage.FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DOWN) and FList.Visible and (FList.Items.Count > 0) then
  begin
    FList.SetFocus;
    Key := 0;
  end
  else if Key = VK_RETURN then
  begin
    OpenSelected;
    Key := 0;
  end;
end;

procedure TAtlasContinueSavedPage.ListDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TAtlasContinueSavedPage.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    OpenSelected;
    Key := 0;
  end;
end;

procedure TAtlasContinueSavedPage.OpenSelected;
var
  mSource: IAtlasContinueSource;
  Item: TAtlasSavedItem;
  Index: Integer;
begin
  if (FSource = nil) or (FList.Selected = nil) then
  begin
    Exit;
  end;
  Index := FList.Selected.Index;
  if (Index < 0) or (Index > High(FShownSaved)) then
  begin
    Exit;
  end;
  mSource := FSource;
  Item := FShownSaved[Index];
  // Die Quelle öffnet Projekt und Datei: nicht im eigenen Ereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.OpenSaved(Item);
    end);
end;

{ TAtlasContinueRecentView }

constructor TAtlasContinueRecentView.Create(AFrame: TAtlasWelcomeSectionFrame);
begin
  inherited Create(AFrame);
  FFrame := AFrame;
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
  FBox.OnMouseDown := BoxMouseDown;
  FBox.OnMouseLeave := BoxMouseLeave;

  // Schnellaktionen (#764): Knopfleiste, Tastatur und Kontextmenü der Zeilen.
  FMenuRow := -1;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FResumeItem := TMenuItem.Create(Self);
  FResumeItem.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueResume);
  FResumeItem.Default := True;
  FResumeItem.OnClick := ResumeClick;
  FMenu.Items.Add(FResumeItem);
  FBox.PopupMenu := FMenu;
  FQuick := TAtlasQuickActionsBar.Create(Self, FBox, AFrame.Body);
  FQuick.OnScale :=
    function(AValue: Integer): Integer
    begin
      Result := AFrame.ScaleValue(AValue);
    end;
  FQuick.OnOpenRow := QuickOpenRow;
  FQuick.OnRowMenu := QuickRowMenu;
  FQuick.AttachMenu(FMenu);
end;

procedure TAtlasContinueRecentView.Fill;
begin
  FEntries := nil;
  FIncoming := Default(TAtlasContinueIncoming);
  FQuerying := False;
  FNotice := '';
  if FSource <> nil then
  begin
    FEntries := FSource.Entries;
    FIncoming := FSource.Incoming;
    FQuerying := FSource.IncomingQuerying;
    FNotice := FSource.Notice;
  end;
  // Die Rechtecke der Schaltflächen entstehen beim Zeichnen.
  FButtonRects := nil;
  FHintKey := '';
  FQuick.SetRows(ProjectNames(FEntries));
  FBox.Invalidate;
end;

function TAtlasContinueRecentView.ContentHeight: Integer;
var
  mRows, mLines: Integer;
begin
  mRows := Length(FEntries);
  if mRows < 1 then
  begin
    mRows := 1;
  end;
  mLines := IncomingLines(Self);
  if FNotice <> '' then
  begin
    Inc(mLines);
  end;
  Result := mRows * FFrame.ScaleValue(RowHeight) + mLines * FFrame.ScaleValue(LineHeight) + FFrame.ScaleValue(Indent);
  if mLines > 0 then
  begin
    Inc(Result, FFrame.ScaleValue(Indent));
  end;
end;

procedure TAtlasContinueRecentView.QuickOpenRow(ARow: Integer);
var
  Hit: TAtlasContinueHit;
begin
  // Enter ohne Knopf setzt fort (wie „Fortsetzen“).
  Hit.Row := ARow;
  Hit.Button := True;
  Hit.Commit := -1;
  ClickAt(Hit);
end;

procedure TAtlasContinueRecentView.QuickRowMenu(ARow: Integer);
var
  Position: TPoint;
begin
  if (ARow < 0) or (ARow > High(FEntries)) then
  begin
    Exit;
  end;
  Position := FBox.ClientToScreen(Point(FFrame.ScaleValue(Indent), RowTop(ARow) + FFrame.ScaleValue(RowHeight) div 2));
  FMenu.PopupComponent := FBox;
  FMenu.Popup(Position.X, Position.Y);
end;

procedure TAtlasContinueRecentView.MenuPopup(Sender: TObject);
var
  Position: TPoint;
begin
  Position := FBox.ScreenToClient(FMenu.PopupPoint);
  FMenuRow := HitTest(Position.X, Position.Y).Row;
  FResumeItem.Enabled := FMenuRow >= 0;
  // Schnellaktionen der Zeile: nur eingestellte Knöpfe, gesperrte grau.
  FQuick.PrepareMenu(FMenuRow);
end;

procedure TAtlasContinueRecentView.ResumeClick(Sender: TObject);
begin
  QuickOpenRow(FMenuRow);
end;

procedure TAtlasContinueRecentView.LayoutButtons;
var
  Row, mWidth, mTop, Right: Integer;
  Canvas: TCanvas;
  mText: string;
begin
  // „Fortsetzen“ rechts, mittig in der Zeile; die Rechtecke dienen auch dem Treffertest. Nur beim Zeichnen.
  SetLength(FButtonRects, Length(FEntries));
  Canvas := FBox.Canvas;
  Canvas.Font.Assign(FFrame.Font);
  mText := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueResume);
  Right := FBox.Width - FFrame.ScaleValue(Indent);
  for Row := 0 to High(FEntries) do
  begin
    mWidth := Canvas.TextWidth(mText) + 2 * FFrame.ScaleValue(ButtonPadding);
    mTop := RowTop(Row) + (FFrame.ScaleValue(RowHeight) - FFrame.ScaleValue(ButtonHeight)) div 2;
    FButtonRects[Row] := Rect(Right - mWidth, mTop, Right, mTop + FFrame.ScaleValue(ButtonHeight));
  end;
end;

function TAtlasContinueRecentView.RowTop(ARow: Integer): Integer;
begin
  Result := FFrame.ScaleValue(Indent) div 2 + ARow * FFrame.ScaleValue(RowHeight);
end;

function TAtlasContinueRecentView.IncomingTop: Integer;
var
  Rows: Integer;
begin
  Rows := Length(FEntries);
  if Rows < 1 then
  begin
    Rows := 1;
  end;
  Result := RowTop(Rows) + FFrame.ScaleValue(Indent);
end;

function TAtlasContinueRecentView.HitTest(X, Y: Integer): TAtlasContinueHit;
var
  Line: Integer;
begin
  Result.Row := -1;
  Result.Button := False;
  Result.Commit := -1;
  Result.Login := False;
  if Length(FEntries) = 0 then
  begin
    Exit;
  end;
  if (Y >= RowTop(0)) and (Y < RowTop(Length(FEntries))) then
  begin
    Result.Row := (Y - RowTop(0)) div FFrame.ScaleValue(RowHeight);
    if (Result.Row >= 0) and (Result.Row <= High(FButtonRects)) then
    begin
      Result.Button := FButtonRects[Result.Row].Contains(Point(X, Y));
    end;
    Exit;
  end;
  if not ShowsIncoming(Self) or (Y < IncomingTop) then
  begin
    Exit;
  end;
  // Zeile 0 ist die Überschrift, danach die Commits.
  Line := (Y - IncomingTop) div FFrame.ScaleValue(LineHeight) - 1;
  if (Line >= 0) and (Line <= High(FIncoming.Commits)) then
  begin
    Result.Commit := Line;
  end;
  // Hinweis „Anmeldung nötig“: nach den Commits (bzw. „Keine …“) und „… weitere“.
  if FIncoming.LoginNeeded and (Line = LoginLine(FIncoming)) then
  begin
    Result.Login := True;
  end;
end;

procedure TAtlasContinueRecentView.ClickAt(const AHit: TAtlasContinueHit);
var
  mSource: IAtlasContinueSource;
  Project: string;
  Commit: TAtlasContinueCommit;
begin
  if FSource = nil then
  begin
    Exit;
  end;
  mSource := FSource;
  if AHit.Button and (AHit.Row >= 0) and (AHit.Row <= High(FEntries)) then
  begin
    Project := FEntries[AHit.Row].Project;
    // Die Quelle füllt den Bereich danach neu: nicht im eigenen Mausereignis.
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      begin
        mSource.Resume(Project);
      end);
    Exit;
  end;
  if AHit.Login then
  begin
    Project := FIncoming.Project;
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      begin
        mSource.ShowServerAccess(Project);
      end);
    Exit;
  end;
  if (AHit.Commit >= 0) and (AHit.Commit <= High(FIncoming.Commits)) then
  begin
    Project := FIncoming.Project;
    Commit := FIncoming.Commits[AHit.Commit];
    TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
      procedure
      begin
        mSource.ShowCommit(Project, Commit);
      end);
  end;
end;

procedure TAtlasContinueRecentView.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  // Knöpfe der Schnellaktionen (#764) handeln selbst.
  if (Button = mbLeft) and not FQuick.ClickAt(X, Y) then
  begin
    ClickAt(HitTest(X, Y));
  end;
end;

procedure TAtlasContinueRecentView.BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  // Die Tastatur der Schnellaktionen übernimmt Zeile und Fokus (#764).
  FQuick.MouseDown(HitTest(X, Y).Row);
end;

procedure TAtlasContinueRecentView.BoxMouseLeave(Sender: TObject);
begin
  FQuick.MouseLeave;
  FHintKey := '';
end;

procedure TAtlasContinueRecentView.BoxPaint(Sender: TObject);
var
  mPainter: TContinuePainter;
begin
  mPainter.View := Self;
  mPainter.Canvas := FBox.Canvas;
  mPainter.Colors.Text := StyleServices(FFrame).GetSystemColor(clWindowText);
  mPainter.Colors.Muted := StyleServices(FFrame).GetSystemColor(clGrayText);
  mPainter.Colors.Line := StyleServices(FFrame).GetSystemColor(clBtnShadow);
  mPainter.Colors.Link := StyleServices(FFrame).GetSystemColor(clHotLight);
  mPainter.Stamp := TAtlasContinueTexts.NowUtc;
  mPainter.Active := FQuick.ActiveRow;
  mPainter.Paint;
end;

/// <summary>Tooltip an der Stelle des Treffers AHit; QuickHint ist der Tooltip eines Knopfs ('' = keiner).</summary>
function ContinueHint(AView: TAtlasContinueRecentView; const AHit: TAtlasContinueHit; const AQuickHint: string): string;
begin
  Result := '';
  if AQuickHint <> '' then
  begin
    Result := AQuickHint;
  end
  else if AHit.Row >= 0 then
  begin
    // Stand der letzten Schnellaktion samt Grund (#764).
    Result := TAtlasContinueTexts.HintFor(AView.FEntries[AHit.Row]) +
      TAtlasQuickRowTexts.HintSuffix(AView.FQuick, AHit.Row);
  end
  else if AHit.Commit >= 0 then
  begin
    Result := TAtlasContinueTexts.CommitHint(AView.FIncoming.Commits[AHit.Commit]);
  end;
end;

procedure TAtlasContinueRecentView.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  mHit: TAtlasContinueHit;
  mKey, mHint: string;
  mQuickRow, mQuickButton: Integer;
  mOnMenu: Boolean;
begin
  mHit := HitTest(X, Y);
  FQuick.MouseMove(mHit.Row, X, Y);
  if not FQuick.HitTest(X, Y, mQuickRow, mQuickButton, mOnMenu) then
  begin
    mQuickButton := -1;
  end;
  FBox.Cursor := crDefault;
  if mHit.Button or (mHit.Commit >= 0) or mHit.Login or (mQuickButton >= 0) then
  begin
    FBox.Cursor := crHandPoint;
  end;
  mKey := Format('%d/%d/%d', [mHit.Row, mHit.Commit, mQuickButton]);
  if mKey = FHintKey then
  begin
    Exit;
  end;
  FHintKey := mKey;
  if (mQuickButton < 0) or not FQuick.HintAt(X, Y, mHint) then
  begin
    mHint := '';
  end;
  FBox.Hint := ContinueHint(Self, mHit, mHint);
  Application.CancelHint;
end;

{ TAtlasWelcomeContinueFrame }

procedure TAtlasWelcomeContinueFrame.CreateWnd;
begin
  inherited;
  if FTabs.Tabs.Count = 0 then
  begin
    FTabs.Tabs.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueTabRecent));
    FTabs.Tabs.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeContinueTabSaved));
    FTabs.TabIndex := PageRecent;
  end;
end;

constructor TAtlasWelcomeContinueFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTabs := TTabControl.Create(Self);
  FTabs.Parent := Body;
  FTabs.Align := alTop;
  FTabs.Height := ScaleValue(TabHeight);
  // Reiter erst in CreateWnd: TTabControl braucht dafür ein Fenster („kein übergeordnetes Fenster“).
  FTabs.OnChange := TabsChange;

  FRecent := TAtlasContinueRecentView.Create(Self);
  FRecent.Parent := Body;
  FRecent.Align := alClient;

  FSavedPage := TAtlasContinueSavedPage.Create(Self);
  FSavedPage.Parent := Body;
  FSavedPage.Align := alClient;
  FSavedPage.Visible := False;
  FSavedPage.AddColumns([ScaleValue(80), ScaleValue(220), ScaleValue(140), ScaleValue(120)]);
end;

function TAtlasWelcomeContinueFrame.GetQuickActions: IAtlasQuickActionsSource;
begin
  Result := FRecent.Quick.Source;
end;

procedure TAtlasWelcomeContinueFrame.SetQuickActions(const AValue: IAtlasQuickActionsSource);
begin
  FRecent.Quick.Source := AValue;
  UpdateContent;
end;

procedure TAtlasWelcomeContinueFrame.SetSource(const AValue: IAtlasContinueSource);
begin
  FSource := AValue;
  FRecent.Source := AValue;
  FSavedPage.Source := AValue;
  FSavedPage.Loaded := False;
  UpdateContent;
  if FSource <> nil then
  begin
    FSource.Shown;
  end;
end;

function TAtlasWelcomeContinueFrame.TabsShown: Boolean;
begin
  Result := (FSource <> nil) and FSource.SavedEnabled;
end;

function TAtlasWelcomeContinueFrame.GetPage: Integer;
begin
  Result := PageRecent;
  if TabsShown and (FTabs.TabIndex = PageSaved) then
  begin
    Result := PageSaved;
  end;
end;

procedure TAtlasWelcomeContinueFrame.SetPage(AValue: Integer);
begin
  if (AValue = PageSaved) and TabsShown then
  begin
    FTabs.TabIndex := PageSaved;
  end
  else
  begin
    FTabs.TabIndex := PageRecent;
  end;
  ShowPage;
end;

procedure TAtlasWelcomeContinueFrame.TabsChange(Sender: TObject);
begin
  ShowPage;
end;

procedure TAtlasWelcomeContinueFrame.ShowPage;
var
  mSaved: Boolean;
begin
  FTabs.Visible := TabsShown;
  mSaved := Page = PageSaved;
  if mSaved and not FSavedPage.Loaded then
  begin
    FSavedPage.LoadSaved;
  end;
  FSavedPage.Visible := mSaved;
  FRecent.Visible := not mSaved;
  // Die Tastatur der Schnellaktionen gilt nur für „Zuletzt“.
  FRecent.Quick.Sink.Visible := not mSaved;
  HeightChanged;
end;

procedure TAtlasWelcomeContinueFrame.UpdateContent;
var
  mHeight: Integer;
begin
  // Ohne Fenster später: CreateWnd bzw. die Tafel ruft UpdateContent nach dem Einhängen.
  if not HasWindow then
  begin
    Exit;
  end;
  mHeight := FRecent.ContentHeight;
  FRecent.Fill;
  FTabs.Visible := TabsShown;
  // „Gemerkt“ neu lesen, wenn der Reiter offen ist; sonst erst beim Wechsel dorthin.
  FSavedPage.Loaded := False;
  if Page = PageSaved then
  begin
    FSavedPage.LoadSaved;
  end;
  FSavedPage.Visible := Page = PageSaved;
  FRecent.Visible := Page = PageRecent;
  FRecent.Quick.Sink.Visible := Page = PageRecent;
  inherited;
  // Andere Höhe: Der Frame „Atlas“ ordnet die Spalten neu.
  if mHeight <> FRecent.ContentHeight then
  begin
    HeightChanged;
  end;
end;

function TAtlasWelcomeContinueFrame.BodyHeight: Integer;
begin
  Result := 0;
  if TabsShown then
  begin
    Inc(Result, ScaleValue(TabHeight));
  end;
  if Page = PageSaved then
  begin
    Inc(Result, ScaleValue(FilterHeight) + (SavedRows + 1) * ScaleValue(LineHeight) + ScaleValue(Indent));
  end
  else
  begin
    Inc(Result, FRecent.ContentHeight);
  end;
end;

end.
