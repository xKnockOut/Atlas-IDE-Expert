unit Atlas.Core.Debug.StepInto.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.StepInto;

type
  [TestFixture]
  TCoreDebugStepIntoTests = class
  private
    FAnswer: TAtlasStepAnswer;
    procedure Load(const AJson: string);
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsAnswer;
    [Test]
    procedure RowsInOrderWithLocations;
    [Test]
    procedure LibraryAndMissingSourceUnavailable;
    [Test]
    procedure VirtualPicksRuntimeClass;
    [Test]
    procedure VirtualWalksClassParent;
    [Test]
    procedure VirtualUnknownOffersAllOverrides;
    [Test]
    procedure InterfaceReceiverCastToObject;
    [Test]
    procedure DigitsAndNavigation;
    [Test]
    procedure SingleCallActsLikeStepInto;
    [Test]
    procedure ArgumentsAndHelpers;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

const
  Answer =
    '{"format":1,"line":61,"followLine":62,"calls":[' +
    '{"name":"GetName","container":"TKunde","kind":"getter","text":"Kunde.Name","receiver":"Kunde",' +
    '"receiverSimple":true,"virtual":false,"declFile":"C:\\P\\Kunden.pas","declLine":9,' +
    '"targets":[{"container":"TKunde","name":"GetName","file":"C:\\P\\Kunden.pas","line":26}]},' +
    '{"name":"Format","container":"","kind":"call","text":"Format(''%d'', [N])","targets":[]},' +
    '{"name":"Speichere","container":"TKunde","kind":"call","receiver":"Kunde","receiverSimple":true,' +
    '"virtual":true,"targets":[' +
    '{"container":"TKunde","name":"Speichere","file":"C:\\P\\Kunden.pas","line":37},' +
    '{"container":"Kunden.TStammkunde","name":"Speichere","file":"C:\\P\\Stamm.pas","line":12}]},' +
    '{"name":"Create","container":"TKunde","kind":"constructor","receiverSimple":false,' +
    '"targets":[{"container":"TKunde","name":"Create","file":"C:\\RAD\\source\\rtl\\Kunden.pas","line":5}]}]}';

procedure TCoreDebugStepIntoTests.TearDown;
begin
  FAnswer := Default(TAtlasStepAnswer);
end;

procedure TCoreDebugStepIntoTests.Load(const AJson: string);
var
  Json: TJSONValue;
begin
  Json := TJSONObject.ParseJSONValue(AJson);
  try
    Assert.IsTrue(TAtlasStepInto.ReadAnswer(Json, FAnswer));
  finally
    Json.Free;
  end;
end;

procedure TCoreDebugStepIntoTests.ReadsAnswer;
var
  Json: TJSONValue;
  Other: TAtlasStepAnswer;
begin
  Load(Answer);
  Assert.AreEqual(61, FAnswer.Line);
  Assert.AreEqual(62, FAnswer.FollowLine);
  Assert.AreEqual(4, Integer(Length(FAnswer.Calls)));
  Assert.AreEqual(Ord(TAtlasStepKind.Getter), Ord(FAnswer.Calls[0].Kind));
  Assert.AreEqual(Ord(TAtlasStepKind.Constructor_), Ord(FAnswer.Calls[3].Kind));
  Assert.IsTrue(FAnswer.Calls[2].IsVirtual);
  Assert.AreEqual(2, Integer(Length(FAnswer.Calls[2].Targets)));
  Assert.AreEqual('C:\P\Stamm.pas', FAnswer.Calls[2].Targets[1].FileName);
  Json := TJSONObject.ParseJSONValue('{"format":2}');
  try
    Assert.IsFalse(TAtlasStepInto.ReadAnswer(Json, Other));
  finally
    Json.Free;
  end;
end;

procedure TCoreDebugStepIntoTests.RowsInOrderWithLocations;
var
  Rows: TArray<TAtlasStepRow>;
