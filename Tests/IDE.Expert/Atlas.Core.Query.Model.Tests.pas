unit Atlas.Core.Query.Model.Tests;

// Kern des Fensters „Atlas-Abfrage“ (#1351): Antwort lesen, sortieren mit
// eindeutigem Gleichstand, CSV wie der Server, Katalog, Vervollständigung,
// „Als Regel speichern …“ und Parameter der Anfragen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasQueryModelTests = class
  public
    [Test]
    procedure ParsesRowsAndCells;
    [Test]
    procedure ParsesErrorAndDisabled;
    [Test]
    procedure SortsNumbersTextAndTies;
    [Test]
    procedure CsvLikeServer;
    [Test]
    procedure ParsesCatalog;
    [Test]
    procedure CompletesEntitiesFieldsAndKeywords;
    [Test]
    procedure CompletesSymbolNamesAfterPredicates;
    [Test]
    procedure SymbolNamesFitPredicate;
    [Test]
    procedure SavedQueryReplacesSameName;
    [Test]
    procedure RequestParams;
  end;

/// <summary>Beispielantwort von atlas/query bzw. atlas/queryCatalog (auch für die Tests des Fensters).</summary>
function QuerySampleAnswer: string;
function QuerySampleCatalog: string;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Query.Model;

const
  cAnswer = '{"enabled": true, "root": "C:\\P", "format": "json", "data": {"query": "classes where methods > 0", ' +
    '"entity": "classes", "columns": ["name", "unit", "line", "methods"], "total": 3, "truncated": true, ' +
    '"inferred": 1, "elapsedMs": 12, "rows": [' +
    '{"name": "TB", "container": "", "unit": "U", "path": "U.pas", "file": "C:\\P\\U.pas", "line": 9, ' +
      '"character": 3, "inferred": false, "values": {"name": "TB", "unit": "U", "line": 9, "methods": 2}},' +
    '{"name": "TA", "container": "", "unit": "U", "path": "U.pas", "file": "C:\\P\\U.pas", "line": 4, ' +
      '"character": 3, "inferred": true, "inferredDetail": "interface", "values": {"name": "TA", "unit": "U", ' +
      '"line": 4, "methods": 10}},' +
    '{"name": "TC;x", "container": "", "unit": "V", "path": "V.pas", "file": "C:\\P\\V.pas", "line": 1, ' +
      '"character": 1, "inferred": false, "values": {"name": "TC;x", "unit": "V", "line": 1, "methods": null}}]}}';

  cCatalog = '{"enabled": true, "catalog": {"entities": [' +
    '{"name": "units", "caption": "Units", "fields": [{"name": "name", "type": "Text", "description": "Name"}, ' +
      '{"name": "usedBy", "type": "Zahl", "description": "Verwender"}], "predicates": [{"name": "uses", ' +
      '"description": "bindet ein"}]},' +
    '{"name": "classes", "caption": "Klassen", "fields": [{"name": "name", "type": "Text", "description": "Name"}, ' +
      '{"name": "methods", "type": "Zahl", "description": "Methoden"}], "predicates": [{"name": "inherits", ' +
      '"description": "erbt"}, {"name": "has attribute", "description": "Attribut"}]}], ' +
    '"keywords": ["where", "and", "or", "not", "order", "by", "asc", "desc", "limit", "like"], ' +
    '"queries": [{"name": "gross", "query": "classes where methods > 40", "description": "Große Klassen", ' +
    '"failIfAny": true}]}}';

function QuerySampleAnswer: string;
begin
  Result := cAnswer;
end;

function QuerySampleCatalog: string;
begin
  Result := cCatalog;
end;

function Names(const AAnswer: TAtlasQueryAnswer): string;
var
  mRow: TAtlasQueryRow;
begin
  Result := '';
  for mRow in AAnswer.Rows do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + mRow.Cells[0].Text;
  end;
end;

function Texts(const ASuggestions: TArray<TAtlasQuerySuggestion>): string;
var
  mItem: TAtlasQuerySuggestion;
begin
  Result := '';
  for mItem in ASuggestions do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + mItem.Text;
  end;
end;

function Catalog: TAtlasQueryCatalog;
begin
  Assert.IsTrue(TAtlasQueryCatalog.Parse(cCatalog, Result));
