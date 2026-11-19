unit Atlas.Core.AiProviders.TestSupport;

// Gemeinsames der Tests der KI-Anbieter: ein Transport, der Anfragen nur festhält und eine feste Antwort gibt, und
// das Lesen eines Kopfes. Es geht nichts ins Netz.

interface

uses
  Atlas.Core.AiProviders.Contract;

type
  /// <summary>Transport mit fester Antwort; merkt sich die letzte Anfrage und zählt die Aufrufe.</summary>
  TFakeAiHttp = class(TInterfacedObject, IAtlasAiHttp)
  public
    Calls: Integer;
    Method: string;
    Url: string;
    Headers: TArray<TAtlasAiHeader>;
    Body: string;
    TimeoutMs: Integer;
    Reply: TAtlasAiHttpReply;
    Cancelled: Boolean;
    function Send(const AMethod, AUrl: string; const AHeaders: TArray<TAtlasAiHeader>; const ABody: string;
      ATimeoutMs: Integer): TAtlasAiHttpReply;
    procedure Cancel;
  end;

/// <summary>Wert des Kopfes AName (Groß-/Kleinschreibung egal); leer, wenn er fehlt.</summary>
function AiHeaderValue(const AHeaders: TArray<TAtlasAiHeader>; const AName: string): string;

implementation

uses
  System.SysUtils;

{ TFakeAiHttp }

function TFakeAiHttp.Send(const AMethod, AUrl: string; const AHeaders: TArray<TAtlasAiHeader>; const ABody: string;
  ATimeoutMs: Integer): TAtlasAiHttpReply;
begin
  Inc(Calls);
  Method := AMethod;
  Url := AUrl;
  Headers := AHeaders;
  Body := ABody;
  TimeoutMs := ATimeoutMs;
  Result := Reply;
end;

procedure TFakeAiHttp.Cancel;
begin
  Cancelled := True;
end;

function AiHeaderValue(const AHeaders: TArray<TAtlasAiHeader>; const AName: string): string;
var
  mHeader: TAtlasAiHeader;
begin
  Result := '';
  for mHeader in AHeaders do
  begin
    if SameText(mHeader.Name, AName) then
    begin
      Exit(mHeader.Value);
    end;
  end;
end;

end.
