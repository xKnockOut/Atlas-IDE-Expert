unit Atlas.Common.Query.Output.Tests;

// Tests der Ausgabe (Markdown, JSON, CSV, Text, Fehler mit Marke, Meldung mit
// Platzhaltern) und des Dienstes mit Zwischenspeicher je Index-Generation
// (#1351).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TQueryOutputTests = class
  public
    [Test]
    procedure ParsesFormats;
    [Test]
    procedure MarkdownHasTableAndInferredMark;
    [Test]
    procedure JsonIsValidAndTyped;
    [Test]
    procedure JsonCarriesError;
    [Test]
    procedure CsvQuotesSeparators;
    [Test]
    procedure TextAlignsColumns;
    [Test]
    procedure ErrorTextPointsAtColumn;
    [Test]
    procedure MessageReplacesPlaceholders;
    [Test]
    procedure PlaceholdersInOrder;
  end;

  [TestFixture]
  TQueryServiceTests = class
  public
    [Test]
    procedure CachesPerGeneration;
    [Test]
    procedure ScopeChangeComputesAgain;
    [Test]
    procedure WithoutSourceReportsError;
    [Test]
    procedure CancelledIsNotCached;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Query.Contract,
  Atlas.Common.Query.Engine,
  Atlas.Common.Query.Service,
  Atlas.Common.Query.Output,
  Atlas.Common.Query.Engine.Tests;

function Run(const AQuery: string): TQueryResult;
begin
  Result := TCodeQueryEngine.Run(QueryTestSource, TQueryRequest.Create(AQuery, 0), nil);
end;

function SampleResult: TQueryResult;
var
  mRow: TQueryRow;
begin
  Result := Default(TQueryResult);
  Result.Query := 'classes where name like ''T*''';
  Result.Entity := 'classes';
  Result.Columns := TArray<string>.Create('name', 'unit', 'methods');
  mRow := Default(TQueryRow);
  mRow.Name := 'TA;B';
  mRow.UnitName := 'U"1';
  mRow.Path := 'U1.pas';
  mRow.Values := TArray<TQueryValue>.Create(TQueryValue.OfText('TA;B'), TQueryValue.OfText('U"1'),
    TQueryValue.OfNumber(12));
  mRow.Inferred := True;
  mRow.InferredDetail := 'Interface';
  Result.Rows := TArray<TQueryRow>.Create(mRow);
  Result.Total := 1;
  Result.InferredCount := 1;
end;

{ TQueryOutputTests }

procedure TQueryOutputTests.ParsesFormats;
var
  mFormat: TQueryOutputFormat;
begin
  Assert.IsTrue(TQueryOutput.TryParseFormat('', TQueryOutputFormat.Text, mFormat));
  Assert.IsTrue(mFormat = TQueryOutputFormat.Text);
  Assert.IsTrue(TQueryOutput.TryParseFormat('CSV', TQueryOutputFormat.Text, mFormat));
  Assert.IsTrue(mFormat = TQueryOutputFormat.Csv);
  Assert.IsTrue(TQueryOutput.TryParseFormat('json', TQueryOutputFormat.Text, mFormat));
  Assert.IsTrue(mFormat = TQueryOutputFormat.Json);
  Assert.IsFalse(TQueryOutput.TryParseFormat('sarif', TQueryOutputFormat.Markdown, mFormat));
  Assert.IsTrue(mFormat = TQueryOutputFormat.Markdown);
end;

procedure TQueryOutputTests.MarkdownHasTableAndInferredMark;
var
  mText: string;
begin
  mText := TQueryOutput.Markdown(SampleResult);
  Assert.IsTrue(mText.Contains('| name | unit | methods | Datei |'), mText);
  Assert.IsTrue(mText.Contains('TA;B (erschlossen)'), mText);
  Assert.IsTrue(mText.Contains('1 Treffer, 1 davon erschlossen'), mText);
  Assert.IsTrue(mText.Contains('U1.pas:1'), mText);
end;

