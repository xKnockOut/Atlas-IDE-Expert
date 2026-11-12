unit Atlas.Common.Rules.Builtin.Registration.Statements;

// Anmeldung der eingebauten Prüfregeln für Anweisungen und Ausdrücke (Ablauf, Aufrufe, Sprünge, Schleifen,
// Bedingungen, Typprüfungen, Casts, Zeichenketten, Migration nach Win64 und Unicode, Performance, unsicherer
// Code). Atlas.Common.Rules.Builtin ruft die drei Registration-Units nacheinander auf; nach Themen aufgeteilt,
// damit keine Unit zu viele Units einbindet (metric-uses-count).

interface

uses
  Atlas.Common.Rules.Registry;

/// <summary>Meldet die Regeln für Anweisungen und Ausdrücke in ARegistry an.</summary>
procedure RegisterBuiltinStatementRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Builtin.Unicode,
  Atlas.Common.Rules.Builtin.Flow,
  Atlas.Common.Rules.Builtin.Capture,
  Atlas.Common.Rules.Builtin.Performance,
  Atlas.Common.Rules.Builtin.Recursion,
  Atlas.Common.Rules.Builtin.Expressions,
  Atlas.Common.Rules.Builtin.Statements,
  Atlas.Common.Rules.Builtin.Calls,
  Atlas.Common.Rules.Builtin.Jumps,
  Atlas.Common.Rules.Builtin.Loops,
  Atlas.Common.Rules.Builtin.TypeChecks,
  Atlas.Common.Rules.Builtin.TypeKinds,
  Atlas.Common.Rules.Builtin.TypeMismatch,
  Atlas.Common.Rules.Builtin.CompilerTraps,
  Atlas.Common.Rules.Builtin.IgnoredResult,
  Atlas.Common.Rules.Builtin.Conditions,
  Atlas.Common.Rules.Builtin.Idioms,
  Atlas.Common.Rules.Builtin.Inlining,
  Atlas.Common.Rules.Builtin.CompilerHints,
  Atlas.Common.Rules.Builtin.TypedExpressions,
  Atlas.Common.Rules.Builtin.Migration,
  Atlas.Common.Rules.Builtin.StringConversions,
  Atlas.Common.Rules.Builtin.TypeRestrictions,
  Atlas.Common.Rules.Builtin.Casts,
  Atlas.Common.Rules.Builtin.UnsafeCode,
  Atlas.Common.Rules.Builtin.StringAddress,
  Atlas.Common.Rules.Builtin.FormatArgs,
  Atlas.Common.Rules.Builtin.Assembler;

procedure RegisterBuiltinStatementRules(const ARegistry: TRuleRegistry);
begin
  RegisterUnicodeRules(ARegistry);
  RegisterFlowRules(ARegistry);
  RegisterCaptureRules(ARegistry);
  RegisterPerformanceRules(ARegistry);
  RegisterRecursionRules(ARegistry);
  RegisterExpressionRules(ARegistry);
  RegisterStatementRules(ARegistry);
  RegisterCallRules(ARegistry);
  RegisterJumpRules(ARegistry);
  RegisterLoopRules(ARegistry);
  RegisterTypeCheckRules(ARegistry);
  RegisterTypeKindRules(ARegistry);
  RegisterTypeMismatchRules(ARegistry);
  RegisterCompilerTrapRules(ARegistry);
  RegisterIgnoredResultRules(ARegistry);
  RegisterConditionRules(ARegistry);
  RegisterIdiomRules(ARegistry);
  RegisterInliningRules(ARegistry);
  RegisterCompilerHintRules(ARegistry);
  RegisterTypedExpressionRules(ARegistry);
  RegisterMigrationRules(ARegistry);
  RegisterStringConversionRules(ARegistry);
  RegisterTypeRestrictionRules(ARegistry);
  RegisterCastRules(ARegistry);
  RegisterUnsafeCodeRules(ARegistry);
  RegisterStringAddressRules(ARegistry);
  RegisterFormatArgsRules(ARegistry);
  RegisterAssemblerRules(ARegistry);
end;

end.
