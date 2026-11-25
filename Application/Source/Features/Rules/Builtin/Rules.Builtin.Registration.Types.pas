unit Rules.Builtin.Registration.Types;

// Anmeldung der eingebauten Prüfregeln für Typen in Ausdrücken (Typprüfungen, Typarten, unverträgliche Typen, typabhängige
// Ausdrücke, Einschränkungen, Casts, Umwandlungen zwischen String-, Zahl- und Zeigertypen). Rules.Builtin ruft die Registration-Units
// nacheinander auf; eine je Thema.

interface

uses
  Rules.Registry;

/// <summary>Meldet die Regeln für Typen in Ausdrücken in ARegistry an.</summary>
procedure RegisterBuiltinTypeRules(const ARegistry: TRuleRegistry);

implementation

uses
  Rules.Builtin.TypeChecks,
  Rules.Builtin.TypeKinds,
  Rules.Builtin.TypeMismatch,
  Rules.Builtin.TypedExpressions,
  Rules.Builtin.TypeRestrictions,
  Rules.Builtin.Casts,
  Rules.Builtin.Conversions,
  Rules.Builtin.StringConversions,
  Rules.Builtin.StringAddress;

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
