unit Atlas.Common.Rules.Builtin;

// Alle eingebauten Prüfregeln an einer Stelle, für Editor und Linter. Die Anmeldung steht nach Themen in
// Atlas.Common.Rules.Builtin.Registration.Declarations, .Statements, .Types, .Compiler, .Frameworks und .Ownership.

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
  Atlas.Common.Rules.Builtin.Registration.Types,
  Atlas.Common.Rules.Builtin.Registration.Compiler,
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
    RegisterBuiltinTypeRules(mRegistry);
    RegisterBuiltinCompilerRules(mRegistry);
    RegisterBuiltinFrameworkRules(mRegistry);
    RegisterBuiltinOwnershipRules(mRegistry);
    Result := mRegistry.Rules;
  finally
    mRegistry.Free;
  end;
end;

end.
