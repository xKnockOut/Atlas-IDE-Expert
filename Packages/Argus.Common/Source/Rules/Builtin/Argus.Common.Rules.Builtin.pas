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
  Argus.Common.Rules.Builtin.Unicode;

function BuiltinRules: TArray<IRule>;
var
  Registry: TRuleRegistry;
begin
  Registry := TRuleRegistry.Create;
  try
    RegisterUnicodeRules(Registry);
    Result := Registry.Rules;
  finally
    Registry.Free;
  end;
end;

end.
