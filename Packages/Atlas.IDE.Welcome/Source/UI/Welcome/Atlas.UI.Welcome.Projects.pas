unit Atlas.UI.Welcome.Projects;

// Bereich „Projekte“ der Willkommensseite (#592), ohne Open Tools API.
// Je Projekt eine Zeile, selbst gezeichnet (eigene Marken sind mit den
// Listen der IDE nicht möglich):
//   ● Name  Branch                        [Build 0/0/0] [3 geändert] [↑1 ↓0]
//     C:\…\Projekte\Demo.dproj · geöffnet 14.10.2026 17:45 · Stand vom …
// Der Punkt vorn trägt die schlimmste Stufe der Marken (grün/gelb/rot). Der
// Tooltip nennt Build, Prüfung, Versionsverwaltung und Regeltreffer im
// Einzelnen. Klick auf die Zeile öffnet das Projekt, Klick auf eine rote
// Marke öffnet es und springt zur ersten Meldung; das Kontextmenü bietet
// „Öffnen“, „Ordner öffnen“ und „Aus Liste entfernen“ (nur dieser Bereich),
// mit Arbeitskopie „Branch anlegen …“ (#1288) und mit vcs.externals.show
// „Arbeitskopien …“ (#1292: Tabelle mit Externals bzw. Submodulen).
// Mit Projektverlauf (#758, Selectable) wählt ein Klick die Zeile für den
// Verlauf (hinterlegt), Doppelklick öffnet; rote Marken springen weiter.
// Schnellaktionen (#764, Atlas.UI.Welcome.QuickActions): In der Zeile unter
// der Maus bzw. in der mit der Tastatur gewählten Zeile (hinterlegt) stehen
// statt der Marken die Knöpfe „Öffnen und bauen“, „Tests“, „Startprofil ▾“,
// „Pull“, „Ordner“, „Konsole“; ein laufender oder beendeter Lauf steht als
// Marke links der übrigen („baut … 12 s“, „Tests: 57 ok“). Das Kontextmenü
// bietet dieselben Aktionen samt „Bauen mit“ und „Starten mit“. Tastatur:
// ↑/↓ Zeile (mit Projektverlauf zugleich die Auswahl), ←/→ Knopf, Enter
// führt aus bzw. öffnet, Strg+B baut, Strg+T testet.
// Daten und Aktionen kommen über IAtlasProjectsSource aus der IDE-Schicht;
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
  Vcl.Menus,
  Vcl.Graphics,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.Projects,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.QuickActions;

