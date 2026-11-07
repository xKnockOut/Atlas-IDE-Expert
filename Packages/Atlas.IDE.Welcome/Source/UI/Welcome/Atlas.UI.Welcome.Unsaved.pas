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

  /// <summary>Farben des IDE-Themas für eine Zeichnung des Bereichs.</summary>
  TAtlasUnsavedPalette = record
    Text: TColor;
    Muted: TColor;
    Line: TColor;
  end;

  /// <summary>Texte und Farben des Bereichs „Nicht gesichert“, ohne Steuerelement.</summary>
  TAtlasUnsavedTexts = class
  public
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
  end;

  TAtlasWelcomeUnsavedFrame = class(TAtlasWelcomeSectionFrame)
  public const
    cRowHeight = 44;
    cIndent = 8;
    cDotSize = 10;
    cButtonHeight = 22;
    cButtonPadding = 10;
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
    procedure PaintRow(ACanvas: TCanvas; ARow: Integer; const APalette: TAtlasUnsavedPalette; AStamp: TDateTime);
    procedure PaintButton(ACanvas: TCanvas; const AButton: TRect; const AText: string;
      const APalette: TAtlasUnsavedPalette);
    function RowTop(ARow: Integer): Integer;
    function MenuTarget(out ARow: TAtlasUnsavedRow): Boolean;
  protected
    function BodyHeight: Integer; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure UpdateContent; override;
    /// <summary>Zeile und Schaltfläche an X, Y (Koordinaten der Zeichenfläche).</summary>
    function HitTest(AX, AY: Integer): TAtlasUnsavedHit;
    /// <summary>Klick wie mit der Maus (auch für Tests); nur die Schaltfläche löst eine Aktion aus.</summary>
    procedure ClickAt(const AHit: TAtlasUnsavedHit);
    property Source: IAtlasUnsavedSource read FSource write SetSource;
    property View: TAtlasUnsavedView read FView;
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
  Atlas.UI.Welcome.Strings;

const
  cSeparator = ' · ';

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
  FOpenFolderItem.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedOpenFolder);
  FOpenFolderItem.OnClick := OpenFolderClick;
  FMenu.Items.Add(FOpenFolderItem);
  FIgnoreItem := TMenuItem.Create(Self);
  FIgnoreItem.Caption := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedIgnore);
  FIgnoreItem.OnClick := IgnoreClick;
  FMenu.Items.Add(FIgnoreItem);
  FBox.PopupMenu := FMenu;
end;

procedure TAtlasWelcomeUnsavedFrame.SetSource(const AValue: IAtlasUnsavedSource);
begin
  FSource := AValue;
  UpdateContent;
  if FSource <> nil then
  begin
    FSource.Shown;
  end;
end;

procedure TAtlasWelcomeUnsavedFrame.UpdateContent;
var
  mCount: Integer;
begin
  mCount := Length(FView.Rows);
  FView := Default(TAtlasUnsavedView);
  if FSource <> nil then
  begin
    FView := FSource.View;
  end;
  // Die Rechtecke der Schaltflächen entstehen beim Zeichnen.
  FButtonRects := nil;
  FHintRow := -1;
  FBox.Invalidate;
  inherited;
  if mCount <> Length(FView.Rows) then
  begin
    HeightChanged;
  end;
end;

function TAtlasWelcomeUnsavedFrame.BodyHeight: Integer;
var
  mRows: Integer;
begin
  mRows := Length(FView.Rows);
  if mRows < 1 then
  begin
    mRows := 1;
  end;
  Result := mRows * ScaleValue(cRowHeight) + ScaleValue(cIndent);
end;

function TAtlasWelcomeUnsavedFrame.RowTop(ARow: Integer): Integer;
begin
  Result := ScaleValue(cIndent) div 2 + ARow * ScaleValue(cRowHeight);
end;

class function TAtlasUnsavedTexts.NowUtc: TDateTime;
begin
  Result := TTimeZone.Local.ToUniversalTime(Now);
end;

