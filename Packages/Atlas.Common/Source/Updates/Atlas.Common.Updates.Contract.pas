unit Atlas.Common.Updates.Contract;

// Platform-Feature "Updates" (#1519), Contract: alles, was AtlasUpdate.exe vom
// System braucht (Registry des Benutzers, Dateien, laufende Prozesse,
// Prüfsummen und Signaturen, Netz, ZIP, Compiler), als Schnittstellen. Die
// Logik in Atlas.Common.Updates.* kennt weder Windows noch Netz und ist so
// mit Attrappen testbar; die echten Umsetzungen stehen in
// Atlas.Windows.Updates.Adapters.*. Pfade sind Windows-Pfade.

interface

uses
  System.SysUtils;

type
  /// <summary>Eine Zeile für Benutzer und Protokoll; auch die Ausgabe des Compilers. Ein gemeinsamer Typ, weil
  /// Delphi 12 gleich aufgebaute Methodenreferenzen nicht einander zuweist.</summary>
  TUpdateLog = reference to procedure(const AText: string);

  TUpdateRegistryValue = record
    Name: string;
    Data: string;
  end;

  /// <summary>Registry unter HKEY_CURRENT_USER; RootDir einer Delphi-Version aus HKEY_LOCAL_MACHINE.</summary>
  IUpdateRegistry = interface
    ['{5C0F6B1E-3A2D-4E8B-9F71-2D6A8C4B1E07}']
    function SubKeys(const AKey: string): TArray<string>;
    function Values(const AKey: string): TArray<TUpdateRegistryValue>;
    /// <summary>Legt den Schlüssel bei Bedarf an.</summary>
    procedure WriteValue(const AKey, AName, AData: string);
    /// <summary>Ein fehlender Wert ist kein Fehler.</summary>
    procedure DeleteValue(const AKey, AName: string);
    /// <summary>Installationsordner der Delphi-Version ABdsVersion (z. B. „37.0“); '' ohne Installation.</summary>
    function RootDir(const ABdsVersion: string): string;
  end;

  IUpdateFiles = interface
    ['{8E2A4C6D-1B3F-4A57-8C9E-0F2D4B6A8C13}']
    function FileExists(const AFileName: string): Boolean;
    function DirectoryExists(const ADirectory: string): Boolean;
    /// <summary>Alle Dateien unter ADirectory mit Unterordnern, relativ zu ADirectory; leer ohne Ordner.</summary>
    function FilesIn(const ADirectory: string): TArray<string>;
    /// <summary>Legt den Zielordner an und überschreibt; EInOutError, wenn die Datei gesperrt ist.</summary>
    procedure CopyFile(const ASource, ATarget: string);
    /// <summary>Umbenennen bzw. Verschieben im selben Laufwerk (geht auch bei laufender EXE).</summary>
    procedure MoveFile(const ASource, ATarget: string);
    /// <summary>Eine fehlende Datei ist kein Fehler; EInOutError, wenn sie gesperrt ist.</summary>
    procedure DeleteFile(const AFileName: string);
    /// <summary>Mit Inhalt; ein fehlender Ordner ist kein Fehler.</summary>
    procedure DeleteDirectory(const ADirectory: string);
    procedure ForceDirectories(const ADirectory: string);
    /// <summary>UTF-8; '' ohne Datei.</summary>
    function ReadText(const AFileName: string): string;
    /// <summary>UTF-8 ohne BOM, atomar, legt den Ordner an.</summary>
    procedure WriteText(const AFileName, AText: string);
    procedure AppendText(const AFileName, AText: string);
    /// <summary>In ADirectory lassen sich Dateien anlegen (sonst Adminrechte nötig).</summary>
    function CanWrite(const ADirectory: string): Boolean;
  end;

  TUpdateProcess = record
    Pid: Cardinal;
    Name: string;
  end;

  IUpdateProcesses = interface
    ['{2F6B8D0A-4C1E-4B39-A75D-6E8C0A2F4B91}']
    /// <summary>Prozesse, die ein Package (.bpl) aus AFolder oder einem Unterordner geladen haben.</summary>
    function UsingPackages(const AFolder: string): TArray<TUpdateProcess>;
    function IsRunning(APid: Cardinal): Boolean;
    procedure Sleep(AMilliseconds: Integer);
    /// <summary>Abbruch durch den Benutzer (Strg+C, Fenster geschlossen), solange noch nichts getauscht ist.
    /// </summary>
    function CancelRequested: Boolean;
  end;

  TUpdateSignature = record
    /// <summary>Authenticode-Signatur vorhanden, Kette gültig und nicht widerrufen.</summary>
    Valid: Boolean;
    /// <summary>Name des Herausgebers aus dem Zertifikat; '' ohne Signatur.</summary>
    Subject: string;
  end;

  IUpdateTrust = interface
    ['{7A9C1E3B-5D2F-4C68-B04A-1E3C5A7B9D26}']
    /// <summary>SHA-256 als 64 kleine Hexziffern.</summary>
    function Sha256(const AFileName: string): string;
    function Signature(const AFileName: string): TUpdateSignature;
  end;

  TUpdateProgress = reference to procedure(APercent: Integer);

  IUpdateNetwork = interface
    ['{3D5F7A9C-6B1E-4D82-91C3-5A7D9F1B3E48}']
    /// <summary>Kleine Textdatei (Versionsdatei) lesen; False mit AError (ohne Adresse).</summary>
    function Fetch(const AUrl: string; out AText, AError: string): Boolean;
    /// <summary>Nur https; AProgress mit 0 bis 100; False mit AError (ohne Adresse).</summary>
    function Download(const AUrl, AFileName: string; const AProgress: TUpdateProgress; out AError: string): Boolean;
  end;

  IUpdateArchive = interface
    ['{9B1D3F5A-7C2E-4E93-A2D4-6B8E0C2A4F59}']
    /// <summary>Namen der Einträge (Dateien) des ZIP, wie sie darin stehen.</summary>
    function Entries(const AZipFile: string): TArray<string>;
    /// <summary>Eintrag AEntry nach ATargetFile entpacken (Ordner wird angelegt).</summary>
    procedure Extract(const AZipFile, AEntry, ATargetFile: string);
  end;

  IUpdateBuilder = interface
    ['{4E6A8C0B-2D3F-4F17-B3E5-7C9A1D3B5F60}']
    /// <summary>Kommandozeilen-Compiler der Delphi-Version ABdsVersion für APlatform vorhanden; sonst False mit
    /// AReason = fehlender Compiler (z. B. dcc32.exe; die Starter-Edition hat keinen).</summary>
    function CanBuild(const ABdsVersion, APlatform: string; out AReason: string): Boolean;
    /// <summary>AProject (.dproj) als Release für APlatform bauen; Exit-Code 0 = Erfolg.</summary>
    function Build(const ABdsVersion, APlatform, AProject: string; const AOnLine: TUpdateLog): Integer;
  end;

  /// <summary>Alle Zugänge zum System zusammen; die Composition setzt sie.</summary>
  TUpdateSystem = record
    Registry: IUpdateRegistry;
    Files: IUpdateFiles;
    Processes: IUpdateProcesses;
    Trust: IUpdateTrust;
    Network: IUpdateNetwork;
    Archive: IUpdateArchive;
    Builder: IUpdateBuilder;
    /// <summary>Fortschritt für den Benutzer (Konsole) und das Protokoll.</summary>
    Log: TUpdateLog;
  end;

  EUpdateError = class(Exception)
  private
    FCode: string;
    FDetail: string;
  public
    /// <summary>ACode aus TUpdateErrors, ADetail ohne Adressen.</summary>
    constructor CreateCode(const ACode, ADetail: string);
    property Code: string read FCode;
    property Detail: string read FDetail;
  end;

implementation

{ EUpdateError }

constructor EUpdateError.CreateCode(const ACode, ADetail: string);
begin
  inherited Create(ACode + ': ' + ADetail);
  FCode := ACode;
  FDetail := ADetail;
end;

end.
