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
    /// <summary>#1357: Fähigkeit prompts, Liste mit Argumenten, prompts/get als Nachricht des Benutzers.</summary>
    [Test]
    procedure ListsAndGetsPrompts;
    [Test]
    procedure GetPromptChecksRequiredArguments;
    [Test]
    procedure PromptErrorBecomesInvalidParams;
    [Test]
    procedure ReadsResourceTemplate;
    [Test]
    procedure TemplateMatchDecodesValue;
    /// <summary>#1357: mcp.prompts aus: Prompts, Vorlagen und Prompt-Ressourcen fehlen, Werkzeuge bleiben.</summary>
    [Test]
    procedure PromptsOffHideListsButNotTools;
    /// <summary>#1357: InvokeTool hält sich an --restricted und mcp.disabledTools wie tools/call.</summary>
    [Test]
    procedure InvokeToolFollowsToolRules;
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

function EchoPrompt: TMcpPrompt;
begin
  Result.Name := 'greet';
  Result.Description := 'Begrüßt';
  Result.Arguments := TArray<TMcpPromptArgument>.Create(TMcpPromptArgument.Create('who', 'Wer', True),
    TMcpPromptArgument.Create('mood', 'Laune', False));
  Result.Handler :=
    function(const AArguments: TDictionary<string, string>): string
    var
      mMood: string;
    begin
      if not AArguments.TryGetValue('mood', mMood) then
        mMood := 'ohne Laune';
      if AArguments['who'] = 'fehler' then
        raise EMcpToolError.Create('Unit liegt außerhalb des Arbeitsbereichs');
      Result := 'Hallo ' + AArguments['who'] + ', ' + mMood;
    end;
end;

function GetPrompt(AServer: TMcpServer; const AJson: string): TJSONObject;
var
  mParams: TJSONValue;
begin
  mParams := TJSONObject.ParseJSONValue(AJson);
  try
    Result := AServer.GetPrompt(mParams);
  finally
    mParams.Free;
  end;
end;

function ReadUri(AServer: TMcpServer; const AUri: string): string;
var
  mParams: TJSONObject;
  mResult: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    mParams.AddPair('uri', AUri);
    mResult := AServer.ReadResource(mParams);
    try
      Result := mResult.GetValue<TJSONArray>('contents').Items[0].GetValue<string>('text');
    finally
      mResult.Free;
    end;
  finally
    mParams.Free;
  end;
end;

procedure TMcpServerTests.ListsAndGetsPrompts;
var
  mServer: TMcpServer;
  mResult: TJSONObject;
  mPrompts, mArguments, mMessages: TJSONArray;
begin
  mServer := NewServer;
  try
    mServer.AddPrompt(EchoPrompt);
    mResult := mServer.Initialize(nil);
    try
      Assert.IsNotNull(mResult.FindValue('capabilities.prompts'));
    finally
      mResult.Free;
    end;
    mResult := mServer.ListPrompts;
    try
      mPrompts := mResult.GetValue<TJSONArray>('prompts');
      Assert.AreEqual(1, Integer(mPrompts.Count));
      Assert.AreEqual('greet', mPrompts.Items[0].GetValue<string>('name'));
      mArguments := mPrompts.Items[0].GetValue<TJSONArray>('arguments');
      Assert.AreEqual(2, Integer(mArguments.Count));
      Assert.IsTrue(mArguments.Items[0].GetValue<Boolean>('required'));
      Assert.IsFalse(mArguments.Items[1].GetValue<Boolean>('required'));
    finally
      mResult.Free;
    end;
    mResult := GetPrompt(mServer, '{"name":"greet","arguments":{"who":"Anna","mood":"  "}}');
    try
      mMessages := mResult.GetValue<TJSONArray>('messages');
      Assert.AreEqual(1, Integer(mMessages.Count));
      Assert.AreEqual('user', mMessages.Items[0].GetValue<string>('role'));
      Assert.AreEqual('Hallo Anna, ohne Laune', mMessages.Items[0].GetValue<string>('content.text'),
        'Leere Argumente fehlen');
      Assert.AreEqual('Begrüßt', mResult.GetValue<string>('description'));
    finally
      mResult.Free;
    end;
  finally
    mServer.Free;
  end;
