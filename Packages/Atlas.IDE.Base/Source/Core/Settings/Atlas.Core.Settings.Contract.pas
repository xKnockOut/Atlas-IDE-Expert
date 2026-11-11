unit Atlas.Core.Settings.Contract;

// Einstellungsteile der Module (#1455): Die
// Einstellungen bleiben zentral in Base (eine Ablage, ein Optionsdialog,
// Export, Import, Zurücksetzen); jedes Modul meldet seinen Teil an: Schlüssel
// mit Vorgaben, Schema-Teil, Seite im Dialog und Umbenennungen. Werte fremder
// und fehlender Module bleiben in der Ablage erhalten, bis der Benutzer das
// Modul aus der Liste der bekannten entfernt.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  /// <summary>Art eines Werts. In der Ablage stehen alle Werte als Text: Wahrheitswerte „1“/„0“, Zahlen
  /// dezimal.</summary>
  TAtlasSettingsValueKind = (svBoolean, svInteger, svString);

  /// <summary>Ein Schlüssel eines Moduls (z. B. „debug.visualizers.enabled“) mit Vorgabe als Text. Minimum und
  /// Maximum begrenzen Zahlen; Minimum > Maximum heißt ohne Grenzen.</summary>
  TAtlasSettingsKey = record
    Key: string;
    Kind: TAtlasSettingsValueKind;
    Default: string;
    Minimum: Integer;
    Maximum: Integer;
  end;

  /// <summary>Seite im Optionsdialog: Id eindeutig, Caption die Anzeige, Parent die Id der übergeordneten Seite
  /// ('' = oberste Ebene).</summary>
  TAtlasSettingsPageInfo = record
    Id: string;
    Caption: string;
    Parent: string;
  end;

  /// <summary>Umbenannter Schlüssel: Der Wert unter OldKey zieht nach NewKey um, solange NewKey keinen Wert hat;
  /// danach wird OldKey entfernt.</summary>
  TAtlasSettingsKeyRename = record
    OldKey: string;
    NewKey: string;
  end;

  /// <summary>Einstellungsteil eines Moduls. SchemaPart ist ein JSON-Objekt mit den Eigenschaften der Schlüssel
  /// (wie unter „properties“ im Schema), x-page verweist auf Page.Id.</summary>
  IAtlasSettingsPart = interface
    ['{AA952223-C6B0-4C63-B110-223D832A7450}']
    /// <summary>Id des Moduls (TAtlasModuleInfo.Id), dem der Teil gehört.</summary>
    function OwnerId: string;
    function Page: TAtlasSettingsPageInfo;
    function Keys: TArray<TAtlasSettingsKey>;
    function SchemaPart: string;
    function Renames: TArray<TAtlasSettingsKeyRename>;
  end;

  /// <summary>Ablage der Werte als Text je Name (Registry, Datei, Arbeitsspeicher). Namen mit „$“ am Anfang
  /// gehören Base (Verwaltungsdaten), keine Einstellung.</summary>
  IAtlasSettingsStorage = interface
    ['{0F1FC6DC-5C85-4CDC-9C54-BE580EBE4603}']
    function Contains(const AName: string): Boolean;
    /// <summary>Wert unter AName; '' ohne Wert.</summary>
    function ReadText(const AName: string): string;
    procedure WriteText(const AName, AValue: string);
    /// <summary>Wert unter AName entfernen; ohne Wert nichts.</summary>
    procedure Remove(const AName: string);
    /// <summary>Alle Namen mit Wert, sortiert.</summary>
    function Names: TArray<string>;
  end;

  /// <summary>Werte der angemeldeten Schlüssel. Ohne gespeicherten oder mit ungültigem Wert gilt die Vorgabe des
  /// Teils. Lesen oder Schreiben eines nicht angemeldeten Schlüssels oder in falscher Art: EAtlasSettingsKey.</summary>
  IAtlasSettingsValues = interface
    ['{9EF3C422-18D4-4A32-823A-5898F816B678}']
    /// <summary>Steht unter AKey ein gespeicherter Wert (gleich, ob angemeldet)?</summary>
    function Contains(const AKey: string): Boolean;
    function ReadBoolean(const AKey: string): Boolean;
    function ReadInteger(const AKey: string): Integer;
    function ReadString(const AKey: string): string;
    procedure WriteBoolean(const AKey: string; AValue: Boolean);
    /// <summary>Zahl schreiben, auf Minimum und Maximum des Schlüssels begrenzt.</summary>
    procedure WriteInteger(const AKey: string; AValue: Integer);
    procedure WriteString(const AKey, AValue: string);
    /// <summary>Gespeicherten Wert entfernen; danach gilt die Vorgabe.</summary>
    procedure Reset(const AKey: string);
    /// <summary>Alle gespeicherten Schlüssel, auch die fremder und fehlender Module, sortiert.</summary>
    function StoredKeys: TArray<string>;
  end;

  /// <summary>Art einer Änderung: Teil an- bzw. abgemeldet, Wert geändert (auch zurückgesetzt), Wert nach einer
  /// Umbenennung übernommen, Ablage gewechselt, Werte eines Moduls vergessen.</summary>
  TAtlasSettingsChangeKind = (scPartAdded, scPartRemoved, scValueChanged, scRenamed, scStorageChanged,
    scOwnerForgotten);

  /// <summary>Eine Änderung: OwnerId der Besitzer, Key der Schlüssel (bei scRenamed der neue), OldKey nur bei
  /// scRenamed.</summary>
  TAtlasSettingsChange = record
    Kind: TAtlasSettingsChangeKind;
    OwnerId: string;
    Key: string;
    OldKey: string;
  end;

  /// <summary>Hört auf Änderungen der Einstellungen (Optionsdialog, Module mit eigenen Werten). Wird im Thread der
  /// Änderung gerufen, nie unter einer Sperre.</summary>
  IAtlasSettingsListener = interface
    ['{BC427CF6-3744-43F4-894F-AAC5BDEFB7CC}']
    procedure SettingsChanged(const AChange: TAtlasSettingsChange);
  end;

  /// <summary>Die zentrale Stelle der Einstellungen in Base. Besteht ab der Unit-Initialisierung (Regel 1); bis
  /// Base seine Ablage setzt, liegen die Werte im Arbeitsspeicher.</summary>
  IAtlasSettingsParts = interface
    ['{3AC97AE4-45BA-4233-9EB3-5C9253765F28}']
    /// <summary>APart anmelden: Umbenennungen anwenden, Schlüssel dem Besitzer zuordnen. Die Anmeldung gehört in den
    /// Scope des Moduls (IAtlasModuleScope.Own). Leere OwnerId, leerer oder schon angemeldeter Schlüssel,
    /// Umbenennung auf einen fremden Schlüssel: EAtlasSettingsParts.</summary>
    function Add(const APart: IAtlasSettingsPart): IAtlasRegistration;
    /// <summary>Angemeldete Teile in Reihenfolge der Anmeldung.</summary>
    function Parts: TArray<IAtlasSettingsPart>;
    /// <summary>Angemeldeter Schlüssel AKey; False, wenn kein Teil ihn anmeldet.</summary>
    function FindKey(const AKey: string; out AEntry: TAtlasSettingsKey): Boolean;
    function Values: IAtlasSettingsValues;
    /// <summary>Ablage wechseln (Base beim Laden der Einstellungen): Werte der bisherigen Ablage, die in AStorage
    /// fehlen, ziehen um; Umbenennungen aller Teile werden dort angewandt.</summary>
    procedure UseStorage(const AStorage: IAtlasSettingsStorage);
    /// <summary>Alle Werte, die ein Modul je angemeldet hat, entfernen (Modul aus der Liste der bekannten
    /// entfernt). Ist ein Teil von AOwnerId angemeldet: EAtlasSettingsParts. Ergebnis: Zahl entfernter Werte.</summary>
    function ForgetOwner(const AOwnerId: string): Integer;
    function Subscribe(const AListener: IAtlasSettingsListener): IAtlasRegistration;
  end;

  /// <summary>Falsche Anmeldung eines Einstellungsteils.</summary>
  EAtlasSettingsParts = class(Exception);
  /// <summary>Zugriff auf einen nicht angemeldeten Schlüssel oder in falscher Art.</summary>
  EAtlasSettingsKey = class(Exception);

implementation

end.
