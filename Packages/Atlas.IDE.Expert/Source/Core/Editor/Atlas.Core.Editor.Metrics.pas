unit Atlas.Core.Editor.Metrics;

// Code-Metriken im Plugin (#66), ohne VCL und OTA; Anfrage, Zeichnen und
// Dateizugriff macht die IDE-Schicht.
// - Code Lens: Antwort des Servers auf atlas.server.metrics lesen
//   ({"enabled", "limits", "file", "methods"}), Beschriftung bauen und
//   prüfen, ob die Zeile noch zur Methode passt.
// - Metrikbericht: Markdown aus der Antwort im Modus "markdown" (ein
//   JSON-String) und Name der Berichtsdatei je Projekt.

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  /// <summary>Kennzahlen in der Reihenfolge des Servers (length, nesting, cyclomatic, cognitive, parameters).</summary>
  TAtlasMetric = (MethodLength, Nesting, Cyclomatic, Cognitive, Parameters);
{$SCOPEDENUMS OFF}

  TAtlasMetricValues = array[TAtlasMetric] of Integer;

  /// <summary>Formate der Beschriftung je Kennzahl mit %d, z. B. „%d Zeilen“, „Tiefe %d“.</summary>
  TAtlasMetricFormats = array[TAtlasMetric] of string;

  TAtlasMethodMetrics = record
    Name: string;
    /// <summary>Zeile des Namens im Kopf, 0-basiert.</summary>
    Line: Integer;
    Values: TAtlasMetricValues;
  end;

  TAtlasFileMetrics = record
    /// <summary>Einstellung codeLens.metrics laut Server.</summary>
    Enabled: Boolean;
    Limits: TAtlasMetricValues;
    Methods: TArray<TAtlasMethodMetrics>;
    /// <summary>Aus der Antwort des Servers; Zeilen dort ab 1. Ohne gültige Antwort: aus, keine Methoden.</summary>
    class function FromJson(const AValue: TJSONValue): TAtlasFileMetrics; static;
    /// <summary>Index der Methode, deren Kopf in ALine (0-basiert) steht; -1 ohne.</summary>
    function IndexAt(ALine: Integer): Integer;
  end;

  TAtlasMetricsLens = class
  public
    /// <summary>Kennung beim Server: length, nesting, cyclomatic, cognitive, parameters.</summary>
    class function Key(AMetric: TAtlasMetric): string; static;
    /// <summary>Beschriftung, Teile mit „ · “ getrennt; ein Wert über dem Grenzwert bekommt ALimitFormat
    /// (mit %s für den Teil und %d für den Grenzwert), z. B. „zyklomatisch 17 (> 15)“.</summary>
    class function Caption(const AMethod: TAtlasMethodMetrics; const ALimits: TAtlasMetricValues;
      const AFormats: TAtlasMetricFormats; const ALimitFormat: string): string; static;
    /// <summary>Mindestens eine Kennzahl über ihrem Grenzwert.</summary>
    class function Exceeds(const AMethod: TAtlasMethodMetrics; const ALimits: TAtlasMetricValues): Boolean; static;
    /// <summary>True, wenn ALine den letzten Teil von AName als Bezeichner enthält (die Lens steht noch an
    /// ihrer Methode, auch wenn der Text seit dem Abruf verschoben ist).</summary>
    class function LineMatches(const ALine, AName: string): Boolean; static;
  end;

  TAtlasMetricsReportFile = class
  public
    /// <summary>Ordner der Berichte unter ABase (%LOCALAPPDATA%\Atlas): ABase\Berichte.</summary>
    class function Folder(const ABase: string): string; static;
    /// <summary>Metriken-Projektname.md im Ordner (z. B. Metriken-Kasse.md); ohne Projekt Metriken.md.</summary>
    class function FileName(const AFolder, AProject: string): string; static;
    /// <summary>Text der Antwort im Modus "markdown" (JSON-String); False bei leerer oder anderer Antwort.</summary>
    class function MarkdownFrom(const AJson: string; out AText: string): Boolean; static;
  end;

implementation

{ TAtlasFileMetrics }

class function TAtlasFileMetrics.FromJson(const AValue: TJSONValue): TAtlasFileMetrics;
var
  Answer, Limits, Values: TJSONObject;
  Methods: TJSONArray;
  Item: TJSONValue;
  Method: TAtlasMethodMetrics;
  Metric: TAtlasMetric;
  Number: Integer;
