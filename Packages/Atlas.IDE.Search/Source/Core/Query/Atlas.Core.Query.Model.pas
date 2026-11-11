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
    cMethod = 'atlas/query';
    cCatalogMethod = 'atlas/queryCatalog';
  public
    /// <summary>{"uri", "query", "limit", "format": "json"} für atlas/query.</summary>
    class function Params(const AUri, AQuery: string; ALimit: Integer): string; static;
    /// <summary>{"uri"} für atlas/queryCatalog.</summary>
    class function CatalogParams(const AUri: string): string; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Generics.Defaults,
  System.Generics.Collections,
  Atlas.Text.Json;

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

/// <summary>Texte aller Einträge (leer ohne Array).</summary>
function ValuesOf(AArray: TJSONArray): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  if AArray <> nil then
  begin
    for mIndex := 0 to AArray.Count - 1 do
    begin
      Result := Result + [AArray.Items[mIndex].Value];
    end;
  end;
end;

/// <summary>Zeile der Antwort; Zellen in der Reihenfolge von AColumns.</summary>
function RowOf(AItem: TJSONValue; AOrder: Integer; const AColumns: TArray<string>): TAtlasQueryRow;
var
  mObject, mValues: TJSONObject;
  mColumn: Integer;
begin
  Result := Default(TAtlasQueryRow);
  Result.Order := AOrder;
  if not (AItem is TJSONObject) then
  begin
    Exit;
  end;
  mObject := TJSONObject(AItem);
  Result.FileName := StringOf(mObject, 'file');
  Result.Path := StringOf(mObject, 'path');
  Result.Line := Integer(TJsonRead.Int64Or(mObject, 'line', 0));
  Result.Character := Integer(TJsonRead.Int64Or(mObject, 'character', 0));
  Result.Inferred := TJsonRead.Flag(mObject, 'inferred');
  Result.InferredDetail := StringOf(mObject, 'inferredDetail');
  mValues := TJsonRead.Obj(mObject, 'values');
  SetLength(Result.Cells, Length(AColumns));
  if mValues <> nil then
  begin
    for mColumn := 0 to High(AColumns) do
    begin
      Result.Cells[mColumn] := CellOf(mValues.GetValue(AColumns[mColumn]));
    end;
  end;
end;

/// <summary>Inhalt von "data" der Antwort: Fehler oder Spalten und Zeilen.</summary>
procedure ReadAnswerData(AData: TJSONObject; var AAnswer: TAtlasQueryAnswer);
var
  mError: TJSONObject;
  mRows: TJSONArray;
  mIndex: Integer;
begin
  AAnswer.Query := StringOf(AData, 'query');
  mError := TJsonRead.Obj(AData, 'error');
  if mError <> nil then
  begin
    AAnswer.Error := StringOf(mError, 'message');
    AAnswer.ErrorColumn := Integer(TJsonRead.Int64Or(mError, 'column', 0));
    AAnswer.Suggestion := StringOf(mError, 'suggestion');
    Exit;
  end;
  AAnswer.Entity := StringOf(AData, 'entity');
  AAnswer.Total := Integer(TJsonRead.Int64Or(AData, 'total', 0));
  AAnswer.InferredCount := Integer(TJsonRead.Int64Or(AData, 'inferred', 0));
  AAnswer.ElapsedMs := TJsonRead.Int64Or(AData, 'elapsedMs', 0);
  AAnswer.Truncated := TJsonRead.Flag(AData, 'truncated');
  AAnswer.Columns := ValuesOf(TJsonRead.Items(AData, 'columns'));
  mRows := TJsonRead.Items(AData, 'rows');
  if mRows = nil then
  begin
    Exit;
  end;
  SetLength(AAnswer.Rows, mRows.Count);
  for mIndex := 0 to mRows.Count - 1 do
  begin
    AAnswer.Rows[mIndex] := RowOf(mRows.Items[mIndex], mIndex, AAnswer.Columns);
  end;
