unit Atlas.Common.Editing.DataFieldNames.Tests;

// Tests für Feld- und Parameternamen in FieldByName, FindField und ParamByName (#461).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDataFieldNamesTests = class
  public
    [Test]
    procedure FindsCallAtCursor;
    [Test]
    procedure IgnoresOtherStringsAndDataModules;
    [Test]
    procedure SplitsSelectList;
    [Test]
    procedure CollectsFieldsFromForm;
    [Test]
    procedure CollectsParamsFromForm;
    [Test]
    procedure ShortensSql;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Editing.DataFieldNames;

const
  Form =
    'object frmOrders: TfrmOrders'#13#10 +
    '  object qryOrders: TSQLQuery'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''select O.ORDER_ID, O.CUSTOMER_ID, O.CURRENCY as CUR,'''#13#10 +
    '      ''  sum(P.AMOUNT) TOTAL, count(*)'''#13#10 +
    '      ''from ORDERS O join POS P on P.ORDER_ID = O.ORDER_ID'''#13#10 +
    '      ''where O.CUSTOMER_ID = :Customer and O.STATE = :State'')'#13#10 +
    '    Params = <'#13#10 +
    '      item'#13#10 +
    '        DataType = ftInteger'#13#10 +
    '        Name = ''Customer'''#13#10 +
    '        ParamType = ptInput'#13#10 +
    '      end'#13#10 +
    '      item'#13#10 +
    '        DataType = ftString'#13#10 +
    '        Name = ''Extra'''#13#10 +
    '        ParamType = ptInput'#13#10 +
    '      end>'#13#10 +
    '    object qryOrdersCUSTOMER_ID: TIntegerField'#13#10 +
    '      FieldName = ''CUSTOMER_ID'''#13#10 +
    '    end'#13#10 +
    '    object qryOrdersNOTE: TWideStringField'#13#10 +
    '      FieldName = ''NOTE'''#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object qryAll: TSQLQuery'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''select * from ORDERS'')'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

function Names(const AItems: TArray<TDataName>): string;
var
  Item: TDataName;
begin
  Result := '';
  for Item in AItems do
  begin
    if Result <> '' then
      Result := Result + '|';
    Result := Result + Item.Name;
    if Item.TypeName <> '' then
      Result := Result + ':' + Item.TypeName;
  end;
end;

procedure TDataFieldNamesTests.FindsCallAtCursor;
var
  Call: TDataNameCall;
  Line: string;
begin
  Line := '  Total := qryOrders.FieldByName(''cu'').AsInteger;';
  // Cursor hinter "cu".
  Assert.IsTrue(TDataFieldNames.CallAt(Line, 36, Call));
  Assert.AreEqual('qryOrders', Call.DataSet);
  Assert.AreEqual('FieldByName', Call.Method);
  Assert.IsTrue(Call.Kind = TDataNameKind.Field);
  Assert.AreEqual(34, Call.ContentStart);
  Assert.AreEqual(36, Call.ContentEnd);
  Assert.AreEqual('cu', Call.Content);
  // Direkt hinter dem öffnenden Anführungszeichen, ohne schließendes.
  Line := '  Self.qryOrders.Params.ParamByName(''';
  Assert.IsTrue(TDataFieldNames.CallAt(Line, Length(Line), Call));
  Assert.AreEqual('qryOrders', Call.DataSet);
  Assert.IsTrue(Call.Kind = TDataNameKind.Param);
  Assert.AreEqual(Length(Line), Call.ContentStart);
  Assert.AreEqual(Length(Line), Call.ContentEnd);
  Line := '  if qryOrders.FindField(''NO'') = nil then';
  Assert.IsTrue(TDataFieldNames.CallAt(Line, 26, Call));
  Assert.AreEqual('FindField', Call.Method);
  Assert.AreEqual('NO', Call.Content);
end;

procedure TDataFieldNamesTests.IgnoresOtherStringsAndDataModules;
var
  Call: TDataNameCall;
