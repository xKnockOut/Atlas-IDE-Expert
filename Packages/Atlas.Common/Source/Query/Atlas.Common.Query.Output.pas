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
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Query.Catalog;

function MarkdownCell(const AText: string): string;
begin
  Result := StringReplace(StringReplace(AText, '|', '\|', [rfReplaceAll]), sLineBreak, ' ', [rfReplaceAll]);
end;

function CsvCell(const AText: string): string;
begin
  if (Pos(';', AText) > 0) or (Pos('"', AText) > 0) or (Pos(#10, AText) > 0) or (Pos(#13, AText) > 0) then
    Result := '"' + StringReplace(AText, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := AText;
end;

function Summary(const AResult: TQueryResult): string;
begin
  if AResult.Truncated then
    Result := Format('%d von %d Treffern', [Length(AResult.Rows), AResult.Total])
  else if AResult.Total = 1 then
    Result := '1 Treffer'
  else
    Result := Format('%d Treffer', [AResult.Total]);
  if AResult.InferredCount > 0 then
    Result := Result + Format(', %d davon erschlossen', [AResult.InferredCount]);
  Result := Result + Format(' in %d ms', [AResult.ElapsedMs]);
end;

{ TQueryOutput }

class function TQueryOutput.TryParseFormat(const AText: string; AFallback: TQueryOutputFormat;
  out AFormat: TQueryOutputFormat): Boolean;
begin
  Result := True;
  if AText = '' then
    AFormat := AFallback
  else if SameText(AText, 'markdown') then
    AFormat := TQueryOutputFormat.Markdown
  else if SameText(AText, 'json') then
    AFormat := TQueryOutputFormat.Json
  else if SameText(AText, 'csv') then
    AFormat := TQueryOutputFormat.Csv
  else if SameText(AText, 'text') then
    AFormat := TQueryOutputFormat.Text
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
    Result := Format('Spalte %d: %s', [AResult.ErrorColumn, AResult.Error]) + sLineBreak + '  ' + AResult.Query +
      sLineBreak + '  ' + StringOfChar(' ', AResult.ErrorColumn - 1) + '^'
  else
    Result := AResult.Error;
  if (AResult.Suggestion <> '') and not ContainsText(AResult.Error, '`' + AResult.Suggestion + '`') then
    Result := Result + sLineBreak + Format('Vorschlag: %s', [AResult.Suggestion]);
end;

class function TQueryOutput.Markdown(const AResult: TQueryResult): string;
var
  mBuilder: TStringBuilder;
  mRow: TQueryRow;
  mIndex: Integer;
  mFirst: string;
begin
  if AResult.Failed then
    Exit('```' + sLineBreak + ErrorText(AResult) + sLineBreak + '```');
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('`').Append(AResult.Query).Append('`: ').Append(Summary(AResult)).Append(sLineBreak);
    if Length(AResult.Rows) = 0 then
      Exit(mBuilder.ToString);
    mBuilder.Append(sLineBreak).Append('|');
    for mIndex := 0 to High(AResult.Columns) do
      mBuilder.Append(' ').Append(AResult.Columns[mIndex]).Append(' |');
    mBuilder.Append(' Datei |').Append(sLineBreak).Append('|');
    for mIndex := 0 to High(AResult.Columns) + 1 do
      mBuilder.Append('---|');
    mBuilder.Append(sLineBreak);
    for mRow in AResult.Rows do
    begin
      mBuilder.Append('|');
      for mIndex := 0 to High(AResult.Columns) do
      begin
        mFirst := MarkdownCell(TQueryResult.CellText(mRow, mIndex));
        if (mIndex = 0) and mRow.Inferred then
          mFirst := mFirst + ' (erschlossen)';
        mBuilder.Append(' ').Append(mFirst).Append(' |');
      end;
      if AResult.Entity <> 'units' then
        mBuilder.Append(' ').Append(MarkdownCell(mRow.Path)).Append(':').Append(mRow.Range.StartPos.Line + 1)
          .Append(' |')
      else
        mBuilder.Append(' ').Append(MarkdownCell(mRow.Path)).Append(' |');
      mBuilder.Append(sLineBreak);
    end;
    if AResult.Truncated then
      mBuilder.Append(sLineBreak).Append(Format('Weitere %d Treffer nicht gezeigt (limit).',
        [AResult.Total - Length(AResult.Rows)])).Append(sLineBreak);
    for mRow in AResult.Rows do
      if mRow.Inferred then
      begin
        mBuilder.Append(sLineBreak).Append('Erschlossen heißt: Ein Aufruf zählt mit, den die Namensauflösung nicht ' +
          'sicher zuordnet (Interface, virtuelle Methode, Überladung; siehe get_call_hierarchy).').Append(sLineBreak);
        Break;
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
        Result := 'true'
      else
        Result := 'false';
  else
    Result := 'null';
  end;
end;

class function TQueryOutput.Json(const AResult: TQueryResult): string;
var
  mBuilder: TStringBuilder;
  mRow: TQueryRow;
  mIndex, mColumn: Integer;
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
    mBuilder.Append(', "entity": ').Append(TMetricsReport.JsonString(AResult.Entity)).Append(', "columns": [');
    for mIndex := 0 to High(AResult.Columns) do
    begin
      if mIndex > 0 then
        mBuilder.Append(', ');
      mBuilder.Append(TMetricsReport.JsonString(AResult.Columns[mIndex]));
    end;
    mBuilder.Append('], "total": ').Append(AResult.Total).Append(', "truncated": ')
      .Append(LowerCase(BoolToStr(AResult.Truncated, True))).Append(', "inferred": ').Append(AResult.InferredCount)
      .Append(', "elapsedMs": ').Append(AResult.ElapsedMs).Append(', "rows": [');
    for mIndex := 0 to High(AResult.Rows) do
    begin
      mRow := AResult.Rows[mIndex];
      if mIndex > 0 then
        mBuilder.Append(', ');
      mBuilder.Append('{"name": ').Append(TMetricsReport.JsonString(mRow.Name))
        .Append(', "container": ').Append(TMetricsReport.JsonString(mRow.Container))
        .Append(', "unit": ').Append(TMetricsReport.JsonString(mRow.UnitName))
        .Append(', "path": ').Append(TMetricsReport.JsonString(mRow.Path))
        .Append(', "file": ').Append(TMetricsReport.JsonString(mRow.FileName))
        .Append(', "line": ').Append(mRow.Range.StartPos.Line + 1)
        .Append(', "character": ').Append(mRow.Range.StartPos.Character + 1)
        .Append(', "inferred": ').Append(LowerCase(BoolToStr(mRow.Inferred, True)));
      if mRow.Inferred then
        mBuilder.Append(', "inferredDetail": ').Append(TMetricsReport.JsonString(mRow.InferredDetail));
      mBuilder.Append(', "values": {');
      for mColumn := 0 to High(AResult.Columns) do
      begin
        if mColumn > 0 then
          mBuilder.Append(', ');
        mBuilder.Append(TMetricsReport.JsonString(AResult.Columns[mColumn])).Append(': ');
        if mColumn <= High(mRow.Values) then
          mBuilder.Append(JsonValue(mRow.Values[mColumn]))
        else
          mBuilder.Append('null');
      end;
      mBuilder.Append('}}');
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
    Exit(ErrorText(AResult));
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 0 to High(AResult.Columns) do
      mBuilder.Append(CsvCell(AResult.Columns[mIndex])).Append(';');
    mBuilder.Append('path;inferred').Append(sLineBreak);
    for mRow in AResult.Rows do
    begin
      for mIndex := 0 to High(AResult.Columns) do
        mBuilder.Append(CsvCell(TQueryResult.CellText(mRow, mIndex))).Append(';');
      mBuilder.Append(CsvCell(mRow.Path)).Append(';');
      if mRow.Inferred then
        mBuilder.Append('erschlossen');
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
    Exit(ErrorText(AResult));
  SetLength(mWidths, Length(AResult.Columns));
  for mIndex := 0 to High(AResult.Columns) do
    mWidths[mIndex] := Length(AResult.Columns[mIndex]);
  for mRow in AResult.Rows do
    for mIndex := 0 to High(AResult.Columns) do
      if Length(TQueryResult.CellText(mRow, mIndex)) > mWidths[mIndex] then
        mWidths[mIndex] := Length(TQueryResult.CellText(mRow, mIndex));
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 0 to High(AResult.Columns) do
      mBuilder.Append(AResult.Columns[mIndex].PadRight(mWidths[mIndex] + 2));
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
        mBuilder.Append('  (erschlossen)');
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
      Result := Result + ', ';
    Result := Result + TMetricsReport.JsonString(AItems[mIndex]);
  end;
  Result := Result + ']';
end;

function JsonFlag(AValue: Boolean): string;
begin
  if AValue then
    Result := 'true'
  else
    Result := 'false';
end;

class function TQueryOutput.CatalogJson(const AQueries: TArray<TSavedQuery>): string;
var
  mBuilder: TStringBuilder;
  mEntity: TQueryEntity;
  mField: TQueryFieldInfo;
  mKind: TQueryPredicateKind;
  mFirst: Boolean;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('{"entities": [');
    for mEntity := Low(TQueryEntity) to High(TQueryEntity) do
    begin
      if mEntity <> Low(TQueryEntity) then
        mBuilder.Append(', ');
      mBuilder.Append('{"name": ').Append(TMetricsReport.JsonString(TQueryCatalog.EntityName(mEntity)))
        .Append(', "caption": ').Append(TMetricsReport.JsonString(TQueryCatalog.EntityCaption(mEntity)))
        .Append(', "fields": [');
      mFirst := True;
      for mField in TQueryCatalog.FieldsOf(mEntity) do
      begin
        if not mFirst then
          mBuilder.Append(', ');
        mFirst := False;
        mBuilder.Append('{"name": ').Append(TMetricsReport.JsonString(mField.Name))
          .Append(', "type": ').Append(TMetricsReport.JsonString(TQueryCatalog.FieldTypeName(mField.FieldType)))
          .Append(', "description": ').Append(TMetricsReport.JsonString(mField.Description)).Append('}');
      end;
      mBuilder.Append('], "predicates": [');
      mFirst := True;
      for mKind := Low(TQueryPredicateKind) to High(TQueryPredicateKind) do
        if mEntity in TQueryCatalog.PredicateEntities(mKind) then
        begin
          if not mFirst then
            mBuilder.Append(', ');
          mFirst := False;
          mBuilder.Append('{"name": ').Append(TMetricsReport.JsonString(TQueryCatalog.PredicateName(mKind)))
            .Append(', "description": ').Append(TMetricsReport.JsonString(TQueryCatalog.PredicateDescription(mKind)))
            .Append('}');
        end;
      mBuilder.Append(']}');
    end;
    mBuilder.Append('], "keywords": ').Append(JsonStrings(TQueryCatalog.Keywords)).Append(', "queries": [');
    for mIndex := 0 to High(AQueries) do
    begin
      if mIndex > 0 then
        mBuilder.Append(', ');
      mBuilder.Append('{"name": ').Append(TMetricsReport.JsonString(AQueries[mIndex].Name))
        .Append(', "query": ').Append(TMetricsReport.JsonString(AQueries[mIndex].Query))
        .Append(', "description": ').Append(TMetricsReport.JsonString(AQueries[mIndex].Description))
        .Append(', "failIfAny": ').Append(JsonFlag(AQueries[mIndex].FailIfAny)).Append('}');
    end;
    mBuilder.Append(']}');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