end;

class function TAtlasQueryAnswer.Parse(const AJson: string; out AAnswer: TAtlasQueryAnswer): Boolean;
var
  mValue: TJSONValue;
  mData: TJSONObject;
begin
  AAnswer := Default(TAtlasQueryAnswer);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if Result then
    begin
      AAnswer.Enabled := TJsonRead.Flag(TJSONObject(mValue), 'enabled');
      mData := TJsonRead.Obj(TJSONObject(mValue), 'data');
      if mData <> nil then
      begin
        ReadAnswerData(mData, AAnswer);
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Zellen einer Spalte: Zahlen als Zahl, sonst Text ohne Groß-/Kleinschreibung; ohne Wert immer zuletzt,
/// auch absteigend.</summary>
function CompareCells(const ALeft, ARight: TAtlasQueryCell; ADescending: Boolean): Integer;
begin
  if ALeft.HasValue <> ARight.HasValue then
  begin
    Exit(Ord(ARight.HasValue) - Ord(ALeft.HasValue));
  end;
  if ALeft.IsNumber and ARight.IsNumber then
  begin
    Result := CompareValue(ALeft.Number, ARight.Number);
  end
  else
  begin
    Result := CompareText(ALeft.Text, ARight.Text);
  end;
  if ADescending then
  begin
    Result := -Result;
  end;
end;

/// <summary>Pfad, Zeile, Spalte und Reihenfolge des Servers: eindeutig, denn TArray.Sort ist nicht stabil.</summary>
function ComparePlaces(const ALeft, ARight: TAtlasQueryRow): Integer;
begin
  Result := CompareText(ALeft.Path, ARight.Path);
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
end;

function RowComparer(AColumn: Integer; ADescending: Boolean): IComparer<TAtlasQueryRow>;
var
  mColumn: Integer;
  mDescending: Boolean;
begin
  mColumn := AColumn;
  mDescending := ADescending;
  Result := TComparer<TAtlasQueryRow>.Construct(
    function(const ALeft, ARight: TAtlasQueryRow): Integer
    begin
      Result := 0;
      if (mColumn >= 0) and (mColumn <= High(ALeft.Cells)) and (mColumn <= High(ARight.Cells)) then
      begin
        Result := CompareCells(ALeft.Cells[mColumn], ARight.Cells[mColumn], mDescending);
      end;
      if Result = 0 then
      begin
        Result := ComparePlaces(ALeft, ARight);
      end;
    end);
end;

procedure TAtlasQueryAnswer.Sort(AColumn: Integer; ADescending: Boolean);
begin
  TArray.Sort<TAtlasQueryRow>(Rows, RowComparer(AColumn, ADescending));
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

function EntitiesOf(AItems: TJSONArray): TArray<TAtlasQueryEntity>;
var
  mIndex: Integer;
  mItem: TJSONObject;
  mEntity: TAtlasQueryEntity;
begin
  Result := nil;
  if AItems = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AItems.Count - 1 do
  begin
    if AItems.Items[mIndex] is TJSONObject then
    begin
      mItem := TJSONObject(AItems.Items[mIndex]);
      mEntity := Default(TAtlasQueryEntity);
      mEntity.Name := StringOf(mItem, 'name');
      mEntity.Caption := StringOf(mItem, 'caption');
      mEntity.Fields := FieldsOf(TJsonRead.Items(mItem, 'fields'));
      mEntity.Predicates := FieldsOf(TJsonRead.Items(mItem, 'predicates'));
      Result := Result + [mEntity];
    end;
  end;
end;

function SavedOf(AItems: TJSONArray): TArray<TAtlasSavedQuery>;
var
  mIndex: Integer;
  mItem: TJSONObject;
  mSaved: TAtlasSavedQuery;
