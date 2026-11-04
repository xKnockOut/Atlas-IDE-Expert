unit Atlas.Core.Editor.Metrics;

// Code-Metriken im Plugin (#66), ohne VCL und OTA; Anfrage, Zeichnen und
// Dateizugriff macht die IDE-Schicht.
// - Code Lens: Antwort des Servers auf atlas.server.metrics lesen
//   ({"enabled", "limits", "file", "methods", "structure"}), Beschriftung
//   bauen und prüfen, ob die Zeile noch zur Methode passt. "structure" trägt
//   die Kennzahlen des Aufbaus (#939): Member je Klasse auf dem Klassennamen,
//   Zeilen der Unit auf dem Unit-Namen, Units im uses auf dem ersten uses,
//   Vererbungstiefe ohne RTL und VCL auf dem Klassennamen (#980). Stehen
//   mehrere in einer Zeile (Member und Vererbungstiefe), zeigt die Linse
//   beide.
// - Metrikbericht: Markdown aus der Antwort im Modus "markdown" (ein
//   JSON-String) und Name der Berichtsdatei je Projekt.

interface

uses
  System.SysUtils,
  System.JSON;

type
{$SCOPEDENUMS ON}
  /// <summary>Kennzahlen in der Reihenfolge des Servers (length, nesting, cyclomatic, cognitive, parameters,
  /// operands, locals, exits; die letzten drei #980).</summary>
  TAtlasMetric = (MethodLength, Nesting, Cyclomatic, Cognitive, Parameters, Operands, Locals, Exits);
{$SCOPEDENUMS OFF}

  TAtlasMetricValues = array[TAtlasMetric] of Integer;

{$SCOPEDENUMS ON}
  /// <summary>Kennzahlen des Aufbaus (#939); Kennung beim Server classSize, unitLength, usesCount,
  /// inheritanceDepth (#980).</summary>
  TAtlasStructureMetric = (ClassSize, UnitLength, UsesCount, InheritanceDepth);
{$SCOPEDENUMS OFF}

  /// <summary>Formate der Beschriftung je Kennzahl des Aufbaus mit %d, z. B. „%d Member“.</summary>
  TAtlasStructureFormats = array[TAtlasStructureMetric] of string;

  /// <summary>Eine Kennzahl des Aufbaus mit ihrem Grenzwert (#939).</summary>
  TAtlasStructureItem = record
    Kind: TAtlasStructureMetric;
    /// <summary>Klassen- bzw. Unit-Name.</summary>
    Name: string;
    /// <summary>Zeile, 0-basiert.</summary>
    Line: Integer;
    Value: Integer;
    Limit: Integer;
    /// <summary>Value ist nur eine Untergrenze ("atLeast", Vererbungstiefe bei abgebrochener Kette, #980).</summary>
    AtLeast: Boolean;
  end;

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
    /// <summary>Kennzahlen des Aufbaus (#939); nil bei älteren Servern.</summary>
    Structures: TArray<TAtlasStructureItem>;
    /// <summary>Aus der Antwort des Servers; Zeilen dort ab 1. Ohne gültige Antwort: aus, keine Methoden.</summary>
    class function FromJson(const AValue: TJSONValue): TAtlasFileMetrics; static;
    /// <summary>Index der Methode, deren Kopf in ALine (0-basiert) steht; -1 ohne.</summary>
    function IndexAt(ALine: Integer): Integer;
    /// <summary>Index der Kennzahl des Aufbaus in ALine (0-basiert); -1 ohne.</summary>
    function StructureAt(ALine: Integer): Integer;
    /// <summary>Alle Kennzahlen des Aufbaus in ALine (0-basiert), z. B. Member und Vererbungstiefe (#980).</summary>
    function StructuresAt(ALine: Integer): TArray<TAtlasStructureItem>;
  end;

  TAtlasMetricsLens = class
  public
    /// <summary>Kennung beim Server: length, nesting, cyclomatic, cognitive, parameters, operands, locals, exits.
    /// </summary>
    class function Key(AMetric: TAtlasMetric): string; static;
    /// <summary>Beschriftung, Teile mit „ · “ getrennt; ein Wert über dem Grenzwert bekommt ALimitFormat
    /// (mit %s für den Teil und %d für den Grenzwert), z. B. „zyklomatisch 17 (> 15)“.</summary>
    class function Caption(const AMethod: TAtlasMethodMetrics; const ALimits: TAtlasMetricValues;
      const AFormats: TAtlasMetricFormats; const ALimitFormat: string): string; static;
    /// <summary>Mindestens eine Kennzahl über ihrem Grenzwert.</summary>
    class function Exceeds(const AMethod: TAtlasMethodMetrics; const ALimits: TAtlasMetricValues): Boolean; static;
    /// <summary>Kennung beim Server: classSize, unitLength, usesCount (#939), inheritanceDepth (#980).</summary>
    class function StructureKey(AMetric: TAtlasStructureMetric): string; static;
    /// <summary>Beschriftung einer Kennzahl des Aufbaus, über dem Grenzwert mit ALimitFormat, z. B.
    /// „87 Member (> 40)“ (#939).</summary>
    class function StructureCaption(const AItem: TAtlasStructureItem; const AFormats: TAtlasStructureFormats;
      const ALimitFormat: string): string; overload; static;
    /// <summary>Beschriftungen aller AItems mit „ · “ getrennt; Untergrenzen (AtLeast) mit AAtLeastFormat, z. B.
    /// „Vererbungstiefe mindestens %d“ (#980).</summary>
    class function StructureCaption(const AItems: TArray<TAtlasStructureItem>; const AFormats: TAtlasStructureFormats;
      const AAtLeastFormat, ALimitFormat: string): string; overload; static;
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

