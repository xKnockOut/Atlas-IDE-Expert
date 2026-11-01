unit Atlas.Core.Ci.Contract;

// Build-Server (CI) für den Bereich „Testergebnisse“ der Willkommensseite
// (#763), ohne VCL und Open Tools API.
// - IAtlasCiProvider: ein CI-Anbieter (zuerst Jenkins,
//   Atlas.Core.Ci.Providers.Jenkins). Weitere Anbieter (GitHub Actions,
//   GitLab CI, TeamCity) kommen als eigene Umsetzung dazu, ohne dass sich der
//   Bereich ändert; die Komposition wählt sie über TAtlasCiJob.Provider.
// - IAtlasCiTransport: ein GET mit Zeitlimit. Die echte Umsetzung
//   (Atlas.Core.Ci.Adapters.Http) sendet Benutzer und Token aus dem
//   Anmeldespeicher von Windows (Atlas.Core.Ci.Adapters.Credentials); Tests
//   setzen eine Fassung mit festen Antworten ein.
// - IAtlasCiSend (#1273): Schreiben (POST, PATCH) mit JSON, nur angemeldet;
//   die Issue-Vorschau schreibt darüber abgehakte Checklisten zurück.
// - TAtlasCiJob, TAtlasCiBuild und die Fehlerart liegen als Daten in Base
//   (Atlas.Core.CiBuild.Contract, #1455), weil die Projekt-Zusammenfassung sie
//   speichert.
// - IAtlasCiCredentialStore und IAtlasCiTransports (#1455, Rolle Adapters):
//   Anmeldespeicher und Transporte als Schnittstellen; die Umsetzungen
//   erzeugt nur Atlas.IDE.Tracker.Composition.
// Abfragen laufen im Hintergrund; nichts davon zeigt einen Dialog.

interface

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract;