begin
  Load(Answer);
  Rows := TAtlasStepInto.Rows(FAnswer, nil, nil);
  // Speichere ohne Auswertung: beide Überschreibungen.
  Assert.AreEqual(5, Integer(Length(Rows)));
  Assert.AreEqual('TKunde.GetName', Rows[0].Caption);
  Assert.AreEqual('Kunden.pas:27', Rows[0].Location);
  Assert.IsTrue(Rows[0].Available);
  Assert.AreEqual('Format', Rows[1].Caption);
  Assert.AreEqual('', Rows[1].Location);
  Assert.AreEqual('TKunde.Speichere', Rows[2].Caption);
  Assert.AreEqual('Kunden.TStammkunde.Speichere', Rows[3].Caption);
  Assert.AreEqual('Stamm.pas:13', Rows[3].Location);
  Assert.IsTrue(Rows[3].Candidate);
  Assert.AreEqual('TKunde.Create', Rows[4].Caption);
end;

procedure TCoreDebugStepIntoTests.LibraryAndMissingSourceUnavailable;
var
  Rows: TArray<TAtlasStepRow>;
begin
  Load(Answer);
  Rows := TAtlasStepInto.Rows(FAnswer, nil,
    function(const AFileName: string): Boolean
    begin
      Result := not TAtlasStepInto.IsLibraryFile(AFileName, 'C:\RAD');
    end);
  Assert.AreEqual(Ord(TAtlasStepUnavailable.NoSource), Ord(Rows[1].Unavailable));
  Assert.IsFalse(Rows[1].Available);
  Assert.AreEqual(Ord(TAtlasStepUnavailable.Library_), Ord(Rows[4].Unavailable));
  Assert.IsFalse(Rows[4].Available);
  Assert.IsTrue(Rows[0].Available);
end;

procedure TCoreDebugStepIntoTests.VirtualPicksRuntimeClass;
var
  Rows: TArray<TAtlasStepRow>;
  Asked: string;
begin
  Load(Answer);
  Rows := TAtlasStepInto.Rows(FAnswer,
    function(const AExpression: string; out AValue: string): Boolean
    begin
      Asked := Asked + AExpression + ';';
      AValue := '''TStammkunde''';
      Result := True;
    end, nil);
  Assert.AreEqual(4, Integer(Length(Rows)));
  Assert.AreEqual('Kunden.TStammkunde.Speichere', Rows[2].Caption);
  Assert.IsFalse(Rows[2].Candidate);
  Assert.AreEqual('Kunde.ClassName;', Asked);
end;

procedure TCoreDebugStepIntoTests.VirtualWalksClassParent;
var
  Target: TAtlasStepTarget;
begin
  Load(Answer);
  // Laufzeittyp TSonderkunde ohne eigene Überschreibung, Vorfahr TStammkunde.
  Assert.IsTrue(TAtlasStepInto.PickTarget(FAnswer.Calls[2],
    function(const AExpression: string; out AValue: string): Boolean
    begin
      Result := True;
      if AExpression = 'Kunde.ClassName' then
        AValue := '''TSonderkunde'''
      else if AExpression = 'Kunde.ClassParent.ClassName' then
        AValue := '''TStammkunde'''
      else
        Result := False;
    end, Target));
  Assert.AreEqual('C:\P\Stamm.pas', Target.FileName);
end;

procedure TCoreDebugStepIntoTests.VirtualUnknownOffersAllOverrides;
var
  Target: TAtlasStepTarget;
  Call: TAtlasStepCall;
begin
  Load(Answer);
  Assert.IsFalse(TAtlasStepInto.PickTarget(FAnswer.Calls[2],
    function(const AExpression: string; out AValue: string): Boolean
    begin
      Result := False;
    end, Target));
  // Bis TObject ohne Treffer.
  Assert.IsFalse(TAtlasStepInto.PickTarget(FAnswer.Calls[2],
    function(const AExpression: string; out AValue: string): Boolean
    begin
      AValue := 'TObject';
      Result := True;
    end, Target));
  // Empfänger mit Aufrufen wird nicht ausgewertet.
  Call := FAnswer.Calls[2];
  Call.ReceiverSimple := False;
  Assert.AreEqual('', TAtlasStepInto.ClassExpression(Call, 0));