type
  IAtlasProjectsSource = interface
    ['{4E7C2A19-6B3D-4F80-9C51-8A2D0E6F3B47}']
    /// <summary>Gezeigte Projekte mit Zusammenfassung und Stand der Versionsverwaltung.</summary>
    function Entries: TAtlasProjectEntries;
    procedure Open(const AProject: string);
    /// <summary>Projekt öffnen und zu ATarget springen (Fehler-Marke).</summary>
    procedure OpenAt(const AProject: string; const ATarget: TAtlasProjectLocation);
    procedure OpenFolder(const AProject: string);
    /// <summary>„Branch anlegen …“ (#1288): Dialog für die Arbeitskopie von AProject.</summary>
    procedure CreateBranch(const AProject: string);
    /// <summary>„Arbeitskopien …“ (#1292): Tabelle der Arbeitskopien von AProject (Wurzel, Externals,
    /// Submodule).</summary>
    procedure ShowWorkingCopies(const AProject: string);
    /// <summary>vcs.externals.show: Eintrag „Arbeitskopien …“ zeigen.</summary>
    function WorkingCopies: Boolean;
    /// <summary>„Aus Liste entfernen“: nur in diesem Bereich, die Liste der IDE bleibt.</summary>
    procedure Remove(const AProject: string);
    /// <summary>Der Bereich wird gezeigt: Versionsverwaltung bei Bedarf im Hintergrund frisch abfragen.</summary>
    procedure Shown;
    /// <summary>Klick wählt eine Zeile für den Projektverlauf (#758) statt sie zu öffnen.</summary>
    function Selectable: Boolean;
    /// <summary>Projekt für den Projektverlauf wählen (#758).</summary>
    procedure Select(const AProject: string);
    /// <summary>Gewähltes Projekt; '' = keins (der Verlauf zeigt dann das oberste).</summary>
    function Selected: string;
  end;

  TAtlasProjectsHit = record
    /// <summary>Zeile; -1 = keine.</summary>
    Row: Integer;
    /// <summary>Marke in der Zeile; -1 = keine.</summary>
    Pill: Integer;
  end;

  /// <summary>Texte und Farben des Bereichs „Projekte“, ohne Steuerelement.</summary>
  TAtlasProjectsTexts = class
  public
    /// <summary>Text einer Marke, z. B. „Build 0/0/0“ oder „2 Fehler“.</summary>
    class function PillText(const APill: TAtlasProjectPill): string; static;
    class function PillColor(ALevel: TAtlasProjectPillLevel): TColor; static;
    /// <summary>Zweite Zeile: gekürzter Pfad, letztes Öffnen und „Stand vom …“.</summary>
    class function DetailText(const AEntry: TAtlasProjectEntry): string; static;
    /// <summary>Tooltip mit allen Angaben; letzte Zeile nennt den Klick (öffnet bzw. mit ASelectable wählt).
    /// </summary>
    class function HintFor(const AEntry: TAtlasProjectEntry): string; overload; static;
    class function HintFor(const AEntry: TAtlasProjectEntry; ASelectable: Boolean): string; overload; static;
    /// <summary>UTC-Zeit als lokale Kurzform; '' für 0.</summary>
    class function LocalText(AUtc: TDateTime): string; static;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Einträge des Kontextmenüs, die die Zeile an die Quelle geben.</summary>
  TAtlasProjectsMenuAction = (Open, OpenFolder, CreateBranch, WorkingCopies, Remove);
{$SCOPEDENUMS OFF}

  TAtlasProjectsMenuEvent = procedure(AAction: TAtlasProjectsMenuAction) of object;

  /// <summary>Kontextmenü einer Zeile: „Öffnen“, „Ordner öffnen“, „Branch anlegen …“, „Arbeitskopien …“, „Aus
  /// Liste entfernen“; dazu hängen die Schnellaktionen ihre Einträge an.</summary>
  TAtlasProjectsMenu = class(TPopupMenu)
  private
    FOpenItem: TMenuItem;
    FOpenFolderItem: TMenuItem;
    FCreateBranchItem: TMenuItem;
    FWorkingCopiesItem: TMenuItem;
    FRemoveItem: TMenuItem;
    FRow: Integer;
    FOnAction: TAtlasProjectsMenuEvent;
    function NewItem(AAction: TAtlasProjectsMenuAction; const ACaption: string): TMenuItem;
    procedure ItemClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    property OpenItem: TMenuItem read FOpenItem;
    property OpenFolderItem: TMenuItem read FOpenFolderItem;
    property CreateBranchItem: TMenuItem read FCreateBranchItem;
    property WorkingCopiesItem: TMenuItem read FWorkingCopiesItem;
    property RemoveItem: TMenuItem read FRemoveItem;
    /// <summary>Zeile des zuletzt geöffneten Kontextmenüs; -1 = keine.</summary>
    property Row: Integer read FRow write FRow;
    /// <summary>Gewählter Eintrag; die Zeile steht in Row.</summary>
    property OnAction: TAtlasProjectsMenuEvent read FOnAction write FOnAction;
  end;

  TAtlasWelcomeProjectsFrame = class(TAtlasWelcomeSectionFrame)
  public const
    RowHeight = 44;
    Indent = 8;
    PillHeight = 18;
    PillPadding = 6;
    PillGap = 6;
    DotSize = 10;
    PathLength = 60;
  private
    FSource: IAtlasProjectsSource;
    FBox: TAtlasWelcomeCanvas;
    FEntries: TAtlasProjectEntries;
    FPills: TArray<TArray<TAtlasProjectPill>>;
    FPillRects: TArray<TArray<TRect>>;
    FMenu: TAtlasProjectsMenu;
    // Zeile und Knopf des gezeigten Tooltips.
    FHintKey: string;
    FQuick: TAtlasQuickActionsBar;
    // Lage des letzten Drückens für den Doppelklick (#758) und ob es der zweite Klick eines Doppelklicks war.
    FLastMouse: TPoint;
    FDoubleDown: Boolean;
    procedure SetSource(const AValue: IAtlasProjectsSource);
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BoxDblClick(Sender: TObject);
    procedure BoxMouseLeave(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure MenuAction(AAction: TAtlasProjectsMenuAction);
    procedure LayoutPills;
    function RowTop(ARow: Integer): Integer;
    function GetQuickActions: IAtlasQuickActionsSource;
    procedure SetQuickActions(const AValue: IAtlasQuickActionsSource);
    procedure QuickOpenRow(ARow: Integer);
    procedure QuickSelectRow(ARow: Integer);
    procedure QuickRowMenu(ARow: Integer);
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    /// <summary>Zeile und Marke an X, Y (Koordinaten der Zeichenfläche).</summary>
    function HitTest(X, Y: Integer): TAtlasProjectsHit;
    /// <summary>Klick wie mit der Maus (auch für Tests).</summary>
    procedure ClickAt(const AHit: TAtlasProjectsHit);
    /// <summary>Doppelklick wie mit der Maus: öffnet die Zeile (auch für Tests).</summary>
    procedure DoubleClickAt(const AHit: TAtlasProjectsHit);
    /// <summary>Zeile des gewählten Projekts (#758); -1 = keine.</summary>
    function SelectedRow: Integer;
    property Source: IAtlasProjectsSource read FSource write SetSource;
    /// <summary>Schnellaktionen (#764); nil = keine Knöpfe.</summary>
    property QuickActions: IAtlasQuickActionsSource read GetQuickActions write SetQuickActions;
    /// <summary>Knopfleiste, Stand und Tastatur der Schnellaktionen (auch für Tests).</summary>
    property Quick: TAtlasQuickActionsBar read FQuick;
    property Entries: TAtlasProjectEntries read FEntries;
    property PaintBox: TAtlasWelcomeCanvas read FBox;
    property Menu: TAtlasProjectsMenu read FMenu;
  end;

implementation

uses
  System.UITypes,
  Atlas.Core.Welcome.QuickActions,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.DateUtils,
  Vcl.Themes,
  Atlas.UI.Welcome.Strings;

type
  /// <summary>Zeichnet die Zeilen des Bereichs: Punkt, Name, Branch, zweite Zeile, Stand der Schnellaktion und
  /// Marken bzw. in der aktiven Zeile die Knöpfe.</summary>
  TProjectsPainter = record
  private
    FFrame: TAtlasWelcomeProjectsFrame;
    FDot: Integer;
    FRadius: Integer;
    FSelected: Integer;
    FActive: Integer;
    function Scaled(AValue: Integer): Integer;
    /// <summary>Rechte Grenze der Texte: die Knopfleiste der aktiven Zeile bzw. der Rand.</summary>
    function TextLimit(ARow, ATop: Integer): Integer;
    procedure PaintMarker(ARow, ATop: Integer);
    procedure PaintTexts(ARow, ATop, ALimit: Integer);
    procedure PaintState(ARow, ATop: Integer);
    procedure PaintPills(ARow: Integer);
  public
    Canvas: TCanvas;
    TextColor: TColor;
    MutedColor: TColor;
    constructor Create(AFrame: TAtlasWelcomeProjectsFrame);
    procedure PaintRow(ARow: Integer);
  end;

function ProjectNames(const AEntries: TAtlasProjectEntries): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AEntries));
  for mIndex := 0 to High(AEntries) do
  begin
    Result[mIndex] := AEntries[mIndex].Project;
  end;
