unit Atlas.Common.Metrics.Report;

// Bericht der Code-Metriken (#66) als Markdown und Metrikdaten als JSON.
// Den HTML-Bericht baut #156 aus diesen Daten; hier entsteht kein HTML.
//
// JSON (Format 1, Zeilen und Spalten ab 1):
//   {"format": 1,
//    "limits": {"length": 60, "nesting": 4, "cyclomatic": 15, "cognitive": 15, "parameters": 6,
//               "operands": 5, "locals": 12, "exits": 4},
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
// kind ist classSize, unitLength, usesCount oder inheritanceDepth (#980, nur mit Index über
// TMetricRules.InheritanceDepths); "atLeast": true, wenn value nur eine Untergrenze ist.

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
    /// <summary>Titel der Code Lens: "12 Zeilen · Tiefe 2 · zyklomatisch 4 · kognitiv 3 · 2 Parameter · Operanden 2 ·
    /// 3 lokale · 1 Ausstiege";
    /// Überschreitungen mit Grenzwert, z. B. "zyklomatisch 17 (> 15)".</summary>
    class function LensTitle(const AValues: TMetricValues; const ALimits: TMetricLimits): string; static;
    /// <summary>Kennung des Aufbaus in JSON: classSize, unitLength, usesCount (#939), inheritanceDepth (#980).
    /// </summary>
    class function StructureKey(AKind: TStructureKind): string; static;
    /// <summary>Kennzahlen des Aufbaus als JSON-Array (siehe Kopf der Unit, #939).</summary>
    class function StructureJson(const AItems: TArray<TStructureMetrics>; const ALimits: TMetricLimits): string;
      static;
    /// <summary>Teil der Code Lens zum Aufbau (#939): "87 Member", "2140 Zeilen", "34 Units im uses" bzw.
    /// "Vererbungstiefe 3" (#980);
    /// Überschreitungen mit Grenzwert, z. B. "87 Member (> 40)".</summary>
    class function StructureLensPart(AKind: TStructureKind; AValue: Integer; const ALimits: TMetricLimits): string;
      overload; static;
    /// <summary>Wie oben für AItem; eine Untergrenze der Vererbungstiefe als "Vererbungstiefe mindestens 3"
    /// (#980).</summary>
    class function StructureLensPart(const AItem: TStructureMetrics; const ALimits: TMetricLimits): string; overload;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.Math,
  Atlas.Text.Json,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TMetricsReportText = (MethodFileLineLengthDepth, AboveAtLeastOneThreshold, ThresholdsFromAtlasJsonRules,
    MetricThresholdMeanMaximumMethods, AboveAThreshold, NoMethodExceedsAThreshold, AndText,
    FileMethodsLengthMaxCyclomatic, MethodsOfThese, MostComplexMethods, UnitsInUses, CodeMetrics, Depth, Cyclomatic,
    Cognitive, Operands, Exits, InheritanceDepth, InheritanceDepthAtLeast, Files, FilesHeading, CaptionLength,
    CaptionDepth, CaptionCyclomatic, CaptionCognitive, CaptionParameters, CaptionOperands, CaptionLocals,
    CaptionExits);

