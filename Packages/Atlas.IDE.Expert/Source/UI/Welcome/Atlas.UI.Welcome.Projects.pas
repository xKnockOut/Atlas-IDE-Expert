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
// „Öffnen“, „Ordner öffnen“ und „Aus Liste entfernen“ (nur dieser Bereich).
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
    FBox: TPaintBox;
    FEntries: TAtlasProjectEntries;
    FPills: TArray<TArray<TAtlasProjectPill>>;
    FPillRects: TArray<TArray<TRect>>;
    FMenu: TPopupMenu;
    FOpenItem: TMenuItem;
    FOpenFolderItem: TMenuItem;
    FRemoveItem: TMenuItem;
    FMenuRow: Integer;
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
    procedure OpenClick(Sender: TObject);
    procedure OpenFolderClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure LayoutPills;
    function RowTop(ARow: Integer): Integer;
    function GetQuickActions: IAtlasQuickActionsSource;
    procedure SetQuickActions(const AValue: IAtlasQuickActionsSource);
    procedure QuickOpenRow(ARow: Integer);
    procedure QuickSelectRow(ARow: Integer);
    procedure QuickRowMenu(ARow: Integer);
    function ProjectNames: TArray<string>;
    function IsUpdateRow(ARow: Integer): Boolean;
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
    property Source: IAtlasProjectsSource read FSource write SetSource;
    /// <summary>Schnellaktionen (#764); nil = keine Knöpfe.</summary>
    property QuickActions: IAtlasQuickActionsSource read GetQuickActions write SetQuickActions;
    /// <summary>Knopfleiste, Stand und Tastatur der Schnellaktionen (auch für Tests).</summary>
    property Quick: TAtlasQuickActionsBar read FQuick;
    property Entries: TAtlasProjectEntries read FEntries;
    property PaintBox: TPaintBox read FBox;
    property Menu: TPopupMenu read FMenu;
    property OpenItem: TMenuItem read FOpenItem;
    property OpenFolderItem: TMenuItem read FOpenFolderItem;
    property RemoveItem: TMenuItem read FRemoveItem;
    /// <summary>Zeile des zuletzt geöffneten Kontextmenüs; -1 = keine.</summary>
    property MenuRow: Integer read FMenuRow write FMenuRow;
  end;

implementation

uses
  System.UITypes,
  Atlas.Core.Welcome.QuickActions,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.DateUtils,
  Vcl.Themes,
  Atlas.UI.Strings;

{ TAtlasWelcomeProjectsFrame }

constructor TAtlasWelcomeProjectsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMenuRow := -1;
  FBox := TPaintBox.Create(Self);
  FBox.Parent := Body;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
  FBox.OnMouseDown := BoxMouseDown;
  FBox.OnDblClick := BoxDblClick;
  FBox.OnMouseLeave := BoxMouseLeave;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FOpenItem := TMenuItem.Create(Self);
  FOpenItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsOpen);
  FOpenItem.Default := True;
  FOpenItem.OnClick := OpenClick;
  FMenu.Items.Add(FOpenItem);
  FOpenFolderItem := TMenuItem.Create(Self);
  FOpenFolderItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsOpenFolder);
  FOpenFolderItem.OnClick := OpenFolderClick;
  FMenu.Items.Add(FOpenFolderItem);
  FRemoveItem := TMenuItem.Create(Self);
  FRemoveItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsRemove);
  FRemoveItem.OnClick := RemoveClick;
  FMenu.Items.Add(FRemoveItem);
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
  FQuick.AttachMenu(FMenu);
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

function TAtlasWelcomeProjectsFrame.ProjectNames: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(FEntries));
  for Index := 0 to High(FEntries) do
    Result[Index] := FEntries[Index].Project;
end;

procedure TAtlasWelcomeProjectsFrame.QuickOpenRow(ARow: Integer);
var
  Source: IAtlasProjectsSource;
  Project: string;
begin
  // Enter ohne Knopf öffnet (wie Doppelklick bzw. Klick ohne Projektverlauf).
  if (FSource = nil) or (ARow < 0) or (ARow > High(FEntries)) then
    Exit;
  Source := FSource;
  Project := FEntries[ARow].Project;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      Source.Open(Project);
    end);
end;

