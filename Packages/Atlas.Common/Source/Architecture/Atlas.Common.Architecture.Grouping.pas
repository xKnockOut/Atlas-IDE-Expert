unit Atlas.Common.Architecture.Grouping;

// Einstellungen der Gruppierung in Teilsysteme für die Architekturübersicht (architecture.grouping, #1364–#1366):
// Auflösung γ des Louvain-Verfahrens, Nachteilung nach Größe und Zusammenhalt und die Behandlung übergreifender
// Fundamente; dazu ihre Texte für Bericht, Zwischenspeicher und Einstellungen.

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Behandlung übergreifender Fundament-Units beim Gruppieren (#1365).</summary>
  TArchitectureFoundations = (Group, Attach, Separate);

  /// <summary>Einstellungen der Gruppierung in Teilsysteme (architecture.grouping).</summary>
  TArchitectureGrouping = record
  public const
    cMinResolution = 0.2;
    cMaxResolution = 5.0;
    cDefaultMaxShare = 0.25;
    cMaxMaxShare = 0.9;
    cDefaultMinCohesion = 0.3;
    /// <summary>Nachteilen nach Größe erst ab so vielen Units (#1364).</summary>
    cSplitMinUnits = 10;
    /// <summary>Nachteilen nach Zusammenhalt erst ab so vielen Units.</summary>
    cLooseMinUnits = 30;
    /// <summary>Höchstens so viele Stufen Nachteilung.</summary>
    cSplitDepth = 2;
    /// <summary>Übergreifendes Fundament (#1365): Abhängige in mindestens so vielen Teilsystemen …</summary>
    cFoundationMinSpread = 3;
    /// <summary>… oder höchstens dieser Anteil der Abhängigen (in Prozent, ganzzahlig verglichen) im eigenen
    /// Teilsystem.</summary>
    cFoundationMaxOwnPercent = 60;
  public
    /// <summary>Auflösung γ des Louvain-Verfahrens (#1366): größer = mehr und kleinere Teilsysteme.</summary>
    Resolution: Double;
    /// <summary>Ab diesem Anteil aller Units wird ein Teilsystem nachgeteilt (#1364); 0 = nie nach Größe.</summary>
    MaxShare: Double;
    /// <summary>Teilsysteme ab LooseMinUnits mit geringerem Zusammenhalt werden nachgeteilt; 0 = nie.</summary>
    MinCohesion: Double;
    /// <summary>Übergreifende Fundamente mitgruppieren, anhängen oder getrennt zeigen (#1365).</summary>
    Foundations: TArchitectureFoundations;
    /// <summary>Vorgaben: Auflösung 1 (Verhalten wie vor #1366), MaxShare 0,25, MinCohesion 0,3, Fundamente
    /// getrennt.</summary>
    class function Default: TArchitectureGrouping; static;
    /// <summary>Werte in ihren Grenzen (Resolution 0,2–5,0, MaxShare 0–0,9, MinCohesion 0–1).</summary>
    function Clamped: TArchitectureGrouping;
    /// <summary>Ein Teilsystem mit ASize von ATotal Units und Zusammenhalt ACohesion wird nachgeteilt (#1364).
    /// </summary>
    function NeedsSplit(ASize, ATotal: Integer; ACohesion: Double): Boolean;
    /// <summary>Text, der die Einstellungen eindeutig beschreibt (Schlüssel des Zwischenspeichers).</summary>
    function Key: string;
    /// <summary>Auflösung weicht von 1 ab (Kopf des Berichts, Hinweis im Vergleich).</summary>
    function ResolutionChanged: Boolean;
    /// <summary>"1,5" (deutsch, höchstens zwei Nachkommastellen).</summary>
    class function ResolutionText(AValue: Double): string; static;
    /// <summary>AValue liegt in 0,2–5,0 (Anfrage und get_architecture).</summary>
    class function ValidResolution(AValue: Double): Boolean; static;
    /// <summary>Zwei Auflösungen gelten als gleich (auf zwei Nachkommastellen).</summary>
    class function SameResolution(ALeft, ARight: Double): Boolean; static;
    /// <summary>"group", "attach" oder "separate" (architecture.grouping.foundations).</summary>
    class function FoundationsText(AValue: TArchitectureFoundations): string; static;
    class function TryFoundations(const AText: string; out AValue: TArchitectureFoundations): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TArchitectureGrouping }

