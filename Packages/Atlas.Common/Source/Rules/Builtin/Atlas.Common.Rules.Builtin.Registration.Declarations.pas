unit Atlas.Common.Rules.Builtin.Registration.Declarations;

// Anmeldung der eingebauten Prüfregeln für Deklarationen und Aufbau (Deklarationen, Typen, Vererbung,
// Sichtbarkeit, Units, Direktiven, Stil, Metriken, Benennung, Dokumentation). Atlas.Common.Rules.Builtin ruft die
// drei Registration-Units nacheinander auf; nach Themen aufgeteilt, damit keine Unit zu viele Units einbindet
// (metric-uses-count).

interface

uses
  Atlas.Common.Rules.Registry;

/// <summary>Meldet die Regeln für Deklarationen und Aufbau in ARegistry an.</summary>
procedure RegisterBuiltinDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Builtin.Architecture,
  Atlas.Common.Rules.Builtin.Unused,
  Atlas.Common.Rules.Builtin.Declarations,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.General,
  Atlas.Common.Rules.Builtin.Style,
  Atlas.Common.Rules.Builtin.Unresolved,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Rules.Builtin.Todos,
  Atlas.Common.Rules.Builtin.DebugDisplay,
  Atlas.Common.Rules.Builtin.Deprecated,
  Atlas.Common.Rules.Builtin.ForwardDeclarations,
  Atlas.Common.Rules.Builtin.TrivialAccessor,
  Atlas.Common.Rules.Builtin.Directives,
  Atlas.Common.Rules.Builtin.Properties,
  Atlas.Common.Rules.Builtin.Generics,
  Atlas.Common.Rules.Builtin.Constants,
  Atlas.Common.Rules.Builtin.MethodDirectives,
  Atlas.Common.Rules.Builtin.InvalidDeclarations,
  Atlas.Common.Rules.Builtin.Published,
  Atlas.Common.Rules.Builtin.Visibility,
  Atlas.Common.Rules.Builtin.TypeDeclarations,
  Atlas.Common.Rules.Builtin.Units,
  Atlas.Common.Rules.Builtin.PublicMembers,
  Atlas.Common.Rules.Builtin.DeadCode,
  Atlas.Common.Rules.Builtin.XmlDoc,
  Atlas.Common.Rules.Builtin.Naming,
  Atlas.Common.Rules.Builtin.MethodWithoutSelf;

procedure RegisterBuiltinDeclarationRules(const ARegistry: TRuleRegistry);
begin
  RegisterArchitectureRules(ARegistry);
  RegisterUnusedRules(ARegistry);
  RegisterDeclarationRules(ARegistry);
  RegisterInheritanceRules(ARegistry);
  RegisterGeneralRules(ARegistry);
  RegisterStyleRules(ARegistry);
  RegisterUnresolvedRules(ARegistry);
  RegisterMetricRules(ARegistry);
  RegisterTodoRules(ARegistry);
  RegisterDebugDisplayRules(ARegistry);
  RegisterDeprecatedRules(ARegistry);
  RegisterForwardDeclarationRules(ARegistry);
  RegisterTrivialAccessorRules(ARegistry);
  RegisterDirectiveRules(ARegistry);
  RegisterPropertyRules(ARegistry);
  RegisterGenericRules(ARegistry);
  RegisterConstantRules(ARegistry);
  RegisterMethodDirectiveRules(ARegistry);
  RegisterInvalidDeclarationRules(ARegistry);
  RegisterPublishedRules(ARegistry);
  RegisterVisibilityRules(ARegistry);
  RegisterTypeDeclarationRules(ARegistry);
  RegisterUnitRules(ARegistry);
  RegisterPublicMemberRules(ARegistry);
  RegisterDeadCodeRules(ARegistry);
  RegisterXmlDocRules(ARegistry);
  RegisterNamingRules(ARegistry);
  RegisterMethodWithoutSelfRules(ARegistry);
end;

end.