procedure TAtlasWelcomeProjectsFrame.QuickSelectRow(ARow: Integer);
var
  Source: IAtlasProjectsSource;
  Project: string;
begin
  // Mit Projektverlauf (#758) wählen die Pfeiltasten auch das Projekt des Verlaufs.
  if (FSource = nil) or (ARow < 0) or (ARow > High(FEntries)) or not FSource.Selectable then
    Exit;
  Source := FSource;
  Project := FEntries[ARow].Project;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      Source.Select(Project);
    end);
end;

procedure TAtlasWelcomeProjectsFrame.QuickRowMenu(ARow: Integer);
var
  Position: TPoint;
begin
  if (ARow < 0) or (ARow > High(FEntries)) then
    Exit;
  Position := FBox.ClientToScreen(Point(ScaleValue(Indent), RowTop(ARow) + ScaleValue(RowHeight) div 2));
  FMenu.PopupComponent := FBox;
  FMenu.Popup(Position.X, Position.Y);
end;

procedure TAtlasWelcomeProjectsFrame.SetSource(const AValue: IAtlasProjectsSource);
begin
  FSource := AValue;
  UpdateContent;
  if FSource <> nil then
    FSource.Shown;
end;

procedure TAtlasWelcomeProjectsFrame.UpdateContent;
var
  Count, Index: Integer;
begin
  Count := Length(FEntries);
  FEntries := nil;
  if FSource <> nil then
    FEntries := FSource.Entries;
  SetLength(FPills, Length(FEntries));
  for Index := 0 to High(FEntries) do
    FPills[Index] := TAtlasWelcomeProjects.Pills(FEntries[Index]);
  // Die Rechtecke der Marken entstehen beim Zeichnen: Erst dann gibt es eine Zeichenfläche.
  FPillRects := nil;
  FHintKey := '';
  FQuick.SetRows(ProjectNames);
  FBox.Invalidate;
  inherited;
  // Andere Anzahl Zeilen: Der Frame „Atlas“ ordnet die Spalten neu.
  if Count <> Length(FEntries) then
    HeightChanged;
end;

function TAtlasWelcomeProjectsFrame.BodyHeight: Integer;
var
  Rows: Integer;
begin
  Rows := Length(FEntries);
  if Rows < 1 then
    Rows := 1;
  Result := Rows * ScaleValue(RowHeight) + ScaleValue(Indent);
end;

function TAtlasWelcomeProjectsFrame.RowTop(ARow: Integer): Integer;
begin
  Result := ScaleValue(Indent) div 2 + ARow * ScaleValue(RowHeight);
end;

class function TAtlasWelcomeProjectsFrame.PillText(const APill: TAtlasProjectPill): string;
begin
  case APill.Kind of
    TAtlasProjectPillKind.Build:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsBuild, [APill.A, APill.B, APill.C]);
    TAtlasProjectPillKind.BuildErrors:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsErrors, [APill.A]);
    TAtlasProjectPillKind.CheckErrors:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsCheckErrors, [APill.A]);
    TAtlasProjectPillKind.Changes:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsChanged, [APill.A]);
    TAtlasProjectPillKind.Sync:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsSync, [APill.A, APill.B]);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsRules, [APill.A]);
  end;
end;

class function TAtlasWelcomeProjectsFrame.PillColor(ALevel: TAtlasProjectPillLevel): TColor;
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

class function TAtlasWelcomeProjectsFrame.LocalText(AUtc: TDateTime): string;
begin
  Result := '';
  if AUtc <= 0 then
    Exit;
  Result := FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(AUtc));
end;

class function TAtlasWelcomeProjectsFrame.DetailText(const AEntry: TAtlasProjectEntry): string;
begin
  Result := TAtlasWelcomeProjects.ShortPath(AEntry.Project, PathLength);
  if AEntry.Summary.LastOpened > 0 then
    Result := Result + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsOpened,
      [LocalText(AEntry.Summary.LastOpened)]);
  if AEntry.VcsQuerying and not AEntry.Summary.Vcs.InWorkingCopy then
    Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsQuerying)
  else if AEntry.VcsStale and (AEntry.Summary.Vcs.At > 0) then
    Result := Result + ' · ' + TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsStale,
      [LocalText(AEntry.Summary.Vcs.At)]);
