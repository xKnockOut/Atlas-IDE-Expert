unit Atlas.Common.Checks.Contract;

// Was eine Prüfung einer Datei vom Host bekommt: Projekt der Datei, Dienste des Arbeitsbereichs (Symbolindex,
// Unit-Suche, Projekte der Gruppe, Abfragen) und die Typen der laufenden IDE. Der Arbeitsbereich füllt sie, die
// Prüfregeln lesen sie; so kennt der Host die Regeln nicht und die Regeln nicht den Arbeitsbereich. Was die Regeln
// für Korrekturen von Refactorings brauchen, steht in Atlas.Common.Checks.Contract.Refactorings.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Query.Contract,
  Atlas.Common.Projects.Contract.Group,
  Atlas.Common.Projects.Contract.UnitLookup,
  Atlas.Common.Checks.Contract.Refactorings;

type
  /// <summary>Typen, die die laufende IDE aus ihren geladenen Packages kennt (RTTI der BPLs, über
  /// RegisterComponents angemeldete Komponenten), auch ohne Quelltext. unresolved-type und unresolved-identifier
  /// schweigen für einen solchen Typ, wenn seine Unit im uses steht. nil = ohne IDE (Linter, MCP).</summary>
  ICheckIdeTypes = interface
    ['{5B0E7C42-91D3-4F6A-8E27-C4A1D96B3F05}']
    /// <summary>Units, in denen die IDE einen Typ ATypeName (ohne Unit-Präfix, ohne Groß-/Kleinschreibung)
    /// kennt; nil = unbekannt.</summary>
    function UnitsOf(const ATypeName: string): TArray<string>;
  end;

  /// <summary>Dienste des Projekts für die Prüfung (#1112): Symbolindex, Nachladen von Units, Unit-Suche,
  /// Packages, Projekte der Gruppe und Namenskonvention. Ein Weg für LSP-Server, MCP und Linter: Der
  /// Arbeitsbereich liefert sie (TCoreWorkspace.RuleServices), TRuleContext.UseServices trägt sie in den
  /// Regelkontext ein.
  /// Default = ohne Index; Regeln, die ihn brauchen, schweigen dann.</summary>
  TCheckServices = record
    /// <summary>Symbolindex für Typen aus anderen Units und der RTL (#125); nil = keiner.</summary>
    Index: ISymbolIndex;
    /// <summary>Units bedarfsweise nachladen (Namensauflösung, #178); nil = nur der vorhandene Index.</summary>
    EnsureUnit: TEnsureUnitFunc;
    /// <summary>Namespaces des Projekts für Unit-Namen ohne Präfix; leer ohne Projekt.</summary>
    Namespaces: TArray<string>;
    /// <summary>Unit-Suche wie beim Compiler (#1016); nil = unbekannt.</summary>
    Units: IUnitLookup;
    /// <summary>Inhalt der Packages aus requires (#46); nil = unbekannt.</summary>
    PackageProvides: TPackageProvides;
    /// <summary>requires eines Packages (für die Kette der requires); nil = nur die direkten.</summary>
    PackageRequires: TPackageRequires;
    /// <summary>Antworten zum Index über alle Units des Arbeitsbereichs; nil = je Unit neu.</summary>
    NameFacts: IIndexNameFacts;
    /// <summary>Projekte der Gruppe für projektweite Regeln (#1102); nil = unbekannt.</summary>
    ProjectFiles: IProjectGroupFiles;
    /// <summary>Präfixe der Projektdatei .atlas (#1111); leer = unbekannt.</summary>
    Naming: TProjectNaming;
    /// <summary>Warnungen der .dproj als "Bezeichner=Wert" (#1378); leer = ohne Projekt.</summary>
    ProjectWarnings: TArray<string>;
    /// <summary>Code-Abfragen des Arbeitsbereichs (#1351); nil = keine.</summary>
    Queries: ICodeQueries;
    /// <summary>Typen der laufenden IDE ohne Quelltext; nil = ohne IDE.</summary>
    IdeTypes: ICheckIdeTypes;
    /// <summary>Refactorings für Korrekturen, vom Host über Adapter; je Eintrag nil = nicht verfügbar.</summary>
    Refactorings: TCheckRefactorings;
  end;

  /// <summary>Projekt einer geprüften Datei (#943); Default = unbekannt.</summary>
  TCheckProject = record
    Application: TApplicationKind;
    /// <summary>Name ohne Endung, z. B. Atlas.IDE.Expert.</summary>
    Name: string;
    /// <summary>Automatisch erzeugte Formulare in der Reihenfolge der .dpr (#956).</summary>
    AutoCreateForms: TArray<string>;
    /// <summary>Absoluter Pfad der geprüften Datei (#1054); '' = unbekannt. Damit sehen die Regeln die
    /// Formulardatei daneben (FormText) und lesen Dateien neben der Unit (ReadFile) wie im Server.</summary>
    FileName: string;
    /// <summary>Pfad der .dpr zu AutoCreateForms (#1055); '' = unbekannt.</summary>
    ProjectMainSource: string;
    /// <summary>Index und weitere Dienste des Projekts (#1112); Default = ohne Index.</summary>
    Services: TCheckServices;
  end;

  /// <summary>Projekt und Dienste (Index, #1112) je Datei, etwa aus den Arbeitsbereichen des MCP-Servers.</summary>
  TCheckProjectFunc = reference to function(const AFileName: string): TCheckProject;

implementation

end.
