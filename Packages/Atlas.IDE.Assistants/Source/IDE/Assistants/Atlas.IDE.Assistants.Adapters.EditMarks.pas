unit Atlas.IDE.Assistants.Adapters.EditMarks;

// Randmarken an Zeilen, die KI-Assistenten geändert haben (#2616, Stufe 2), als Schicht der gemeinsamen
// Zeichenschicht der Rinne (TAtlasIdeGutterMarks):
// - je geänderter Zeile ein senkrechter Balken in der Farbe der Sitzung des Assistenten
//   (TAtlasAssistantSessions.ColorOf; dieselbe Farbe wie die Spalte im KI-Protokoll), unbekannte Herkunft grau;
// - Tooltip: Assistent (Client · Sitzung) und Uhrzeit, bei einer Löschung die Zahl der entfernten Zeilen;
// - die Marken wandern beim Tippen mit (Track) und verschwinden, sobald die Datei gespeichert ist
//   (IAtlasFollowsSaves; das eigene Speichern des Eingangs zählt nicht) und mit dem Modul.
// Die Marken selbst hält Atlas.Core.Assistants.EditMarks; sie gehören der Composition. Abschaltbar über
// assistants.editMarks (und assistants.edit) und am Element (#628); gesichert über TAtlasFeature.Files.
// Nur im Hauptthread.

interface

uses
  System.Types,
  Vcl.Graphics,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Style.Color,
  Atlas.Plugin.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.Core.Assistants.EditMarks,
  Atlas.IDE.Foundation.GutterMarks;

type
  /// <summary>Marken der Composition; nil, solange es keine gibt.</summary>
  TAtlasEditMarksSource = reference to function: TAtlasEditMarks;

  TAtlasIdeEditMarks = class(TAtlasGutterLayer, IAtlasFollowsSaves)
  private const
    /// <summary>Breite des Balkens in Teilen des Symbolplatzes.</summary>
    cBarShare = 3;
    cBarMinWidth = 2;
  private
    FMarks: TAtlasEditMarksSource;
    /// <summary>Marke aus dem letzten MarkAt; TAtlasIdeGutterMarks zeichnet direkt danach.</summary>
    FLast: TAtlasEditMark;
  public
    constructor Create(const AMarks: TAtlasEditMarksSource);
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
    procedure FileSaved(const AFileName: string);
    /// <summary>Überschrift und Text des Tooltips einer Marke.</summary>
    class procedure TipOf(const AMark: TAtlasEditMark; out ATitle, AText: string); static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Assistants.Sessions,
  Atlas.UI.Assistants.Strings;

{ TAtlasIdeEditMarks }

constructor TAtlasIdeEditMarks.Create(const AMarks: TAtlasEditMarksSource);
begin
  inherited Create;
  FMarks := AMarks;
end;

function TAtlasIdeEditMarks.Feature: TAtlasFeature;
begin
  Result := TAtlasFeature.Files;
end;

function TAtlasIdeEditMarks.Element: TAtlasDrawnElement;
begin
  Result := TAtlasDrawnElement.AssistantEdits;
end;

function TAtlasIdeEditMarks.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.AssistantsEdit and TAtlasIdeSettings.Current.AssistantsEditMarks and
    (FMarks() <> nil);
end;

procedure TAtlasIdeEditMarks.Track(const AFileName, AText: string; AOpened: Boolean);
var
  mMarks: TAtlasEditMarks;
begin
  mMarks := FMarks();
  if mMarks <> nil then
  begin
    mMarks.Track(AFileName, AText);
  end;
end;

function TAtlasIdeEditMarks.HasMarks(const AFileName: string): Boolean;
var
  mMarks: TAtlasEditMarks;
begin
  mMarks := FMarks();
  Result := (mMarks <> nil) and mMarks.HasMarks(AFileName);
end;

function TAtlasIdeEditMarks.MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean): Boolean;
var
  mMarks: TAtlasEditMarks;
begin
  mMarks := FMarks();
  Result := (mMarks <> nil) and mMarks.MarkAt(AFileName, ALine, ALineText, AHasText, FLast);
end;

procedure TAtlasIdeEditMarks.PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
  ABack: TAtlasColor);
var
  mBar: TRect;
  mWidth: Integer;
begin
  mWidth := Max(cBarMinWidth, AIcon.Width div cBarShare);
  mBar := TRect.Create(AIcon.Left + (AIcon.Width - mWidth) div 2, AIcon.Top, 0, AIcon.Bottom);
  mBar.Right := mBar.Left + mWidth;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(TAtlasAssistantSessions.ColorOf(FLast.Assistant, AColors));
  ACanvas.FillRect(mBar);
end;

class procedure TAtlasIdeEditMarks.TipOf(const AMark: TAtlasEditMark; out ATitle, AText: string);
var
  mTime: string;
begin
  ATitle := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.MarkTipTitle,
    [TAtlasAssistantsStrings.Assistant(AMark.Origin)]);
  mTime := FormatDateTime('hh:nn:ss', AMark.At, FormatSettings);
  if AMark.Removed > 0 then
  begin
    AText := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.MarkTipRemoved, [mTime, AMark.Removed]);
  end
  else
  begin
    AText := TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.MarkTipText, [mTime]);
  end;
end;

function TAtlasIdeEditMarks.TipText(const AFileName: string; ALine: Integer; out ATitle, AText: string): Boolean;
var
  mMarks: TAtlasEditMarks;
  mMark: TAtlasEditMark;
begin
  ATitle := '';
  AText := '';
  mMarks := FMarks();
  Result := (mMarks <> nil) and mMarks.MarkAt(AFileName, ALine, '', False, mMark);
  if Result then
  begin
    TipOf(mMark, ATitle, AText);
  end;
end;

procedure TAtlasIdeEditMarks.FileSaved(const AFileName: string);
var
  mMarks: TAtlasEditMarks;
begin
  mMarks := FMarks();
  if (mMarks <> nil) and mMarks.HasMarks(AFileName) then
  begin
    mMarks.Saved(AFileName);
    if not mMarks.HasMarks(AFileName) then
    begin
      TAtlasIdeGutterMarks.Invalidate;
    end;
  end;
end;

end.