begin
  // Zweites Argument, anderer Aufruf, Datenmodul, Cursor hinter dem String.
  Assert.IsFalse(TDataFieldNames.CallAt('  Log(''cu'');', 8, Call));
  Assert.IsFalse(TDataFieldNames.CallAt('  dmMain.qryOrders.FieldByName(''cu'');', 34, Call));
  Assert.IsFalse(TDataFieldNames.CallAt('  qryOrders.FieldByName(''cu'').AsString := ''x'';', 30, Call));
  Assert.IsFalse(TDataFieldNames.CallAt('  FieldByName(''cu'');', 17, Call));
  Assert.IsFalse(TDataFieldNames.CallAt('  // qryOrders.FieldByName(''cu'');', 30, Call));
end;

procedure TDataFieldNamesTests.SplitsSelectList;
var
  Star: Boolean;
begin
  Assert.AreEqual('ORDER_ID|CUSTOMER_ID|CUR|TOTAL|Name', string.Join('|', TDataFieldNames.SelectColumns(
    'select distinct O.ORDER_ID, O.CUSTOMER_ID, O.CURRENCY as CUR, sum(P.AMOUNT) TOTAL, count(*), ' +
    '"Name", (select max(X) from Y) from ORDERS O', Star)));
  Assert.IsFalse(Star);
  Assert.AreEqual('A', string.Join('|', TDataFieldNames.SelectColumns(
    '-- Kommentar'#10'select first 10 T.*, A /* B */ from T', Star)));
  Assert.IsTrue(Star);
  Assert.AreEqual('Nr', string.Join('|', TDataFieldNames.SelectColumns(
    'select case when A = 1 then ''x'' else ''y'' end, [Nr] from T', Star)));
  Assert.AreEqual(0, Integer(Length(TDataFieldNames.SelectColumns('update T set A = 1', Star))));
end;

procedure TDataFieldNamesTests.CollectsFieldsFromForm;
var
  Sql: string;
  Found: Boolean;
begin
  // Persistente Felder zuerst, dann die Spalten der Anweisung ohne Doppelte.
  Assert.AreEqual('CUSTOMER_ID:Integer|NOTE:WideString|ORDER_ID|CUR|TOTAL', Names(
    TDataFieldNames.FromForm(Form, 'qryOrders', TDataNameKind.Field, Sql, Found)));
  Assert.IsTrue(Found);
  Assert.IsTrue(Sql.StartsWith('select O.ORDER_ID'));
  // select * ohne Schema-Cache: keine Spalten.
  Assert.AreEqual('', Names(TDataFieldNames.FromForm(Form, 'qryAll', TDataNameKind.Field, Sql, Found)));
  Assert.IsTrue(Found);
  // Zur Laufzeit erzeugt: nicht in der Formulardatei.
  Assert.AreEqual('', Names(TDataFieldNames.FromForm(Form, 'qryLaufzeit', TDataNameKind.Field, Sql, Found)));
  Assert.IsFalse(Found);
end;

procedure TDataFieldNamesTests.CollectsParamsFromForm;
var
  Sql: string;
  Found: Boolean;
begin
  // Platzhalter der Anweisung, Typ aus der Params-Sammlung, dann übrige Einträge der Sammlung.
  Assert.AreEqual('Customer:Integer|State|Extra:String', Names(
    TDataFieldNames.FromForm(Form, 'qryOrders', TDataNameKind.Param, Sql, Found)));
end;

procedure TDataFieldNamesTests.ShortensSql;
var
  Sql: string;
  Found: Boolean;
begin
  Assert.AreEqual('select A from T', TDataFieldNames.ShortSql('select A'#13#10'  from T'));
  Assert.AreEqual('select A, B…', TDataFieldNames.ShortSql('select A, B, C from T', 12));
  Assert.IsTrue(TDataFieldNames.Contains(TDataFieldNames.FromForm(Form, 'qryOrders', TDataNameKind.Field,
    Sql, Found), 'customer_id'));
end;

initialization
  TDUnitX.RegisterTestFixture(TDataFieldNamesTests);

end.
