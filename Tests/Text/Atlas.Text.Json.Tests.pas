unit Atlas.Text.Json.Tests;

interface

uses
  System.JSON,
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonTextTests = class
  public
    [Test]
    procedure QuotesPlainText;
    [Test]
    procedure EscapesQuotesAndBackslash;
    [Test]
    procedure EscapesControlCharacters;
    [Test]
    procedure KeepsUmlauts;
  end;

  [TestFixture]
  TJsonReadTests = class
  private
    FObject: TJSONObject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NilObjectGivesDefaults;
    [Test]
    procedure MissingValueGivesDefaults;
    [Test]
    procedure NullGivesDefaults;
    [Test]
    procedure WrongTypeGivesDefaults;
    [Test]
    procedure ReadsText;
    [Test]
    procedure NumberCountsAsTextOnlyWhenNotStrict;
    [Test]
    procedure ReadsIntegers;
    [Test]
    procedure ReadsIntegerFromText;
    [Test]
    procedure ReadsIntegerWrittenAsFloat;
    [Test]
    procedure IntegerOutOfRangeGivesDefault;
    [Test]
    procedure ReadsLargeInteger;
    [Test]
    procedure ReadsFloat;
    [Test]
    procedure ReadsFlags;
    [Test]
    procedure ReadsObjectAndArray;
    [Test]
    procedure AsObjectOnlyForObjects;
    [Test]
    procedure ParseGivesValueOrNil;
    [Test]
    procedure ParseObjectOnlyForObjects;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Json;

procedure TJsonTextTests.QuotesPlainText;
begin
  Assert.AreEqual('""', TJsonText.Quote(''));
  Assert.AreEqual('"abc"', TJsonText.Quote('abc'));
end;

procedure TJsonTextTests.EscapesQuotesAndBackslash;
begin
  Assert.AreEqual('"a\"b\\c"', TJsonText.Quote('a"b\c'));
end;

