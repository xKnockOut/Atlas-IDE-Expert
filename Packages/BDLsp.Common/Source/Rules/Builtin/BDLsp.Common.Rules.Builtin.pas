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
  BDLsp.Common.Rules.Builtin.Architecture;

function BuiltinRules: TArray<IRule>;
var
  Registry: TRuleRegistry;
begin
  Registry := TRuleRegistry.Create;
  try
    RegisterUnicodeRules(Registry);
    RegisterUnitFileRules(Registry);
    RegisterArchitectureRules(Registry);
    Result := Registry.Rules;
  finally
    Registry.Free;
  end;
end;

end.
