unit Atlas.UI.Welcome.Unsaved;

// Bereich „Nicht gesichert“ der Willkommensseite (#762), ohne Open Tools API.
// Je Projekt und Art eine Zeile, älteste zuerst, selbst gezeichnet:
//   ● XmlInspector · feature/xpath                                [Ansehen]
//     4 Dateien geändert · seit 2 Tagen
//   ● Atlas · main                                                [Push …]
//     3 Commits nicht gepusht (main) · seit 30 Std.
//   ● Kasse · trunk
//     7 Dateien geändert (Kasse 2 · Packages\Drucken 5) · seit 3 Std.
// Mit Externals bzw. Submodulen (#1292) stehen die Anteile je Arbeitskopie
// in Klammern hinter der Summe.
// Der Punkt trägt die Ampel (grün, gelb ab warnHours, rot ab alertHours).
// „Ansehen“ öffnet das Projekt und die geänderten Dateien, „Push …“ fragt
// erst mit Ziel und Commits nach (TAtlasPushDialog). Kontextmenü: „Ordner
// öffnen“ und „Ignorieren bis morgen“. Ohne Zeilen steht dort „Alles
// gesichert“ (bzw. wie viele Einträge ausgeblendet sind); mit
// welcomePage.unsaved.hideWhenClean blendet die IDE-Schicht den Bereich aus.
// Daten und Aktionen kommen über IAtlasUnsavedSource aus der IDE-Schicht;
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
  Atlas.Core.Welcome.Unsaved,
  Atlas.UI.Welcome.Frame;

type
  IAtlasUnsavedSource = interface
    ['{8C2D4E61-3A7B-4F95-B1E8-6D0C9A2F5E73}']
    /// <summary>Zeilen und Zustand des Bereichs.</summary>
    function View: TAtlasUnsavedView;
    /// <summary>„Ansehen“: Projekt öffnen und die betroffenen Dateien zeigen.</summary>
    procedure Show(const ARow: TAtlasUnsavedRow);
    /// <summary>„Push …“: Ziel und Commits zeigen, nur nach Bestätigung pushen.</summary>
    procedure Push(const ARow: TAtlasUnsavedRow);
    procedure OpenFolder(const ARow: TAtlasUnsavedRow);
    /// <summary>„Ignorieren bis morgen“.</summary>
    procedure Ignore(const ARow: TAtlasUnsavedRow);
    /// <summary>Der Bereich wird gezeigt: bei Bedarf im Hintergrund frisch abfragen.</summary>
    procedure Shown;
  end;

  TAtlasUnsavedHit = record
    /// <summary>Zeile; -1 = keine.</summary>
    Row: Integer;
    /// <summary>Auf der Schaltfläche der Zeile.</summary>
    Button: Boolean;
  end;

  TAtlasWelcomeUnsavedFrame = class(TAtlasWelcomeSectionFrame)
  public const
    RowHeight = 44;
    Indent = 8;
    DotSize = 10;
    ButtonHeight = 22;
    ButtonPadding = 10;
  private
    FSource: IAtlasUnsavedSource;
    FBox: TAtlasWelcomeCanvas;
    FView: TAtlasUnsavedView;
    FButtonRects: TArray<TRect>;
    FMenu: TPopupMenu;
    FOpenFolderItem: TMenuItem;
    FIgnoreItem: TMenuItem;
    FMenuRow: Integer;
    FHintRow: Integer;
    procedure SetSource(const AValue: IAtlasUnsavedSource);
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MenuPopup(Sender: TObject);
    procedure OpenFolderClick(Sender: TObject);
    procedure IgnoreClick(Sender: TObject);
    procedure LayoutButtons;
    function RowTop(ARow: Integer): Integer;
    function MenuTarget(out ARow: TAtlasUnsavedRow): Boolean;
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    /// <summary>Zeile und Schaltfläche an X, Y (Koordinaten der Zeichenfläche).</summary>
    function HitTest(X, Y: Integer): TAtlasUnsavedHit;
    /// <summary>Klick wie mit der Maus (auch für Tests); nur die Schaltfläche löst eine Aktion aus.</summary>
    procedure ClickAt(const AHit: TAtlasUnsavedHit);
    /// <summary>Jetzt in UTC.</summary>
    class function NowUtc: TDateTime; static;
    /// <summary>Kopfzeile: „Projekt · Branch“.</summary>
    class function TitleText(const ARow: TAtlasUnsavedRow): string; static;
    /// <summary>Zweite Zeile: was nicht gesichert ist und seit wann.</summary>
    class function DetailText(const ARow: TAtlasUnsavedRow; ANowUtc: TDateTime): string; static;
    /// <summary>Was nicht gesichert ist, z. B. „4 Dateien geändert“ oder „3 Commits nicht gepusht (main)“.</summary>
    class function WhatText(const AItem: TAtlasUnsavedItem): string; static;
    /// <summary>„seit 5 Min.“, „seit 3 Std.“, „seit 2 Tagen“; '' bei unbekanntem Alter.</summary>
    class function AgeText(ASince, ANowUtc: TDateTime): string; static;
    /// <summary>„Ansehen“ bzw. „Push …“.</summary>
    class function ButtonText(const AItem: TAtlasUnsavedItem): string; static;
    /// <summary>Text ohne Zeilen: „Alles gesichert“, ausgeblendete Einträge oder „wird abgefragt …“.</summary>
    class function EmptyText(const AView: TAtlasUnsavedView): string; static;
    class function LevelColor(ALevel: TAtlasUnsavedLevel): TColor; static;
    /// <summary>Tooltip mit Pfad, Branches, ältestem Stand und Stand der Abfrage.</summary>
    class function HintFor(const ARow: TAtlasUnsavedRow): string; static;
    /// <summary>UTC-Zeit als lokales Datum mit Uhrzeit; '' für 0.</summary>
    class function LocalText(AUtc: TDateTime): string; static;
    property Source: IAtlasUnsavedSource read FSource write SetSource;
    property View: TAtlasUnsavedView read FView;
    property PaintBox: TAtlasWelcomeCanvas read FBox;
    property Menu: TPopupMenu read FMenu;
    property OpenFolderItem: TMenuItem read FOpenFolderItem;
    property IgnoreItem: TMenuItem read FIgnoreItem;
    /// <summary>Zeile des zuletzt geöffneten Kontextmenüs; -1 = keine.</summary>
    property MenuRow: Integer read FMenuRow write FMenuRow;
  end;

