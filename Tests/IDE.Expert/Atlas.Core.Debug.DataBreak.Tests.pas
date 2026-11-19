unit Atlas.Core.Debug.DataBreak.Tests;

// Tests für den Kern von „Anhalten bei Datenzugriff“ (#870): Klassen aus der Einstellung, Argumente und Antwort des
// Servers, Haltestellen, Auswerteausdrücke je Klasse und die Entscheidung beim Halt.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.DataBreak;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDataBreakTests = class
  private
    FAnswer: TAtlasDataAnswer;
    FClasses: TArray<TAtlasDataClass>;
    function Site(AIndex: Integer): TAtlasDataSite;
    function ClassNamed(const AName: string): TAtlasDataClass;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ClassesFromSettings;
    [Test]
    procedure ArgumentsForServer;
    [Test]
    procedure AnswerRead;
    [Test]
    procedure LocationsPerLineAndKind;
    [Test]
    procedure ExpressionsPerClass;
    [Test]
    procedure DecideSqlPattern;
    [Test]
    procedure DecideHttpPatternAndMode;
    [Test]
    procedure TextsForBarAndLog;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Settings.DataBreakClasses;

const
  cAnswer =
    '{"format": 1, "unresolved": 2, "sites": [' +
    '{"file": "C:\\P\\Kunde.pas", "line": 42, "character": 11, "breakLine": 42, "class": "TFDQuery", ' +
      '"kind": "sql", "method": "ExecSQL", "receiver": "qryKunde", "receiverType": "TFDQuery", "arguments": [], ' +
      '"routine": "TfrmKunde.Speichern"},' +
    '{"file": "C:\\P\\Kunde.pas", "line": 42, "character": 30, "breakLine": 42, "class": "TFDConnection", ' +
      '"kind": "sql", "method": "ExecSQL", "receiver": "FConn", "receiverType": "TFDConnection", ' +
      '"arguments": ["''DELETE FROM Log WHERE Alt = 1''"], "routine": "TfrmKunde.Speichern"},' +
    '{"file": "C:\\P\\Dienst.pas", "line": 9, "character": 10, "breakLine": 8, "class": "THTTPClient", ' +
      '"kind": "http", "method": "Post", "receiver": "FClient", "receiverType": "THTTPClient", ' +
      '"arguments": ["Basis + ''/api/auftrag''", "Body"], "routine": "TDienst.Senden"},' +
    '{"file": "C:\\P\\Dienst.pas", "line": 20, "breakLine": 20, "class": "TRESTRequest", "kind": "http", ' +
      '"method": "Execute", "receiver": "Req", "arguments": [], "routine": ""},' +
    '{"file": "C:\\P\\Kaputt.pas", "line": 1, "kind": "ftp"}]}';

{ TAtlasDataBreakTests }

function TAtlasDataBreakTests.Site(AIndex: Integer): TAtlasDataSite;
begin
  Result := FAnswer.Sites[AIndex];
end;

function TAtlasDataBreakTests.ClassNamed(const AName: string): TAtlasDataClass;
begin
  Assert.IsTrue(TAtlasDataBreak.ClassOf(FClasses, AName, Result), AName);
end;

procedure TAtlasDataBreakTests.Setup;
var
  mJson: TJSONValue;
begin
  FClasses := TAtlasDataBreak.KnownClasses;
  mJson := TJSONObject.ParseJSONValue(cAnswer);
  try
    Assert.IsTrue(TAtlasDataBreak.ReadAnswer(mJson, FAnswer));
  finally
    mJson.Free;
  end;
end;

procedure TAtlasDataBreakTests.TearDown;
begin
  FAnswer := Default(TAtlasDataAnswer);
  FClasses := nil;
end;

procedure TAtlasDataBreakTests.ClassesFromSettings;
var
  mClasses: TArray<TAtlasDataClass>;
  mSkipped: TArray<string>;
begin
  // Die Vorgabe kennt der Kern vollständig.
  mClasses := TAtlasDataBreak.Classes(TAtlasDataBreakSettings.Entries(TAtlasDataBreakSettings.cDefaultClasses),
    mSkipped);
  Assert.AreEqual(Integer(Length(TAtlasDataBreak.KnownClasses)), Integer(Length(mClasses)));
  Assert.AreEqual(0, Integer(Length(mSkipped)));
  mClasses := TAtlasDataBreak.Classes(TAtlasDataBreakSettings.Entries('tidhttp, TMeineAbfrage=sql, TUnbekannt, ' +
    'TMeinClient=http'), mSkipped);
  Assert.AreEqual(3, Integer(Length(mClasses)));
  Assert.AreEqual('TIdHTTP', mClasses[0].Name);
  Assert.AreEqual(Ord(TAtlasDataKind.Http), Ord(mClasses[0].Kind));
  Assert.AreEqual('TMeineAbfrage', mClasses[1].Name);
  Assert.AreEqual(Ord(TAtlasDataKind.Sql), Ord(mClasses[1].Kind));
  Assert.AreEqual('Open,ExecSQL,Execute,ExecSQLScalar', string.Join(',', mClasses[1].Methods));
  Assert.AreEqual('%R.SQL.Text', mClasses[1].TextExpression);
  Assert.AreEqual(Ord(TAtlasDataKind.Http), Ord(mClasses[2].Kind));
  Assert.AreEqual('TUnbekannt', string.Join(',', mSkipped));
