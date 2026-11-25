unit Rules.Builtin.Registration.Statements;

// Anmeldung der eingebauten Prüfregeln für Anweisungen und Ausdrücke (Ablauf, Aufrufe, Sprünge, Schleifen, Bedingungen,
// Rekursion, eingefangene Variablen, verworfene Ergebnisse, Redewendungen, Performance, Format-Argumente). Rules.Builtin ruft die Registration-Units
// nacheinander auf; eine je Thema.

interface

uses
  Rules.Registry;

/// <summary>Meldet die Regeln für Anweisungen und Ausdrücke in ARegistry an.</summary>
procedure RegisterBuiltinStatementRules(const ARegistry: TRuleRegistry);

implementation

uses
  Rules.Builtin.Flow,
  Rules.Builtin.Capture,
  Rules.Builtin.Performance,
  Rules.Builtin.Recursion,
  Rules.Builtin.Expressions,
  Rules.Builtin.Statements,
  Rules.Builtin.Calls,
  Rules.Builtin.Jumps,
  Rules.Builtin.Loops,
  Rules.Builtin.IgnoredResult,
  Rules.Builtin.Conditions,
  Rules.Builtin.Idioms,
  Rules.Builtin.Inlining,
  Rules.Builtin.FormatArgs;

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
