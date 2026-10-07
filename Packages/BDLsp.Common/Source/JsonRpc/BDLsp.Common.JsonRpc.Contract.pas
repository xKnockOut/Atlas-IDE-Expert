unit BDLsp.Common.JsonRpc.Contract;

// Contract des Platform-Features JsonRpc: Transport-Schnittstelle, Handler-Typen,
// Fehlercodes und Exceptions von JSON-RPC 2.0.

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Fehlercodes nach JSON-RPC 2.0.</summary>
  TJsonRpcErrorCode = record
  public const
    ParseError = -32700;
    InvalidRequest = -32600;
    MethodNotFound = -32601;
    InvalidParams = -32602;
    InternalError = -32603;
  end;

  /// <summary>
  /// Fehler, der als JSON-RPC-Fehlerantwort an die Gegenseite geht. Handler
  /// lösen ihn aus, um eine Anfrage mit einem bestimmten Code abzulehnen.
  /// </summary>
  EJsonRpcError = class(Exception)
  private
    FCode: Integer;
  public
    constructor Create(ACode: Integer; const AMessage: string);
    property Code: Integer read FCode;
  end;

  /// <summary>Basisklasse für Fehler beim Lesen oder Schreiben des Nachrichtenstroms.</summary>
  EJsonRpcTransportError = class(Exception);

  /// <summary>Die Eingabe wurde zwischen zwei Nachrichten regulär geschlossen.</summary>
  EJsonRpcTransportClosed = class(EJsonRpcTransportError);

  /// <summary>Liest und schreibt einzelne JSON-RPC-Nachrichten.</summary>
  IJsonRpcTransport = interface
    ['{5B0E8E57-2C59-4C38-9F2A-3E6B1F0C7D41}']
    /// <summary>
    /// Liest die nächste Nachricht. Der Aufrufer gibt das Ergebnis frei.
    /// Löst EJsonRpcTransportClosed aus, wenn die Eingabe geschlossen wurde,
    /// EJsonRpcTransportError bei zerstörtem Nachrichtenstrom und EJsonRpcError,
    /// wenn eine einzelne Nachricht kein gültiges JSON-Objekt ist.
    /// </summary>
    function ReadMessage: TJSONObject;
    /// <summary>Schreibt eine Nachricht. Threadsicher; das Objekt bleibt beim Aufrufer.</summary>
    procedure WriteMessage(const AMessage: TJSONObject);
  end;

  /// <summary>
  /// Bearbeitet eine Anfrage. AParams kann nil sein und gehört dem Aufrufer.
  /// Das Ergebnis geht in den Besitz des Aufrufers über; nil wird als null gesendet.
  /// </summary>
  TJsonRpcRequestHandler = reference to function(const AParams: TJSONValue): TJSONValue;

  /// <summary>Bearbeitet eine Benachrichtigung. AParams kann nil sein und gehört dem Aufrufer.</summary>
  TJsonRpcNotificationHandler = reference to procedure(const AParams: TJSONValue);

  /// <summary>
  /// Wird vor jeder Verteilung aufgerufen. Löst die Prüfung EJsonRpcError aus,
  /// wird eine Anfrage mit diesem Fehler beantwortet und eine Benachrichtigung verworfen.
  /// </summary>
  TJsonRpcGuard = reference to procedure(const AMethod: string; AIsRequest: Boolean);

implementation

{ EJsonRpcError }

constructor EJsonRpcError.Create(ACode: Integer; const AMessage: string);
begin
  inherited Create(AMessage);
  FCode := ACode;
end;

end.
