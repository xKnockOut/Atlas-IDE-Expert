unit BDLsp.Common.Lsp.Adapters.LogMessageSink;

// Log-Senke, die Einträge als Benachrichtigung window/logMessage an den Editor
// schickt. VS Code zeigt sie im Ausgabefenster der Erweiterung an.

interface

uses
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.Logging.Contract;

type
  TLspLogMessageSink = class(TInterfacedObject, ILogSink)
  public const
    Method = 'window/logMessage';
  private
    FTransport: IJsonRpcTransport;
  public
    constructor Create(const ATransport: IJsonRpcTransport);
    /// <summary>MessageType des LSP: Error = 1, Warning = 2, Info = 3, Log = 4.</summary>
    class function MessageTypeOf(ALevel: TLogLevel): Integer; static;
    { ILogSink }
    procedure Write(const AEntry: TLogEntry);
  end;

implementation

uses
  System.JSON,
  BDLsp.Common.JsonRpc.Messages;

{ TLspLogMessageSink }

constructor TLspLogMessageSink.Create(const ATransport: IJsonRpcTransport);
begin
  inherited Create;
  FTransport := ATransport;
end;

class function TLspLogMessageSink.MessageTypeOf(ALevel: TLogLevel): Integer;
begin
  case ALevel of
    TLogLevel.Error:
      Result := 1;
    TLogLevel.Warning:
      Result := 2;
    TLogLevel.Info:
      Result := 3;
  else
    Result := 4;
  end;
end;

procedure TLspLogMessageSink.Write(const AEntry: TLogEntry);
var
  Params: TJSONObject;
  Notification: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('type', TJSONNumber.Create(MessageTypeOf(AEntry.Level)));
  Params.AddPair('message', AEntry.Text);
  Notification := TJsonRpcMessages.Notification(Method, Params);
  try
    FTransport.WriteMessage(Notification);
  finally
    Notification.Free;
  end;
end;

end.
