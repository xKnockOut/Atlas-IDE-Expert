unit Shell.Composition.Contract;

// Contract-Rolle Shell: Dienste, die mehrere Teile der Komposition gleich brauchen. Ein gemeinsamer Typ je
// Dienst, weil Delphi 12 zwei gleich aufgebaute Methodenreferenztypen nicht ineinander umwandelt.

interface

uses
  Shell.Workspace;

type
  /// <summary>Arbeit an einer Momentaufnahme der Arbeitsbereiche, unter deren Sperre ausgeführt.</summary>
  TShellWorkspacesProc = reference to procedure(const AWorkspaces: TArray<TShellWorkspace>);
  /// <summary>Ruft AVisit mit allen Arbeitsbereichen unter deren Sperre auf.</summary>
  TShellVisitWorkspacesProc = reference to procedure(const AVisit: TShellWorkspacesProc);

implementation

end.
