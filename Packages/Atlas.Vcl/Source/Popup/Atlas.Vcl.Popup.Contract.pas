unit Atlas.Vcl.Popup.Contract;

// Contract des Features Popup (#1443): Einträge einer Liste, die ein Atlas-Fenster für UI Automation
// bereitstellt (#447); die Umsetzung in Atlas.Vcl.Popup.Accessibility liest sie über dieses Interface.

interface

uses
  System.Types;

type
  /// <summary>Einträge einer Liste für UI Automation (#447); Positionen in der Anzeigereihenfolge.</summary>
  IAtlasAccessibleItems = interface
    ['{5C0F3E52-8A47-4D3B-9E61-2B7A4C1D9F08}']
    function AccessibleCount: Integer;
    /// <summary>Gewählte Position; -1 ohne.</summary>
    function AccessibleSelected: Integer;
    /// <summary>Schlüssel des Eintrags an APosition, der beim Filtern gleich bleibt.</summary>
    function AccessibleId(APosition: Integer): Integer;
    function AccessibleName(APosition: Integer): string;
    /// <summary>Zustand in Worten („deprecated, Helper“); '' ohne.</summary>
    function AccessibleStatus(APosition: Integer): string;
    /// <summary>Kurzbeschreibung (Signatur, Herkunft); '' ohne.</summary>
    function AccessibleHelp(APosition: Integer): string;
    /// <summary>Überschrift einer Gruppe statt eines Eintrags; nicht wählbar.</summary>
    function AccessibleIsHeader(APosition: Integer): Boolean;
    /// <summary>Zeile in Bildschirmkoordinaten; False, wenn sie nicht sichtbar ist.</summary>
    function AccessibleBounds(APosition: Integer; out ARect: TRect): Boolean;
    procedure AccessibleSelect(APosition: Integer);
  end;

implementation

end.