procedure TQueryOutputTests.JsonIsValidAndTyped;
var
  mValue: TJSONValue;
  mRows: TJSONArray;
  mRow: TJSONObject;
begin
  mValue := TJSONObject.ParseJSONValue(TQueryOutput.Json(Run('classes where methods > 0 order by name')));
  try
    Assert.IsNotNull(mValue);
    Assert.AreEqual('classes', (mValue as TJSONObject).GetValue<string>('entity'));
    mRows := (mValue as TJSONObject).GetValue<TJSONArray>('rows');
    Assert.IsTrue(mRows.Count > 0);
    mRow := mRows.Items[0] as TJSONObject;
    Assert.AreEqual('TBasis', mRow.GetValue<string>('name'));
    Assert.IsTrue(mRow.GetValue<TJSONObject>('values').GetValue('methods') is TJSONNumber);
  finally
    mValue.Free;
  end;
end;

procedure TQueryOutputTests.JsonCarriesError;
var
  mValue: TJSONValue;
  mError: TJSONObject;
begin
  mValue := TJSONObject.ParseJSONValue(TQueryOutput.Json(Run('classes where methds > 3')));
  try
    Assert.IsNotNull(mValue);
    mError := (mValue as TJSONObject).GetValue<TJSONObject>('error');
    Assert.AreEqual(15, mError.GetValue<Integer>('column'));
    Assert.AreEqual('methods', mError.GetValue<string>('suggestion'));
  finally
    mValue.Free;
  end;
end;

procedure TQueryOutputTests.CsvQuotesSeparators;
var
  mLines: TArray<string>;
begin
  mLines := TQueryOutput.Csv(SampleResult).Split([sLineBreak]);
  Assert.AreEqual('name;unit;methods;path;inferred', mLines[0]);
  Assert.AreEqual('"TA;B";"U""1";12;U1.pas;erschlossen', mLines[1]);
end;

procedure TQueryOutputTests.TextAlignsColumns;
var
  mLines: TArray<string>;
begin
  mLines := TQueryOutput.Text(SampleResult).Split([sLineBreak]);
  Assert.AreEqual(Integer(mLines[0].IndexOf('unit')), Integer(mLines[1].IndexOf('U"1')));
  Assert.IsTrue(mLines[1].EndsWith('(erschlossen)'), mLines[1]);
end;

procedure TQueryOutputTests.ErrorTextPointsAtColumn;
var
  mLines: TArray<string>;
begin
  mLines := TQueryOutput.ErrorText(Run('classes where methds > 3')).Split([sLineBreak]);
  Assert.IsTrue(mLines[0].StartsWith('Spalte 15: '), mLines[0]);
  Assert.IsTrue(mLines[0].Contains('methods'), mLines[0]);
  Assert.AreEqual('  classes where methds > 3', mLines[1]);
  Assert.AreEqual(Integer(16), Integer(mLines[2].IndexOf('^')));
end;

procedure TQueryOutputTests.MessageReplacesPlaceholders;
var
  mResult: TQueryResult;
begin
  mResult := SampleResult;
  Assert.AreEqual('TA;B hat 12 Methoden ({unbekannt}) in U1.pas',
    mResult.Message('{name} hat {methods} Methoden ({unbekannt}) in {path}', mResult.Rows[0]));
  Assert.AreEqual('TA;B: Treffer der Abfrage classes where name like ''T*''',
    mResult.Message('', mResult.Rows[0]));
end;

procedure TQueryOutputTests.PlaceholdersInOrder;
begin
  Assert.AreEqual('name,methods,x', string.Join(',', TQueryResult.Placeholders('{name} hat {methods} {x} {offen')));
  Assert.AreEqual(Integer(0), Integer(Length(TQueryResult.Placeholders('ohne'))));
end;

{ TQueryServiceTests }

type
  TSourceBox = class
    Source: TQuerySource;
    Available: Boolean;
  end;

