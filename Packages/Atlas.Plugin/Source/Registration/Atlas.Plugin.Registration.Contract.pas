unit Atlas.Plugin.Registration.Contract;

// Anmeldung mit Besitzer für Base und Module (#1455, Regel 4): Wer etwas anmeldet (Hörer, Beitrag, Teil einer
// Einstellungsseite), bekommt eine IAtlasRegistration zurück und löst die Anmeldung damit wieder. Umsetzung in
// Atlas.Plugin.Registration.

interface

type
  /// <summary>Eine Anmeldung mit Besitzer (Regel 4). Revoke löst sie; mehrfach aufrufbar, danach erreicht über
  /// diese Anmeldung kein Aufruf mehr den Besitzer.</summary>
  IAtlasRegistration = interface
    ['{955A70D5-92CA-4E1D-B41A-40BFCDFB9BB5}']
    procedure Revoke;
    function IsRevoked: Boolean;
  end;

implementation

end.