type
  IAtlasCiTransport = interface
    ['{3E8B5C21-7D4A-4F96-A0B3-6C2E9F1D7A58}']
    /// <summary>GET auf AUrl mit höchstens ATimeoutMs. True, wenn eine Antwort kam (auch 404); AStatus ist der
    /// HTTP-Status, AText der Inhalt. False ohne Antwort (kein Netz, Zeitlimit, Abbruch) mit AError.</summary>
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Binäre Inhalte (Bilder und Anhänge der Issue-Vorschau, #1264) über denselben Transport, unter
  /// denselben Regeln für Anmeldung, Server und Weiterleitungen.</summary>
  IAtlasCiDownload = interface
    ['{5B1E8D43-2C7A-4F09-9E36-A84D1C7F2B65}']
    /// <summary>GET auf AUrl, höchstens AMaxBytes und ATimeoutMs; sonst wie IAtlasCiTransport.Get.</summary>
    function GetBytes(const AUrl: string; ATimeoutMs, AMaxBytes: Integer; out AStatus: Integer; out ABytes: TBytes;
      out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Schreiben über denselben Transport, für alle schreibenden Anfragen an den Tracker (#1273 Checklisten,
  /// #1279 Unteraufgaben und Verknüpfungen).</summary>
  IAtlasCiSend = interface
    ['{2D7A4E19-8B3C-4F61-A5D0-71E9C3B84F26}']
    /// <summary>AMethod ("POST", "PATCH") auf AUrl mit dem JSON ABody, höchstens ATimeoutMs. Nur mit Anmeldung beim
    /// eingetragenen Server über https (sonst False mit Unauthorized, ohne Netz); eine Weiterleitung ist ein Fehler
    /// (False mit Server), damit der Inhalt nie an ein anderes Ziel geht. True, wenn eine Antwort kam (auch 4xx);
    /// AStatus und AText wie bei IAtlasCiTransport.Get.</summary>
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Laufende und künftige Anfragen eines Transports abbrechen (Fenster geschlossen, #1264); sie enden
  /// mit TAtlasCiFetchError.Cancelled.</summary>
  IAtlasCiCancel = interface
    ['{9C4F2A71-6D3B-4E58-B1A7-3E0D5C8F9A24}']
    procedure Cancel;
  end;

  /// <summary>Bedingte Abfrage (#1271, GitHub /notifications): sendet If-Modified-Since und liest Last-Modified und
  /// X-Poll-Interval aus der Antwort, unter denselben Regeln wie IAtlasCiTransport.Get.</summary>
  IAtlasCiConditional = interface
    ['{E2A7C953-4B18-4D6F-9C31-7F5A0B2D8E46}']
    /// <summary>GET auf AUrl; AIfModifiedSince '' = ohne Bedingung. 304 heißt „unverändert“ (AText leer).
    /// ALastModified ist der Kopf Last-Modified ('' ohne), APollSeconds X-Poll-Interval (0 ohne).</summary>
    function GetConditional(const AUrl, AIfModifiedSince: string; ATimeoutMs: Integer; out AStatus: Integer;
      out AText, ALastModified: string; out APollSeconds: Integer; out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>POST beliebigen Inhalts an den Tracker (Anhänge und Kommentare, #1276) über denselben Transport, unter
  /// denselben Regeln wie IAtlasCiSend: nur mit Token über https an den eingetragenen Server (sonst False mit
  /// Unauthorized, ohne Netz); eine Weiterleitung ist ein Fehler.</summary>
  IAtlasCiPost = interface
    ['{2D7A5E19-8C43-4B6F-A1E0-7F3B9C25D814}']
    /// <summary>POST von ABody (AContentType) an AUrl mit höchstens ATimeoutMs. True, wenn eine Antwort kam (auch
    /// 4xx); AStatus ist der HTTP-Status, AText der Inhalt der Antwort. False ohne Antwort mit AError.</summary>
    function Post(const AUrl, AContentType: string; const ABody: TBytes; ATimeoutMs: Integer; out AStatus: Integer;
      out AText: string; out AError: TAtlasCiFetchError): Boolean;
  end;

  IAtlasCiProvider = interface
    ['{9A4D7E12-5B3C-4E81-8F6A-1D2C7B9E4F30}']
    /// <summary>Kennung wie in .atlas, z. B. "jenkins".</summary>
    function Name: string;
    /// <summary>Letzter abgeschlossener Build von AJob samt Testbericht, insgesamt höchstens ATimeoutMs; im
    /// Hintergrund. False mit AError, wenn kein Build gelesen werden konnte.</summary>
    function Fetch(const AJob: TAtlasCiJob; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
      out ABuild: TAtlasCiBuild; out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Seite des Builds ANumber für den Browser; '' ohne.</summary>
    function BuildPage(const AJob: TAtlasCiJob; ANumber: Integer): string;
  end;

  /// <summary>Zugänge im Anmeldespeicher (Ziel wie TAtlasCiJob.CredentialTarget); Lesen auch im Hintergrund.
  /// </summary>
  IAtlasCiCredentialStore = interface
    ['{5B55F5F5-5096-42DC-888A-6C79045AB11D}']
    /// <summary>Eintrag zu ATarget lesen; False ohne Eintrag.</summary>
    function Read(const ATarget: string; out AUser, AToken: string): Boolean;
    /// <summary>Eintrag anlegen oder ersetzen, AComment für die Anmeldeinformationsverwaltung ('' = Vorgabe);
    /// False bei Fehler oder zu langem Token.</summary>
    function Write(const ATarget, AUser, AToken, AComment: string): Boolean;
    /// <summary>Eintrag entfernen; True auch, wenn es keinen gab.</summary>
    function Delete(const ATarget: string): Boolean;
  end;

  /// <summary>Transporte zum Build-Server bzw. zur API eines Trackers; im Hintergrund.</summary>
  IAtlasCiTransports = interface
    ['{93BA3560-1066-45CA-ABA7-0FAF3535C8DB}']
    /// <summary>Anmeldung mit Benutzer und Token (Basic); beide leer = ohne Anmeldung.</summary>
    function Basic(const AServer, AUser, AToken: string): IAtlasCiTransport;
    /// <summary>Anmeldung mit „Authorization: Bearer“ (#765); AToken leer = ohne Anmeldung.</summary>
    function Bearer(const AServer, AToken: string): IAtlasCiTransport;
  end;

implementation

end.
