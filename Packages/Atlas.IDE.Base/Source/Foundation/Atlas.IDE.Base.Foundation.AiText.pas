unit Atlas.IDE.Base.Foundation.AiText;

// Vertrag zwischen Modulen (#2462, Modulregeln 6 und 9): Text vom eingestellten KI-Anbieter. Das Modul
// KI-Assistenten stellt über seinen Scope ein IAtlasAiText bereit (Anbieter, Modell und Schlüssel aus seinen
// Einstellungen bzw. dem Anmeldespeicher); andere Module (der Tracker für „Zusammenfassen“) fragen es über die
// Registry, ohne den Anbieter zu kennen. Fehlt das Modul oder ist kein Anbieter eingerichtet, gibt es nichts zu
// fragen (Ready = False) und der Aufrufer zeigt seine Funktion nicht.
// - Ask schickt die Anfrage im Hintergrund; ADone kommt genau einmal im Hauptthread, außer nach Cancel des Tickets:
//   Dann nie. Der Aufrufer bricht seine Tickets ab, bevor er selbst geht (Regel 3).
// - Geht der Anbieter (Modul abgemeldet), ruft er ADone offener Anfragen sofort mit Cancelled auf.
// - Inhalte gehen an einen fremden Dienst: Der Aufrufer weist vorher darauf hin (ProviderName).
// - Hinter dem Vertrag steht je nach assistants.textSource der eigene Anbieter des Moduls oder ein Anbieter der IDE
//   (Smart CodeInsight, #2744); der Aufrufer weiß es nicht und braucht es nicht.
// Nur Records und Interfaces; alle Aufrufe im Hauptthread der IDE.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Ergebnis einer Anfrage: Ok oder warum nicht.</summary>
  TAtlasAiTextStatus = (Ok, Cancelled, NotReady, Failed);
{$SCOPEDENUMS OFF}

  /// <summary>Eine Anfrage: feste Anweisung und Inhalt.</summary>
  TAtlasAiTextRequest = record
    Instructions: string;
    Task: string;
    /// <summary>Höchstens so viele Tokens Antwort.</summary>
    MaxTokens: Integer;
    /// <summary>Datei, aus der der Inhalt stammt; '' ohne Dateibezug. Passt sie zu assistants.exclude, geht nichts
    /// hinaus (Failed).</summary>
    FileName: string;
  end;

  TAtlasAiTextResult = record
    Status: TAtlasAiTextStatus;
    /// <summary>Antwort des Modells bei Ok.</summary>
    Text: string;
    /// <summary>Lesbarer Grund bei Failed (in der Sprache der IDE), ohne Schlüssel und ohne Inhalt.</summary>
    Error: string;
  end;

  TAtlasAiTextDone = reference to procedure(const AResult: TAtlasAiTextResult);

  /// <summary>Stellt das Modul KI-Assistenten bereit.</summary>
  IAtlasAiText = interface
    ['{4E2B9C71-8A35-4F6D-B0E2-7C19D5A3F846}']
    /// <summary>Ein Anbieter ist eingerichtet (Modell, nötiger Schlüssel).</summary>
    function Ready: Boolean;
    /// <summary>Anbieter und Modell für den Hinweis vor dem Senden ("Anthropic-API, Modell …").</summary>
    function ProviderName: string;
    /// <summary>Anfrage im Hintergrund; Ergebnis über ADone im Hauptthread. Ergebnis: Ticket für Cancel (&gt; 0).
    /// </summary>
    function Ask(const ARequest: TAtlasAiTextRequest; const ADone: TAtlasAiTextDone): Integer;
    /// <summary>Anfrage abbrechen; ADone kommt danach nicht mehr. Unbekannte Tickets: nichts.</summary>
    procedure Cancel(ATicket: Integer);
  end;

implementation

end.
