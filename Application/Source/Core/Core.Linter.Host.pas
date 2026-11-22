unit Core.Linter.Host;

// Host-Rolle Core: was der Linter-Modus (--check und verwandte Befehle) von außen braucht, als Host-Core aber nicht
// selbst erzeugt (Konzept 8.1): installierte Delphi-Versionen, Zugriff auf git und svn, die Gruppe der Arbeitsbereiche
// samt Dokumenten und Protokoll sowie das Schreiben der Anweisungsdateien. Die Shell setzt es zusammen (TLinterShell).

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.Instructions,
  Core.VersionControlChanges,
  Core.WorkspaceGroup;

type
  /// <summary>Gruppe der Arbeitsbereiche über AConfigRoot, die in AIndex indiziert.</summary>
  TCoreLinterGroupFactory = reference to function(const AConfigRoot: string; const AIndex: ISymbolIndex):
    TCoreWorkspaceGroup;

  /// <summary>Anweisungsdateien für KI-Assistenten unter ARoot prüfen bzw. mit AWrite schreiben (#2615).</summary>
  TCoreLinterInstructions = reference to function(const ARoot: string; const ASettings: TServerSettings;
    AWrite: Boolean): TArray<TInstructionsFile>;

  TCoreLinterHost = record
    /// <summary>Installierte Delphi-Versionen (BDS-Nummern).</summary>
    InstalledVersions: TFunc<TArray<string>>;
    /// <summary>Neuer Zugriff auf git und svn für die Kommandozeile.</summary>
    Vcs: TFunc<TCoreVcsAccess>;
    NewGroup: TCoreLinterGroupFactory;
    Instructions: TCoreLinterInstructions;
  end;

implementation

end.