implementation

uses
  System.UITypes,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.DateUtils,
  Vcl.Themes,
  Atlas.UI.Strings;

const
  Separator = ' · ';

{ TAtlasWelcomeUnsavedFrame }

constructor TAtlasWelcomeUnsavedFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMenuRow := -1;
  FHintRow := -1;
  FBox := TAtlasWelcomeCanvas.Create(Self);
  FBox.Parent := Body;
  FBox.Align := alClient;
  FBox.ShowHint := True;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FOpenFolderItem := TMenuItem.Create(Self);
  FOpenFolderItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedOpenFolder);
  FOpenFolderItem.OnClick := OpenFolderClick;
  FMenu.Items.Add(FOpenFolderItem);
  FIgnoreItem := TMenuItem.Create(Self);
  FIgnoreItem.Caption := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedIgnore);
  FIgnoreItem.OnClick := IgnoreClick;
  FMenu.Items.Add(FIgnoreItem);
  FBox.PopupMenu := FMenu;
end;

procedure TAtlasWelcomeUnsavedFrame.SetSource(const AValue: IAtlasUnsavedSource);
begin
  FSource := AValue;
  UpdateContent;
  if FSource <> nil then
    FSource.Shown;
end;

procedure TAtlasWelcomeUnsavedFrame.UpdateContent;
var
  Count: Integer;
begin
  Count := Length(FView.Rows);
  FView := Default(TAtlasUnsavedView);
  if FSource <> nil then
    FView := FSource.View;
  // Die Rechtecke der Schaltflächen entstehen beim Zeichnen.
  FButtonRects := nil;
  FHintRow := -1;
  FBox.Invalidate;
  inherited;
  if Count <> Length(FView.Rows) then
    HeightChanged;
end;

function TAtlasWelcomeUnsavedFrame.BodyHeight: Integer;
var
  Rows: Integer;
begin
  Rows := Length(FView.Rows);
  if Rows < 1 then
    Rows := 1;
  Result := Rows * ScaleValue(RowHeight) + ScaleValue(Indent);
end;

function TAtlasWelcomeUnsavedFrame.RowTop(ARow: Integer): Integer;
begin
  Result := ScaleValue(Indent) div 2 + ARow * ScaleValue(RowHeight);
end;

class function TAtlasWelcomeUnsavedFrame.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasWelcomeUnsavedFrame.LocalText(AUtc: TDateTime): string;
begin
  Result := '';
  if AUtc > 0 then
    Result := FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(AUtc));
end;

