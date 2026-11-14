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
  System.Generics.Collections,
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
  mCommands: TLspCommands;
  mToken, mReceived: IJsonRpcCancellationToken;
begin
  mToken := TProbeToken.Create;
  mReceived := nil;
  mCommands := TLspCommands.Create;
  try
    mCommands.RegisterCancellable('atlas.test', Recorder(mReceived));
    mCommands.Execute('atlas.test', nil, mToken).Free;
    Assert.AreSame(mToken, mReceived);
  finally
    mCommands.Free;
    mReceived := nil;
    mToken := nil;
  end;
end;

procedure TLspCommandsTests.ExecuteTakesCurrentRequestToken;
var
  mCommands: TLspCommands;
  mToken, mReceived: IJsonRpcCancellationToken;
  mPrevious: Pointer;
begin
  mToken := TProbeToken.Create;
  mReceived := nil;
  mCommands := TLspCommands.Create;
  try
    mCommands.RegisterCancellable('atlas.test', Recorder(mReceived));
    // Außerhalb einer Anfrage: kein Token.
    mCommands.Execute('atlas.test', nil).Free;
    Assert.IsNull(mReceived);
    mPrevious := TJsonRpcCurrentRequest.Enter(mToken);
    try
      mCommands.Execute('atlas.test', nil).Free;
    finally
      TJsonRpcCurrentRequest.Leave(mPrevious);
    end;
    Assert.AreSame(mToken, mReceived);
  finally
    mCommands.Free;
    mReceived := nil;
    mToken := nil;
  end;
end;

procedure TLspCommandsTests.PlainHandlerStillRuns;
var
  mCommands: TLspCommands;
  mArguments: TJSONArray;
  mReply: TJSONValue;
  mToken: IJsonRpcCancellationToken;
begin
  mCommands := TLspCommands.Create;
  try
    mCommands.Register('atlas.plain',
      function(const AArguments: TJSONArray): TJSONValue
      begin
        Result := TJSONString.Create(AArguments.Items[0].Value);
      end);
    mArguments := TJSONArray.Create;
    try
      mArguments.Add('x');
      // Nicht TProbeToken.Create direkt an den const-Interface-Parameter: Delphi zählt dann nie hoch und gibt
      // das Objekt nicht frei (Leck).
      mToken := TProbeToken.Create;
      mReply := mCommands.Execute('atlas.plain', mArguments, mToken);
      try
        Assert.AreEqual('x', mReply.Value);
      finally
        mReply.Free;
      end;
    finally
      mArguments.Free;
    end;
    // Ohne Ergebnis antwortet der Befehl mit null.
    mCommands.Register('atlas.nothing',
      function(const AArguments: TJSONArray): TJSONValue
      begin
        Result := nil;
      end);
    mReply := mCommands.Execute('atlas.nothing', nil);
    try
      Assert.IsTrue(mReply is TJSONNull);
    finally
      mReply.Free;
    end;
  finally
    mCommands.Free;
  end;
end;

procedure TLspCommandsTests.ConcurrentCancellableIsConcurrent;
var
  mCommands: TLspCommands;
  mReceived: IJsonRpcCancellationToken;
  mCapability: TJSONObject;
begin
  mReceived := nil;
  mCommands := TLspCommands.Create;
  try
    mCommands.RegisterConcurrentCancellable('atlas.read', Recorder(mReceived));
    mCommands.RegisterCancellable('atlas.write', Recorder(mReceived));
    Assert.IsTrue(mCommands.IsConcurrentCommand('atlas.read'));
    Assert.IsFalse(mCommands.IsConcurrentCommand('atlas.write'));
    mCapability := mCommands.Capability;
    try
      Assert.AreEqual('["atlas.read","atlas.write"]', mCapability.GetValue('commands').ToJSON);
    finally
      mCapability.Free;
    end;
  finally
    mCommands.Free;
    mReceived := nil;
  end;
end;

procedure TLspCommandsTests.UnknownCommandRaises;
var
  mCommands: TLspCommands;
begin
  mCommands := TLspCommands.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        mCommands.Execute('atlas.unknown', nil, nil).Free;
      end,
      EJsonRpcError);
  finally
    mCommands.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCommandsTests);

end.
