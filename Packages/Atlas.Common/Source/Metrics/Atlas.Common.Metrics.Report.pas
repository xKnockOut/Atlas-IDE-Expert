unit Atlas.Common.Metrics.Report;

// Bericht der Code-Metriken (#66) als Markdown und Metrikdaten als JSON.
// Den HTML-Bericht baut #156 aus diesen Daten; hier entsteht kein HTML.
//
// JSON (Format 1, Zeilen und Spalten ab 1):
//   {"format": 1,
//    "limits": {"length": 60, "nesting": 4, "cyclomatic": 15, "cognitive": 15, "parameters": 6},
//    "summary": {"files": 2, "methods": 10, "overLimits": 1,
//                "average": {"length": 12.5, …}, "maximum": {"length": 75, …},
//                "exceeded": {"length": 1, …}},
//    "files": [{"file": "Source/Main.pas", "methods": [
//      {"name": "TFoo.Bar", "line": 8, "character": 11, "endLine": 44,
//       "values": {"length": 30, …}, "exceeded": ["cyclomatic"]}]}]}
// "average" hat eine Nachkommastelle; "exceeded" zählt je Kennzahl die
// Methoden darüber, "overLimits" die Methoden mit mindestens einer
// Überschreitung. Die Projekt-Zusammenfassung der Willkommensseite (#592)
// übernimmt "summary" als Abschnitt "metrics" (#758).
// Der Text entsteht ohne System.JSON, damit die Unit überall gleich arbeitet.
// Kennzahlen des Aufbaus einer Datei (#939) als StructureJson:
//   [{"kind": "classSize", "name": "TFoo", "line": 5, "character": 3, "value": 87, "limit": 40}, …]
// kind ist classSize, unitLength oder usesCount.

interface

uses
  Atlas.Common.Metrics.Contract;

type
  /// <summary>Kennzahlen über alle Methoden eines Berichts.</summary>
  TMetricsSummary = record
    Files: Integer;
    Methods: Integer;
    /// <summary>Summe je Kennzahl (für den Mittelwert).</summary>
    Totals: array[TMetricKind] of Int64;
    Maximum: TMetricValues;
    /// <summary>Methoden über dem Grenzwert je Kennzahl.</summary>
    Exceeded: TMetricValues;
    /// <summary>Methoden mit mindestens einer Überschreitung.</summary>
    OverLimits: Integer;
    /// <summary>Mittelwert in Zehnteln, kaufmännisch gerundet (125 = 12,5); 0 ohne Methoden.</summary>
    function AverageTenths(AKind: TMetricKind): Integer;
  end;

  TMetricsReport = class
  public const
    Format = 1;
    /// <summary>Höchstzahl der Zeilen in der Tabelle „Über einem Grenzwert“.</summary>
    MaxRows = 100;
    /// <summary>Zeilen der Tabelle „Komplexeste Methoden“.</summary>
    TopRows = 10;
  public
    class function Summarize(const AFiles: TArray<TFileMetrics>; const ALimits: TMetricLimits): TMetricsSummary;
      static;
    /// <summary>Zehntel als Text mit Punkt: 125 → "12.5", 30 → "3.0".</summary>
    class function TenthsText(ATenths: Int64): string; static;
    /// <summary>AText als JSON-String samt Anführungszeichen.</summary>
    class function JsonString(const AText: string): string; static;
    class function LimitsJson(const ALimits: TMetricLimits): string; static;
    class function SummaryJson(const ASummary: TMetricsSummary): string; static;
    class function RoutineJson(const ARoutine: TRoutineMetrics; const ALimits: TMetricLimits): string; static;
    /// <summary>{"file": …, "methods": […]} einer Datei.</summary>
    class function FileJson(const AFile: TFileMetrics; const ALimits: TMetricLimits): string; static;
    /// <summary>Vollständige Metrikdaten (siehe Kopf der Unit).</summary>
    class function Json(const AFiles: TArray<TFileMetrics>; const ALimits: TMetricLimits): string; static;
    /// <summary>Gesamtbericht als Markdown; ATitle z. B. der Projektname.</summary>
    class function Markdown(const AFiles: TArray<TFileMetrics>; const ALimits: TMetricLimits;
      const ATitle: string): string; static;
    /// <summary>Titel der Code Lens: "12 Zeilen · Tiefe 2 · zyklomatisch 4 · kognitiv 3 · 2 Parameter";
    /// Überschreitungen mit Grenzwert, z. B. "zyklomatisch 17 (> 15)".</summary>
    class function LensTitle(const AValues: TMetricValues; const ALimits: TMetricLimits): string; static;
    /// <summary>Kennung des Aufbaus in JSON: classSize, unitLength, usesCount (#939).</summary>
    class function StructureKey(AKind: TStructureKind): string; static;
    /// <summary>Kennzahlen des Aufbaus als JSON-Array (siehe Kopf der Unit, #939).</summary>
    class function StructureJson(const AItems: TArray<TStructureMetrics>; const ALimits: TMetricLimits): string;
      static;
    /// <summary>Teil der Code Lens zum Aufbau (#939): "87 Member", "2140 Zeilen" bzw. "34 Units im uses";
    /// Überschreitungen mit Grenzwert, z. B. "87 Member (> 40)".</summary>
    class function StructureLensPart(AKind: TStructureKind; AValue: Integer; const ALimits: TMetricLimits): string;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

