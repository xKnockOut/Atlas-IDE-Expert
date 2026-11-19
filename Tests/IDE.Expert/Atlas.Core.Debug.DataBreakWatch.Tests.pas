unit Atlas.Core.Debug.DataBreakWatch.Tests;

// Tests für den Ablauf von „Anhalten bei Datenzugriff“ (#870): neuer Halt, Auswertung an einer Stelle und
// Entscheidung an einer Haltestelle, mit vorgegebenen Antworten statt des Debuggers.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.DataBreak,
  Atlas.Core.Debug.DataBreakWatch;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDataBreakWatchTests = class
  private
    FPairs: TArray<string>;
    FCalls: Integer;
    FClasses: TArray<TAtlasDataClass>;
    function Lookup(const AExpression: string; out AValue: string): Boolean;
    function Evaluator: TAtlasDataEvaluate;
    function NewSite(const AClass, AMethod, AReceiver: string; AKind: TAtlasDataKind): TAtlasDataSite;
    function ClassNamed(const AName: string): TAtlasDataClass;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure StopsAnew;
    [Test]
    procedure SqlValuesWithParams;
    [Test]
    procedure SqlValuesFromArgument;
    [Test]
    procedure HttpValues;
    [Test]
    procedure NotEvaluated;
    [Test]
    procedure JudgeFirstMatchingSite;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasDataBreakWatchTests }

procedure TAtlasDataBreakWatchTests.Setup;
begin
  FPairs := nil;
  FCalls := 0;
  FClasses := TAtlasDataBreak.KnownClasses;
end;

procedure TAtlasDataBreakWatchTests.TearDown;
begin
  FPairs := nil;
  FClasses := nil;
end;

function TAtlasDataBreakWatchTests.Lookup(const AExpression: string; out AValue: string): Boolean;
var
  mIndex: Integer;
begin
  Inc(FCalls);
  AValue := '';
  mIndex := 0;
  while mIndex < High(FPairs) do
  begin
    if FPairs[mIndex] = AExpression then
    begin
      AValue := FPairs[mIndex + 1];
      Exit(True);
    end;
    Inc(mIndex, 2);
  end;
  Result := False;
end;

function TAtlasDataBreakWatchTests.Evaluator: TAtlasDataEvaluate;
begin
  Result :=
    function(const AExpression: string; out AValue: string): Boolean
    begin
      Result := Lookup(AExpression, AValue);
    end;
end;

function TAtlasDataBreakWatchTests.NewSite(const AClass, AMethod, AReceiver: string;
  AKind: TAtlasDataKind): TAtlasDataSite;
begin
  Result := Default(TAtlasDataSite);
  Result.FileName := 'C:\P\Kunde.pas';
  Result.Line := 42;
  Result.BreakLine := 42;
  Result.WatchedClass := AClass;
  Result.Kind := AKind;
  Result.Method := AMethod;
  Result.Receiver := AReceiver;
  Result.ReceiverType := AClass;
  Result.Routine := 'TfrmKunde.Speichern';
end;

function TAtlasDataBreakWatchTests.ClassNamed(const AName: string): TAtlasDataClass;
begin
  Assert.IsTrue(TAtlasDataBreak.ClassOf(FClasses, AName, Result), AName);
end;

procedure TAtlasDataBreakWatchTests.StopsAnew;
var
  mWatch: TAtlasDataWatch;
