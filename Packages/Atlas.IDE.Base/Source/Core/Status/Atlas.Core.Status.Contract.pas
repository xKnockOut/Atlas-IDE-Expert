unit Atlas.Core.Status.Contract;

// Schnittstelle des Atlas-Statusfelds (#591), ohne VCL und Open Tools API:
// Jede Funktion, die etwas in der Statusleiste zeigen will (Server, Index,
// Datei, später Fehlerzähler #509, Compilerprüfung #548 …), meldet eine Zeile
// als IAtlasStatusItem bei IAtlasStatusRegistry an und ruft Changed, wenn
// sich ihr Inhalt ändert. Das Feld in der Statusleiste und das Fenster beim
// Klick lesen nur die Registry; neue Zeilen brauchen keine Änderung an der
// Oberfläche. Die Zustandskachel der Willkommensseite (#754) liest dieselben
// Zeilen; die optionale Schnittstelle IAtlasStatusBrief liefert ihr eine
// Kurzform mit Zusatz rechts.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Zustand einer Zeile, aufsteigend nach Schwere: Neutral (keine Aussage), Grün (in
  /// Ordnung), Gelb (Warnung, läuft noch, langsam), Rot (gestoppt, Fehler).</summary>
  TAtlasStatusState = (Neutral, Green, Yellow, Red);
{$SCOPEDENUMS OFF}

  IAtlasStatusItem = interface
    ['{6B1F4C2E-3A97-4D58-9E0B-21C7A5D3F864}']
    /// <summary>Eindeutige Kennung, z. B. "atlas.server"; für statusField.hidden.</summary>
    function Id: string;
    /// <summary>Zeile im Fenster, z. B. "Server: läuft, 12 ms im Mittel, Version 1.0.0".</summary>
    function Text: string;
    /// <summary>Kurztext neben „Atlas“ (z. B. "2 Fehler"); '' = keiner.</summary>
    function Summary: string;
    function State: TAtlasStatusState;
    /// <summary>Reihenfolge im Fenster, kleiner zuerst; bei Gleichstand nach Kennung.</summary>
    function Order: Integer;
    /// <summary>True, wenn ein Klick auf die Zeile etwas tut (Execute).</summary>
    function HasAction: Boolean;
    /// <summary>Aktion bei Klick auf die Zeile; im Hauptthread.</summary>
    procedure Execute;
  end;

  /// <summary>Optionale Kurzform einer Zeile für die Zustandskachel der Willkommensseite (#754). Zustand und
  /// Aktion bleiben die der Zeile; Zeilen ohne diese Schnittstelle zeigen dort ihren Text.</summary>
  IAtlasStatusBrief = interface
    ['{9C4E2B71-0D5A-4F3E-8B26-7A1F6C93D4E5}']
    /// <summary>Kurzer Text, z. B. "Server läuft"; '' = Text der Zeile.</summary>
    function Brief: string;
    /// <summary>Zusatz rechts, z. B. "seit 19:02"; '' = keiner.</summary>
    function Detail: string;
  end;

  IAtlasStatusRegistry = interface
    ['{0D93E7A4-5C21-4B8F-A6E3-9F48B2C1D057}']
    /// <summary>Meldet AItem an; eine Zeile mit derselben Kennung wird ersetzt.</summary>
    procedure Add(const AItem: IAtlasStatusItem);
    procedure Remove(const AId: string);
    /// <summary>nil, wenn keine Zeile diese Kennung hat.</summary>
    function Find(const AId: string): IAtlasStatusItem;
    /// <summary>Alle Zeilen nach Order, dann Kennung.</summary>
    function Items: TArray<IAtlasStatusItem>;
    /// <summary>Eine Zeile hat sich geändert; benachrichtigt alle Beobachter. Aus jedem Thread.</summary>
    procedure Changed;
    /// <summary>Zählt jede Änderung (Add, Remove, Changed).</summary>
    function Version: Integer;
    /// <summary>Beobachter für Änderungen; läuft im Thread des Aufrufers von Changed.</summary>
    function AddListener(const AListener: TProc): Integer;
    procedure RemoveListener(AHandle: Integer);
  end;

implementation

end.