class function TAtlasUnsavedTexts.LocalText(AUtc: TDateTime): string;
begin
  Result := '';
  if AUtc > 0 then
  begin
    Result := FormatDateTime('ddddd t', TTimeZone.Local.ToLocalTime(AUtc));
  end;
end;

function LocalDate(AUtc: TDateTime): string;
begin
  Result := '';
  if AUtc > 0 then
  begin
    Result := FormatDateTime('ddddd', TTimeZone.Local.ToLocalTime(AUtc));
  end;
end;

function Joined(const AItems: TArray<string>): string;
begin
  Result := string.Join(', ', AItems);
end;

class function TAtlasUnsavedTexts.TitleText(const ARow: TAtlasUnsavedRow): string;
begin
  Result := ARow.Name;
  if ARow.Branch <> '' then
  begin
    Result := Result + cSeparator + ARow.Branch;
  end;
end;

/// <summary>Geänderte Dateien: Summe, bei neuen oder gelöschten Dateien mit den Anteilen.</summary>
function ChangesText(const AItem: TAtlasUnsavedItem): string;
var
  mParts: TArray<string>;
begin
  if (AItem.Added = 0) and (AItem.Deleted = 0) then
  begin
    if AItem.Count = 1 then
    begin
      Exit(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedFileOne));
    end;
    Exit(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedFiles, [AItem.Count]));
  end;
  mParts := nil;
  if AItem.Modified > 0 then
  begin
    mParts := mParts + [TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedPartModified, [AItem.Modified])];
  end;
  if AItem.Added > 0 then
  begin
    mParts := mParts + [TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedPartAdded, [AItem.Added])];
  end;
  if AItem.Deleted > 0 then
  begin
    mParts := mParts + [TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedPartDeleted, [AItem.Deleted])];
  end;
  Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedFilesMixed, [AItem.Count, Joined(mParts)]);
end;

/// <summary>Nicht gepushte Commits mit den Branches.</summary>
function CommitsText(const AItem: TAtlasUnsavedItem): string;
begin
  if AItem.Count = 1 then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedCommitOne, [Joined(AItem.Branches)]);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedCommits,
      [AItem.Count, Joined(AItem.Branches)]);
  end;
end;

/// <summary>Branches ohne Upstream, dazu die Zahl ihrer lokalen Commits.</summary>
function NoUpstreamText(const AItem: TAtlasUnsavedItem): string;
begin
  if AItem.Count = 1 then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedNoUpstreamOne, [Joined(AItem.Branches)]);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedNoUpstream,
      [AItem.Count, Joined(AItem.Branches)]);
  end;
  if AItem.Commits > 0 then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedLocalCommits, [Result, AItem.Commits]);
  end;
end;

/// <summary>Abgelegte Änderungen (Stash) mit Name und Datum.</summary>
function StashText(const AItem: TAtlasUnsavedItem): string;
begin
  if AItem.Count = 1 then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedStash, [AItem.Name, LocalDate(AItem.Since)]);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedStashes, [AItem.Count, AItem.Name,
      LocalDate(AItem.Since)]);
  end;
end;

class function TAtlasUnsavedTexts.WhatText(const AItem: TAtlasUnsavedItem): string;
begin
  case AItem.Kind of
    TAtlasUnsavedKind.Changes:
      Result := ChangesText(AItem);
    TAtlasUnsavedKind.Conflicts:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedConflicts, [AItem.Count]);
    TAtlasUnsavedKind.Commits:
      Result := CommitsText(AItem);
    TAtlasUnsavedKind.NoUpstream:
      Result := NoUpstreamText(AItem);
  else
    Result := StashText(AItem);
  end;
end;

class function TAtlasUnsavedTexts.AgeText(ASince, ANowUtc: TDateTime): string;
var
  mValue: Integer;
  mAgeUnit: TAtlasUnsavedAgeUnit;
