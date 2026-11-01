unit Atlas.Core.Modules.Contract;

// Allgemeine Verträge zwischen Base und den Modulen des Plugins (#1455,
// ADR 0017, Regeln 1–9 in docs/Architektur.md „Module und Verträge des
// Plugins“). Nur Interfaces mit GUID, Records und Konstanten; Base versteht
// nicht, was ein Modul anbietet, und kennt keine Modulnamen (Regel 9).
// - IAtlasModule: Deskriptor, den ein Modul in seinem Register anmeldet;
//   gestartet und gestoppt wird nur über Base (Regel 1).
// - IAtlasModuleScope: sammelt jede Anmeldung eines Moduls und löst sie beim
//   Abmelden rückwärts (Regel 4); danach erreicht nichts mehr das Modul
//   (Regel 3).
// - IAtlasModuleRegistry: Modulliste aus Anmeldungen, Objekte nach
//   Interface-GUID (Provide/FindAll) und Änderungsmeldung (Regel 2).
// - cAtlasCoreContractVersion: Versions-Handschlag (Regel 7); jede Änderung an
//   einem Vertrag im interface-Teil von Base erhöht sie.

interface

uses
  System.SysUtils;

const
  /// <summary>Vertragsversion von Base (Regel 7). Erhöhen, sobald sich ein Vertrag von Base ändert, den Module
  /// übersetzen (Interface, Record, Konstante): Delphi prüft die Binärschnittstelle zwischen Packages nicht.</summary>
  cAtlasCoreContractVersion = 1;
  /// <summary>Name der exportierten Funktion, die cAtlasCoreContractVersion liefert
  /// (Atlas.Core.Modules.Handshake); ein Modul fragt sie über GetProcAddress ab.</summary>
  cAtlasCoreContractExport = 'AtlasCoreContractVersion';