end;

class function TAtlasWelcomeProjectsFrame.HintFor(const AEntry: TAtlasProjectEntry): string;
begin
  Result := HintFor(AEntry, False);
end;

class function TAtlasWelcomeProjectsFrame.HintFor(const AEntry: TAtlasProjectEntry; ASelectable: Boolean): string;
var
  Lines: TStringList;
  Summary: TAtlasProjectSummary;

  procedure AddFirst(const ALocation: TAtlasProjectLocation);
  begin
    if not ALocation.IsEmpty then
      Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsHintFirst,
        [ExtractFileName(ALocation.FileName), ALocation.Line, Trim(ALocation.Code + ' ' + ALocation.Text)]));
  end;

begin
  Summary := AEntry.Summary;
  Lines := TStringList.Create;
  try
    Lines.Add(AEntry.Project);
    if Summary.Vcs.InWorkingCopy then
    begin
      Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsHintVcs,
        [UpperCase(Summary.Vcs.Kind), AEntry.Branch, Summary.Vcs.Revision]));
      if Summary.Vcs.Changed >= 0 then
        Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsHintChanged, [Summary.Vcs.Changed]));
      if (Summary.Vcs.Ahead >= 0) and (Summary.Vcs.Behind >= 0) then
        Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsHintSync, [Summary.Vcs.Ahead, Summary.Vcs.Behind]));
      if AEntry.VcsStale and (Summary.Vcs.At > 0) then
        Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsStale, [LocalText(Summary.Vcs.At)]));
    end;
    if Summary.Build.Known then
    begin
      Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsHintBuild, [LocalText(Summary.Build.At),
        Summary.Build.Kind, Summary.Build.Configuration, Summary.Build.Platform, Summary.Build.Errors,
        Summary.Build.Warnings, Summary.Build.Hints]));
      AddFirst(Summary.Build.First);
    end
    else
      Lines.Add(TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsHintNoBuild));
    if Summary.Check.Known then
    begin
      Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsHintCheck, [LocalText(Summary.Check.At),
        Summary.Check.Errors]));
      AddFirst(Summary.Check.First);
    end;
    if Summary.Rules.Known then
      Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsHintRules, [Summary.Rules.NewHits]));
    if ASelectable then
      Lines.Add(TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsHintSelect))
    else
      Lines.Add(TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsHintClick));
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

procedure TAtlasWelcomeProjectsFrame.LayoutPills;
var
  Row, Index, Right, Width, Top: Integer;
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
    Top := RowTop(Row) + ScaleValue(3);
    for Index := High(FPills[Row]) downto 0 do
    begin
      Width := Canvas.TextWidth(PillText(FPills[Row][Index])) + 2 * ScaleValue(PillPadding);
      FPillRects[Row][Index] := Rect(Right - Width, Top, Right, Top + ScaleValue(PillHeight));
      Dec(Right, Width + ScaleValue(PillGap));
    end;
  end;
end;

procedure TAtlasWelcomeProjectsFrame.BoxPaint(Sender: TObject);
var
  Canvas: TCanvas;
  Row, Index, Left, Top, Dot, Radius: Integer;
  Entry: TAtlasProjectEntry;
  Pill: TAtlasProjectPill;
  PillRect: TRect;
  Text, Branch: string;
  TextColor, MutedColor: TColor;
  Selected, Active, Limit, Right: Integer;
  State: TAtlasQuickActionState;
  QuickRect: TRect;