begin
  Result := nil;
  if AItems = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AItems.Count - 1 do
  begin
    if AItems.Items[mIndex] is TJSONObject then
    begin
      mItem := TJSONObject(AItems.Items[mIndex]);
      mSaved := Default(TAtlasSavedQuery);
      mSaved.Name := StringOf(mItem, 'name');
      mSaved.Query := StringOf(mItem, 'query');
      mSaved.Description := StringOf(mItem, 'description');
      mSaved.FailIfAny := TJsonRead.Flag(mItem, 'failIfAny');
      Result := Result + [mSaved];
    end;
  end;
end;

class function TAtlasQueryCatalog.Parse(const AJson: string; out ACatalog: TAtlasQueryCatalog): Boolean;
var
  mValue: TJSONValue;
  mCatalog: TJSONObject;
begin
  ACatalog := Default(TAtlasQueryCatalog);
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := mValue is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    ACatalog.Enabled := TJsonRead.Flag(TJSONObject(mValue), 'enabled');
    mCatalog := TJsonRead.Obj(TJSONObject(mValue), 'catalog');
    if mCatalog <> nil then
    begin
      ACatalog.Entities := EntitiesOf(TJsonRead.Items(mCatalog, 'entities'));
      ACatalog.Keywords := ValuesOf(TJsonRead.Items(mCatalog, 'keywords'));
      ACatalog.Saved := SavedOf(TJsonRead.Items(mCatalog, 'queries'));
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

function IsComparisonChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['=', '<', '>', '!']);
end;

