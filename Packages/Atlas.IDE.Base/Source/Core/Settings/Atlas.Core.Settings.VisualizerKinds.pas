unit Atlas.Core.Settings.VisualizerKinds;

// Arten und Grenzen der Visualisierer (#835) für debug.visualizers.*: Namen
// der Arten (types), Auswertungsstufe (evaluation), Namensfelder (nameFields)
// und die Grenzen von maxLength, timeoutMs und maxImagePixels. Liegt bei den
// Einstellungen, damit der Parser ohne den Debug-Kern auskommt (A-09: sonst
// Feature-Zyklus Settings -> Debug -> Files/Hover/Lsp -> Settings); die
// Ersatztexte und Ansichten rechnet Atlas.Core.Debug.Visualizers.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  TAtlasVisualizerKind = (Lists, Dictionaries, DataSets, Bytes, Json, Colors, Guid, Geometry, Graphics);
  /// <summary>Wie weit Atlas für einen Wert auswerten darf (debug.visualizers.evaluation): nur Felder, auch Getter
  /// von Eigenschaften, auch Funktionsaufrufe.</summary>
  TAtlasVisualizerEvaluation = (Fields, Properties, Calls);
  {$SCOPEDENUMS OFF}

  TAtlasVisualizerKinds = set of TAtlasVisualizerKind;

  TAtlasVisualizerSettings = class
  public const
    cDefaultMaxLength = 120;
    cMinMaxLength = 20;
    cMaxMaxLength = 2000;
    cDefaultTimeoutMs = 200;
    cMinTimeoutMs = 20;
    cMaxTimeoutMs = 5000;
    cDefaultMaxImagePixels = 4000000;
    cMinMaxImagePixels = 10000;
    cMaxMaxImagePixels = 64000000;
    cAllKinds = [Low(TAtlasVisualizerKind)..High(TAtlasVisualizerKind)];
    cKindNames: array[TAtlasVisualizerKind] of string = ('lists', 'dictionaries', 'dataSets', 'bytes', 'json',
      'colors', 'guid', 'geometry', 'graphics');
    cEvaluationNames: array[TAtlasVisualizerEvaluation] of string = ('fields', 'properties', 'calls');
    cDefaultNameFields = 'Name,Caption,Text';
  public
    /// <summary>Kommagetrennte Arten wie in debug.visualizers.types; unbekannte fallen weg, '' = keine.</summary>
    class function ParseKinds(const AText: string): TAtlasVisualizerKinds; static;
    class function KindsText(AKinds: TAtlasVisualizerKinds): string; static;
    /// <summary>Normalisiert die Liste: bekannte Namen in fester Reihenfolge, Groß-/Kleinschreibung wie oben.</summary>
    class function NormalizeKinds(const AText: string): string; static;
    class function ParseEvaluation(const AText: string): TAtlasVisualizerEvaluation; static;
    /// <summary>Kommagetrennte Feldnamen (debug.visualizers.nameFields), getrimmt, ohne leere und doppelte.</summary>
    class function ParseNameFields(const AText: string): TArray<string>; static;
    class function NormalizeNameFields(const AText: string): string; static;
  end;

implementation

{ TAtlasVisualizerSettings }

class function TAtlasVisualizerSettings.ParseKinds(const AText: string): TAtlasVisualizerKinds;
var
  mPart: string;
  mKind: TAtlasVisualizerKind;
begin
  Result := [];
  for mPart in AText.Split([',', ';']) do
  begin
    for mKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
    begin
      if SameText(Trim(mPart), cKindNames[mKind]) then
      begin
        Include(Result, mKind);
      end;
    end;
  end;
end;

class function TAtlasVisualizerSettings.KindsText(AKinds: TAtlasVisualizerKinds): string;
var
  mKind: TAtlasVisualizerKind;
begin
  Result := '';
  for mKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
  begin
    if mKind in AKinds then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + cKindNames[mKind];
    end;
  end;
end;

class function TAtlasVisualizerSettings.NormalizeKinds(const AText: string): string;
begin
  Result := KindsText(ParseKinds(AText));
end;

class function TAtlasVisualizerSettings.ParseEvaluation(const AText: string): TAtlasVisualizerEvaluation;
var
  mItem: TAtlasVisualizerEvaluation;
begin
  for mItem := Low(TAtlasVisualizerEvaluation) to High(TAtlasVisualizerEvaluation) do
  begin
    if SameText(Trim(AText), cEvaluationNames[mItem]) then
    begin
      Exit(mItem);
    end;
  end;
  Result := TAtlasVisualizerEvaluation.Properties;
end;

class function TAtlasVisualizerSettings.ParseNameFields(const AText: string): TArray<string>;
var
  mPart, mName, mKnown: string;
  mSeen: Boolean;
begin
  Result := nil;
  for mPart in AText.Split([',', ';']) do
  begin
    mName := Trim(mPart);
    if (mName = '') or not IsValidIdent(mName) then
    begin
      Continue;
    end;
    mSeen := False;
    for mKnown in Result do
    begin
      if SameText(mKnown, mName) then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mName];
    end;
  end;
end;

class function TAtlasVisualizerSettings.NormalizeNameFields(const AText: string): string;
begin
  Result := string.Join(',', ParseNameFields(AText));
end;

end.
