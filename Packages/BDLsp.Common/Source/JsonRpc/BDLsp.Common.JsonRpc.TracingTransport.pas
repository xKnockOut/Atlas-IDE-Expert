unit BDLsp.Common.JsonRpc.TracingTransport;

// Transport-Dekorator, der jede gelesene und geschriebene Nachricht in einen
// Mitschnitt-Stream schreibt. Dient der Fehlersuche und als Quelle für
// Protokolltests (Spezifikation, Abschnitte 8 und 10).
//
// Format je Zeile: <Zeitstempel> <Richtung> <JSON>
//   -->  vom Client empfangen
//   <--  an den Client gesendet

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract;

type
  TJsonRpcTracingTransport = class(TInterfacedObject, IJsonRpcTransport)
  public const
    IncomingMarker = '-->';
    OutgoingMarker = '<--';
  private
    FInner: IJsonRpcTransport;
    FTrace: TStream;
    FOwnsTrace: Boolean;
    FLock: TCriticalSection;
    procedure WriteTrace(const AMarker, AText: string);
  public
    constructor Create(const AInner: IJsonRpcTransport; ATrace: TStream; AOwnsTrace: Boolean);
    destructor Destroy; override;
    { IJsonRpcTransport }
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
  end;

implementation

{ TJsonRpcTracingTransport }

constructor TJsonRpcTracingTransport.Create(const AInner: IJsonRpcTransport; ATrace: TStream;
  AOwnsTrace: Boolean);
begin
  inherited Create;
  FInner := AInner;
  FTrace := ATrace;
  FOwnsTrace := AOwnsTrace;
  FLock := TCriticalSection.Create;
end;

destructor TJsonRpcTracingTransport.Destroy;
begin
  FLock.Free;
  if FOwnsTrace then
    FTrace.Free;
  inherited;
end;

procedure TJsonRpcTracingTransport.WriteTrace(const AMarker, AText: string);
var
  Data: TBytes;
begin
  Data := TEncoding.UTF8.GetBytes(
    FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss"."zzz', Now) + ' ' + AMarker + ' ' + AText + sLineBreak);
  FLock.Enter;
  try
    try
      FTrace.WriteBuffer(Data, Length(Data));
    except
      // Ein defekter Mitschnitt darf das Protokoll nicht stören.
    end;
  finally
    FLock.Leave;
  end;
end;

function TJsonRpcTracingTransport.ReadMessage: TJSONObject;
begin
  try
    Result := FInner.ReadMessage;
  except
    on EJsonRpcTransportClosed do
      raise;
    on E: Exception do
    begin
      WriteTrace(IncomingMarker, Format('!! %s: %s', [E.ClassName, E.Message]));
      raise;
    end;
  end;
  WriteTrace(IncomingMarker, Result.ToJSON);
end;

procedure TJsonRpcTracingTransport.WriteMessage(const AMessage: TJSONObject);
begin
  WriteTrace(OutgoingMarker, AMessage.ToJSON);
  FInner.WriteMessage(AMessage);
end;

end.