/// <summary>Stelle des schließenden Anführungszeichens zu AText[AFrom] bis ALimit (ALimit + 1 ohne).</summary>
function ClosingQuote(const AText: string; AFrom, ALimit: Integer): Integer;
begin
  Result := AFrom + 1;
  while (Result <= ALimit) and (AText[Result] <> AText[AFrom]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Erste Stelle ab AFrom bis ALimit, die kein Wortzeichen ist (ALimit + 1 ohne).</summary>
function SkipWordChars(const AText: string; AFrom, ALimit: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= ALimit) and IsWordChar(AText[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Erste Stelle ab AFrom bis ALimit, die kein Vergleichszeichen ist (ALimit + 1 ohne).</summary>
function SkipComparisonChars(const AText: string; AFrom, ALimit: Integer): Integer;
begin
  Result := AFrom;
  while (Result <= ALimit) and IsComparisonChar(AText[Result]) do
  begin
    Inc(Result);
  end;
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
    mStart := mIndex;
    if CharInSet(mChar, ['''', '"']) then
    begin
      mIndex := ClosingQuote(AText, mIndex, APosition);
      Result := Result + [Copy(AText, mStart, mIndex - mStart + 1)];
      Inc(mIndex);
    end
    else if IsWordChar(mChar) then
    begin
      mIndex := SkipWordChars(AText, mIndex, APosition);
      Result := Result + [LowerCase(Copy(AText, mStart, mIndex - mStart))];
    end
    else if IsComparisonChar(mChar) then
    begin
      mIndex := SkipComparisonChars(AText, mIndex, APosition);
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
  Result := MatchStr(AWord, ['=', '<>', '!=', '<', '>', '<=', '>=', 'like']);
end;

function IsSymbolPredicate(const AWord: string): Boolean;
begin
  Result := MatchStr(AWord, ['inherits', 'implements', 'uses', 'calls', 'attribute']);
end;

/// <summary>Schreibmarke in den Text geklemmt (0 bis Länge).</summary>
function ClampCursor(const AText: string; ACursor: Integer): Integer;
begin
  Result := EnsureRange(ACursor, 0, Length(AText));
end;

/// <summary>Anfang (0-basiert) des Worts, das an der Schreibmarke ACursor endet.</summary>
function WordBegin(const AText: string; ACursor: Integer): Integer;
begin
  Result := ACursor;
  while (Result > 0) and IsWordChar(AText[Result]) do
  begin
    Dec(Result);
  end;
end;

type
  /// <summary>Gesammelte Vorschläge, noch ohne Filter nach dem getippten Anfang.</summary>
  TSuggestionList = record
    Items: TArray<TAtlasQuerySuggestion>;
    procedure Add(const AName, ADetail: string);
    procedure AddKeywords(const ANames: array of string);
    procedure AddFields(const AFields: TArray<TAtlasQueryField>);
  end;

procedure TSuggestionList.Add(const AName, ADetail: string);
begin
  Items := Items + [Suggestion(AName, ADetail)];
end;

procedure TSuggestionList.AddKeywords(const ANames: array of string);
var
  mName: string;
begin
  for mName in ANames do
  begin
    Add(mName, '');
  end;
end;

procedure TSuggestionList.AddFields(const AFields: TArray<TAtlasQueryField>);
var
  mField: TAtlasQueryField;
begin
  for mField in AFields do
  begin
    Add(mField.Name, mField.Description);
  end;
end;

/// <summary>Am Anfang: Mengen und gespeicherte Abfragen.</summary>
procedure SuggestStart(const ACatalog: TAtlasQueryCatalog; var AList: TSuggestionList);
var
  mEntity: TAtlasQueryEntity;
  mSaved: TAtlasSavedQuery;
begin
  for mEntity in ACatalog.Entities do
  begin
    AList.Add(mEntity.Name, mEntity.Caption);
  end;
  for mSaved in ACatalog.Saved do
  begin
    AList.Add('@' + mSaved.Name, mSaved.Description);
  end;
end;

/// <summary>Regeln, die nur am letzten Wort hängen; True, wenn eine gegriffen hat (auch ohne Vorschlag).</summary>
function SuggestAfterWord(const ALast: string; var AList: TSuggestionList): Boolean;
begin
  Result := True;
  if ALast = 'order' then
  begin
    AList.AddKeywords(['by']);
  end
  else if (ALast = 'asc') or (ALast = 'desc') then
  begin
    AList.AddKeywords(['limit']);
  end
  else if ALast = 'has' then
  begin
    AList.AddKeywords(['attribute']);
  end
  else
  begin
    // Symbolname: Vorschläge über SymbolPredicate aus der Symbolsuche.
    Result := IsSymbolPredicate(ALast) and (ALast <> 'uses');
  end;
end;

function IsFieldOf(const AEntity: TAtlasQueryEntity; const AName: string): Boolean;
var
  mField: TAtlasQueryField;
begin
  for mField in AEntity.Fields do
  begin
    if SameText(mField.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Regeln in einer Abfrage über AEntity (erstes Wort).</summary>
procedure SuggestForEntity(const AWords: TArray<string>; const AEntity: TAtlasQueryEntity;
  var AList: TSuggestionList);
var
  mLast: string;
begin
  mLast := AWords[High(AWords)];
  if mLast = 'by' then
  begin
    AList.AddFields(AEntity.Fields);
  end
  else if Length(AWords) = 1 then
  begin
    AList.AddKeywords(['where', 'order', 'limit']);
  end
  else if MatchStr(mLast, ['where', 'and', 'or', 'not', '(']) then
  begin
    AList.AddFields(AEntity.Fields);
    AList.AddFields(AEntity.Predicates);
    if mLast <> 'not' then
    begin
      AList.AddKeywords(['not']);
    end;
  end
  else if IsComparison(mLast) then
  begin
    // Nach einem Vergleich steht ein Wert: nichts aus dem Katalog.
  end
  else if IsFieldOf(AEntity, mLast) then
  begin
    // Nach einem Feld: Vergleich.
    AList.AddKeywords(['=', '<>', '<', '>', '<=', '>=', 'like', 'not like']);
  end
  else
  begin
    // Nach einem Wert: Verknüpfung, Sortierung, Grenze.
    AList.AddKeywords(['and', 'or', 'order', 'limit']);
  end;
end;

class function TAtlasQueryCompletion.Suggest(const ACatalog: TAtlasQueryCatalog; const AText: string;
  ACursor: Integer; out AStart: Integer): TArray<TAtlasQuerySuggestion>;
var
  mCursor: Integer;
  mPrefix: string;
  mWords: TArray<string>;
  mEntity: TAtlasQueryEntity;
  mList: TSuggestionList;
  mItem: TAtlasQuerySuggestion;
begin
  Result := nil;
  mCursor := ClampCursor(AText, ACursor);
  AStart := WordBegin(AText, mCursor);
  mPrefix := Copy(AText, AStart + 1, mCursor - AStart);
  mWords := WordsBefore(AText, AStart);
  mList := Default(TSuggestionList);
  if Length(mWords) = 0 then
  begin
    SuggestStart(ACatalog, mList);
  end
  else if not SuggestAfterWord(mWords[High(mWords)], mList) and ACatalog.TryEntity(mWords[0], mEntity) then
  begin
    SuggestForEntity(mWords, mEntity, mList);
  end;
  for mItem in mList.Items do
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

/// <summary>Eintrag der gespeicherten Abfrage; ASeverity und AMessage nur, wenn nicht leer.</summary>
function SavedEntry(const AQuery: TAtlasSavedQuery; const ASeverity, AMessage: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AQuery.Name);
  Result.AddPair('query', AQuery.Query);
  if AQuery.Description <> '' then
  begin
    Result.AddPair('description', AQuery.Description);
  end;
  if AQuery.FailIfAny then
  begin
    Result.AddPair('failIfAny', TJSONBool.Create(True));
  end;
  if ASeverity <> '' then
  begin
    Result.AddPair('severity', ASeverity);
  end;
  if AMessage <> '' then
  begin
    Result.AddPair('message', AMessage);
  end;
end;

/// <summary>Kopiert die Einträge der bisherigen Liste nach AResult; der erste Eintrag namens AName wird durch
/// AEntry ersetzt, weitere gleichen Namens fallen weg. True, wenn AEntry so eingefügt wurde.</summary>
function CopyReplacing(AExisting: TJSONValue; AResult: TJSONArray; AEntry: TJSONObject; const AName: string): Boolean;
var
  mList: TJSONArray;
  mItem: TJSONValue;
  mIndex: Integer;
begin
  Result := False;
  if not (AExisting is TJSONArray) then
  begin
    Exit;
  end;
  mList := TJSONArray(AExisting);
  for mIndex := 0 to mList.Count - 1 do
  begin
    mItem := mList.Items[mIndex];
    if not ((mItem is TJSONObject) and SameText(StringOf(TJSONObject(mItem), 'name'), AName)) then
    begin
      AResult.AddElement(TJSONValue(mItem.Clone));
    end
    else if not Result then
    begin
      AResult.AddElement(AEntry);
      Result := True;
    end;
  end;
end;

class function TAtlasSavedQueries.WithQuery(const AExisting: string; const AQuery: TAtlasSavedQuery;
  const ASeverity, AMessage: string): string;
var
  mValue: TJSONValue;
  mResult: TJSONArray;
  mEntry: TJSONObject;
begin
  mResult := TJSONArray.Create;
  try
    mValue := nil;
    if Trim(AExisting) <> '' then
    begin
      mValue := TJSONObject.ParseJSONValue(AExisting);
    end;
    try
      mEntry := SavedEntry(AQuery, ASeverity, AMessage);
      if not CopyReplacing(mValue, mResult, mEntry, AQuery.Name) then
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
  mCursor: Integer;
  mWords: TArray<string>;
begin
  mCursor := ClampCursor(AText, ACursor);
  AStart := WordBegin(AText, mCursor);
  APrefix := Copy(AText, AStart + 1, mCursor - AStart);
  APredicate := '';
  mWords := WordsBefore(AText, AStart);
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
