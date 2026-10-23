unit Atlas.IDE.Notes.Gutter;

// Persönliche Notizen in der Rinne (#545) als Schicht der gemeinsamen
// Zeichenschicht TAtlasIdeGutterMarks (auch für die Lesezeichen #622):
// - Symbol: kleines Notizblatt im Akzent, wenn an der Zeile eine Notiz steht
//   und der Zeileninhalt noch zum Anker passt (sonst wartet das Symbol auf die
//   nächste Verankerung).
// - Tooltip: „Notiz vom 15.10.2026“ und der Text, bei mehreren Notizen an der
//   Zeile alle untereinander.
// - Verankerung: neue Datei vorn bzw. nach einer Tipp-Pause über
//   TAtlasIdeNotes.Track, damit die Notizen eingefügten und gelöschten Zeilen
//   folgen.
// Abschaltbar über die Einstellung „Notizen“; Sicherung über
// TAtlasFeature.Notes (#493).

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Notes.Store,
  Atlas.IDE.Foundation.GutterMarks;

type
  TAtlasIdeNotesGutter = class(TAtlasGutterLayer)
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
    /// <summary>Überschrift und Text des Tooltips für die Notizen einer Zeile.</summary>
    class procedure NotesTipText(const ANotes: TArray<TAtlasNote>; out ATitle, AText: string); static;
  end;

implementation

uses
  System.Math,
  System.DateUtils,
  Atlas.Core.Editor.LineAnchor,
  Atlas.UI.Strings,
  Atlas.IDE.Notes.Service,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeNotesGutter }

function TAtlasIdeNotesGutter.Feature: TAtlasFeature;
begin
  Result := TAtlasFeature.Notes;
end;

function TAtlasIdeNotesGutter.Element: TAtlasDrawnElement;
begin
  Result := TAtlasDrawnElement.Notes;
end;

function TAtlasIdeNotesGutter.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Notes;
end;

procedure TAtlasIdeNotesGutter.Track(const AFileName, AText: string; AOpened: Boolean);
begin
  TAtlasIdeNotes.Track(AFileName, AText);
end;

function TAtlasIdeNotesGutter.HasMarks(const AFileName: string): Boolean;
begin
  Result := TAtlasIdeNotes.HasNotes(AFileName);
end;

function TAtlasIdeNotesGutter.MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean): Boolean;
var
  Notes: TArray<TAtlasNote>;
begin
  Notes := TAtlasIdeNotes.NotesAt(AFileName, ALine);
  // Nur, wenn die Zeile im Editor noch zum Anker passt; nach dem Tippen folgt die Verankerung.
  Result := (Length(Notes) > 0) and
    (not AHasText or (TAtlasLineAnchors.Normalize(ALineText) = Notes[0].Anchor.Text));
end;

procedure TAtlasIdeNotesGutter.PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
  ABack: TAtlasColor);
var
  Fold, Step, Y: Integer;
begin
  // Notizblatt mit umgeknickter Ecke und zwei Textzeilen, im Akzent.
  Fold := Max(2, AIcon.Width div 3);
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(TAtlasColorMath.Mix(AColors.Accent, ABack, 0.25));
  ACanvas.Pen.Color := TColor(TAtlasColorMath.Mix(AColors.Accent, ABack, 0.9));
  ACanvas.Pen.Width := 1;
  ACanvas.Polygon([Point(AIcon.Left, AIcon.Top), Point(AIcon.Right - Fold, AIcon.Top),
    Point(AIcon.Right, AIcon.Top + Fold), Point(AIcon.Right, AIcon.Bottom), Point(AIcon.Left, AIcon.Bottom)]);
  ACanvas.MoveTo(AIcon.Right - Fold, AIcon.Top);
  ACanvas.LineTo(AIcon.Right - Fold, AIcon.Top + Fold);
  ACanvas.LineTo(AIcon.Right, AIcon.Top + Fold);
  Step := Max(2, AIcon.Height div 4);
  Y := AIcon.Top + Fold + Step - 1;
  while Y < AIcon.Bottom - 1 do
  begin
    ACanvas.MoveTo(AIcon.Left + 2, Y);
    ACanvas.LineTo(AIcon.Right - 1, Y);
    Inc(Y, Step);
  end;
end;

function TAtlasIdeNotesGutter.TipText(const AFileName: string; ALine: Integer; out ATitle, AText: string): Boolean;
var
  Notes: TArray<TAtlasNote>;
begin
  Notes := TAtlasIdeNotes.NotesAt(AFileName, ALine);
  NotesTipText(Notes, ATitle, AText);
  Result := Length(Notes) > 0;
end;

class procedure TAtlasIdeNotesGutter.NotesTipText(const ANotes: TArray<TAtlasNote>; out ATitle, AText: string);
var
  Note: TAtlasNote;
  Stamp: TDateTime;
begin
  ATitle := '';
  AText := '';
  if Length(ANotes) = 0 then
    Exit;
  if Length(ANotes) = 1 then
  begin
    Stamp := ANotes[0].Changed;
    if Stamp = 0 then
      Stamp := ANotes[0].Created;
    ATitle := TAtlasStrings.Fmt(TAtlasTextId.NotesTipTitle, [DateToStr(TTimeZone.Local.ToLocalTime(Stamp), FormatSettings)]);
    AText := ANotes[0].Text;
    Exit;
  end;
  ATitle := TAtlasStrings.Fmt(TAtlasTextId.NotesTipMore, [Length(ANotes)]);
  for Note in ANotes do
  begin
    if AText <> '' then
      AText := AText + #10#10;
    AText := AText + Note.Text;
  end;
end;

end.
