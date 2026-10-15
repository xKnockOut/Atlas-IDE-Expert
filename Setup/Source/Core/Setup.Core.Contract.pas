unit Setup.Core.Contract;

// Installer (#495): alles, was der Installer vom System braucht (Registry
// des Benutzers und des Rechners, Dateien, laufende Programme), als
// Schnittstelle. Der Kern kennt weder Windows noch VCL und ist so mit einer
// Attrappe testbar; die echte Umsetzung steht in Setup.Adapters.WindowsSystem.
// Registry-Schlüssel sind relativ zu HKEY_CURRENT_USER bzw. (Machine…)
// HKEY_LOCAL_MACHINE, dort in beiden Ansichten (32 und 64 Bit).

interface

type
  ISetupSystem = interface
    ['{0D7C6E21-4B8F-4F3A-9E62-5C1A7B3D9E04}']
    function SubKeys(const AKey: string): TArray<string>;
    function MachineSubKeys(const AKey: string): TArray<string>;
    /// <summary>'' wenn Schlüssel oder Wert fehlt.</summary>
    function ReadString(const AKey, AName: string): string;
    function MachineReadString(const AKey, AName: string): string;
    function ValueNames(const AKey: string): TArray<string>;
    /// <summary>Legt den Schlüssel bei Bedarf an.</summary>
    procedure WriteString(const AKey, AName, AValue: string);
    procedure WriteInteger(const AKey, AName: string; AValue: Integer);
    procedure DeleteValue(const AKey, AName: string);
    /// <summary>Mit allen Unterschlüsseln; ein fehlender Schlüssel ist kein Fehler.</summary>
    procedure DeleteKey(const AKey: string);
    function FileExists(const AFileName: string): Boolean;
    function DirectoryExists(const ADirectory: string): Boolean;
    /// <summary>Legt den Zielordner an und überschreibt; Ausnahme, wenn die Datei gesperrt ist.</summary>
    procedure CopyFile(const ASource, ATarget: string);
    procedure DeleteFile(const AFileName: string);
    /// <summary>Mit Inhalt; ein fehlender Ordner ist kein Fehler.</summary>
    procedure DeleteDirectory(const ADirectory: string);
    /// <summary>Ordner löschen, sobald dieser Prozess beendet ist (der Installer liegt selbst darin).</summary>
    procedure DeleteDirectoryLater(const ADirectory: string);
    function FileSize(const AFileName: string): Int64;
    /// <summary>Namen der Dateien direkt in ADirectory (ohne Unterordner); leer, wenn es ihn nicht gibt.</summary>
    function FilesIn(const ADirectory: string): TArray<string>;
    /// <summary>Vollständige Pfade der laufenden Programme.</summary>
    function RunningExecutables: TArray<string>;
  end;

implementation

end.
