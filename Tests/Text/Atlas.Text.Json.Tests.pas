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
    [Test]
    procedure KeepsSlash;
    [Test]
    procedure QuotedTextParsesBack;
    [Test]
    procedure ListsQuotedItems;
  end;

  [TestFixture]
  TJsonBuildTests = class
  public
    [Test]
    procedure EmptyListGivesEmptyArray;
    [Test]
    procedure KeepsOrderAndText;
    [Test]
    procedure TakesDynamicArray;
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
    [Test]
    procedure ParseObjectOrEmptyNeverNil;
    [Test]
    procedure IsStringRejectsNumbers;
    [Test]
    procedure StringsSkipOtherValues;
    [Test]
    procedure StringsOfNoArrayAreEmpty;
    [Test]
    procedure TrimmedStringsDropEmpty;
    [Test]
    procedure JsonGivesValueText;
    [Test]
    procedure IntsSkipOtherValues;
    [Test]
    procedure ReadsIsoTime;
    [Test]
    procedure IsoTimeIsZeroForOtherValues;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  Atlas.Text.Json;

{ TJsonTextTests }

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

procedure TJsonTextTests.KeepsSlash;
begin
  Assert.AreEqual('"a/b"', TJsonText.Quote('a/b'));
end;

procedure TJsonTextTests.QuotedTextParsesBack;
const
  cText = 'Größe "x" \ / C:\Pfad' + #9#10;
var
  mValue: TJSONValue;
begin
  mValue := TJsonRead.Parse(TJsonText.Quote(cText));
  try
    Assert.IsTrue(mValue is TJSONString);
    Assert.AreEqual(cText, mValue.Value);
  finally
    mValue.Free;
  end;
end;

{ TJsonBuildTests }

procedure TJsonBuildTests.EmptyListGivesEmptyArray;
var
  mArray: TJSONArray;
begin
  mArray := TJsonBuild.Strings([]);
  try
    Assert.AreEqual(0, mArray.Count);
    Assert.AreEqual('[]', mArray.ToJSON);
  finally
    mArray.Free;
  end;
end;

procedure TJsonBuildTests.KeepsOrderAndText;
var
  mArray: TJSONArray;
begin
  mArray := TJsonBuild.Strings(['b', 'a', '', 'Größe "x"']);
  try
    Assert.AreEqual(4, mArray.Count);
    Assert.AreEqual('b', mArray.Items[0].Value);
    Assert.AreEqual('a', mArray.Items[1].Value);
    Assert.AreEqual('', mArray.Items[2].Value);
    Assert.AreEqual('Größe "x"', mArray.Items[3].Value);
    Assert.IsTrue(mArray.Items[3] is TJSONString);
  finally
    mArray.Free;
  end;
end;

procedure TJsonBuildTests.TakesDynamicArray;
var
  mItems: TArray<string>;
  mArray: TJSONArray;
begin
  mItems := TArray<string>.Create('x', 'y');
  mArray := TJsonBuild.Strings(mItems);
  try
    Assert.AreEqual(2, mArray.Count);
    Assert.AreEqual('y', mArray.Items[1].Value);
  finally
    mArray.Free;
  end;
end;

{ TJsonReadTests }

procedure TJsonReadTests.Setup;
begin
  FObject := TJSONObject.ParseJSONValue('{"text":"  Hallo  ","number":42,"float":12.0,"exp":1e3,' +
    '"numberText":"17","big":5000000000,"real":2.5,"yes":true,"no":false,"none":null,' +
    '"object":{"a":1},"array":[1,2],"bad":"zwölf",' +
    '"names":[" a ","",1,"b",true,null,{"c":"d"},["e"],"  "],' +
    '"stamp":"2026-11-17T10:57:54.250Z","noStamp":"gestern",' +
    '"ints":[1,"2",3.0,true,5000000000,-4,null]}') as TJSONObject;
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

procedure TJsonReadTests.ParseObjectOrEmptyNeverNil;
var
  mObject: TJSONObject;
begin
  mObject := TJsonRead.ParseObjectOrEmpty('[1]');
  try
    Assert.AreEqual(0, mObject.Count);
  finally
    mObject.Free;
  end;
  mObject := TJsonRead.ParseObjectOrEmpty('{"a": 2}');
  try
    Assert.AreEqual(2, TJsonRead.Int(mObject, 'a'));
  finally
    mObject.Free;
  end;
end;