function ServiceOf(ABox: TSourceBox): TCodeQueryService;
begin
  Result := TCodeQueryService.Create(
    function(out ASource: TQuerySource): Boolean
    begin
      ASource := ABox.Source;
      Result := ABox.Available;
    end);
end;

procedure TQueryServiceTests.CachesPerGeneration;
var
  mBox: TSourceBox;
  mService: TCodeQueryService;
  mQueries: ICodeQueries;
  mFirst, mSecond: TQueryResult;
begin
  mBox := TSourceBox.Create;
  try
    mBox.Source := QueryTestSource;
    mBox.Available := True;
    mService := ServiceOf(mBox);
    mQueries := mService;
    mFirst := mQueries.Execute(TQueryRequest.Create('classes where methods > 0', 0));
    mSecond := mQueries.Execute(TQueryRequest.Create('classes where methods > 0', 0));
    Assert.AreEqual(1, mService.Computations);
    Assert.AreEqual(RowNames(mFirst), RowNames(mSecond));
    // Anderes limit ist eine andere Anfrage.
    mQueries.Execute(TQueryRequest.Create('classes where methods > 0', 1));
    Assert.AreEqual(2, mService.Computations);
    // Neuer Index-Stand: neu rechnen.
    mBox.Source.Index.AddUnit(TIndexExtractor.ExtractText('unit Neu; interface implementation end.', 'C:\P\Neu.pas',
      nil));
    mQueries.Execute(TQueryRequest.Create('classes where methods > 0', 0));
    Assert.AreEqual(3, mService.Computations);
  finally
    mQueries := nil;
    mBox.Free;
  end;
end;

procedure TQueryServiceTests.ScopeChangeComputesAgain;
var
  mBox: TSourceBox;
  mService: TCodeQueryService;
  mQueries: ICodeQueries;
begin
  mBox := TSourceBox.Create;
  try
    mBox.Source := QueryTestSource;
    mBox.Available := True;
    mService := ServiceOf(mBox);
    mQueries := mService;
    mQueries.Execute(TQueryRequest.Create('units where name like ''*''', 0));
    mBox.Source.Files := TArray<string>.Create('C:\P\Main.pas');
    Assert.AreEqual('Main', RowNames(mQueries.Execute(TQueryRequest.Create('units where name like ''*''', 0))));
    Assert.AreEqual(2, mService.Computations);
  finally
    mQueries := nil;
    mBox.Free;
  end;
end;

procedure TQueryServiceTests.WithoutSourceReportsError;
var
  mBox: TSourceBox;
  mQueries: ICodeQueries;
  mResult: TQueryResult;
begin
  mBox := TSourceBox.Create;
  try
    mBox.Available := False;
    mQueries := ServiceOf(mBox);
    mResult := mQueries.Execute(TQueryRequest.Create('units where name = X', 0));
    Assert.IsTrue(mResult.Failed);
    Assert.AreEqual('Kein Projekt geladen', mResult.Error);
  finally
    mQueries := nil;
    mBox.Free;
  end;
end;

procedure TQueryServiceTests.CancelledIsNotCached;
var
  mBox: TSourceBox;
  mService: TCodeQueryService;
  mQueries: ICodeQueries;
  mCancel: Boolean;
begin
  mBox := TSourceBox.Create;
  try
    mBox.Source := QueryTestSource;
    mBox.Available := True;
    mCancel := True;
    mBox.Source.Cancelled :=
      function: Boolean
      begin
        Result := mCancel;
      end;
    mService := ServiceOf(mBox);
    mQueries := mService;
    Assert.IsTrue(mQueries.Execute(TQueryRequest.Create('classes where methods > 0', 0)).Failed);
    mCancel := False;
    Assert.IsFalse(mQueries.Execute(TQueryRequest.Create('classes where methods > 0', 0)).Failed);
    Assert.AreEqual(1, mService.Computations);
  finally
    mQueries := nil;
    mBox.Source := Default(TQuerySource);
    mBox.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TQueryOutputTests);
  TDUnitX.RegisterTestFixture(TQueryServiceTests);

end.