begin
  Canvas := FBox.Canvas;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  // Farben des IDE-Themas (hell oder dunkel).
  TextColor := StyleServices(Self).GetSystemColor(clWindowText);
  MutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  Canvas.Font.Color := TextColor;
  if Length(FEntries) = 0 then
  begin
    Canvas.Font.Color := MutedColor;
    Canvas.TextOut(ScaleValue(Indent), RowTop(0) + ScaleValue(4),
      TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsEmpty));
    Exit;
  end;
  LayoutPills;
  Dot := ScaleValue(DotSize);
  Radius := ScaleValue(PillHeight);
  Selected := SelectedRow;
  Active := FQuick.ActiveRow;
  for Row := 0 to High(FEntries) do
  begin
    Entry := FEntries[Row];
    Top := RowTop(Row);
    Left := ScaleValue(Indent);
    // Schnellaktionen (#764): aktive Zeile hinterlegt, Fokusrahmen der Tastatur.
    FQuick.PaintBackground(Canvas, Row, Rect(0, Top, FBox.Width, Top + ScaleValue(RowHeight) - ScaleValue(2)));
    // Rechte Grenze für Name, Branch und zweite Zeile: die Knopfleiste der aktiven Zeile bzw. die Marken.
    Limit := FBox.Width - ScaleValue(Indent);
    if Row = Active then
    begin
      Canvas.Font.Assign(Font);
      Canvas.Font.Size := Font.Size - 1;
      Limit := FQuick.LayoutRow(Canvas, Row, Rect(ScaleValue(Indent) + Dot + ScaleValue(80), Top,
        FBox.Width - ScaleValue(Indent), Top + ScaleValue(RowHeight) - ScaleValue(2))) - ScaleValue(Indent);
    end;
    // Für den Projektverlauf gewählte Zeile hinterlegen (#758), in der Markierungsfarbe des Themas.
    if Row = Selected then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := StyleServices(Self).GetSystemColor(clHighlight);
      Canvas.Pen.Color := Canvas.Brush.Color;
      Canvas.FillRect(Rect(0, Top, ScaleValue(3), Top + ScaleValue(RowHeight) - ScaleValue(2)));
      Canvas.Brush.Style := bsClear;
    end;
    // Punkt mit der schlimmsten Stufe; ohne Angaben grau.
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := PillColor(TAtlasWelcomeProjects.Level(FPills[Row]));
    Canvas.Pen.Color := Canvas.Brush.Color;
    Canvas.Ellipse(Left, Top + ScaleValue(6), Left + Dot, Top + ScaleValue(6) + Dot);
    Canvas.Brush.Style := bsClear;
    Inc(Left, Dot + ScaleValue(6));
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := TextColor;
    Canvas.Font.Style := [fsBold];
    Canvas.TextRect(Rect(Left, Top + ScaleValue(3), Limit, Top + ScaleValue(21)), Left, Top + ScaleValue(3),
      Entry.Name);
    Inc(Left, Canvas.TextWidth(Entry.Name) + ScaleValue(8));
    Canvas.Font.Style := [];
    Branch := Entry.Branch;
    if (Branch <> '') and (Left < Limit) then
    begin
      Canvas.Font.Color := MutedColor;
      Canvas.TextRect(Rect(Left, Top + ScaleValue(3), Limit, Top + ScaleValue(21)), Left, Top + ScaleValue(3),
        Branch);
    end;
    // Zweite Zeile.
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := MutedColor;
    Canvas.TextRect(Rect(ScaleValue(Indent) + Dot + ScaleValue(6), Top + ScaleValue(23), Limit,
      Top + ScaleValue(41)), ScaleValue(Indent) + Dot + ScaleValue(6), Top + ScaleValue(23), DetailText(Entry));
    // Aktive Zeile: Knöpfe statt Marken.
    Canvas.Font.Size := Font.Size - 1;
    if Row = Active then
    begin
      FQuick.PaintRow(Canvas, Row);
      Continue;
    end;
    // Stand der letzten Schnellaktion links der Marken („baut … 12 s“, „Tests: 57 ok“).
    State := FQuick.StateOf(Row);
    Text := TAtlasQuickActionsBar.StateText(State, FQuick.NowMs, IsUpdateRow(Row));
    if Text <> '' then
    begin
      Right := FBox.Width - ScaleValue(Indent);
      if Length(FPillRects[Row]) > 0 then
        Right := FPillRects[Row][0].Left - ScaleValue(PillGap);
      QuickRect := Rect(Right - Canvas.TextWidth(Text) - 2 * ScaleValue(PillPadding), Top + ScaleValue(3), Right,
        Top + ScaleValue(3) + ScaleValue(PillHeight));
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := TAtlasQuickActionsBar.StateColor(State);
      Canvas.Pen.Color := Canvas.Brush.Color;
      Canvas.RoundRect(QuickRect.Left, QuickRect.Top, QuickRect.Right, QuickRect.Bottom, Radius, Radius);
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := clWhite;
      Canvas.Font.Style := [];
      Canvas.TextOut(QuickRect.Left + ScaleValue(PillPadding),
        QuickRect.Top + (QuickRect.Height - Canvas.TextHeight(Text)) div 2, Text);
    end;
    // Marken.
    for Index := 0 to High(FPills[Row]) do
    begin
      Pill := FPills[Row][Index];
      PillRect := FPillRects[Row][Index];
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := PillColor(Pill.Level);
      Canvas.Pen.Color := Canvas.Brush.Color;
      Canvas.RoundRect(PillRect.Left, PillRect.Top, PillRect.Right, PillRect.Bottom, Radius, Radius);
      Canvas.Brush.Style := bsClear;
      Canvas.Font.Color := clWhite;
      if Pill.Clickable then
        Canvas.Font.Style := [fsUnderline]
      else
        Canvas.Font.Style := [];
      Text := PillText(Pill);
      Canvas.TextOut(PillRect.Left + ScaleValue(PillPadding),
        PillRect.Top + (PillRect.Height - Canvas.TextHeight(Text)) div 2, Text);
    end;
  end;