end;

procedure TAtlasDataBreakTests.ArgumentsForServer;
var
  mJson: TJSONArray;
  mClass: TJSONObject;
begin
  mJson := TJSONObject.ParseJSONValue(TAtlasDataBreak.Arguments('file:///C:/P/P.dproj',
    TArray<TAtlasDataClass>.Create(ClassNamed('TFDConnection'), ClassNamed('TRESTRequest')))) as TJSONArray;
  try
    Assert.AreEqual(2, mJson.Count);
    Assert.AreEqual('file:///C:/P/P.dproj', mJson.Items[0].Value);
    mClass := (mJson.Items[1] as TJSONArray).Items[1] as TJSONObject;
    Assert.AreEqual('TRESTRequest', mClass.GetValue<string>('name'));
    Assert.AreEqual('http', mClass.GetValue<string>('kind'));
    Assert.AreEqual(2, mClass.GetValue<TJSONArray>('methods').Count);
  finally
    mJson.Free;
  end;
  Assert.AreEqual('[null,[]]', TAtlasDataBreak.Arguments('', nil));
end;

procedure TAtlasDataBreakTests.AnswerRead;
begin
  // Der Eintrag mit unbekannter Art fällt weg.
  Assert.AreEqual(4, Integer(Length(FAnswer.Sites)));
  Assert.AreEqual(2, FAnswer.Unresolved);
  Assert.AreEqual('C:\P\Kunde.pas', Site(0).FileName);
  Assert.AreEqual('TfrmKunde.Speichern', Site(0).Routine);
  Assert.AreEqual(8, Site(2).BreakLine);
  Assert.AreEqual(9, Site(2).Line);
  Assert.AreEqual(Ord(TAtlasDataKind.Http), Ord(Site(2).Kind));
  Assert.AreEqual('Body', Site(2).Arguments[1]);
  Assert.AreEqual(2, TAtlasDataBreak.CountOf(FAnswer.Sites, TAtlasDataKind.Sql));
  Assert.AreEqual(2, TAtlasDataBreak.CountOf(FAnswer.Sites, TAtlasDataKind.Http));
end;

procedure TAtlasDataBreakTests.LocationsPerLineAndKind;
var
  mLocations: TArray<TAtlasDataLocation>;
begin
  mLocations := TAtlasDataBreak.Locations(FAnswer.Sites, [TAtlasDataKind.Sql, TAtlasDataKind.Http]);
  Assert.AreEqual(3, Integer(Length(mLocations)));
  Assert.AreEqual(2, Integer(Length(mLocations[0].Items)));
  Assert.AreEqual(8, mLocations[1].Line);
  Assert.AreEqual(1, TAtlasDataBreak.LocationAt(mLocations, 'c:\p\dienst.pas', 8));
  Assert.AreEqual(-1, TAtlasDataBreak.LocationAt(mLocations, 'C:\P\Dienst.pas', 9));
  mLocations := TAtlasDataBreak.Locations(FAnswer.Sites, [TAtlasDataKind.Http]);
  Assert.AreEqual(2, Integer(Length(mLocations)));
  Assert.AreEqual(2, mLocations[0].Items[0]);
end;

procedure TAtlasDataBreakTests.ExpressionsPerClass;
var
  mQuery, mConnection, mHttp, mRest: TAtlasDataClass;
begin
  mQuery := ClassNamed('TFDQuery');
  mConnection := ClassNamed('TFDConnection');
  mHttp := ClassNamed('THTTPClient');
  mRest := ClassNamed('TRESTRequest');
  Assert.AreEqual('qryKunde.SQL.Text', TAtlasDataBreak.TextExpression(Site(0), mQuery));
  Assert.AreEqual('qryKunde.Params.Count', TAtlasDataBreak.ParamCountExpression(Site(0), mQuery));
  Assert.AreEqual('qryKunde.Params[3].Name', TAtlasDataBreak.ParamNameExpression(Site(0), mQuery, 3));
  Assert.AreEqual('qryKunde.Params[3].AsString', TAtlasDataBreak.ParamValueExpression(Site(0), mQuery, 3));
  // Text im Argument: keine Parameter der Abfrage.
  Assert.AreEqual('''DELETE FROM Log WHERE Alt = 1''', TAtlasDataBreak.TextExpression(Site(1), mConnection));
  Assert.AreEqual('', TAtlasDataBreak.ParamCountExpression(Site(1), mConnection));
  Assert.AreEqual('Basis + ''/api/auftrag''', TAtlasDataBreak.TextExpression(Site(2), mHttp));
  Assert.AreEqual('', TAtlasDataBreak.MethodExpression(Site(2), mHttp));
  Assert.AreEqual('Req.GetFullRequestURL(True)', TAtlasDataBreak.TextExpression(Site(3), mRest));
  Assert.AreEqual('Req.Method', TAtlasDataBreak.MethodExpression(Site(3), mRest));
  Assert.AreEqual('qryKunde.Parameters[0].Value',
    TAtlasDataBreak.ParamValueExpression(Site(0), ClassNamed('TADOQuery'), 0));
