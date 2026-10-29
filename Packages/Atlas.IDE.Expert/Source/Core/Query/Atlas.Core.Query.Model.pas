unit Atlas.Core.Query.Model;

// Fenster „Atlas-Abfrage“ (#1351), Kern ohne VCL und OTA:
// - TAtlasQueryAnswer.Parse liest die Antwort von atlas/query ({"enabled",
//   "root", "format": "json", "data"} mit den Daten aus TQueryOutput.Json des
//   Servers): Spalten, Zeilen mit Werten, Datei, Zeile und Spalte (1-basiert),
//   Kennzeichen „erschlossen“ (#1119), Gesamtzahl, Laufzeit, Fehler mit Spalte
//   und Vorschlag.
// - Sort sortiert nach einer Spalte (Zahlen als Zahl, Text ohne Groß-/
//   Kleinschreibung, Zeilen ohne Wert zuletzt) und bei Gleichstand eindeutig
//   nach Pfad, Zeile, Spalte und der Reihenfolge des Servers. Csv schreibt wie
//   der Server (Semikolon, Kopfzeile mit path und inferred).
// - TAtlasQueryCatalog liest atlas/queryCatalog: Mengen mit Feldern und
//   Prädikaten, Schlüsselwörter, gespeicherte Abfragen.
// - TAtlasQueryCompletion schlägt an der Schreibmarke Mengen, Felder,
//   Prädikate, Schlüsselwörter und gespeicherte Abfragen (@name) vor.
//   Hinter inherits, implements, calls und has attribute kommen Namen aus der
//   Symbolsuche des Servers (SymbolPredicate, SymbolNames).
// - TAtlasSavedQueries baut den Eintrag für „Als Regel speichern …“: die Liste
//   queries aus atlas.json mit dem neuen bzw. ersetzten Eintrag.
// - TAtlasQueryRequest baut die Parameter von atlas/query und
//   atlas/queryCatalog.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.Contract;