type
  TReportRow = record
    Path: string;
    Routine: TRoutineMetrics;
    Exceeded: Integer;
  end;

const
  LineBreak = #13#10;

{ TMetricsSummary }

function TMetricsSummary.AverageTenths(AKind: TMetricKind): Integer;
begin
  if Methods <= 0 then
    Exit(0);
  Result := Integer((Totals[AKind] * 10 + Methods div 2) div Methods);
end;

{ TMetricsReport }

class function TMetricsReport.Summarize(const AFiles: TArray<TFileMetrics>;
  const ALimits: TMetricLimits): TMetricsSummary;
var
  FileItem: TFileMetrics;
  Routine: TRoutineMetrics;
  Kind: TMetricKind;
  Over: Boolean;
begin
  Result := Default(TMetricsSummary);
  Result.Files := Length(AFiles);
  for FileItem in AFiles do
    for Routine in FileItem.Routines do
    begin
      Inc(Result.Methods);
      Over := False;
      for Kind := Low(TMetricKind) to High(TMetricKind) do
      begin
        Inc(Result.Totals[Kind], Routine.Values[Kind]);
        if Routine.Values[Kind] > Result.Maximum[Kind] then
          Result.Maximum[Kind] := Routine.Values[Kind];
        if ALimits.Exceeds(Kind, Routine.Values[Kind]) then
        begin
          Inc(Result.Exceeded[Kind]);
          Over := True;
        end;
      end;
      if Over then
        Inc(Result.OverLimits);
    end;
end;

class function TMetricsReport.TenthsText(ATenths: Int64): string;
var
  Value: Int64;
begin
  Value := Abs(ATenths);
  Result := IntToStr(Value div 10) + '.' + IntToStr(Value mod 10);
  if ATenths < 0 then
    Result := '-' + Result;
end;

class function TMetricsReport.JsonString(const AText: string): string;
var
  Index: Integer;
  Ch: Char;
begin
  Result := '"';
  for Index := 1 to Length(AText) do
  begin
    Ch := AText[Index];
    case Ch of
      '"':
        Result := Result + '\"';
      '\':
        Result := Result + '\\';
      #8:
        Result := Result + '\b';
      #9:
        Result := Result + '\t';
      #10:
        Result := Result + '\n';
      #12:
        Result := Result + '\f';
      #13:
        Result := Result + '\r';
    else
      if Ord(Ch) < 32 then
        Result := Result + '\u' + IntToHex(Ord(Ch), 4)
      else
        Result := Result + Ch;
    end;
  end;
  Result := Result + '"';
end;

function ValuesJson(const AValues: TMetricValues): string;
var
  Kind: TMetricKind;
begin
  Result := '{';
  for Kind := Low(TMetricKind) to High(TMetricKind) do
  begin
    if Kind <> Low(TMetricKind) then
      Result := Result + ', ';
    Result := Result + TMetricsReport.JsonString(TMetrics.Key(Kind)) + ': ' + IntToStr(AValues[Kind]);
  end;
  Result := Result + '}';
end;

class function TMetricsReport.LimitsJson(const ALimits: TMetricLimits): string;
begin
  Result := ValuesJson(ALimits.Values);
end;

class function TMetricsReport.SummaryJson(const ASummary: TMetricsSummary): string;
var
  Kind: TMetricKind;
  Average: string;
