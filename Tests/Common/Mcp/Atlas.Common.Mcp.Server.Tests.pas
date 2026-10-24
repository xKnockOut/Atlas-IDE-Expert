unit Atlas.Common.Mcp.Server.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpServerTests = class
  public
    [Test]
    procedure InitializeEchoesVersionAndOffersTools;
    [Test]
    procedure ListsToolsWithSchema;
    [Test]
    procedure CallsToolWithArguments;
    [Test]
    procedure ToolErrorBecomesIsError;
    [Test]
    procedure UnknownToolIsInvalidParams;
    [Test]
    procedure BuildsStringSchema;
    [Test]
    procedure ResourceTemplatesAreEmptyList;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Mcp.Server;

function NewServer: TMcpServer;
begin
  Result := TMcpServer.Create('Atlas', '1.0');
  Result.AddTool('echo', 'Gibt den Text zurück', TMcpServer.StringSchema(['text'], ['Text']),
    function(const AArguments: TJSONObject): string
    begin
      Result := 'Echo: ' + TMcpServer.RequiredString(AArguments, 'text');
    end);
end;

function Call(AServer: TMcpServer; const AJson: string): TJSONObject;
var
  Params: TJSONValue;
begin
  Params := TJSONObject.ParseJSONValue(AJson);
  try
    Result := AServer.CallTool(Params);
  finally
    Params.Free;
  end;
end;

procedure TMcpServerTests.InitializeEchoesVersionAndOffersTools;
var
  Server: TMcpServer;
  Params: TJSONValue;
  Result_: TJSONObject;
begin
  Server := NewServer;
  Params := TJSONObject.ParseJSONValue('{"protocolVersion":"2024-11-05","capabilities":{}}');
  try
    Result_ := Server.Initialize(Params);
    try
      Assert.AreEqual('2024-11-05', Result_.GetValue<string>('protocolVersion'));
      Assert.IsNotNull(Result_.FindValue('capabilities.tools'));
      Assert.AreEqual('Atlas', Result_.GetValue<string>('serverInfo.name'));
    finally
      Result_.Free;
    end;
    Result_ := Server.Initialize(nil);
    try
      Assert.AreEqual(TMcpServer.DefaultProtocolVersion, Result_.GetValue<string>('protocolVersion'));
    finally
      Result_.Free;
    end;
  finally
    Params.Free;
    Server.Free;
  end;
end;

procedure TMcpServerTests.ListsToolsWithSchema;
var
  Server: TMcpServer;
  Result_: TJSONObject;
  Tools: TJSONArray;
begin
  Server := NewServer;
  try
    Result_ := Server.ListTools;
    try
      Tools := Result_.GetValue<TJSONArray>('tools');
      Assert.AreEqual(1, Integer(Tools.Count));
      Assert.AreEqual('echo', Tools.Items[0].GetValue<string>('name'));
      Assert.AreEqual('object', Tools.Items[0].GetValue<string>('inputSchema.type'));
      Assert.AreEqual('text', Tools.Items[0].GetValue<TJSONArray>('inputSchema.required').Items[0].Value);
    finally
      Result_.Free;
    end;
  finally
    Server.Free;
  end;
end;

procedure TMcpServerTests.CallsToolWithArguments;
var
  Server: TMcpServer;
  Result_: TJSONObject;
begin
  Server := NewServer;
  try
    Result_ := Call(Server, '{"name":"echo","arguments":{"text":"Hallo"}}');
    try
      Assert.AreEqual('Echo: Hallo', Result_.GetValue<TJSONArray>('content').Items[0].GetValue<string>('text'));
      Assert.IsFalse(Result_.GetValue<Boolean>('isError'));
    finally
      Result_.Free;
    end;
  finally
    Server.Free;
  end;
end;

procedure TMcpServerTests.ToolErrorBecomesIsError;
var
  Server: TMcpServer;
  Result_: TJSONObject;
begin
  Server := NewServer;
  try
    Result_ := Call(Server, '{"name":"echo"}');
    try
      Assert.IsTrue(Result_.GetValue<Boolean>('isError'));
      Assert.Contains(Result_.GetValue<TJSONArray>('content').Items[0].GetValue<string>('text'), 'text');
    finally
      Result_.Free;
    end;
  finally
    Server.Free;
  end;
end;

procedure TMcpServerTests.UnknownToolIsInvalidParams;
var
  Server: TMcpServer;
  Code: Integer;
begin
  Server := NewServer;
  try
    Code := 0;
    try
      Call(Server, '{"name":"gibtsnicht"}').Free;
    except
      on E: EJsonRpcError do
        Code := E.Code;
    end;
    Assert.AreEqual(TJsonRpcErrorCode.InvalidParams, Code);
  finally
    Server.Free;
  end;
end;

procedure TMcpServerTests.BuildsStringSchema;
begin
  Assert.AreEqual('{"type":"object","properties":{"a":{"type":"string","description":"A"},' +
    '"b":{"type":"string","description":"B"}},"required":["a"]}',
    TMcpServer.StringSchema(['a', 'b'], ['A', 'B'], 1));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpServerTests);

procedure TMcpServerTests.ResourceTemplatesAreEmptyList;
var
  Server: TMcpServer;
  Result_: TJSONObject;
begin
  Server := NewServer;
  try
    Result_ := Server.ListResourceTemplates;
    try
      Assert.AreEqual(0, Integer(Result_.GetValue<TJSONArray>('resourceTemplates').Count));
    finally
      Result_.Free;
    end;
  finally
    Server.Free;
  end;
end;

end.