end;

function TAtlasWelcomeProjectsFrame.IsUpdateRow(ARow: Integer): Boolean;
var
  Button: TAtlasQuickActionButton;
begin
  // SVN: „aktualisiert …“ statt „holt …“.
  Result := False;
  for Button in FQuick.ButtonsOf(ARow) do
    if Button.Action = TAtlasQuickAction.Pull then
      Result := Button.Update;
end;

function TAtlasWelcomeProjectsFrame.HitTest(X, Y: Integer): TAtlasProjectsHit;
var
  Index: Integer;
begin
  Result.Row := -1;
  Result.Pill := -1;
  if (Y < RowTop(0)) or (Length(FEntries) = 0) then
    Exit;
  Result.Row := (Y - RowTop(0)) div ScaleValue(RowHeight);
  if Result.Row > High(FEntries) then
  begin
    Result.Row := -1;
    Exit;
  end;
  if Result.Row > High(FPillRects) then
    Exit;
  for Index := 0 to High(FPillRects[Result.Row]) do
    if FPillRects[Result.Row][Index].Contains(Point(X, Y)) then
      Result.Pill := Index;
end;

procedure TAtlasWelcomeProjectsFrame.ClickAt(const AHit: TAtlasProjectsHit);
var
  Source: IAtlasProjectsSource;
  Project: string;
  Target: TAtlasProjectLocation;
  Jump, Choose: Boolean;
begin
  if (FSource = nil) or (AHit.Row < 0) or (AHit.Row > High(FEntries)) then
    Exit;
  Source := FSource;
  Project := FEntries[AHit.Row].Project;
  Jump := (AHit.Pill >= 0) and (AHit.Pill <= High(FPills[AHit.Row])) and FPills[AHit.Row][AHit.Pill].Clickable;
  Target := Default(TAtlasProjectLocation);
  if Jump then
    Target := FPills[AHit.Row][AHit.Pill].Target;
  // Mit Projektverlauf wählt der Klick (#758); rote Marken springen weiter zur Meldung.
  Choose := not Jump and Source.Selectable;
  // Die Quelle füllt den Bereich danach neu: nicht im eigenen Mausereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if Jump then
        Source.OpenAt(Project, Target)
      else if Choose then
        Source.Select(Project)
      else
        Source.Open(Project);
    end);
end;

procedure TAtlasWelcomeProjectsFrame.DoubleClickAt(const AHit: TAtlasProjectsHit);
var
  Source: IAtlasProjectsSource;
  Project: string;
begin
  // Ohne Auswahl öffnet schon der einfache Klick; ein zweites Öffnen wäre doppelt.
  if (FSource = nil) or (AHit.Row < 0) or (AHit.Row > High(FEntries)) or not FSource.Selectable then
    Exit;
  Source := FSource;
  Project := FEntries[AHit.Row].Project;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      Source.Open(Project);
    end);
end;

function TAtlasWelcomeProjectsFrame.SelectedRow: Integer;
var
  Wanted: string;
  Row: Integer;
