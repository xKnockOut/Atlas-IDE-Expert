unit Atlas.Common.Editing.Composition;

// Erzeugt die Schnittstellen, die Editing anderen Teilen des Servers anbietet (Atlas.Common.Editing.Contract.*).
// Die Shell gibt sie an die Host-Adapter (Shell.Composition.Mcp).

interface

uses
  Atlas.Common.Editing.Contract.CompilerFixes,
  Atlas.Common.Editing.Contract.Extract,
  Atlas.Common.Editing.Contract.Formatting;

type
  TEditingComposition = record
    /// <summary>„Methode extrahieren“.</summary>
    class function Extract: IEditingExtract; static;
    /// <summary>Formatierer mit Abweichungen.</summary>
    class function Formatting: IEditingFormatting; static;
    /// <summary>Schnellkorrekturen für Compilermeldungen.</summary>
    class function CompilerFixes: IEditingCompilerFixes; static;
  end;

implementation

uses
  Atlas.Common.Editing.Providers.CompilerFixes,
  Atlas.Common.Editing.Providers.Extract,
  Atlas.Common.Editing.Providers.Formatting;

{ TEditingComposition }

class function TEditingComposition.Extract: IEditingExtract;
begin
  Result := TEditingExtractProvider.Create;
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
