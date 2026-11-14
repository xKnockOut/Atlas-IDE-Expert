unit Atlas.Common.Lsp.LearnedSuggestions;

// Gelernte Vorschläge (#1890) über das Protokoll. Das Plugin schickt vorher
// den Puffer.
//   - atlas.server.suggestNext [uri, line, editorOptions, options]: Vorschlag
//     für die leere Zeile line (0-basiert) nach einem Auslöser. editorOptions
//     sind die FormattingOptions des Editors ({tabSize, insertSpaces}) oder
//     null; options {"minCount", "minShare", "adjust": {Kennung: Punkte}} aus
//     den Einstellungen und Lernzählern des Plugins. Antwort {"id", "trigger",
//     "lines", "cursor", "count", "total", "share", "team", "evidence":
//     [{"uri", "line"}]} oder null.
//   - atlas.server.learnedPatterns [uri]: alle Muster aus atlas.json und aus
//     dem Projekt ab zwei Stellen für die Liste „Gelernte Vorschläge“, je
//     {"id", "trigger", "text", "count", "total", "share", "team",
//     "evidence"}.
// Die Logik liegt in Atlas.Common.Editing.LearnedSuggestions.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.LearnedSuggestions;

type
  /// <summary>Einrückung und Muster aus atlas.json für AUri mit den Editor-Optionen AEditorOptions (nil = keine).
  /// </summary>
  TLearnedOptionsFunc = reference to function(const AUri: string; const AEditorOptions: TJSONValue):
    TLearnedOptions;

  TLspLearnedSuggestions = class
  public const
    cSuggestCommand = 'atlas.server.suggestNext';
    cListCommand = 'atlas.server.learnedPatterns';
  public
    /// <summary>Schwellen und Lernzähler aus AValue ({"minCount", "minShare", "adjust"}) in AOptions.</summary>
    class procedure ReadOptions(const AValue: TJSONValue; var AOptions: TLearnedOptions); static;
    /// <summary>atlas.server.suggestNext; ungültige Argumente ergeben EArgumentException.</summary>
    class function ExecuteSuggest(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AOptionsFor: TLearnedOptionsFunc; const AArguments: TJSONArray): TJSONValue; static;
    /// <summary>atlas.server.learnedPatterns.</summary>
    class function ExecuteList(const AIndex: ISymbolIndex; const AOptionsFor: TLearnedOptionsFunc;
      const AArguments: TJSONArray): TJSONValue; static;
  end;

implementation

uses
  System.Math,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLearnedSuggestionsText = (ArgumentsUriAndLineMissing);

const
  cTexts: array[TLearnedSuggestionsText] of TAtlasText = (
    (De: 'Argumente "uri" und "line" fehlen'; En: 'Arguments "uri" and "line" missing'));

{$SCOPEDENUMS OFF}

const
  /// <summary>Grenzen der Schwellen wie in den Einstellungen des Plugins.</summary>
  cMinCountLow = 2;
  cMinCountHigh = 100;
  cMinShareLow = 50;
  cMinShareHigh = 100;

class procedure TLspLearnedSuggestions.ReadOptions(const AValue: TJSONValue; var AOptions: TLearnedOptions);
var
  mObject, mAdjust: TJSONObject;
  mPair: TJSONPair;
  mNumber: TJSONValue;
begin
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mObject := TJSONObject(AValue);
  mNumber := mObject.GetValue('minCount');
  if mNumber is TJSONNumber then
  begin
    AOptions.MinCount := EnsureRange(TJSONNumber(mNumber).AsInt, cMinCountLow, cMinCountHigh);
  end;
  mNumber := mObject.GetValue('minShare');
  if mNumber is TJSONNumber then
  begin
    AOptions.MinShare := EnsureRange(TJSONNumber(mNumber).AsInt, cMinShareLow, cMinShareHigh);
  end;
  if mObject.GetValue('adjust') is TJSONObject then
  begin
    mAdjust := TJSONObject(mObject.GetValue('adjust'));
    for mPair in mAdjust do
    begin
      if mPair.JsonValue is TJSONNumber then
      begin
        AOptions.AdjustIds := AOptions.AdjustIds + [mPair.JsonString.Value];
        AOptions.AdjustBy := AOptions.AdjustBy + [TJSONNumber(mPair.JsonValue).AsInt];
      end;
    end;
  end;
end;

