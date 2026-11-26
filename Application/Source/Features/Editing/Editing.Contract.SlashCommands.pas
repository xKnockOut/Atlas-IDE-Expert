unit Editing.Contract.SlashCommands;

// API von Editing: Befehlszeilen "/name", die stehen bleiben, weil der Befehl unbekannt ist oder an der Stelle
// nicht passt (#293).

interface

uses
  Atlas.Common.Index.Contract,
  Editing.Contract;

type
  /// <summary>Prüft die Schnellbefehle einer Unit.</summary>
  IEditingSlashChecks = interface
    ['{471DD189-89CF-4CE6-BCC9-ACB7F2C67A3A}']
    /// <summary>Befehlszeilen in AText, die nicht ausgeführt würden, samt Grund. AIndex darf nil sein.</summary>
    function Problems(const AText: string; const AIndex: ISymbolIndex;
      const ADelphiVersion: string): TArray<TSlashProblem>;
    /// <summary>Hinweis zu "/ignore ARuleId", wenn die Regel in der Zeile darunter nichts meldet.</summary>
    function IgnoreWithoutHit(const ARuleId: string): string;
  end;

implementation

end.