end;

{ TAtlasQueryModelTests }

procedure TAtlasQueryModelTests.ParsesRowsAndCells;
var
  mAnswer: TAtlasQueryAnswer;
begin
  Assert.IsTrue(TAtlasQueryAnswer.Parse(cAnswer, mAnswer));
  Assert.IsTrue(mAnswer.Enabled);
  Assert.IsFalse(mAnswer.Failed);
  Assert.AreEqual('classes', mAnswer.Entity);
  Assert.AreEqual('name,unit,line,methods', string.Join(',', mAnswer.Columns));
  Assert.AreEqual(3, mAnswer.Total);
  Assert.IsTrue(mAnswer.Truncated);
  Assert.AreEqual(Int64(12), mAnswer.ElapsedMs);
  Assert.AreEqual(Integer(3), Integer(Length(mAnswer.Rows)));
  Assert.AreEqual('C:\P\U.pas', mAnswer.Rows[1].FileName);
  Assert.AreEqual(4, mAnswer.Rows[1].Line);
  Assert.IsTrue(mAnswer.Rows[1].Inferred);
  Assert.AreEqual('interface', mAnswer.Rows[1].InferredDetail);
  Assert.IsTrue(mAnswer.Rows[1].Cells[3].IsNumber);
  Assert.AreEqual(Int64(10), mAnswer.Rows[1].Cells[3].Number);
  Assert.IsFalse(mAnswer.Rows[2].Cells[3].HasValue);
  Assert.AreEqual(3, mAnswer.ColumnOf('METHODS'));
  Assert.IsFalse(TAtlasQueryAnswer.Parse('kein json', mAnswer));
end;

procedure TAtlasQueryModelTests.ParsesErrorAndDisabled;
var
  mAnswer: TAtlasQueryAnswer;
begin
  Assert.IsTrue(TAtlasQueryAnswer.Parse('{"enabled": true, "data": {"query": "classes where methds > 3", ' +
    '"error": {"message": "Unbekanntes Feld", "column": 15, "suggestion": "methods"}}}', mAnswer));
  Assert.IsTrue(mAnswer.Failed);
  Assert.AreEqual(15, mAnswer.ErrorColumn);
  Assert.AreEqual('methods', mAnswer.Suggestion);
  Assert.IsTrue(TAtlasQueryAnswer.Parse('{"enabled": false}', mAnswer));
  Assert.IsFalse(mAnswer.Enabled);
  Assert.IsFalse(mAnswer.Failed);
end;

procedure TAtlasQueryModelTests.SortsNumbersTextAndTies;
var
  mAnswer: TAtlasQueryAnswer;
begin
  Assert.IsTrue(TAtlasQueryAnswer.Parse(cAnswer, mAnswer));
  // Zahl als Zahl (10 nach 2), ohne Wert zuletzt, auch absteigend.
  mAnswer.Sort(3, False);
  Assert.AreEqual('TB,TA,TC;x', Names(mAnswer));
  mAnswer.Sort(3, True);
  Assert.AreEqual('TA,TB,TC;x', Names(mAnswer));
  mAnswer.Sort(0, False);
  Assert.AreEqual('TA,TB,TC;x', Names(mAnswer));
  // Gleichstand in unit: nach Pfad, dann Zeile.
  mAnswer.Sort(1, True);
  Assert.AreEqual('TC;x,TA,TB', Names(mAnswer));
  mAnswer.Sort(1, False);
  Assert.AreEqual('TA,TB,TC;x', Names(mAnswer));
end;

procedure TAtlasQueryModelTests.CsvLikeServer;
var
  mAnswer: TAtlasQueryAnswer;
  mLines: TArray<string>;
begin
  Assert.IsTrue(TAtlasQueryAnswer.Parse(cAnswer, mAnswer));
  mLines := mAnswer.Csv.Split([sLineBreak]);
  Assert.AreEqual('name;unit;line;methods;path;inferred', mLines[0]);
  Assert.AreEqual('TB;U;9;2;U.pas;', mLines[1]);
  Assert.AreEqual('TA;U;4;10;U.pas;erschlossen', mLines[2]);
  Assert.AreEqual('"TC;x";V;1;;V.pas;', mLines[3]);
end;

