unit Atlas.Common.Rules.Builtin;

// Alle eingebauten Prüfregeln an einer Stelle, für Editor und Linter. Die Anmeldung steht nach Themen in
// Atlas.Common.Rules.Builtin.Registration.Declarations, .Statements, .Frameworks und .Ownership, damit keine Unit zu
// viele Units einbindet.

interface

uses
  Atlas.Common.Rules.Contract;

/// <summary>Neue Instanzen aller eingebauten Regeln.</summary>
function BuiltinRules: TArray<IRule>;

implementation

uses
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Builtin.Registration.Declarations,
  Atlas.Common.Rules.Builtin.Registration.Statements,
  Atlas.Common.Rules.Builtin.Registration.Frameworks,
  Atlas.Common.Rules.Builtin.Registration.Ownership;

function BuiltinRules: TArray<IRule>;
var
  mRegistry: TRuleRegistry;
begin
  mRegistry := TRuleRegistry.Create;
  try
    RegisterBuiltinDeclarationRules(mRegistry);
    RegisterBuiltinStatementRules(mRegistry);
    RegisterBuiltinFrameworkRules(mRegistry);
    RegisterBuiltinOwnershipRules(mRegistry);
    Result := mRegistry.Rules;
  finally
    mRegistry.Free;
  end;
end;

end.
