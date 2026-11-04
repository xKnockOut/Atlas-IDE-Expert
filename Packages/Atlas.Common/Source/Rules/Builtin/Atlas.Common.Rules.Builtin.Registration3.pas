unit Atlas.Common.Rules.Builtin.Registration3;

// Anmeldung der dritten Gruppe eingebauter Prüfregeln für Atlas.Common.Rules.Builtin. Die Gruppen teilen
// die Anmeldung nur auf, damit keine Unit zu viele Units einbindet; die Reihenfolge bleibt erhalten.

interface

uses
  Atlas.Common.Rules.Registry;

/// <summary>Meldet die Regeln der dritten Gruppe in ARegistry an.</summary>
procedure RegisterBuiltinRules3(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Builtin.Platform,
  Atlas.Common.Rules.Builtin.Idioms,
  Atlas.Common.Rules.Builtin.Inlining,
  Atlas.Common.Rules.Builtin.CompilerHints,
  Atlas.Common.Rules.Builtin.MethodDirectives,
  Atlas.Common.Rules.Builtin.InvalidDeclarations,
  Atlas.Common.Rules.Builtin.Published,
  Atlas.Common.Rules.Builtin.Collections,
  Atlas.Common.Rules.Builtin.Visibility,
  Atlas.Common.Rules.Builtin.TypeDeclarations,
  Atlas.Common.Rules.Builtin.Automation,
  Atlas.Common.Rules.Builtin.TypedExpressions,
  Atlas.Common.Rules.Builtin.StringConversions,
  Atlas.Common.Rules.Builtin.TypeRestrictions,
  Atlas.Common.Rules.Builtin.Units,
  Atlas.Common.Rules.Builtin.PublicMembers,
  Atlas.Common.Rules.Builtin.DeadCode,
  Atlas.Common.Rules.Builtin.XmlDoc,
  Atlas.Common.Rules.Builtin.Naming,
  Atlas.Common.Rules.Builtin.Casts,
  Atlas.Common.Rules.Builtin.UnsafeCode,
  Atlas.Common.Rules.Builtin.StringAddress,
  Atlas.Common.Rules.Builtin.FormatArgs,
  Atlas.Common.Rules.Builtin.ForbiddenSymbols,
  Atlas.Common.Rules.Builtin.MethodWithoutSelf,
  Atlas.Common.Rules.Builtin.Assembler;

procedure RegisterBuiltinRules3(const ARegistry: TRuleRegistry);
begin
  RegisterPlatformRules(ARegistry);
  RegisterIdiomRules(ARegistry);
  RegisterInliningRules(ARegistry);
  RegisterCompilerHintRules(ARegistry);
  RegisterMethodDirectiveRules(ARegistry);
  RegisterInvalidDeclarationRules(ARegistry);
  RegisterPublishedRules(ARegistry);
  RegisterCollectionRules(ARegistry);
  RegisterVisibilityRules(ARegistry);
  RegisterTypeDeclarationRules(ARegistry);
  RegisterAutomationRules(ARegistry);
  RegisterTypedExpressionRules(ARegistry);
  RegisterStringConversionRules(ARegistry);
  RegisterTypeRestrictionRules(ARegistry);
  RegisterUnitRules(ARegistry);
  RegisterPublicMemberRules(ARegistry);
  RegisterDeadCodeRules(ARegistry);
  RegisterXmlDocRules(ARegistry);
  RegisterNamingRules(ARegistry);
  RegisterCastRules(ARegistry);
  RegisterUnsafeCodeRules(ARegistry);
  RegisterStringAddressRules(ARegistry);
  RegisterFormatArgsRules(ARegistry);
  RegisterForbiddenSymbolRules(ARegistry);
  RegisterMethodWithoutSelfRules(ARegistry);
  RegisterAssemblerRules(ARegistry);
end;

end.
