unit Atlas.Common.Query.Output;

// Ausgabe der Code-Abfragen (#1351): Markdown (MCP), JSON (MCP, LSP,
// --format json), CSV (--format csv, „Als CSV kopieren“) und Text
// (--format text). Fehler stehen mit Spalte, Marke unter der Abfrage und
// Vorschlag da; erschlossene Treffer (#1119) tragen das Kennzeichen
// „erschlossen“. Die Meldung gespeicherter Abfragen bildet TQueryResult.Message.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Query.Contract;

{$SCOPEDENUMS ON}

type
  TQueryOutputFormat = (Markdown, Json, Csv, Text);

  TQueryOutput = class
  public
    /// <summary>"markdown", "json", "csv" oder "text" ('' = AFallback); False bei anderem Text.</summary>
    class function TryParseFormat(const AText: string; AFallback: TQueryOutputFormat;
      out AFormat: TQueryOutputFormat): Boolean; static;
    class function Render(const AResult: TQueryResult; AFormat: TQueryOutputFormat): string; static;
    class function Markdown(const AResult: TQueryResult): string; static;
    class function Json(const AResult: TQueryResult): string; static;
    /// <summary>Kopfzeile mit den Spalten, dazu path und inferred; Trenner Semikolon wie Excel im deutschen
    /// Gebietsschema, Werte bei Bedarf in Anführungszeichen.</summary>
    class function Csv(const AResult: TQueryResult): string; static;
    class function Text(const AResult: TQueryResult): string; static;
    /// <summary>Fehler mit Spalte, der Abfrage und einer Marke darunter, dazu der Vorschlag.</summary>
    class function ErrorText(const AResult: TQueryResult): string; static;
    /// <summary>Katalog für die Vervollständigung im Fenster „Atlas-Abfrage“ (atlas/queryCatalog): Mengen mit ihren
    /// Feldern und Prädikaten, Schlüsselwörter und die gespeicherten Abfragen AQueries.</summary>
    class function CatalogJson(const AQueries: TArray<TSavedQuery>): string; static;
    /// <summary>Meldung einer gespeicherten Abfrage: ATemplate oder bei '' der Vorgabetext in der Sprache von
    /// Atlas.</summary>
    class function MessageTemplate(const ATemplate: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Query.Catalog,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TOutputText = (FileText, MoreMatchesNotShownLimit, InferredMeansACallCounts, OfMatches, DefaultMessage, OneMatch,
    Matches, OfTheseInferred, Column, Suggestion, Inferred, Inferred2, Inferred3);

const
  cTexts: array[TOutputText] of TAtlasText = (
    (De: ' Datei |'; En: ' File |'),
    (De: 'Weitere %d Treffer nicht gezeigt (limit).'; En: '%d more matches not shown (limit).'),
    (De: 'Erschlossen heißt: Ein Aufruf zählt mit, den die Namensauflösung nicht sicher zuordnet (Interface, ' +
      'virtuelle Methode, Überladung; siehe get_call_hierarchy).';
     En: 'Inferred means: a call counts that the name resolution does not assign with certainty (interface, virtual ' +
      'method, overload; see get_call_hierarchy).'),
    (De: '%d von %d Treffern'; En: '%d of %d matches'),
    (De: '{name}: Treffer der Abfrage {query}'; En: '{name}: hit of the query {query}'),
    (De: '1 Treffer'; En: '1 match'),
    (De: '%d Treffer'; En: '%d matches'),
    (De: ', %d davon erschlossen'; En: ', %d of them inferred'),
    (De: 'Spalte %d: %s'; En: 'Column %d: %s'),
    (De: 'Vorschlag: %s'; En: 'Suggestion: %s'),
    (De: ' (erschlossen)'; En: ' (inferred)'),
    (De: 'erschlossen'; En: 'inferred'),
    (De: '  (erschlossen)'; En: '  (inferred)'));

function MarkdownCell(const AText: string): string;
begin
  Result := StringReplace(StringReplace(AText, '|', '\|', [rfReplaceAll]), sLineBreak, ' ', [rfReplaceAll]);
end;

function CsvCell(const AText: string): string;
begin
  if (Pos(';', AText) > 0) or (Pos('"', AText) > 0) or (Pos(#10, AText) > 0) or (Pos(#13, AText) > 0) then
  begin
    Result := '"' + StringReplace(AText, '"', '""', [rfReplaceAll]) + '"';
  end
  else
  begin
    Result := AText;
  end;
end;

function Summary(const AResult: TQueryResult): string;
begin
  if AResult.Truncated then
  begin
    Result := cTexts[TOutputText.OfMatches].Fmt([Length(AResult.Rows), AResult.Total]);
  end
  else if AResult.Total = 1 then
  begin
    Result := cTexts[TOutputText.OneMatch].Text;
  end
  else
  begin
    Result := cTexts[TOutputText.Matches].Fmt([AResult.Total]);
  end;
  if AResult.InferredCount > 0 then
  begin
    Result := Result + cTexts[TOutputText.OfTheseInferred].Fmt([AResult.InferredCount]);
  end;
  Result := Result + Format(' in %d ms', [AResult.ElapsedMs]);
end;

{ TQueryOutput }

class function TQueryOutput.MessageTemplate(const ATemplate: string): string;
begin
  Result := ATemplate;
  if Result = '' then
  begin
    Result := cTexts[TOutputText.DefaultMessage].Text;
  end;
end;

class function TQueryOutput.TryParseFormat(const AText: string; AFallback: TQueryOutputFormat;
  out AFormat: TQueryOutputFormat): Boolean;
begin
  Result := True;
  if AText = '' then
  begin
    AFormat := AFallback;
  end
  else if SameText(AText, 'markdown') then
  begin
    AFormat := TQueryOutputFormat.Markdown;
  end
  else if SameText(AText, 'json') then
  begin
    AFormat := TQueryOutputFormat.Json;
  end
  else if SameText(AText, 'csv') then
  begin
    AFormat := TQueryOutputFormat.Csv;
  end
  else if SameText(AText, 'text') then
  begin
    AFormat := TQueryOutputFormat.Text;
  end
  else
  begin
    AFormat := AFallback;
    Result := False;
  end;
end;

class function TQueryOutput.Render(const AResult: TQueryResult; AFormat: TQueryOutputFormat): string;
begin
  case AFormat of
    TQueryOutputFormat.Json:
      Result := Json(AResult);
    TQueryOutputFormat.Csv:
      Result := Csv(AResult);
    TQueryOutputFormat.Text:
      Result := Text(AResult);
  else
    Result := Markdown(AResult);
  end;
end;

class function TQueryOutput.ErrorText(const AResult: TQueryResult): string;
begin
  if AResult.ErrorColumn > 0 then
  begin
    Result := cTexts[TOutputText.Column].Fmt([AResult.ErrorColumn, AResult.Error]) + sLineBreak + '  ' + AResult.Query +
      sLineBreak + '  ' + StringOfChar(' ', AResult.ErrorColumn - 1) + '^';
  end
  else
  begin
    Result := AResult.Error;
  end;
  if (AResult.Suggestion <> '') and not ContainsText(AResult.Error, '`' + AResult.Suggestion + '`') then
  begin
    Result := Result + sLineBreak + cTexts[TOutputText.Suggestion].Fmt([AResult.Suggestion]);
  end;
end;

procedure AppendMarkdownHead(ABuilder: TStringBuilder; const AResult: TQueryResult);
var
  mIndex: Integer;
begin
  ABuilder.Append(sLineBreak).Append('|');
  for mIndex := 0 to High(AResult.Columns) do
  begin
    ABuilder.Append(' ').Append(AResult.Columns[mIndex]).Append(' |');
  end;
  ABuilder.Append(cTexts[TOutputText.FileText].Text).Append(sLineBreak).Append('|');
  for mIndex := 0 to High(AResult.Columns) + 1 do
  begin
    ABuilder.Append('---|');
  end;
  ABuilder.Append(sLineBreak);
end;

procedure AppendMarkdownRow(ABuilder: TStringBuilder; const AResult: TQueryResult; const ARow: TQueryRow);
var
  mIndex: Integer;
  mCell: string;
begin
  ABuilder.Append('|');
  for mIndex := 0 to High(AResult.Columns) do
  begin
    mCell := MarkdownCell(TQueryResult.CellText(ARow, mIndex));
    if (mIndex = 0) and ARow.Inferred then
    begin
      mCell := mCell + cTexts[TOutputText.Inferred].Text;
    end;
    ABuilder.Append(' ').Append(mCell).Append(' |');
  end;
  ABuilder.Append(' ').Append(MarkdownCell(ARow.Path));
  if AResult.Entity <> 'units' then
  begin
    ABuilder.Append(':').Append(ARow.Range.StartPos.Line + 1);
  end;
  ABuilder.Append(' |').Append(sLineBreak);
end;

function HasInferredRow(const AResult: TQueryResult): Boolean;
var
  mRow: TQueryRow;
begin
  Result := False;
  for mRow in AResult.Rows do
  begin
    if mRow.Inferred then
    begin
      Exit(True);
    end;
  end;
end;

procedure AppendMarkdownNotes(ABuilder: TStringBuilder; const AResult: TQueryResult);
begin
  if AResult.Truncated then
  begin
    ABuilder.Append(sLineBreak).Append(cTexts[TOutputText.MoreMatchesNotShownLimit].Fmt([
      AResult.Total - Length(AResult.Rows)])).Append(sLineBreak);
  end;
  if HasInferredRow(AResult) then
  begin
    ABuilder.Append(sLineBreak).Append(cTexts[TOutputText.InferredMeansACallCounts].Text).Append(sLineBreak);
  end;
end;

class function TQueryOutput.Markdown(const AResult: TQueryResult): string;
var
  mBuilder: TStringBuilder;
  mRow: TQueryRow;
begin
  if AResult.Failed then
  begin
    Exit('```' + sLineBreak + ErrorText(AResult) + sLineBreak + '```');
  end;
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('`').Append(AResult.Query).Append('`: ').Append(Summary(AResult)).Append(sLineBreak);
    if Length(AResult.Rows) > 0 then
    begin
      AppendMarkdownHead(mBuilder, AResult);
      for mRow in AResult.Rows do
      begin
        AppendMarkdownRow(mBuilder, AResult, mRow);
      end;
      AppendMarkdownNotes(mBuilder, AResult);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function JsonValue(const AValue: TQueryValue): string;
begin
  case AValue.Kind of
    TQueryValueKind.Number:
      Result := IntToStr(AValue.Number);
    TQueryValueKind.Text:
      Result := TMetricsReport.JsonString(AValue.Text);
    TQueryValueKind.Flag:
      if AValue.Number <> 0 then
      begin
        Result := 'true';
      end
      else
      begin
        Result := 'false';
      end;
  else
    Result := 'null';
  end;
end;

procedure AppendJsonColumns(ABuilder: TStringBuilder; const AColumns: TArray<string>);
var
  mIndex: Integer;
begin
  ABuilder.Append('[');
  for mIndex := 0 to High(AColumns) do
  begin
    if mIndex > 0 then
    begin
      ABuilder.Append(', ');
    end;
    ABuilder.Append(TMetricsReport.JsonString(AColumns[mIndex]));
  end;
  ABuilder.Append(']');
end;

procedure AppendJsonValues(ABuilder: TStringBuilder; const AColumns: TArray<string>; const ARow: TQueryRow);
var
  mColumn: Integer;
begin
  ABuilder.Append('{');
  for mColumn := 0 to High(AColumns) do
  begin
    if mColumn > 0 then
    begin
      ABuilder.Append(', ');
    end;
    ABuilder.Append(TMetricsReport.JsonString(AColumns[mColumn])).Append(': ');
    if mColumn <= High(ARow.Values) then
    begin
      ABuilder.Append(JsonValue(ARow.Values[mColumn]));
    end
    else
    begin
      ABuilder.Append('null');
    end;
  end;
  ABuilder.Append('}');
end;

procedure AppendJsonRow(ABuilder: TStringBuilder; const AColumns: TArray<string>; const ARow: TQueryRow);
begin
  ABuilder.Append('{"name": ').Append(TMetricsReport.JsonString(ARow.Name))
    .Append(', "container": ').Append(TMetricsReport.JsonString(ARow.Container))
    .Append(', "unit": ').Append(TMetricsReport.JsonString(ARow.UnitName))
    .Append(', "path": ').Append(TMetricsReport.JsonString(ARow.Path))
    .Append(', "file": ').Append(TMetricsReport.JsonString(ARow.FileName))
    .Append(', "line": ').Append(ARow.Range.StartPos.Line + 1)
    .Append(', "character": ').Append(ARow.Range.StartPos.Character + 1)
    .Append(', "inferred": ').Append(LowerCase(BoolToStr(ARow.Inferred, True)));
  if ARow.Inferred then
  begin
    ABuilder.Append(', "inferredDetail": ').Append(TMetricsReport.JsonString(ARow.InferredDetail));
  end;
  ABuilder.Append(', "values": ');
  AppendJsonValues(ABuilder, AColumns, ARow);
  ABuilder.Append('}');
end;

class function TQueryOutput.Json(const AResult: TQueryResult): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('{"query": ').Append(TMetricsReport.JsonString(AResult.Query));
    if AResult.Failed then
    begin
      mBuilder.Append(', "error": {"message": ').Append(TMetricsReport.JsonString(AResult.Error))
        .Append(', "column": ').Append(AResult.ErrorColumn)
        .Append(', "suggestion": ').Append(TMetricsReport.JsonString(AResult.Suggestion)).Append('}}');
      Exit(mBuilder.ToString);
    end;
    mBuilder.Append(', "entity": ').Append(TMetricsReport.JsonString(AResult.Entity)).Append(', "columns": ');
    AppendJsonColumns(mBuilder, AResult.Columns);
    mBuilder.Append(', "total": ').Append(AResult.Total).Append(', "truncated": ')
      .Append(LowerCase(BoolToStr(AResult.Truncated, True))).Append(', "inferred": ').Append(AResult.InferredCount)
      .Append(', "elapsedMs": ').Append(AResult.ElapsedMs).Append(', "rows": [');
    for mIndex := 0 to High(AResult.Rows) do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(', ');
      end;
      AppendJsonRow(mBuilder, AResult.Columns, AResult.Rows[mIndex]);
    end;
    mBuilder.Append(']}');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TQueryOutput.Csv(const AResult: TQueryResult): string;
var
  mBuilder: TStringBuilder;
  mRow: TQueryRow;
  mIndex: Integer;
begin
  if AResult.Failed then
  begin
    Exit(ErrorText(AResult));
  end;
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 0 to High(AResult.Columns) do
    begin
      mBuilder.Append(CsvCell(AResult.Columns[mIndex])).Append(';');
    end;
    mBuilder.Append('path;inferred').Append(sLineBreak);
    for mRow in AResult.Rows do
    begin
      for mIndex := 0 to High(AResult.Columns) do
      begin
        mBuilder.Append(CsvCell(TQueryResult.CellText(mRow, mIndex))).Append(';');
      end;
      mBuilder.Append(CsvCell(mRow.Path)).Append(';');
      if mRow.Inferred then
      begin
        mBuilder.Append(cTexts[TOutputText.Inferred2].Text);
      end;
      mBuilder.Append(sLineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TQueryOutput.Text(const AResult: TQueryResult): string;
var
  mWidths: TArray<Integer>;
  mBuilder: TStringBuilder;
  mRow: TQueryRow;
  mIndex: Integer;
  mCell: string;
begin
  if AResult.Failed then
  begin
    Exit(ErrorText(AResult));
  end;
  SetLength(mWidths, Length(AResult.Columns));
  for mIndex := 0 to High(AResult.Columns) do
  begin
    mWidths[mIndex] := Length(AResult.Columns[mIndex]);
  end;
  for mRow in AResult.Rows do
  begin
    for mIndex := 0 to High(AResult.Columns) do
    begin
      if Length(TQueryResult.CellText(mRow, mIndex)) > mWidths[mIndex] then
      begin
        mWidths[mIndex] := Length(TQueryResult.CellText(mRow, mIndex));
      end;
    end;
  end;
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 0 to High(AResult.Columns) do
    begin
      mBuilder.Append(AResult.Columns[mIndex].PadRight(mWidths[mIndex] + 2));
    end;
    mBuilder.Append('path').Append(sLineBreak);
    for mRow in AResult.Rows do
    begin
      for mIndex := 0 to High(AResult.Columns) do
      begin
        mCell := TQueryResult.CellText(mRow, mIndex);
        mBuilder.Append(mCell.PadRight(mWidths[mIndex] + 2));
      end;
      mBuilder.Append(mRow.Path);
      if mRow.Inferred then
      begin
        mBuilder.Append(cTexts[TOutputText.Inferred3].Text);
      end;
      mBuilder.Append(sLineBreak);
    end;
    mBuilder.Append(Summary(AResult)).Append(sLineBreak);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function JsonStrings(const AItems: TArray<string>): string;
var
  mIndex: Integer;
begin
  Result := '[';
  for mIndex := 0 to High(AItems) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ', ';
    end;
    Result := Result + TMetricsReport.JsonString(AItems[mIndex]);
  end;
  Result := Result + ']';
end;

function JsonFlag(AValue: Boolean): string;
begin
  if AValue then
  begin
    Result := 'true';
  end
  else
  begin
    Result := 'false';
  end;
end;

procedure AppendCatalogFields(ABuilder: TStringBuilder; AEntity: TQueryEntity);
var
  mField: TQueryFieldInfo;
  mFirst: Boolean;
begin
  ABuilder.Append('[');
  mFirst := True;
  for mField in TQueryCatalog.FieldsOf(AEntity) do
  begin
    if not mFirst then
    begin
      ABuilder.Append(', ');
    end;
    mFirst := False;
    ABuilder.Append('{"name": ').Append(TMetricsReport.JsonString(mField.Name))
      .Append(', "type": ').Append(TMetricsReport.JsonString(TQueryCatalog.FieldTypeName(mField.FieldType)))
      .Append(', "description": ').Append(TMetricsReport.JsonString(mField.Description)).Append('}');
  end;
  ABuilder.Append(']');
end;

procedure AppendCatalogPredicates(ABuilder: TStringBuilder; AEntity: TQueryEntity);
var
  mKind: TQueryPredicateKind;
  mFirst: Boolean;
begin
  ABuilder.Append('[');
  mFirst := True;
  for mKind := Low(TQueryPredicateKind) to High(TQueryPredicateKind) do
  begin
    if not (AEntity in TQueryCatalog.PredicateEntities(mKind)) then
    begin
      Continue;
    end;
    if not mFirst then
    begin
      ABuilder.Append(', ');
    end;
    mFirst := False;
    ABuilder.Append('{"name": ').Append(TMetricsReport.JsonString(TQueryCatalog.PredicateName(mKind)))
      .Append(', "description": ').Append(TMetricsReport.JsonString(TQueryCatalog.PredicateDescription(mKind)))
      .Append('}');
  end;
  ABuilder.Append(']');
end;

procedure AppendCatalogQueries(ABuilder: TStringBuilder; const AQueries: TArray<TSavedQuery>);
var
  mIndex: Integer;
begin
  ABuilder.Append('[');
  for mIndex := 0 to High(AQueries) do
  begin
    if mIndex > 0 then
    begin
      ABuilder.Append(', ');
    end;
    ABuilder.Append('{"name": ').Append(TMetricsReport.JsonString(AQueries[mIndex].Name))
      .Append(', "query": ').Append(TMetricsReport.JsonString(AQueries[mIndex].Query))
      .Append(', "description": ').Append(TMetricsReport.JsonString(AQueries[mIndex].Description))
      .Append(', "failIfAny": ').Append(JsonFlag(AQueries[mIndex].FailIfAny)).Append('}');
  end;
  ABuilder.Append(']');
end;

class function TQueryOutput.CatalogJson(const AQueries: TArray<TSavedQuery>): string;
var
  mBuilder: TStringBuilder;
  mEntity: TQueryEntity;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('{"entities": [');
    for mEntity := Low(TQueryEntity) to High(TQueryEntity) do
    begin
      if mEntity <> Low(TQueryEntity) then
      begin
        mBuilder.Append(', ');
      end;
      mBuilder.Append('{"name": ').Append(TMetricsReport.JsonString(TQueryCatalog.EntityName(mEntity)))
        .Append(', "caption": ').Append(TMetricsReport.JsonString(TQueryCatalog.EntityCaption(mEntity)))
        .Append(', "fields": ');
      AppendCatalogFields(mBuilder, mEntity);
      mBuilder.Append(', "predicates": ');
      AppendCatalogPredicates(mBuilder, mEntity);
      mBuilder.Append('}');
    end;
    mBuilder.Append('], "keywords": ').Append(JsonStrings(TQueryCatalog.Keywords)).Append(', "queries": ');
    AppendCatalogQueries(mBuilder, AQueries);
    mBuilder.Append('}');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Query.Output', cTexts);

end.