begin
  Result := '';
  if ASince <= 0 then
  begin
    Exit;
  end;
  TAtlasWelcomeUnsaved.Age(ASince, ANowUtc, mValue, mAgeUnit);
  case mAgeUnit of
    TAtlasUnsavedAgeUnit.Minutes:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedSinceMinutes, [mValue]);
    TAtlasUnsavedAgeUnit.Hours:
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedSinceHours, [mValue]);
  else
    if mValue = 1 then
    begin
      Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedSinceDayOne);
    end
    else
    begin
      Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedSinceDays, [mValue]);
    end;
  end;
end;

class function TAtlasUnsavedTexts.DetailText(const ARow: TAtlasUnsavedRow; ANowUtc: TDateTime): string;
var
  mAge, mPlaces: string;
begin
  Result := WhatText(ARow.Item);
  // Externals bzw. Submodule (#1292): die Summe mit den Anteilen je Arbeitskopie.
  mPlaces := TAtlasWelcomeUnsaved.PlacesText(ARow.Item, ARow.Name);
  if mPlaces <> '' then
  begin
    Result := Result + ' (' + mPlaces + ')';
  end;
  mAge := AgeText(ARow.Item.Since, ANowUtc);
  if mAge <> '' then
  begin
    Result := Result + cSeparator + mAge;
  end;
end;

class function TAtlasUnsavedTexts.ButtonText(const AItem: TAtlasUnsavedItem): string;
begin
  if AItem.CanPush then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedPush);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedView);
  end;
end;

class function TAtlasUnsavedTexts.EmptyText(const AView: TAtlasUnsavedView): string;
begin
  if AView.Hidden > 0 then
  begin
    Result := TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedHiddenOnly, [AView.Hidden]);
  end
  else if AView.Querying and not AView.Known then
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedQuerying);
  end
  else
  begin
    Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedClean);
  end;
end;

class function TAtlasUnsavedTexts.LevelColor(ALevel: TAtlasUnsavedLevel): TColor;
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

class function TAtlasUnsavedTexts.HintFor(const ARow: TAtlasUnsavedRow): string;
var
  mLines: TStringList;
begin
  mLines := TStringList.Create;
  try
    mLines.Add(ARow.Project);
    mLines.Add(WhatText(ARow.Item));
    if Length(ARow.Item.Branches) > 0 then
    begin
      mLines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedHintBranches,
        [Joined(ARow.Item.Branches)]));
    end;
    if ARow.Item.Since > 0 then
    begin
      mLines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeUnsavedHintSince, [LocalText(ARow.Item.Since)]));
    end;
    if ARow.Stale and (ARow.At > 0) then
    begin
      mLines.Add(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeProjectsStale, [LocalText(ARow.At)]));
    end;
    if ARow.Item.CanPush then
    begin
      mLines.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedHintPush));
    end
    else
    begin
      mLines.Add(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeUnsavedHintView));
    end;
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

procedure TAtlasWelcomeUnsavedFrame.LayoutButtons;
var
  mRow, mWidth, mTop, mRight: Integer;
  mCanvas: TCanvas;
begin
  // Schaltfläche rechts, mittig in der Zeile; die Rechtecke dienen auch dem Treffertest. Nur beim Zeichnen.
  SetLength(FButtonRects, Length(FView.Rows));
  mCanvas := FBox.Canvas;
  mCanvas.Font.Assign(Font);
  mRight := FBox.Width - ScaleValue(cIndent);
  for mRow := 0 to High(FView.Rows) do
  begin
    mWidth := mCanvas.TextWidth(TAtlasUnsavedTexts.ButtonText(FView.Rows[mRow].Item)) + 2 * ScaleValue(cButtonPadding);
    mTop := RowTop(mRow) + (ScaleValue(cRowHeight) - ScaleValue(cButtonHeight)) div 2;
    FButtonRects[mRow] := Rect(mRight - mWidth, mTop, mRight, mTop + ScaleValue(cButtonHeight));
  end;
end;

procedure TAtlasWelcomeUnsavedFrame.BoxPaint(Sender: TObject);
var
  mCanvas: TCanvas;
  mRow: Integer;
  mPalette: TAtlasUnsavedPalette;
  mStamp: TDateTime;
