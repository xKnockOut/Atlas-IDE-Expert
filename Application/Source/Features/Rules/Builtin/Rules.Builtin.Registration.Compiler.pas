unit Rules.Builtin.Registration.Compiler;

// Anmeldung der eingebauten Prüfregeln für Compiler und Quelltext (Fallen, die dcc anders liest als gemeint, Hinweise des
// Compilers, Delphi-Semantik, Zeilenumbrüche, Migration nach Win64 und Unicode, Zeichen im Quelltext, unsicherer Code,
// Assembler). Rules.Builtin ruft die Registration-Units
// nacheinander auf; eine je Thema.

interface

uses
  Rules.Registry;

/// <summary>Meldet die Regeln für Compiler und Quelltext in ARegistry an.</summary>
procedure RegisterBuiltinCompilerRules(const ARegistry: TRuleRegistry);

implementation

uses
  Rules.Builtin.CompilerTraps,
  Rules.Builtin.CompilerTraps.Rtl,
  Rules.Builtin.CompilerTraps.Scopes,
  Rules.Builtin.CompilerTraps.MethodRefs,
  Rules.Builtin.CompilerHints,
  Rules.Builtin.DelphiSemantics,
  Rules.Builtin.LineBreaks,
  Rules.Builtin.Migration,
  Rules.Builtin.Unicode,
  Rules.Builtin.UnsafeCode,
  Rules.Builtin.Assembler;

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
