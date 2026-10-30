unit Atlas.Common.Lsp.Query.Tests;

// atlas/query, atlas/queryCatalog und Befehl atlas.query (#1351) sowie Aufrufer
// und Aufgerufene über die Aufrufhierarchie (TLspQuery.Calls).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspQueryTests = class
  public
    [Test]
    procedure RequestAnswersJsonRows;
    [Test]
    procedure RequestReportsErrorWithColumn;
    [Test]
    procedure DisabledAnswersEnabledFalse;
    [Test]
    procedure TextFormatsAndInvalidFormat;
    [Test]
    procedure CatalogListsEntitiesAndSavedQueries;
    [Test]
    procedure CommandTakesUriAndOptions;
    [Test]
    procedure CallsFromCallHierarchy;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Query.Contract,
  Atlas.Common.Query.Service,
  Atlas.Common.Query.Engine,
  Atlas.Common.Query.Engine.Tests,
  Atlas.Common.Lsp.Query;

const
  cHauptFile = 'C:\W\Haupt.pas';
  cWerkzeugFile = 'C:\W\Werkzeug.pas';

  cWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'procedure Rechne;'#10 +
    'implementation'#10 +
    'procedure Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  cHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werkzeug;'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Bar;'#10 +
    '    procedure Baz;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar;'#10 +
    'begin'#10 +
    '  Rechne;'#10 +
    '  Baz;'#10 +
    '  Rechne;'#10 +
    'end;'#10 +
    'procedure TFoo.Baz;'#10 +
    'begin'#10 +
    '  Rechne;'#10 +
    'end;'#10 +
    'end.';

function NewQuery(const ASettingsJson: string): TLspQuery;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  mSettings := TConfigurationParser.Parse(ASettingsJson, mIssues);
  Result := TLspQuery.Create(
    TCodeQueryService.Create(
      function(out ASource: TQuerySource): Boolean
      begin
        ASource := QueryTestSource;
        Result := True;
      end),
    function(const AFileName: string; out ASettings: TServerSettings; out ARoot: string): Boolean
    begin
      ASettings := mSettings;
      ARoot := 'C:\P';
      Result := True;
    end);
end;