begin
  Result := Default(TAtlasFileMetrics);
  Result.Methods := nil;
  if not (AValue is TJSONObject) then
    Exit;
  Answer := TJSONObject(AValue);
  if not Answer.TryGetValue<Boolean>('enabled', Result.Enabled) then
    Result.Enabled := True;
  if Answer.GetValue('limits') is TJSONObject then
  begin
    Limits := TJSONObject(Answer.GetValue('limits'));
    for Metric := Low(TAtlasMetric) to High(TAtlasMetric) do
      if Limits.TryGetValue<Integer>(TAtlasMetricsLens.Key(Metric), Number) then
        Result.Limits[Metric] := Number
      else
        Result.Limits[Metric] := MaxInt;
  end
  else
    for Metric := Low(TAtlasMetric) to High(TAtlasMetric) do
      Result.Limits[Metric] := MaxInt;
  if not (Answer.GetValue('methods') is TJSONArray) then
    Exit;
  Methods := TJSONArray(Answer.GetValue('methods'));
  for Item in Methods do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Method := Default(TAtlasMethodMetrics);
    if not (TJSONObject(Item).TryGetValue<string>('name', Method.Name) and
      TJSONObject(Item).TryGetValue<Integer>('line', Number)) then
      Continue;
    Method.Line := Number - 1;
    if TJSONObject(Item).GetValue('values') is TJSONObject then
    begin
      Values := TJSONObject(TJSONObject(Item).GetValue('values'));
      for Metric := Low(TAtlasMetric) to High(TAtlasMetric) do
        if Values.TryGetValue<Integer>(TAtlasMetricsLens.Key(Metric), Number) then
          Method.Values[Metric] := Number;
    end;
    Result.Methods := Result.Methods + [Method];
  end;
end;

function TAtlasFileMetrics.IndexAt(ALine: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Methods) do
    if Methods[Index].Line = ALine then
      Exit(Index);
  Result := -1;
end;

{ TAtlasMetricsLens }

class function TAtlasMetricsLens.Key(AMetric: TAtlasMetric): string;
begin
  case AMetric of
    TAtlasMetric.MethodLength:
      Result := 'length';
    TAtlasMetric.Nesting:
      Result := 'nesting';
    TAtlasMetric.Cyclomatic:
      Result := 'cyclomatic';
    TAtlasMetric.Cognitive:
      Result := 'cognitive';
  else
    Result := 'parameters';
  end;
end;

class function TAtlasMetricsLens.Caption(const AMethod: TAtlasMethodMetrics; const ALimits: TAtlasMetricValues;
  const AFormats: TAtlasMetricFormats; const ALimitFormat: string): string;
var
  Metric: TAtlasMetric;
  Part: string;
begin
  Result := '';
  for Metric := Low(TAtlasMetric) to High(TAtlasMetric) do
  begin
    Part := Format(AFormats[Metric], [AMethod.Values[Metric]]);
    if AMethod.Values[Metric] > ALimits[Metric] then
      Part := Format(ALimitFormat, [Part, ALimits[Metric]]);
    if Result <> '' then
      Result := Result + ' · ';
    Result := Result + Part;
  end;
end;

class function TAtlasMetricsLens.Exceeds(const AMethod: TAtlasMethodMetrics; const ALimits: TAtlasMetricValues): Boolean;
var
  Metric: TAtlasMetric;
begin
  for Metric := Low(TAtlasMetric) to High(TAtlasMetric) do
    if AMethod.Values[Metric] > ALimits[Metric] then
      Exit(True);
  Result := False;
end;

function IsIdentChar(ACh: Char): Boolean;
begin
  Result := CharInSet(ACh, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(ACh) > 127);
end;

class function TAtlasMetricsLens.LineMatches(const ALine, AName: string): Boolean;
var
  Name, Line: string;
  Dot, Start: Integer;
begin
  Name := AName;
  Dot := LastDelimiter('.', Name);
  if Dot > 0 then
    Name := Copy(Name, Dot + 1, MaxInt);
  Result := False;
  if Name = '' then
    Exit;
  Line := UpperCase(ALine);
  Name := UpperCase(Name);
  Start := Pos(Name, Line);
  while Start > 0 do
  begin
    if ((Start = 1) or not IsIdentChar(Line[Start - 1])) and
      ((Start + Length(Name) > Length(Line)) or not IsIdentChar(Line[Start + Length(Name)])) then
      Exit(True);
    Start := Pos(Name, Line, Start + 1);
  end;
end;

{ TAtlasMetricsReportFile }

class function TAtlasMetricsReportFile.Folder(const ABase: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ABase) + 'Berichte';
end;

class function TAtlasMetricsReportFile.FileName(const AFolder, AProject: string): string;
var
  Name: string;
begin
  Name := ChangeFileExt(ExtractFileName(AProject), '');
  if Name = '' then
    Name := 'Metriken'
  else
    Name := 'Metriken-' + Name;
  Result := IncludeTrailingPathDelimiter(AFolder) + Name + '.md';
end;

class function TAtlasMetricsReportFile.MarkdownFrom(const AJson: string; out AText: string): Boolean;
var
  Value: TJSONValue;
begin
  AText := '';
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if Value is TJSONString then
      AText := TJSONString(Value).Value;
  finally
    Value.Free;
  end;
  Result := Trim(AText) <> '';
end;

end.
