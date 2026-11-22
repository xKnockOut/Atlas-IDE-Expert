unit Atlas.Common.Editing.Composition;

// Erzeugt die Schnittstellen, die Editing anderen Teilen des Servers anbietet (Atlas.Common.Editing.Contract.*).
// Die Shell gibt sie an die Host-Adapter (Shell.Composition.Mcp).

interface

uses
  Atlas.Common.Editing.Contract.Extract;

type
  TEditingComposition = record
    /// <summary>„Methode extrahieren“.</summary>
    class function Extract: IEditingExtract; static;
  end;

implementation

uses
  Atlas.Common.Editing.Providers.Extract;

{ TEditingComposition }

class function TEditingComposition.Extract: IEditingExtract;
begin
  Result := TEditingExtractProvider.Create;
end;

end.
