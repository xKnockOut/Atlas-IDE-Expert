unit Atlas.Common.Editing.Composition;

// Erzeugt die Schnittstellen, die Editing anderen Teilen des Servers anbietet (Atlas.Common.Editing.Contract.*).
// Die Shell gibt sie an die Host-Adapter (Shell.Composition.Mcp).

interface

uses
  Atlas.Common.Editing.Contract.ClassActions,
  Atlas.Common.Editing.Contract.ClassCompletion,
  Atlas.Common.Editing.Contract.CompilerFixes,
  Atlas.Common.Editing.Contract.Extract,
  Atlas.Common.Editing.Contract.Formatting,
  Atlas.Common.Editing.Contract.MethodOrder,
  Atlas.Common.Editing.Contract.MethodWithoutSelf;

type
  TEditingComposition = record
    /// <summary>Klassen-Aktionen: überschreiben, Interface implementieren, Zugriffsmethode anlegen.</summary>
    class function ClassActions: IEditingClassActions; static;
    /// <summary>Klassenvervollständigung: Zuordnung von Deklarationen und Rümpfen samt Korrekturen.</summary>
    class function ClassCompletion: IEditingClassCompletion; static;
    /// <summary>„Methode extrahieren“.</summary>
    class function Extract: IEditingExtract; static;
    /// <summary>Bedingung auslagern, Konstante einführen (Korrekturen der Prüfregeln).</summary>
    class function ExtractFixes: IEditingExtractFixes; static;
    /// <summary>Methoden ohne Self samt Umwandlung in class-Methoden.</summary>
    class function MethodsWithoutSelf: IEditingMethodsWithoutSelf; static;
    /// <summary>Prüfung der Methodenordnung je Typ samt Korrekturen.</summary>
    class function MethodOrder: IEditingMethodOrderReview; static;
    /// <summary>Formatierer mit Abweichungen.</summary>
    class function Formatting: IEditingFormatting; static;
    /// <summary>Schnellkorrekturen für Compilermeldungen.</summary>
    class function CompilerFixes: IEditingCompilerFixes; static;
  end;

implementation

uses
  Atlas.Common.Editing.Providers.ClassActions,
  Atlas.Common.Editing.Providers.ClassCompletion,
  Atlas.Common.Editing.Providers.CompilerFixes,
  Atlas.Common.Editing.Providers.Extract,
  Atlas.Common.Editing.Providers.Formatting,
  Atlas.Common.Editing.Providers.MethodOrder,
  Atlas.Common.Editing.Providers.MethodWithoutSelf;

{ TEditingComposition }

class function TEditingComposition.ClassActions: IEditingClassActions;
begin
  Result := TEditingClassActionsProvider.New;
end;

class function TEditingComposition.ClassCompletion: IEditingClassCompletion;
begin
  Result := TEditingClassCompletionProvider.Create;
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

class function TEditingComposition.Formatting: IEditingFormatting;
begin
  Result := TEditingFormattingProvider.Create;
end;

class function TEditingComposition.CompilerFixes: IEditingCompilerFixes;
begin
  Result := TEditingCompilerFixesProvider.Create;
end;

end.
