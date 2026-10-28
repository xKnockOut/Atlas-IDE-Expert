unit Atlas.Common.Configuration.Internals.ScopeData;

// Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json (x-scope);
// nicht von Hand ändern. Ort jedes Schlüssels: global = %APPDATA%\Atlas\settings.json,
// Projekt = atlas.json. Gemischte Objekte stehen je Glied als "objekt.glied" da.
// Schlüssel mit x-scope "both" stehen in beiden Listen.

interface

const
  /// <summary>Schlüssel für alle Projekte (settings.json).</summary>
  GlobalSettingPaths: array[0..57] of string = (
    'delphiVersion',
    'language',
    'rules',
    'compiler',
    'vcs',
    'completion.matching',
    'completion.offerTryFinally',
    'completion.keywords',
    'completion.postfixTemplates',
    'completion.genericConstraints',
    'completion.resourceStrings',
    'completion.typeConversion',
    'completion.assignAllFields',
    'completion.usesDetails',
    'completion.inheritedCall',
    'completion.attributes',
    'completion.anonymousMethods',
    'completion.withOrigin',
    'completion.exceptionClasses',
    'completion.syntaxNotice',
    'completion.sameNameVariants',
    'completion.sameNameInsert',
    'completion.showFmxUnits',
    'completion.nameSuggestions',
    'usesCommand',
    'completeBlocks',
    'metrics',
    'experimental',
    'slashCommands',
    'memoryBudgetMb',
    'index.projectGroup',
    'index.searchPaths',
    'index.libraryPaths',
    'index.usages',
    'index.removeOrphans',
    'index.cacheMaxAgeDays',
    'index.cacheMaxMb',
    'architecture.enabled',
    'architecture.scope',
    'architecture.includeLibraryUnits',
    'architecture.centralUnits',
    'requestTimeoutMs',
    'diagnostics.log',
    'diagnostics.logDays',
    'diagnostics.logMapFile',
    'highlight',
    'inlayHints',
    'codeLens',
    'references',
    'navigation',
    'hints',
    'directives',
    'mcp.disabledTools',
    'tasks',
    'issues',
    'logLevel',
    'logFile',
    'traceFile');
  /// <summary>Schlüssel des Projekts (atlas.json).</summary>
  ProjectSettingPaths: array[0..35] of string = (
    'minDelphiVersion',
    'encoding',
    'project',
    'config',
    'platform',
    'rules',
    'profile',
    'profiles',
    'overrides',
    'excludeTests',
    'testProfile',
    'completion.interfaceSection',
    'completion.senderCast',
    'completion.freeStyle',
    'completion.createAccessors',
    'completion.accessorSection',
    'completion.resourceStringUnit',
    'refactoring',
    'sortUses',
    'usesKeep',
    'deadCode',
    'dfmPropertyRules',
    'index.exclude',
    'architecture.exclude',
    'architecture.baseline',
    'architecture.failOn',
    'diagnostics.usesCycleLive',
    'diagnostics.usesCycleImplementation',
    'stringLiteral',
    'memberOrder',
    'testUnits',
    'minConfidence',
    'exclude',
    'mcp.globalSettings',
    'format',
    'tasks');

/// <summary>Experimentelle Schlüssel (x-experimental, #834): wirken nur mit experimental.enabled.</summary>
function ExperimentalSettingPaths: TArray<string>;

implementation

function ExperimentalSettingPaths: TArray<string>;
begin
  Result := ['completion.typeConversion', 'completion.assignAllFields', 'refactoring.inline', 'refactoring.moveClass', 'refactoring.unitRenameFollowUp'];
end;

end.
