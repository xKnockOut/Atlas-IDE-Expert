unit Editing.Composition;

// Erzeugt die Schnittstellen, die Editing anderen Teilen des Servers anbietet (Editing.Contract.*).
// Die Shell gibt sie an die Host-Adapter (Shell.Composition.Mcp).

interface

uses
  Editing.Contract.BoundaryCases,
  Editing.Contract.ClassActions,
  Editing.Contract.CodeActions,
  Editing.Contract.ClassCompletion,
  Editing.Contract.CompilerFixes,
  Editing.Contract.Extract,
  Editing.Contract.Formatting,
  Editing.Contract.MethodOrder,
  Editing.Contract.SlashCommands,
  Editing.Contract.MethodWithoutSelf;

type
  TEditingComposition = record
    /// <summary>Klassen-Aktionen: überschreiben, Interface implementieren, Zugriffsmethode anlegen.</summary>
    class function ClassActions: IEditingClassActions; static;
    /// <summary>Klassenvervollständigung: Zuordnung von Deklarationen und Rümpfen samt Korrekturen.</summary>
    class function ClassCompletion: IEditingClassCompletion; static;
    /// <summary>Code-Aktionen des Sprachservers aus Editing (Klasse, Anweisung, uses, Deklarationen).</summary>
    class function CodeActions(const ASettings: TEditingCodeActionSettings): IEditingCodeActions; static;
    /// <summary>„Methode extrahieren“.</summary>
    class function Extract: IEditingExtract; static;
    /// <summary>Bedingung auslagern, Konstante einführen (Korrekturen der Prüfregeln).</summary>
    class function ExtractFixes: IEditingExtractFixes; static;
    /// <summary>Methoden ohne Self samt Umwandlung in class-Methoden.</summary>
    class function MethodsWithoutSelf: IEditingMethodsWithoutSelf; static;
    /// <summary>Prüfung der Methodenordnung je Typ samt Korrekturen.</summary>
    class function MethodOrder: IEditingMethodOrderReview; static;
    /// <summary>Prüfung der Schnellbefehle.</summary>
    class function SlashChecks: IEditingSlashChecks; static;
    /// <summary>Formatierer mit Abweichungen.</summary>
    class function Formatting: IEditingFormatting; static;
    /// <summary>Schnellkorrekturen für Compilermeldungen.</summary>
    class function CompilerFixes: IEditingCompilerFixes; static;
    /// <summary>Grenzfälle einer Routine als Bericht.</summary>
    class function BoundaryCases: IEditingBoundaryCases; static;
  end;

implementation

uses
  Editing.Providers.BoundaryCases,
  Editing.Providers.ClassActions,
  Editing.Providers.ClassCompletion,
  Editing.Providers.CodeActions,
  Editing.Providers.CompilerFixes,
  Editing.Providers.Extract,
  Editing.Providers.Formatting,
  Editing.Providers.MethodOrder,
  Editing.Providers.MethodWithoutSelf,
  Editing.Providers.SlashCommands;

{ TEditingComposition }

class function TEditingComposition.ClassActions: IEditingClassActions;
begin
  Result := TEditingClassActionsProvider.New;
end;

class function TEditingComposition.ClassCompletion: IEditingClassCompletion;
begin
  Result := TEditingClassCompletionProvider.Create;
end;

class function TEditingComposition.CodeActions(const ASettings: TEditingCodeActionSettings): IEditingCodeActions;
begin
  Result := TEditingCodeActionsProvider.Create(ASettings);
end;

class function TEditingComposition.Extract: IEditingExtract;
begin
  Result := TEditingExtractProvider.Create;
end;

class function TEditingComposition.ExtractFixes: IEditingExtractFixes;
begin
  Result := TEditingExtractProvider.Create;
end;

class function TEditingComposition.MethodsWithoutSelf: IEditingMethodsWithoutSelf;
begin
  Result := TEditingMethodsWithoutSelfProvider.Create;
end;

class function TEditingComposition.MethodOrder: IEditingMethodOrderReview;
begin
  Result := TEditingMethodOrderProvider.Create;
end;

class function TEditingComposition.SlashChecks: IEditingSlashChecks;
begin
  Result := TEditingSlashChecksProvider.Create;
end;

class function TEditingComposition.Formatting: IEditingFormatting;
begin
  Result := TEditingFormattingProvider.Create;
end;

class function TEditingComposition.CompilerFixes: IEditingCompilerFixes;
begin
  Result := TEditingCompilerFixesProvider.Create;
end;

class function TEditingComposition.BoundaryCases: IEditingBoundaryCases;
begin
  Result := TEditingBoundaryCasesProvider.Create;
end;

end.
