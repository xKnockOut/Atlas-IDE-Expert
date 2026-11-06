unit Atlas.Common.Rules.Builtin.TypeRestrictions;

// Feste Sprachregeln für Typdeklarationen (#909, Gruppe Compiler vorab), die der Parser allein erkennt. Jede Regel
// steht in einer eigenen Unit; RegisterTypeRestrictionRules meldet alle an:
//   operator-declaration-invalid  TypeRestrictions.Operators
//   generic-declaration-invalid   TypeRestrictions.Generics
//   type-restriction-violated     TypeRestrictions.Records
//   attribute-usage-invalid       TypeRestrictions.Attributes
//   typeinfo-invalid              TypeRestrictions.TypeInfo
// Gemeinsame Hilfen: TypeRestrictions.Heads (Kopf einer Routine, Typen der Datei) und TypeRestrictions.Symbols.

interface

uses
  Atlas.Common.Rules.Registry;

procedure RegisterTypeRestrictionRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Builtin.TypeRestrictions.Operators,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Generics,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Records,
  Atlas.Common.Rules.Builtin.TypeRestrictions.Attributes,
  Atlas.Common.Rules.Builtin.TypeRestrictions.TypeInfo;

procedure RegisterTypeRestrictionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOperatorDeclarationInvalidRule.Create);
  ARegistry.Register(TGenericDeclarationInvalidRule.Create);
  ARegistry.Register(TTypeRestrictionViolatedRule.Create);
  ARegistry.Register(TAttributeUsageInvalidRule.Create);
  ARegistry.Register(TTypeInfoInvalidRule.Create);
end;

end.