begin
  Average := '{';
  for Kind := Low(TMetricKind) to High(TMetricKind) do
  begin
    if Kind <> Low(TMetricKind) then
      Average := Average + ', ';
    Average := Average + JsonString(TMetrics.Key(Kind)) + ': ' + TenthsText(ASummary.AverageTenths(Kind));
  end;
  Average := Average + '}';
  Result := '{"files": ' + IntToStr(ASummary.Files) + ', "methods": ' + IntToStr(ASummary.Methods) +
    ', "overLimits": ' + IntToStr(ASummary.OverLimits) + ', "average": ' + Average + ', "maximum": ' +
    ValuesJson(ASummary.Maximum) + ', "exceeded": ' + ValuesJson(ASummary.Exceeded) + '}';
end;

class function TMetricsReport.RoutineJson(const ARoutine: TRoutineMetrics; const ALimits: TMetricLimits): string;
var
  Kind: TMetricKind;
  Exceeded: string;
begin
  Exceeded := '';
  for Kind in ALimits.Exceeded(ARoutine.Values) do
  begin
    if Exceeded <> '' then
      Exceeded := Exceeded + ', ';
    Exceeded := Exceeded + JsonString(TMetrics.Key(Kind));
  end;
  Result := '{"name": ' + JsonString(ARoutine.Name) + ', "line": ' + IntToStr(ARoutine.NameRange.StartPos.Line + 1) +
    ', "character": ' + IntToStr(ARoutine.NameRange.StartPos.Character + 1) + ', "endLine": ' +
    IntToStr(ARoutine.Range.EndPos.Line + 1) + ', "values": ' + ValuesJson(ARoutine.Values) + ', "exceeded": [' +
    Exceeded + ']}';
end;

class function TMetricsReport.FileJson(const AFile: TFileMetrics; const ALimits: TMetricLimits): string;
var
  Index: Integer;
begin
  Result := '{"file": ' + JsonString(AFile.Path) + ', "methods": [';
  for Index := 0 to High(AFile.Routines) do
  begin
    if Index > 0 then
      Result := Result + ', ';
    Result := Result + RoutineJson(AFile.Routines[Index], ALimits);
  end;
  Result := Result + ']}';
end;

