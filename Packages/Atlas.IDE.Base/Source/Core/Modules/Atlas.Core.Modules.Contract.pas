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
  /// 2 (#1903): IAtlasSettingsContribution, TAtlasWelcomeTileInfo.SwitchKey/SettingsKey, neue Texte.
  /// 3 (#1905): IAtlasLineChanges und TAtlasLineChangeMarks (Atlas.IDE.Contracts.LineChanges).
  /// 4 (#1906): IAtlasBuildRequests.Forget.
  cAtlasCoreContractVersion = 4;
  /// <summary>Name der exportierten Funktion, die cAtlasCoreContractVersion liefert
  /// (Atlas.Core.Modules.Handshake); ein Modul fragt sie über GetProcAddress ab.</summary>
  cAtlasCoreContractExport = 'AtlasCoreContractVersion';

type
{$SCOPEDENUMS ON}
  /// <summary>Stufe des abgesicherten Starts (#722). Normal: alles; Safe: Grundfunktionen (Server, Statusfeld,
  /// Einstellungen, Palette, Menü); Minimal: nur Einstellungsseite und Statusfeld. Steht im Vertrag, weil ein Modul
  /// seine Mindeststufe angibt (TAtlasModuleInfo.MinLevel).</summary>
  TAtlasSafeLevel = (Normal, Safe, Minimal);
  /// <summary>Wo ein Menüeintrag eines Moduls erscheint: Atlas-Menü der IDE, Untermenü „Atlas“ im Kontextmenü des
  /// Editors oder Ansicht › Atlas (Fenster).</summary>
  TAtlasMenuPlace = (AtlasMenu, EditorContext, ViewMenu);
  /// <summary>Vorrang einer Taste eines Moduls vor fremden Belegungen: Shared folgt keys.editorPriority wie die
  /// Editorbefehle von Base, Take übernimmt die Taste, Yield lässt eine fremde Belegung aktiv.</summary>
  TAtlasKeyPriority = (Shared, Take, Yield);
{$SCOPEDENUMS OFF}

  /// <summary>Bedingung eines Teils der Feature-Tabelle je Stufe des abgesicherten Starts und Einstellung. Ein Typ
  /// für Base und Module: Delphi 12 hält gleich gebaute Methodenreferenztypen auseinander.</summary>
  TAtlasFeatureWanted = reference to function(ALevel: TAtlasSafeLevel): Boolean;

  /// <summary>Angaben eines Moduls. Id ist dauerhaft und eindeutig (z. B. „atlas.debugger“), Name die Anzeige,
  /// Version die des Moduls. Handle ist das HMODULE des Packages (HInstance des Moduls) für die Frage „gehört
  /// das zu Atlas?“ (Regel 8); 0, wenn unbekannt. MinLevel: ab welcher Stufe des abgesicherten Starts das Modul
  /// läuft (Normal = nur im normalen Start, Safe = nicht minimal, Minimal = immer; Regel 1). Switch: Kennung des
  /// Modulschalters (x-module, #1454), z. B. „debug“; '' = ohne Schalter, immer an.</summary>
  TAtlasModuleInfo = record
    Id: string;
    Name: string;
    Version: string;
    Handle: NativeUInt;
    MinLevel: TAtlasSafeLevel;
    Switch: string;
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

  /// <summary>Ein bereitgestelltes Objekt mit seinem Besitzer ('' für Base).</summary>
  TAtlasProvided = record
    OwnerId: string;
    Instance: IInterface;
  end;

  /// <summary>Ein Teil der Feature-Tabelle von Base (Regel 4: ein Feature-Slot mit Besitzer). Ein Modul stellt
  /// seine Teile über seinen Scope bereit (Provide mit IAtlasFeaturePart); Base trägt sie in Reihenfolge der
  /// Bereitstellung hinter seinen eigenen Teilen ein, startet sie, wenn Wanted es will und der Modulschalter des
  /// Besitzers an ist, und stoppt sie beim Abmelden. Name ist je Tabelle eindeutig.</summary>
  IAtlasFeaturePart = interface
    ['{6F0B7E2A-58C4-4D1B-9E37-2A4C8D51F6B0}']
    function Name: string;
    /// <summary>Soll das Teil in der Stufe ALevel und mit den aktuellen Einstellungen laufen?</summary>
    function Wanted(ALevel: TAtlasSafeLevel): Boolean;
    function IsActive: Boolean;
    procedure Start;
    procedure Stop;
  end;

  /// <summary>Ein Befehl eines Moduls für Palette, Atlas-Menü und Tastenkürzel. Id ist eindeutig
  /// („Atlas.DebugEvaluate“), Caption ohne „Atlas: “; Visible nil = immer sichtbar. Run läuft im Hauptthread.
  /// </summary>
  TAtlasModuleCommand = record
    Id: string;
    Caption: string;
    Description: string;
    Run: TProc;
    Visible: TFunc<Boolean>;
    /// <summary>Tastenkürzel (TShortCut) zur Anzeige in Palette und Kontextmenü; nil oder 0 = keins.</summary>
    Key: TFunc<Integer>;
  end;

  /// <summary>Befehle eines Moduls (Regel 4); Base fragt sie bei jedem Öffnen der Palette bzw. des Menüs.</summary>
  IAtlasCommandSource = interface
    ['{0C9E4B7D-3A61-4F2E-8D05-B6A1E97C2F44}']
    function Commands: TArray<TAtlasModuleCommand>;
  end;

  /// <summary>Ein Eintrag im Atlas-Menü bzw. im Kontextmenü des Editors (Place): Befehl CommandId (aus einer
  /// IAtlasCommandSource) im Untermenü Section ('' = oberste Ebene; nur im Atlas-Menü); Text und Sichtbarkeit kommen
  /// vom Befehl. CommandId „-“ ist eine Trennlinie, sichtbar nur zwischen sichtbaren Einträgen. Unter Ansicht › Atlas
  /// (ViewMenu) ersetzt eine gesetzte Caption den Text des Befehls.
  /// Eintrag ohne Befehl (nur im Atlas-Menü): CommandId ist eine eindeutige Kennung, Caption der Text, Run die
  /// Aktion (nil = ausgegraut), etwa je Projektaufgabe; Base fragt die Einträge bei jedem Öffnen und beim Klick
  /// neu (Regel 3).</summary>
  TAtlasMenuEntry = record
    CommandId: string;
    Section: string;
    Place: TAtlasMenuPlace;
    Caption: string;
    Run: TProc;
  end;

  /// <summary>Einträge eines Moduls im Atlas-Menü.</summary>
  IAtlasMenuSource = interface
    ['{7D2F91A3-6B48-4C0E-A5D7-1E83F4C69B21}']
    function MenuEntries: TArray<TAtlasMenuEntry>;
  end;

  /// <summary>Tastenkürzel eines Moduls im Editor (Key: TShortCut, 0 = keins). Mit Attempt läuft die Taste sofort;
  /// liefert Attempt False, geht sie an die nächste Bindung der IDE. Sonst läuft Run nach der Tastenverarbeitung.
  /// Id ist eindeutig (Tastenkürzel-Tipps; Base sucht die Taste beim Drücken darüber neu).</summary>
  TAtlasModuleKey = record
    Id: string;
    Caption: string;
    Key: Integer;
    Priority: TAtlasKeyPriority;
    Attempt: TFunc<Boolean>;
    Run: TProc;
  end;

  /// <summary>Tastenkürzel eines Moduls; Base fragt sie bei jedem Neubelegen der Tasten (nach Einstellungen und
  /// nach jeder Änderung der Registry).</summary>
  IAtlasKeySource = interface
    ['{5E1A7C93-2B06-4D8F-91E4-C3A0F68B2D57}']
    function Keys: TArray<TAtlasModuleKey>;
  end;

  /// <summary>Wird gerufen, wenn der Editor eine andere Ansicht zeigt (Listen und Tooltips der alten schließen).
  /// </summary>
  IAtlasFollowsEditorView = interface
    ['{9F4D2B61-E8A3-47C5-B02E-6A17D3C85F90}']
    procedure EditorViewActivated;
  end;

  /// <summary>Übernimmt geänderte Einstellungen (nach jedem Speichern der Optionen und jedem Schnellschalter).
  /// </summary>
  IAtlasAppliesSettings = interface
    ['{A41C6E08-95D3-4B7F-8E2A-0F6D3B9C7E15}']
    procedure ApplySettings;
  end;

  /// <summary>Folgt dem Thema der IDE (hell, dunkel, eigene Farben).</summary>
  IAtlasFollowsTheme = interface
    ['{E6B8302D-4F17-49A5-B3C1-82D0A7F5E946}']
    procedure ThemeChanged;
  end;

  /// <summary>Führt DUnitX-Tests aus (Modul Tests, #69). Base fragt ihn für „Betroffene Tests ausführen“ der
  /// Auswirkungsanalyse (#1120), Module etwa für „Fehlgeschlagene erneut ausführen“ der Willkommensseite. Ohne
  /// Anbieter sind die Tests aus. Hauptthread.</summary>
  IAtlasTestRunner = interface
    ['{88CE7F4C-2648-4187-BF73-C976328E6C9B}']
    /// <summary>ATests (volle Namen für --run) aus dem Testprojekt von AFileName (Unit oder .dproj) ausführen;
    /// leer = alle.</summary>
    procedure RunTests(const AFileName: string; const ATests: TArray<string>);
  end;

  /// <summary>Ein Befund für „Issue anlegen“ (#1268) aus dem Fenster „Atlas-Prüfung“: Regelkennung bzw.
  /// Meldungsnummer, Meldung, Fundstelle („Unit1.pas:12:5“) und betroffene Zeile ('' = unbekannt).</summary>
  TAtlasIssueFinding = record
    Rule: string;
    Message: string;
    Location: string;
    LineText: string;
  end;

  /// <summary>Textdatei für ein neues Issue (#1355): Name beim Tracker und Inhalt; nach dem Anlegen zum Anhängen
  /// vorgewählt (#1276).</summary>
  TAtlasIssueTextFile = record
    Name: string;
    Text: string;
  end;

  /// <summary>„Issue anlegen“ (#1268) für Base: aus Befunden des Fensters „Atlas-Prüfung“ und aus einem
  /// Absturzfall des Servers (#1355). Stellt das Modul Tracker bereit; ohne Anbieter oder mit Enabled = False
  /// zeigt Base die Einträge nicht bzw. öffnet den Ordner des Falls. Hauptthread.</summary>
  IAtlasIssueCreation = interface
    ['{09578943-8085-41BC-BFA2-8C20E7D2CCB8}']
    /// <summary>issues.create an und das Modul bereit.</summary>
    function Enabled: Boolean;
    /// <summary>Dialog mit den Befunden; mehrere ergeben ein Issue mit Liste.</summary>
    procedure FromFindings(const AFindings: TArray<TAtlasIssueFinding>);
    /// <summary>Dialog mit ATitle und ADescription; AFiles nach dem Anlegen zum Anhängen vorgewählt.</summary>
    procedure FromCrash(const ATitle, ADescription: string; const AFiles: TArray<TAtlasIssueTextFile>);
  end;

  /// <summary>Wert eines Ausdrucks im Tooltip beim Debuggen (Visualisierer, eigene Darstellungen): '' = kein Beitrag.
  /// ATypeChain: Typ und seine Vorfahren, AText: Wert der IDE.</summary>
  IAtlasHoverValueSource = interface
    ['{3B57C0E9-1D82-4A6F-9C34-D7E2058AB613}']
    function HoverValue(const AExpression: string; const ATypeChain: TArray<string>; const AText: string): string;
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
    /// <summary>AObject unter AIID mit diesem Modul als Besitzer bereitstellen; AObject muss AIID
    /// unterstützen.</summary>
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
    /// <summary>AModule anmelden; liefert seinen Scope. Leere oder schon angemeldete Id:
    /// EAtlasModuleRegistry.</summary>
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
    /// <summary>AObject unter AIID mit Base als Besitzer bereitstellen; Module nehmen
    /// IAtlasModuleScope.Provide.</summary>
    function Provide(const AIID: TGUID; const AObject: IInterface): IAtlasRegistration;
    /// <summary>Alle unter AIID bereitgestellten Objekte in Reihenfolge der Bereitstellung.</summary>
    function FindAll(const AIID: TGUID): TArray<IInterface>;
    /// <summary>Wie FindAll, mit dem Besitzer jedes Objekts.</summary>
    function Provisions(const AIID: TGUID): TArray<TAtlasProvided>;
    /// <summary>Auf Änderungen hören; Module nehmen IAtlasModuleScope.Subscribe.</summary>
    function Subscribe(const AListener: IAtlasRegistryListener): IAtlasRegistration;
  end;

  /// <summary>Falsche Benutzung der Registry (leere oder doppelte Modul-Id, Objekt ohne das Interface).</summary>
  EAtlasModuleRegistry = class(Exception);

implementation

end.