begin
  mCanvas := FBox.Canvas;
  mCanvas.Brush.Style := bsClear;
  mCanvas.Font.Assign(Font);
  // Farben des IDE-Themas (hell oder dunkel).
  mPalette.Text := StyleServices(Self).GetSystemColor(clWindowText);
  mPalette.Muted := StyleServices(Self).GetSystemColor(clGrayText);
  mPalette.Line := StyleServices(Self).GetSystemColor(clBtnShadow);
  if Length(FView.Rows) = 0 then
  begin
    mCanvas.Font.Color := mPalette.Muted;
    mCanvas.TextOut(ScaleValue(cIndent), RowTop(0) + ScaleValue(4), TAtlasUnsavedTexts.EmptyText(FView));
    Exit;
  end;
  LayoutButtons;
  mStamp := TAtlasUnsavedTexts.NowUtc;
  for mRow := 0 to High(FView.Rows) do
  begin
    PaintRow(mCanvas, mRow, mPalette, mStamp);
  end;
end;

procedure TAtlasWelcomeUnsavedFrame.PaintRow(ACanvas: TCanvas; ARow: Integer; const APalette: TAtlasUnsavedPalette;
  AStamp: TDateTime);
var
  mData: TAtlasUnsavedRow;
  mLeft, mTop, mDot, mLimit: Integer;
begin
  mData := FView.Rows[ARow];
  mTop := RowTop(ARow);
  mLeft := ScaleValue(cIndent);
  mDot := ScaleValue(cDotSize);
  // Ampel.
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TAtlasUnsavedTexts.LevelColor(mData.Level);
  ACanvas.Pen.Color := ACanvas.Brush.Color;
  ACanvas.Ellipse(mLeft, mTop + ScaleValue(6), mLeft + mDot, mTop + ScaleValue(6) + mDot);
  ACanvas.Brush.Style := bsClear;
  Inc(mLeft, mDot + ScaleValue(6));
  mLimit := FButtonRects[ARow].Left - ScaleValue(cIndent);
  ACanvas.Font.Assign(Font);
  ACanvas.Font.Color := APalette.Text;
  ACanvas.Font.Style := [fsBold];
  ACanvas.TextRect(Rect(mLeft, mTop + ScaleValue(3), mLimit, mTop + ScaleValue(21)), mLeft, mTop + ScaleValue(3),
    mData.Name);
  Inc(mLeft, ACanvas.TextWidth(mData.Name));
  ACanvas.Font.Style := [];
  if (mData.Branch <> '') and (mLeft < mLimit) then
  begin
    ACanvas.Font.Color := APalette.Muted;
    ACanvas.TextRect(Rect(mLeft, mTop + ScaleValue(3), mLimit, mTop + ScaleValue(21)), mLeft, mTop + ScaleValue(3),
      cSeparator + mData.Branch);
  end;
  // Zweite Zeile.
  mLeft := ScaleValue(cIndent) + mDot + ScaleValue(6);
  ACanvas.Font.Color := APalette.Muted;
  ACanvas.TextRect(Rect(mLeft, mTop + ScaleValue(23), mLimit, mTop + ScaleValue(41)), mLeft, mTop + ScaleValue(23),
    TAtlasUnsavedTexts.DetailText(mData, AStamp));
  PaintButton(ACanvas, FButtonRects[ARow], TAtlasUnsavedTexts.ButtonText(mData.Item), APalette);
end;

procedure TAtlasWelcomeUnsavedFrame.PaintButton(ACanvas: TCanvas; const AButton: TRect; const AText: string;
  const APalette: TAtlasUnsavedPalette);
begin
  ACanvas.Pen.Color := APalette.Line;
  ACanvas.Brush.Style := bsClear;
  ACanvas.RoundRect(AButton.Left, AButton.Top, AButton.Right, AButton.Bottom, ScaleValue(6), ScaleValue(6));
  ACanvas.Font.Color := APalette.Text;
  ACanvas.TextOut(AButton.Left + (AButton.Width - ACanvas.TextWidth(AText)) div 2,
    AButton.Top + (AButton.Height - ACanvas.TextHeight(AText)) div 2, AText);
