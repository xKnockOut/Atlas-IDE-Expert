unit Atlas.Common.Rules.Builtin;

// Alle eingebauten Prüfregeln an einer Stelle, für Editor und Linter. Die Anmeldung steht in drei Gruppen
// (Atlas.Common.Rules.Builtin.Registration1 bis 3), damit keine Unit zu viele Units einbindet.

interface

uses
  Atlas.Common.Rules.Contract;

/// <summary>Neue Instanzen aller eingebauten Regeln.</summary>
function BuiltinRules: TArray<IRule>;

implementation

uses
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Builtin.Registration1,
  Atlas.Common.Rules.Builtin.Registration2,
  Atlas.Common.Rules.Builtin.Registration3;

function BuiltinRules: TArray<IRule>;
var
  mRegistry: TRuleRegistry;
begin
  mRegistry := TRuleRegistry.Create;
  try
    RegisterBuiltinRules1(mRegistry);
    RegisterBuiltinRules2(mRegistry);
    RegisterBuiltinRules3(mRegistry);
    Result := mRegistry.Rules;
  finally
    mRegistry.Free;
  end;
end;

end.