begin
  Result := -1;
  if (FSource = nil) or not FSource.Selectable or (Length(FEntries) = 0) then
    Exit;
  Wanted := TAtlasProjectSummaries.NormalizedPath(FSource.Selected);
  for Row := 0 to High(FEntries) do
    if TAtlasProjectSummaries.NormalizedPath(FEntries[Row].Project) = Wanted then
      Exit(Row);
  // Ohne (gültige) Auswahl zeigt der Verlauf das oberste Projekt.
  Result := 0;
end;

procedure TAtlasWelcomeProjectsFrame.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Hit: TAtlasProjectsHit;
  QuickRow, QuickButton: Integer;
  OnMenu: Boolean;
  Key, Hint, State: string;
begin
  Hit := HitTest(X, Y);
  FQuick.MouseMove(Hit.Row, X, Y);
  if Hit.Row >= 0 then
    FBox.Cursor := crHandPoint
  else
    FBox.Cursor := crDefault;
  if not FQuick.HitTest(X, Y, QuickRow, QuickButton, OnMenu) then
    QuickButton := -1;
  Key := Format('%d/%d', [Hit.Row, QuickButton]);
  if Key = FHintKey then
    Exit;
  FHintKey := Key;
  if (QuickButton >= 0) and FQuick.HintAt(X, Y, Hint) then
    FBox.Hint := Hint
  else if Hit.Row >= 0 then
  begin
    FBox.Hint := HintFor(FEntries[Hit.Row], (FSource <> nil) and FSource.Selectable);
    // Stand der letzten Schnellaktion samt Grund (#764).
    if FQuick.Source <> nil then
    begin
      State := TAtlasQuickActionsBar.StateText(FQuick.StateOf(Hit.Row), FQuick.NowMs, IsUpdateRow(Hit.Row));
      if (State <> '') and (FQuick.StateOf(Hit.Row).Detail <> '') then
        State := State + ': ' + FQuick.StateOf(Hit.Row).Detail;
      if State <> '' then
        FBox.Hint := FBox.Hint + sLineBreak + TAtlasStrings.Fmt(TAtlasTextId.WelcomeQuickHintState, [State]);
      if FQuick.Active then
        FBox.Hint := FBox.Hint + sLineBreak + TAtlasStrings.Text(TAtlasTextId.WelcomeQuickHintKeys);
    end;
  end
  else
    FBox.Hint := '';
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
    ClickAt(HitTest(X, Y));
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
    Exit;
  DoubleClickAt(HitTest(FLastMouse.X, FLastMouse.Y));
end;

procedure TAtlasWelcomeProjectsFrame.MenuPopup(Sender: TObject);
var
  Position: TPoint;
begin
  Position := FBox.ScreenToClient(FMenu.PopupPoint);
  FMenuRow := HitTest(Position.X, Position.Y).Row;
  FOpenItem.Enabled := FMenuRow >= 0;
  FOpenFolderItem.Enabled := FMenuRow >= 0;
  FRemoveItem.Enabled := FMenuRow >= 0;
  // Schnellaktionen der Zeile (#764): nur eingestellte Knöpfe, gesperrte grau.
  FQuick.PrepareMenu(FMenuRow);
end;

procedure TAtlasWelcomeProjectsFrame.OpenClick(Sender: TObject);
var
  Source: IAtlasProjectsSource;
  Project: string;
begin
  if (FSource = nil) or (FMenuRow < 0) or (FMenuRow > High(FEntries)) then
    Exit;
  Source := FSource;
  Project := FEntries[FMenuRow].Project;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      Source.Open(Project);
    end);
end;

procedure TAtlasWelcomeProjectsFrame.OpenFolderClick(Sender: TObject);
var
  Source: IAtlasProjectsSource;
  Project: string;
begin
  if (FSource = nil) or (FMenuRow < 0) or (FMenuRow > High(FEntries)) then
    Exit;
  Source := FSource;
  Project := FEntries[FMenuRow].Project;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      Source.OpenFolder(Project);
    end);
end;

procedure TAtlasWelcomeProjectsFrame.RemoveClick(Sender: TObject);
var
  Source: IAtlasProjectsSource;
  Project: string;
begin
  if (FSource = nil) or (FMenuRow < 0) or (FMenuRow > High(FEntries)) then
    Exit;
  Source := FSource;
  Project := FEntries[FMenuRow].Project;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      Source.Remove(Project);
    end);
end;

end.
