unit Argus.Common.Rules.Builtin;

// Alle eingebauten Prüfregeln an einer Stelle, für Editor und Linter.

interface

uses
  Argus.Common.Rules.Contract;

/// <summary>Neue Instanzen aller eingebauten Regeln.</summary>
function BuiltinRules: TArray<IRule>;

implementation

uses
  Argus.Common.Rules.Registry,
  Argus.Common.Rules.Builtin.Unicode,
  Argus.Common.Rules.Builtin.Architecture,
  Argus.Common.Rules.Builtin.Concurrency,
  Argus.Common.Rules.Builtin.Flow,
  Argus.Common.Rules.Builtin.Unused,
  Argus.Common.Rules.Builtin.Declarations,
  Argus.Common.Rules.Builtin.Inheritance,
  Argus.Common.Rules.Builtin.Capture,
  Argus.Common.Rules.Builtin.Components,
  Argus.Common.Rules.Builtin.FormFields,
  Argus.Common.Rules.Builtin.Security,
  Argus.Common.Rules.Builtin.DataBinding;

function BuiltinRules: TArray<IRule>;
var
  Registry: TRuleRegistry;
begin
  Registry := TRuleRegistry.Create;
  try
    RegisterUnicodeRules(Registry);
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
    RegisterDataBindingRules(Registry);
    Result := Registry.Rules;
  finally
    Registry.Free;
  end;
end;

end.