const
  cTexts: array[TMetricsReportText] of TAtlasText = (
    (De: '| Methode | Datei | Zeile | Länge | Tiefe | zyklomatisch | kognitiv | Parameter | Operanden | lokale ' +
      'Variablen | Ausstiege |%s|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|';
     En: '| Method | File | Line | Length | Depth | cyclomatic | cognitive | Parameters | Operands | local variables ' +
      '| Exits |%s|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|'),
    (De: ' über mindestens einem Grenzwert. '; En: ' above at least one threshold. '),
    (De: 'Grenzwerte aus atlas.json ("rules": { "metric-…": { "max": … } }), sonst die Vorgaben.';
     En: 'Thresholds from atlas.json ("rules": { "metric-…": { "max": … } }), otherwise the defaults.'),
    (De: '| Kennzahl | Grenzwert | Mittelwert | Maximum | Methoden darüber |';
     En: '| Metric | Threshold | Mean | Maximum | Methods above |'),
    (De: '## Über einem Grenzwert'; En: '## Above a threshold'),
    (De: 'Keine Methode überschreitet einen Grenzwert.'; En: 'No method exceeds a threshold.'),
    (De: '… und '; En: '… and '),
    (De: '| Datei | Methoden | Ø Länge | max. zyklomatisch | max. kognitiv | über Grenzwert |';
     En: '| File | Methods | Ø length | max. cyclomatic | max. cognitive | above threshold |'),
    (De: ' Methoden, davon '; En: ' methods, of these '),
    (De: '## Komplexeste Methoden'; En: '## Most complex methods'),
    (De: ' Units im uses'; En: ' units in uses'),
    (De: '# Code-Metriken'; En: '# Code metrics'),
    (De: 'Tiefe '; En: 'depth '),
    (De: 'zyklomatisch '; En: 'cyclomatic '),
    (De: 'kognitiv '; En: 'cognitive '),
    (De: 'Operanden '; En: 'operands '),
    (De: ' Ausstiege'; En: ' exits'),
    (De: 'Vererbungstiefe '; En: 'Inheritance depth '),
    (De: 'Vererbungstiefe mindestens '; En: 'Inheritance depth at least '),
    (De: ' Dateien, '; En: ' files, '),
    (De: '## Dateien'; En: '## Files'),
    (De: 'Länge'; En: 'length'),
    (De: 'Tiefe'; En: 'depth'),
    (De: 'zyklomatisch'; En: 'cyclomatic'),
    (De: 'kognitiv'; En: 'cognitive'),
    (De: 'Parameter'; En: 'parameters'),
    (De: 'Operanden'; En: 'operands'),
    (De: 'lokale Variablen'; En: 'local variables'),
    (De: 'Ausstiege'; En: 'exits'));

{$SCOPEDENUMS OFF}

/// <summary>Kurzname der Kennzahl in der Sprache von Atlas, z. B. „zyklomatisch“.</summary>
function MetricCaption(AKind: TMetricKind): string;
const
  cCaptions: array[TMetricKind] of TMetricsReportText = (TMetricsReportText.CaptionLength,
    TMetricsReportText.CaptionDepth, TMetricsReportText.CaptionCyclomatic, TMetricsReportText.CaptionCognitive,
    TMetricsReportText.CaptionParameters, TMetricsReportText.CaptionOperands, TMetricsReportText.CaptionLocals,
    TMetricsReportText.CaptionExits);
begin
  Result := cTexts[cCaptions[AKind]].Text;
end;

/// <summary>Zehntel als Text mit dem Dezimaltrenner der Sprache (Komma auf Deutsch).</summary>
function DecimalText(const AText: string): string;
begin
  Result := AText;
  if TAtlasLocale.Language = TTextLanguage.German then
  begin
    Result := StringReplace(Result, '.', ',', []);
  end;
end;

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
  begin
    Exit(0);
  end;
  Result := Integer((Totals[AKind] * 10 + Methods div 2) div Methods);
end;

{ TMetricsReport }

/// <summary>Zählt die Kennzahlen einer Methode in ASummary ein.</summary>
procedure AddRoutine(var ASummary: TMetricsSummary; const ARoutine: TRoutineMetrics; const ALimits: TMetricLimits);
var
  mKind: TMetricKind;
  mOver: Boolean;
begin
  Inc(ASummary.Methods);
  mOver := False;
  for mKind := Low(TMetricKind) to High(TMetricKind) do
  begin
    Inc(ASummary.Totals[mKind], ARoutine.Values[mKind]);
    if ARoutine.Values[mKind] > ASummary.Maximum[mKind] then
    begin
      ASummary.Maximum[mKind] := ARoutine.Values[mKind];
    end;
    if ALimits.Exceeds(mKind, ARoutine.Values[mKind]) then
    begin
      Inc(ASummary.Exceeded[mKind]);
      mOver := True;
    end;
  end;
  if mOver then
  begin
    Inc(ASummary.OverLimits);
  end;