end;

procedure AddFirstHint(ALines: TStrings; const ALocation: TAtlasProjectLocation);
begin
  if not ALocation.IsEmpty then
  begin
    ALines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsHintFirst,
      [ExtractFileName(ALocation.FileName), ALocation.Line, Trim(ALocation.Code + ' ' + ALocation.Text)]));
  end;
end;

/// <summary>Zeilen der Versionsverwaltung im Tooltip: Art, Branch, Revision, Änderungen, Abstand, Stand.</summary>
procedure AddVcsHint(ALines: TStrings; const AEntry: TAtlasProjectEntry);
var
  mVcs: TAtlasProjectVcs;
begin
  mVcs := AEntry.Summary.Vcs;
  if not mVcs.InWorkingCopy then
  begin
    Exit;
  end;
  ALines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsHintVcs,
    [UpperCase(mVcs.Kind), AEntry.Branch, mVcs.Revision]));
  if mVcs.Changed >= 0 then
  begin
    ALines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsHintChanged, [mVcs.Changed]));
  end;
  if (mVcs.Ahead >= 0) and (mVcs.Behind >= 0) then
  begin
    ALines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsHintSync, [mVcs.Ahead, mVcs.Behind]));
  end;
  if AEntry.VcsStale and (mVcs.At > 0) then
  begin
    ALines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsStale,
      [TAtlasProjectsTexts.LocalText(mVcs.At)]));
  end;
end;

/// <summary>Zeilen zu Build, Prüfung und Regeltreffern im Tooltip.</summary>
procedure AddCheckHint(ALines: TStrings; const ASummary: TAtlasProjectSummary);
begin
  if ASummary.Build.Known then
  begin
    ALines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsHintBuild,
      [TAtlasProjectsTexts.LocalText(ASummary.Build.At), ASummary.Build.Kind, ASummary.Build.Configuration,
      ASummary.Build.Platform, ASummary.Build.Errors, ASummary.Build.Warnings, ASummary.Build.Hints]));
    AddFirstHint(ALines, ASummary.Build.First);
  end
  else
  begin
    ALines.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsHintNoBuild));
  end;
  if ASummary.Check.Known then
  begin
    ALines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsHintCheck,
      [TAtlasProjectsTexts.LocalText(ASummary.Check.At), ASummary.Check.Errors]));
    AddFirstHint(ALines, ASummary.Check.First);
  end;
  if ASummary.Rules.Known then
  begin
    ALines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsHintRules, [ASummary.Rules.NewHits]));
  end;
end;

/// <summary>Tooltip der Zeile ARow samt Stand der letzten Schnellaktion (#764); '' ohne Zeile.</summary>
function RowHint(AFrame: TAtlasWelcomeProjectsFrame; ARow: Integer): string;
begin
  Result := '';
  if ARow >= 0 then
  begin
    Result := TAtlasProjectsTexts.HintFor(AFrame.FEntries[ARow], (AFrame.FSource <> nil) and
      AFrame.FSource.Selectable) + TAtlasQuickRowTexts.HintSuffix(AFrame.FQuick, ARow);
  end;
end;

procedure RunMenuAction(const ASource: IAtlasProjectsSource; AAction: TAtlasProjectsMenuAction;
  const AProject: string);
begin
  case AAction of
    TAtlasProjectsMenuAction.Open:
      ASource.Open(AProject);
    TAtlasProjectsMenuAction.OpenFolder:
      ASource.OpenFolder(AProject);
    TAtlasProjectsMenuAction.CreateBranch:
      ASource.CreateBranch(AProject);
    TAtlasProjectsMenuAction.WorkingCopies:
      ASource.ShowWorkingCopies(AProject);
  else
    ASource.Remove(AProject);
  end;
end;

{ TAtlasProjectsMenu }