end;

function TAtlasWelcomeUnsavedFrame.HitTest(AX, AY: Integer): TAtlasUnsavedHit;
begin
  Result.Row := -1;
  Result.Button := False;
  if (AY < RowTop(0)) or (Length(FView.Rows) = 0) then
  begin
    Exit;
  end;
  Result.Row := (AY - RowTop(0)) div ScaleValue(cRowHeight);
  if Result.Row > High(FView.Rows) then
  begin
    Result.Row := -1;
    Exit;
  end;
  if Result.Row <= High(FButtonRects) then
  begin
    Result.Button := FButtonRects[Result.Row].Contains(Point(AX, AY));
  end;
end;

procedure TAtlasWelcomeUnsavedFrame.ClickAt(const AHit: TAtlasUnsavedHit);
var
  mSource: IAtlasUnsavedSource;
  mRow: TAtlasUnsavedRow;
begin
  if (FSource = nil) or not AHit.Button or (AHit.Row < 0) or (AHit.Row > High(FView.Rows)) then
  begin
    Exit;
  end;
  mSource := FSource;
  mRow := FView.Rows[AHit.Row];
  // Die Quelle füllt den Bereich danach neu (und „Push …“ zeigt einen Dialog): nicht im eigenen Mausereignis.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if mRow.Item.CanPush then
      begin
        mSource.Push(mRow);
      end
      else
      begin
        mSource.Show(mRow);
      end;
    end);
end;

procedure TAtlasWelcomeUnsavedFrame.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  mHit: TAtlasUnsavedHit;
begin
  mHit := HitTest(X, Y);
  if mHit.Button then
  begin
    FBox.Cursor := crHandPoint;
  end
  else
  begin
    FBox.Cursor := crDefault;
  end;
  if mHit.Row = FHintRow then
  begin
    Exit;
  end;
  FHintRow := mHit.Row;
  if mHit.Row >= 0 then
  begin
    FBox.Hint := TAtlasUnsavedTexts.HintFor(FView.Rows[mHit.Row]);
  end
  else
  begin
    FBox.Hint := '';
  end;
  Application.CancelHint;
end;

procedure TAtlasWelcomeUnsavedFrame.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if Button = mbLeft then
  begin
    ClickAt(HitTest(X, Y));
  end;
end;

procedure TAtlasWelcomeUnsavedFrame.MenuPopup(Sender: TObject);
var
  mPosition: TPoint;
begin
  mPosition := FBox.ScreenToClient(FMenu.PopupPoint);
  FMenuRow := HitTest(mPosition.X, mPosition.Y).Row;
  FOpenFolderItem.Enabled := FMenuRow >= 0;
  FIgnoreItem.Enabled := FMenuRow >= 0;
end;

function TAtlasWelcomeUnsavedFrame.MenuTarget(out ARow: TAtlasUnsavedRow): Boolean;
begin
  ARow := Default(TAtlasUnsavedRow);
  Result := (FSource <> nil) and (FMenuRow >= 0) and (FMenuRow <= High(FView.Rows));
  if Result then
  begin
    ARow := FView.Rows[FMenuRow];
  end;
end;

procedure TAtlasWelcomeUnsavedFrame.OpenFolderClick(Sender: TObject);
var
  mSource: IAtlasUnsavedSource;
  mRow: TAtlasUnsavedRow;
begin
  if not MenuTarget(mRow) then
  begin
    Exit;
  end;
  mSource := FSource;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.OpenFolder(mRow);
    end);
end;

procedure TAtlasWelcomeUnsavedFrame.IgnoreClick(Sender: TObject);
var
  mSource: IAtlasUnsavedSource;
  mRow: TAtlasUnsavedRow;
begin
  if not MenuTarget(mRow) then
  begin
    Exit;
  end;
  mSource := FSource;
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      mSource.Ignore(mRow);
    end);
end;

end.