end;

class function TMetricsReport.Summarize(const AFiles: TArray<TFileMetrics>;
  const ALimits: TMetricLimits): TMetricsSummary;
var
  mFile: TFileMetrics;
  mRoutine: TRoutineMetrics;
begin
  Result := Default(TMetricsSummary);
  Result.Files := Length(AFiles);
  for mFile in AFiles do
  begin
    for mRoutine in mFile.Routines do
    begin
      AddRoutine(Result, mRoutine, ALimits);
    end;
  end;
end;

class function TMetricsReport.TenthsText(ATenths: Int64): string;
var
  Value: Int64;
begin
  Value := Abs(ATenths);
  Result := IntToStr(Value div 10) + '.' + IntToStr(Value mod 10);
  if ATenths < 0 then
  begin
    Result := '-' + Result;
  end;
end;

class function TMetricsReport.JsonString(const AText: string): string;
begin
  Result := TJsonText.Quote(AText);
end;

function ValuesJson(const AValues: TMetricValues): string;
var
  Kind: TMetricKind;
begin
  Result := '{';
  for Kind := Low(TMetricKind) to High(TMetricKind) do
  begin
    if Kind <> Low(TMetricKind) then
    begin
      Result := Result + ', ';
    end;
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
    begin
      Average := Average + ', ';
    end;
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
    begin
      Exceeded := Exceeded + ', ';
    end;
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
    begin
      Result := Result + ', ';
    end;
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
      begin
        Builder.Append(',');
      end;
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
  begin
    Result := '**' + Result + '**';
  end;
end;

function RoutineRow(const ARow: TReportRow; const ALimits: TMetricLimits): string;
var
  Kind: TMetricKind;
begin
  Result := '| ' + Cell(ARow.Routine.Name) + ' | ' + Cell(ARow.Path) + ' | ' +
    IntToStr(ARow.Routine.NameRange.StartPos.Line + 1);
  for Kind := Low(TMetricKind) to High(TMetricKind) do
  begin
    Result := Result + ' | ' + ValueCell(ALimits, Kind, ARow.Routine.Values[Kind]);
  end;
  Result := Result + ' |';
end;

function RoutineHeader: string;
begin
  Result := cTexts[TMetricsReportText.MethodFileLineLengthDepth].Fmt([LineBreak]);
end;

/// <summary>Kopf mit Titel, Überblick und Tabelle der Kennzahlen.</summary>
procedure AppendSummary(ABuilder: TStringBuilder; const ASummary: TMetricsSummary; const ALimits: TMetricLimits;
  const ATitle: string);
var
  mKind: TMetricKind;
begin
  ABuilder.Append(cTexts[TMetricsReportText.CodeMetrics].Text);
  if ATitle <> '' then
  begin
    ABuilder.Append(': ').Append(ATitle);
  end;
  ABuilder.Append(LineBreak).Append(LineBreak);
  ABuilder.Append(IntToStr(ASummary.Files)).Append(cTexts[TMetricsReportText.Files].Text)
    .Append(IntToStr(ASummary.Methods))
    .Append(cTexts[TMetricsReportText.MethodsOfThese].Text).Append(IntToStr(ASummary.OverLimits))
    .Append(cTexts[TMetricsReportText.AboveAtLeastOneThreshold].Text)
    .Append(cTexts[TMetricsReportText.ThresholdsFromAtlasJsonRules].Text)
    .Append(LineBreak).Append(LineBreak);

  ABuilder.Append(cTexts[TMetricsReportText.MetricThresholdMeanMaximumMethods].Text).Append(LineBreak);
  ABuilder.Append('|---|---:|---:|---:|---:|').Append(LineBreak);
  for mKind := Low(TMetricKind) to High(TMetricKind) do
  begin
    ABuilder.Append('| ').Append(MetricCaption(mKind)).Append(' | ').Append(IntToStr(ALimits.Values[mKind]))
      .Append(' | ').Append(DecimalText(TMetricsReport.TenthsText(ASummary.AverageTenths(mKind))))
      .Append(' | ').Append(IntToStr(ASummary.Maximum[mKind])).Append(' | ').Append(IntToStr(ASummary.Exceeded[mKind]))
      .Append(' |').Append(LineBreak);
  end;
