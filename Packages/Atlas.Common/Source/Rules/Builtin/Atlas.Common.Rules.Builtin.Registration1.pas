unit Atlas.Common.Rules.Builtin.Registration1;

// Anmeldung der ersten Gruppe eingebauter Prüfregeln für Atlas.Common.Rules.Builtin. Die Gruppen teilen
// die Anmeldung nur auf, damit keine Unit zu viele Units einbindet; die Reihenfolge bleibt erhalten.

interface

uses
  Atlas.Common.Rules.Registry;

/// <summary>Meldet die Regeln der ersten Gruppe in ARegistry an.</summary>
procedure RegisterBuiltinRules1(const ARegistry: TRuleRegistry);

implementation

uses
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
  Atlas.Common.Rules.Builtin.Unresolved,
  Atlas.Common.Rules.Builtin.PaletteIcons,
  Atlas.Common.Rules.Builtin.Performance,
  Atlas.Common.Rules.Builtin.DataBinding,
  Atlas.Common.Rules.Builtin.DfmProperties,
  Atlas.Common.Rules.Builtin.SlashCommands,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Rules.Builtin.Todos,
  Atlas.Common.Rules.Builtin.DebugDisplay,
  Atlas.Common.Rules.Builtin.Recursion,
  Atlas.Common.Rules.Builtin.Deprecated;

procedure RegisterBuiltinRules1(const ARegistry: TRuleRegistry);
begin
  RegisterUnicodeRules(ARegistry);
  RegisterArchitectureRules(ARegistry);
  RegisterConcurrencyRules(ARegistry);
  RegisterFlowRules(ARegistry);
  RegisterUnusedRules(ARegistry);
  RegisterDeclarationRules(ARegistry);
  RegisterInheritanceRules(ARegistry);
  RegisterCaptureRules(ARegistry);
  RegisterComponentRules(ARegistry);
  RegisterFormFieldRules(ARegistry);
  RegisterSecurityRules(ARegistry);
  RegisterGeneralRules(ARegistry);
  RegisterRtlPatternRules(ARegistry);
  RegisterRtlTypePatternRules(ARegistry);
  RegisterExceptionRules(ARegistry);
  RegisterStyleRules(ARegistry);
  RegisterUnresolvedRules(ARegistry);
  RegisterPaletteIconRules(ARegistry);
  RegisterPerformanceRules(ARegistry);
  RegisterDataBindingRules(ARegistry);
  RegisterDfmPropertyRules(ARegistry);
  RegisterSlashCommandRules(ARegistry);
  RegisterMetricRules(ARegistry);
  RegisterTodoRules(ARegistry);
  RegisterDebugDisplayRules(ARegistry);
  RegisterRecursionRules(ARegistry);
  RegisterDeprecatedRules(ARegistry);
end;

end.
