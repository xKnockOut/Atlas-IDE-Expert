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
    procedure FindsDataModuleCall;
    [Test]
    procedure LooksUpOwnFormAndDataModules;
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
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.DataFieldNames;

const
  cForm =
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
  mItem: TDataName;
begin
  Result := '';
  for mItem in AItems do
  begin
    if Result <> '' then
    begin
      Result := Result + '|';
    end;
    Result := Result + mItem.Name;
    if mItem.TypeName <> '' then
    begin
      Result := Result + ':' + mItem.TypeName;
    end;
  end;
end;

procedure TDataFieldNamesTests.FindsCallAtCursor;
var
  mCall: TDataNameCall;
  mLine: string;
begin
  mLine := '  Total := qryOrders.FieldByName(''cu'').AsInteger;';
  // Cursor hinter "cu".
  Assert.IsTrue(TDataFieldNames.CallAt(mLine, 36, mCall));
  Assert.AreEqual('qryOrders', mCall.DataSet);
  Assert.AreEqual('FieldByName', mCall.Method);
  Assert.AreEqual<TDataNameKind>(TDataNameKind.Field, mCall.Kind);
  Assert.AreEqual(34, mCall.ContentStart);
  Assert.AreEqual(36, mCall.ContentEnd);
  Assert.AreEqual('cu', mCall.Content);
  // Direkt hinter dem öffnenden Anführungszeichen, ohne schließendes.
  mLine := '  Self.qryOrders.Params.ParamByName(''';
  Assert.IsTrue(TDataFieldNames.CallAt(mLine, Length(mLine), mCall));
  Assert.AreEqual('qryOrders', mCall.DataSet);
  Assert.AreEqual<TDataNameKind>(TDataNameKind.Param, mCall.Kind);
  Assert.AreEqual(Integer(Length(mLine)), mCall.ContentStart);
  Assert.AreEqual(Integer(Length(mLine)), mCall.ContentEnd);
  mLine := '  if qryOrders.FindField(''NO'') = nil then';
  Assert.IsTrue(TDataFieldNames.CallAt(mLine, 26, mCall));
  Assert.AreEqual('FindField', mCall.Method);
  Assert.AreEqual('NO', mCall.Content);
end;

procedure TDataFieldNamesTests.IgnoresOtherStringsAndDataModules;
var
  mCall: TDataNameCall;
begin
  // Zweites Argument, anderer Aufruf, lange Kette, Cursor hinter dem String.
  Assert.IsFalse(TDataFieldNames.CallAt('  Log(''cu'');', 8, mCall));
  Assert.IsFalse(TDataFieldNames.CallAt('  App.dmMain.qryOrders.FieldByName(''cu'');', 38, mCall));
  Assert.IsFalse(TDataFieldNames.CallAt('  qryOrders.FieldByName(''cu'').AsString := ''x'';', 30, mCall));
  Assert.IsFalse(TDataFieldNames.CallAt('  FieldByName(''cu'');', 17, mCall));
  Assert.IsFalse(TDataFieldNames.CallAt('  // qryOrders.FieldByName(''cu'');', 30, mCall));
end;

procedure TDataFieldNamesTests.FindsDataModuleCall;
var
  mCall: TDataNameCall;
begin
  Assert.IsTrue(TDataFieldNames.CallAt('  dmMain.qryOrders.FieldByName(''cu'');', 34, mCall));
  Assert.AreEqual('dmMain', mCall.Owner);
  Assert.AreEqual('qryOrders', mCall.DataSet);
  Assert.AreEqual('dmMain.qryOrders', mCall.DisplayName);
  Assert.IsTrue(TDataFieldNames.CallAt('  Self.dmMain.qryOrders.Params.ParamByName(''', 44, mCall));
  Assert.AreEqual('dmMain', mCall.Owner);
  Assert.AreEqual<TDataNameKind>(TDataNameKind.Param, mCall.Kind);
  Assert.IsTrue(TDataFieldNames.CallAt('  qryOrders.FieldByName(''cu'');', 27, mCall));
  Assert.AreEqual('', mCall.Owner);
  Assert.AreEqual('qryOrders', mCall.DisplayName);
