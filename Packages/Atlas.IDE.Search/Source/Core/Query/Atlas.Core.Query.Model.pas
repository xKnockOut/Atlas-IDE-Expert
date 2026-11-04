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
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if (mValue <> nil) and not (mValue is TJSONNull) and not (mValue is TJSONObject) and
    not (mValue is TJSONArray) then
  begin
    Result := mValue.Value;
  end;
end;

function IntegerOf(AObject: TJSONObject; const AName: string): Int64;
var
  mValue: TJSONValue;
begin
  Result := 0;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsInt64;
  end;
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  Result := False;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONBool then
  begin
    Result := TJSONBool(mValue).AsBoolean;
  end;
end;

function ArrayOf(AObject: TJSONObject; const AName: string): TJSONArray;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONArray then
  begin
    Result := TJSONArray(mValue);
  end;
end;

function ObjectOf(AObject: TJSONObject; const AName: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONObject then
  begin
    Result := TJSONObject(mValue);
  end;
end;

function CellOf(AValue: TJSONValue): TAtlasQueryCell;
begin
  Result := Default(TAtlasQueryCell);
  if (AValue = nil) or (AValue is TJSONNull) then
  begin
    Exit;
  end;
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
    begin
      Result.Text := 'ja';
    end
    else
    begin
      Result.Text := 'nein';
    end;
  end
  else
  begin
    Result.Text := AValue.Value;
  end;
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
  begin
    if SameText(Columns[mIndex], AName) then
    begin
      Exit(mIndex);
    end;
  end;
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
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    AAnswer.Enabled := FlagOf(mRoot, 'enabled');
    mData := ObjectOf(mRoot, 'data');
    if mData = nil then
    begin
      Exit;
    end;
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
    begin
      for mIndex := 0 to mColumns.Count - 1 do
      begin
        AAnswer.Columns := AAnswer.Columns + [mColumns.Items[mIndex].Value];
      end;
    end;
    mRows := ArrayOf(mData, 'rows');
    if mRows = nil then
    begin
      Exit;
    end;
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
        begin
          if mValues <> nil then
          begin
            mRow.Cells[mColumn] := CellOf(mValues.GetValue(AAnswer.Columns[mColumn]));
          end;
        end;
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
          begin
            Exit(-1);
          end;
          Exit(1);
        end;
        if mLeft.IsNumber and mRight.IsNumber then
        begin
          if mLeft.Number < mRight.Number then
          begin
            Result := -1;
          end
          else if mLeft.Number > mRight.Number then
          begin
            Result := 1;
          end;
        end
        else
        begin
          Result := CompareText(mLeft.Text, mRight.Text);
        end;
        if mDescending then
        begin
          Result := -Result;
        end;
      end;
      // Eindeutig weitersortieren: TArray.Sort ist nicht stabil.
      if Result = 0 then
      begin
        Result := CompareText(ALeft.Path, ARight.Path);
      end;
      if Result = 0 then
      begin
        Result := ALeft.Line - ARight.Line;
      end;
      if Result = 0 then
      begin
        Result := ALeft.Character - ARight.Character;
      end;
      if Result = 0 then
      begin
        Result := ALeft.Order - ARight.Order;
      end;
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
    begin
      mBuilder.Append(CsvCell(Columns[mIndex])).Append(';');
    end;
    mBuilder.Append('path;inferred').Append(sLineBreak);
    for mRow in Rows do
    begin
      for mIndex := 0 to High(Columns) do
      begin
        if mIndex <= High(mRow.Cells) then
        begin
          mBuilder.Append(CsvCell(mRow.Cells[mIndex].Text)).Append(';');
        end
        else
        begin
          mBuilder.Append(';');
        end;
      end;
      mBuilder.Append(CsvCell(mRow.Path)).Append(';');
      if mRow.Inferred then
      begin
        mBuilder.Append('erschlossen');
      end;
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
  begin
    Exit;
  end;
  for mIndex := 0 to AArray.Count - 1 do
  begin
    if AArray.Items[mIndex] is TJSONObject then
    begin
      mField.Name := StringOf(TJSONObject(AArray.Items[mIndex]), 'name');
      mField.FieldType := StringOf(TJSONObject(AArray.Items[mIndex]), 'type');
      mField.Description := StringOf(TJSONObject(AArray.Items[mIndex]), 'description');
      Result := Result + [mField];
    end;
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
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    ACatalog.Enabled := FlagOf(mRoot, 'enabled');
    mCatalog := ObjectOf(mRoot, 'catalog');
    if mCatalog = nil then
    begin
      Exit;
    end;
    mItems := ArrayOf(mCatalog, 'entities');
    if mItems <> nil then
    begin
      for mIndex := 0 to mItems.Count - 1 do
      begin
        if mItems.Items[mIndex] is TJSONObject then
        begin
          mItem := TJSONObject(mItems.Items[mIndex]);
          mEntity.Name := StringOf(mItem, 'name');
          mEntity.Caption := StringOf(mItem, 'caption');
          mEntity.Fields := FieldsOf(ArrayOf(mItem, 'fields'));
          mEntity.Predicates := FieldsOf(ArrayOf(mItem, 'predicates'));
          ACatalog.Entities := ACatalog.Entities + [mEntity];
        end;
      end;
    end;
    mItems := ArrayOf(mCatalog, 'keywords');
    if mItems <> nil then
    begin
      for mIndex := 0 to mItems.Count - 1 do
      begin
        ACatalog.Keywords := ACatalog.Keywords + [mItems.Items[mIndex].Value];
      end;
    end;
    mItems := ArrayOf(mCatalog, 'queries');
    if mItems <> nil then
    begin
      for mIndex := 0 to mItems.Count - 1 do
      begin
        if mItems.Items[mIndex] is TJSONObject then
        begin
          mItem := TJSONObject(mItems.Items[mIndex]);
          mSaved.Name := StringOf(mItem, 'name');
          mSaved.Query := StringOf(mItem, 'query');
          mSaved.Description := StringOf(mItem, 'description');
          mSaved.FailIfAny := FlagOf(mItem, 'failIfAny');
          ACatalog.Saved := ACatalog.Saved + [mSaved];
        end;
      end;
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
  begin
    if SameText(mEntity.Name, AName) then
    begin
      AEntity := mEntity;
      Exit(True);
    end;
  end;
  AEntity := Default(TAtlasQueryEntity);
  Result := False;
end;

function TAtlasQueryCatalog.TrySaved(const AName: string; out AQuery: TAtlasSavedQuery): Boolean;
var
  mSaved: TAtlasSavedQuery;
begin
  for mSaved in Saved do
  begin
    if SameText(mSaved.Name, AName) then
    begin
      AQuery := mSaved;
      Exit(True);
    end;
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
      begin
        Inc(mIndex);
      end;
      Result := Result + [Copy(AText, mStart, mIndex - mStart + 1)];
      Inc(mIndex);
    end
    else if IsWordChar(mChar) then
    begin
      mStart := mIndex;
      while (mIndex <= APosition) and IsWordChar(AText[mIndex]) do
      begin
        Inc(mIndex);
      end;
      Result := Result + [LowerCase(Copy(AText, mStart, mIndex - mStart))];
    end
    else if CharInSet(mChar, ['=', '<', '>', '!']) then
    begin
      mStart := mIndex;
      while (mIndex <= APosition) and CharInSet(AText[mIndex], ['=', '<', '>', '!']) do
      begin
        Inc(mIndex);
      end;
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
    end
    else
    begin
      if CharInSet(mChar, ['(', ')']) then
      begin
        Result := Result + [string(mChar)];
      end;
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
    begin
      Add(mName, '');
    end;
  end;

begin
  Result := nil;
  mAll := nil;
  mCursor := ACursor;
  if mCursor > Length(AText) then
  begin
    mCursor := Length(AText);
  end;
  if mCursor < 0 then
  begin
    mCursor := 0;
  end;
  // Anfang des Worts an der Schreibmarke (1-basiert in mBegin).
  mBegin := mCursor;
  while (mBegin > 0) and IsWordChar(AText[mBegin]) do
  begin
    Dec(mBegin);
  end;
  AStart := mBegin;
  mPrefix := Copy(AText, mBegin + 1, mCursor - mBegin);
  mWords := WordsBefore(AText, mBegin);
  if Length(mWords) = 0 then
  begin
    // Am Anfang: Mengen und gespeicherte Abfragen.
    for mEntity in ACatalog.Entities do
    begin
      Add(mEntity.Name, mEntity.Caption);
    end;
    for mSaved in ACatalog.Saved do
    begin
      Add('@' + mSaved.Name, mSaved.Description);
    end;
  end
  else
  begin
    mHasEntity := ACatalog.TryEntity(mWords[0], mEntity);
    mLast := mWords[High(mWords)];
    if mLast = 'order' then
    begin
      AddKeywords(['by']);
    end
    else if (mLast = 'by') and mHasEntity then
    begin
      for mField in mEntity.Fields do
      begin
        Add(mField.Name, mField.Description);
      end;
    end
    else if (mLast = 'asc') or (mLast = 'desc') then
    begin
      AddKeywords(['limit']);
    end
    else if (Length(mWords) = 1) and mHasEntity then
    begin
      AddKeywords(['where', 'order', 'limit']);
    end
    else if ((mLast = 'where') or (mLast = 'and') or (mLast = 'or') or (mLast = 'not') or (mLast = '(')) and
      mHasEntity then
    begin
      for mField in mEntity.Fields do
      begin
        Add(mField.Name, mField.Description);
      end;
      for mField in mEntity.Predicates do
      begin
        Add(mField.Name, mField.Description);
      end;
      if mLast <> 'not' then
      begin
        AddKeywords(['not']);
      end;
    end
    else if IsSymbolPredicate(mLast) and (mLast <> 'uses') then
      // Symbolname: Vorschläge über SymbolPredicate aus der Symbolsuche.
    else if mLast = 'has' then
    begin
      AddKeywords(['attribute']);
    end
    else if mHasEntity and (Length(mWords) >= 2) and IsComparison(mWords[High(mWords)]) then
      // Nach einem Vergleich steht ein Wert: nichts aus dem Katalog.
    else if mHasEntity and (Length(mWords) >= 2) and not IsComparison(mLast) then
    begin
      // Nach einem Feld: Vergleich; nach einem Wert: Verknüpfung, Sortierung, Grenze.
      for mField in mEntity.Fields do
      begin
        if SameText(mField.Name, mLast) then
        begin
          AddKeywords(['=', '<>', '<', '>', '<=', '>=', 'like', 'not like']);
          Break;
        end;
      end;
      if Length(mAll) = 0 then
      begin
        AddKeywords(['and', 'or', 'order', 'limit']);
      end;
    end;
  end;
  for mItem in mAll do
  begin
    if (mPrefix = '') or StartsText(mPrefix, mItem.Text) then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

{ TAtlasSavedQueries }

class function TAtlasSavedQueries.ValidName(const AName: string): Boolean;
var
  mChar: Char;
begin
  Result := AName <> '';
  for mChar in AName do
  begin
    if not CharInSet(mChar, ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.']) then
    begin
      Exit(False);
    end;
  end;
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
    begin
      mValue := TJSONObject.ParseJSONValue(AExisting);
    end;
    try
      mEntry := TJSONObject.Create;
      mEntry.AddPair('name', AQuery.Name);
      mEntry.AddPair('query', AQuery.Query);
      if AQuery.Description <> '' then
      begin
        mEntry.AddPair('description', AQuery.Description);
      end;
      if AQuery.FailIfAny then
      begin
        mEntry.AddPair('failIfAny', TJSONBool.Create(True));
      end;
      if ASeverity <> '' then
      begin
        mEntry.AddPair('severity', ASeverity);
      end;
      if AMessage <> '' then
      begin
        mEntry.AddPair('message', AMessage);
      end;
      mReplaced := False;
      if mValue is TJSONArray then
      begin
        mList := TJSONArray(mValue);
        for mIndex := 0 to mList.Count - 1 do
        begin
          if (mList.Items[mIndex] is TJSONObject) and
            SameText(StringOf(TJSONObject(mList.Items[mIndex]), 'name'), AQuery.Name) then
          begin
            if not mReplaced then
            begin
              mResult.AddElement(mEntry);
            end;
            mReplaced := True;
          end
          else
          begin
            mResult.AddElement(TJSONValue(mList.Items[mIndex].Clone));
          end;
        end;
      end;
      if not mReplaced then
      begin
        mResult.AddElement(mEntry);
      end;
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
  begin
    mCursor := Length(AText);
  end;
  if mCursor < 0 then
  begin
    mCursor := 0;
  end;
  mBegin := mCursor;
  while (mBegin > 0) and IsWordChar(AText[mBegin]) do
  begin
    Dec(mBegin);
  end;
  AStart := mBegin;
  APrefix := Copy(AText, mBegin + 1, mCursor - mBegin);
  APredicate := '';
  mWords := WordsBefore(AText, mBegin);
  // Das erste Wort ist die Menge (units hat ein Feld uses, aber „uses“ als erstes Wort gibt es nicht).
  Result := (Length(mWords) >= 2) and IsSymbolPredicate(mWords[High(mWords)]);
  if Result then
  begin
    APredicate := mWords[High(mWords)];
  end;
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
    begin
      mFits := (mSymbol.Kind = cClass) or (mSymbol.Kind = cStruct) or (mSymbol.Kind = cInterface);
    end
    else if APredicate = 'implements' then
    begin
      mFits := mSymbol.Kind = cInterface;
    end
    else if APredicate = 'calls' then
    begin
      mFits := (mSymbol.Kind = cMethod) or (mSymbol.Kind = cConstructor) or (mSymbol.Kind = cFunction);
    end
    else if APredicate = 'attribute' then
    begin
      mFits := (mSymbol.Kind = cClass) and EndsText('Attribute', mSymbol.Name);
    end
    else
    begin
      mFits := False;
    end;
    if mFits and (mSymbol.Name <> '') then
    begin
      Result := Result + [mSymbol.Name];
    end;
  end;
end;

end.
