unit Atlas.Common.JsonRpc.Messages.Tests;

// Tests für den Aufbau von JSON-RPC-2.0-Nachrichten (#415): Antwort mit
// kopierter id und übernommenem Ergebnis, null für fehlende Werte,
// Fehlerantwort und Benachrichtigung mit und ohne Parameter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcMessagesTests = class
  public
    [Test]
    procedure ResponseCopiesIdAndTakesResult;
    [Test]
    procedure ResponseWithoutIdAndResultSendsNull;
    [Test]
    procedure ErrorCarriesCodeAndMessage;
    [Test]
    procedure ErrorWithoutIdSendsNull;
    [Test]
    procedure NotificationWithParams;
    [Test]
    procedure NotificationWithoutParams;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Messages;

{ TJsonRpcMessagesTests }

procedure TJsonRpcMessagesTests.ResponseCopiesIdAndTakesResult;
var
  mId: TJSONNumber;
  mMessage: TJSONObject;
begin
  mId := TJSONNumber.Create(7);
  try
    mMessage := TJsonRpcMessages.Response(mId, TJSONString.Create('fertig'));
    try
      Assert.AreEqual('{"jsonrpc":"2.0","id":7,"result":"fertig"}', mMessage.ToJSON);
      // Die id ist kopiert: Das Original gehört weiter dem Aufrufer.
      Assert.AreNotEqual<Pointer>(Pointer(mId), Pointer(mMessage.GetValue('id')));
    finally
      mMessage.Free;
    end;
  finally
    mId.Free;
  end;
end;

procedure TJsonRpcMessagesTests.ResponseWithoutIdAndResultSendsNull;
var
  mMessage: TJSONObject;
begin
  mMessage := TJsonRpcMessages.Response(nil, nil);
  try
    Assert.AreEqual('{"jsonrpc":"2.0","id":null,"result":null}', mMessage.ToJSON);
  finally
    mMessage.Free;
  end;
end;

procedure TJsonRpcMessagesTests.ErrorCarriesCodeAndMessage;
var
  mId: TJSONString;
  mMessage: TJSONObject;
begin
  mId := TJSONString.Create('a1');
  try
    mMessage := TJsonRpcMessages.Error(mId, -32601, 'Methode unbekannt');
    try
      Assert.AreEqual('{"jsonrpc":"2.0","id":"a1","error":{"code":-32601,"message":"Methode unbekannt"}}',
        mMessage.ToJSON);
    finally
      mMessage.Free;
    end;
  finally
    mId.Free;
  end;
end;

procedure TJsonRpcMessagesTests.ErrorWithoutIdSendsNull;
var
  mMessage: TJSONObject;
begin
  mMessage := TJsonRpcMessages.Error(nil, -32700, 'Parse error');
  try
    Assert.IsTrue(mMessage.GetValue('id') is TJSONNull);
    Assert.AreEqual(-32700, ((mMessage.GetValue('error') as TJSONObject).GetValue('code') as TJSONNumber).AsInt);
  finally
    mMessage.Free;
  end;
end;

procedure TJsonRpcMessagesTests.NotificationWithParams;
var
  mParams: TJSONObject;
  mMessage: TJSONObject;
begin
  mParams := TJSONObject.Create;
  mParams.AddPair('uri', 'file:///c:/p/a.pas');
  mMessage := TJsonRpcMessages.Notification('textDocument/didOpen', mParams);
  try
    Assert.AreEqual('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"uri":"file:///c:/p/a.pas"}}',
      mMessage.ToJSON);
    // Die Parameter gehen in die Nachricht über.
    Assert.AreSame(mParams, mMessage.GetValue('params'));
  finally
    mMessage.Free;
  end;
end;

procedure TJsonRpcMessagesTests.NotificationWithoutParams;
var
  mMessage: TJSONObject;
begin
  mMessage := TJsonRpcMessages.Notification('exit', nil);
  try
    Assert.AreEqual('{"jsonrpc":"2.0","method":"exit"}', mMessage.ToJSON);
    Assert.IsNull(mMessage.GetValue('id'));
  finally
    mMessage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcMessagesTests);

end.