end;

procedure TMcpServerTests.GetPromptChecksRequiredArguments;
var
  mServer: TMcpServer;
  mCode: Integer;
  mMessage: string;
begin
  mServer := NewServer;
  try
    mServer.AddPrompt(EchoPrompt);
    mCode := 0;
    try
      GetPrompt(mServer, '{"name":"greet","arguments":{"mood":"gut"}}').Free;
    except
      on E: EJsonRpcError do
      begin
        mCode := E.Code;
        mMessage := E.Message;
      end;
    end;
    Assert.AreEqual(TJsonRpcErrorCode.InvalidParams, mCode);
    Assert.Contains(mMessage, '"who"');
    mCode := 0;
    try
      GetPrompt(mServer, '{"name":"gibtsnicht"}').Free;
    except
      on E: EJsonRpcError do
        mCode := E.Code;
    end;
    Assert.AreEqual(TJsonRpcErrorCode.InvalidParams, mCode);
  finally
    mServer.Free;
  end;
end;

procedure TMcpServerTests.PromptErrorBecomesInvalidParams;
var
  mServer: TMcpServer;
  mMessage: string;
begin
  mServer := NewServer;
  try
    mServer.AddPrompt(EchoPrompt);
    mMessage := '';
    try
      GetPrompt(mServer, '{"name":"greet","arguments":{"who":"fehler"}}').Free;
    except
      on E: EJsonRpcError do
        mMessage := E.Message;
    end;
    Assert.Contains(mMessage, 'außerhalb des Arbeitsbereichs', 'Begründung kommt beim Client an');
  finally
    mServer.Free;
  end;
end;

procedure TMcpServerTests.ReadsResourceTemplate;
var
  mServer: TMcpServer;
  mResult: TJSONObject;
  mTemplates: TJSONArray;
  mMessage: string;
begin
  mServer := NewServer;
  try
    mServer.AddResourceTemplate('delphi://unit/{name}', 'Unit', 'Gliederung', 'text/markdown',
      function(const AValue: string): string
      begin
        if AValue = 'Fremd' then
          raise EMcpToolError.Create('"Fremd" liegt außerhalb des Arbeitsbereichs');
        Result := 'Unit ' + AValue;
      end);
    mResult := mServer.ListResourceTemplates;
    try
      mTemplates := mResult.GetValue<TJSONArray>('resourceTemplates');
      Assert.AreEqual(1, Integer(mTemplates.Count));
      Assert.AreEqual('delphi://unit/{name}', mTemplates.Items[0].GetValue<string>('uriTemplate'));
    finally
      mResult.Free;
    end;
    Assert.AreEqual('Unit UI.Auftrag', ReadUri(mServer, 'delphi://unit/UI.Auftrag'));
    mMessage := '';
    try
      ReadUri(mServer, 'delphi://unit/Fremd');
    except
      on E: EJsonRpcError do
        mMessage := E.Message;
    end;
    Assert.Contains(mMessage, 'außerhalb');
  finally
    mServer.Free;
  end;
end;

procedure TMcpServerTests.TemplateMatchDecodesValue;
var
  mTemplate: TMcpResourceTemplate;
  mValue: string;
begin
  mTemplate := Default(TMcpResourceTemplate);
  mTemplate.UriTemplate := 'delphi://findings/{file}';
  Assert.IsTrue(mTemplate.Match('delphi://findings/Source%2FA%20B.pas', mValue));
  Assert.AreEqual('Source/A B.pas', mValue);
  Assert.IsTrue(mTemplate.Match('DELPHI://findings/%C3%84nderung.pas', mValue), 'UTF-8, Schema ohne Groß/klein');
  Assert.AreEqual('Änderung.pas', mValue);
  Assert.IsFalse(mTemplate.Match('delphi://findings/', mValue), 'leerer Wert');
  Assert.IsFalse(mTemplate.Match('delphi://unit/A', mValue));