class function TArchitectureGrouping.Default: TArchitectureGrouping;
begin
  Result.Resolution := 1;
  Result.MaxShare := cDefaultMaxShare;
  Result.MinCohesion := cDefaultMinCohesion;
  Result.Foundations := TArchitectureFoundations.Separate;
end;

function TArchitectureGrouping.Clamped: TArchitectureGrouping;
begin
  Result := Self;
  if IsNan(Result.Resolution) or (Result.Resolution <= 0) then
  begin
    Result.Resolution := 1;
  end;
  Result.Resolution := EnsureRange(Result.Resolution, cMinResolution, cMaxResolution);
  if IsNan(Result.MaxShare) then
  begin
    Result.MaxShare := cDefaultMaxShare;
  end;
  Result.MaxShare := EnsureRange(Result.MaxShare, 0, cMaxMaxShare);
  if IsNan(Result.MinCohesion) then
  begin
    Result.MinCohesion := cDefaultMinCohesion;
  end;
  Result.MinCohesion := EnsureRange(Result.MinCohesion, 0, 1);
end;

function TArchitectureGrouping.NeedsSplit(ASize, ATotal: Integer; ACohesion: Double): Boolean;
begin
  Result := ((MaxShare > 0) and (ASize >= cSplitMinUnits) and (ASize > MaxShare * ATotal)) or
    ((MinCohesion > 0) and (ASize >= cLooseMinUnits) and (ACohesion < MinCohesion));
end;

function TArchitectureGrouping.Key: string;
var
  mGrouping: TArchitectureGrouping;
begin
  mGrouping := Clamped;
  Result := 'r' + FormatFloat('0.####', mGrouping.Resolution, TFormatSettings.Invariant) + ';s' +
    FormatFloat('0.####', mGrouping.MaxShare, TFormatSettings.Invariant) + ';c' +
    FormatFloat('0.####', mGrouping.MinCohesion, TFormatSettings.Invariant) + ';f' + FoundationsText(Foundations);
end;

class function TArchitectureGrouping.FoundationsText(AValue: TArchitectureFoundations): string;
begin
  case AValue of
    TArchitectureFoundations.Attach:
      Result := 'attach';
    TArchitectureFoundations.Separate:
      Result := 'separate';
  else
    Result := 'group';
  end;
end;

class function TArchitectureGrouping.TryFoundations(const AText: string; out AValue: TArchitectureFoundations): Boolean;
begin
  Result := True;
  if AText = 'group' then
  begin
    AValue := TArchitectureFoundations.Group;
  end
  else if AText = 'attach' then
  begin
    AValue := TArchitectureFoundations.Attach;
  end
  else if AText = 'separate' then
  begin
    AValue := TArchitectureFoundations.Separate;
  end
  else
  begin
    AValue := TArchitectureFoundations.Group;
    Result := False;
  end;
end;

function TArchitectureGrouping.ResolutionChanged: Boolean;
begin
  Result := not SameResolution(Clamped.Resolution, 1);
end;

class function TArchitectureGrouping.ResolutionText(AValue: Double): string;
var
  mSettings: TFormatSettings;
begin
  mSettings := TFormatSettings.Invariant;
  mSettings.DecimalSeparator := ',';
  Result := FormatFloat('0.0#', AValue, mSettings);
end;

class function TArchitectureGrouping.ValidResolution(AValue: Double): Boolean;
begin
  Result := not IsNan(AValue) and (AValue >= cMinResolution - 1E-9) and (AValue <= cMaxResolution + 1E-9);
end;

class function TArchitectureGrouping.SameResolution(ALeft, ARight: Double): Boolean;
begin
  Result := Abs(ALeft - ARight) < 0.005;
end;

end.
