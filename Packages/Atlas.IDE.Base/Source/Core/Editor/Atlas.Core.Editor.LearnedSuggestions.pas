unit Atlas.Core.Editor.LearnedSuggestions;

// Gelernte Vorschläge (#1890), Plugin-Kern ohne VCL und Open Tools API:
// Argumente für atlas.server.suggestNext und atlas.server.learnedPatterns
// bauen, die Antworten lesen und den Schattentext führen.
// - Der Server liefert die Zeilen für die leere Zeile nach dem Auslöser samt
//   Einrückung und die Stelle der Schreibmarke danach (Atlas.Common.Lsp.
//   LearnedSuggestions).
// - Der Editor zeichnet nur eine Zeile: Der Schattentext ist der Block in
//   einer Zeile („try … finally X.Free; end;“), die leere Zeile des Rumpfs
//   als „…“.
// - Tab schreibt den Rest des Blocks, Strg+→ das nächste Wort (TAtlasGhostText).
//   Ist alles geschrieben, steht die Schreibmarke dort, wo der Server sie will.
// - Der Hinweis „gelernt aus N Stellen“ nennt bis zu drei Belege.

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Beleg eines Musters: Datei und Zeile (0-basiert).</summary>
  TAtlasLearnedEvidence = record
    FileName: string;
    Line: Integer;
  end;

  /// <summary>Muster aus atlas.server.suggestNext bzw. atlas.server.learnedPatterns.</summary>
  TAtlasLearnedPattern = record
    Id: string;
    Trigger: string;
    /// <summary>Folge in einer Zeile (nur in der Liste).</summary>
    Text: string;
    Count: Integer;
    Total: Integer;
    Share: Integer;
    /// <summary>Aus suggestions.patterns in atlas.json.</summary>
    Team: Boolean;
    Evidence: TArray<TAtlasLearnedEvidence>;
  end;

  /// <summary>Vorschlag für die leere Zeile Line (0-basiert).</summary>
  TAtlasLearnedSuggestion = record
    Pattern: TAtlasLearnedPattern;
    Line: Integer;
    /// <summary>Zeilen, die die leere Zeile ersetzen, mit Einrückung.</summary>
    Lines: TArray<string>;
    CursorLine: Integer;
    CursorCharacter: Integer;
  end;

  /// <summary>Zuschlag je Muster aus den Lernzählern (Kennung, Punkte).</summary>
  TAtlasLearnedAdjust = record
    Id: string;
    By: Integer;
  end;

  /// <summary>Schattentext eines Blocks, der Stück für Stück geschrieben werden kann.</summary>
  TAtlasGhostText = record
  private
    FText: string;
    FDone: Integer;
  public
    /// <summary>AText: ganzer Block; AWritten: so viele Zeichen stehen schon im Puffer (die Einrückung der
    /// leeren Zeile).</summary>
    class function Create(const AText: string; AWritten: Integer): TAtlasGhostText; static;
    /// <summary>Was noch fehlt.</summary>
    function Rest: string;
    /// <summary>Der Rest in einer Zeile für die Anzeige; leere Zeilen als „…“.</summary>
    function Display: string;
    /// <summary>Das nächste Stück für Strg+→: Leerraum samt Zeilenumbrüchen, dann ein Wort oder eine Folge von
    /// Satzzeichen.</summary>
    function NextWord: string;
    /// <summary>AText ist geschrieben.</summary>
    procedure Advance(const AText: string);
    function Finished: Boolean;
  end;

  TAtlasLearnedSuggestions = class
  public const
    cSuggestCommand = 'atlas.server.suggestNext';
    cListCommand = 'atlas.server.learnedPatterns';
    /// <summary>Beim Tippen: lieber kein Vorschlag als ein später.</summary>
    cTimeoutMs = 1500;
    /// <summary>Für die Liste darf es länger dauern.</summary>
    cListTimeoutMs = 10000;
    /// <summary>Belege im Hinweis.</summary>
    cHintEvidence = 3;
  public
    /// <summary>Argumente für suggestNext als JSON-Text.</summary>
    class function SuggestArguments(const AUri: string; ALine, ATabSize: Integer; AInsertSpaces: Boolean;
      AMinCount, AMinShare: Integer; const AAdjust: TArray<TAtlasLearnedAdjust>): string; static;
    /// <summary>Argumente für learnedPatterns als JSON-Text.</summary>
    class function ListArguments(const AUri: string): string; static;
    /// <summary>Antwort von suggestNext für die Zeile ALine; False bei null oder ungültiger Antwort.</summary>
    class function ReadSuggestion(const AValue: TJSONValue; ALine: Integer;
      out ASuggestion: TAtlasLearnedSuggestion): Boolean; static;
    /// <summary>Antwort von learnedPatterns; ungültige Einträge fallen weg.</summary>
    class function ReadList(const AValue: TJSONValue): TArray<TAtlasLearnedPattern>; static;
    /// <summary>Text, der die leere Zeile ersetzt (Zeilen mit ALineBreak verbunden).</summary>
    class function BlockText(const ASuggestion: TAtlasLearnedSuggestion; const ALineBreak: string): string; static;
    /// <summary>Wie viel von ABlock steht schon in der leeren Zeile ACurrent? Ihr Leerraum, wenn der Block damit
    /// beginnt, sonst 0 (dann ersetzt das erste Schreiben ACurrent).</summary>
    class function Written(const ABlock, ACurrent: string): Integer; static;
    /// <summary>Feld im Statusfeld: „gelernt aus N Stellen“ bzw. „aus atlas.json“.</summary>
    class function StatusText(const APattern: TAtlasLearnedPattern): string; static;
    /// <summary>Hinweis mit Anteil und bis zu drei Belegen (Datei:Zeile, 1-basiert).</summary>
    class function HintText(const APattern: TAtlasLearnedPattern): string; static;
    /// <summary>Beleg als „Datei.pas:12“ (Zeile 1-basiert).</summary>
    class function EvidenceText(const AEvidence: TAtlasLearnedEvidence): string; static;
  end;

