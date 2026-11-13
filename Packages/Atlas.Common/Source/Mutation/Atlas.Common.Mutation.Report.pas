unit Atlas.Common.Mutation.Report;

// Mutanten einer Unit (#1460) als Markdown, JSON oder Patch für die
// Kommandozeile (--mutate) und das MCP-Werkzeug get_mutants. Beide liefern
// dieselben Mutanten (Atlas.Common.Mutation.Generator).
//
// JSON (Format 1, Zeilen und Spalten ab 1, Offsets ab 0):
//   {"format": 1, "file": "Source/Preise.pas", "count": 2,
//    "operators": {"boundary": 1, "statement": 1},
//    "mutants": [{"id": 1, "operator": "boundary", "routine": "Satz",
//      "line": 7, "character": 15, "endLine": 7, "endCharacter": 17,
//      "startOffset": 120, "endOffset": 122, "original": ">=",
//      "replacement": ">", "description": "\">=\" durch \">\" ersetzt"}]}
// Patch: je Mutant eine Kopfzeile "# Mutant <id> (<operator>, <routine>):
// <Beschreibung>" und ein vereinigter Diff (--- a/<Datei>, +++ b/<Datei>,
// drei Zeilen Umgebung), anwendbar mit git apply bzw. patch -p1, wenn man
// ihn an der Kopfzeile auftrennt.

interface

uses
  Atlas.Common.Mutation.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Ausgabeform: Markdown-Tabelle, JSON oder Patch.</summary>
  TMutationOutputFormat = (Markdown, Json, Patch);
{$SCOPEDENUMS OFF}

  TMutationReport = class
  public const
    cFormat = 1;
    /// <summary>Zeilen Umgebung im Patch.</summary>
    cContextLines = 3;
  public
    /// <summary>Kurzbeschreibung des Mutanten in der aktuellen Sprache: '"&gt;=" durch "&gt;" ersetzt'.</summary>
    class function Describe(const AMutant: TMutant): string; static;
    class function MutantJson(const AMutant: TMutant): string; static;
    /// <summary>Vollständige Daten (siehe Kopf der Unit); APath erscheint als "file".</summary>
    class function Json(const APath: string; const AMutants: TArray<TMutant>): string; static;
    /// <summary>Tabelle der Mutanten als Markdown mit Zahl je Operator.</summary>
    class function Markdown(const APath: string; const AMutants: TArray<TMutant>): string; static;
    /// <summary>Je Mutant ein vereinigter Diff gegen AText (siehe Kopf der Unit).</summary>
    class function Patch(const APath, AText: string; const AMutants: TArray<TMutant>): string; static;
    /// <summary>Format aus "markdown" bzw. "text", "json" oder "diff" bzw. "patch" (Groß-/Kleinschreibung egal);
    /// '' = Markdown. False bei anderen Werten.</summary>
    class function TryParseFormat(const AText: string; out AFormat: TMutationOutputFormat): Boolean; static;
    /// <summary>Mutanten von AText (Pfad APath für die Ausgabe) unter AOptions in der Form AFormat.</summary>
    class function Render(const APath, AText: string; const AOptions: TMutationOptions;
      AFormat: TMutationOutputFormat): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Text.Diff,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Mutation.Generator,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TMutationReportText = (Title, Count, TableHead, NoMutants, Replaced, Removed);

const
  cTexts: array[TMutationReportText] of TAtlasText = (
    (De: 'Mutanten in %s'; En: 'Mutants in %s'),
    (De: 'Mutanten: %d (%s)'; En: 'Mutants: %d (%s)'),
    (De: '| Nr. | Zeile | Routine | Operator | Veränderung |'; En: '| No. | Line | Routine | Operator | Change |'),
    (De: 'Keine Mutanten: keine Routine mit Rumpf oder alles ausgenommen.';
     En: 'No mutants: no routine with a body, or everything excluded.'),
    (De: '"%s" durch "%s" ersetzt'; En: 'replaced "%s" with "%s"'),
    (De: '"%s" entfernt'; En: 'removed "%s"'));