end;

/// <summary>Alle Methoden als Zeilen in ARows, die über einem Grenzwert zusätzlich in AOver.</summary>
procedure CollectRows(const AFiles: TArray<TFileMetrics>; const ALimits: TMetricLimits;
  ARows, AOver: TList<TReportRow>);
var
  mFile: TFileMetrics;
  mRoutine: TRoutineMetrics;
  mRow: TReportRow;
begin
  for mFile in AFiles do
  begin
    for mRoutine in mFile.Routines do
    begin
      mRow.Path := mFile.Path;
      mRow.Routine := mRoutine;
      mRow.Exceeded := Length(ALimits.Exceeded(mRoutine.Values));
      ARows.Add(mRow);
      if mRow.Exceeded > 0 then
      begin
        AOver.Add(mRow);
      end;
    end;
  end;
end;

/// <summary>Meiste Überschreitungen zuerst, dann die kognitiv komplexesten, dann die längsten.</summary>
function CompareOver(const A, B: TReportRow): Integer;
begin
  Result := B.Exceeded - A.Exceeded;
  if Result = 0 then
  begin
    Result := B.Routine.Values[TMetricKind.Cognitive] - A.Routine.Values[TMetricKind.Cognitive];
  end;
  if Result = 0 then
  begin
    Result := B.Routine.Values[TMetricKind.MethodLength] - A.Routine.Values[TMetricKind.MethodLength];
  end;
  if Result = 0 then
  begin
    Result := CompareText(A.Path + A.Routine.Name, B.Path + B.Routine.Name);
  end;
end;

/// <summary>Kognitiv komplexeste zuerst, dann die zyklomatisch komplexesten.</summary>
function CompareComplexity(const A, B: TReportRow): Integer;
begin
  Result := B.Routine.Values[TMetricKind.Cognitive] - A.Routine.Values[TMetricKind.Cognitive];
  if Result = 0 then
  begin
    Result := B.Routine.Values[TMetricKind.Cyclomatic] - A.Routine.Values[TMetricKind.Cyclomatic];
  end;
  if Result = 0 then
  begin
    Result := CompareText(A.Path + A.Routine.Name, B.Path + B.Routine.Name);
  end;
end;

/// <summary>Abschnitt "Über einem Grenzwert" mit höchstens TMetricsReport.MaxRows Zeilen.</summary>
procedure AppendOverLimits(ABuilder: TStringBuilder; AOver: TList<TReportRow>; const ALimits: TMetricLimits);
var
  mIndex: Integer;
begin
  ABuilder.Append(LineBreak).Append(cTexts[TMetricsReportText.AboveAThreshold].Text).Append(LineBreak)
    .Append(LineBreak);
  if AOver.Count = 0 then
  begin
    ABuilder.Append(cTexts[TMetricsReportText.NoMethodExceedsAThreshold].Text).Append(LineBreak);
    Exit;
  end;
  AOver.Sort(TComparer<TReportRow>.Construct(
    function(const A, B: TReportRow): Integer
    begin
      Result := CompareOver(A, B);
    end));
  ABuilder.Append(RoutineHeader).Append(LineBreak);
  for mIndex := 0 to Min(AOver.Count, TMetricsReport.MaxRows) - 1 do
  begin
    ABuilder.Append(RoutineRow(AOver[mIndex], ALimits)).Append(LineBreak);
  end;
  if AOver.Count > TMetricsReport.MaxRows then
  begin
    ABuilder.Append(LineBreak).Append(cTexts[TMetricsReportText.AndText].Text)
      .Append(IntToStr(AOver.Count - TMetricsReport.MaxRows))
      .Append(' weitere.').Append(LineBreak);
  end;
