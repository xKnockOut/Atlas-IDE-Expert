unit Atlas.Common.Rules.Builtin.Registration2;

// Anmeldung der zweiten Gruppe eingebauter Prüfregeln für Atlas.Common.Rules.Builtin. Die Gruppen teilen
// die Anmeldung nur auf, damit keine Unit zu viele Units einbindet; die Reihenfolge bleibt erhalten.

interface

uses
  Atlas.Common.Rules.Registry;

/// <summary>Meldet die Regeln der zweiten Gruppe in ARegistry an.</summary>
procedure RegisterBuiltinRules2(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Builtin.ForwardDeclarations,
  Atlas.Common.Rules.Builtin.FreeFields,
  Atlas.Common.Rules.Builtin.TrivialAccessor,
  Atlas.Common.Rules.Builtin.Packages,
  Atlas.Common.Rules.Builtin.OpenTools,
  Atlas.Common.Rules.Builtin.Testing,
  Atlas.Common.Rules.Builtin.Events,
  Atlas.Common.Rules.Builtin.Ownership,
  Atlas.Common.Rules.Builtin.Ownership.RawMemory,
  Atlas.Common.Rules.Builtin.Ownership.StringListObjects,
  Atlas.Common.Rules.Builtin.Ownership.ComponentInterface,
  Atlas.Common.Rules.Builtin.Expressions,
  Atlas.Common.Rules.Builtin.Statements,
  Atlas.Common.Rules.Builtin.Database,
  Atlas.Common.Rules.Builtin.DllExports,
  Atlas.Common.Rules.Builtin.Files,
  Atlas.Common.Rules.Builtin.Directives,
  Atlas.Common.Rules.Builtin.Properties,
  Atlas.Common.Rules.Builtin.Calls,
  Atlas.Common.Rules.Builtin.Jumps,
  Atlas.Common.Rules.Builtin.Loops,
  Atlas.Common.Rules.Builtin.Generics,
  Atlas.Common.Rules.Builtin.TypeChecks,
  Atlas.Common.Rules.Builtin.TypeKinds,
  Atlas.Common.Rules.Builtin.TypeMismatch,
  Atlas.Common.Rules.Builtin.Constants,
  Atlas.Common.Rules.Builtin.Forms,
  Atlas.Common.Rules.Builtin.SharedState,
  Atlas.Common.Rules.Builtin.Conditions;

procedure RegisterBuiltinRules2(const ARegistry: TRuleRegistry);
begin
  RegisterForwardDeclarationRules(ARegistry);
  RegisterFreeFieldRules(ARegistry);
  RegisterTrivialAccessorRules(ARegistry);
  RegisterPackageRules(ARegistry);
  RegisterOpenToolsRules(ARegistry);
  RegisterTestingRules(ARegistry);
  RegisterEventRules(ARegistry);
  RegisterOwnershipRules(ARegistry);
  RegisterOwnershipRawMemoryRules(ARegistry);
  RegisterOwnershipStringListObjectsRules(ARegistry);
  RegisterOwnershipComponentInterfaceRules(ARegistry);
  RegisterExpressionRules(ARegistry);
  RegisterStatementRules(ARegistry);
  RegisterDatabaseRules(ARegistry);
  RegisterDllExportRules(ARegistry);
  RegisterFileRules(ARegistry);
  RegisterDirectiveRules(ARegistry);
  RegisterPropertyRules(ARegistry);
  RegisterCallRules(ARegistry);
  RegisterJumpRules(ARegistry);
  RegisterLoopRules(ARegistry);
  RegisterGenericRules(ARegistry);
  RegisterTypeCheckRules(ARegistry);
  RegisterTypeKindRules(ARegistry);
  RegisterTypeMismatchRules(ARegistry);
  RegisterConstantRules(ARegistry);
  RegisterFormRules(ARegistry);
  RegisterSharedStateRules(ARegistry);
  RegisterConditionRules(ARegistry);
end;

end.