end;

const
  cLooksUpMainFile = 'C:\P\Main.pas';
  cLooksUpModuleFile = 'C:\P\Daten.pas';
  cLooksUpMainText = 'unit Main;'#13#10'interface'#13#10'implementation'#13#10'{$R *.dfm}'#13#10'end.'#13#10;
  cLooksUpModuleText = 'unit Daten;'#13#10'interface'#13#10'type'#13#10'  TdmMain = class(TDataModule)'#13#10'  end;'#13#10 +
    'var'#13#10'  dmMain: TdmMain;'#13#10'implementation'#13#10'{$R *.dfm}'#13#10'end.'#13#10;
  cLooksUpModuleForm =
    'object dmMain: TdmMain'#13#10 +
    '  object qryKunden: TSQLQuery'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''select K.KUNDE_ID, K.NAME from KUNDEN K'')'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

procedure TDataFieldNamesTests.LooksUpOwnFormAndDataModules;
var
  mIndex: ISymbolIndex;
  mReader: TDataTextReader;
  mCall: TDataNameCall;
  mSql: string;
  mFound: Boolean;
  mItems: TArray<TDataName>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cLooksUpModuleText, cLooksUpModuleFile, nil));
  mReader :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, cLooksUpMainFile) then
      begin
        AText := cLooksUpMainText;
      end
      else if SameText(AFileName, ChangeFileExt(cLooksUpMainFile, '.dfm')) then
      begin
        AText := cForm;
      end
      else if SameText(AFileName, cLooksUpModuleFile) then
      begin
        AText := cLooksUpModuleText;
      end
      else if SameText(AFileName, ChangeFileExt(cLooksUpModuleFile, '.dfm')) then
      begin
        AText := cLooksUpModuleForm;
      end
      else
      begin
        Result := False;
      end;
    end;
  // Eigene Unit, auch über den Namen des eigenen Formulars.
  Assert.IsTrue(TDataFieldNames.CallAt('  qryOrders.FieldByName(''cu'');', 27, mCall));
  mItems := TDataFieldNames.Lookup(TDataLookupSource.Create(cLooksUpMainText, cLooksUpMainFile, mIndex, mReader), mCall,
    mSql, mFound);
  Assert.IsTrue(mFound);
  Assert.Contains(Names(mItems), 'CUSTOMER_ID');
  Assert.IsTrue(TDataFieldNames.CallAt('  frmOrders.qryOrders.FieldByName(''cu'');', 37, mCall));
  mItems := TDataFieldNames.Lookup(TDataLookupSource.Create(cLooksUpMainText, cLooksUpMainFile, mIndex, mReader), mCall,
    mSql, mFound);
  Assert.IsTrue(mFound);
  // Anderes Datenmodul über die globale Variable im Index.
  Assert.IsTrue(TDataFieldNames.CallAt('  dmMain.qryKunden.FieldByName(''na'');', 34, mCall));
  mItems := TDataFieldNames.Lookup(TDataLookupSource.Create(cLooksUpMainText, cLooksUpMainFile, mIndex, mReader), mCall,
    mSql, mFound);
  Assert.IsTrue(mFound);
  Assert.AreEqual('KUNDE_ID|NAME', Names(mItems));
  Assert.Contains(mSql, 'from KUNDEN');
  // Ohne Index, unbekanntes Datenmodul oder unbekannte Datenmenge: nichts.
  mItems := TDataFieldNames.Lookup(TDataLookupSource.Create(cLooksUpMainText, cLooksUpMainFile, nil, mReader), mCall,
    mSql, mFound);
  Assert.IsFalse(mFound);
  Assert.IsTrue(TDataFieldNames.CallAt('  dmFremd.qryKunden.FieldByName(''na'');', 35, mCall));
  mItems := TDataFieldNames.Lookup(TDataLookupSource.Create(cLooksUpMainText, cLooksUpMainFile, mIndex, mReader), mCall,
    mSql, mFound);
  Assert.IsFalse(mFound);
  Assert.AreEqual(0, Integer(Length(mItems)));
  Assert.IsTrue(TDataFieldNames.CallAt('  dmMain.qryOrders.FieldByName(''na'');', 34, mCall));
  mItems := TDataFieldNames.Lookup(TDataLookupSource.Create(cLooksUpMainText, cLooksUpMainFile, mIndex, mReader), mCall,
    mSql, mFound);
  Assert.IsFalse(mFound);
