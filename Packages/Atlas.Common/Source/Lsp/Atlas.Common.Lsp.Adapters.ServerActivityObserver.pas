unit Atlas.Common.Lsp.Adapters.ServerActivityObserver;

// Meldet jede Anfrage des JSON-RPC-Verteilers an die Aktivität des Servers (Atlas.Common.Lsp.ServerActivity), damit
// die Statusdatei laufende Anfragen mit Dauer und die Zahl der Fehler zeigt; ANext (z. B. das Diagnoselog) bekommt
// beide Aufrufe danach.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.ServerActivity;

type
  /// <summary>Beobachter am Verteiler: meldet Beginn und Ende jeder Anfrage an die Aktivität und reicht beides an
  /// ANext weiter (nil = keiner).</summary>
  TServerActivityObserver = class(TInterfacedObject, IJsonRpcRequestObserver)
  private
    FActivity: TServerActivity;
    FNext: IJsonRpcRequestObserver;
  public
    constructor Create(AActivity: TServerActivity; const ANext: IJsonRpcRequestObserver);
    procedure Started(const AMethod: string);
    procedure Finished(const AMethod: string; const AParams, AResult: TJSONValue; const AError: Exception;
      AQueueMs, AElapsedMs: Int64);
  end;

implementation

uses
  System.Classes;

{ TServerActivityObserver }

constructor TServerActivityObserver.Create(AActivity: TServerActivity; const ANext: IJsonRpcRequestObserver);
begin
  inherited Create;
  FActivity := AActivity;
  FNext := ANext;
end;

procedure TServerActivityObserver.Started(const AMethod: string);
begin
  FActivity.RequestStarted(AMethod, TThread.GetTickCount64);
  if FNext <> nil then
  begin
    FNext.Started(AMethod);
  end;
end;

procedure TServerActivityObserver.Finished(const AMethod: string; const AParams, AResult: TJSONValue;
  const AError: Exception; AQueueMs, AElapsedMs: Int64);
begin
  FActivity.RequestFinished(AError <> nil);
  if FNext <> nil then
  begin
    FNext.Finished(AMethod, AParams, AResult, AError, AQueueMs, AElapsedMs);
  end;
end;

end.