uses
  System.Generics.Collections,
  Atlas.Text.Chars;

{ TAtlasFileMetrics }

/// <summary>Grenzwerte je Metrik; fehlende gelten als unbegrenzt (MaxInt).</summary>
function ReadLimits(const AValue: TJSONValue): TAtlasMetricValues;
var
  mMetric: TAtlasMetric;
  mNumber: Integer;
begin
  for mMetric := Low(TAtlasMetric) to High(TAtlasMetric) do
  begin
    Result[mMetric] := MaxInt;
    if (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<Integer>(TAtlasMetricsLens.Key(mMetric),
      mNumber) then
    begin
      Result[mMetric] := mNumber;
    end;
  end;
end;

function StructureKindOf(const AText: string; out AKind: TAtlasStructureMetric): Boolean;
var
  mKind: TAtlasStructureMetric;
begin
  Result := False;
  AKind := Low(TAtlasStructureMetric);
  for mKind := Low(TAtlasStructureMetric) to High(TAtlasStructureMetric) do
  begin
    if SameText(AText, TAtlasMetricsLens.StructureKey(mKind)) then
    begin
      AKind := mKind;
      Result := True;
    end;
  end;
end;

/// <summary>Ein Strukturwert {kind, line, value, name, atLeast, limit}; False ohne Art, Zeile oder Wert.</summary>
function ReadStructure(const AItem: TJSONObject; out AStructure: TAtlasStructureItem): Boolean;
var
  mKindText: string;
  mNumber: Integer;
begin
  AStructure := Default(TAtlasStructureItem);
  Result := AItem.TryGetValue<string>('kind', mKindText) and AItem.TryGetValue<Integer>('line', mNumber) and
    AItem.TryGetValue<Integer>('value', AStructure.Value) and StructureKindOf(mKindText, AStructure.Kind);
  if Result then
  begin
    AStructure.Line := mNumber - 1;
    AItem.TryGetValue<string>('name', AStructure.Name);
    if not AItem.TryGetValue<Boolean>('atLeast', AStructure.AtLeast) then
    begin
      AStructure.AtLeast := False;
    end;
    if not AItem.TryGetValue<Integer>('limit', AStructure.Limit) then
    begin
      AStructure.Limit := MaxInt;
    end;
  end;
end;

function ReadStructures(const AValue: TJSONValue): TArray<TAtlasStructureItem>;
var
  mItem: TJSONValue;
  mStructure: TAtlasStructureItem;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      if (mItem is TJSONObject) and ReadStructure(TJSONObject(mItem), mStructure) then
      begin
        Result := Result + [mStructure];
      end;
    end;
  end;
end;

/// <summary>Eine Methode {name, line, values}; False ohne Name oder Zeile.</summary>
function ReadMethod(const AItem: TJSONObject; out AMethod: TAtlasMethodMetrics): Boolean;
var
  mValues: TJSONObject;
  mMetric: TAtlasMetric;
  mNumber: Integer;
begin
  AMethod := Default(TAtlasMethodMetrics);
  Result := AItem.TryGetValue<string>('name', AMethod.Name) and AItem.TryGetValue<Integer>('line', mNumber);
  if Result then
  begin
    AMethod.Line := mNumber - 1;
    if AItem.GetValue('values') is TJSONObject then
    begin
      mValues := TJSONObject(AItem.GetValue('values'));
      for mMetric := Low(TAtlasMetric) to High(TAtlasMetric) do
      begin
        if mValues.TryGetValue<Integer>(TAtlasMetricsLens.Key(mMetric), mNumber) then
        begin
          AMethod.Values[mMetric] := mNumber;
        end;
      end;
    end;
  end;
end;

function ReadMethods(const AValue: TJSONValue): TArray<TAtlasMethodMetrics>;
var
  mItem: TJSONValue;
  mMethod: TAtlasMethodMetrics;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      if (mItem is TJSONObject) and ReadMethod(TJSONObject(mItem), mMethod) then
      begin
        Result := Result + [mMethod];
      end;
    end;
  end;
end;

class function TAtlasFileMetrics.FromJson(const AValue: TJSONValue): TAtlasFileMetrics;
var
  mAnswer: TJSONObject;
begin
  Result := Default(TAtlasFileMetrics);
  Result.Methods := nil;
  Result.Structures := nil;
  if AValue is TJSONObject then
  begin
    mAnswer := TJSONObject(AValue);
    if not mAnswer.TryGetValue<Boolean>('enabled', Result.Enabled) then
    begin
      Result.Enabled := True;
    end;
    Result.Limits := ReadLimits(mAnswer.GetValue('limits'));
    Result.Structures := ReadStructures(mAnswer.GetValue('structure'));
    Result.Methods := ReadMethods(mAnswer.GetValue('methods'));
  end;
end;

function TAtlasFileMetrics.IndexAt(ALine: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Methods) do
  begin
    if Methods[Index].Line = ALine then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function TAtlasFileMetrics.StructureAt(ALine: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Structures) do
  begin
    if Structures[Index].Line = ALine then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

function TAtlasFileMetrics.StructuresAt(ALine: Integer): TArray<TAtlasStructureItem>;
var
  Item: TAtlasStructureItem;
begin
  Result := nil;
  for Item in Structures do
  begin
    if Item.Line = ALine then
    begin
      Result := Result + [Item];
    end;
  end;
end;

{ TAtlasMetricsLens }

class function TAtlasMetricsLens.StructureKey(AMetric: TAtlasStructureMetric): string;
begin
  case AMetric of
    TAtlasStructureMetric.ClassSize:
      Result := 'classSize';
    TAtlasStructureMetric.UnitLength:
      Result := 'unitLength';
    TAtlasStructureMetric.UsesCount:
      Result := 'usesCount';
  else
    Result := 'inheritanceDepth';
  end;
end;

class function TAtlasMetricsLens.StructureCaption(const AItem: TAtlasStructureItem;
  const AFormats: TAtlasStructureFormats; const ALimitFormat: string): string;
begin
  Result := Format(AFormats[AItem.Kind], [AItem.Value]);
  if AItem.Value > AItem.Limit then
  begin
    Result := Format(ALimitFormat, [Result, AItem.Limit]);
  end;
end;

class function TAtlasMetricsLens.StructureCaption(const AItems: TArray<TAtlasStructureItem>;
  const AFormats: TAtlasStructureFormats; const AAtLeastFormat, ALimitFormat: string): string;
var
  Item: TAtlasStructureItem;
  Formats: TAtlasStructureFormats;
begin
  Result := '';
  for Item in AItems do
  begin
    Formats := AFormats;
    if Item.AtLeast then
    begin
      Formats[Item.Kind] := AAtLeastFormat;
    end;
    if Result <> '' then
    begin
      Result := Result + ' · ';
    end;
    Result := Result + StructureCaption(Item, Formats, ALimitFormat);
  end;
end;

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
    TAtlasMetric.Parameters:
      Result := 'parameters';
    TAtlasMetric.Operands:
      Result := 'operands';
    TAtlasMetric.Locals:
      Result := 'locals';
  else
    Result := 'exits';
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
    begin
      Part := Format(ALimitFormat, [Part, ALimits[Metric]]);
    end;
    if Result <> '' then
    begin
      Result := Result + ' · ';
    end;
    Result := Result + Part;
  end;
end;

class function TAtlasMetricsLens.Exceeds(const AMethod: TAtlasMethodMetrics; const ALimits: TAtlasMetricValues): Boolean;
var
  Metric: TAtlasMetric;
begin
  for Metric := Low(TAtlasMetric) to High(TAtlasMetric) do
  begin
    if AMethod.Values[Metric] > ALimits[Metric] then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasMetricsLens.LineMatches(const ALine, AName: string): Boolean;
var
  Name, Line: string;
  Dot, Start: Integer;
begin
  Name := AName;
  Dot := LastDelimiter('.', Name);
  if Dot > 0 then
  begin
    Name := Copy(Name, Dot + 1, MaxInt);
  end;
  Result := False;
  if Name = '' then
  begin
    Exit;
  end;
  Line := UpperCase(ALine);
  Name := UpperCase(Name);
  Start := Pos(Name, Line);
  while Start > 0 do
  begin
    if ((Start = 1) or not TTextChars.IsIdentChar(Line[Start - 1])) and
      ((Start + Length(Name) > Length(Line)) or not TTextChars.IsIdentChar(Line[Start + Length(Name)])) then
    begin
      Exit(True);
    end;
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
  begin
    Name := 'Metriken';
  end
  else
  begin
    Name := 'Metriken-' + Name;
  end;
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
    begin
      AText := TJSONString(Value).Value;
    end;
  finally
    Value.Free;
  end;
  Result := Trim(AText) <> '';
end;

end.
