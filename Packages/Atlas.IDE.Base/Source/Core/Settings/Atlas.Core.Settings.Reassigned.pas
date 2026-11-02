unit Atlas.Core.Settings.Reassigned;

// Einstellungen der Unterstreichung neu zugewiesener Variablen (#712):
// - highlight.reassigned.targets: kommagetrennte Arten (locals, loopVars,
//   valueParams, varParams, fields; Vorgabe "locals,valueParams"); unbekannte
//   fallen weg, die Reihenfolge ist fest. Dieselben Namen versteht der Server
//   (atlas.server.reassigned).
// - highlight.reassigned.style: dotted, solid oder wavy.
// - highlight.reassigned.color: theme (Akzentfarbe des Themas) oder #RRGGBB.
// Liegt bei den Einstellungen, damit der Parser ohne den Editor-Kern auskommt;
// Antwort und Zeichnen rechnet Atlas.Core.Editor.Reassigned.

interface

uses
  Atlas.Core.Style.Color;

type
{$SCOPEDENUMS ON}
  TAtlasReassignedTarget = (Locals, LoopVars, ValueParams, VarParams, Fields);
  TAtlasReassignedStyle = (Dotted, Solid, Wavy);
{$SCOPEDENUMS OFF}
  TAtlasReassignedTargets = set of TAtlasReassignedTarget;

  TAtlasReassignedNames = class
  public const
    DefaultTargets = [TAtlasReassignedTarget.Locals, TAtlasReassignedTarget.ValueParams];
    Styles: array[TAtlasReassignedStyle] of string = ('dotted', 'solid', 'wavy');
    ThemeColor = 'theme';
  public
    class function TargetName(ATarget: TAtlasReassignedTarget): string; static;
    class function TryTarget(const AName: string; out ATarget: TAtlasReassignedTarget): Boolean; static;
    class function ParseTargets(const AText: string): TAtlasReassignedTargets; static;
    class function TargetsText(ATargets: TAtlasReassignedTargets): string; static;
    /// <summary>Bekannte Namen in fester Reihenfolge, ohne Doppelte.</summary>
    class function NormalizeTargets(const AText: string): string; static;
    /// <summary>Art der Linie; unbekannt = dotted.</summary>
    class function StyleOf(const AText: string): TAtlasReassignedStyle; static;
    /// <summary>Eigene Farbe aus #RRGGBB; False bei theme oder unlesbarem Wert (dann gilt die Themenfarbe).</summary>
    class function TryColor(const AText: string; out AColor: TAtlasColor): Boolean; static;
    /// <summary>theme oder #RRGGBB in Großbuchstaben; Unlesbares wird theme.</summary>
    class function NormalizeColor(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils;

const
  TargetNames: array[TAtlasReassignedTarget] of string = ('locals', 'loopVars', 'valueParams', 'varParams',
    'fields');

class function TAtlasReassignedNames.TargetName(ATarget: TAtlasReassignedTarget): string;
begin
  Result := TargetNames[ATarget];
end;

class function TAtlasReassignedNames.TryTarget(const AName: string; out ATarget: TAtlasReassignedTarget): Boolean;
var
  Target: TAtlasReassignedTarget;
begin
  for Target := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
    if SameText(Trim(AName), TargetNames[Target]) then
    begin
      ATarget := Target;
      Exit(True);
    end;
  ATarget := TAtlasReassignedTarget.Locals;
  Result := False;
end;

class function TAtlasReassignedNames.ParseTargets(const AText: string): TAtlasReassignedTargets;
var
  Part: string;
  Target: TAtlasReassignedTarget;
begin
  Result := [];
  for Part in AText.Split([',', ';', ' ']) do
    if TryTarget(Part, Target) then
      Include(Result, Target);
end;

class function TAtlasReassignedNames.TargetsText(ATargets: TAtlasReassignedTargets): string;
var
  Target: TAtlasReassignedTarget;
begin
  Result := '';
  for Target := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
    if Target in ATargets then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + TargetNames[Target];
    end;
end;

class function TAtlasReassignedNames.NormalizeTargets(const AText: string): string;
begin
  Result := TargetsText(ParseTargets(AText));
end;

class function TAtlasReassignedNames.StyleOf(const AText: string): TAtlasReassignedStyle;
var
  Style: TAtlasReassignedStyle;
begin
  for Style := Low(TAtlasReassignedStyle) to High(TAtlasReassignedStyle) do
    if SameText(Trim(AText), Styles[Style]) then
      Exit(Style);
  Result := TAtlasReassignedStyle.Dotted;
end;

class function TAtlasReassignedNames.TryColor(const AText: string; out AColor: TAtlasColor): Boolean;
var
  Value: Integer;
  Text: string;
begin
  AColor := 0;
  Text := Trim(AText);
  Result := (Length(Text) = 7) and (Text[1] = '#') and TryStrToInt('$' + Copy(Text, 2, 6), Value);
  if Result then
    AColor := TAtlasColorMath.FromHex(Text);
end;

class function TAtlasReassignedNames.NormalizeColor(const AText: string): string;
var
  Color: TAtlasColor;
begin
  if TryColor(AText, Color) then
    Result := TAtlasColorMath.ToHex(Color)
  else
    Result := ThemeColor;
end;

end.
