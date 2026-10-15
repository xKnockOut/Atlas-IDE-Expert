unit Atlas.Common.JsonRpc.TracingTransport;

// Transport-Dekorator, der jede gelesene und geschriebene Nachricht in einen
// Mitschnitt-Stream schreibt. Dient der Fehlersuche und als Quelle für
// Protokolltests (Spezifikation, Abschnitte 8 und 10).
//
// Format je Zeile: <Zeitstempel> <Richtung> <JSON>
//   -->  vom Client empfangen
//   <--  an den Client gesendet
//
// Nach dem ersten Schreibfehler (z. B. Datenträger entfernt) schreibt der
// Transport keinen Mitschnitt mehr und meldet das einmal über OnFailed
// (Code-Review S-07).

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  Atlas.Common.JsonRpc.Contract;

type
  /// <summary>Meldet den ersten Schreibfehler des Mitschnitts; danach schreibt der Transport keinen mehr.</summary>
  TJsonRpcTraceFailedEvent = reference to procedure(const AReason: string);

  TJsonRpcTracingTransport = class(TInterfacedObject, IJsonRpcTransport)
  public const
    IncomingMarker = '-->';
    OutgoingMarker = '<--';
  private
    FInner: IJsonRpcTransport;
    FTrace: TStream;
    FOwnsTrace: Boolean;
    FLock: TCriticalSection;
    /// <summary>Unter FLock: Nach dem ersten Schreibfehler wird nichts mehr geschrieben.</summary>
    FFailed: Boolean;
    /// <summary>Unter FLock; wird nach dem Melden geleert (einmalig, bricht Referenzzyklen).</summary>
    FOnFailed: TJsonRpcTraceFailedEvent;
    procedure WriteTrace(const AMarker, AText: string);
    function GetOnFailed: TJsonRpcTraceFailedEvent;
    procedure SetOnFailed(const AValue: TJsonRpcTraceFailedEvent);
  public
    constructor Create(const AInner: IJsonRpcTransport; ATrace: TStream; AOwnsTrace: Boolean);
    destructor Destroy; override;
    { IJsonRpcTransport }
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
    /// <summary>Höchstens einmal aufgerufen, außerhalb der Sperre, im schreibenden Thread.</summary>
    property OnFailed: TJsonRpcTraceFailedEvent read GetOnFailed write SetOnFailed;
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

function TJsonRpcTracingTransport.GetOnFailed: TJsonRpcTraceFailedEvent;
begin
  FLock.Enter;
  try
    Result := FOnFailed;
  finally
    FLock.Leave;
  end;
end;

procedure TJsonRpcTracingTransport.SetOnFailed(const AValue: TJsonRpcTraceFailedEvent);
begin
  FLock.Enter;
  try
    FOnFailed := AValue;
  finally
    FLock.Leave;
  end;
end;

procedure TJsonRpcTracingTransport.WriteTrace(const AMarker, AText: string);
var
  Data: TBytes;
  Report: TJsonRpcTraceFailedEvent;
  Reason: string;
begin
  Data := TEncoding.UTF8.GetBytes(
    FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss"."zzz', Now) + ' ' + AMarker + ' ' + AText + sLineBreak);
  Report := nil;
  Reason := '';
  FLock.Enter;
  try
    if not FFailed then
      try
        FTrace.WriteBuffer(Data, Length(Data));
      except
        // Ein defekter Mitschnitt darf das Protokoll nicht stören; ab jetzt wird nicht mehr geschrieben.
        on E: Exception do
        begin
          FFailed := True;
          Reason := E.ClassName + ': ' + E.Message;
          Report := FOnFailed;
          FOnFailed := nil;
        end;
      end;
  finally
    FLock.Leave;
  end;
  // Außerhalb der Sperre: Die Meldung kann über diesen Transport zurückkommen (window/logMessage),
  // und der Logger hält eigene Sperren.
  if Assigned(Report) then
    try
      Report(Reason);
    except
      // Meldefehler ignorieren: Das Protokoll läuft weiter.
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