function Params(const AJson: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(AJson);
end;

function Ask(AQuery: TLspQuery; const AJson: string): TJSONObject;
var
  mParams: TJSONValue;
begin
  mParams := Params(AJson);
  try
    Result := AQuery.Request(mParams, nil) as TJSONObject;
  finally
    mParams.Free;
  end;
end;

{ TLspQueryTests }

procedure TLspQueryTests.RequestAnswersJsonRows;
var
  mQuery: TLspQuery;
  mAnswer: TJSONObject;
  mRows: TJSONArray;
begin
  mQuery := NewQuery('{}');
  try
    mAnswer := Ask(mQuery, '{"query": "classes where methods > 0 order by name", "limit": 1}');
    try
      Assert.IsTrue(mAnswer.GetValue<Boolean>('enabled'));
      Assert.AreEqual('C:\P', mAnswer.GetValue<string>('root'));
      Assert.AreEqual('json', mAnswer.GetValue<string>('format'));
      mRows := mAnswer.GetValue<TJSONArray>('data.rows');
      Assert.AreEqual(1, mRows.Count);
      Assert.AreEqual('TBasis', (mRows.Items[0] as TJSONObject).GetValue<string>('name'));
      Assert.IsTrue(mAnswer.GetValue<Integer>('data.total') > 1);
      Assert.IsTrue(mAnswer.GetValue<Boolean>('data.truncated'));
    finally
      mAnswer.Free;
    end;
  finally
    mQuery.Free;
  end;
end;

procedure TLspQueryTests.RequestReportsErrorWithColumn;
var
  mQuery: TLspQuery;
  mAnswer: TJSONObject;
begin
  mQuery := NewQuery('{}');
  try
    mAnswer := Ask(mQuery, '{"query": "classes where methds > 3"}');
    try
      Assert.AreEqual(15, mAnswer.GetValue<Integer>('data.error.column'));
      Assert.AreEqual('methods', mAnswer.GetValue<string>('data.error.suggestion'));
    finally
      mAnswer.Free;
    end;
  finally
    mQuery.Free;
  end;
end;

procedure TLspQueryTests.DisabledAnswersEnabledFalse;
var
  mQuery: TLspQuery;
  mAnswer: TJSONObject;
  mValue: TJSONValue;
begin
  mQuery := NewQuery('{"query": {"enabled": false}}');
  try
    mAnswer := Ask(mQuery, '{"query": "classes where methods > 0"}');
    try
      Assert.IsFalse(mAnswer.GetValue<Boolean>('enabled'));
      Assert.IsNull(mAnswer.GetValue('data'));
    finally
      mAnswer.Free;
    end;
    mValue := mQuery.Catalog(nil);
    try
      Assert.IsFalse((mValue as TJSONObject).GetValue<Boolean>('enabled'));
      Assert.IsNull((mValue as TJSONObject).GetValue('catalog'));
    finally
      mValue.Free;
    end;
  finally
    mQuery.Free;
  end;
end;

procedure TLspQueryTests.TextFormatsAndInvalidFormat;
var
  mQuery: TLspQuery;
  mAnswer: TJSONObject;
  mRaised: Boolean;
begin
  mQuery := NewQuery('{}');
  try
    mAnswer := Ask(mQuery, '{"query": "classes where name = TBasis", "format": "csv"}');
    try
      Assert.AreEqual('csv', mAnswer.GetValue<string>('format'));
      Assert.IsTrue(mAnswer.GetValue<string>('text').StartsWith('name;unit;line;path;inferred'),
        mAnswer.GetValue<string>('text'));
    finally
      mAnswer.Free;
    end;
    mRaised := False;
    try
      Ask(mQuery, '{"query": "classes where name = TBasis", "format": "sarif"}').Free;
    except
      on E: EJsonRpcError do
        mRaised := True;
    end;
    Assert.IsTrue(mRaised);
  finally
    mQuery.Free;
  end;
end;

procedure TLspQueryTests.CatalogListsEntitiesAndSavedQueries;
var
  mQuery: TLspQuery;
  mValue: TJSONValue;
  mCatalog: TJSONObject;
  mEntities, mQueries: TJSONArray;
begin
  mQuery := NewQuery('{"queries": [{"name": "gross", "query": "classes where methods > 40", ' +
    '"description": "Große Klassen"}]}');
  try
    mValue := mQuery.Catalog(nil);
    try
      mCatalog := (mValue as TJSONObject).GetValue<TJSONObject>('catalog');
      mEntities := mCatalog.GetValue<TJSONArray>('entities');
      Assert.AreEqual(9, mEntities.Count);
      Assert.AreEqual('units', (mEntities.Items[0] as TJSONObject).GetValue<string>('name'));
      Assert.IsTrue((mEntities.Items[0] as TJSONObject).GetValue<TJSONArray>('fields').Count > 3);
      mQueries := mCatalog.GetValue<TJSONArray>('queries');
      Assert.AreEqual(1, mQueries.Count);
      Assert.AreEqual('Große Klassen', (mQueries.Items[0] as TJSONObject).GetValue<string>('description'));
      Assert.IsTrue(mCatalog.GetValue<TJSONArray>('keywords').Count > 5);
    finally
      mValue.Free;
    end;
  finally
    mQuery.Free;
  end;
end;

procedure TLspQueryTests.CommandTakesUriAndOptions;
var
  mQuery: TLspQuery;
  mArguments: TJSONValue;
  mAnswer: TJSONValue;
begin
  mQuery := NewQuery('{}');
  try
    mArguments := TJSONObject.ParseJSONValue('["file:///C:/P/Main.pas", {"query": "forms where components > 0", ' +
      '"format": "text"}]');
    try
      mAnswer := mQuery.Execute(mArguments as TJSONArray);
      try
        Assert.IsTrue((mAnswer as TJSONObject).GetValue<string>('text').Contains('TMainForm'));
      finally
        mAnswer.Free;
      end;
    finally
      mArguments.Free;
    end;
  finally
    mQuery.Free;
  end;
end;

function ReadWorkFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cHauptFile) then
    AText := cHaupt
  else if SameText(AFileName, cWerkzeugFile) then
    AText := cWerkzeug
  else
    Result := False;
end;

procedure TLspQueryTests.CallsFromCallHierarchy;
var
  mSource: TQuerySource;
  mResult: TQueryResult;
begin
  mSource := Default(TQuerySource);
  mSource.Index := TSymbolIndex.Create;
  mSource.Index.AddUnit(TIndexExtractor.ExtractText(cWerkzeug, cWerkzeugFile, nil));
  mSource.Index.AddUnit(TIndexExtractor.ExtractText(cHaupt, cHauptFile, nil));
  mSource.Root := 'C:\W';
  mSource.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadWorkFile(AFileName, AText);
    end;
  mSource.Calls := TLspQuery.Calls(mSource.Index, nil, nil, TArray<string>.Create(cHauptFile, cWerkzeugFile),
    ReadWorkFile, TReferenceSettings.Default);
  // Rechne wird von TFoo.Bar und TFoo.Baz aufgerufen; TFoo.Bar ruft Rechne und Baz.
  mResult := TCodeQueryEngine.Run(mSource, TQueryRequest.Create('routines where callers = 2', 0), nil);
  Assert.AreEqual('Rechne', RowNames(mResult));
  mResult := TCodeQueryEngine.Run(mSource, TQueryRequest.Create('methods where callees = 2', 0), nil);
  Assert.AreEqual('TFoo.Bar', RowNames(mResult));
  mResult := TCodeQueryEngine.Run(mSource, TQueryRequest.Create('methods where calls Rechne order by name', 0), nil);
  Assert.AreEqual('TFoo.Bar,TFoo.Baz', RowNames(mResult));
  mResult := TCodeQueryEngine.Run(mSource, TQueryRequest.Create('methods where callers = 0', 0), nil);
  Assert.AreEqual('TFoo.Bar', RowNames(mResult));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspQueryTests);

end.