{$SCOPEDENUMS OFF}

const
  cLineBreak = #13#10;
  /// <summary>Längster Originaltext in Describe; längere werden gekürzt.</summary>
  cMaxDescribed = 60;

function JsonText(const AText: string): string;
begin
  Result := TMetricsReport.JsonString(AText);
end;

function Cell(const AText: string): string;
begin
  Result := StringReplace(AText, '|', '\|', [rfReplaceAll]);
end;

/// <summary>Anzahl je Operator in der Reihenfolge der Aufzählung; nur Operatoren mit Mutanten.</summary>
function Counts(const AMutants: TArray<TMutant>): TArray<TPair<string, Integer>>;
var
  mCounts: array[TMutationOperator] of Integer;
  mOperator: TMutationOperator;
  mMutant: TMutant;
begin
  for mOperator := Low(TMutationOperator) to High(TMutationOperator) do
  begin
    mCounts[mOperator] := 0;
  end;
  for mMutant in AMutants do
  begin
    Inc(mCounts[mMutant.Operator]);
  end;
  Result := nil;
  for mOperator := Low(TMutationOperator) to High(TMutationOperator) do
  begin
    if mCounts[mOperator] > 0 then
    begin
      Result := Result + [TPair<string, Integer>.Create(TMutation.OperatorId(mOperator), mCounts[mOperator])];
    end;
  end;
end;

{ TMutationReport }

