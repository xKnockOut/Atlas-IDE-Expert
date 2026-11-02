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
    DefaultMaxLength = 120;
    MinMaxLength = 20;
    MaxMaxLength = 2000;
    DefaultTimeoutMs = 200;
    MinTimeoutMs = 20;
    MaxTimeoutMs = 5000;
    DefaultMaxImagePixels = 4000000;
    MinMaxImagePixels = 10000;
    MaxMaxImagePixels = 64000000;
    AllKinds = [Low(TAtlasVisualizerKind)..High(TAtlasVisualizerKind)];
    KindNames: array[TAtlasVisualizerKind] of string = ('lists', 'dictionaries', 'dataSets', 'bytes', 'json',
      'colors', 'guid', 'geometry', 'graphics');
    EvaluationNames: array[TAtlasVisualizerEvaluation] of string = ('fields', 'properties', 'calls');
    DefaultNameFields = 'Name,Caption,Text';
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
  Part: string;
  Kind: TAtlasVisualizerKind;
begin
  Result := [];
  for Part in AText.Split([',', ';']) do
    for Kind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
      if SameText(Trim(Part), KindNames[Kind]) then
        Include(Result, Kind);
end;

class function TAtlasVisualizerSettings.KindsText(AKinds: TAtlasVisualizerKinds): string;
var
  Kind: TAtlasVisualizerKind;
begin
  Result := '';
  for Kind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
    if Kind in AKinds then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + KindNames[Kind];
    end;
end;

class function TAtlasVisualizerSettings.NormalizeKinds(const AText: string): string;
begin
  Result := KindsText(ParseKinds(AText));
end;

class function TAtlasVisualizerSettings.ParseEvaluation(const AText: string): TAtlasVisualizerEvaluation;
var
  Item: TAtlasVisualizerEvaluation;
begin
  for Item := Low(TAtlasVisualizerEvaluation) to High(TAtlasVisualizerEvaluation) do
    if SameText(Trim(AText), EvaluationNames[Item]) then
      Exit(Item);
  Result := TAtlasVisualizerEvaluation.Properties;
end;

class function TAtlasVisualizerSettings.ParseNameFields(const AText: string): TArray<string>;
var
  Part, Name, Known: string;
  Seen: Boolean;
begin
  Result := nil;
  for Part in AText.Split([',', ';']) do
  begin
    Name := Trim(Part);
    if (Name = '') or not IsValidIdent(Name) then
      Continue;
    Seen := False;
    for Known in Result do
      if SameText(Known, Name) then
        Seen := True;
    if not Seen then
      Result := Result + [Name];
  end;
end;

class function TAtlasVisualizerSettings.NormalizeNameFields(const AText: string): string;
begin
  Result := string.Join(',', ParseNameFields(AText));
end;

end.