type
  TAtlasQueryCell = record
    Text: string;
    /// <summary>Wert vorhanden (sonst null, etwa die Komplexität einer abstrakten Methode).</summary>
    HasValue: Boolean;
    IsNumber: Boolean;
    Number: Int64;
  end;

  TAtlasQueryRow = record
    Cells: TArray<TAtlasQueryCell>;
    /// <summary>Absoluter Pfad der Deklaration.</summary>
    FileName: string;
    /// <summary>Pfad relativ zum Projekt, wie ihn der Server zeigt.</summary>
    Path: string;
    /// <summary>1-basiert.</summary>
    Line: Integer;
    Character: Integer;
    Inferred: Boolean;
    InferredDetail: string;
    /// <summary>Stelle in der Antwort des Servers (letzte Stufe beim Sortieren).</summary>
    Order: Integer;
  end;

  TAtlasQueryAnswer = record
    Enabled: Boolean;
    Query: string;
    Entity: string;
    Columns: TArray<string>;
    Rows: TArray<TAtlasQueryRow>;
    Total: Integer;
    InferredCount: Integer;
    ElapsedMs: Int64;
    Truncated: Boolean;
    Error: string;
    /// <summary>Spalte des Fehlers in der Abfrage ab 1; 0 ohne.</summary>
    ErrorColumn: Integer;
    Suggestion: string;
    function Failed: Boolean;
    /// <summary>Antwort von atlas/query; False bei ungültigem JSON.</summary>
    class function Parse(const AJson: string; out AAnswer: TAtlasQueryAnswer): Boolean; static;
    /// <summary>Sortiert nach Spalte AColumn; bei Gleichstand nach Pfad, Zeile, Spalte und Reihenfolge des Servers.
    /// </summary>
    procedure Sort(AColumn: Integer; ADescending: Boolean);
    /// <summary>Wie TQueryOutput.Csv des Servers: Semikolon, Kopfzeile mit path und inferred.</summary>
    function Csv: string;
    /// <summary>Spalte AName (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    function ColumnOf(const AName: string): Integer;
  end;

  TAtlasQueryField = record
    Name: string;
    /// <summary>"Zahl", "Text" oder "ja/nein".</summary>
    FieldType: string;
    Description: string;
  end;

  TAtlasQueryEntity = record
    Name: string;
    Caption: string;
    Fields: TArray<TAtlasQueryField>;
    Predicates: TArray<TAtlasQueryField>;
  end;

  TAtlasSavedQuery = record
    Name: string;
    Query: string;
    Description: string;
    FailIfAny: Boolean;
  end;

  TAtlasQueryCatalog = record
    Enabled: Boolean;
    Entities: TArray<TAtlasQueryEntity>;
    Keywords: TArray<string>;
    Saved: TArray<TAtlasSavedQuery>;
    /// <summary>Antwort von atlas/queryCatalog; False bei ungültigem JSON.</summary>
    class function Parse(const AJson: string; out ACatalog: TAtlasQueryCatalog): Boolean; static;
    /// <summary>Menge AName; False ohne.</summary>
    function TryEntity(const AName: string; out AEntity: TAtlasQueryEntity): Boolean;
    /// <summary>Gespeicherte Abfrage AName (ohne @, ohne Groß-/Kleinschreibung); False ohne.</summary>
    function TrySaved(const AName: string; out AQuery: TAtlasSavedQuery): Boolean;
  end;

  TAtlasQuerySuggestion = record
    Text: string;
    Detail: string;
  end;

  TAtlasQueryCompletion = class
  public
    /// <summary>Vorschläge für das Wort an ACursor (0-basiert, Zeichen vor der Schreibmarke) in AText; AStart ist
    /// der Anfang des Worts (0-basiert), das ein Vorschlag ersetzt.</summary>
    class function Suggest(const ACatalog: TAtlasQueryCatalog; const AText: string; ACursor: Integer;
      out AStart: Integer): TArray<TAtlasQuerySuggestion>; static;
    /// <summary>Steht die Schreibmarke im Namen hinter inherits, implements, uses, calls oder has attribute?
    /// APredicate ist dieses Wort (klein), APrefix der bisher getippte Name, AStart sein Anfang (0-basiert).
    /// Die Namen kommen aus der Symbolsuche des Servers, nicht aus dem Katalog.</summary>
    class function SymbolPredicate(const AText: string; ACursor: Integer; out AStart: Integer;
      out APrefix, APredicate: string): Boolean; static;
    /// <summary>Namen aus der Symbolsuche (workspace/symbol), die hinter APredicate passen: inherits Klassen,
    /// Records und Interfaces, implements Interfaces, calls Methoden und Routinen, attribute Klassen auf
    /// „Attribute“. uses braucht Unit-Namen; die liefert die Symbolsuche nicht (leer).</summary>
    class function SymbolNames(const APredicate: string; const ASymbols: TArray<TAtlasSymbol>): TArray<string>;
      static;
  end;

  TAtlasSavedQueries = class
  public
    /// <summary>Gültiger Name einer gespeicherten Abfrage: Buchstaben, Ziffern, "-", "_" und ".".</summary>
    class function ValidName(const AName: string): Boolean; static;
    /// <summary>Neue Liste queries für atlas.json als JSON-Text: AExisting (bisherige Liste als JSON, '' = keine)
    /// mit AQuery; ein Eintrag gleichen Namens wird ersetzt. ASeverity und AMessage nur, wenn nicht leer.
    /// </summary>
    class function WithQuery(const AExisting: string; const AQuery: TAtlasSavedQuery;
      const ASeverity, AMessage: string): string; static;
  end;

  TAtlasQueryRequest = class
  public const
    Method = 'atlas/query';
    CatalogMethod = 'atlas/queryCatalog';
  public
    /// <summary>{"uri", "query", "limit", "format": "json"} für atlas/query.</summary>
    class function Params(const AUri, AQuery: string; ALimit: Integer): string; static;
    /// <summary>{"uri"} für atlas/queryCatalog.</summary>
    class function CatalogParams(const AUri: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Defaults,
  System.Generics.Collections;

function StringOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if (mValue <> nil) and not (mValue is TJSONNull) and not (mValue is TJSONObject) and
    not (mValue is TJSONArray) then
    Result := mValue.Value;
end;

function IntegerOf(AObject: TJSONObject; const AName: string): Int64;
var
  mValue: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
    Result := TJSONNumber(mValue).AsInt64;
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  Result := False;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONBool then
    Result := TJSONBool(mValue).AsBoolean;
end;

function ArrayOf(AObject: TJSONObject; const AName: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONArray then
    Result := TJSONArray(mValue);
end;

function ObjectOf(AObject: TJSONObject; const AName: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONObject then
    Result := TJSONObject(mValue);
end;

function CellOf(AValue: TJSONValue): TAtlasQueryCell;
begin
  Result := Default(TAtlasQueryCell);
  if (AValue = nil) or (AValue is TJSONNull) then
    Exit;
  Result.HasValue := True;
  if AValue is TJSONNumber then
  begin
    Result.IsNumber := True;
    Result.Number := TJSONNumber(AValue).AsInt64;
    Result.Text := IntToStr(Result.Number);
  end
  else if AValue is TJSONBool then
  begin
    if TJSONBool(AValue).AsBoolean then
      Result.Text := 'ja'
    else
      Result.Text := 'nein';
  end
  else
    Result.Text := AValue.Value;
end;

function CsvCell(const AText: string): string;
begin
  if (Pos(';', AText) > 0) or (Pos('"', AText) > 0) or (Pos(#10, AText) > 0) or (Pos(#13, AText) > 0) then
    Result := '"' + StringReplace(AText, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := AText;
end;

{ TAtlasQueryAnswer }

function TAtlasQueryAnswer.Failed: Boolean;
begin
  Result := Error <> '';
end;

function TAtlasQueryAnswer.ColumnOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Columns) do
    if SameText(Columns[mIndex], AName) then
      Exit(mIndex);
  Result := -1;
end;

class function TAtlasQueryAnswer.Parse(const AJson: string; out AAnswer: TAtlasQueryAnswer): Boolean;
var
  mValue: TJSONValue;
  mRoot, mData, mError, mRowObject, mValues: TJSONObject;
  mColumns, mRows: TJSONArray;
  mIndex, mColumn: Integer;
  mRow: TAtlasQueryRow;
begin
  AAnswer := Default(TAtlasQueryAnswer);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
      Exit;
    mRoot := TJSONObject(mValue);
    AAnswer.Enabled := FlagOf(mRoot, 'enabled');
    mData := ObjectOf(mRoot, 'data');
    if mData = nil then
      Exit;
    AAnswer.Query := StringOf(mData, 'query');
    mError := ObjectOf(mData, 'error');
    if mError <> nil then
    begin
      AAnswer.Error := StringOf(mError, 'message');
      AAnswer.ErrorColumn := IntegerOf(mError, 'column');
      AAnswer.Suggestion := StringOf(mError, 'suggestion');
      Exit;
    end;
    AAnswer.Entity := StringOf(mData, 'entity');
    AAnswer.Total := IntegerOf(mData, 'total');
    AAnswer.InferredCount := IntegerOf(mData, 'inferred');
    AAnswer.ElapsedMs := IntegerOf(mData, 'elapsedMs');
    AAnswer.Truncated := FlagOf(mData, 'truncated');
    mColumns := ArrayOf(mData, 'columns');
    if mColumns <> nil then
      for mIndex := 0 to mColumns.Count - 1 do
        AAnswer.Columns := AAnswer.Columns + [mColumns.Items[mIndex].Value];
    mRows := ArrayOf(mData, 'rows');
    if mRows = nil then
      Exit;
    SetLength(AAnswer.Rows, mRows.Count);
    for mIndex := 0 to mRows.Count - 1 do
    begin
      mRow := Default(TAtlasQueryRow);
      mRow.Order := mIndex;
      if mRows.Items[mIndex] is TJSONObject then
      begin
        mRowObject := TJSONObject(mRows.Items[mIndex]);
        mRow.FileName := StringOf(mRowObject, 'file');
        mRow.Path := StringOf(mRowObject, 'path');
        mRow.Line := IntegerOf(mRowObject, 'line');
        mRow.Character := IntegerOf(mRowObject, 'character');
        mRow.Inferred := FlagOf(mRowObject, 'inferred');
        mRow.InferredDetail := StringOf(mRowObject, 'inferredDetail');
        mValues := ObjectOf(mRowObject, 'values');
        SetLength(mRow.Cells, Length(AAnswer.Columns));
        for mColumn := 0 to High(AAnswer.Columns) do
          if mValues <> nil then
            mRow.Cells[mColumn] := CellOf(mValues.GetValue(AAnswer.Columns[mColumn]));
      end;
      AAnswer.Rows[mIndex] := mRow;
    end;
  finally
    mValue.Free;
  end;
end;

procedure TAtlasQueryAnswer.Sort(AColumn: Integer; ADescending: Boolean);
var
  mColumn: Integer;
  mDescending: Boolean;
begin
  mColumn := AColumn;
  mDescending := ADescending;
  TArray.Sort<TAtlasQueryRow>(Rows, TComparer<TAtlasQueryRow>.Construct(
    function(const ALeft, ARight: TAtlasQueryRow): Integer
    var
      mLeft, mRight: TAtlasQueryCell;
    begin
      Result := 0;
      if (mColumn >= 0) and (mColumn <= High(ALeft.Cells)) and (mColumn <= High(ARight.Cells)) then
      begin
        mLeft := ALeft.Cells[mColumn];
        mRight := ARight.Cells[mColumn];
        // Ohne Wert immer zuletzt, auch absteigend.
        if mLeft.HasValue <> mRight.HasValue then
        begin
          if mLeft.HasValue then
            Exit(-1);
          Exit(1);
        end;
        if mLeft.IsNumber and mRight.IsNumber then
        begin
          if mLeft.Number < mRight.Number then
            Result := -1
          else if mLeft.Number > mRight.Number then
            Result := 1;
        end
        else
          Result := CompareText(mLeft.Text, mRight.Text);
        if mDescending then
          Result := -Result;
      end;
      // Eindeutig weitersortieren: TArray.Sort ist nicht stabil.
      if Result = 0 then
        Result := CompareText(ALeft.Path, ARight.Path);
      if Result = 0 then
        Result := ALeft.Line - ARight.Line;
      if Result = 0 then
        Result := ALeft.Character - ARight.Character;
      if Result = 0 then
        Result := ALeft.Order - ARight.Order;
    end));
end;

function TAtlasQueryAnswer.Csv: string;
var
  mBuilder: TStringBuilder;
  mRow: TAtlasQueryRow;
  mIndex: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 0 to High(Columns) do
      mBuilder.Append(CsvCell(Columns[mIndex])).Append(';');
    mBuilder.Append('path;inferred').Append(sLineBreak);
    for mRow in Rows do
    begin
      for mIndex := 0 to High(Columns) do
        if mIndex <= High(mRow.Cells) then
          mBuilder.Append(CsvCell(mRow.Cells[mIndex].Text)).Append(';')
        else
          mBuilder.Append(';');
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

{ TAtlasQueryCatalog }

function FieldsOf(AArray: TJSONArray): TArray<TAtlasQueryField>;
var
  mIndex: Integer;
  mField: TAtlasQueryField;
begin
  Result := nil;
  if AArray = nil then
    Exit;
  for mIndex := 0 to AArray.Count - 1 do
    if AArray.Items[mIndex] is TJSONObject then
    begin
      mField.Name := StringOf(TJSONObject(AArray.Items[mIndex]), 'name');
      mField.FieldType := StringOf(TJSONObject(AArray.Items[mIndex]), 'type');
      mField.Description := StringOf(TJSONObject(AArray.Items[mIndex]), 'description');
      Result := Result + [mField];
    end;
end;

class function TAtlasQueryCatalog.Parse(const AJson: string; out ACatalog: TAtlasQueryCatalog): Boolean;
var
  mValue: TJSONValue;
  mRoot, mCatalog, mItem: TJSONObject;
  mItems: TJSONArray;
  mIndex: Integer;
  mEntity: TAtlasQueryEntity;
  mSaved: TAtlasSavedQuery;
begin
  ACatalog := Default(TAtlasQueryCatalog);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
      Exit;
    mRoot := TJSONObject(mValue);
    ACatalog.Enabled := FlagOf(mRoot, 'enabled');
    mCatalog := ObjectOf(mRoot, 'catalog');
    if mCatalog = nil then
      Exit;
    mItems := ArrayOf(mCatalog, 'entities');
    if mItems <> nil then
      for mIndex := 0 to mItems.Count - 1 do
        if mItems.Items[mIndex] is TJSONObject then
        begin
          mItem := TJSONObject(mItems.Items[mIndex]);
          mEntity.Name := StringOf(mItem, 'name');
          mEntity.Caption := StringOf(mItem, 'caption');
          mEntity.Fields := FieldsOf(ArrayOf(mItem, 'fields'));
          mEntity.Predicates := FieldsOf(ArrayOf(mItem, 'predicates'));
          ACatalog.Entities := ACatalog.Entities + [mEntity];
        end;
    mItems := ArrayOf(mCatalog, 'keywords');
    if mItems <> nil then
      for mIndex := 0 to mItems.Count - 1 do
        ACatalog.Keywords := ACatalog.Keywords + [mItems.Items[mIndex].Value];
    mItems := ArrayOf(mCatalog, 'queries');
    if mItems <> nil then
      for mIndex := 0 to mItems.Count - 1 do
        if mItems.Items[mIndex] is TJSONObject then
        begin
          mItem := TJSONObject(mItems.Items[mIndex]);
          mSaved.Name := StringOf(mItem, 'name');
          mSaved.Query := StringOf(mItem, 'query');
          mSaved.Description := StringOf(mItem, 'description');
          mSaved.FailIfAny := FlagOf(mItem, 'failIfAny');
          ACatalog.Saved := ACatalog.Saved + [mSaved];
        end;
  finally
    mValue.Free;
  end;
end;

function TAtlasQueryCatalog.TryEntity(const AName: string; out AEntity: TAtlasQueryEntity): Boolean;
var
  mEntity: TAtlasQueryEntity;
begin
  for mEntity in Entities do
    if SameText(mEntity.Name, AName) then
    begin
      AEntity := mEntity;
      Exit(True);
    end;
  AEntity := Default(TAtlasQueryEntity);
  Result := False;
end;

function TAtlasQueryCatalog.TrySaved(const AName: string; out AQuery: TAtlasSavedQuery): Boolean;
var
  mSaved: TAtlasSavedQuery;
begin
  for mSaved in Saved do
    if SameText(mSaved.Name, AName) then
    begin
      AQuery := mSaved;
      Exit(True);
    end;
  AQuery := Default(TAtlasSavedQuery);
  Result := False;
end;

{ TAtlasQueryCompletion }

function IsWordChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.', '@', '*', '?']) or (Ord(AChar) > 127);
end;

/// <summary>Wörter vor APosition (ohne Text in Anführungszeichen), in Kleinschreibung; Klammern und Vergleiche als
/// eigene Wörter.</summary>
function WordsBefore(const AText: string; APosition: Integer): TArray<string>;
var
  mIndex, mStart: Integer;
  mChar: Char;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= APosition do
  begin
    mChar := AText[mIndex];
    if CharInSet(mChar, ['''', '"']) then
    begin
      mStart := mIndex;
      Inc(mIndex);
      while (mIndex <= APosition) and (AText[mIndex] <> mChar) do
        Inc(mIndex);
      Result := Result + [Copy(AText, mStart, mIndex - mStart + 1)];
      Inc(mIndex);
    end
    else if IsWordChar(mChar) then
    begin
      mStart := mIndex;
      while (mIndex <= APosition) and IsWordChar(AText[mIndex]) do
        Inc(mIndex);
      Result := Result + [LowerCase(Copy(AText, mStart, mIndex - mStart))];
    end
    else if CharInSet(mChar, ['=', '<', '>', '!']) then
    begin
      mStart := mIndex;
      while (mIndex <= APosition) and CharInSet(AText[mIndex], ['=', '<', '>', '!']) do
        Inc(mIndex);
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
    end
    else
    begin
      if CharInSet(mChar, ['(', ')']) then
        Result := Result + [string(mChar)];
      Inc(mIndex);
    end;
  end;
end;

function Suggestion(const AText, ADetail: string): TAtlasQuerySuggestion;
begin
  Result.Text := AText;
  Result.Detail := ADetail;
end;

function IsComparison(const AWord: string): Boolean;
begin
  Result := (AWord = '=') or (AWord = '<>') or (AWord = '!=') or (AWord = '<') or (AWord = '>') or (AWord = '<=') or
    (AWord = '>=') or (AWord = 'like');
end;

function IsSymbolPredicate(const AWord: string): Boolean;
begin
  Result := (AWord = 'inherits') or (AWord = 'implements') or (AWord = 'uses') or (AWord = 'calls') or
    (AWord = 'attribute');
end;

class function TAtlasQueryCompletion.Suggest(const ACatalog: TAtlasQueryCatalog; const AText: string;
  ACursor: Integer; out AStart: Integer): TArray<TAtlasQuerySuggestion>;
var
  mCursor, mBegin: Integer;
  mPrefix, mLast: string;
  mWords: TArray<string>;
  mEntity: TAtlasQueryEntity;
  mField: TAtlasQueryField;
  mSaved: TAtlasSavedQuery;
  mAll: TArray<TAtlasQuerySuggestion>;
  mItem: TAtlasQuerySuggestion;
  mHasEntity: Boolean;

  procedure Add(const AName, ADetail: string);
  begin
    mAll := mAll + [Suggestion(AName, ADetail)];
  end;

  procedure AddKeywords(const ANames: array of string);
  var
    mName: string;
  begin
    for mName in ANames do
      Add(mName, '');
  end;

begin
  Result := nil;
  mAll := nil;
  mCursor := ACursor;
  if mCursor > Length(AText) then
    mCursor := Length(AText);
  if mCursor < 0 then
    mCursor := 0;
  // Anfang des Worts an der Schreibmarke (1-basiert in mBegin).
  mBegin := mCursor;
  while (mBegin > 0) and IsWordChar(AText[mBegin]) do
    Dec(mBegin);
  AStart := mBegin;
  mPrefix := Copy(AText, mBegin + 1, mCursor - mBegin);
  mWords := WordsBefore(AText, mBegin);
  if Length(mWords) = 0 then
  begin
    // Am Anfang: Mengen und gespeicherte Abfragen.
    for mEntity in ACatalog.Entities do
      Add(mEntity.Name, mEntity.Caption);
    for mSaved in ACatalog.Saved do
      Add('@' + mSaved.Name, mSaved.Description);
  end
  else
  begin
    mHasEntity := ACatalog.TryEntity(mWords[0], mEntity);
    mLast := mWords[High(mWords)];
    if mLast = 'order' then
      AddKeywords(['by'])
    else if (mLast = 'by') and mHasEntity then
    begin
      for mField in mEntity.Fields do
        Add(mField.Name, mField.Description);
    end
    else if (mLast = 'asc') or (mLast = 'desc') then
      AddKeywords(['limit'])
    else if (Length(mWords) = 1) and mHasEntity then
      AddKeywords(['where', 'order', 'limit'])
    else if ((mLast = 'where') or (mLast = 'and') or (mLast = 'or') or (mLast = 'not') or (mLast = '(')) and
      mHasEntity then
    begin
      for mField in mEntity.Fields do
        Add(mField.Name, mField.Description);
      for mField in mEntity.Predicates do
        Add(mField.Name, mField.Description);
      if mLast <> 'not' then
        AddKeywords(['not']);
    end
    else if IsSymbolPredicate(mLast) and (mLast <> 'uses') then
      // Symbolname: Vorschläge über SymbolPredicate aus der Symbolsuche.
    else if mLast = 'has' then
      AddKeywords(['attribute'])
    else if mHasEntity and (Length(mWords) >= 2) and IsComparison(mWords[High(mWords)]) then
      // Nach einem Vergleich steht ein Wert: nichts aus dem Katalog.
    else if mHasEntity and (Length(mWords) >= 2) and not IsComparison(mLast) then
    begin
      // Nach einem Feld: Vergleich; nach einem Wert: Verknüpfung, Sortierung, Grenze.
      for mField in mEntity.Fields do
        if SameText(mField.Name, mLast) then
        begin
          AddKeywords(['=', '<>', '<', '>', '<=', '>=', 'like', 'not like']);
          Break;
        end;
      if Length(mAll) = 0 then
        AddKeywords(['and', 'or', 'order', 'limit']);
    end;
  end;
  for mItem in mAll do
    if (mPrefix = '') or StartsText(mPrefix, mItem.Text) then
      Result := Result + [mItem];
end;

{ TAtlasSavedQueries }

class function TAtlasSavedQueries.ValidName(const AName: string): Boolean;
var
  mChar: Char;
begin
  Result := AName <> '';
  for mChar in AName do
    if not CharInSet(mChar, ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.']) then
      Exit(False);
end;

class function TAtlasSavedQueries.WithQuery(const AExisting: string; const AQuery: TAtlasSavedQuery;
  const ASeverity, AMessage: string): string;
var
  mValue: TJSONValue;
  mList, mResult: TJSONArray;
  mEntry: TJSONObject;
  mIndex: Integer;
  mReplaced: Boolean;
begin
  mResult := TJSONArray.Create;
  try
    mValue := nil;
    if Trim(AExisting) <> '' then
      mValue := TJSONObject.ParseJSONValue(AExisting);
    try
      mEntry := TJSONObject.Create;
      mEntry.AddPair('name', AQuery.Name);
      mEntry.AddPair('query', AQuery.Query);
      if AQuery.Description <> '' then
        mEntry.AddPair('description', AQuery.Description);
      if AQuery.FailIfAny then
        mEntry.AddPair('failIfAny', TJSONBool.Create(True));
      if ASeverity <> '' then
        mEntry.AddPair('severity', ASeverity);
      if AMessage <> '' then
        mEntry.AddPair('message', AMessage);
      mReplaced := False;
      if mValue is TJSONArray then
      begin
        mList := TJSONArray(mValue);
        for mIndex := 0 to mList.Count - 1 do
          if (mList.Items[mIndex] is TJSONObject) and
            SameText(StringOf(TJSONObject(mList.Items[mIndex]), 'name'), AQuery.Name) then
          begin
            if not mReplaced then
              mResult.AddElement(mEntry);
            mReplaced := True;
          end
          else
            mResult.AddElement(TJSONValue(mList.Items[mIndex].Clone));
      end;
      if not mReplaced then
        mResult.AddElement(mEntry);
    finally
      mValue.Free;
    end;
    Result := mResult.ToJSON([]);
  finally
    mResult.Free;
  end;
end;

{ TAtlasQueryRequest }

class function TAtlasQueryRequest.Params(const AUri, AQuery: string; ALimit: Integer): string;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    mParams.AddPair('uri', AUri);
    mParams.AddPair('query', AQuery);
    mParams.AddPair('limit', TJSONNumber.Create(ALimit));
    mParams.AddPair('format', 'json');
    Result := mParams.ToJSON([]);
  finally
    mParams.Free;
  end;
end;

class function TAtlasQueryRequest.CatalogParams(const AUri: string): string;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    mParams.AddPair('uri', AUri);
    Result := mParams.ToJSON([]);
  finally
    mParams.Free;
  end;
end;

class function TAtlasQueryCompletion.SymbolPredicate(const AText: string; ACursor: Integer; out AStart: Integer;
  out APrefix, APredicate: string): Boolean;
var
  mCursor, mBegin: Integer;
  mWords: TArray<string>;
begin
  mCursor := ACursor;
  if mCursor > Length(AText) then
    mCursor := Length(AText);
  if mCursor < 0 then
    mCursor := 0;
  mBegin := mCursor;
  while (mBegin > 0) and IsWordChar(AText[mBegin]) do
    Dec(mBegin);
  AStart := mBegin;
  APrefix := Copy(AText, mBegin + 1, mCursor - mBegin);
  APredicate := '';
  mWords := WordsBefore(AText, mBegin);
  // Das erste Wort ist die Menge (units hat ein Feld uses, aber „uses“ als erstes Wort gibt es nicht).
  Result := (Length(mWords) >= 2) and IsSymbolPredicate(mWords[High(mWords)]);
  if Result then
    APredicate := mWords[High(mWords)];
end;

class function TAtlasQueryCompletion.SymbolNames(const APredicate: string;
  const ASymbols: TArray<TAtlasSymbol>): TArray<string>;
const
  // LSP SymbolKind.
  cClass = 5;
  cMethod = 6;
  cConstructor = 9;
  cInterface = 11;
  cFunction = 12;
  cStruct = 23;
var
  mSymbol: TAtlasSymbol;
  mFits: Boolean;
begin
  Result := nil;
  for mSymbol in ASymbols do
  begin
    if APredicate = 'inherits' then
      mFits := (mSymbol.Kind = cClass) or (mSymbol.Kind = cStruct) or (mSymbol.Kind = cInterface)
    else if APredicate = 'implements' then
      mFits := mSymbol.Kind = cInterface
    else if APredicate = 'calls' then
      mFits := (mSymbol.Kind = cMethod) or (mSymbol.Kind = cConstructor) or (mSymbol.Kind = cFunction)
    else if APredicate = 'attribute' then
      mFits := (mSymbol.Kind = cClass) and EndsText('Attribute', mSymbol.Name)
    else
      mFits := False;
    if mFits and (mSymbol.Name <> '') then
      Result := Result + [mSymbol.Name];
  end;
end;

end.
