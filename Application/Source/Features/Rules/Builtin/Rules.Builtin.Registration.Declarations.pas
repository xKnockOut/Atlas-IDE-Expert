unit Rules.Builtin.Registration.Declarations;

// Anmeldung der eingebauten Prüfregeln für Deklarationen und Aufbau (Deklarationen, Typen, Vererbung,
// Sichtbarkeit, Units, Direktiven, Stil, Metriken, Benennung, Dokumentation). Rules.Builtin ruft die
// drei Registration-Units nacheinander auf; nach Themen aufgeteilt, damit keine Unit zu viele Units einbindet
// (metric-uses-count).

interface

uses
  Rules.Registry;

/// <summary>Meldet die Regeln für Deklarationen und Aufbau in ARegistry an.</summary>
procedure RegisterBuiltinDeclarationRules(const ARegistry: TRuleRegistry);

implementation

uses
  Rules.Builtin.Architecture,
  Rules.Builtin.Unused,
  Rules.Builtin.Declarations,
  Rules.Builtin.Inheritance,
  Rules.Builtin.General,
  Rules.Builtin.Style,
  Rules.Builtin.Unresolved,
  Rules.Builtin.Metrics,
  Rules.Builtin.Todos,
  Rules.Builtin.DebugDisplay,
  Rules.Builtin.Deprecated,
  Rules.Builtin.ForwardDeclarations,
  Rules.Builtin.TrivialAccessor,
  Rules.Builtin.Directives,
  Rules.Builtin.Properties,
  Rules.Builtin.Generics,
  Rules.Builtin.Constants,
  Rules.Builtin.MethodDirectives,
  Rules.Builtin.InvalidDeclarations,
  Rules.Builtin.Published,
  Rules.Builtin.Visibility,
  Rules.Builtin.TypeDeclarations,
  Rules.Builtin.Units,
  Rules.Builtin.PublicMembers,
  Rules.Builtin.DuplicateBodies,
  Rules.Builtin.DeadCode,
  Rules.Builtin.XmlDoc,
  Rules.Builtin.Naming,
  Rules.Builtin.MethodWithoutSelf;

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
  RegisterDuplicateBodyRules(ARegistry);
  RegisterDeadCodeRules(ARegistry);
  RegisterXmlDocRules(ARegistry);
  RegisterNamingRules(ARegistry);
  RegisterMethodWithoutSelfRules(ARegistry);
end;

end.