end;

procedure TAtlasDataBreakTests.DecideSqlPattern;
var
  mChoice: TAtlasDataChoice;
  mValues: TAtlasDataValues;
begin
  mChoice := TAtlasDataChoice.Defaults;
  mChoice.SqlPattern := 'UPDATE Kunden*';
  mValues := Default(TAtlasDataValues);
  mValues.Evaluated := True;
  mValues.Text := 'update kunden set Name = :Name where ID = :ID';
  Assert.AreEqual(Ord(TAtlasDataOutcome.Stop), Ord(TAtlasDataBreak.Decide(mChoice, Site(0), mValues)));
  mValues.Text := 'SELECT * FROM Kunden';
  Assert.AreEqual(Ord(TAtlasDataOutcome.Continue), Ord(TAtlasDataBreak.Decide(mChoice, Site(0), mValues)));
  mChoice.IgnoreCase := False;
  mValues.Text := 'update kunden set Name = :Name where ID = :ID';
  Assert.AreEqual(Ord(TAtlasDataOutcome.Continue), Ord(TAtlasDataBreak.Decide(mChoice, Site(0), mValues)));
  // Nicht auswertbar: lieber anhalten.
  mValues.Evaluated := False;
  Assert.AreEqual(Ord(TAtlasDataOutcome.Stop), Ord(TAtlasDataBreak.Decide(mChoice, Site(0), mValues)));
  // Art nicht gewählt: weiter.
  mChoice.Kinds := [TAtlasDataKind.Http];
  Assert.AreEqual(Ord(TAtlasDataOutcome.Continue), Ord(TAtlasDataBreak.Decide(mChoice, Site(0), mValues)));
end;

procedure TAtlasDataBreakTests.DecideHttpPatternAndMode;
var
  mChoice: TAtlasDataChoice;
  mValues: TAtlasDataValues;
begin
  mChoice := TAtlasDataChoice.Defaults;
  mChoice.HttpPattern := 'POST */api/auftrag*';
  mValues := Default(TAtlasDataValues);
  mValues.Evaluated := True;
  mValues.HttpMethod := 'POST';
  mValues.Text := 'https://server/api/auftrag?id=4';
  Assert.AreEqual(Ord(TAtlasDataOutcome.Stop), Ord(TAtlasDataBreak.Decide(mChoice, Site(2), mValues)));
  mValues.HttpMethod := 'GET';
  Assert.AreEqual(Ord(TAtlasDataOutcome.Continue), Ord(TAtlasDataBreak.Decide(mChoice, Site(2), mValues)));
  mValues.HttpMethod := 'POST';
  mChoice.Mode := TAtlasDataMode.Log;
  Assert.AreEqual(Ord(TAtlasDataOutcome.Log), Ord(TAtlasDataBreak.Decide(mChoice, Site(2), mValues)));
end;

procedure TAtlasDataBreakTests.TextsForBarAndLog;
var
  mValues: TAtlasDataValues;
begin
  mValues := Default(TAtlasDataValues);
  mValues.Evaluated := True;
  mValues.Text := 'UPDATE Kunden'#13#10'  SET Name = :Name WHERE ID = :ID';
  mValues.Params := TArray<string>.Create('Name=''A''', 'ID=5');
  Assert.AreEqual('Kunde.pas:43 · TfrmKunde.Speichern · qryKunde.ExecSQL', TAtlasDataBreak.Place(Site(0)));
  Assert.AreEqual('UPDATE Kunden SET Name = :Name WHERE ID = :ID [Name=''A'', ID=5]',
    TAtlasDataBreak.Detail(Site(0), mValues, '?'));
  Assert.AreEqual('[SQL] Kunde.pas:43 · TfrmKunde.Speichern · qryKunde.ExecSQL: ' +
    'UPDATE Kunden SET Name = :Name WHERE ID = :ID ' +
    '[Name=''A'', ID=5]', TAtlasDataBreak.LogLine(Site(0), mValues, '?'));
  mValues := Default(TAtlasDataValues);
  mValues.Evaluated := True;
  mValues.HttpMethod := 'POST';
  mValues.Text := 'https://server/api/auftrag';
  Assert.AreEqual('POST https://server/api/auftrag', TAtlasDataBreak.Detail(Site(2), mValues, '?'));
  Assert.AreEqual('Dienst.pas:21 · Req.Execute', TAtlasDataBreak.Place(Site(3)));
  mValues.Evaluated := False;
  Assert.AreEqual('[HTTP] Dienst.pas:21 · Req.Execute: (nicht auswertbar)',
    TAtlasDataBreak.LogLine(Site(3), mValues, '(nicht auswertbar)'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDataBreakTests);

end.