constructor TAtlasProjectsMenu.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRow := -1;
  FOpenItem := NewItem(TAtlasProjectsMenuAction.Open,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsOpen));
  FOpenItem.Default := True;
  FOpenFolderItem := NewItem(TAtlasProjectsMenuAction.OpenFolder,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsOpenFolder));
  // Branch anlegen (#1288): nur für Zeilen mit Arbeitskopie.
  FCreateBranchItem := NewItem(TAtlasProjectsMenuAction.CreateBranch,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsCreateBranch));
  // Arbeitskopien (#1292): Wurzel, Externals und Submodule; nur mit vcs.externals.show.
  FWorkingCopiesItem := NewItem(TAtlasProjectsMenuAction.WorkingCopies,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsWorkingCopies));
  FRemoveItem := NewItem(TAtlasProjectsMenuAction.Remove,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsRemove));
end;

function TAtlasProjectsMenu.NewItem(AAction: TAtlasProjectsMenuAction; const ACaption: string): TMenuItem;
begin
  Result := TMenuItem.Create(Self);
  Result.Caption := ACaption;
  Result.Tag := Ord(AAction);
  Result.OnClick := ItemClick;
  Items.Add(Result);
end;

procedure TAtlasProjectsMenu.ItemClick(Sender: TObject);
begin
  if Assigned(FOnAction) then
  begin
    FOnAction(TAtlasProjectsMenuAction((Sender as TMenuItem).Tag));
  end;
end;

{ TProjectsPainter }

constructor TProjectsPainter.Create(AFrame: TAtlasWelcomeProjectsFrame);
begin
  FFrame := AFrame;
  Canvas := AFrame.FBox.Canvas;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(AFrame.Font);
  // Farben des IDE-Themas (hell oder dunkel).
  TextColor := StyleServices(AFrame).GetSystemColor(clWindowText);
  MutedColor := StyleServices(AFrame).GetSystemColor(clGrayText);
  Canvas.Font.Color := TextColor;
  FDot := Scaled(TAtlasWelcomeProjectsFrame.DotSize);
  FRadius := Scaled(TAtlasWelcomeProjectsFrame.PillHeight);
  FSelected := AFrame.SelectedRow;
  FActive := AFrame.FQuick.ActiveRow;
end;

function TProjectsPainter.Scaled(AValue: Integer): Integer;
begin
  Result := FFrame.ScaleValue(AValue);
end;

function TProjectsPainter.TextLimit(ARow, ATop: Integer): Integer;
var
  mWidth: Integer;
begin
  mWidth := FFrame.FBox.Width;
  Result := mWidth - Scaled(TAtlasWelcomeProjectsFrame.Indent);
  if ARow = FActive then
  begin
    Canvas.Font.Assign(FFrame.Font);
    Canvas.Font.Size := FFrame.Font.Size - 1;
    Result := FFrame.FQuick.LayoutRow(Canvas, ARow, Rect(Scaled(TAtlasWelcomeProjectsFrame.Indent) + FDot +
      Scaled(80), ATop, mWidth - Scaled(TAtlasWelcomeProjectsFrame.Indent),
      ATop + Scaled(TAtlasWelcomeProjectsFrame.RowHeight) - Scaled(2))) - Scaled(TAtlasWelcomeProjectsFrame.Indent);
  end;
end;

procedure TProjectsPainter.PaintRow(ARow: Integer);
var
  mTop, mLimit: Integer;
begin
  mTop := FFrame.RowTop(ARow);
  // Schnellaktionen (#764): aktive Zeile hinterlegt, Fokusrahmen der Tastatur.
  FFrame.FQuick.PaintBackground(Canvas, ARow, Rect(0, mTop, FFrame.FBox.Width,
    mTop + Scaled(TAtlasWelcomeProjectsFrame.RowHeight) - Scaled(2)));
  // Rechte Grenze für Name, Branch und zweite Zeile: die Knopfleiste der aktiven Zeile bzw. die Marken.
  mLimit := TextLimit(ARow, mTop);
  PaintMarker(ARow, mTop);
  PaintTexts(ARow, mTop, mLimit);
  // Aktive Zeile: Knöpfe statt Marken.
  Canvas.Font.Size := FFrame.Font.Size - 1;
  if ARow = FActive then
  begin
    FFrame.FQuick.PaintRow(Canvas, ARow);
    Exit;
  end;
  PaintState(ARow, mTop);
  PaintPills(ARow);
end;

procedure TProjectsPainter.PaintMarker(ARow, ATop: Integer);
var
  mLeft: Integer;
begin
  // Für den Projektverlauf gewählte Zeile hinterlegen (#758), in der Markierungsfarbe des Themas.
  if ARow = FSelected then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := StyleServices(FFrame).GetSystemColor(clHighlight);
    Canvas.Pen.Color := Canvas.Brush.Color;
    Canvas.FillRect(Rect(0, ATop, Scaled(3), ATop + Scaled(TAtlasWelcomeProjectsFrame.RowHeight) - Scaled(2)));
    Canvas.Brush.Style := bsClear;
  end;
  // Punkt mit der schlimmsten Stufe; ohne Angaben grau.
  mLeft := Scaled(TAtlasWelcomeProjectsFrame.Indent);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TAtlasProjectsTexts.PillColor(TAtlasWelcomeProjects.Level(FFrame.FPills[ARow]));
  Canvas.Pen.Color := Canvas.Brush.Color;
  Canvas.Ellipse(mLeft, ATop + Scaled(6), mLeft + FDot, ATop + Scaled(6) + FDot);
  Canvas.Brush.Style := bsClear;
end;