/// <summary>Text in einer Zeile, höchstens cMaxDescribed Zeichen.</summary>
function Short(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := AText;
  for mIndex := 1 to Length(Result) do
  begin
    if CharInSet(Result[mIndex], [#9, #10, #13]) then
    begin
      Result[mIndex] := ' ';
    end;
  end;
  while Pos('  ', Result) > 0 do
  begin
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  end;
  if Length(Result) > cMaxDescribed then
  begin
    Result := Copy(Result, 1, cMaxDescribed - 1) + '…';
  end;
end;

class function TMutationReport.Describe(const AMutant: TMutant): string;
begin
  if AMutant.Replacement = '' then
  begin
    Result := cTexts[TMutationReportText.Removed].Fmt([Short(AMutant.Original)]);
  end
  else
  begin
    Result := cTexts[TMutationReportText.Replaced].Fmt([Short(AMutant.Original), Short(AMutant.Replacement)]);
  end;
end;


class function TMutationReport.MutantJson(const AMutant: TMutant): string;
begin
  Result := Format('{"id": %d, "operator": %s, "routine": %s, "line": %d, "character": %d, "endLine": %d, ' +
    '"endCharacter": %d, "startOffset": %d, "endOffset": %d, "original": %s, "replacement": %s, ' +
    '"description": %s}', [AMutant.Id, JsonText(TMutation.OperatorId(AMutant.Operator)), JsonText(AMutant.Routine),
    AMutant.Range.StartPos.Line + 1, AMutant.Range.StartPos.Character + 1, AMutant.Range.EndPos.Line + 1,
    AMutant.Range.EndPos.Character + 1, AMutant.StartOffset, AMutant.EndOffset, JsonText(AMutant.Original),
    JsonText(AMutant.Replacement), JsonText(Describe(AMutant))]);
end;

class function TMutationReport.Json(const APath: string; const AMutants: TArray<TMutant>): string;
var
  mBuilder: TStringBuilder;
  mPair: TPair<string, Integer>;
  mFirst: Boolean;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('{"format": ').Append(cFormat).Append(', "file": ').Append(JsonText(APath))
      .Append(', "count": ').Append(Length(AMutants)).Append(', "operators": {');
    mFirst := True;
    for mPair in Counts(AMutants) do
    begin
      if not mFirst then
      begin
        mBuilder.Append(', ');
      end;
      mFirst := False;
      mBuilder.Append(JsonText(mPair.Key)).Append(': ').Append(mPair.Value);
    end;
    mBuilder.Append('}, "mutants": [');
    for mIndex := 0 to High(AMutants) do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(', ');
      end;
      mBuilder.Append(MutantJson(AMutants[mIndex]));
    end;
    mBuilder.Append(']}');
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>"boundary 2, statement 1".</summary>
function CountsText(const AMutants: TArray<TMutant>): string;
var
  mPair: TPair<string, Integer>;
begin
  Result := '';
  for mPair in Counts(AMutants) do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + mPair.Key + ' ' + IntToStr(mPair.Value);
  end;
end;

class function TMutationReport.Markdown(const APath: string; const AMutants: TArray<TMutant>): string;
var
  mBuilder: TStringBuilder;
  mMutant: TMutant;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('# ').Append(cTexts[TMutationReportText.Title].Fmt([APath])).Append(cLineBreak)
      .Append(cLineBreak);
    if Length(AMutants) = 0 then
    begin
      mBuilder.Append(cTexts[TMutationReportText.NoMutants].Text).Append(cLineBreak);
      Exit(mBuilder.ToString);
    end;
    mBuilder.Append(cTexts[TMutationReportText.Count].Fmt([Length(AMutants), CountsText(AMutants)]))
      .Append(cLineBreak).Append(cLineBreak).Append(cTexts[TMutationReportText.TableHead].Text).Append(cLineBreak)
      .Append('| ---: | ---: | --- | --- | --- |').Append(cLineBreak);
    for mMutant in AMutants do
    begin
      mBuilder.Append('| ').Append(mMutant.Id).Append(' | ').Append(mMutant.Range.StartPos.Line + 1).Append(' | ')
        .Append(Cell(mMutant.Routine)).Append(' | ').Append(TMutation.OperatorId(mMutant.Operator)).Append(' | ')
        .Append(Cell(Describe(mMutant))).Append(' |').Append(cLineBreak);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TMutationReport.Patch(const APath, AText: string; const AMutants: TArray<TMutant>): string;
var
  mBuilder: TStringBuilder;
  mMutant: TMutant;
  mOld, mDiff: TArray<string>;
  mLine, mPath: string;
begin
  mPath := StringReplace(APath, '\', '/', [rfReplaceAll]);
  mOld := TTextLines.SplitLines(AText);
  mBuilder := TStringBuilder.Create;
  try
    for mMutant in AMutants do
    begin
      mDiff := TTextDiff.Unified('a/' + mPath, 'b/' + mPath, mOld,
        TTextLines.SplitLines(TMutation.Apply(AText, mMutant)), cContextLines);
      mBuilder.Append('# Mutant ').Append(mMutant.Id).Append(' (').Append(TMutation.OperatorId(mMutant.Operator))
        .Append(', ').Append(mMutant.Routine).Append('): ').Append(Describe(mMutant)).Append(cLineBreak);
      for mLine in mDiff do
      begin
        mBuilder.Append(mLine).Append(cLineBreak);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TMutationReport.TryParseFormat(const AText: string; out AFormat: TMutationOutputFormat): Boolean;
var
  mText: string;
begin
  mText := LowerCase(Trim(AText));
  Result := True;
  if (mText = '') or (mText = 'markdown') or (mText = 'text') then
  begin
    AFormat := TMutationOutputFormat.Markdown;
  end
  else if mText = 'json' then
  begin
    AFormat := TMutationOutputFormat.Json;
  end
  else if (mText = 'diff') or (mText = 'patch') then
  begin
    AFormat := TMutationOutputFormat.Patch;
  end
  else
  begin
    AFormat := TMutationOutputFormat.Markdown;
    Result := False;
  end;
end;

class function TMutationReport.Render(const APath, AText: string; const AOptions: TMutationOptions;
  AFormat: TMutationOutputFormat): string;
var
  mMutants: TArray<TMutant>;
begin
  mMutants := TMutationGenerator.ForText(AText, AOptions);
  case AFormat of
    TMutationOutputFormat.Json:
      Result := Json(APath, mMutants);
    TMutationOutputFormat.Patch:
      Result := Patch(APath, AText, mMutants);
  else
    Result := Markdown(APath, mMutants);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mutation.Report', cTexts);

end.
