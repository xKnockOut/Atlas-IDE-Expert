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
  Id: TJSONNumber;
  Message: TJSONObject;
begin
  Id := TJSONNumber.Create(7);
  try
    Message := TJsonRpcMessages.Response(Id, TJSONString.Create('fertig'));
    try
      Assert.AreEqual('{"jsonrpc":"2.0","id":7,"result":"fertig"}', Message.ToJSON);
      // Die id ist kopiert: Das Original gehört weiter dem Aufrufer.
      Assert.IsFalse(Message.GetValue('id') = Id);
    finally
      Message.Free;
    end;
  finally
    Id.Free;
  end;
end;

procedure TJsonRpcMessagesTests.ResponseWithoutIdAndResultSendsNull;
var
  Message: TJSONObject;
begin
  Message := TJsonRpcMessages.Response(nil, nil);
  try
    Assert.AreEqual('{"jsonrpc":"2.0","id":null,"result":null}', Message.ToJSON);
  finally
    Message.Free;
  end;
end;

procedure TJsonRpcMessagesTests.ErrorCarriesCodeAndMessage;
var
  Id: TJSONString;
  Message: TJSONObject;
begin
  Id := TJSONString.Create('a1');
  try
    Message := TJsonRpcMessages.Error(Id, -32601, 'Methode unbekannt');
    try
      Assert.AreEqual('{"jsonrpc":"2.0","id":"a1","error":{"code":-32601,"message":"Methode unbekannt"}}',
        Message.ToJSON);
    finally
      Message.Free;
    end;
  finally
    Id.Free;
  end;
end;

procedure TJsonRpcMessagesTests.ErrorWithoutIdSendsNull;
var
  Message: TJSONObject;
begin
  Message := TJsonRpcMessages.Error(nil, -32700, 'Parse error');
  try
    Assert.IsTrue(Message.GetValue('id') is TJSONNull);
    Assert.AreEqual(-32700, ((Message.GetValue('error') as TJSONObject).GetValue('code') as TJSONNumber).AsInt);
  finally
    Message.Free;
  end;
end;

procedure TJsonRpcMessagesTests.NotificationWithParams;
var
  Params: TJSONObject;
  Message: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('uri', 'file:///c:/p/a.pas');
  Message := TJsonRpcMessages.Notification('textDocument/didOpen', Params);
  try
    Assert.AreEqual('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"uri":"file:///c:/p/a.pas"}}',
      Message.ToJSON);
    // Die Parameter gehen in die Nachricht über.
    Assert.IsTrue(Message.GetValue('params') = Params);
  finally
    Message.Free;
  end;
end;

procedure TJsonRpcMessagesTests.NotificationWithoutParams;
var
  Message: TJSONObject;
begin
  Message := TJsonRpcMessages.Notification('exit', nil);
  try
    Assert.AreEqual('{"jsonrpc":"2.0","method":"exit"}', Message.ToJSON);
    Assert.IsNull(Message.GetValue('id'));
  finally
    Message.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcMessagesTests);

end.
