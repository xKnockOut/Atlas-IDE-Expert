unit Atlas.Common.Projects.Contract.UnitLookup;

// Unit-Suche wie beim Compiler (IUnitLookup, #1016) samt Antworten zu Packages, und was die Umsetzung
// (TUnitLookup) über Projekt, Installation und Dateisystem wissen muss. Eigene Unit, damit Aufrufer die Suche einrichten können, ohne den Adapter zu importieren; wer sie
// erzeugt, entscheidet die Zusammensetzung.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Projects.Contract;

type
  /// <summary>Gehört eine Unit zu einem Package (#46)? Unknown, wenn das Package nicht gefunden wird.</summary>
{$SCOPEDENUMS ON}
  TPackageAnswer = (No, Yes, Unknown);
{$SCOPEDENUMS OFF}
  /// <summary>Gehört AUnitName zu Package APackage (aus requires)? Über dessen .dpk bzw. .dcp (#46).</summary>
  TPackageProvides = reference to function(const APackage, AUnitName: string): TPackageAnswer;
  /// <summary>Namen aus requires des Packages APackage (aus seiner .dpk); leer ohne Quelle.</summary>
  TPackageRequires = reference to function(const APackage: string): TArray<string>;
  /// <summary>Antwort der Unit-Suche (#1016): gefunden, sicher nicht gefunden oder ohne Aussage (Pfade der
  /// Installation unbekannt, Makro in einem Pfad offen, Inhalt eines Packages unbekannt).</summary>
{$SCOPEDENUMS ON}
  TUnitAnswer = (Found, Missing, Unknown);
  /// <summary>Wo gesucht wird (#1016): wie der Compiler (Projekt, Suchpfade der .dproj, Bibliothek) bzw. was
  /// Atlas kennt (Index, Quellpfade der Installation).</summary>
  TUnitSource = (Project, Atlas);
{$SCOPEDENUMS OFF}
  TUnitSources = set of TUnitSource;

  /// <summary>Unit-Suche wie beim Compiler für uses-unit-not-found (#1016); nil = unbekannt, die Regel
  /// schweigt bis auf Prüfungen ohne Pfade.</summary>
  IUnitLookup = interface
    ['{7866E50C-6086-4876-A359-8193140A05BD}']
    /// <summary>Findet der Compiler AUnitName, verwendet in AFromFile (absolut)? AInPath ist der Text aus
    /// "in '…'" ('' ohne); dann zählt nur diese Datei.</summary>
    function Find(const AUnitName, AInPath, AFromFile: string; ASources: TUnitSources): TUnitAnswer;
    /// <summary>Package aus requires als .dpk oder .dcp (E2202).</summary>
    function FindPackage(const APackage: string): TUnitAnswer;
    /// <summary>Datei aus {$I} bzw. {$R} (AFileName so, wie sie dort steht) wie beim Compiler (#1379): Ordner
    /// von AFromFile (absolut), Projektordner, Suchpfade der .dproj (auch DCC_IncludePath und DCC_ResourcePath),
    /// Bibliothekspfade der Installation. Missing nur mit bekannter Installation und ohne offenes Makro.</summary>
    function FindFile(const AFileName, AFromFile: string): TUnitAnswer;
    /// <summary>Namen aller Units, die die Suche findet, für Vorschläge.</summary>
    function KnownUnits(ASources: TUnitSources): TArray<string>;
    /// <summary>Ordner unter dem Projektordner, der AUnitName.pas enthält, aber in keinem Suchpfad steht;
    /// relativ zur .dproj, '' ohne.</summary>
    function FolderOutsidePaths(const AUnitName: string): string;
    /// <summary>Pfad und Text der .dproj; False ohne Projekt.</summary>
    function ReadProject(out AFileName, AText: string): Boolean;
  end;

  /// <summary>Liest eine Textdatei; False, wenn sie fehlt.</summary>
  TUnitLookupReadText = TDocumentReadText;

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
    PackageProvides: TPackageProvides;
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
  TUnitLookupFactory = reference to function(const ASetup: TUnitLookupSetup): IUnitLookup;

implementation

end.
