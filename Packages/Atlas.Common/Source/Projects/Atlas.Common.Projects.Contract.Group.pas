unit Atlas.Common.Projects.Contract.Group;

// Die Projekte einer Projektgruppe als reine Werte für projektweite Auswertungen (#1102): Art der Anwendung und
// des Projekts, Quelltexte und Formulare, Zugriff auf Dateien und Uses-Graph (IProjectGroupFiles) und die
// Präfix-Vorgaben der Projektdatei .atlas. Prüfregeln, Linter und Sprachserver lesen sie; wer sie füllt,
// entscheidet die Zusammensetzung.

interface

type
  /// <summary>Text einer Datei, geöffnete Dokumente zuerst; False, wenn sie nicht lesbar ist.</summary>
  TProjectReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Sind alle Projekte geladen und indiziert? Sonst der Grund in AReason.</summary>
  TProjectGroupComplete = reference to function(out AReason: string): Boolean;

  /// <summary>Art der Anwendung, zu der die Datei gehört (#926): mit oder ohne Konsole, Package (#943),
  /// Windows-Dienst und DLL ohne Formulare (#1060). Eine DLL mit Formularen ist Unknown.</summary>
{$SCOPEDENUMS ON}
  TApplicationKind = (Unknown, Console, Gui, Package, Service, Library_);
{$SCOPEDENUMS OFF}

  /// <summary>Art eines Projekts für projektweite Regeln (#1102): Anwendung (program), Package (.dpk) oder DLL
  /// (library).</summary>
{$SCOPEDENUMS ON}
  TGroupProjectKind = (Unknown, Application, Package, Library_);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Projekt der Projektgruppe mit seinen Quelltexten und Formularen (#1102).</summary>
  TGroupProject = record
    /// <summary>Projektdatei (.dproj, .dpr oder .dpk).</summary>
    FileName: string;
    Kind: TGroupProjectKind;
    /// <summary>DUnitX- oder DUnit-Testprojekt.</summary>
    IsTest: Boolean;
    /// <summary>Absolute Pfade der Units samt Hauptquelltext (.dpr/.dpk).</summary>
    Sources: TArray<string>;
    /// <summary>Absolute Pfade der Formulardateien (.dfm/.fmx) neben den Units.</summary>
    Forms: TArray<string>;
  end;

  /// <summary>Antwort auf "kommt der Name in der Datei vor?" (#1102).</summary>
{$SCOPEDENUMS ON}
  TNameAnswer = (Absent, Present, Unknown);
{$SCOPEDENUMS OFF}

  /// <summary>Ein uses-Eintrag auf einem Weg durch den Uses-Graphen (#64): die Unit, zu der er führt, und ob
  /// er im interface-Teil steht. SourceFileName ist die Datei mit dem Eintrag, UsesName der Name, wie er dort
  /// steht (#896, Sprung zum Eintrag).</summary>
  TGroupUsesStep = record
    UnitName: string;
    FileName: string;
    InInterface: Boolean;
    SourceFileName: string;
    UsesName: string;
  end;

  /// <summary>Ein uses-Eintrag des Uses-Graphen zwischen zwei Units (ohne Programme und Packages).</summary>
  TGroupUsesEdge = record
    SourceUnit: string;
    SourceFileName: string;
    TargetUnit: string;
    TargetFileName: string;
    InInterface: Boolean;
  end;

  /// <summary>Leitet aus allen uses-Einträgen einen Wert ab, etwa eine Auswertung über den ganzen Graphen.</summary>
  TGroupUsesDerive = reference to function(const AEdges: TArray<TGroupUsesEdge>): IInterface;

  /// <summary>Die Projekte der Gruppe für projektweite Regeln wie unused-public-member (#1102); nil = unbekannt
  /// (Linter, Datei ohne Projekt), die Regeln schweigen.</summary>
  IProjectGroupFiles = interface
    ['{3F0B6C1D-9A47-4E2B-8D15-6C7A2E94B0F3}']
    /// <summary>Sind alle Projekte geladen und indiziert? Sonst nennt AReason den Grund ("Index läuft (180 von
    /// 214 Units)"), und projektweite Regeln schweigen.</summary>
    function Complete(out AReason: string): Boolean;
    /// <summary>Projekte, zu denen AFileName gehört, zuerst; mit AWholeGroup danach alle übrigen der Gruppe.
    /// AFileName '' liefert alle Projekte der Gruppe.</summary>
    function ProjectsOf(const AFileName: string; AWholeGroup: Boolean): TArray<TGroupProject>;
    /// <summary>Kommt AName als Bezeichner in AFileName vor (ohne Groß-/Kleinschreibung)? Unknown, wenn die
    /// Datei nicht gelesen werden kann.</summary>
    function NameIn(const AFileName, AName: string): TNameAnswer;
    /// <summary>Text der Datei, geöffnete Dokumente zuerst; False, wenn sie nicht lesbar ist.</summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Kürzester Weg über uses von der Unit AFromUnit (Name wie im uses, auch ohne Namensraum) zur
    /// Datei AToFile (#64): je uses-Eintrag ein Schritt, der letzte führt zu AToFile. Mit AInterfaceOnly nur
    /// über Einträge im interface-Teil. nil, wenn es keinen Weg gibt oder der Uses-Graph (#268) eine der
    /// Units nicht kennt.</summary>
    function UsesPath(const AFromUnit, AToFile: string; AInterfaceOnly: Boolean): TArray<TGroupUsesStep>;
    /// <summary>Units, die AFileName direkt im uses nennen, auch Programme und Packages (#64); False, wenn
    /// der Uses-Graph die Unit nicht kennt.</summary>
    function UsedBy(const AFileName: string; out AUsers: TArray<TGroupUsesStep>): Boolean;
    /// <summary>Aus allen uses-Einträgen des Uses-Graphen abgeleiteter Wert: ADerive läuft je Schlüssel
    /// einmal und erst wieder, wenn sich der Graph geändert hat. AKey nennt die Ableitung samt ihren Optionen.
    /// nil ohne Uses-Graph.</summary>
    function UsesDerived(const AKey: string; const ADerive: TGroupUsesDerive): IInterface;
  end;

  /// <summary>Art eines Namens mit Präfix-Vorgabe (#1111).</summary>
{$SCOPEDENUMS ON}
  TProjectNamingKind = (Local, Field, Parameter, Constant);
{$SCOPEDENUMS OFF}

  /// <summary>Präfix-Vorgaben der Projektdatei .atlas (naming, #452, #1111); Known = gesetzt, auch leer (= ohne
  /// Präfix).</summary>
  TProjectNaming = record
    Prefixes: array[TProjectNamingKind] of string;
    Known: array[TProjectNamingKind] of Boolean;
  end;

implementation

end.
