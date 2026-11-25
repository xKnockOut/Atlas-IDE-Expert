unit Atlas.Common.Rules.Builtin.Registration.Statements;

// Anmeldung der eingebauten Prüfregeln für Anweisungen und Ausdrücke (Ablauf, Aufrufe, Sprünge, Schleifen, Bedingungen,
// Rekursion, eingefangene Variablen, verworfene Ergebnisse, Redewendungen, Performance, Format-Argumente). Atlas.Common.Rules.Builtin ruft die Registration-Units
// nacheinander auf; eine je Thema.

interface

uses
  Atlas.Common.Rules.Registry;

/// <summary>Meldet die Regeln für Anweisungen und Ausdrücke in ARegistry an.</summary>
procedure RegisterBuiltinStatementRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Builtin.Flow,
  Atlas.Common.Rules.Builtin.Capture,
  Atlas.Common.Rules.Builtin.Performance,
  Atlas.Common.Rules.Builtin.Recursion,
  Atlas.Common.Rules.Builtin.Expressions,
  Atlas.Common.Rules.Builtin.Statements,
  Atlas.Common.Rules.Builtin.Calls,
  Atlas.Common.Rules.Builtin.Jumps,
  Atlas.Common.Rules.Builtin.Loops,
  Atlas.Common.Rules.Builtin.IgnoredResult,
  Atlas.Common.Rules.Builtin.Conditions,
  Atlas.Common.Rules.Builtin.Idioms,
  Atlas.Common.Rules.Builtin.Inlining,
  Atlas.Common.Rules.Builtin.FormatArgs;

procedure RegisterBuiltinStatementRules(const ARegistry: TRuleRegistry);
begin
  RegisterFlowRules(ARegistry);
  RegisterCaptureRules(ARegistry);
  RegisterPerformanceRules(ARegistry);
  RegisterRecursionRules(ARegistry);
  RegisterExpressionRules(ARegistry);
  RegisterStatementRules(ARegistry);
  RegisterCallRules(ARegistry);
  RegisterJumpRules(ARegistry);
  RegisterLoopRules(ARegistry);
  RegisterIgnoredResultRules(ARegistry);
  RegisterConditionRules(ARegistry);
  RegisterIdiomRules(ARegistry);
  RegisterInliningRules(ARegistry);
  RegisterFormatArgsRules(ARegistry);
end;

end.