function LocalDate(AUtc: TDateTime): string;
begin
  Result := '';
  if AUtc > 0 then
    Result := FormatDateTime('ddddd', TTimeZone.Local.ToLocalTime(AUtc));
end;

function Joined(const AItems: TArray<string>): string;
begin
  Result := string.Join(', ', AItems);
end;

class function TAtlasWelcomeUnsavedFrame.TitleText(const ARow: TAtlasUnsavedRow): string;
begin
  Result := ARow.Name;
  if ARow.Branch <> '' then
    Result := Result + Separator + ARow.Branch;
end;

class function TAtlasWelcomeUnsavedFrame.WhatText(const AItem: TAtlasUnsavedItem): string;
var
  Parts: TArray<string>;
begin
  case AItem.Kind of
    TAtlasUnsavedKind.Changes:
      if (AItem.Added = 0) and (AItem.Deleted = 0) then
      begin
        if AItem.Count = 1 then
          Result := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedFileOne)
        else
          Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedFiles, [AItem.Count]);
      end
      else
      begin
        Parts := nil;
        if AItem.Modified > 0 then
          Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedPartModified, [AItem.Modified])];
        if AItem.Added > 0 then
          Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedPartAdded, [AItem.Added])];
        if AItem.Deleted > 0 then
          Parts := Parts + [TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedPartDeleted, [AItem.Deleted])];
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedFilesMixed, [AItem.Count, Joined(Parts)]);
      end;
    TAtlasUnsavedKind.Conflicts:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedConflicts, [AItem.Count]);
    TAtlasUnsavedKind.Commits:
      if AItem.Count = 1 then
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedCommitOne, [Joined(AItem.Branches)])
      else
        Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedCommits, [AItem.Count, Joined(AItem.Branches)]);
    TAtlasUnsavedKind.NoUpstream:
      begin
        if AItem.Count = 1 then
          Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedNoUpstreamOne, [Joined(AItem.Branches)])
        else
          Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedNoUpstream, [AItem.Count, Joined(AItem.Branches)]);
        if AItem.Commits > 0 then
          Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedLocalCommits, [Result, AItem.Commits]);
      end;
  else
    if AItem.Count = 1 then
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedStash, [AItem.Name, LocalDate(AItem.Since)])
    else
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedStashes, [AItem.Count, AItem.Name,
        LocalDate(AItem.Since)]);
  end;
end;

class function TAtlasWelcomeUnsavedFrame.AgeText(ASince, ANowUtc: TDateTime): string;
var
  Value: Integer;
  AgeUnit: TAtlasUnsavedAgeUnit;
begin
  Result := '';
  if ASince <= 0 then
    Exit;
  TAtlasWelcomeUnsaved.Age(ASince, ANowUtc, Value, AgeUnit);
  case AgeUnit of
    TAtlasUnsavedAgeUnit.Minutes:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedSinceMinutes, [Value]);
    TAtlasUnsavedAgeUnit.Hours:
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedSinceHours, [Value]);
  else
    if Value = 1 then
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedSinceDayOne)
    else
      Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedSinceDays, [Value]);
  end;
end;

class function TAtlasWelcomeUnsavedFrame.DetailText(const ARow: TAtlasUnsavedRow; ANowUtc: TDateTime): string;
var
  Age, mPlaces: string;
begin
  Result := WhatText(ARow.Item);
  // Externals bzw. Submodule (#1292): die Summe mit den Anteilen je Arbeitskopie.
  mPlaces := TAtlasWelcomeUnsaved.PlacesText(ARow.Item, ARow.Name);
  if mPlaces <> '' then
    Result := Result + ' (' + mPlaces + ')';
  Age := AgeText(ARow.Item.Since, ANowUtc);
  if Age <> '' then
    Result := Result + Separator + Age;
end;

class function TAtlasWelcomeUnsavedFrame.ButtonText(const AItem: TAtlasUnsavedItem): string;
begin
  if AItem.CanPush then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedPush)
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedView);
end;

class function TAtlasWelcomeUnsavedFrame.EmptyText(const AView: TAtlasUnsavedView): string;
begin
  if AView.Hidden > 0 then
    Result := TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedHiddenOnly, [AView.Hidden])
  else if AView.Querying and not AView.Known then
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedQuerying)
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedClean);
end;

class function TAtlasWelcomeUnsavedFrame.LevelColor(ALevel: TAtlasUnsavedLevel): TColor;
begin
  // Dieselben Töne wie die Marken im Bereich „Projekte“: lesbar im hellen und im dunklen Thema.
  case ALevel of
    TAtlasUnsavedLevel.Warning:
      Result := TColor($001A8CC9);
    TAtlasUnsavedLevel.Alert:
      Result := TColor($002E22CF);
  else
    Result := TColor($0043A02E);
  end;
