unit Atlas.Common.Rules.Builtin.Registration.Types;

// Anmeldung der eingebauten Prüfregeln für Typen in Ausdrücken (Typprüfungen, Typarten, unverträgliche Typen, typabhängige
// Ausdrücke, Einschränkungen, Casts, Umwandlungen zwischen String-, Zahl- und Zeigertypen). Atlas.Common.Rules.Builtin ruft die Registration-Units
// nacheinander auf; eine je Thema.

interface

uses
  Atlas.Common.Rules.Registry;

/// <summary>Meldet die Regeln für Typen in Ausdrücken in ARegistry an.</summary>
procedure RegisterBuiltinTypeRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Builtin.TypeChecks,
  Atlas.Common.Rules.Builtin.TypeKinds,
  Atlas.Common.Rules.Builtin.TypeMismatch,
  Atlas.Common.Rules.Builtin.TypedExpressions,
  Atlas.Common.Rules.Builtin.TypeRestrictions,
  Atlas.Common.Rules.Builtin.Casts,
  Atlas.Common.Rules.Builtin.Conversions,
  Atlas.Common.Rules.Builtin.StringConversions,
  Atlas.Common.Rules.Builtin.StringAddress;

procedure RegisterBuiltinTypeRules(const ARegistry: TRuleRegistry);
begin
  RegisterTypeCheckRules(ARegistry);
  RegisterTypeKindRules(ARegistry);
  RegisterTypeMismatchRules(ARegistry);
  RegisterTypedExpressionRules(ARegistry);
  RegisterTypeRestrictionRules(ARegistry);
  RegisterCastRules(ARegistry);
  RegisterConversionRules(ARegistry);
  RegisterStringConversionRules(ARegistry);
  RegisterStringAddressRules(ARegistry);
end;

end.
