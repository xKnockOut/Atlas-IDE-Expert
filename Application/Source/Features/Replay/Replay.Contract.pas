unit Replay.Contract;

// Hosted-Feature Replay: Vertrag des Transports, gegen den ein nachgestellter Fall läuft (#1355). TReplayPlayer
// legt ihn über TReplayTransportFactory an; die Umsetzung liegt in Replay.Providers.Transport.

interface

uses
  System.JSON,
  Atlas.Common.JsonRpc.Contract;

type
  /// <summary>Transport des Nachstellens: liefert die Nachrichten des Falls und fängt die Antwort ab.</summary>
  IReplayTransport = interface(IJsonRpcTransport)
    ['{6F0C2B7E-4D1A-4E8B-9C35-2A7B9E41D0F3}']
    /// <summary>Antwort auf die nachgestellte Anfrage, gehört dem Aufrufer; nil ohne.</summary>
    function TakeAnswer: TJSONObject;
  end;

  /// <summary>Neuer Transport mit AMessages; vor AMessages[ARequestIndex] wartet er auf die Ruhe der Indizierung,
  /// danach höchstens AAnswerMs auf die Antwort.</summary>
  TReplayTransportFactory = reference to function(const AMessages: TArray<TJSONObject>; ARequestIndex: Integer;
    AAnswerMs: Cardinal): IReplayTransport;

implementation

end.