procedure TProjectsPainter.PaintTexts(ARow, ATop, ALimit: Integer);
var
  mEntry: TAtlasProjectEntry;
  mLeft, mTextLeft: Integer;
begin
  mEntry := FFrame.FEntries[ARow];
  mTextLeft := Scaled(TAtlasWelcomeProjectsFrame.Indent) + FDot + Scaled(6);
  mLeft := mTextLeft;
  Canvas.Font.Assign(FFrame.Font);
  Canvas.Font.Color := TextColor;
  Canvas.Font.Style := [fsBold];
  Canvas.TextRect(Rect(mLeft, ATop + Scaled(3), ALimit, ATop + Scaled(21)), mLeft, ATop + Scaled(3), mEntry.Name);
  Inc(mLeft, Canvas.TextWidth(mEntry.Name) + Scaled(8));
  Canvas.Font.Style := [];
  if (mEntry.Branch <> '') and (mLeft < ALimit) then
  begin
    Canvas.Font.Color := MutedColor;
    Canvas.TextRect(Rect(mLeft, ATop + Scaled(3), ALimit, ATop + Scaled(21)), mLeft, ATop + Scaled(3),
      mEntry.Branch);
  end;
  // Zweite Zeile.
  Canvas.Font.Assign(FFrame.Font);
  Canvas.Font.Color := MutedColor;
  Canvas.TextRect(Rect(mTextLeft, ATop + Scaled(23), ALimit, ATop + Scaled(41)), mTextLeft, ATop + Scaled(23),
    TAtlasProjectsTexts.DetailText(mEntry));
end;

procedure TProjectsPainter.PaintState(ARow, ATop: Integer);
var
  mState: TAtlasQuickActionState;
  mText: string;
  mRight: Integer;
  mRect: TRect;
begin
  // Stand der letzten Schnellaktion links der Marken („baut … 12 s“, „Tests: 57 ok“).
  mState := FFrame.FQuick.StateOf(ARow);
  mText := TAtlasQuickRowTexts.StateText(FFrame.FQuick, ARow);
  if mText = '' then
  begin
    Exit;
  end;
  mRight := FFrame.FBox.Width - Scaled(TAtlasWelcomeProjectsFrame.Indent);
  if Length(FFrame.FPillRects[ARow]) > 0 then
  begin
    mRight := FFrame.FPillRects[ARow][0].Left - Scaled(TAtlasWelcomeProjectsFrame.PillGap);
  end;
  mRect := Rect(mRight - Canvas.TextWidth(mText) - 2 * Scaled(TAtlasWelcomeProjectsFrame.PillPadding),
    ATop + Scaled(3), mRight, ATop + Scaled(3) + Scaled(TAtlasWelcomeProjectsFrame.PillHeight));
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TAtlasQuickActionTexts.StateColor(mState);
  Canvas.Pen.Color := Canvas.Brush.Color;
  Canvas.RoundRect(mRect.Left, mRect.Top, mRect.Right, mRect.Bottom, FRadius, FRadius);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := clWhite;
  Canvas.Font.Style := [];
  Canvas.TextOut(mRect.Left + Scaled(TAtlasWelcomeProjectsFrame.PillPadding),
    mRect.Top + (mRect.Height - Canvas.TextHeight(mText)) div 2, mText);
end;

procedure TProjectsPainter.PaintPills(ARow: Integer);
var
  mIndex: Integer;
  mPill: TAtlasProjectPill;
  mRect: TRect;
  mText: string;
begin
  for mIndex := 0 to High(FFrame.FPills[ARow]) do
  begin
    mPill := FFrame.FPills[ARow][mIndex];
    mRect := FFrame.FPillRects[ARow][mIndex];
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := TAtlasProjectsTexts.PillColor(mPill.Level);
    Canvas.Pen.Color := Canvas.Brush.Color;
    Canvas.RoundRect(mRect.Left, mRect.Top, mRect.Right, mRect.Bottom, FRadius, FRadius);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := clWhite;
    if mPill.Clickable then
    begin
      Canvas.Font.Style := [fsUnderline];
    end
    else
    begin
      Canvas.Font.Style := [];
    end;
    mText := TAtlasProjectsTexts.PillText(mPill);
    Canvas.TextOut(mRect.Left + Scaled(TAtlasWelcomeProjectsFrame.PillPadding),
      mRect.Top + (mRect.Height - Canvas.TextHeight(mText)) div 2, mText);
  end;
end;

{ TAtlasWelcomeProjectsFrame }

constructor TAtlasWelcomeProjectsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBox := TAtlasWelcomeCanvas.Create(Self);
  FBox.Parent := Body;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
  FBox.OnMouseDown := BoxMouseDown;
  FBox.OnDblClick := BoxDblClick;
  FBox.OnMouseLeave := BoxMouseLeave;
  FMenu := TAtlasProjectsMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FMenu.OnAction := MenuAction;
  FBox.PopupMenu := FMenu;
  // Schnellaktionen (#764): Knopfleiste, Tastatur und Einträge im Kontextmenü.
  FQuick := TAtlasQuickActionsBar.Create(Self, FBox, Body);
  FQuick.OnScale :=
    function(AValue: Integer): Integer
    begin
      Result := ScaleValue(AValue);
    end;
  FQuick.OnOpenRow := QuickOpenRow;
  FQuick.OnSelectRow := QuickSelectRow;
  FQuick.OnRowMenu := QuickRowMenu;
  FQuick.Menus.Attach(FMenu);