end;

procedure TDataFieldNamesTests.SplitsSelectList;
var
  mStar: Boolean;
begin
  Assert.AreEqual('ORDER_ID|CUSTOMER_ID|CUR|TOTAL|Name', string.Join('|', TDataFieldNames.SelectColumns(
    'select distinct O.ORDER_ID, O.CUSTOMER_ID, O.CURRENCY as CUR, sum(P.AMOUNT) TOTAL, count(*), ' +
    '"Name", (select max(X) from Y) from ORDERS O', mStar)));
  Assert.IsFalse(mStar);
  Assert.AreEqual('A', string.Join('|', TDataFieldNames.SelectColumns(
    '-- Kommentar'#10'select first 10 T.*, A /* B */ from T', mStar)));
  Assert.IsTrue(mStar);
  Assert.AreEqual('Nr', string.Join('|', TDataFieldNames.SelectColumns(
    'select case when A = 1 then ''x'' else ''y'' end, [Nr] from T', mStar)));
  Assert.AreEqual(0, Integer(Length(TDataFieldNames.SelectColumns('update T set A = 1', mStar))));
end;

procedure TDataFieldNamesTests.CollectsFieldsFromForm;
var
  mSql: string;
  mFound: Boolean;
begin
  // Persistente Felder zuerst, dann die Spalten der Anweisung ohne Doppelte.
  Assert.AreEqual('CUSTOMER_ID:Integer|NOTE:WideString|ORDER_ID|CUR|TOTAL', Names(
    TDataFieldNames.FromForm(cForm, 'qryOrders', TDataNameKind.Field, mSql, mFound)));
  Assert.IsTrue(mFound);
  Assert.IsTrue(mSql.StartsWith('select O.ORDER_ID'));
  // select * ohne Schema-Cache: keine Spalten.
  Assert.AreEqual('', Names(TDataFieldNames.FromForm(cForm, 'qryAll', TDataNameKind.Field, mSql, mFound)));
  Assert.IsTrue(mFound);
  // Zur Laufzeit erzeugt: nicht in der Formulardatei.
  Assert.AreEqual('', Names(TDataFieldNames.FromForm(cForm, 'qryLaufzeit', TDataNameKind.Field, mSql, mFound)));
  Assert.IsFalse(mFound);
end;

procedure TDataFieldNamesTests.CollectsParamsFromForm;
var
  mSql: string;
  mFound: Boolean;
begin
  // Platzhalter der Anweisung, Typ aus der Params-Sammlung, dann übrige Einträge der Sammlung.
  Assert.AreEqual('Customer:Integer|State|Extra:String', Names(
    TDataFieldNames.FromForm(cForm, 'qryOrders', TDataNameKind.Param, mSql, mFound)));
end;

procedure TDataFieldNamesTests.ShortensSql;
var
  mSql: string;
  mFound: Boolean;
begin
  Assert.AreEqual('select A from T', TDataFieldNames.ShortSql('select A'#13#10'  from T'));
  // Mehrere Lücken: Der Text zwischen den Treffern bleibt ganz.
  Assert.AreEqual('select O.ID, O.TOTAL from ORDERS',
    TDataFieldNames.ShortSql('select  O.ID,'#13#10'  O.TOTAL  from  ORDERS'));
  Assert.AreEqual('select A, B…', TDataFieldNames.ShortSql('select A, B, C from T', 12));
  Assert.IsTrue(TDataFieldNames.Contains(TDataFieldNames.FromForm(cForm, 'qryOrders', TDataNameKind.Field,
    mSql, mFound), 'customer_id'));
end;

initialization
  TDUnitX.RegisterTestFixture(TDataFieldNamesTests);

end.
