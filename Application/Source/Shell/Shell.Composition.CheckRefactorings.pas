unit Shell.Composition.CheckRefactorings;

// Verdrahtung der Korrekturen aus Refactorings für die Prüfregeln: Editing bietet die Refactorings über seinen
// Contract an, der Host-Adapter Adapters.Checks.Refactorings übersetzt sie in die SPI von Rules.

interface

uses
  Atlas.Common.Checks.Contract.Refactorings;

type
  TShellCheckRefactorings = record
    /// <summary>Alle Refactorings, die Prüfregeln als Korrektur anbieten.</summary>
    class function Create: TCheckRefactorings; static;
  end;

implementation

uses
  Atlas.Common.Editing.Composition,
  Adapters.Checks.Refactorings;

class function TShellCheckRefactorings.Create: TCheckRefactorings;
var
  mSources: TCheckRefactoringSources;
begin
  mSources := Default(TCheckRefactoringSources);
  mSources.Classes := TEditingComposition.ClassActions;
  mSources.Extract := TEditingComposition.ExtractFixes;
  mSources.Methods := TEditingComposition.MethodsWithoutSelf;
  mSources.Order := TEditingComposition.MethodOrder;
  mSources.Completion := TEditingComposition.ClassCompletion;
  mSources.Commands := TEditingComposition.SlashChecks;
  Result := TCheckRefactoringsAdapters.Create(mSources);
end;

end.