begin
  mWatch := Default(TAtlasDataWatch);
  // Beobachtung im stehenden Programm: dieselbe Stelle ist nicht neu, eine andere schon.
  mWatch.Start('A.pas', 10);
  Assert.IsTrue(mWatch.Active);
  Assert.IsFalse(mWatch.StoppedAnew('a.PAS', 10, 100000));
  Assert.IsTrue(mWatch.StoppedAnew('A.pas', 11, 0));
  // Nach dem Weiterlaufen: dieselbe Stelle erst nach der Wartezeit, nach dem Laufen sofort.
  mWatch.Resumed('A.pas', 10, 1000);
  Assert.IsFalse(mWatch.StoppedAnew('A.pas', 10, 1000 + TAtlasDataBreakWatch.cSameStopMs - 1));
  Assert.IsTrue(mWatch.StoppedAnew('A.pas', 10, 1000 + TAtlasDataBreakWatch.cSameStopMs));
  mWatch.Running;
  Assert.IsTrue(mWatch.StoppedAnew('A.pas', 10, 1000));
  // Gehalten: bleibt alt, bis das Programm läuft.
  mWatch.Held('B.pas', 3);
  Assert.IsFalse(mWatch.StoppedAnew('B.pas', 3, 999999));
  mWatch.Running;
  Assert.IsTrue(mWatch.StoppedAnew('B.pas', 3, 0));
  // Beobachtung mit laufendem Programm: jeder Halt ist neu.
  mWatch.Start('', -1);
  Assert.IsTrue(mWatch.StoppedAnew('B.pas', 3, 0));
end;

procedure TAtlasDataBreakWatchTests.SqlValuesWithParams;
var
  mValues: TAtlasDataValues;
begin
  FPairs := TArray<string>.Create(
    'qryKunde.SQL.Text', '''UPDATE Kunden SET Name = :Name WHERE ID = :ID''',
    'qryKunde.Params.Count', '2',
    'qryKunde.Params[0].Name', '''Name''', 'qryKunde.Params[0].AsString', '''Müller''',
    'qryKunde.Params[1].Name', '''ID''', 'qryKunde.Params[1].AsString', '''7''');
  mValues := TAtlasDataBreakWatch.Values(NewSite('TFDQuery', 'ExecSQL', 'qryKunde', TAtlasDataKind.Sql),
    ClassNamed('TFDQuery'), Evaluator());
  Assert.IsTrue(mValues.Evaluated);
  Assert.AreEqual('UPDATE Kunden SET Name = :Name WHERE ID = :ID', mValues.Text);
  Assert.AreEqual('Name=''Müller'', ID=''7''', string.Join(', ', mValues.Params));
end;

procedure TAtlasDataBreakWatchTests.SqlValuesFromArgument;
var
  mSite: TAtlasDataSite;
  mValues: TAtlasDataValues;
begin
  mSite := NewSite('TFDConnection', 'ExecSQL', 'FConn', TAtlasDataKind.Sql);
  mSite.Arguments := TArray<string>.Create('cLoeschen');
  FPairs := TArray<string>.Create('cLoeschen', '''DELETE FROM Log WHERE Alt = 1''');
  mValues := TAtlasDataBreakWatch.Values(mSite, ClassNamed('TFDConnection'), Evaluator());
  Assert.IsTrue(mValues.Evaluated);
  Assert.AreEqual('DELETE FROM Log WHERE Alt = 1', mValues.Text);
  Assert.AreEqual(0, Integer(Length(mValues.Params)));
end;

procedure TAtlasDataBreakWatchTests.HttpValues;
var
  mSite: TAtlasDataSite;
  mValues: TAtlasDataValues;
begin
  mSite := NewSite('THTTPClient', 'Post', 'FClient', TAtlasDataKind.Http);
  mSite.Arguments := TArray<string>.Create('FBasis + ''/api/auftrag''');
  FPairs := TArray<string>.Create('FBasis + ''/api/auftrag''', '''https://x.de/api/auftrag''',
    'reqAuftrag.GetFullRequestURL(True)', '''https://x.de/api/kunde/3''', 'reqAuftrag.Method', 'rmDELETE');
  mValues := TAtlasDataBreakWatch.Values(mSite, ClassNamed('THTTPClient'), Evaluator());
  Assert.IsTrue(mValues.Evaluated);
  Assert.AreEqual('POST', mValues.HttpMethod);
  Assert.AreEqual('https://x.de/api/auftrag', mValues.Text);
  mValues := TAtlasDataBreakWatch.Values(NewSite('TRESTRequest', 'Execute', 'reqAuftrag', TAtlasDataKind.Http),
    ClassNamed('TRESTRequest'), Evaluator());
  Assert.IsTrue(mValues.Evaluated);
  Assert.AreEqual('DELETE', mValues.HttpMethod);
  Assert.AreEqual('https://x.de/api/kunde/3', mValues.Text);
