unit Atlas.Common.Leaks.Contract;

// Vertrag der Leckprüfung: was die Komposition für die Einrichtung (Atlas.Common.Leaks.Setup) liefert.

interface

type
  /// <summary>Dateizugriffe von außen (Tests ohne Platte).</summary>
  ILeakSetupFiles = interface
    ['{62B7614D-5288-48D9-BA5E-A2FB3237CC5B}']
    function FileExists(const AFileName: string): Boolean;
    /// <summary>Liest eine Textdatei; False, wenn sie fehlt.</summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
  end;

implementation

end.
