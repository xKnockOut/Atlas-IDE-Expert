unit Atlas.Common.Rules.Builtin;

// Alle eingebauten Prüfregeln an einer Stelle, für Editor und Linter.

interface

uses
  Atlas.Common.Rules.Contract;

/// <summary>Neue Instanzen aller eingebauten Regeln.</summary>
function BuiltinRules: TArray<IRule>;

implementation

uses
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Builtin.Unicode,
  Atlas.Common.Rules.Builtin.Architecture,
  Atlas.Common.Rules.Builtin.Concurrency,
  Atlas.Common.Rules.Builtin.Flow,
  Atlas.Common.Rules.Builtin.Unused,
  Atlas.Common.Rules.Builtin.Declarations,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.Capture,
  Atlas.Common.Rules.Builtin.Components,
  Atlas.Common.Rules.Builtin.FormFields,
  Atlas.Common.Rules.Builtin.Security,
  Atlas.Common.Rules.Builtin.General,
  Atlas.Common.Rules.Builtin.RtlPatterns,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Rules.Builtin.Exceptions,
  Atlas.Common.Rules.Builtin.Style,
  Atlas.Common.Rules.Builtin.PaletteIcons,
  Atlas.Common.Rules.Builtin.Performance,
  Atlas.Common.Rules.Builtin.DataBinding,
  Atlas.Common.Rules.Builtin.DfmProperties,
  Atlas.Common.Rules.Builtin.SlashCommands,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Rules.Builtin.Todos,
  Atlas.Common.Rules.Builtin.Recursion,
  Atlas.Common.Rules.Builtin.Deprecated,
  Atlas.Common.Rules.Builtin.ForwardDeclarations,
  Atlas.Common.Rules.Builtin.FreeFields,
  Atlas.Common.Rules.Builtin.Packages,
  Atlas.Common.Rules.Builtin.OpenTools,
  Atlas.Common.Rules.Builtin.Testing,
  Atlas.Common.Rules.Builtin.Events,
  Atlas.Common.Rules.Builtin.Ownership,
  Atlas.Common.Rules.Builtin.Expressions,
  Atlas.Common.Rules.Builtin.Statements,
  Atlas.Common.Rules.Builtin.Database,
  Atlas.Common.Rules.Builtin.Directives,
  Atlas.Common.Rules.Builtin.Properties,
  Atlas.Common.Rules.Builtin.Forms,
  Atlas.Common.Rules.Builtin.SharedState,
  Atlas.Common.Rules.Builtin.Unresolved;

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
    RegisterGeneralRules(Registry);
    RegisterRtlPatternRules(Registry);
    RegisterRtlTypePatternRules(Registry);
    RegisterExceptionRules(Registry);
    RegisterStyleRules(Registry);
    RegisterUnresolvedRules(Registry);
    RegisterPaletteIconRules(Registry);
    RegisterPerformanceRules(Registry);
    RegisterDataBindingRules(Registry);
    RegisterDfmPropertyRules(Registry);
    RegisterSlashCommandRules(Registry);
    RegisterMetricRules(Registry);
    RegisterTodoRules(Registry);
    RegisterRecursionRules(Registry);
    RegisterDeprecatedRules(Registry);
    RegisterForwardDeclarationRules(Registry);
    RegisterFreeFieldRules(Registry);
    RegisterPackageRules(Registry);
    RegisterOpenToolsRules(Registry);
    RegisterTestingRules(Registry);
    RegisterEventRules(Registry);
    RegisterOwnershipRules(Registry);
    RegisterExpressionRules(Registry);
    RegisterStatementRules(Registry);
    RegisterDatabaseRules(Registry);
    RegisterDirectiveRules(Registry);
    RegisterPropertyRules(Registry);
    RegisterFormRules(Registry);
    RegisterSharedStateRules(Registry);
    Result := Registry.Rules;
  finally
    Registry.Free;
  end;
end;

end.
