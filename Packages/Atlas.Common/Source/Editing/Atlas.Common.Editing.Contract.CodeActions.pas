unit Atlas.Common.Editing.Contract.CodeActions;

// Code-Aktionen, die Editing dem Sprachserver anbietet (API, #42): Klassen-Aktionen und Felder freigeben,
// fehlende Methodenrümpfe, Zuweisung tauschen und String-Literale, uses-Aktionen, Dokumentationskommentar und
// Klassenmitglieder ordnen, uses aufräumen. Erzeugt wird die Umsetzung (Editing.Providers.CodeActions) von der
// Zusammensetzung des Hosts; der Sprachserver erreicht sie über einen Host-Adapter.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Editing.Contract;

type
  /// <summary>Einstellung "sortUses" für AUri als Optionen für "uses aufräumen" (#182, #284, #2794).</summary>
  TEditingUsesOrderFunc = reference to function(const AUri: string): TUsesRewrite;
  /// <summary>Index und Einstellungen für die uses-Aktionen; False ohne Index.</summary>
  TEditingUsesContextFunc = reference to function(const AUri: string; out AContext: TUsesContext): Boolean;
  /// <summary>Symbole des Projekts für die uses-Einträge in {$IFDEF}-Zweigen (#621); False ohne.</summary>
  TEditingDefinesFunc = reference to function(const AUri: string; out ADefines: TArray<string>): Boolean;
  /// <summary>Einstellungen "stringLiteral" für AUri und ob ein mehrzeiliger String entsteht (#312).</summary>
  TEditingStringLiteralFunc = reference to function(const AUri: string;
    out AMultiline: Boolean): TStringLiteralSettings;
  /// <summary>Einstellungen "memberOrder" für AUri (#89).</summary>
  TEditingMemberOrderFunc = reference to function(const AUri: string): TMemberOrderSettings;
  /// <summary>Einstellung "completeBlocks.docComment" für AUri (#88).</summary>
  TEditingDocCommentsFunc = reference to function(const AUri: string): Boolean;

  /// <summary>Umgebung der Klassen-Aktionen einer Datei: Index für Vorfahren und Interfaces aus anderen Units,
  /// Sprachversion und die Einstellungen der Erzeuger.</summary>
  TEditingClassEnvironment = record
    Index: ISymbolIndex;
    Namespaces: TArray<string>;
    DelphiVersion: string;
    /// <summary>Für die Einstellungen der Erzeuger (z. B. Abschnitt der Interface-Methoden); nil ohne.</summary>
    Host: ISlashHost;
  end;

  TEditingClassEnvironmentFunc = reference to function(const AUri: string): TEditingClassEnvironment;

  /// <summary>Einstellungen je Datei; ohne Zuweisung gelten die Vorgaben (keine uses-Aktionen ohne
  /// UsesContextFor, Klassen-Aktionen nur mit der Datei).</summary>
  TEditingCodeActionSettings = record
    UsesOrderFor: TEditingUsesOrderFunc;
    UsesContextFor: TEditingUsesContextFunc;
    DefinesFor: TEditingDefinesFunc;
    StringLiteralFor: TEditingStringLiteralFunc;
    MemberOrderFor: TEditingMemberOrderFunc;
    DocCommentsFor: TEditingDocCommentsFunc;
    ClassEnvironmentFor: TEditingClassEnvironmentFunc;
  end;

  /// <summary>Code-Aktionen an einer Stelle; die Gruppen stehen in der Reihenfolge, in der der Sprachserver sie
  /// zeigt.</summary>
  IEditingCodeActions = interface
    ['{CAFE6DF7-1D67-4EE5-ABB5-499139B74CC7}']
    /// <summary>Klassen-Aktionen (Getter/Setter/Feld, Interface-Methoden, Überschreiben) und Felder im Destruktor
    /// freigeben, je nach ASite.Refactoring.</summary>
    function Structure(const ASite: TCodeActionSite): TArray<TCodeAction>;
    /// <summary>Fehlende Methodenrümpfe am Anfang von ASite.Range (#1834).</summary>
    function MissingBodies(const ASite: TCodeActionSite; out AAction: TCodeAction): Boolean;
    /// <summary>Zuweisung tauschen und Aktionen an String-Literalen (#312).</summary>
    function Statements(const ASite: TCodeActionSite): TArray<TCodeAction>;
    /// <summary>uses-Aktionen (#284, #621): fehlende Unit ergänzen, verschieben, entfernen.</summary>
    function UsesActions(const ASite: TCodeActionSite): TArray<TCodeAction>;
    /// <summary>Dokumentationskommentar (#88) und Klassenmitglieder ordnen (#89).</summary>
    function Declarations(const ASite: TCodeActionSite): TArray<TCodeAction>;
    /// <summary>source.organizeImports (#182); False, wenn es nichts aufzuräumen gibt.</summary>
    function OrganizeImports(const ASite: TCodeActionSite; out AAction: TCodeAction): Boolean;
  end;

implementation

end.
