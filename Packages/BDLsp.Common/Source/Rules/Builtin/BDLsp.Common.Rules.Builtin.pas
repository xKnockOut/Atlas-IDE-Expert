unit BDLsp.Common.Rules.Builtin;

// Alle eingebauten Prüfregeln an einer Stelle, für Editor und Linter.

interface

uses
  BDLsp.Common.Rules.Contract;

/// <summary>Neue Instanzen aller eingebauten Regeln.</summary>
function BuiltinRules: TArray<IRule>;

implementation

uses
  BDLsp.Common.Rules.Registry,
  BDLsp.Common.Rules.Builtin.Unicode,
  BDLsp.Common.Rules.Builtin.UnitFiles,
  BDLsp.Common.Rules.Builtin.Architecture,
  BDLsp.Common.Rules.Builtin.Concurrency,
  BDLsp.Common.Rules.Builtin.Flow,
  BDLsp.Common.Rules.Builtin.Unused,
  BDLsp.Common.Rules.Builtin.Declarations,
  BDLsp.Common.Rules.Builtin.Inheritance,
  BDLsp.Common.Rules.Builtin.Capture,
  BDLsp.Common.Rules.Builtin.Components,
  BDLsp.Common.Rules.Builtin.FormFields,
  BDLsp.Common.Rules.Builtin.Security;

function BuiltinRules: TArray<IRule>;
var
  Registry: TRuleRegistry;
begin
  Registry := TRuleRegistry.Create;
  try
    RegisterUnicodeRules(Registry);
    RegisterUnitFileRules(Registry);
    RegisterArchitectureRules(Registry);
    RegisterConcurrencyRules(Registry);
    RegisterFlowRules(Registry);
    RegisterUnusedRules(Registry);
    RegisterDeclarationRules(Registry);
    RegisterInheritanceRules(Registry);
    RegisterCaptureRules(Registry);
    RegisterComponentRules(Registry);
    RegisterFormFieldRules(Registry);
    RegisterSecurityRules(Registry);
    Result := Registry.Rules;
  finally
    Registry.Free;
  end;
end;

end.
