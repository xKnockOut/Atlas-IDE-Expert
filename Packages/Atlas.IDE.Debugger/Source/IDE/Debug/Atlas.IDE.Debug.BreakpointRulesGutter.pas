unit Atlas.IDE.Debug.BreakpointRulesGutter;

// Haltepunkte mit Aufrufer-Bedingung (#2548) in der Rinne als Schicht von
// TAtlasIdeGutterMarks: ein Haken nach rechts („↳“) im Akzent an jeder Zeile,
// deren Haltepunkt-Regel einen Aufrufer nennt. Der Tooltip nennt den
// Aufrufer. Das Element zum Ausblenden ist die Atlas-Spalte (GutterColumn).
// Abschaltbar über debug.breakpointRules; Sicherung über
// TAtlasFeature.Debugger (#493).

interface

uses
  System.Types,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.GutterMarks;

type
  TAtlasIdeBreakpointRulesGutter = class(TAtlasGutterLayer)
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
  Atlas.Core.Debug.BreakpointRules,
  Atlas.IDE.Debug.BreakpointRules,
  Atlas.UI.Debug.Breakpoints.Strings;

const
  /// <summary>Der Haken teilt das Symbol in Viertel: senkrechter Strich bei einem Viertel, waagrechter bei drei
  /// Vierteln, Pfeilspitze ein Viertel hoch.</summary>
  cQuarters = 4;
  cBottomQuarters = 3;

{ TAtlasIdeBreakpointRulesGutter }

function TAtlasIdeBreakpointRulesGutter.Feature: TAtlasFeature;
begin
  Result := TAtlasFeature.Debugger;
end;

function TAtlasIdeBreakpointRulesGutter.Element: TAtlasDrawnElement;
begin
  Result := TAtlasDrawnElement.GutterColumn;
end;

function TAtlasIdeBreakpointRulesGutter.Wanted: Boolean;
begin
  Result := TAtlasIdeBreakpointRules.Enabled;
end;

procedure TAtlasIdeBreakpointRulesGutter.Track(const AFileName, AText: string; AOpened: Boolean);
begin
  // Die Regeln liegen im Speicher; nichts nachzulesen.
end;

function TAtlasIdeBreakpointRulesGutter.HasMarks(const AFileName: string): Boolean;
begin
  Result := TAtlasIdeBreakpointRules.HasCallers(AFileName);
end;

function TAtlasIdeBreakpointRulesGutter.MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean): Boolean;
var
  mRule: TAtlasBreakpointRule;
begin
  Result := TAtlasIdeBreakpointRules.RuleAt(AFileName, ALine, mRule) and mRule.HasCaller;
end;

procedure TAtlasIdeBreakpointRulesGutter.PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
  ABack: TAtlasColor);
var
  mLeft, mBottom, mRight, mHead: Integer;
begin
  // Haken: senkrecht nach unten, dann nach rechts mit Pfeilspitze.
  mLeft := AIcon.Left + AIcon.Width div cQuarters;
  mBottom := AIcon.Top + (AIcon.Height * cBottomQuarters) div cQuarters;
  mRight := AIcon.Right - 1;
  mHead := AIcon.Height div cQuarters;
  ACanvas.Pen.Color := TColor(AColors.Accent);
  ACanvas.Pen.Width := 1;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := TColor(AColors.Accent);
  ACanvas.Polyline([Point(mLeft, AIcon.Top), Point(mLeft, mBottom), Point(mRight - mHead, mBottom)]);
  ACanvas.Polygon([Point(mRight - mHead, mBottom - mHead), Point(mRight, mBottom),
    Point(mRight - mHead, mBottom + mHead)]);
end;

function TAtlasIdeBreakpointRulesGutter.TipText(const AFileName: string; ALine: Integer;
  out ATitle, AText: string): Boolean;
var
  mRule: TAtlasBreakpointRule;
begin
  ATitle := '';
  AText := '';
  Result := TAtlasIdeBreakpointRules.RuleAt(AFileName, ALine, mRule) and mRule.HasCaller;
  if not Result then
  begin
    Exit;
  end;
  ATitle := TAtlasBreakpointsStrings.Text(TAtlasBreakpointsTextId.BreakpointRulesCallerTipTitle);
  if mRule.CallerDirect then
  begin
    AText := TAtlasBreakpointsStrings.Fmt(TAtlasBreakpointsTextId.BreakpointRulesCallerTipDirect, [mRule.Caller]);
  end
  else
  begin
    AText := TAtlasBreakpointsStrings.Fmt(TAtlasBreakpointsTextId.BreakpointRulesCallerTip, [mRule.Caller]);
  end;
end;

end.
