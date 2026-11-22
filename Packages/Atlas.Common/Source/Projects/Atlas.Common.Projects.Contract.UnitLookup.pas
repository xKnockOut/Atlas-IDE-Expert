unit Atlas.Common.Projects.Contract.UnitLookup;

// Was die Unit-Suche wie beim Compiler (TUnitLookup, #1016) über Projekt, Installation und Dateisystem wissen
// muss. Eigene Unit, damit Aufrufer die Suche einrichten können, ohne den Adapter zu importieren; wer sie
// erzeugt, entscheidet die Zusammensetzung.

interface

uses
  System.SysUtils,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Liest eine Textdatei; False, wenn sie fehlt.</summary>
  TUnitLookupReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Anderes Projekt der Gruppe: Ordner, in den es übersetzt, und seine Units.</summary>
  TUnitLookupGroupOutput = record
    /// <summary>Name des Projekts ohne Endung (Atlas.Text): requires dieses Namens baut die Gruppe selbst.</summary>
    ProjectName: string;
    /// <summary>DCU-Ausgabeordner, absolut, mit eingesetzter Plattform und Konfiguration.</summary>
    DcuFolder: string;
    Units: TArray<string>;
  end;

  /// <summary>Was TUnitLookup über Projekt, Installation und Dateisystem wissen muss.</summary>
  TUnitLookupSetup = record
    Project: TProjectInfo;
    /// <summary>Bibliothekspfade der Installation (Library Path) in Suchreihenfolge, absolut.</summary>
    LibraryPaths: TArray<string>;
    /// <summary>Installation bekannt: Ohne gilt keine Unit als sicher fehlend.</summary>
    LibraryKnown: Boolean;
    /// <summary>Quellpfade der Installation (Browsing Path) für die Quelle Atlas.</summary>
    BrowsingPaths: TArray<string>;
    /// <summary>Packages aus requires der Hauptdatei (.dpk); leer bei Programmen.</summary>
    RequiredPackages: TArray<string>;
    /// <summary>Dateien eines Ordners (vollständige Pfade, mindestens .pas und .dcu); leer, wenn es ihn nicht gibt.
    /// </summary>
    ListFiles: TFunc<string, TArray<string>>;
    /// <summary>Unterordner eines Ordners (vollständige Pfade); nil = keine Suche außerhalb der Suchpfade.</summary>
    ListFolders: TFunc<string, TArray<string>>;
    FileExists: TFunc<string, Boolean>;
    /// <summary>Text einer Datei (.dproj); nil = keine Korrektur am Suchpfad.</summary>
    ReadText: TUnitLookupReadText;
    /// <summary>Liefert Package APackage die Unit? nil = keine requires-Prüfung.</summary>
    PackageProvides: TRulePackageProvides;
    /// <summary>requires eines Packages (aus der .dpk); leer ohne Quelle. nil = nur die direkten Packages.</summary>
    PackageRequires: TFunc<string, TArray<string>>;
    /// <summary>Gibt es das Package (.dpk oder .dcp)? nil = unbekannt.</summary>
    PackageExists: TFunc<string, Boolean>;
    /// <summary>Steht die Unit im Index (Quelle Atlas)? nil = Index unbekannt.</summary>
    IndexKnows: TFunc<string, Boolean>;
    /// <summary>Namen der Units im Index für Vorschläge; nil = keine.</summary>
    IndexUnits: TFunc<TArray<string>>;
    /// <summary>Die anderen Projekte der Projektgruppe (3a).</summary>
    GroupOutputs: TArray<TUnitLookupGroupOutput>;
    /// <summary>Wie GroupOutputs, aber bei jeder Suche neu gefragt: Die IDE meldet die Projekte der Gruppe einzeln
    /// und nach diesem an. nil = nur GroupOutputs.</summary>
    GroupOutputsOf: TFunc<TArray<TUnitLookupGroupOutput>>;
  end;
  /// <summary>Erzeugt die Unit-Suche zu ASetup; die Zusammensetzung wählt die Umsetzung.</summary>
  TUnitLookupFactory = reference to function(const ASetup: TUnitLookupSetup): IRuleUnitLookup;

implementation

end.