procedure TAtlasQueryModelTests.ParsesCatalog;
var
  mCatalog: TAtlasQueryCatalog;
  mEntity: TAtlasQueryEntity;
  mSaved: TAtlasSavedQuery;
begin
  mCatalog := Catalog;
  Assert.IsTrue(mCatalog.Enabled);
  Assert.AreEqual(Integer(2), Integer(Length(mCatalog.Entities)));
  Assert.IsTrue(mCatalog.TryEntity('CLASSES', mEntity));
  Assert.AreEqual('Klassen', mEntity.Caption);
  Assert.AreEqual(Integer(2), Integer(Length(mEntity.Predicates)));
  Assert.IsTrue(mCatalog.TrySaved('Gross', mSaved));
  Assert.IsTrue(mSaved.FailIfAny);
  Assert.IsFalse(mCatalog.TrySaved('fehlt', mSaved));
end;

procedure TAtlasQueryModelTests.CompletesEntitiesFieldsAndKeywords;
var
  mStart: Integer;
begin
  Assert.AreEqual('units,classes,@gross', Texts(TAtlasQueryCompletion.Suggest(Catalog, '', 0, mStart)));
  Assert.AreEqual('classes', Texts(TAtlasQueryCompletion.Suggest(Catalog, 'cl', 2, mStart)));
  Assert.AreEqual(0, mStart);
  Assert.AreEqual('where', Texts(TAtlasQueryCompletion.Suggest(Catalog, 'classes w', 9, mStart)));
  Assert.AreEqual(8, mStart);
  Assert.AreEqual('name,methods,inherits,has attribute,not',
    Texts(TAtlasQueryCompletion.Suggest(Catalog, 'classes where ', 14, mStart)));
  Assert.AreEqual('methods', Texts(TAtlasQueryCompletion.Suggest(Catalog, 'classes where me', 16, mStart)));
  Assert.AreEqual('=,<>,<,>,<=,>=,like,not like',
    Texts(TAtlasQueryCompletion.Suggest(Catalog, 'classes where methods ', 22, mStart)));
  Assert.AreEqual('', Texts(TAtlasQueryCompletion.Suggest(Catalog, 'classes where methods > ', 24, mStart)));
  Assert.AreEqual('and,or,order,limit',
    Texts(TAtlasQueryCompletion.Suggest(Catalog, 'classes where methods > 4 ', 26, mStart)));
  Assert.AreEqual('by', Texts(TAtlasQueryCompletion.Suggest(Catalog, 'classes order ', 14, mStart)));
  Assert.AreEqual('name,methods', Texts(TAtlasQueryCompletion.Suggest(Catalog, 'classes order by ', 17, mStart)));
  // Text in Anführungszeichen zählt als ein Wert.
  Assert.AreEqual('and', Texts(TAtlasQueryCompletion.Suggest(Catalog, 'classes where name like ''T a*'' a', 32,
    mStart)));
  // Mitten im Text: nur bis zur Schreibmarke.
  Assert.AreEqual('units', Texts(TAtlasQueryCompletion.Suggest(Catalog, 'un where', 2, mStart)));
end;

procedure TAtlasQueryModelTests.CompletesSymbolNamesAfterPredicates;
var
  mStart: Integer;
  mPrefix, mPredicate: string;
begin
  Assert.IsTrue(TAtlasQueryCompletion.SymbolPredicate('classes where inherits TFo', 26, mStart, mPrefix, mPredicate));
  Assert.AreEqual('inherits', mPredicate);
  Assert.AreEqual('TFo', mPrefix);
  Assert.AreEqual(23, mStart);
  // Kein Vorschlag aus dem Katalog hinter inherits (dort steht ein Typ, keine Verknüpfung).
  Assert.AreEqual('', Texts(TAtlasQueryCompletion.Suggest(Catalog, 'classes where inherits ', 23, mStart)));
  Assert.IsTrue(TAtlasQueryCompletion.SymbolPredicate('classes where has attribute ', 28, mStart, mPrefix,
    mPredicate));
  Assert.AreEqual('attribute', mPredicate);
  Assert.AreEqual('', mPrefix);
  Assert.IsTrue(TAtlasQueryCompletion.SymbolPredicate('methods where calls Re', 22, mStart, mPrefix, mPredicate));
  Assert.AreEqual('calls', mPredicate);
  Assert.IsFalse(TAtlasQueryCompletion.SymbolPredicate('classes where methods > ', 24, mStart, mPrefix, mPredicate));
  Assert.IsFalse(TAtlasQueryCompletion.SymbolPredicate('uses', 4, mStart, mPrefix, mPredicate));
