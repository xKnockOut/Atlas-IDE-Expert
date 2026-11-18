unit Atlas.Core.AiProviders.Contract;

// KI-Anbieter des Moduls KI-Assistenten (#1922): eine Schnittstelle für alle
// Anbieter (Anthropic-API, später OpenAI-kompatible Server, #2056), damit
// Schattentext und andere Nutzer nur „Text zu einer Aufgabe“ kennen.
// - IAtlasAiProvider.Complete schickt eine Aufgabe (System- und Nutzertext,
//   Höchstlänge der Antwort, Zeitlimit) und liefert Text oder einen Fehler.
//   Läuft im Hintergrund-Thread; blockiert bis zur Antwort, zum Zeitlimit oder
//   zum Abbruch über IAtlasAiHttp.Cancel.
// - IAtlasAiHttp ist der Transport (HTTPS über THTTPClient in
//   Atlas.Core.AiProviders.Adapters.Http); Tests setzen eine Attrappe ein.
// - Schlüssel liest ein Anbieter erst beim Senden aus dem Anmeldespeicher von
//   Windows (TAtlasAiKeys.Target); sie stehen nie in Einstellungen, Dateien
//   oder Protokollen, auch nicht in Fehlermeldungen.
// Nur Records und Interfaces.

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Warum keine Antwort kam.</summary>
  TAtlasAiError = (None, NoKey, Unreachable, Timeout, Unauthorized, ModelMissing, RateLimited, ServerError,
    BadAnswer, Cancelled, Refused);

  /// <summary>Eine Aufgabe an den Anbieter.</summary>
  TAtlasAiPrompt = record
    Instructions: string;
    Task: string;
    /// <summary>Höchstzahl der Token der Antwort.</summary>
    MaxTokens: Integer;
    TimeoutMs: Integer;
  end;

  TAtlasAiAnswer = record
    /// <summary>Text der Antwort; '' bei Fehler.</summary>
    Text: string;
    /// <summary>Modell, das geantwortet hat (aus der Antwort).</summary>
    Model: string;
    Error: TAtlasAiError;
    /// <summary>HTTP-Status; 0 ohne Antwort.</summary>
    Status: Integer;
    /// <summary>Meldung des Anbieters ohne Schlüssel, höchstens cMaxDetail Zeichen.</summary>
    Detail: string;
    function Ok: Boolean;
  end;

  TAtlasAiHeader = record
    Name: string;
    Value: string;
    class function Create(const AName, AValue: string): TAtlasAiHeader; static;
  end;

  /// <summary>Antwort des Transports.</summary>
  TAtlasAiHttpReply = record
    /// <summary>HTTP-Status; 0, wenn keine Antwort kam.</summary>
    Status: Integer;
    Body: string;
    /// <summary>None, Unreachable, Timeout oder Cancelled.</summary>
    Failure: TAtlasAiError;
  end;

  /// <summary>HTTP für die Anbieter; im Hintergrund-Thread.</summary>
  IAtlasAiHttp = interface
    ['{5E1A9C34-7B2D-4F80-9A61-3D8C2E4B7F15}']
    /// <summary>AMethod "GET" oder "POST"; ABody nur bei POST (JSON, UTF-8).</summary>
    function Send(const AMethod, AUrl: string; const AHeaders: TArray<TAtlasAiHeader>; const ABody: string;
      ATimeoutMs: Integer): TAtlasAiHttpReply;
    /// <summary>Laufende Anfragen abbrechen; danach endet jedes Send mit Cancelled.</summary>
    procedure Cancel;
  end;

  /// <summary>Liest den Schlüssel eines Anbieters; '' ohne Schlüssel. Im Hintergrund-Thread.</summary>
  TAtlasAiKeyReader = reference to function(const AProviderId: string): string;

  IAtlasAiProvider = interface
    ['{A4C2E7D1-3B85-4F96-8E0A-6D1F2B9C5A47}']
    /// <summary>Wert von assistants.provider, z. B. "anthropic".</summary>
    function Id: string;
    function Complete(const APrompt: TAtlasAiPrompt): TAtlasAiAnswer;
  end;

  /// <summary>Einträge der Schlüssel im Anmeldespeicher.</summary>
  TAtlasAiKeys = record
    /// <summary>Ziel im Anmeldespeicher für den Anbieter AProviderId ("Atlas:ai:anthropic").</summary>
    class function Target(const AProviderId: string): string; static;
  end;

const
  /// <summary>Benutzername und Kommentar der Einträge im Anmeldespeicher.</summary>
  cAiKeyUser = 'Atlas';
  cAiKeyComment = 'Atlas: KI-Anbieter';
  /// <summary>Höchstlänge von TAtlasAiAnswer.Detail.</summary>
  cMaxAiDetail = 300;

implementation

uses
  System.SysUtils;

{ TAtlasAiAnswer }

function TAtlasAiAnswer.Ok: Boolean;
begin
  Result := Error = TAtlasAiError.None;
end;

{ TAtlasAiHeader }

class function TAtlasAiHeader.Create(const AName, AValue: string): TAtlasAiHeader;
begin
  Result.Name := AName;
  Result.Value := AValue;
end;

{ TAtlasAiKeys }

class function TAtlasAiKeys.Target(const AProviderId: string): string;
begin
  Result := 'Atlas:ai:' + LowerCase(Trim(AProviderId));
end;

end.