end;

procedure TMcpServerTests.PromptsOffHideListsButNotTools;
var
  mServer: TMcpServer;
  mEnabled: Boolean;
  mResult: TJSONObject;
  mCode: Integer;
begin
  mServer := NewServer;
  try
    mEnabled := False;
    mServer.OnPromptsEnabled :=
      function: Boolean
      begin
        Result := mEnabled; // lsp-ignore: captured-loop-variable -- Absicht: liest den jeweils aktuellen Wert
      end;
    mServer.AddPrompt(EchoPrompt);
    mServer.AddResource('delphi://conventions', 'Konventionen', '', 'text/markdown',
      function: string
      begin
        Result := 'K';
      end);
    mServer.AddPromptResource('delphi://build/last', 'Build', '', 'text/markdown',
      function: string
      begin
        Result := 'B';
      end);
    mServer.AddResourceTemplate('delphi://unit/{name}', 'Unit', '', 'text/markdown',
      function(const AValue: string): string
      begin
        Result := AValue;
      end);
    mResult := mServer.ListPrompts;
    try
      Assert.AreEqual(0, Integer(mResult.GetValue<TJSONArray>('prompts').Count));
    finally
      mResult.Free;
    end;
    mResult := mServer.ListResourceTemplates;
    try
      Assert.AreEqual(0, Integer(mResult.GetValue<TJSONArray>('resourceTemplates').Count));
    finally
      mResult.Free;
    end;
    mResult := mServer.ListResources;
    try
      Assert.AreEqual(1, Integer(mResult.GetValue<TJSONArray>('resources').Count), 'nur delphi://conventions');
    finally
      mResult.Free;
    end;
    mResult := mServer.ListTools;
    try
      Assert.AreEqual(1, Integer(mResult.GetValue<TJSONArray>('tools').Count), 'Werkzeuge bleiben');
    finally
      mResult.Free;
    end;
    mCode := 0;
    try
      ReadUri(mServer, 'delphi://build/last');
    except
      on E: EJsonRpcError do
        mCode := E.Code;
    end;
    Assert.AreEqual(TJsonRpcErrorCode.InvalidParams, mCode);
    mEnabled := True;
    Assert.AreEqual('B', ReadUri(mServer, 'delphi://build/last'));
    mResult := mServer.ListResources;
    try
      Assert.AreEqual(2, Integer(mResult.GetValue<TJSONArray>('resources').Count));
    finally
      mResult.Free;
    end;
  finally
    mServer.Free;
  end;
end;

procedure TMcpServerTests.InvokeToolFollowsToolRules;
var
  mServer: TMcpServer;
  mText: string;
  mArguments: TJSONObject;
begin
  mServer := NewServer;
  mArguments := TJSONObject.Create;
  try
    mArguments.AddPair('text', 'x');
    mServer.AddTool('write', 'Schreibt', TMcpServer.StringSchema([], []),
      function(const AArguments: TJSONObject): string
      begin
        Result := 'geschrieben';
      end, TMcpToolKind.Write);
    Assert.IsTrue(mServer.InvokeTool('echo', mArguments, mText));
    Assert.AreEqual('Echo: x', mText);
    Assert.IsFalse(mServer.InvokeTool('echo', nil, mText), 'fachlicher Fehler');
    Assert.Contains(mText, 'text');
    Assert.IsFalse(mServer.InvokeTool('gibtsnicht', nil, mText));
    Assert.IsTrue(mServer.ToolAvailable('write'));
    mServer.Restricted := True;
    Assert.IsFalse(mServer.ToolAvailable('write'));
    Assert.IsFalse(mServer.InvokeTool('write', nil, mText));
    Assert.Contains(mText, 'eingeschränkten Modus');
    mServer.OnDisabledTools :=
      function: TArray<string>
      begin
        Result := TArray<string>.Create('echo');
      end;
    Assert.IsFalse(mServer.InvokeTool('echo', mArguments, mText));
    Assert.Contains(mText, 'mcp.disabledTools');
  finally
    mArguments.Free;
    mServer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpServerTests);

end.
