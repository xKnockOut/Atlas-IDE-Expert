unit Atlas.Common.Rules.Builtin.Registration.Compiler;

// Anmeldung der eingebauten Prüfregeln für Compiler und Quelltext (Fallen, die dcc anders liest als gemeint, Hinweise des
// Compilers, Delphi-Semantik, Zeilenumbrüche, Migration nach Win64 und Unicode, Zeichen im Quelltext, unsicherer Code,
// Assembler). Atlas.Common.Rules.Builtin ruft die Registration-Units
// nacheinander auf; eine je Thema.

interface

uses
  Atlas.Common.Rules.Registry;

/// <summary>Meldet die Regeln für Compiler und Quelltext in ARegistry an.</summary>
procedure RegisterBuiltinCompilerRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Builtin.CompilerTraps,
  Atlas.Common.Rules.Builtin.CompilerTraps.Rtl,
  Atlas.Common.Rules.Builtin.CompilerTraps.Scopes,
  Atlas.Common.Rules.Builtin.CompilerTraps.MethodRefs,
  Atlas.Common.Rules.Builtin.CompilerHints,
  Atlas.Common.Rules.Builtin.DelphiSemantics,
  Atlas.Common.Rules.Builtin.LineBreaks,
  Atlas.Common.Rules.Builtin.Migration,
  Atlas.Common.Rules.Builtin.Unicode,
  Atlas.Common.Rules.Builtin.UnsafeCode,
  Atlas.Common.Rules.Builtin.Assembler;

procedure RegisterBuiltinCompilerRules(const ARegistry: TRuleRegistry);
begin
  RegisterCompilerTrapRules(ARegistry);
  RegisterCompilerTrapRtlRules(ARegistry);
  RegisterCompilerTrapScopeRules(ARegistry);
  RegisterCompilerTrapMethodRefRules(ARegistry);
  RegisterCompilerHintRules(ARegistry);
  RegisterDelphiSemanticsRules(ARegistry);
  RegisterLineBreakRules(ARegistry);
  RegisterMigrationRules(ARegistry);
  RegisterUnicodeRules(ARegistry);
  RegisterUnsafeCodeRules(ARegistry);
  RegisterAssemblerRules(ARegistry);
end;

end.
