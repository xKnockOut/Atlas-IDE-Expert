unit Atlas.IDE.Debug.LogpointGutter;

// Logpunkte (#583) in der Rinne als Schicht von TAtlasIdeGutterMarks: eine
// Raute im Akzent an jeder Zeile mit Logpunkt, abgeschaltete grau. Der
// Tooltip zeigt den Text mit Platzhaltern und die Bedingung. Das Element zum
// Ausblenden ist die Atlas-Spalte (GutterColumn). Abschaltbar über
// debug.logpoints; Sicherung über TAtlasFeature.Debugger (#493).

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.GutterMarks;

type
  TAtlasIdeLogpointGutter = class(TAtlasGutterLayer)
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
  end;

implementation

uses
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Logpoints,
  Atlas.UI.Debug.Strings;

const
  /// <summary>Anteil des Akzents an der Füllung der Raute.</summary>
  cFillShare = 0.85;

function TAtlasIdeLogpointGutter.Feature: TAtlasFeature;
begin
  Result := TAtlasFeature.Debugger;
end;

function TAtlasIdeLogpointGutter.Element: TAtlasDrawnElement;
begin
  Result := TAtlasDrawnElement.GutterColumn;
end;

function TAtlasIdeLogpointGutter.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DebugLogpoints and TAtlasIdeLogpoints.Started;
end;

procedure TAtlasIdeLogpointGutter.Track(const AFileName, AText: string; AOpened: Boolean);
begin
  TAtlasIdeLogpoints.Refresh(AOpened);
end;

function TAtlasIdeLogpointGutter.HasMarks(const AFileName: string): Boolean;
begin
  // Haltepunkte ändert auch die IDE (Haltepunktliste); höchstens alle cRefreshMs neu lesen.
  TAtlasIdeLogpoints.Refresh(False);
  Result := Length(TAtlasIdeLogpoints.Marks(AFileName)) > 0;
end;

function TAtlasIdeLogpointGutter.MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean): Boolean;
var
  mMark: TAtlasIdeLogpointMark;
begin
  Result := TAtlasIdeLogpoints.TryMark(AFileName, ALine, mMark);
end;

procedure TAtlasIdeLogpointGutter.PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
  ABack: TAtlasColor);
var
  mMiddle: TPoint;
begin
  // Raute; die Farbe für „aus“ kennt die Schicht hier nicht, deshalb zeichnet sie immer im Akzent.
  mMiddle := AIcon.CenterPoint;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(TAtlasColorMath.Mix(AColors.Accent, ABack, cFillShare));
  ACanvas.Pen.Color := TColor(AColors.Accent);
  ACanvas.Pen.Width := 1;
  ACanvas.Polygon([Point(mMiddle.X, AIcon.Top), Point(AIcon.Right - 1, mMiddle.Y), Point(mMiddle.X, AIcon.Bottom - 1),
    Point(AIcon.Left, mMiddle.Y)]);
end;

function TAtlasIdeLogpointGutter.TipText(const AFileName: string; ALine: Integer;
  out ATitle, AText: string): Boolean;
var
  mMark: TAtlasIdeLogpointMark;
begin
  ATitle := '';
  AText := '';
  Result := TAtlasIdeLogpoints.TryMark(AFileName, ALine, mMark);
  if not Result then
  begin
    Exit;
  end;
  ATitle := TAtlasDebugStrings.Text(TAtlasDebugTextId.LogpointTipTitle);
  if not mMark.Enabled then
  begin
    ATitle := ATitle + ' (' + TAtlasDebugStrings.Text(TAtlasDebugTextId.LogpointTipOff) + ')';
  end;
  AText := mMark.Input.Text;
  if mMark.Input.Condition <> '' then
  begin
    AText := AText + #10 + TAtlasDebugStrings.Text(TAtlasDebugTextId.LogpointCondition) + ' ' +
      mMark.Input.Condition;
  end;
end;

end.