type
  /// <summary>Angaben eines Moduls. Id ist dauerhaft und eindeutig (z. B. „atlas.debugger“), Name die Anzeige,
  /// Version die des Moduls. Handle ist das HMODULE des Packages (HInstance des Moduls) für die Frage „gehört
  /// das zu Atlas?“ (Regel 8); 0, wenn unbekannt.</summary>
  TAtlasModuleInfo = record
    Id: string;
    Name: string;
    Version: string;
    Handle: NativeUInt;
  end;

  /// <summary>Ein Modul, das sich einmal angemeldet hat (Regel 9): Installed, solange es angemeldet ist; sonst
  /// zeigt die Modulseite es als „nicht installiert“. Info.Handle ist bei nicht installierten Modulen 0.</summary>
  TAtlasKnownModule = record
    Info: TAtlasModuleInfo;
    Installed: Boolean;
  end;

  /// <summary>Eine Anmeldung mit Besitzer (Regel 4). Revoke löst sie; mehrfach aufrufbar, danach erreicht über
  /// diese Anmeldung kein Aufruf mehr den Besitzer.</summary>
  IAtlasRegistration = interface
    ['{955A70D5-92CA-4E1D-B41A-40BFCDFB9BB5}']
    procedure Revoke;
    function IsRevoked: Boolean;
  end;

  /// <summary>Art einer Änderung in der Registry: Modul an- bzw. abgemeldet, Objekt bereitgestellt bzw. zurückgezogen,
  /// Liste der bekannten Module geändert (Modul vergessen).</summary>
  TAtlasRegistryChangeKind = (rcModuleAdded, rcModuleRemoved, rcProvided, rcRevoked, rcKnownChanged);

  /// <summary>Eine Änderung: ModuleId ist der Besitzer ('' für Base), IID nur bei rcProvided und rcRevoked
  /// gesetzt.</summary>
  TAtlasRegistryChange = record
    Kind: TAtlasRegistryChangeKind;
    ModuleId: string;
    IID: TGUID;
  end;

  /// <summary>Hört auf die Änderungsmeldung der Registry (Regel 2). Wird im Thread der Änderung gerufen (Hauptthread
  /// der IDE), nie unter einer Sperre der Registry.</summary>
  IAtlasRegistryListener = interface
    ['{3ADBAB46-113E-4AF3-A0E8-E211F8547C66}']
    procedure RegistryChanged(const AChange: TAtlasRegistryChange);
  end;

  /// <summary>Alles, was ein Modul in Base anmeldet, läuft hierüber und trägt dessen Id (Regel 4). Beim Abmelden
  /// des Moduls löst Base jede Anmeldung in umgekehrter Reihenfolge; danach ist der Scope geschlossen.</summary>
  IAtlasModuleScope = interface
    ['{41487819-8DA7-4E6E-AC2B-AB584E0930E7}']
    function ModuleId: string;
    /// <summary>Offen bis zum Abmelden des Moduls.</summary>
    function IsOpen: Boolean;
    /// <summary>ARegistration übernehmen und beim Abmelden lösen. Ist der Scope schon geschlossen, wird sie sofort
    /// gelöst: Nach dem Abmelden bleibt nichts vom Modul angemeldet (Regel 3).</summary>
    procedure Own(const ARegistration: IAtlasRegistration);
    /// <summary>AObject unter AIID mit diesem Modul als Besitzer bereitstellen; AObject muss AIID unterstützen.</summary>
    function Provide(const AIID: TGUID; const AObject: IInterface): IAtlasRegistration;
    /// <summary>Auf Änderungen der Registry hören, bis zum Abmelden des Moduls.</summary>
    function Subscribe(const AListener: IAtlasRegistryListener): IAtlasRegistration;
  end;

  /// <summary>Deskriptor eines Moduls (Regel 1). Das Register eines Moduls meldet ihn nur an; Start, Stop und
  /// IsActive ruft allein Base (Feature-Tabelle).</summary>
  IAtlasModule = interface
    ['{BE36778B-C910-418F-AE72-CE1C9AD251AB}']
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
  end;

  /// <summary>Modulliste aus Anmeldungen (Regel 9) und Ablage für Objekte nach Interface-GUID. Besteht ab der
  /// Unit-Initialisierung von Base (Regel 1).</summary>
  IAtlasModuleRegistry = interface
    ['{AC5A806A-1AEF-41E1-B78F-4B039EA312C9}']
    /// <summary>AModule anmelden; liefert seinen Scope. Leere oder schon angemeldete Id: EAtlasModuleRegistry.</summary>
    function RegisterModule(const AModule: IAtlasModule): IAtlasModuleScope;
    /// <summary>Modul AModuleId abmelden: stoppen, wenn aktiv, dann seinen Scope rückwärts lösen. Ein Fehler hält
    /// den Abbau nicht an; Ergebnis: die fehlgeschlagenen Schritte als „Schritt: Klasse: Meldung“.</summary>
    function UnregisterModule(const AModuleId: string): TArray<string>;
    /// <summary>Angemeldete Module in Reihenfolge der Anmeldung.</summary>
    function Modules: TArray<IAtlasModule>;
    /// <summary>Angemeldetes Modul AModuleId; False, wenn es nicht angemeldet ist.</summary>
    function FindModule(const AModuleId: string; out AModule: IAtlasModule): Boolean;
    /// <summary>Jedes Modul, das sich einmal angemeldet hat, in Reihenfolge der ersten Anmeldung (Regel 9).</summary>
    function Known: TArray<TAtlasKnownModule>;
    /// <summary>Nicht installiertes Modul aus der Liste der bekannten entfernen (der Benutzer räumt auf). False,
    /// wenn es angemeldet oder unbekannt ist.</summary>
    function ForgetModule(const AModuleId: string): Boolean;
    /// <summary>Gehört AHandle zu einem angemeldeten Modul (Regel 8)?</summary>
    function IsModuleHandle(AHandle: NativeUInt): Boolean;
    /// <summary>AObject unter AIID mit Base als Besitzer bereitstellen; Module nehmen IAtlasModuleScope.Provide.</summary>
    function Provide(const AIID: TGUID; const AObject: IInterface): IAtlasRegistration;
    /// <summary>Alle unter AIID bereitgestellten Objekte in Reihenfolge der Bereitstellung.</summary>
    function FindAll(const AIID: TGUID): TArray<IInterface>;
    /// <summary>Auf Änderungen hören; Module nehmen IAtlasModuleScope.Subscribe.</summary>
    function Subscribe(const AListener: IAtlasRegistryListener): IAtlasRegistration;
  end;

  /// <summary>Falsche Benutzung der Registry (leere oder doppelte Modul-Id, Objekt ohne das Interface).</summary>
  EAtlasModuleRegistry = class(Exception);

implementation

end.