function EvidenceJson(const APattern: TLearnedPattern): TJSONArray;
var
  mEvidence: TLearnedEvidence;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mEvidence in APattern.Evidence do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('uri', TDocumentUris.FromPath(mEvidence.FileName));
    mItem.AddPair('line', TJSONNumber.Create(mEvidence.Line));
    Result.AddElement(mItem);
  end;
end;

/// <summary>Gemeinsame Felder eines Musters.</summary>
procedure AddPattern(AObject: TJSONObject; const APattern: TLearnedPattern);
begin
  AObject.AddPair('id', APattern.Id);
  AObject.AddPair('trigger', APattern.Trigger);
  AObject.AddPair('count', TJSONNumber.Create(APattern.Count));
  AObject.AddPair('total', TJSONNumber.Create(APattern.Total));
  AObject.AddPair('share', TJSONNumber.Create(APattern.Share));
  AObject.AddPair('team', TJSONBool.Create(APattern.Team));
  AObject.AddPair('evidence', EvidenceJson(APattern));
end;

function SuggestionJson(const ASuggestion: TLearnedSuggestion): TJSONObject;
var
  mLines: TJSONArray;
  mLine: string;
  mCursor: TJSONObject;
begin
  Result := TJSONObject.Create;
  AddPattern(Result, ASuggestion.Pattern);
  mLines := TJSONArray.Create;
  for mLine in ASuggestion.Lines do
  begin
    mLines.Add(mLine);
  end;
  Result.AddPair('lines', mLines);
  mCursor := TJSONObject.Create;
  mCursor.AddPair('line', TJSONNumber.Create(ASuggestion.CursorLine));
  mCursor.AddPair('character', TJSONNumber.Create(ASuggestion.CursorCharacter));
  Result.AddPair('cursor', mCursor);
end;

class function TLspLearnedSuggestions.ExecuteSuggest(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AOptionsFor: TLearnedOptionsFunc; const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mLine: Integer;
  mDocument: ITextDocument;
  mEditorOptions: TJSONValue;
  mOptions: TLearnedOptions;
  mShared: ISharedSyntaxTree;
  mSuggestion: TLearnedSuggestion;
  mIndex: ISymbolIndex;
begin
  if (AArguments = nil) or (AArguments.Count < 2) or not (AArguments.Items[1] is TJSONNumber) then
  begin
    raise EArgumentException.Create(cTexts[TLearnedSuggestionsText.ArgumentsUriAndLineMissing].Text);
  end;
  mUri := AArguments.Items[0].Value;
  mLine := TJSONNumber(AArguments.Items[1]).AsInt;
  mEditorOptions := nil;
  if (AArguments.Count > 2) and not (AArguments.Items[2] is TJSONNull) then
  begin
    mEditorOptions := AArguments.Items[2];
  end;
  if (AIndex = nil) or not AStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  mOptions := AOptionsFor(mUri, mEditorOptions);
  if AArguments.Count > 3 then
  begin
    ReadOptions(AArguments.Items[3], mOptions);
  end;
  mIndex := AIndex;
  mShared := TSyntaxTreeCache.Get(mDocument);
  if not TLearnedSuggestions.Suggest(mShared.Tree, mDocument.Text, mLine, TLearnedProject.Create(AIndex.Units,
    function(const AName: string): Boolean
    begin
      Result := Length(mIndex.FindSymbols(AName)) > 0;
    end), mOptions, mSuggestion) then
  begin
    Exit(TJSONNull.Create);
  end;
  Result := SuggestionJson(mSuggestion);
end;

class function TLspLearnedSuggestions.ExecuteList(const AIndex: ISymbolIndex; const AOptionsFor: TLearnedOptionsFunc;
  const AArguments: TJSONArray): TJSONValue;
var
  mUri: string;
  mPattern: TLearnedPattern;
  mItem: TJSONObject;
  mList: TJSONArray;
  mUnits: TArray<TUnitIndex>;
begin
  mUri := '';
  if (AArguments <> nil) and (AArguments.Count > 0) then
  begin
    mUri := AArguments.Items[0].Value;
  end;
  mUnits := nil;
  if AIndex <> nil then
  begin
    mUnits := AIndex.Units;
  end;
  mList := TJSONArray.Create;
  for mPattern in TLearnedSuggestions.List(mUnits, AOptionsFor(mUri, nil)) do
  begin
    mItem := TJSONObject.Create;
    AddPattern(mItem, mPattern);
    mItem.AddPair('text', TLearnedSuggestions.Display(mPattern.Follow));
    mList.AddElement(mItem);
  end;
  Result := mList;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.LearnedSuggestions', cTexts);

end.
