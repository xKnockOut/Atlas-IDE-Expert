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
  cTargetNames: array[TAtlasReassignedTarget] of string = ('locals', 'loopVars', 'valueParams', 'varParams',
    'fields');

class function TAtlasReassignedNames.TargetName(ATarget: TAtlasReassignedTarget): string;
begin
  Result := cTargetNames[ATarget];
end;

class function TAtlasReassignedNames.TryTarget(const AName: string; out ATarget: TAtlasReassignedTarget): Boolean;
var
  mTarget: TAtlasReassignedTarget;
begin
  for mTarget := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
  begin
    if SameText(Trim(AName), cTargetNames[mTarget]) then
    begin
      ATarget := mTarget;
      Exit(True);
    end;
  end;
  ATarget := TAtlasReassignedTarget.Locals;
  Result := False;
end;

class function TAtlasReassignedNames.ParseTargets(const AText: string): TAtlasReassignedTargets;
var
  mPart: string;
  mTarget: TAtlasReassignedTarget;
begin
  Result := [];
  for mPart in AText.Split([',', ';', ' ']) do
  begin
    if TryTarget(mPart, mTarget) then
    begin
      Include(Result, mTarget);
    end;
  end;
end;

class function TAtlasReassignedNames.TargetsText(ATargets: TAtlasReassignedTargets): string;
var
  mTarget: TAtlasReassignedTarget;
begin
  Result := '';
  for mTarget := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
  begin
    if mTarget in ATargets then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + cTargetNames[mTarget];
    end;
  end;
end;

class function TAtlasReassignedNames.NormalizeTargets(const AText: string): string;
begin
  Result := TargetsText(ParseTargets(AText));
end;

class function TAtlasReassignedNames.StyleOf(const AText: string): TAtlasReassignedStyle;
var
  mStyle: TAtlasReassignedStyle;
begin
  for mStyle := Low(TAtlasReassignedStyle) to High(TAtlasReassignedStyle) do
  begin
    if SameText(Trim(AText), Styles[mStyle]) then
    begin
      Exit(mStyle);
    end;
  end;
  Result := TAtlasReassignedStyle.Dotted;
end;

class function TAtlasReassignedNames.TryColor(const AText: string; out AColor: TAtlasColor): Boolean;
var
  mValue: Integer;
  mText: string;
begin
  AColor := 0;
  mText := Trim(AText);
  Result := (Length(mText) = 7) and (mText[1] = '#') and TryStrToInt('$' + Copy(mText, 2, 6), mValue);
  if Result then
  begin
    AColor := TAtlasColorMath.FromHex(mText);
  end;
end;

class function TAtlasReassignedNames.NormalizeColor(const AText: string): string;
var
  mColor: TAtlasColor;
begin
  if TryColor(AText, mColor) then
  begin
    Result := TAtlasColorMath.ToHex(mColor);
  end
  else
  begin
    Result := ThemeColor;
  end;
end;

end.
