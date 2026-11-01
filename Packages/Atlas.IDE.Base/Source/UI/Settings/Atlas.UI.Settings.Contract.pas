unit Atlas.UI.Settings.Contract;

// Abschnitte der Module im Optionsdialog (#1455, ADR 0017 Entscheidung 3):
// Ein Modul meldet einen IAtlasSettingsSectionProvider über seinen Scope an
// (GScope.Provide); jede Optionsseite holt sich daraus ihren eigenen Abschnitt
// (IAtlasSettingsSection), so dass zwei Seiten nie dieselben Steuerelemente
// teilen. Die Optionsseite von Base baut ihn in den
// Bereich AreaId (x-area des Schemas; unbekannter Bereich: eigener Reiter mit
// der Beschriftung aus dem Katalog) und gibt ihm dafür die Bausteine der Seite
// (IAtlasSettingsSectionHost). Schalter, Zahl, Text und Auswahl hängen an
// einem Schlüssel: Base liest und schreibt sie selbst. Eigene Zeilen
// (Tabellen, Knöpfe) füllt das Modul; deren Schlüssel liest und schreibt es in
// Load und Save über IAtlasSettingsValues. Alle Werte bleiben in der einen
// Ablage von Base; fehlt das Modul, bleiben sie unverändert erhalten.
// Gebundene Felder schreibt die Seite vor Save; ein Abschnitt darf einen
// Wert in Save anders schreiben (z. B. ungekürzt oder geordnet).
// Steuerelemente aus der VCL dürfen über die Package-Grenze: Base und Module
// teilen dieselbe VCL. Klassen aus Atlas-Packages nie.

interface

uses
  Vcl.Controls,
  Atlas.Core.Settings.Contract;

type
  /// <summary>Bausteine der Optionsseite für einen Abschnitt. Gilt nur während Build und bis Close; Elemente gehören
  /// der Seite (Zeilen, gebundene Felder), eigene Steuerelemente in AddRow gehören dem Modul.</summary>
  IAtlasSettingsSectionHost = interface
    ['{666679A9-357F-47D0-92AF-59F06A1AAEB3}']
    /// <summary>Fette Überschrift.</summary>
    procedure AddTitle(const ACaption: string);
    /// <summary>Umbrochener Hinweistext in eigener Zeile (Höhe AHeight).</summary>
    function AddHint(const AText: string; AHeight: Integer): TControl;
    /// <summary>Schalter an AKey (x-key, Wahrheitswert); ein TCheckBox.</summary>
    function AddSwitch(const AKey, ACaption: string): TControl;
    /// <summary>Zahl an AKey; ein TCustomEdit.</summary>
    function AddNumber(const AKey, ACaption: string): TControl;
    /// <summary>Textzeile an AKey (Beschriftung darüber, Feld in voller Breite); ein TCustomEdit. Gespeichert wird
    /// der Text ohne Leerzeichen an den Enden.</summary>
    function AddText(const AKey, ACaption: string): TControl;
    /// <summary>Auswahl an AKey: ACaptions die Anzeige, AValues die gespeicherten Werte in derselben Reihenfolge
    /// (bei Zahlen als Text); ein TCustomComboBox. Ein gespeicherter Wert, der fehlt, zeigt den ersten Eintrag.
    /// </summary>
    function AddChoice(const AKey, ACaption: string; const ACaptions, AValues: TArray<string>): TControl;
    /// <summary>Eigene Zeile der Höhe AHeight für Tabellen und Knöpfe. AKeys: Schlüssel, die der Abschnitt darin
    /// selbst liest und schreibt; nach ihnen richten sich Punkt, Zurücksetzen, Unterpunkt und Sperre der Zeile.
    /// </summary>
    function AddRow(AHeight: Integer; const AKeys: TArray<string>): TWinControl;
    /// <summary>Zeile ohne eigenen Schlüssel (Knöpfe, Felder unter einer Tabelle) steht bei AAnchor: gleicher
    /// Unterpunkt, gleicher Rahmen.</summary>
    procedure Attach(ARow, AAnchor: TControl);
    /// <summary>Ein Wert in einer eigenen Zeile hat sich geändert: Punkte und Sperren neu.</summary>
    procedure Changed;
    /// <summary>Eigene Logik des Abschnitts (Liste leer, Zeile schreibgeschützt): AControl frei oder gesperrt. Eine
    /// Sperre durch den Hauptschalter bleibt bestehen.</summary>
    procedure Allow(AControl: TControl; AEnabled: Boolean);
    /// <summary>Hat AControl ein Fenster (Zeilen von Listen und Bäumen brauchen eins)? Legt es an, sobald die Seite
    /// eins hat; sonst False, und der Abschnitt füllt die Liste in WindowReady.</summary>
    function ListReady(AControl: TWinControl): Boolean;
    /// <summary>Zeigt die Einstellung AKey (Reiter, ins Bild rollen); False, wenn die Seite sie nicht kennt.</summary>
    function Reveal(const AKey: string): Boolean;
  end;

  /// <summary>Abschnitt eines Moduls im Optionsdialog, je Seite ein eigener. Die Seite ruft Build einmal, danach
  /// Load, Save, WindowReady und Show beliebig oft und zuletzt Close; nach Close nie wieder (auch nicht, wenn das
  /// Modul vorher abgemeldet wird).</summary>
  IAtlasSettingsSection = interface
    ['{91C21CB1-3374-4185-AD4F-F6BAEF7A1C4C}']
    /// <summary>Id des Moduls (TAtlasModuleInfo.Id).</summary>
    function OwnerId: string;
    /// <summary>Bereich der Optionsseite (x-area, z. B. „issues“).</summary>
    function AreaId: string;
    procedure Build(const AHost: IAtlasSettingsSectionHost);
    /// <summary>Werte der eigenen Zeilen aus AValues zeigen (gebundene Felder lädt die Seite selbst).</summary>
    procedure Load(const AValues: IAtlasSettingsValues);
    /// <summary>Werte der eigenen Zeilen nach AValues schreiben.</summary>
    procedure Save(const AValues: IAtlasSettingsValues);
    /// <summary>Die Seite hat jetzt ein Fenster: Listen füllen, die ListReady vorher abgelehnt hat.</summary>
    procedure WindowReady;
    /// <summary>„Einstellung zeigen“ mit Vorgabe (z. B. „zuordnen …“ mit dem Projekt): AKey ist die Einstellung,
    /// AArgument die Vorgabe. False, wenn AKey nicht zum Abschnitt gehört.</summary>
    function Show(const AKey, AArgument: string): Boolean;
    /// <summary>Die Seite schließt oder das Modul geht: eigene Steuerelemente und Ereignisse lösen.</summary>
    procedure Close;
  end;

  /// <summary>Was ein Modul für den Optionsdialog anmeldet (GScope.Provide): je Seite ein neuer Abschnitt.
  /// </summary>
  IAtlasSettingsSectionProvider = interface
    ['{3B0E5C27-6F1D-4A8E-B9C2-7D45E1A0F836}']
    function CreateSection: IAtlasSettingsSection;
  end;

implementation

end.