end;

/// <summary>Abschnitt "Komplexeste Methoden" mit höchstens TMetricsReport.TopRows Zeilen.</summary>
procedure AppendMostComplex(ABuilder: TStringBuilder; ARows: TList<TReportRow>; const ALimits: TMetricLimits);
var
  mIndex: Integer;
begin
  if ARows.Count = 0 then
  begin
    Exit;
  end;
  ARows.Sort(TComparer<TReportRow>.Construct(
    function(const A, B: TReportRow): Integer
    begin
      Result := CompareComplexity(A, B);
    end));
  ABuilder.Append(LineBreak).Append(cTexts[TMetricsReportText.MostComplexMethods].Text).Append(LineBreak)
    .Append(LineBreak);
  ABuilder.Append(RoutineHeader).Append(LineBreak);
  for mIndex := 0 to Min(ARows.Count, TMetricsReport.TopRows) - 1 do
  begin
    ABuilder.Append(RoutineRow(ARows[mIndex], ALimits)).Append(LineBreak);
  end;
end;

/// <summary>Abschnitt "Dateien" mit einer Zeile je Datei.</summary>
procedure AppendFiles(ABuilder: TStringBuilder; const AFiles: TArray<TFileMetrics>; const ALimits: TMetricLimits);
var
  mFile: TFileMetrics;
  mSummary: TMetricsSummary;
begin
  if Length(AFiles) = 0 then
  begin
    Exit;
  end;
  ABuilder.Append(LineBreak).Append(cTexts[TMetricsReportText.FilesHeading].Text).Append(LineBreak).Append(LineBreak);
  ABuilder.Append(cTexts[TMetricsReportText.FileMethodsLengthMaxCyclomatic].Text)
    .Append(LineBreak);
  ABuilder.Append('|---|---:|---:|---:|---:|---:|').Append(LineBreak);
  for mFile in AFiles do
  begin
    mSummary := TMetricsReport.Summarize(TArray<TFileMetrics>.Create(mFile), ALimits);
    ABuilder.Append('| ').Append(Cell(mFile.Path)).Append(' | ').Append(IntToStr(mSummary.Methods))
      .Append(' | ').Append(DecimalText(TMetricsReport.TenthsText(mSummary.AverageTenths(TMetricKind.MethodLength))))
      .Append(' | ').Append(IntToStr(mSummary.Maximum[TMetricKind.Cyclomatic])).Append(' | ')
      .Append(IntToStr(mSummary.Maximum[TMetricKind.Cognitive])).Append(' | ')
      .Append(IntToStr(mSummary.OverLimits)).Append(' |').Append(LineBreak);
  end;
end;

class function TMetricsReport.Markdown(const AFiles: TArray<TFileMetrics>; const ALimits: TMetricLimits;
  const ATitle: string): string;
var
  mBuilder: TStringBuilder;
  mRows, mOver: TList<TReportRow>;
begin
  mBuilder := TStringBuilder.Create;
  mRows := TList<TReportRow>.Create;
  mOver := TList<TReportRow>.Create;
  try
    AppendSummary(mBuilder, Summarize(AFiles, ALimits), ALimits, ATitle);
    CollectRows(AFiles, ALimits, mRows, mOver);
    AppendOverLimits(mBuilder, mOver, ALimits);
    AppendMostComplex(mBuilder, mRows, ALimits);
    AppendFiles(mBuilder, AFiles, ALimits);
    Result := mBuilder.ToString;
  finally
    mOver.Free;
    mRows.Free;
    mBuilder.Free;
  end;