class function TMetricsReport.Json(const AFiles: TArray<TFileMetrics>; const ALimits: TMetricLimits): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('{"format": ').Append(IntToStr(Format)).Append(', "limits": ').Append(LimitsJson(ALimits));
    Builder.Append(', "summary": ').Append(SummaryJson(Summarize(AFiles, ALimits))).Append(', "files": [');
    for Index := 0 to High(AFiles) do
    begin
      if Index > 0 then
        Builder.Append(',');
      Builder.Append(LineBreak).Append('  ').Append(FileJson(AFiles[Index], ALimits));
    end;
    Builder.Append(']}').Append(LineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function Cell(const AText: string): string;
begin
  Result := StringReplace(AText, '|', '\|', [rfReplaceAll]);
end;

/// <summary>Wert für die Tabelle; über dem Grenzwert fett.</summary>
function ValueCell(const ALimits: TMetricLimits; AKind: TMetricKind; AValue: Integer): string;
begin
  Result := IntToStr(AValue);
  if ALimits.Exceeds(AKind, AValue) then
    Result := '**' + Result + '**';
end;

function RoutineRow(const ARow: TReportRow; const ALimits: TMetricLimits): string;
var
  Kind: TMetricKind;
begin
  Result := '| ' + Cell(ARow.Routine.Name) + ' | ' + Cell(ARow.Path) + ' | ' +
    IntToStr(ARow.Routine.NameRange.StartPos.Line + 1);
  for Kind := Low(TMetricKind) to High(TMetricKind) do
    Result := Result + ' | ' + ValueCell(ALimits, Kind, ARow.Routine.Values[Kind]);
  Result := Result + ' |';
end;

function RoutineHeader: string;
begin
  Result := '| Methode | Datei | Zeile | Länge | Tiefe | zyklomatisch | kognitiv | Parameter |' + LineBreak +
    '|---|---|---:|---:|---:|---:|---:|---:|';
end;

class function TMetricsReport.Markdown(const AFiles: TArray<TFileMetrics>; const ALimits: TMetricLimits;
  const ATitle: string): string;
var
  Builder: TStringBuilder;
  Summary, FileSummary: TMetricsSummary;
  Kind: TMetricKind;
  Rows, Over: TList<TReportRow>;
  Row: TReportRow;
  FileItem: TFileMetrics;
  Routine: TRoutineMetrics;
  Index: Integer;
  OneFile: TArray<TFileMetrics>;
begin
  Summary := Summarize(AFiles, ALimits);
  SetLength(OneFile, 1);
  Builder := TStringBuilder.Create;
  Rows := TList<TReportRow>.Create;
  Over := TList<TReportRow>.Create;
  try
    if ATitle <> '' then
      Builder.Append('# Code-Metriken: ').Append(ATitle).Append(LineBreak)
    else
      Builder.Append('# Code-Metriken').Append(LineBreak);
    Builder.Append(LineBreak);
    Builder.Append(IntToStr(Summary.Files)).Append(' Dateien, ').Append(IntToStr(Summary.Methods))
      .Append(' Methoden, davon ').Append(IntToStr(Summary.OverLimits)).Append(' über mindestens einem Grenzwert. ')
      .Append('Grenzwerte aus atlas.json ("rules": { "metric-…": { "max": … } }), sonst die Vorgaben.')
      .Append(LineBreak).Append(LineBreak);

    Builder.Append('| Kennzahl | Grenzwert | Mittelwert | Maximum | Methoden darüber |').Append(LineBreak);
    Builder.Append('|---|---:|---:|---:|---:|').Append(LineBreak);
    for Kind := Low(TMetricKind) to High(TMetricKind) do
      Builder.Append('| ').Append(TMetrics.Caption(Kind)).Append(' | ').Append(IntToStr(ALimits.Values[Kind]))
        .Append(' | ').Append(StringReplace(TenthsText(Summary.AverageTenths(Kind)), '.', ',', []))
        .Append(' | ').Append(IntToStr(Summary.Maximum[Kind])).Append(' | ').Append(IntToStr(Summary.Exceeded[Kind]))
        .Append(' |').Append(LineBreak);

    for FileItem in AFiles do
      for Routine in FileItem.Routines do
      begin
        Row.Path := FileItem.Path;
        Row.Routine := Routine;
        Row.Exceeded := Length(ALimits.Exceeded(Routine.Values));
        Rows.Add(Row);
        if Row.Exceeded > 0 then
          Over.Add(Row);
      end;

    Builder.Append(LineBreak).Append('## Über einem Grenzwert').Append(LineBreak).Append(LineBreak);
    if Over.Count = 0 then
      Builder.Append('Keine Methode überschreitet einen Grenzwert.').Append(LineBreak)
    else
    begin
      // Meiste Überschreitungen zuerst, dann die kognitiv komplexesten.
      Over.Sort(TComparer<TReportRow>.Construct(
        function(const A, B: TReportRow): Integer
        begin
          Result := B.Exceeded - A.Exceeded;
          if Result = 0 then
            Result := B.Routine.Values[TMetricKind.Cognitive] - A.Routine.Values[TMetricKind.Cognitive];
          if Result = 0 then
            Result := B.Routine.Values[TMetricKind.MethodLength] - A.Routine.Values[TMetricKind.MethodLength];
          if Result = 0 then
            Result := CompareText(A.Path + A.Routine.Name, B.Path + B.Routine.Name);
        end));
      Builder.Append(RoutineHeader).Append(LineBreak);
      for Index := 0 to Over.Count - 1 do
      begin
        if Index >= MaxRows then
        begin
          Builder.Append(LineBreak).Append('… und ').Append(IntToStr(Over.Count - MaxRows)).Append(' weitere.')
            .Append(LineBreak);
          Break;
        end;
        Builder.Append(RoutineRow(Over[Index], ALimits)).Append(LineBreak);
      end;
    end;

    if Rows.Count > 0 then
    begin
      Rows.Sort(TComparer<TReportRow>.Construct(
        function(const A, B: TReportRow): Integer
        begin
          Result := B.Routine.Values[TMetricKind.Cognitive] - A.Routine.Values[TMetricKind.Cognitive];
          if Result = 0 then
            Result := B.Routine.Values[TMetricKind.Cyclomatic] - A.Routine.Values[TMetricKind.Cyclomatic];
          if Result = 0 then
            Result := CompareText(A.Path + A.Routine.Name, B.Path + B.Routine.Name);
        end));
      Builder.Append(LineBreak).Append('## Komplexeste Methoden').Append(LineBreak).Append(LineBreak);
      Builder.Append(RoutineHeader).Append(LineBreak);
      for Index := 0 to Rows.Count - 1 do
      begin
        if Index >= TopRows then
          Break;
        Builder.Append(RoutineRow(Rows[Index], ALimits)).Append(LineBreak);
      end;
    end;

    if Length(AFiles) > 0 then
    begin
      Builder.Append(LineBreak).Append('## Dateien').Append(LineBreak).Append(LineBreak);
      Builder.Append('| Datei | Methoden | Ø Länge | max. zyklomatisch | max. kognitiv | über Grenzwert |')
        .Append(LineBreak);
      Builder.Append('|---|---:|---:|---:|---:|---:|').Append(LineBreak);
      for FileItem in AFiles do
      begin
        OneFile[0] := FileItem;
        FileSummary := Summarize(OneFile, ALimits);
        Builder.Append('| ').Append(Cell(FileItem.Path)).Append(' | ').Append(IntToStr(FileSummary.Methods))
          .Append(' | ').Append(StringReplace(TenthsText(FileSummary.AverageTenths(TMetricKind.MethodLength)), '.',
          ',', [])).Append(' | ').Append(IntToStr(FileSummary.Maximum[TMetricKind.Cyclomatic])).Append(' | ')
          .Append(IntToStr(FileSummary.Maximum[TMetricKind.Cognitive])).Append(' | ')
          .Append(IntToStr(FileSummary.OverLimits)).Append(' |').Append(LineBreak);
      end;
    end;
    Result := Builder.ToString;
  finally
    Over.Free;
    Rows.Free;
    Builder.Free;
  end;
end;

class function TMetricsReport.LensTitle(const AValues: TMetricValues; const ALimits: TMetricLimits): string;

  function Part(AKind: TMetricKind; const AText: string): string;
  begin
    Result := AText;
    if ALimits.Exceeds(AKind, AValues[AKind]) then
      Result := Result + ' (> ' + IntToStr(ALimits.Values[AKind]) + ')';
  end;

begin
  Result := Part(TMetricKind.MethodLength, IntToStr(AValues[TMetricKind.MethodLength]) + ' Zeilen') + ' · ' +
    Part(TMetricKind.NestingDepth, 'Tiefe ' + IntToStr(AValues[TMetricKind.NestingDepth])) + ' · ' +
    Part(TMetricKind.Cyclomatic, 'zyklomatisch ' + IntToStr(AValues[TMetricKind.Cyclomatic])) + ' · ' +
    Part(TMetricKind.Cognitive, 'kognitiv ' + IntToStr(AValues[TMetricKind.Cognitive])) + ' · ' +
    Part(TMetricKind.ParameterCount, IntToStr(AValues[TMetricKind.ParameterCount]) + ' Parameter');
end;

class function TMetricsReport.StructureKey(AKind: TStructureKind): string;
begin
  case AKind of
    TStructureKind.ClassSize:
      Result := 'classSize';
    TStructureKind.UnitLength:
      Result := 'unitLength';
  else
    Result := 'usesCount';
  end;
end;

class function TMetricsReport.StructureJson(const AItems: TArray<TStructureMetrics>;
  const ALimits: TMetricLimits): string;
var
  Index: Integer;
  Item: TStructureMetrics;
begin
  Result := '[';
  for Index := 0 to High(AItems) do
  begin
    Item := AItems[Index];
    if Index > 0 then
      Result := Result + ', ';
    Result := Result + '{"kind": ' + JsonString(StructureKey(Item.Kind)) + ', "name": ' + JsonString(Item.Name) +
      ', "line": ' + IntToStr(Item.NameRange.StartPos.Line + 1) + ', "character": ' +
      IntToStr(Item.NameRange.StartPos.Character + 1) + ', "value": ' + IntToStr(Item.Value) + ', "limit": ' +
      IntToStr(ALimits.Structure[Item.Kind]) + '}';
  end;
  Result := Result + ']';
end;

class function TMetricsReport.StructureLensPart(AKind: TStructureKind; AValue: Integer;
  const ALimits: TMetricLimits): string;
begin
  case AKind of
    TStructureKind.ClassSize:
      Result := IntToStr(AValue) + ' Member';
    TStructureKind.UnitLength:
      Result := IntToStr(AValue) + ' Zeilen';
  else
    Result := IntToStr(AValue) + ' Units im uses';
  end;
  if ALimits.ExceedsStructure(AKind, AValue) then
    Result := Result + ' (> ' + IntToStr(ALimits.Structure[AKind]) + ')';
end;

end.