end;

function TAtlasWelcomeProjectsFrame.GetQuickActions: IAtlasQuickActionsSource;
begin
  Result := FQuick.Source;
end;

procedure TAtlasWelcomeProjectsFrame.SetQuickActions(const AValue: IAtlasQuickActionsSource);
begin
  FQuick.Source := AValue;
  UpdateContent;
end;

procedure TAtlasWelcomeProjectsFrame.QuickOpenRow(ARow: Integer);
var
  mSource: IAtlasProjectsSource;
  Project: string;
begin
  // Enter ohne Knopf öffnet (wie Doppelklick bzw. Klick ohne Projektverlauf).
  if (FSource = nil) or (ARow < 0) or (ARow > High(FEntries)) then
  begin
    Exit;
  end;
  mSource := FSource;
  Project := FEntries[ARow].Project;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.Open(Project);
    end);
end;

procedure TAtlasWelcomeProjectsFrame.QuickSelectRow(ARow: Integer);
var
  mSource: IAtlasProjectsSource;
  Project: string;
begin
  // Mit Projektverlauf (#758) wählen die Pfeiltasten auch das Projekt des Verlaufs.
  if (FSource = nil) or (ARow < 0) or (ARow > High(FEntries)) or not FSource.Selectable then
  begin
    Exit;
  end;
  mSource := FSource;
  Project := FEntries[ARow].Project;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.Select(Project);
    end);
end;

procedure TAtlasWelcomeProjectsFrame.QuickRowMenu(ARow: Integer);
var
  Position: TPoint;
begin
  if (ARow < 0) or (ARow > High(FEntries)) then
  begin
    Exit;
  end;
  Position := FBox.ClientToScreen(Point(ScaleValue(Indent), RowTop(ARow) + ScaleValue(RowHeight) div 2));
  FMenu.PopupComponent := FBox;
  FMenu.Popup(Position.X, Position.Y);
end;

procedure TAtlasWelcomeProjectsFrame.SetSource(const AValue: IAtlasProjectsSource);
begin
  FSource := AValue;
  UpdateContent;
  if FSource <> nil then
  begin
    FSource.Shown;
  end;
end;

procedure TAtlasWelcomeProjectsFrame.UpdateContent;
var
  Count, Index: Integer;
begin
  Count := Length(FEntries);
  FEntries := nil;
  if FSource <> nil then
  begin
    FEntries := FSource.Entries;
  end;
  SetLength(FPills, Length(FEntries));
  for Index := 0 to High(FEntries) do
  begin
    FPills[Index] := TAtlasWelcomeProjects.Pills(FEntries[Index]);
  end;
  // Die Rechtecke der Marken entstehen beim Zeichnen: Erst dann gibt es eine Zeichenfläche.
  FPillRects := nil;
  FHintKey := '';
  FQuick.SetRows(ProjectNames(FEntries));
  FBox.Invalidate;
  inherited;
  // Andere Anzahl Zeilen: Der Frame „Atlas“ ordnet die Spalten neu.
  if Count <> Length(FEntries) then
  begin
    HeightChanged;
  end;
end;

function TAtlasWelcomeProjectsFrame.BodyHeight: Integer;
var
  Rows: Integer;
begin
  Rows := Length(FEntries);
  if Rows < 1 then
  begin
    Rows := 1;
  end;
  Result := Rows * ScaleValue(RowHeight) + ScaleValue(Indent);
end;

function TAtlasWelcomeProjectsFrame.RowTop(ARow: Integer): Integer;
begin
  Result := ScaleValue(Indent) div 2 + ARow * ScaleValue(RowHeight);
end;

class function TAtlasProjectsTexts.PillText(const APill: TAtlasProjectPill): string;
begin
  case APill.Kind of
    TAtlasProjectPillKind.Build:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsBuild, [APill.A, APill.B, APill.C]);
    TAtlasProjectPillKind.BuildErrors:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsErrors, [APill.A]);
    TAtlasProjectPillKind.CheckErrors:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsCheckErrors, [APill.A]);
    TAtlasProjectPillKind.Changes:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsChanged, [APill.A]);
    TAtlasProjectPillKind.Sync:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsSync, [APill.A, APill.B]);
  else
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsRules, [APill.A]);
  end;
end;

class function TAtlasProjectsTexts.PillColor(ALevel: TAtlasProjectPillLevel): TColor;
begin
  // Kräftige Töne mit weißer Schrift: lesbar im hellen und im dunklen Thema.
  case ALevel of
    TAtlasProjectPillLevel.Good:
      Result := TColor($0043A02E);
    TAtlasProjectPillLevel.Warning:
      Result := TColor($001A8CC9);
    TAtlasProjectPillLevel.Error:
      Result := TColor($002E22CF);
  else
    Result := TColor($00817666);
  end;
end;

class function TAtlasProjectsTexts.LocalText(AUtc: TDateTime): string;
begin
  Result := '';
  if AUtc <= 0 then
  begin
    Exit;
  end;
  Result := FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(AUtc));
end;