end;

class function TAtlasWelcomeUnsavedFrame.HintFor(const ARow: TAtlasUnsavedRow): string;
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Add(ARow.Project);
    Lines.Add(WhatText(ARow.Item));
    if Length(ARow.Item.Branches) > 0 then
      Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedHintBranches, [Joined(ARow.Item.Branches)]));
    if ARow.Item.Since > 0 then
      Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeUnsavedHintSince, [LocalText(ARow.Item.Since)]));
    if ARow.Stale and (ARow.At > 0) then
      Lines.Add(TAtlasStrings.Fmt(TAtlasTextId.WelcomeProjectsStale, [LocalText(ARow.At)]));
    if ARow.Item.CanPush then
      Lines.Add(TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedHintPush))
    else
      Lines.Add(TAtlasStrings.Text(TAtlasTextId.WelcomeUnsavedHintView));
    Result := TrimRight(Lines.Text);
  finally
    Lines.Free;
  end;
end;

procedure TAtlasWelcomeUnsavedFrame.LayoutButtons;
var
  Row, mWidth, mTop, Right: Integer;
  Canvas: TCanvas;
begin
  // Schaltfläche rechts, mittig in der Zeile; die Rechtecke dienen auch dem Treffertest. Nur beim Zeichnen.
  SetLength(FButtonRects, Length(FView.Rows));
  Canvas := FBox.Canvas;
  Canvas.Font.Assign(Font);
  Right := FBox.Width - ScaleValue(Indent);
  for Row := 0 to High(FView.Rows) do
  begin
    mWidth := Canvas.TextWidth(ButtonText(FView.Rows[Row].Item)) + 2 * ScaleValue(ButtonPadding);
    mTop := RowTop(Row) + (ScaleValue(RowHeight) - ScaleValue(ButtonHeight)) div 2;
    FButtonRects[Row] := Rect(Right - mWidth, mTop, Right, mTop + ScaleValue(ButtonHeight));
  end;
end;

procedure TAtlasWelcomeUnsavedFrame.BoxPaint(Sender: TObject);
var
  Canvas: TCanvas;
  Row, mLeft, mTop, Dot, Limit: Integer;
  Data: TAtlasUnsavedRow;
  mText, Branch: string;
  TextColor, MutedColor, LineColor: TColor;
  Button: TRect;
  Stamp: TDateTime;
begin
  Canvas := FBox.Canvas;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(Font);
  // Farben des IDE-Themas (hell oder dunkel).
  TextColor := StyleServices(Self).GetSystemColor(clWindowText);
  MutedColor := StyleServices(Self).GetSystemColor(clGrayText);
  LineColor := StyleServices(Self).GetSystemColor(clBtnShadow);
  if Length(FView.Rows) = 0 then
  begin
    Canvas.Font.Color := MutedColor;
    Canvas.TextOut(ScaleValue(Indent), RowTop(0) + ScaleValue(4), EmptyText(FView));
    Exit;
  end;
  LayoutButtons;
  Stamp := NowUtc;
  Dot := ScaleValue(DotSize);
  for Row := 0 to High(FView.Rows) do
  begin
    Data := FView.Rows[Row];
    mTop := RowTop(Row);
    mLeft := ScaleValue(Indent);
    Button := FButtonRects[Row];
    // Ampel.
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := LevelColor(Data.Level);
    Canvas.Pen.Color := Canvas.Brush.Color;
    Canvas.Ellipse(mLeft, mTop + ScaleValue(6), mLeft + Dot, mTop + ScaleValue(6) + Dot);
    Canvas.Brush.Style := bsClear;
    Inc(mLeft, Dot + ScaleValue(6));
    Limit := Button.Left - ScaleValue(Indent);
    Canvas.Font.Assign(Font);
    Canvas.Font.Color := TextColor;
    Canvas.Font.Style := [fsBold];
    Canvas.TextRect(Rect(mLeft, mTop + ScaleValue(3), Limit, mTop + ScaleValue(21)), mLeft, mTop + ScaleValue(3),
      Data.Name);
    Inc(mLeft, Canvas.TextWidth(Data.Name));
    Canvas.Font.Style := [];
    Branch := Data.Branch;
    if (Branch <> '') and (mLeft < Limit) then
    begin
      Canvas.Font.Color := MutedColor;
      Canvas.TextRect(Rect(mLeft, mTop + ScaleValue(3), Limit, mTop + ScaleValue(21)), mLeft, mTop + ScaleValue(3),
        Separator + Branch);
    end;
    // Zweite Zeile.
    mLeft := ScaleValue(Indent) + Dot + ScaleValue(6);
    Canvas.Font.Color := MutedColor;
    Canvas.TextRect(Rect(mLeft, mTop + ScaleValue(23), Limit, mTop + ScaleValue(41)), mLeft, mTop + ScaleValue(23),
      DetailText(Data, Stamp));
    // Schaltfläche.
    Canvas.Pen.Color := LineColor;
    Canvas.Brush.Style := bsClear;
    Canvas.RoundRect(Button.Left, Button.Top, Button.Right, Button.Bottom, ScaleValue(6), ScaleValue(6));
    Canvas.Font.Color := TextColor;
    mText := ButtonText(Data.Item);
    Canvas.TextOut(Button.Left + (Button.Width - Canvas.TextWidth(mText)) div 2,
      Button.Top + (Button.Height - Canvas.TextHeight(mText)) div 2, mText);
  end;