implementation

uses
  System.Math,
  Atlas.Text.Chars,
  Atlas.Core.Lsp.Uris,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  TLearnedText = (StatusLearned, StatusTeam, HintShare, HintTeam, HintKeys);

{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TLearnedText] of string = (
    ('gelernt aus %d Stellen', 'Vorschlag aus atlas.json',
      'Folgt im Projekt an %d von %d Stellen (%d %%) auf „%s“.', 'Hausregel aus suggestions.patterns in atlas.json.',
      'Tab übernimmt, Strg+→ wortweise, Esc verwirft. Klick: zu einem Beleg springen.'),
    ('learned from %d places', 'Suggestion from atlas.json',
      'At %d of %d places in the project (%d %%) this follows "%s".', 'House rule from suggestions.patterns in atlas.json.',
      'Tab accepts, Ctrl+→ word by word, Esc discards. Click: jump to an example.'));

function Text(AId: TLearnedText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

{ TAtlasGhostText }

class function TAtlasGhostText.Create(const AText: string; AWritten: Integer): TAtlasGhostText;
begin
  Result.FText := AText;
  Result.FDone := EnsureRange(AWritten, 0, Length(AText));
end;

function TAtlasGhostText.Rest: string;
begin
  Result := Copy(FText, FDone + 1, MaxInt);
end;

function TAtlasGhostText.Display: string;
var
  mLine: string;
  mParts: TArray<string>;
begin
  mParts := nil;
  for mLine in Rest.Split([#13#10, #10]) do
  begin
    if Trim(mLine) = '' then
    begin
      mParts := mParts + ['…'];
    end
    else
    begin
      mParts := mParts + [Trim(mLine)];
    end;
  end;
  // Ein Rest, der mit dem Zeilenumbruch beginnt, zeigt nicht erst ein „…“ für die schon geschriebene Zeile.
  if (Length(mParts) > 1) and (mParts[0] = '…') and (Rest <> '') and CharInSet(Rest[1], [#13, #10]) then
  begin
    Delete(mParts, 0, 1);
  end;
  Result := string.Join(' ', mParts);
end;

function TAtlasGhostText.NextWord: string;
var
  mIndex: Integer;
begin
  mIndex := FDone + 1;
  while (mIndex <= Length(FText)) and CharInSet(FText[mIndex], [' ', #9, #13, #10]) do
  begin
    Inc(mIndex);
  end;
  if (mIndex <= Length(FText)) and TTextChars.IsIdentChar(FText[mIndex]) then
  begin
    while (mIndex <= Length(FText)) and TTextChars.IsIdentChar(FText[mIndex]) do
    begin
      Inc(mIndex);
    end;
  end
  else
  begin
    while (mIndex <= Length(FText)) and not TTextChars.IsIdentChar(FText[mIndex]) and
      not CharInSet(FText[mIndex], [' ', #9, #13, #10]) do
    begin
      Inc(mIndex);
    end;
  end;
  Result := Copy(FText, FDone + 1, mIndex - FDone - 1);
end;

procedure TAtlasGhostText.Advance(const AText: string);
begin
  FDone := Min(FDone + Length(AText), Length(FText));
end;

function TAtlasGhostText.Finished: Boolean;
begin
  Result := FDone >= Length(FText);
end;

{ TAtlasLearnedSuggestions }

class function TAtlasLearnedSuggestions.SuggestArguments(const AUri: string; ALine, ATabSize: Integer;
  AInsertSpaces: Boolean; AMinCount, AMinShare: Integer; const AAdjust: TArray<TAtlasLearnedAdjust>): string;
var
  mValues: TJSONArray;
  mEditor, mOptions, mAdjust: TJSONObject;
  mItem: TAtlasLearnedAdjust;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(AUri);
    mValues.Add(ALine);
    mEditor := TJSONObject.Create;
    mEditor.AddPair('tabSize', TJSONNumber.Create(ATabSize));
    mEditor.AddPair('insertSpaces', TJSONBool.Create(AInsertSpaces));
    mValues.AddElement(mEditor);
    mOptions := TJSONObject.Create;
    mOptions.AddPair('minCount', TJSONNumber.Create(AMinCount));
    mOptions.AddPair('minShare', TJSONNumber.Create(AMinShare));
    mAdjust := TJSONObject.Create;
    for mItem in AAdjust do
    begin
      mAdjust.AddPair(mItem.Id, TJSONNumber.Create(mItem.By));
    end;
    mOptions.AddPair('adjust', mAdjust);
    mValues.AddElement(mOptions);
    Result := mValues.ToJSON([]);
  finally
    mValues.Free;
  end;
end;

class function TAtlasLearnedSuggestions.ListArguments(const AUri: string): string;
var
  mValues: TJSONArray;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(AUri);
    Result := mValues.ToJSON([]);
  finally
    mValues.Free;
  end;
end;

/// <summary>Gemeinsame Felder eines Musters; False ohne Kennung.</summary>
function ReadPattern(const AObject: TJSONObject; out APattern: TAtlasLearnedPattern): Boolean;
var
  mEvidence: TJSONArray;
  mItem: TJSONValue;
  mUri: string;
  mFound: TAtlasLearnedEvidence;
begin
  APattern := Default(TAtlasLearnedPattern);
  Result := AObject.TryGetValue<string>('id', APattern.Id) and (APattern.Id <> '');
  if not Result then
  begin
    Exit;
  end;
  AObject.TryGetValue<string>('trigger', APattern.Trigger);
  AObject.TryGetValue<string>('text', APattern.Text);
  AObject.TryGetValue<Integer>('count', APattern.Count);
  AObject.TryGetValue<Integer>('total', APattern.Total);
  AObject.TryGetValue<Integer>('share', APattern.Share);
  AObject.TryGetValue<Boolean>('team', APattern.Team);
  if AObject.TryGetValue<TJSONArray>('evidence', mEvidence) then
  begin
    for mItem in mEvidence do
    begin
      mFound := Default(TAtlasLearnedEvidence);
      if (mItem is TJSONObject) and mItem.TryGetValue<string>('uri', mUri) and
        mItem.TryGetValue<Integer>('line', mFound.Line) then
      begin
        mFound.FileName := TLspUris.ToPath(mUri);
        APattern.Evidence := APattern.Evidence + [mFound];
      end;
    end;
  end;
end;

class function TAtlasLearnedSuggestions.ReadSuggestion(const AValue: TJSONValue; ALine: Integer;
  out ASuggestion: TAtlasLearnedSuggestion): Boolean;
var
  mLines: TJSONArray;
  mCursor: TJSONObject;
  mItem: TJSONValue;
begin
  ASuggestion := Default(TAtlasLearnedSuggestion);
  ASuggestion.Line := ALine;
  Result := (AValue is TJSONObject) and ReadPattern(TJSONObject(AValue), ASuggestion.Pattern) and
    AValue.TryGetValue<TJSONArray>('lines', mLines) and (mLines.Count > 0) and
    AValue.TryGetValue<TJSONObject>('cursor', mCursor) and
    mCursor.TryGetValue<Integer>('line', ASuggestion.CursorLine) and
    mCursor.TryGetValue<Integer>('character', ASuggestion.CursorCharacter);
  if not Result then
  begin
    Exit;
  end;
  for mItem in mLines do
  begin
    ASuggestion.Lines := ASuggestion.Lines + [mItem.Value];
  end;
  // Die Schreibmarke gehört in den eingefügten Block.
  Result := (ASuggestion.CursorLine >= ALine) and (ASuggestion.CursorLine < ALine + Length(ASuggestion.Lines)) and
    (ASuggestion.CursorCharacter >= 0);
end;

class function TAtlasLearnedSuggestions.ReadList(const AValue: TJSONValue): TArray<TAtlasLearnedPattern>;
var
  mItem: TJSONValue;
  mPattern: TAtlasLearnedPattern;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if (mItem is TJSONObject) and ReadPattern(TJSONObject(mItem), mPattern) then
    begin
      Result := Result + [mPattern];
    end;
  end;
end;

class function TAtlasLearnedSuggestions.BlockText(const ASuggestion: TAtlasLearnedSuggestion;
  const ALineBreak: string): string;
begin
  Result := string.Join(ALineBreak, ASuggestion.Lines);
end;

class function TAtlasLearnedSuggestions.Written(const ABlock, ACurrent: string): Integer;
begin
  Result := 0;
  if (Trim(ACurrent) = '') and ABlock.StartsWith(ACurrent) then
  begin
    Result := Length(ACurrent);
  end;
end;

class function TAtlasLearnedSuggestions.StatusText(const APattern: TAtlasLearnedPattern): string;
begin
  if APattern.Team then
  begin
    Result := Text(TLearnedText.StatusTeam);
  end
  else
  begin
    Result := Format(Text(TLearnedText.StatusLearned), [APattern.Count]);
  end;
end;

class function TAtlasLearnedSuggestions.EvidenceText(const AEvidence: TAtlasLearnedEvidence): string;
begin
  Result := Format('%s:%d', [ExtractFileName(AEvidence.FileName), AEvidence.Line + 1]);
end;

class function TAtlasLearnedSuggestions.HintText(const APattern: TAtlasLearnedPattern): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  if APattern.Team then
  begin
    mLines := [Text(TLearnedText.HintTeam)];
  end
  else
  begin
    mLines := [Format(Text(TLearnedText.HintShare), [APattern.Count, APattern.Total, APattern.Share,
      APattern.Trigger])];
  end;
  for mIndex := 0 to Min(Length(APattern.Evidence), cHintEvidence) - 1 do
  begin
    mLines := mLines + ['  ' + EvidenceText(APattern.Evidence[mIndex])];
  end;
  mLines := mLines + [Text(TLearnedText.HintKeys)];
  Result := string.Join(sLineBreak, mLines);
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Editor.LearnedSuggestions', cTexts[TAtlasLanguage.German],
    cTexts[TAtlasLanguage.English]);

end.
