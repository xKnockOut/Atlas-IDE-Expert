unit Atlas.Core.Notifications.Contract;

// Schnittstelle der Benachrichtigungszentrale (#601), ohne VCL und Open Tools
// API: Jede Funktion, die einen kurzen Hinweis zeigt (Build fertig #535,
// Dateien neu geladen #536, Server neu gestartet #393, Tastenkürzel-Tipps
// #600, Hintergrundprüfung #548, später Build-Server #763 …), meldet ihn als
// Eintrag bei IAtlasNotificationCenter. Die Zentrale sammelt die Einträge der
// IDE-Sitzung, fasst gleichartige innerhalb von 10 s zusammen und sagt der
// meldenden Funktion, ob sie ihre eigene Einblendung zeigen soll (Verhalten
// je Quelle: einblenden und sammeln, nur sammeln, aus). Liste und Zähler im
// Atlas-Statusfeld lesen nur die Zentrale; neue Quellen brauchen keine
// Änderung an der Oberfläche.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Schwere eines Eintrags, aufsteigend.</summary>
  TAtlasNotificationSeverity = (Info, Warning, Error);
  /// <summary>Verhalten je Quelle: Show = eigene Einblendung und Eintrag in der Liste (Vorgabe), Collect = nur
  /// der Eintrag, Off = weder noch.</summary>
  TAtlasNotificationMode = (Show, Collect, Off);
{$SCOPEDENUMS OFF}

  /// <summary>Aktion eines Eintrags, als Knopf in der Liste (z. B. „Zum Fehler“). Run läuft im Hauptthread; die
  /// Zentrale markiert den Eintrag vorher als gelesen.</summary>
  TAtlasNotificationAction = record
    Caption: string;
    Run: TProc;
  end;

  IAtlasNotification = interface
    ['{5E2C7A91-3B4D-4F60-8A1E-9C7D2B6F0A13}']
    /// <summary>Kennung, fortlaufend je Sitzung ab 1; bleibt beim Zusammenfassen gleich.</summary>
    function Id: Integer;
    /// <summary>Quelle, z. B. "build" (TAtlasNotificationSources).</summary>
    function Source: string;
    function Severity: TAtlasNotificationSeverity;
    /// <summary>Titel ohne Zähler, z. B. "Server neu gestartet".</summary>
    function Title: string;
    function Text: string;
    /// <summary>Zeitpunkt der letzten Meldung (Ortszeit).</summary>
    function Time: TDateTime;
    /// <summary>Wie oft der Hinweis innerhalb der Zusammenfassung kam; mindestens 1.</summary>
    function Count: Integer;
    function Read: Boolean;
    function Actions: TArray<TAtlasNotificationAction>;
    /// <summary>Titel mit Zähler: "3 × Server neu gestartet"; bei Count = 1 der Titel.</summary>
    function Caption: string;
  end;

  IAtlasNotificationCenter = interface
    ['{A4F1B83C-6D29-4E57-B0C2-1F8E3D7A5C96}']
    /// <summary>Meldet einen Hinweis; aus jedem Thread. Ergebnis: Verhalten der Quelle. Nur bei Show zeigt die
    /// meldende Funktion ihre eigene Einblendung; bei Off entsteht kein Eintrag. Ist die Zentrale aus
    /// (Enabled = False), gilt immer Show und es entsteht kein Eintrag (Verhalten wie vor #601).</summary>
    function Notify(const ASource: string; ASeverity: TAtlasNotificationSeverity;
      const ATitle, AText: string): TAtlasNotificationMode; overload;
    function Notify(const ASource: string; ASeverity: TAtlasNotificationSeverity; const ATitle, AText: string;
      const AActions: TArray<TAtlasNotificationAction>): TAtlasNotificationMode; overload;
    /// <summary>Verhalten der Quelle (ohne Eintrag Show); mit ausgeschalteter Zentrale immer Show.</summary>
    function ModeOf(const ASource: string): TAtlasNotificationMode;
    procedure SetMode(const ASource: string; AMode: TAtlasNotificationMode);
    /// <summary>Alle Einträge, neueste zuerst.</summary>
    function Items: TArray<IAtlasNotification>; overload;
    /// <summary>Einträge einer Quelle (ohne Groß-/Kleinschreibung), neueste zuerst; '' = alle.</summary>
    function Items(const ASource: string): TArray<IAtlasNotification>; overload;
    /// <summary>nil, wenn es den Eintrag nicht (mehr) gibt.</summary>
    function Find(AId: Integer): IAtlasNotification;
    /// <summary>Quellen der vorhandenen Einträge in der Reihenfolge ihres ersten Auftretens in Items.</summary>
    function Sources: TArray<string>;
    procedure MarkRead(AId: Integer);
    procedure MarkAllRead;
    /// <summary>Liste leeren.</summary>
    procedure Clear;
    /// <summary>Markiert den Eintrag als gelesen und führt Aktion AIndex aus (im Thread des Aufrufers, also aus
    /// der Liste im Hauptthread). False, wenn es Eintrag oder Aktion nicht gibt.</summary>
    function RunAction(AId, AIndex: Integer): Boolean;
    function UnreadCount: Integer;
    /// <summary>Schwerster ungelesener Eintrag; False ohne ungelesene.</summary>
    function WorstUnread(out ASeverity: TAtlasNotificationSeverity): Boolean;
    /// <summary>Höchstens so viele Einträge; ältere fallen weg.</summary>
    function MaxEntries: Integer;
    procedure SetMaxEntries(AValue: Integer);
    /// <summary>Zählt jede Änderung.</summary>
    function Version: Integer;
    /// <summary>Beobachter für Änderungen; läuft im Thread des Aufrufers, der die Änderung auslöst.</summary>
    function AddListener(const AListener: TProc): Integer;
    procedure RemoveListener(AHandle: Integer);
  end;

implementation

end.