procedure TJsonReadTests.IsStringRejectsNumbers;
begin
  Assert.IsTrue(TJsonRead.IsString(TJsonRead.Value(FObject, 'numberText')));
  Assert.IsFalse(TJsonRead.IsString(TJsonRead.Value(FObject, 'number')));
  Assert.IsFalse(TJsonRead.IsString(TJsonRead.Value(FObject, 'none')));
  Assert.IsFalse(TJsonRead.IsString(TJsonRead.Value(FObject, 'missing')));
end;

procedure TJsonReadTests.StringsSkipOtherValues;
begin
  Assert.AreEqual(' a ||b|  ', string.Join('|', TJsonRead.Strings(FObject, 'names')));
  Assert.AreEqual(Integer(4), Integer(Length(TJsonRead.Strings(TJsonRead.Value(FObject, 'names')))));
end;

procedure TJsonReadTests.StringsOfNoArrayAreEmpty;
begin
  Assert.AreEqual(Integer(0), Integer(Length(TJsonRead.Strings(nil, 'names'))));
  Assert.AreEqual(Integer(0), Integer(Length(TJsonRead.Strings(FObject, 'missing'))));
  Assert.AreEqual(Integer(0), Integer(Length(TJsonRead.Strings(FObject, 'text'))));
  Assert.AreEqual(Integer(0), Integer(Length(TJsonRead.Strings(FObject, 'object'))));
  Assert.AreEqual(Integer(0), Integer(Length(TJsonRead.Strings(FObject, 'array'))));
  Assert.AreEqual(Integer(0), Integer(Length(TJsonRead.TrimmedStrings(FObject, 'none'))));
end;

procedure TJsonReadTests.TrimmedStringsDropEmpty;
begin
  Assert.AreEqual('a|b', string.Join('|', TJsonRead.TrimmedStrings(FObject, 'names')));
  Assert.AreEqual('a|b', string.Join('|', TJsonRead.TrimmedStrings(TJsonRead.Value(FObject, 'names'))));
end;

procedure TJsonReadTests.JsonGivesValueText;
begin
  Assert.AreEqual('{"a":1}', TJsonRead.Json(FObject, 'object'));
  Assert.AreEqual('null', TJsonRead.Json(FObject, 'none'));
  Assert.AreEqual('42', TJsonRead.Json(FObject, 'number'));
  Assert.AreEqual('', TJsonRead.Json(FObject, 'fehlt'));
  Assert.AreEqual('', TJsonRead.Json(nil, 'object'));
end;

procedure TJsonReadTests.IntsSkipOtherValues;
var
  mInts: TArray<Integer>;
begin
  mInts := TJsonRead.Ints(FObject, 'ints');
  Assert.AreEqual(Integer(3), Integer(Length(mInts)));
  Assert.AreEqual(1, mInts[0]);
  Assert.AreEqual(3, mInts[1]);
  Assert.AreEqual(-4, mInts[2]);
  Assert.AreEqual(Integer(1), Integer(Length(TJsonRead.Ints(FObject, 'names'))));
  Assert.AreEqual(Integer(0), Integer(Length(TJsonRead.Ints(nil, 'ints'))));
  Assert.AreEqual(Integer(0), Integer(Length(TJsonRead.Ints(FObject, 'number'))));
  mInts := nil;
end;

procedure TJsonReadTests.ReadsIsoTime;
begin
  Assert.AreEqual(Double(EncodeDate(2026, 11, 17) + EncodeTime(10, 57, 54, 250)),
    Double(TJsonRead.IsoTime(FObject, 'stamp', True)), Double(1 / MSecsPerDay));
end;

procedure TJsonReadTests.IsoTimeIsZeroForOtherValues;
begin
  Assert.AreEqual(Double(0), Double(TJsonRead.IsoTime(nil, 'stamp', True)));
  Assert.AreEqual(Double(0), Double(TJsonRead.IsoTime(FObject, 'fehlt', True)));
  Assert.AreEqual(Double(0), Double(TJsonRead.IsoTime(FObject, 'noStamp', True)));
  Assert.AreEqual(Double(0), Double(TJsonRead.IsoTime(FObject, 'number', False)));
  Assert.AreEqual(Double(0), Double(TJsonRead.IsoTime(FObject, 'none', False)));
end;

procedure TJsonTextTests.ListsQuotedItems;
begin
  Assert.AreEqual('[]', TJsonText.List([]));
  Assert.AreEqual('["a", "b\"c"]', TJsonText.List(['a', 'b"c']));
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonTextTests);
  TDUnitX.RegisterTestFixture(TJsonBuildTests);
  TDUnitX.RegisterTestFixture(TJsonReadTests);

end.