end;

function TAtlasWelcomeUnsavedFrame.HitTest(X, Y: Integer): TAtlasUnsavedHit;
begin
  Result.Row := -1;
  Result.Button := False;
  if (Y < RowTop(0)) or (Length(FView.Rows) = 0) then
    Exit;
  Result.Row := (Y - RowTop(0)) div ScaleValue(RowHeight);
  if Result.Row > High(FView.Rows) then
  begin
    Result.Row := -1;
    Exit;
  end;
  if Result.Row <= High(FButtonRects) then
    Result.Button := FButtonRects[Result.Row].Contains(Point(X, Y));
end;

procedure TAtlasWelcomeUnsavedFrame.ClickAt(const AHit: TAtlasUnsavedHit);
var
  mSource: IAtlasUnsavedSource;
  Row: TAtlasUnsavedRow;
begin
  if (FSource = nil) or not AHit.Button or (AHit.Row < 0) or (AHit.Row > High(FView.Rows)) then
    Exit;
  mSource := FSource;
  Row := FView.Rows[AHit.Row];
  // Die Quelle füllt den Bereich danach neu (und „Push …“ zeigt einen Dialog): nicht im eigenen Mausereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if Row.Item.CanPush then
        mSource.Push(Row)
      else
        mSource.Show(Row);
    end);
end;

procedure TAtlasWelcomeUnsavedFrame.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Hit: TAtlasUnsavedHit;
begin
  Hit := HitTest(X, Y);
  if Hit.Button then
    FBox.Cursor := crHandPoint
  else
    FBox.Cursor := crDefault;
  if Hit.Row = FHintRow then
    Exit;
  FHintRow := Hit.Row;
  if Hit.Row >= 0 then
    FBox.Hint := HintFor(FView.Rows[Hit.Row])
  else
    FBox.Hint := '';
  Application.CancelHint;
end;

procedure TAtlasWelcomeUnsavedFrame.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if Button = mbLeft then
    ClickAt(HitTest(X, Y));
end;

procedure TAtlasWelcomeUnsavedFrame.MenuPopup(Sender: TObject);
var
  Position: TPoint;
begin
  Position := FBox.ScreenToClient(FMenu.PopupPoint);
  FMenuRow := HitTest(Position.X, Position.Y).Row;
  FOpenFolderItem.Enabled := FMenuRow >= 0;
  FIgnoreItem.Enabled := FMenuRow >= 0;
end;

function TAtlasWelcomeUnsavedFrame.MenuTarget(out ARow: TAtlasUnsavedRow): Boolean;
begin
  ARow := Default(TAtlasUnsavedRow);
  Result := (FSource <> nil) and (FMenuRow >= 0) and (FMenuRow <= High(FView.Rows));
  if Result then
    ARow := FView.Rows[FMenuRow];
end;

procedure TAtlasWelcomeUnsavedFrame.OpenFolderClick(Sender: TObject);
var
  mSource: IAtlasUnsavedSource;
  Row: TAtlasUnsavedRow;
begin
  if not MenuTarget(Row) then
    Exit;
  mSource := FSource;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.OpenFolder(Row);
    end);
end;

procedure TAtlasWelcomeUnsavedFrame.IgnoreClick(Sender: TObject);
var
  mSource: IAtlasUnsavedSource;
  Row: TAtlasUnsavedRow;
begin
  if not MenuTarget(Row) then
    Exit;
  mSource := FSource;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.Ignore(Row);
    end);
end;

end.