class function TAtlasProjectsTexts.DetailText(const AEntry: TAtlasProjectEntry): string;
begin
  Result := TAtlasWelcomeProjects.ShortPath(AEntry.Project, TAtlasWelcomeProjectsFrame.PathLength);
  if AEntry.Summary.LastOpened > 0 then
  begin
    Result := Result + ' · ' + TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsOpened,
      [LocalText(AEntry.Summary.LastOpened)]);
  end;
  if AEntry.VcsQuerying and not AEntry.Summary.Vcs.InWorkingCopy then
  begin
    Result := Result + ' · ' + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsQuerying);
  end
  else if AEntry.VcsStale and (AEntry.Summary.Vcs.At > 0) then
  begin
    Result := Result + ' · ' + TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsStale,
      [LocalText(AEntry.Summary.Vcs.At)]);
  end;
end;

class function TAtlasProjectsTexts.HintFor(const AEntry: TAtlasProjectEntry): string;
begin
  Result := HintFor(AEntry, False);
end;

class function TAtlasProjectsTexts.HintFor(const AEntry: TAtlasProjectEntry; ASelectable: Boolean): string;
var
  mLines: TStringList;
begin
  mLines := TStringList.Create;
  try
    mLines.Add(AEntry.Project);
    AddVcsHint(mLines, AEntry);
    AddCheckHint(mLines, AEntry.Summary);
    if ASelectable then
    begin
      mLines.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsHintSelect));
    end
    else
    begin
      mLines.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsHintClick));
    end;
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

procedure TAtlasWelcomeProjectsFrame.LayoutPills;
var
  Row, Index, Right, mWidth, mTop: Integer;
  Canvas: TCanvas;
begin
  // Marken rechtsbündig in der ersten Zeile; die Rechtecke dienen auch dem Treffertest. Nur beim Zeichnen.
  SetLength(FPillRects, Length(FEntries));
  Canvas := FBox.Canvas;
  Canvas.Font.Assign(Font);
  Canvas.Font.Size := Font.Size - 1;
  for Row := 0 to High(FEntries) do
  begin
    SetLength(FPillRects[Row], Length(FPills[Row]));
    Right := FBox.Width - ScaleValue(Indent);
    mTop := RowTop(Row) + ScaleValue(3);
    for Index := High(FPills[Row]) downto 0 do
    begin
      mWidth := Canvas.TextWidth(TAtlasProjectsTexts.PillText(FPills[Row][Index])) + 2 * ScaleValue(PillPadding);
      FPillRects[Row][Index] := Rect(Right - mWidth, mTop, Right, mTop + ScaleValue(PillHeight));
      Dec(Right, mWidth + ScaleValue(PillGap));
    end;
  end;
end;

procedure TAtlasWelcomeProjectsFrame.BoxPaint(Sender: TObject);
var
  mPainter: TProjectsPainter;
  mRow: Integer;
begin
  mPainter := TProjectsPainter.Create(Self);
  if Length(FEntries) = 0 then
  begin
    mPainter.Canvas.Font.Color := mPainter.MutedColor;
    mPainter.Canvas.TextOut(ScaleValue(Indent), RowTop(0) + ScaleValue(4),
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeProjectsEmpty));
    Exit;
  end;
  LayoutPills;
  for mRow := 0 to High(FEntries) do
  begin
    mPainter.PaintRow(mRow);
  end;
end;

function TAtlasWelcomeProjectsFrame.HitTest(X, Y: Integer): TAtlasProjectsHit;
var
  Index: Integer;
begin
  Result.Row := -1;
  Result.Pill := -1;
  if (Y < RowTop(0)) or (Length(FEntries) = 0) then
  begin
    Exit;
  end;
  Result.Row := (Y - RowTop(0)) div ScaleValue(RowHeight);
  if Result.Row > High(FEntries) then
  begin
    Result.Row := -1;
    Exit;
  end;
  if Result.Row > High(FPillRects) then
  begin
    Exit;
  end;
  for Index := 0 to High(FPillRects[Result.Row]) do
  begin
    if FPillRects[Result.Row][Index].Contains(Point(X, Y)) then
    begin
      Result.Pill := Index;
    end;
  end;
end;

procedure TAtlasWelcomeProjectsFrame.ClickAt(const AHit: TAtlasProjectsHit);
var
  mSource: IAtlasProjectsSource;
  Project: string;
  Target: TAtlasProjectLocation;
  Jump, Choose: Boolean;
begin
  if (FSource = nil) or (AHit.Row < 0) or (AHit.Row > High(FEntries)) then
  begin
    Exit;
  end;
  mSource := FSource;
  Project := FEntries[AHit.Row].Project;
  Jump := (AHit.Pill >= 0) and (AHit.Pill <= High(FPills[AHit.Row])) and FPills[AHit.Row][AHit.Pill].Clickable;
  Target := Default(TAtlasProjectLocation);
  if Jump then
  begin
    Target := FPills[AHit.Row][AHit.Pill].Target;
  end;
  // Mit Projektverlauf wählt der Klick (#758); rote Marken springen weiter zur Meldung.
  Choose := not Jump and mSource.Selectable;
  // Die Quelle füllt den Bereich danach neu: nicht im eigenen Mausereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if Jump then
      begin
        mSource.OpenAt(Project, Target);
      end
      else if Choose then
      begin
        mSource.Select(Project);
      end
      else
      begin
        mSource.Open(Project);
      end;
    end);
end;

procedure TAtlasWelcomeProjectsFrame.DoubleClickAt(const AHit: TAtlasProjectsHit);
var
  mSource: IAtlasProjectsSource;
  Project: string;