end;

function Symbol(const AName: string; AKind: Integer): TAtlasSymbol;
begin
  Result := Default(TAtlasSymbol);
  Result.Name := AName;
  Result.Kind := AKind;
end;

procedure TAtlasQueryModelTests.SymbolNamesFitPredicate;
var
  mSymbols: TArray<TAtlasSymbol>;
begin
  // Klasse, Interface, Methode, Routine, Attributklasse, Record.
  mSymbols := TArray<TAtlasSymbol>.Create(Symbol('TForm1', 5), Symbol('IWerkzeug', 11), Symbol('Rechne', 6),
    Symbol('Hilfe', 12), Symbol('WeakAttribute', 5), Symbol('TPunkt', 23));
  Assert.AreEqual('TForm1,IWerkzeug,WeakAttribute,TPunkt',
    string.Join(',', TAtlasQueryCompletion.SymbolNames('inherits', mSymbols)));
  Assert.AreEqual('IWerkzeug', string.Join(',', TAtlasQueryCompletion.SymbolNames('implements', mSymbols)));
  Assert.AreEqual('Rechne,Hilfe', string.Join(',', TAtlasQueryCompletion.SymbolNames('calls', mSymbols)));
  Assert.AreEqual('WeakAttribute', string.Join(',', TAtlasQueryCompletion.SymbolNames('attribute', mSymbols)));
  Assert.AreEqual(0, Integer(Length(TAtlasQueryCompletion.SymbolNames('uses', mSymbols))));
end;

procedure TAtlasQueryModelTests.SavedQueryReplacesSameName;
var
  mQuery: TAtlasSavedQuery;
  mValue: TJSONValue;
  mList: TJSONArray;
begin
  Assert.IsTrue(TAtlasSavedQueries.ValidName('grosse-klassen.v2_a'));
  Assert.IsFalse(TAtlasSavedQueries.ValidName('mit leer'));
  Assert.IsFalse(TAtlasSavedQueries.ValidName(''));
  mQuery := Default(TAtlasSavedQuery);
  mQuery.Name := 'Gross';
  mQuery.Query := 'classes where methods > 50';
  mQuery.FailIfAny := True;
  mValue := TJSONObject.ParseJSONValue(TAtlasSavedQueries.WithQuery('[{"name": "a", "query": "q"}, ' +
    '{"name": "gross", "query": "alt"}]', mQuery, 'error', '{name} hat {methods} Methoden'));
  try
    mList := mValue as TJSONArray;
    Assert.AreEqual(2, mList.Count);
    Assert.AreEqual('a', (mList.Items[0] as TJSONObject).GetValue<string>('name'));
    Assert.AreEqual('classes where methods > 50', (mList.Items[1] as TJSONObject).GetValue<string>('query'));
    Assert.IsTrue((mList.Items[1] as TJSONObject).GetValue<Boolean>('failIfAny'));
    Assert.AreEqual('error', (mList.Items[1] as TJSONObject).GetValue<string>('severity'));
    Assert.AreEqual('{name} hat {methods} Methoden', (mList.Items[1] as TJSONObject).GetValue<string>('message'));
  finally
    mValue.Free;
  end;
  mQuery.FailIfAny := False;
  Assert.AreEqual('[{"name":"Gross","query":"classes where methods > 50"}]',
    TAtlasSavedQueries.WithQuery('', mQuery, '', ''));
end;

procedure TAtlasQueryModelTests.RequestParams;
begin
  Assert.AreEqual('{"uri":"file:///C:/P/A.dproj","query":"units where usedBy = 0","limit":500,"format":"json"}',
    TAtlasQueryRequest.Params('file:///C:/P/A.dproj', 'units where usedBy = 0', 500));
  Assert.AreEqual('{"uri":"file:///C:/P/A.dproj"}', TAtlasQueryRequest.CatalogParams('file:///C:/P/A.dproj'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQueryModelTests);

end.
