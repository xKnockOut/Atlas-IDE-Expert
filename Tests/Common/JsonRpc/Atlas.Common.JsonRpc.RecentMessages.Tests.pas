unit Atlas.Common.JsonRpc.RecentMessages.Tests;

// Tests für TJsonRpcRecentMessages (#1355): Ringpuffer der letzten Nachrichten,
// gekürzte Texte, Parameter einer Anfrage nach id.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcRecentMessagesTests = class
  public
    [Test]
    procedure KeepsOrderOldestFirst;
    [Test]
    procedure KeepsOnlyCapacity;
    [Test]
    procedure ShortensLongStrings;
    [Test]
    procedure ShortensLongMessages;
    [Test]
    procedure KeepsNumbersAsNumbers;
    [Test]
    procedure FindsRequestByIdWithFullParams;
    [Test]
    procedure ForgetsOldRequests;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.RecentMessages;

procedure AddJson(const ARecent: IJsonRpcRecentMessages; const AJson: string);
var
  mMessage: TJSONValue;
begin
  mMessage := TJSONValue.ParseJSONValue(AJson);
  try
    ARecent.Add(TJSONObject(mMessage));
  finally
    mMessage.Free;
  end;
end;

procedure TJsonRpcRecentMessagesTests.KeepsOrderOldestFirst;
var
  mRecent: IJsonRpcRecentMessages;
  mLast: TArray<string>;
begin
  mRecent := TJsonRpcRecentMessages.Create;
  AddJson(mRecent, '{"method":"a"}');
  AddJson(mRecent, '{"method":"b"}');
  AddJson(mRecent, '{"method":"c"}');
  mLast := mRecent.Last(2);
  Assert.AreEqual(2, Integer(Length(mLast)));
  Assert.AreEqual('{"method":"b"}', mLast[0]);
  Assert.AreEqual('{"method":"c"}', mLast[1]);
  Assert.AreEqual(3, Integer(Length(mRecent.Last(10))));
end;

procedure TJsonRpcRecentMessagesTests.KeepsOnlyCapacity;
var
  mRecent: IJsonRpcRecentMessages;
  mLast: TArray<string>;
  mIndex: Integer;
begin
  mRecent := TJsonRpcRecentMessages.Create;
  for mIndex := 1 to TJsonRpcRecentMessages.Capacity + 5 do
    AddJson(mRecent, Format('{"method":"m%d"}', [mIndex]));
  mLast := mRecent.Last(1000);
  Assert.AreEqual(TJsonRpcRecentMessages.Capacity, Integer(Length(mLast)));
  Assert.AreEqual('{"method":"m6"}', mLast[0]);
end;

procedure TJsonRpcRecentMessagesTests.ShortensLongStrings;
var
  mValue: TJSONValue;
  mText: string;
begin
  mValue := TJSONValue.ParseJSONValue('{"text":"' + StringOfChar('x', 500) + '"}');
  try
    mText := TJsonRpcRecentMessages.Shortened(mValue, 10, 2000);
  finally
    mValue.Free;
  end;
  Assert.IsTrue(mText.Contains('xxxxxxxxxx'));
  Assert.IsFalse(mText.Contains(StringOfChar('x', 11)));
  Assert.IsTrue(mText.Contains('500'));
end;

procedure TJsonRpcRecentMessagesTests.ShortensLongMessages;
var
  mValue: TJSONValue;
  mText: string;
  mArray: TJSONArray;
  mIndex: Integer;
begin
  mArray := TJSONArray.Create;
  mValue := mArray;
  try
    for mIndex := 1 to 500 do
      mArray.Add('abc');
    mText := TJsonRpcRecentMessages.Shortened(mValue, 200, 100);
  finally
    mValue.Free;
  end;
  Assert.IsTrue(Length(mText) < 120, mText);
  Assert.IsTrue(mText.EndsWith(',"…"]'), mText);
  // Gültiges JSON: Der Absturzfall nimmt die Nachricht als Objekt auf.
  mValue := TJSONValue.ParseJSONValue(mText);
  try
    Assert.IsTrue(mValue is TJSONArray);
  finally
    mValue.Free;
  end;
end;

procedure TJsonRpcRecentMessagesTests.KeepsNumbersAsNumbers;
var
  mRecent: IJsonRpcRecentMessages;
begin
  mRecent := TJsonRpcRecentMessages.Create;
  AddJson(mRecent, '{"id":12,"ok":true,"none":null,"list":[1,"a"]}');
  Assert.AreEqual('{"id":12,"ok":true,"none":null,"list":[1,"a"]}', mRecent.Last(1)[0]);
end;

procedure TJsonRpcRecentMessagesTests.FindsRequestByIdWithFullParams;
var
  mRecent: IJsonRpcRecentMessages;
  mMethod, mParams: string;
  mLong: string;
begin
  mRecent := TJsonRpcRecentMessages.Create;
  mLong := StringOfChar('y', 1000);
  AddJson(mRecent, '{"id":"r1","method":"textDocument/hover","params":{"text":"' + mLong + '"}}');
  AddJson(mRecent, '{"method":"note"}');
  Assert.IsTrue(mRecent.FindRequest('"r1"', mMethod, mParams));
  Assert.AreEqual('textDocument/hover', mMethod);
  Assert.IsTrue(mParams.Contains(mLong));
  Assert.IsFalse(mRecent.FindRequest('"r2"', mMethod, mParams));
end;

procedure TJsonRpcRecentMessagesTests.ForgetsOldRequests;
var
  mRecent: IJsonRpcRecentMessages;
  mMethod, mParams: string;
  mIndex: Integer;
begin
  mRecent := TJsonRpcRecentMessages.Create;
  for mIndex := 1 to TJsonRpcRecentMessages.Capacity + 1 do
    AddJson(mRecent, Format('{"id":%d,"method":"m"}', [mIndex]));
  Assert.IsFalse(mRecent.FindRequest('1', mMethod, mParams));
  Assert.IsTrue(mRecent.FindRequest('2', mMethod, mParams));
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcRecentMessagesTests);

end.