end;

procedure TCoreDebugStepIntoTests.InterfaceReceiverCastToObject;
var
  Call: TAtlasStepCall;
begin
  Call := Default(TAtlasStepCall);
  Call.Receiver := 'Drucker';
  Call.ReceiverSimple := True;
  Call.ReceiverInterface := True;
  Assert.AreEqual('(Drucker as TObject).ClassName', TAtlasStepInto.ClassExpression(Call, 0));
  Assert.AreEqual('(Drucker as TObject).ClassParent.ClassParent.ClassName',
    TAtlasStepInto.ClassExpression(Call, 2));
end;

procedure TCoreDebugStepIntoTests.DigitsAndNavigation;
var
  Rows: TArray<TAtlasStepRow>;
begin
  Load(Answer);
  Rows := TAtlasStepInto.Rows(FAnswer, nil, nil);
  Assert.AreEqual(0, TAtlasStepInto.DigitRow(Rows, 1));
  // Format ohne Quelltext: Ziffer 2 wählt nichts.
  Assert.AreEqual(-1, TAtlasStepInto.DigitRow(Rows, 2));
  Assert.AreEqual(2, TAtlasStepInto.DigitRow(Rows, 3));
  Assert.AreEqual(-1, TAtlasStepInto.DigitRow(Rows, 9));
  Assert.AreEqual(-1, TAtlasStepInto.DigitRow(Rows, 0));
  Assert.AreEqual(2, TAtlasStepInto.NextAvailable(Rows, 1, 1));
  Assert.AreEqual(0, TAtlasStepInto.NextAvailable(Rows, 1, -1));
  Assert.AreEqual(-1, TAtlasStepInto.NextAvailable(Rows, 5, 1));
end;

procedure TCoreDebugStepIntoTests.SingleCallActsLikeStepInto;
var
  Rows: TArray<TAtlasStepRow>;
begin
  Load('{"format":1,"line":3,"followLine":4,"calls":[{"name":"Tu","kind":"call","targets":[]}]}');
  Rows := TAtlasStepInto.Rows(FAnswer, nil, nil);
  Assert.IsTrue(TAtlasStepInto.ActsLikeStepInto(Rows));
  Load('{"format":1,"line":3,"followLine":4,"calls":[]}');
  Rows := TAtlasStepInto.Rows(FAnswer, nil, nil);
  Assert.IsTrue(TAtlasStepInto.ActsLikeStepInto(Rows));
  Load(Answer);
  Rows := TAtlasStepInto.Rows(FAnswer, nil, nil);
  Assert.IsFalse(TAtlasStepInto.ActsLikeStepInto(Rows));
end;

procedure TCoreDebugStepIntoTests.ArgumentsAndHelpers;
begin
  Assert.AreEqual('["file:///C:/P/A.pas",12]', TAtlasStepInto.Arguments('file:///C:/P/A.pas', 12));
  Assert.AreEqual('TKunde', TAtlasStepInto.Unquote('''TKunde'''));
  Assert.AreEqual('TKunde', TAtlasStepInto.Unquote(' TKunde '));
  Assert.AreEqual('TInnen', TAtlasStepInto.ShortName('Unit.TAussen.TInnen'));
  Assert.AreEqual('TList', TAtlasStepInto.ShortName('TList<Integer>'));
  Assert.IsTrue(TAtlasStepInto.IsLibraryFile('C:\RAD' + PathDelim + 'source' + PathDelim + 'rtl' + PathDelim +
    'System.pas', 'C:\RAD'));
  Assert.IsFalse(TAtlasStepInto.IsLibraryFile('C:\P\A.pas', 'C:\RAD'));
  Assert.IsFalse(TAtlasStepInto.IsLibraryFile('C:\P\A.pas', ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TCoreDebugStepIntoTests);

end.