end;

class function TMetricsReport.LensTitle(const AValues: TMetricValues; const ALimits: TMetricLimits): string;

  function Part(AKind: TMetricKind; const AText: string): string;
  begin
    Result := AText;
    if ALimits.Exceeds(AKind, AValues[AKind]) then
    begin
      Result := Result + ' (> ' + IntToStr(ALimits.Values[AKind]) + ')';
    end;
  end;

begin
  Result := Part(TMetricKind.MethodLength, IntToStr(AValues[TMetricKind.MethodLength]) + ' Zeilen') + ' · ' +
    Part(TMetricKind.NestingDepth, cTexts[TMetricsReportText.Depth].Text +
      IntToStr(AValues[TMetricKind.NestingDepth])) + ' · ' +
    Part(TMetricKind.Cyclomatic, cTexts[TMetricsReportText.Cyclomatic].Text +
      IntToStr(AValues[TMetricKind.Cyclomatic])) + ' · ' +
    Part(TMetricKind.Cognitive, cTexts[TMetricsReportText.Cognitive].Text + IntToStr(AValues[TMetricKind.Cognitive])) +
      ' · ' +
    Part(TMetricKind.ParameterCount, IntToStr(AValues[TMetricKind.ParameterCount]) + ' Parameter') + ' · ' +
    Part(TMetricKind.BooleanOperands, cTexts[TMetricsReportText.Operands].Text +
      IntToStr(AValues[TMetricKind.BooleanOperands])) + ' · ' +
    Part(TMetricKind.LocalCount, IntToStr(AValues[TMetricKind.LocalCount]) + ' lokale') + ' · ' +
    Part(TMetricKind.ExitPoints, IntToStr(AValues[TMetricKind.ExitPoints]) + cTexts[TMetricsReportText.Exits].Text);
end;

class function TMetricsReport.StructureKey(AKind: TStructureKind): string;
begin
  case AKind of
    TStructureKind.ClassSize:
      Result := 'classSize';
    TStructureKind.UnitLength:
      Result := 'unitLength';
    TStructureKind.UsesCount:
      Result := 'usesCount';
  else
    Result := 'inheritanceDepth';
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
    begin
      Result := Result + ', ';
    end;
    Result := Result + '{"kind": ' + JsonString(StructureKey(Item.Kind)) + ', "name": ' + JsonString(Item.Name) +
      ', "line": ' + IntToStr(Item.NameRange.StartPos.Line + 1) + ', "character": ' +
      IntToStr(Item.NameRange.StartPos.Character + 1) + ', "value": ' + IntToStr(Item.Value) + ', "limit": ' +
      IntToStr(ALimits.Structure[Item.Kind]);
    if Item.AtLeast then
    begin
      Result := Result + ', "atLeast": true';
    end;
    Result := Result + '}';
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
    TStructureKind.UsesCount:
      Result := IntToStr(AValue) + cTexts[TMetricsReportText.UnitsInUses].Text;
  else
    Result := cTexts[TMetricsReportText.InheritanceDepth].Text + IntToStr(AValue);
  end;
  if ALimits.ExceedsStructure(AKind, AValue) then
  begin
    Result := Result + ' (> ' + IntToStr(ALimits.Structure[AKind]) + ')';
  end;
end;

class function TMetricsReport.StructureLensPart(const AItem: TStructureMetrics; const ALimits: TMetricLimits): string;
begin
  Result := StructureLensPart(AItem.Kind, AItem.Value, ALimits);
  if AItem.AtLeast and (AItem.Kind = TStructureKind.InheritanceDepth) then
  begin
    Result := StringReplace(Result, cTexts[TMetricsReportText.InheritanceDepth].Text,
      cTexts[TMetricsReportText.InheritanceDepthAtLeast].Text, []);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Metrics.Report', cTexts);

end.
