unit Atlas.Core.Debug.StepInto.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.StepInto;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
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
  cAnswer =
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
  mJson: TJSONValue;
begin
  mJson := TJSONObject.ParseJSONValue(AJson);
  try
    Assert.IsTrue(TAtlasStepInto.ReadAnswer(mJson, FAnswer));
  finally
    mJson.Free;
  end;
end;

procedure TCoreDebugStepIntoTests.ReadsAnswer;
var
  mJson: TJSONValue;
  mOther: TAtlasStepAnswer;
begin
  Load(cAnswer);
  Assert.AreEqual(61, FAnswer.Line);
  Assert.AreEqual(62, FAnswer.FollowLine);
  Assert.AreEqual(4, Integer(Length(FAnswer.Calls)));
  Assert.AreEqual(Ord(TAtlasStepKind.Getter), Ord(FAnswer.Calls[0].Kind));
  Assert.AreEqual(Ord(TAtlasStepKind.Constructor_), Ord(FAnswer.Calls[3].Kind));
  Assert.IsTrue(FAnswer.Calls[2].IsVirtual);
  Assert.AreEqual(2, Integer(Length(FAnswer.Calls[2].Targets)));
  Assert.AreEqual('C:\P\Stamm.pas', FAnswer.Calls[2].Targets[1].FileName);
  mJson := TJSONObject.ParseJSONValue('{"format":2}');
  try
    Assert.IsFalse(TAtlasStepInto.ReadAnswer(mJson, mOther));
  finally
    mJson.Free;
  end;
end;

procedure TCoreDebugStepIntoTests.RowsInOrderWithLocations;
var
  mRows: TArray<TAtlasStepRow>;
begin
  Load(cAnswer);
  mRows := TAtlasStepInto.Rows(FAnswer, nil, nil);
  // Speichere ohne Auswertung: beide Überschreibungen.
  Assert.AreEqual(5, Integer(Length(mRows)));
  Assert.AreEqual('TKunde.GetName', mRows[0].Caption);
  Assert.AreEqual('Kunden.pas:27', mRows[0].Location);
  Assert.IsTrue(mRows[0].Available);
  Assert.AreEqual('Format', mRows[1].Caption);
  Assert.AreEqual('', mRows[1].Location);
  Assert.AreEqual('TKunde.Speichere', mRows[2].Caption);
  Assert.AreEqual('Kunden.TStammkunde.Speichere', mRows[3].Caption);
  Assert.AreEqual('Stamm.pas:13', mRows[3].Location);
  Assert.IsTrue(mRows[3].Candidate);
  Assert.AreEqual('TKunde.Create', mRows[4].Caption);
end;

procedure TCoreDebugStepIntoTests.LibraryAndMissingSourceUnavailable;
var
  mRows: TArray<TAtlasStepRow>;
begin
  Load(cAnswer);
  mRows := TAtlasStepInto.Rows(FAnswer, nil,
    function(const AFileName: string): Boolean
    begin
      Result := not TAtlasStepInto.IsLibraryFile(AFileName, 'C:\RAD');
    end);
  Assert.AreEqual(Ord(TAtlasStepUnavailable.NoSource), Ord(mRows[1].Unavailable));
  Assert.IsFalse(mRows[1].Available);
  Assert.AreEqual(Ord(TAtlasStepUnavailable.Library_), Ord(mRows[4].Unavailable));
  Assert.IsFalse(mRows[4].Available);
  Assert.IsTrue(mRows[0].Available);
end;

procedure TCoreDebugStepIntoTests.VirtualPicksRuntimeClass;
var
  mRows: TArray<TAtlasStepRow>;
  mAsked: string;
begin
  Load(cAnswer);
  mRows := TAtlasStepInto.Rows(FAnswer,
    function(const AExpression: string; out AValue: string): Boolean
    begin
      mAsked := mAsked + AExpression + ';';
      AValue := '''TStammkunde''';
      Result := True;
    end, nil);
  Assert.AreEqual(4, Integer(Length(mRows)));
  Assert.AreEqual('Kunden.TStammkunde.Speichere', mRows[2].Caption);
  Assert.IsFalse(mRows[2].Candidate);
  Assert.AreEqual('Kunde.ClassName;', mAsked);
end;

procedure TCoreDebugStepIntoTests.VirtualWalksClassParent;
var
  mTarget: TAtlasStepTarget;
