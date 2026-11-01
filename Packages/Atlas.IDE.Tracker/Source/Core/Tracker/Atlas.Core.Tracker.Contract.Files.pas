unit Atlas.Core.Tracker.Contract.Files;

// Datei- und Prozesszugriff des Tracker-Moduls (#1455 Paket 2d), ohne VCL und
// Open Tools API. Die Units in Core/Tracker (Meldungen, Board, Issue-Cache,
// Zeiterfassung, Commit-Hook, Anhänge) und die Oberfläche des Trackers
// erreichen Platte, Umgebung und Shell nur über diese Schnittstellen:
// - IAtlasTrackerFiles: Dateien und Ordner lesen, schreiben, auflisten und
//   löschen, Sperrdatei, Umgebungsvariable, Temp-Ordner. Keine Methode wirft;
//   Fehler kommen als False, leeres Ergebnis bzw. nil zurück.
// - IAtlasTrackerShell: Adresse oder Datei mit dem zugeordneten Programm
//   öffnen, Datei im Explorer zeigen.
// Die echten Umsetzungen liegen in Atlas.Core.Tracker.Adapters.LocalFiles und
// Atlas.Core.Tracker.Adapters.Shell; nur Atlas.IDE.Tracker.Composition (und
// die Tests) erzeugt sie und meldet sie bei Atlas.Core.Tracker.Files an.

interface

uses
  System.SysUtils;

type
  /// <summary>Dateizugriff des Trackers; Text immer UTF-8.</summary>
  IAtlasTrackerFiles = interface
    ['{7740BA78-E5EE-4595-9EB6-3651942FB78C}']
    function FileExists(const AFileName: string): Boolean;
    function FolderExists(const AFolder: string): Boolean;
    /// <summary>Ganze Datei als UTF-8 (BOM wird übergangen); False, wenn sie fehlt oder nicht lesbar ist.
    /// </summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Höchstens AMaxBytes vom Anfang; liest auch, während ein anderes Programm schreibt.</summary>
    function ReadHead(const AFileName: string; AMaxBytes: Integer; out AData: TBytes): Boolean;
    /// <summary>Höchstens AMaxBytes vom Ende (0 = ganz); ACut: vorn fehlt etwas.</summary>
    function ReadTail(const AFileName: string; AMaxBytes: Integer; out AData: TBytes; out ACut: Boolean): Boolean;
    /// <summary>Text als UTF-8 mit BOM schreiben; der Ordner wird angelegt.</summary>
    function WriteText(const AFileName, AText: string): Boolean;
    /// <summary>Wie WriteText, aber erst daneben geschrieben und dann ersetzt: Ein Abbruch lässt nie eine halbe
    /// Datei zurück.</summary>
    function ReplaceText(const AFileName, AText: string): Boolean;
    /// <summary>Bytes unverändert schreiben; der Ordner wird angelegt.</summary>
    function WriteBytes(const AFileName: string; const AData: TBytes): Boolean;
    /// <summary>True, wenn die Datei danach fehlt.</summary>
    function DeleteFile(const AFileName: string): Boolean;
    /// <summary>Ordner samt Inhalt löschen; True, wenn er danach fehlt.</summary>
    function DeleteFolder(const AFolder: string): Boolean;
    /// <summary>Ordner nur löschen, wenn er leer ist.</summary>
    function RemoveEmptyFolder(const AFolder: string): Boolean;
    /// <summary>Ordner samt fehlender Elternordner anlegen.</summary>
    function ForceFolder(const AFolder: string): Boolean;
    /// <summary>Dateien in AFolder (nicht rekursiv) zur Maske mit * und ?; volle Pfade.</summary>
    function Files(const AFolder, AMask: string): TArray<string>;
    /// <summary>Unterordner von AFolder; volle Pfade.</summary>
    function Folders(const AFolder: string): TArray<string>;
    /// <summary>Letzte Änderung einer Datei oder eines Ordners; 0, wenn es ihn nicht gibt.</summary>
    function WriteTime(const APath: string): TDateTime;
    /// <summary>Sperrdatei AFileName exklusiv öffnen und bis zu AWaitMs warten; nil ohne Sperre. Freigabe mit
    /// dem letzten Verweis.</summary>
    function Lock(const AFileName: string; AWaitMs: Integer): IInterface;
    /// <summary>Wert einer Umgebungsvariablen; '' ohne.</summary>
    function Environment(const AName: string): string;
    /// <summary>Temp-Ordner des Benutzers.</summary>
    function TempFolder: string;
  end;

  /// <summary>Programme der Shell für den Tracker.</summary>
  IAtlasTrackerShell = interface
    ['{ECB2BCD6-E093-4750-BD69-61EDF743FB5D}']
    /// <summary>Adresse oder Datei mit dem zugeordneten Programm öffnen.</summary>
    function Open(const ATarget: string): Boolean;
    /// <summary>Datei öffnen, Arbeitsordner ist ihr Ordner.</summary>
    function OpenFile(const AFileName: string): Boolean;
    /// <summary>Ordner der Datei im Explorer zeigen, die Datei markiert.</summary>
    function Reveal(const AFileName: string): Boolean;
  end;

implementation

end.
