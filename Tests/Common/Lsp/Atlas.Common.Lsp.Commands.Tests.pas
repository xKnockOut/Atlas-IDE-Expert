unit Atlas.Common.Lsp.Commands.Tests;

// Befehle über workspace/executeCommand: Handler mit Abbruchsignal bekommen das
// Token der Anfrage, ohne ausdrückliches Token das der laufenden Anfrage
// (TJsonRpcCurrentRequest); normale Handler laufen unverändert.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspCommandsTests = class
  public
    [Test]
    procedure CancellableHandlerGetsToken;
    [Test]
    procedure ExecuteTakesCurrentRequestToken;
    [Test]
    procedure PlainHandlerStillRuns;
    [Test]
    procedure ConcurrentCancellableIsConcurrent;
    [Test]
    procedure UnknownCommandRaises;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.CurrentRequest,
  Atlas.Common.Lsp.Commands;

type
  /// <summary>Abbruchsignal, das nur zum Vergleich dient.</summary>
  TProbeToken = class(TInterfacedObject, IJsonRpcCancellationToken)
  public
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
  end;

function TProbeToken.IsCancellationRequested: Boolean;
begin
  Result := False;
end;

procedure TProbeToken.ThrowIfCancellationRequested;
begin
end;

/// <summary>Handler, der das erhaltene Token in AReceived ablegt.</summary>
function Recorder(var AReceived: IJsonRpcCancellationToken): TLspCancellableCommandHandler;
var
  mReceived: ^IJsonRpcCancellationToken;
begin
  mReceived := @AReceived;
  Result :=
    function(const AArguments: TJSONArray; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      mReceived^ := ACancellation;
      Result := TJSONTrue.Create;
    end;
end;

{ TLspCommandsTests }

procedure TLspCommandsTests.CancellableHandlerGetsToken;
var
  Commands: TLspCommands;
  Token, Received: IJsonRpcCancellationToken;
begin
  Token := TProbeToken.Create;
  Received := nil;
  Commands := TLspCommands.Create;
  try
    Commands.RegisterCancellable('atlas.test', Recorder(Received));
    Commands.Execute('atlas.test', nil, Token).Free;
    Assert.IsTrue(Received = Token);
  finally
    Commands.Free;
    Received := nil;
    Token := nil;
  end;
end;

procedure TLspCommandsTests.ExecuteTakesCurrentRequestToken;
var
  Commands: TLspCommands;
  Token, Received: IJsonRpcCancellationToken;
  Previous: Pointer;
begin
  Token := TProbeToken.Create;
  Received := nil;
  Commands := TLspCommands.Create;
  try
    Commands.RegisterCancellable('atlas.test', Recorder(Received));
    // Außerhalb einer Anfrage: kein Token.
    Commands.Execute('atlas.test', nil).Free;
    Assert.IsTrue(Received = nil);
    Previous := TJsonRpcCurrentRequest.Enter(Token);
    try
      Commands.Execute('atlas.test', nil).Free;
    finally
      TJsonRpcCurrentRequest.Leave(Previous);
    end;
    Assert.IsTrue(Received = Token);
  finally
    Commands.Free;
    Received := nil;
    Token := nil;
  end;
end;

procedure TLspCommandsTests.PlainHandlerStillRuns;
var
  Commands: TLspCommands;
  Arguments: TJSONArray;
  Reply: TJSONValue;
begin
  Commands := TLspCommands.Create;
  try
    Commands.Register('atlas.plain',
      function(const AArguments: TJSONArray): TJSONValue
      begin
        Result := TJSONString.Create(AArguments.Items[0].Value);
      end);
    Arguments := TJSONArray.Create;
    try
      Arguments.Add('x');
      Reply := Commands.Execute('atlas.plain', Arguments, TProbeToken.Create);
      try
        Assert.AreEqual('x', Reply.Value);
      finally
        Reply.Free;
      end;
    finally
      Arguments.Free;
    end;
    // Ohne Ergebnis antwortet der Befehl mit null.
    Commands.Register('atlas.nothing',
      function(const AArguments: TJSONArray): TJSONValue
      begin
        Result := nil;
      end);
    Reply := Commands.Execute('atlas.nothing', nil);
    try
      Assert.IsTrue(Reply is TJSONNull);
    finally
      Reply.Free;
    end;
  finally
    Commands.Free;
  end;
end;

procedure TLspCommandsTests.ConcurrentCancellableIsConcurrent;
var
  Commands: TLspCommands;
  Received: IJsonRpcCancellationToken;
  Capability: TJSONObject;
begin
  Received := nil;
  Commands := TLspCommands.Create;
  try
    Commands.RegisterConcurrentCancellable('atlas.read', Recorder(Received));
    Commands.RegisterCancellable('atlas.write', Recorder(Received));
    Assert.IsTrue(Commands.IsConcurrentCommand('atlas.read'));
    Assert.IsFalse(Commands.IsConcurrentCommand('atlas.write'));
    Capability := Commands.Capability;
    try
      Assert.AreEqual('["atlas.read","atlas.write"]', Capability.GetValue('commands').ToJSON);
    finally
      Capability.Free;
    end;
  finally
    Commands.Free;
    Received := nil;
  end;
end;

procedure TLspCommandsTests.UnknownCommandRaises;
var
  Commands: TLspCommands;
begin
  Commands := TLspCommands.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        Commands.Execute('atlas.unknown', nil, nil).Free;
      end,
      EJsonRpcError);
  finally
    Commands.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCommandsTests);

end.