end;

procedure TAtlasDataBreakWatchTests.NotEvaluated;
var
  mValues: TAtlasDataValues;
begin
  // Kein Ausdruck auswertbar, kein Text als Zeichenkette, Methode unbekannt: jeweils nicht ausgewertet.
  mValues := TAtlasDataBreakWatch.Values(NewSite('TFDQuery', 'Open', 'qryKunde', TAtlasDataKind.Sql),
    ClassNamed('TFDQuery'), Evaluator());
  Assert.IsFalse(mValues.Evaluated);
  FPairs := TArray<string>.Create('qryKunde.SQL.Text', '<nicht verfügbar>', 'reqAuftrag.GetFullRequestURL(True)',
    '''http://a''');
  Assert.IsFalse(TAtlasDataBreakWatch.Values(NewSite('TFDQuery', 'Open', 'qryKunde', TAtlasDataKind.Sql),
    ClassNamed('TFDQuery'), Evaluator()).Evaluated);
  Assert.IsFalse(TAtlasDataBreakWatch.Values(NewSite('TRESTRequest', 'Execute', 'reqAuftrag', TAtlasDataKind.Http),
    ClassNamed('TRESTRequest'), Evaluator()).Evaluated);
end;

procedure TAtlasDataBreakWatchTests.JudgeFirstMatchingSite;
var
  mSites: TArray<TAtlasDataSite>;
  mLocations: TArray<TAtlasDataLocation>;
  mChoice: TAtlasDataChoice;
  mVerdict: TAtlasDataVerdict;
begin
  mSites := TArray<TAtlasDataSite>.Create(NewSite('TFDQuery', 'Open', 'qryKunde', TAtlasDataKind.Sql),
    NewSite('TFDQuery', 'Open', 'qryAuftrag', TAtlasDataKind.Sql));
  mLocations := TAtlasDataBreak.Locations(mSites, [TAtlasDataKind.Sql]);
  Assert.AreEqual(1, Integer(Length(mLocations)));
  FPairs := TArray<string>.Create('qryKunde.SQL.Text', '''SELECT * FROM Kunden WHERE ID = 1''',
    'qryAuftrag.SQL.Text', '''UPDATE Auftrag SET Stand = 2 WHERE ID = 1''');
  mChoice := TAtlasDataChoice.Defaults;
  mChoice.SqlPattern := 'update auftrag * where *';
  mVerdict := TAtlasDataBreakWatch.Judge(mChoice, mSites, FClasses, mLocations[0], Evaluator());
  Assert.AreEqual(Ord(TAtlasDataOutcome.Stop), Ord(mVerdict.Outcome));
  Assert.AreEqual(1, mVerdict.Site);
  Assert.AreEqual('UPDATE Auftrag SET Stand = 2 WHERE ID = 1', mVerdict.Values.Text);
  mChoice.Mode := TAtlasDataMode.Log;
  Assert.AreEqual(Ord(TAtlasDataOutcome.Log),
    Ord(TAtlasDataBreakWatch.Judge(mChoice, mSites, FClasses, mLocations[0], Evaluator()).Outcome));
  mChoice.SqlPattern := 'DELETE FROM * WHERE *';
  mVerdict := TAtlasDataBreakWatch.Judge(mChoice, mSites, FClasses, mLocations[0], Evaluator());
  Assert.AreEqual(Ord(TAtlasDataOutcome.Continue), Ord(mVerdict.Outcome));
  Assert.AreEqual(-1, mVerdict.Site);
  // Art nicht gewählt: keine Auswertung.
  FCalls := 0;
  mChoice.Kinds := [TAtlasDataKind.Http];
  Assert.AreEqual(Ord(TAtlasDataOutcome.Continue),
    Ord(TAtlasDataBreakWatch.Judge(mChoice, mSites, FClasses, mLocations[0], Evaluator()).Outcome));
  Assert.AreEqual(0, FCalls);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDataBreakWatchTests);

end.
