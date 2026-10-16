unit Atlas.IDE.Bookmarks.Gutter;

// Benannte Lesezeichen in der Rinne (#622) als Schicht der gemeinsamen
// Zeichenschicht TAtlasIdeGutterMarks (wie die Notizen, #545):
// - Symbol: kleines Lesezeichenband in der Warnfarbe, wenn an der Zeile ein
//   gefundenes Lesezeichen steht und der Zeileninhalt noch zum Anker passt
//   (sonst wartet das Symbol auf das nächste Wiederfinden).
// - Tooltip: „Lesezeichen“ und der Name, bei mehreren Lesezeichen an der
//   Zeile alle Namen untereinander.
// - Wiederfinden: neue Datei vorn bzw. nach einer Tipp-Pause über
//   TAtlasIdeBookmarks.Track.
// Abschaltbar über bookmarks.named; Sicherung über TAtlasFeature.Bookmarks
// (#493).

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Bookmarks.Store,
  Atlas.IDE.Foundation.GutterMarks;

type
  TAtlasIdeBookmarksGutter = class(TAtlasGutterLayer)
  public
    function Feature: TAtlasFeature; override;
    function Element: TAtlasDrawnElement; override;
    function Wanted: Boolean; override;
    procedure Track(const AFileName, AText: string; AOpened: Boolean); override;
    function HasMarks(const AFileName: string): Boolean; override;
    function MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
      AHasText: Boolean): Boolean; override;
    procedure PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
      ABack: TAtlasColor); override;
    function TipText(const AFileName: string; ALine: Integer; out ATitle, AText: string): Boolean; override;
    /// <summary>Überschrift und Text des Tooltips für die Lesezeichen einer Zeile.</summary>
    class procedure BookmarksTipText(const ABookmarks: TArray<TAtlasBookmark>; out ATitle, AText: string); static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Editor.LineAnchor,
  Atlas.UI.Strings,
  Atlas.IDE.Bookmarks.Service,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeBookmarksGutter }

function TAtlasIdeBookmarksGutter.Feature: TAtlasFeature;
begin
  Result := TAtlasFeature.Bookmarks;
end;

function TAtlasIdeBookmarksGutter.Element: TAtlasDrawnElement;
begin
  Result := TAtlasDrawnElement.Bookmarks;
end;

function TAtlasIdeBookmarksGutter.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.BookmarksNamed;
end;

procedure TAtlasIdeBookmarksGutter.Track(const AFileName, AText: string; AOpened: Boolean);
begin
  TAtlasIdeBookmarks.Track(AFileName, AText);
end;

function TAtlasIdeBookmarksGutter.HasMarks(const AFileName: string): Boolean;
begin
  Result := TAtlasIdeBookmarks.HasBookmarks(AFileName);
end;

function TAtlasIdeBookmarksGutter.MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean): Boolean;
var
  Marks: TArray<TAtlasBookmark>;
begin
  Marks := TAtlasIdeBookmarks.BookmarksAt(AFileName, ALine);
  // Nur, wenn die Zeile im Editor noch zum Anker passt; nach dem Tippen folgt das Wiederfinden.
  Result := (Length(Marks) > 0) and
    (not AHasText or (TAtlasLineAnchors.Normalize(ALineText) = Marks[0].Anchor.Text));
end;

procedure TAtlasIdeBookmarksGutter.PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
  ABack: TAtlasColor);
var
  Notch, Left, Right: Integer;
begin
  // Lesezeichenband: schmales Rechteck mit Kerbe unten, in der Warnfarbe.
  Left := AIcon.Left + Max(0, (AIcon.Width - Max(4, (AIcon.Width * 3) div 4)) div 2);
  Right := Left + Max(4, (AIcon.Width * 3) div 4);
  Notch := Max(2, AIcon.Height div 4);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(TAtlasColorMath.Mix(AColors.Warn, ABack, 0.85));
  ACanvas.Pen.Color := TColor(AColors.Warn);
  ACanvas.Pen.Width := 1;
  ACanvas.Polygon([Point(Left, AIcon.Top), Point(Right, AIcon.Top), Point(Right, AIcon.Bottom),
    Point((Left + Right) div 2, AIcon.Bottom - Notch), Point(Left, AIcon.Bottom)]);
end;

function TAtlasIdeBookmarksGutter.TipText(const AFileName: string; ALine: Integer;
  out ATitle, AText: string): Boolean;
var
  Marks: TArray<TAtlasBookmark>;
begin
  Marks := TAtlasIdeBookmarks.BookmarksAt(AFileName, ALine);
  BookmarksTipText(Marks, ATitle, AText);
  Result := Length(Marks) > 0;
end;

class procedure TAtlasIdeBookmarksGutter.BookmarksTipText(const ABookmarks: TArray<TAtlasBookmark>;
  out ATitle, AText: string);
var
  Mark: TAtlasBookmark;
begin
  ATitle := '';
  AText := '';
  if Length(ABookmarks) = 0 then
    Exit;
  if Length(ABookmarks) = 1 then
    ATitle := TAtlasStrings.Text(TAtlasTextId.BookmarksTipTitle)
  else
    ATitle := TAtlasStrings.Fmt(TAtlasTextId.BookmarksTipMore, [Length(ABookmarks)]);
  for Mark in ABookmarks do
  begin
    if AText <> '' then
      AText := AText + #10;
    AText := AText + Mark.Name;
  end;
end;

end.