procedure TJsonTextTests.EscapesControlCharacters;
begin
  Assert.AreEqual('"\b\t\n\f\r\u0001\u001F"', TJsonText.Quote(#8#9#10#12#13#1#31));
end;

procedure TJsonTextTests.KeepsUmlauts;
begin
  Assert.AreEqual('"Größe"', TJsonText.Quote('Größe'));
end;

{ TJsonReadTests }

procedure TJsonReadTests.Setup;
begin
  FObject := TJSONObject.ParseJSONValue('{"text":"  Hallo  ","number":42,"float":12.0,"exp":1e3,' +
    '"numberText":"17","big":5000000000,"real":2.5,"yes":true,"no":false,"none":null,' +
    '"object":{"a":1},"array":[1,2],"bad":"zwölf"}') as TJSONObject;
end;

procedure TJsonReadTests.TearDown;
begin
  FreeAndNil(FObject);
end;

procedure TJsonReadTests.NilObjectGivesDefaults;
var
  mInt: Int64;
  mText: string;
begin
  Assert.AreEqual('', TJsonRead.Text(nil, 'text'));
  Assert.AreEqual('', TJsonRead.StrictText(nil, 'text'));
  Assert.AreEqual(7, TJsonRead.IntOr(nil, 'number', 7));
  Assert.IsTrue(TJsonRead.FlagOr(nil, 'yes', True));
  Assert.IsNull(TJsonRead.Obj(nil, 'object'));
  Assert.IsNull(TJsonRead.Items(nil, 'array'));
  Assert.IsFalse(TJsonRead.TryInt64(nil, 'number', mInt));
  Assert.IsFalse(TJsonRead.TryText(nil, 'text', mText));
end;

procedure TJsonReadTests.MissingValueGivesDefaults;
begin
  Assert.AreEqual('', TJsonRead.Text(FObject, 'fehlt'));
  Assert.AreEqual(0, TJsonRead.Int(FObject, 'fehlt'));
  Assert.AreEqual(-1, TJsonRead.IntOr(FObject, 'fehlt', -1));
  Assert.AreEqual(Int64(9), TJsonRead.Int64Or(FObject, 'fehlt', 9));
  Assert.IsFalse(TJsonRead.Flag(FObject, 'fehlt'));
  Assert.IsTrue(TJsonRead.FlagOr(FObject, 'fehlt', True));
  Assert.IsNull(TJsonRead.Obj(FObject, 'fehlt'));
  Assert.IsNull(TJsonRead.Items(FObject, 'fehlt'));
end;

procedure TJsonReadTests.NullGivesDefaults;
begin
  Assert.AreEqual('', TJsonRead.Text(FObject, 'none'));
  Assert.AreEqual(3, TJsonRead.IntOr(FObject, 'none', 3));
  Assert.IsTrue(TJsonRead.FlagOr(FObject, 'none', True));
  Assert.IsNull(TJsonRead.Obj(FObject, 'none'));
  Assert.IsNull(TJsonRead.Items(FObject, 'none'));
end;

procedure TJsonReadTests.WrongTypeGivesDefaults;
begin
  Assert.AreEqual('', TJsonRead.Text(FObject, 'yes'));
  Assert.AreEqual('', TJsonRead.Text(FObject, 'object'));
  Assert.AreEqual(5, TJsonRead.IntOr(FObject, 'bad', 5));
  Assert.AreEqual(5, TJsonRead.IntOr(FObject, 'yes', 5));
  Assert.IsTrue(TJsonRead.FlagOr(FObject, 'text', True));
  Assert.IsTrue(Abs(TJsonRead.Float(FObject, 'text')) < 1e-9);
  Assert.IsNull(TJsonRead.Obj(FObject, 'array'));
  Assert.IsNull(TJsonRead.Items(FObject, 'object'));
end;

procedure TJsonReadTests.ReadsText;
var
  mText: string;
begin
  Assert.AreEqual('  Hallo  ', TJsonRead.Text(FObject, 'text'));
  Assert.AreEqual('  Hallo  ', TJsonRead.StrictText(FObject, 'text'));
  Assert.AreEqual('Hallo', TJsonRead.TrimmedText(FObject, 'text'));
  Assert.IsTrue(TJsonRead.TryText(FObject, 'text', mText));
  Assert.AreEqual('  Hallo  ', mText);
end;

procedure TJsonReadTests.NumberCountsAsTextOnlyWhenNotStrict;
begin
  Assert.AreEqual('42', TJsonRead.Text(FObject, 'number'));
  Assert.AreEqual('', TJsonRead.StrictText(FObject, 'number'));
end;

procedure TJsonReadTests.ReadsIntegers;
begin
  Assert.AreEqual(42, TJsonRead.Int(FObject, 'number'));
  Assert.AreEqual(42, TJsonRead.IntOr(FObject, 'number', -1));
end;

procedure TJsonReadTests.ReadsIntegerFromText;
begin
  Assert.AreEqual(17, TJsonRead.Int(FObject, 'numberText'));
end;

procedure TJsonReadTests.ReadsIntegerWrittenAsFloat;
begin
  Assert.AreEqual(12, TJsonRead.Int(FObject, 'float'));
  Assert.AreEqual(1000, TJsonRead.Int(FObject, 'exp'));
end;

procedure TJsonReadTests.IntegerOutOfRangeGivesDefault;
begin
  Assert.AreEqual(-1, TJsonRead.IntOr(FObject, 'big', -1));
end;

procedure TJsonReadTests.ReadsLargeInteger;
var
  mValue: Int64;
begin
  Assert.AreEqual(Int64(5000000000), TJsonRead.Int64Or(FObject, 'big', 0));
  Assert.IsTrue(TJsonRead.TryInt64(FObject, 'big', mValue));
  Assert.AreEqual(Int64(5000000000), mValue);
end;

procedure TJsonReadTests.ReadsFloat;
begin
  Assert.IsTrue(Abs(TJsonRead.Float(FObject, 'real') - 2.5) < 1e-9);
end;

procedure TJsonReadTests.ReadsFlags;
begin
  Assert.IsTrue(TJsonRead.Flag(FObject, 'yes'));
  Assert.IsFalse(TJsonRead.Flag(FObject, 'no'));
  Assert.IsFalse(TJsonRead.FlagOr(FObject, 'no', True));
end;

procedure TJsonReadTests.ReadsObjectAndArray;
begin
  Assert.AreEqual(1, TJsonRead.Int(TJsonRead.Obj(FObject, 'object'), 'a'));
  Assert.AreEqual(2, TJsonRead.Items(FObject, 'array').Count);
end;

procedure TJsonReadTests.AsObjectOnlyForObjects;
begin
  Assert.IsNull(TJsonRead.AsObject(nil));
  Assert.IsNull(TJsonRead.AsObject(FObject.GetValue('array')));
  Assert.AreSame(FObject, TJsonRead.AsObject(FObject));
end;

procedure TJsonReadTests.ParseGivesValueOrNil;
var
  mValue: TJSONValue;
begin
  Assert.IsNull(TJsonRead.Parse(''));
  Assert.IsNull(TJsonRead.Parse('  '));
  Assert.IsNull(TJsonRead.Parse('{"offen": '));
  mValue := TJsonRead.Parse('{"a": 1}');
  try
    Assert.IsNotNull(TJsonRead.AsObject(mValue));
    Assert.AreEqual(1, TJsonRead.Int(TJsonRead.AsObject(mValue), 'a'));
  finally
    mValue.Free;
  end;
end;

procedure TJsonReadTests.ParseObjectOnlyForObjects;
var
  mObject: TJSONObject;
begin
  Assert.IsNull(TJsonRead.ParseObject(''));
  Assert.IsNull(TJsonRead.ParseObject('[1, 2]'));
  Assert.IsNull(TJsonRead.ParseObject('"text"'));
  Assert.IsNull(TJsonRead.ParseObject('{"offen": '));
  mObject := TJsonRead.ParseObject('  {"a": "b"}');
  try
    Assert.AreEqual('b', TJsonRead.Text(mObject, 'a'));
  finally
    mObject.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonTextTests);
  TDUnitX.RegisterTestFixture(TJsonReadTests);

end.