begin
  // Ohne Auswahl öffnet schon der einfache Klick; ein zweites Öffnen wäre doppelt.
  if (FSource = nil) or (AHit.Row < 0) or (AHit.Row > High(FEntries)) or not FSource.Selectable then
  begin
    Exit;
  end;
  mSource := FSource;
  Project := FEntries[AHit.Row].Project;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.Open(Project);
    end);
end;

function TAtlasWelcomeProjectsFrame.SelectedRow: Integer;
var
  Wanted: string;
  Row: Integer;
begin
  Result := -1;
  if (FSource = nil) or not FSource.Selectable or (Length(FEntries) = 0) then
  begin
    Exit;
  end;
  Wanted := TAtlasProjectSummaries.NormalizedPath(FSource.Selected);
  for Row := 0 to High(FEntries) do
  begin
    if TAtlasProjectSummaries.NormalizedPath(FEntries[Row].Project) = Wanted then
    begin
      Exit(Row);
    end;
  end;
  // Ohne (gültige) Auswahl zeigt der Verlauf das oberste Projekt.
  Result := 0;
end;

procedure TAtlasWelcomeProjectsFrame.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  mHit: TAtlasProjectsHit;
  mQuickRow, mQuickButton: Integer;
  mOnMenu: Boolean;
  mKey, mHint: string;
begin
  mHit := HitTest(X, Y);
  FQuick.MouseMove(mHit.Row, X, Y);
  if mHit.Row >= 0 then
  begin
    FBox.Cursor := crHandPoint;
  end
  else
  begin
    FBox.Cursor := crDefault;
  end;
  if not FQuick.HitTest(X, Y, mQuickRow, mQuickButton, mOnMenu) then
  begin
    mQuickButton := -1;
  end;
  mKey := Format('%d/%d', [mHit.Row, mQuickButton]);
  if mKey = FHintKey then
  begin
    Exit;
  end;
  FHintKey := mKey;
  if (mQuickButton >= 0) and FQuick.HintAt(X, Y, mHint) then
  begin
    FBox.Hint := mHint;
  end
  else
  begin
    FBox.Hint := RowHint(Self, mHit.Row);
  end;
  Application.CancelHint;
end;

procedure TAtlasWelcomeProjectsFrame.BoxMouseLeave(Sender: TObject);
begin
  FQuick.MouseLeave;
  FHintKey := '';
end;

procedure TAtlasWelcomeProjectsFrame.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  // Der zweite Klick eines Doppelklicks wählt nicht noch einmal: BoxDblClick öffnet. Knöpfe der Schnellaktionen
  // (#764) handeln selbst.
  if (Button = mbLeft) and not FDoubleDown and not FQuick.ClickAt(X, Y) then
  begin
    ClickAt(HitTest(X, Y));
  end;
  FDoubleDown := False;
end;

procedure TAtlasWelcomeProjectsFrame.BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  FLastMouse := Point(X, Y);
  FDoubleDown := ssDouble in Shift;
  // Die Tastatur der Schnellaktionen übernimmt Zeile und Fokus (#764).
  FQuick.MouseDown(HitTest(X, Y).Row);
end;

procedure TAtlasWelcomeProjectsFrame.BoxDblClick(Sender: TObject);
var
  QuickRow, QuickButton: Integer;
  OnMenu: Boolean;
begin
  // Doppelklick auf einen Knopf öffnet nicht zusätzlich das Projekt.
  if FQuick.HitTest(FLastMouse.X, FLastMouse.Y, QuickRow, QuickButton, OnMenu) then
  begin
    Exit;
  end;
  DoubleClickAt(HitTest(FLastMouse.X, FLastMouse.Y));
end;

procedure TAtlasWelcomeProjectsFrame.MenuPopup(Sender: TObject);
var
  mPosition: TPoint;
  mRow: Integer;
begin
  mPosition := FBox.ScreenToClient(FMenu.PopupPoint);
  mRow := HitTest(mPosition.X, mPosition.Y).Row;
  FMenu.Row := mRow;
  FMenu.OpenItem.Enabled := mRow >= 0;
  FMenu.OpenFolderItem.Enabled := mRow >= 0;
  FMenu.CreateBranchItem.Enabled := (mRow >= 0) and (mRow <= High(FEntries)) and (FEntries[mRow].Branch <> '');
  FMenu.WorkingCopiesItem.Visible := (FSource <> nil) and FSource.WorkingCopies;
  FMenu.WorkingCopiesItem.Enabled := FMenu.CreateBranchItem.Enabled;
  FMenu.RemoveItem.Enabled := mRow >= 0;
  // Schnellaktionen der Zeile (#764): nur eingestellte Knöpfe, gesperrte grau.
  FQuick.Menus.Prepare(mRow);
end;

procedure TAtlasWelcomeProjectsFrame.MenuAction(AAction: TAtlasProjectsMenuAction);
var
  mSource: IAtlasProjectsSource;
  mProject: string;
begin
  if (FSource = nil) or (FMenu.Row < 0) or (FMenu.Row > High(FEntries)) then
  begin
    Exit;
  end;
  mSource := FSource;
  mProject := FEntries[FMenu.Row].Project;
  // Die Quelle füllt den Bereich danach neu (und öffnet Dialoge): nicht im Klick des Eintrags.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      RunMenuAction(mSource, AAction, mProject);
    end);
end;

end.
