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
// „Ordner öffnen“ und „Aus Liste entfernen“ (nur dieser Bereich).
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
  Atlas.UI.Welcome.Frame;

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
    FOpenFolderItem: TMenuItem;
    FRemoveItem: TMenuItem;
    FMenuRow: Integer;
    FHintRow: Integer;
    procedure SetSource(const AValue: IAtlasProjectsSource);
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MenuPopup(Sender: TObject);
    procedure OpenFolderClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure LayoutPills;
    function RowTop(ARow: Integer): Integer;
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    /// <summary>Zeile und Marke an X, Y (Koordinaten der Zeichenfläche).</summary>
    function HitTest(X, Y: Integer): TAtlasProjectsHit;
    /// <summary>Klick wie mit der Maus (auch für Tests).</summary>
    procedure ClickAt(const AHit: TAtlasProjectsHit);
    /// <summary>Text einer Marke, z. B. „Build 0/0/0“ oder „2 Fehler“.</summary>
    class function PillText(const APill: TAtlasProjectPill): string; static;
    class function PillColor(ALevel: TAtlasProjectPillLevel): TColor; static;
    /// <summary>Zweite Zeile: gekürzter Pfad, letztes Öffnen und „Stand vom …“.</summary>
    class function DetailText(const AEntry: TAtlasProjectEntry): string; static;
    /// <summary>Tooltip mit allen Angaben.</summary>
    class function HintFor(const AEntry: TAtlasProjectEntry): string; static;
    /// <summary>UTC-Zeit als lokale Kurzform; '' für 0.</summary>
    class function LocalText(AUtc: TDateTime): string; static;
    property Source: IAtlasProjectsSource read FSource write SetSource;
    property Entries: TAtlasProjectEntries read FEntries;
    property PaintBox: TPaintBox read FBox;
    property Menu: TPopupMenu read FMenu;
    property OpenFolderItem: TMenuItem read FOpenFolderItem;
    property RemoveItem: TMenuItem read FRemoveItem;
    /// <summary>Zeile des zuletzt geöffneten Kontextmenüs; -1 = keine.</summary>
    property MenuRow: Integer read FMenuRow write FMenuRow;
  end;

implementation

uses
  System.UITypes,
  System.DateUtils,
  Vcl.Themes,
  Atlas.UI.Strings;

{ TAtlasWelcomeProjectsFrame }

constructor TAtlasWelcomeProjectsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMenuRow := -1;
  FHintRow := -1;
  FBox := TPaintBox.Create(Self);
  FBox.Parent := Body;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FOpenFolderItem := TMenuItem.Create(Self);
  FOpenFolderItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsOpenFolder);
  FOpenFolderItem.OnClick := OpenFolderClick;
  FMenu.Items.Add(FOpenFolderItem);
  FRemoveItem := TMenuItem.Create(Self);
  FRemoveItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeProjectsRemove);
  FRemoveItem.OnClick := RemoveClick;
  FMenu.Items.Add(FRemoveItem);
  FBox.PopupMenu := FMenu;
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
  FHintRow := -1;
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
  for Row := 0 to High(FEntries) do
  begin
    Entry := FEntries[Row];
    Top := RowTop(Row);
    Left := ScaleValue(Indent);
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
    Canvas.TextOut(Left, Top + ScaleValue(3), Entry.Name);
    Inc(Left, Canvas.TextWidth(Entry.Name) + ScaleValue(8));
    Canvas.Font.Style := [];
    Branch := Entry.Branch;
    if Branch <> '' then
    begin
      Canvas.Font.Color := MutedColor;
      Canvas.TextOut(Left, Top + ScaleValue(3), Branch);
    end;
    // Marken.
    Canvas.Font.Size := Font.Size - 1;
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
    // Zweite Zeile.
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := MutedColor;
    Canvas.TextOut(ScaleValue(Indent) + Dot + ScaleValue(6), Top + ScaleValue(23), DetailText(Entry));
  end;
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
  Jump: Boolean;
begin
  if (FSource = nil) or (AHit.Row < 0) or (AHit.Row > High(FEntries)) then
    Exit;
  Source := FSource;
  Project := FEntries[AHit.Row].Project;
  Jump := (AHit.Pill >= 0) and (AHit.Pill <= High(FPills[AHit.Row])) and FPills[AHit.Row][AHit.Pill].Clickable;
  Target := Default(TAtlasProjectLocation);
  if Jump then
    Target := FPills[AHit.Row][AHit.Pill].Target;
  // Die Quelle füllt den Bereich danach neu: nicht im eigenen Mausereignis.
  TThread.ForceQueue(nil,
    procedure
    begin
      if Jump then
        Source.OpenAt(Project, Target)
      else
        Source.Open(Project);
    end);
end;

procedure TAtlasWelcomeProjectsFrame.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Hit: TAtlasProjectsHit;
begin
  Hit := HitTest(X, Y);
  if Hit.Row >= 0 then
    FBox.Cursor := crHandPoint
  else
    FBox.Cursor := crDefault;
  if Hit.Row = FHintRow then
    Exit;
  FHintRow := Hit.Row;
  if Hit.Row >= 0 then
    FBox.Hint := HintFor(FEntries[Hit.Row])
  else
    FBox.Hint := '';
  Application.CancelHint;
end;

procedure TAtlasWelcomeProjectsFrame.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if Button = mbLeft then
    ClickAt(HitTest(X, Y));
end;

procedure TAtlasWelcomeProjectsFrame.MenuPopup(Sender: TObject);
var
  Position: TPoint;
begin
  Position := FBox.ScreenToClient(FMenu.PopupPoint);
  FMenuRow := HitTest(Position.X, Position.Y).Row;
  FOpenFolderItem.Enabled := FMenuRow >= 0;
  FRemoveItem.Enabled := FMenuRow >= 0;
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
  TThread.ForceQueue(nil,
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
  TThread.ForceQueue(nil,
    procedure
    begin
      Source.Remove(Project);
    end);
end;

end.
