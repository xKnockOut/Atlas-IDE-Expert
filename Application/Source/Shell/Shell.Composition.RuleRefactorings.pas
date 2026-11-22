unit Shell.Composition.RuleRefactorings;

// Verdrahtung der Korrekturen aus Refactorings für die Prüfregeln: Editing bietet die Refactorings über seinen
// Contract an, der Host-Adapter Adapters.Rules.Refactorings übersetzt sie in die SPI von Rules.

interface

uses
  Atlas.Common.Rules.Contract.Refactorings;

type
  TShellRuleRefactorings = record
    /// <summary>Alle Refactorings, die Prüfregeln als Korrektur anbieten.</summary>
    class function Create: TRuleRefactorings; static;
  end;

implementation

uses
  Atlas.Common.Editing.Providers.ClassActions,
  Adapters.Rules.Refactorings;

class function TShellRuleRefactorings.Create: TRuleRefactorings;
begin
  Result := TRuleRefactoringsAdapters.Create(TEditingClassActionsProvider.New);
end;

end.
