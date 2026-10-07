unit Shell.Composition;

// Host-Rolle Shell: Komposition des Servers von Hand (DI-Strategie ohne Container).
// Verbindet stdin/stdout, Transport, Dispatcher, Lebenszyklus und Nachrichtenschleife.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.JsonRpc.Connection,
  BDLsp.Common.Lsp.Lifecycle;

type
  TServerComposition = class
  private
    FTransport: IJsonRpcTransport;
    FDispatcher: TJsonRpcDispatcher;
    FLifecycle: TLspLifecycle;
    FConnection: TJsonRpcConnection;
    class function BuildCapabilities: TJSONObject; static;
  public
    constructor Create(const ATransport: IJsonRpcTransport);
    destructor Destroy; override;
    /// <summary>Komposition mit stdin/stdout des Prozesses.</summary>
    class function CreateForStdio: TServerComposition; static;
    /// <summary>Verarbeitet Nachrichten bis exit oder Ende der Eingabe und liefert den Exit-Code.</summary>
    function Run: Integer;
  end;

implementation

uses
  BDLsp.Common.Product.Version,
  BDLsp.Common.JsonRpc.StreamTransport,
  BDLsp.Common.Lsp.Contract,
  BDLsp.Windows.Console.StdStreams,
  BDLsp.Windows.Diagnostics.DebugOutput;

{ TServerComposition }

constructor TServerComposition.Create(const ATransport: IJsonRpcTransport);
begin
  inherited Create;
  FTransport := ATransport;
  FDispatcher := TJsonRpcDispatcher.Create;
  FLifecycle := TLspLifecycle.Create(TProductVersion.Name, TProductVersion.Version,
    function: TJSONObject
    begin
      Result := BuildCapabilities;
    end);
  FLifecycle.Attach(FDispatcher);
  FConnection := TJsonRpcConnection.Create(FTransport, FDispatcher);
  FConnection.OnError :=
    procedure(const AError: Exception)
    begin
      TDebugOutput.Write(Format('Fehler bei der Verarbeitung: %s: %s', [AError.ClassName, AError.Message]));
    end;
  FLifecycle.OnExit :=
    procedure
    begin
      FConnection.Stop;
    end;
end;

destructor TServerComposition.Destroy;
begin
  FConnection.Free;
  FLifecycle.Free;
  FDispatcher.Free;
  FTransport := nil;
  inherited;
end;

class function TServerComposition.CreateForStdio: TServerComposition;
var
  Transport: IJsonRpcTransport;
begin
  TStdStreams.RedirectTextOutputToStdErr;
  Transport := TJsonRpcStreamTransport.Create(TStdStreams.CreateInput, TStdStreams.CreateOutput, True);
  Result := TServerComposition.Create(Transport);
end;

class function TServerComposition.BuildCapabilities: TJSONObject;
begin
  // Die Features tragen ihre Capabilities hier ein, sobald sie umgesetzt sind.
  Result := TJSONObject.Create;
  Result.AddPair('textDocumentSync', TJSONNumber.Create(TLspTextDocumentSyncKind.Incremental));
end;

function TServerComposition.Run: Integer;
begin
  FConnection.Run;
  Result := FLifecycle.ExitCode;
end;

end.