begin
  Load(cAnswer);
  // Laufzeittyp TSonderkunde ohne eigene Überschreibung, Vorfahr TStammkunde.
  Assert.IsTrue(TAtlasStepInto.PickTarget(FAnswer.Calls[2],
    function(const AExpression: string; out AValue: string): Boolean
    begin
      Result := True;
      if AExpression = 'Kunde.ClassName' then
      begin
        AValue := '''TSonderkunde''';
      end
      else if AExpression = 'Kunde.ClassParent.ClassName' then
      begin
        AValue := '''TStammkunde''';
      end
      else
      begin
        Result := False;
      end;
    end, mTarget));
  Assert.AreEqual('C:\P\Stamm.pas', mTarget.FileName);
end;

procedure TCoreDebugStepIntoTests.VirtualUnknownOffersAllOverrides;
var
  mTarget: TAtlasStepTarget;
  mCall: TAtlasStepCall;
begin
  Load(cAnswer);
  Assert.IsFalse(TAtlasStepInto.PickTarget(FAnswer.Calls[2],
    function(const AExpression: string; out AValue: string): Boolean
    begin
      Result := False;
    end, mTarget));
  // Bis TObject ohne Treffer.
  Assert.IsFalse(TAtlasStepInto.PickTarget(FAnswer.Calls[2],
    function(const AExpression: string; out AValue: string): Boolean
    begin
      AValue := 'TObject';
      Result := True;
    end, mTarget));
  // Empfänger mit Aufrufen wird nicht ausgewertet.
  mCall := FAnswer.Calls[2];
  mCall.ReceiverSimple := False;
  Assert.AreEqual('', TAtlasStepInto.ClassExpression(mCall, 0));
end;

procedure TCoreDebugStepIntoTests.InterfaceReceiverCastToObject;
var
  mCall: TAtlasStepCall;
begin
  mCall := Default(TAtlasStepCall);
  mCall.Receiver := 'Drucker';
  mCall.ReceiverSimple := True;
  mCall.ReceiverInterface := True;
  Assert.AreEqual('(Drucker as TObject).ClassName', TAtlasStepInto.ClassExpression(mCall, 0));
  Assert.AreEqual('(Drucker as TObject).ClassParent.ClassParent.ClassName',
    TAtlasStepInto.ClassExpression(mCall, 2));
end;

procedure TCoreDebugStepIntoTests.DigitsAndNavigation;
var
  mRows: TArray<TAtlasStepRow>;
begin
  Load(cAnswer);
  mRows := TAtlasStepInto.Rows(FAnswer, nil, nil);
  Assert.AreEqual(0, TAtlasStepInto.DigitRow(mRows, 1));
  // Format ohne Quelltext: Ziffer 2 wählt nichts.
  Assert.AreEqual(-1, TAtlasStepInto.DigitRow(mRows, 2));
  Assert.AreEqual(2, TAtlasStepInto.DigitRow(mRows, 3));
  Assert.AreEqual(-1, TAtlasStepInto.DigitRow(mRows, 9));
  Assert.AreEqual(-1, TAtlasStepInto.DigitRow(mRows, 0));
  Assert.AreEqual(2, TAtlasStepInto.NextAvailable(mRows, 1, 1));
  Assert.AreEqual(0, TAtlasStepInto.NextAvailable(mRows, 1, -1));
  Assert.AreEqual(-1, TAtlasStepInto.NextAvailable(mRows, 5, 1));
end;

procedure TCoreDebugStepIntoTests.SingleCallActsLikeStepInto;
var
  mRows: TArray<TAtlasStepRow>;
begin
  Load('{"format":1,"line":3,"followLine":4,"calls":[{"name":"Tu","kind":"call","targets":[]}]}');
  mRows := TAtlasStepInto.Rows(FAnswer, nil, nil);
  Assert.IsTrue(TAtlasStepInto.ActsLikeStepInto(mRows));
  Load('{"format":1,"line":3,"followLine":4,"calls":[]}');
  mRows := TAtlasStepInto.Rows(FAnswer, nil, nil);
  Assert.IsTrue(TAtlasStepInto.ActsLikeStepInto(mRows));
  Load(cAnswer);
  mRows := TAtlasStepInto.Rows(FAnswer, nil, nil);
  Assert.IsFalse(TAtlasStepInto.ActsLikeStepInto(mRows));
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
