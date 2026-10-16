unit Atlas.Common.Configuration.Internals.ScopeData;

// Erzeugt von Tools/Update-ConfigDoc.ps1 aus schemas/atlas.schema.json (x-scope);
// nicht von Hand ändern. Ort jedes Schlüssels: global = %APPDATA%\Atlas\settings.json,
// Projekt = atlas.json. Gemischte Objekte stehen je Glied als "objekt.glied" da.

interface

const
  /// <summary>Schlüssel für alle Projekte (settings.json).</summary>
  GlobalSettingPaths: array[0..24] of string = (
    'delphiVersion',
    'language',
    'compiler',
    'vcs',
    'completion.matching',
    'completion.offerTryFinally',
    'completion.keywords',
    'completion.postfixTemplates',
    'usesCommand',
    'slashCommands',
    'memoryBudgetMb',
    'index.projectGroup',
    'index.searchPaths',
    'index.libraryPaths',
    'index.usages',
    'requestTimeoutMs',
    'diagnostics',
    'highlight',
    'inlayHints',
    'codeLens',
    'hints',
    'mcp.disabledTools',
    'logLevel',
    'logFile',
    'traceFile');
  /// <summary>Schlüssel des Projekts (atlas.json).</summary>
  ProjectSettingPaths: array[0..24] of string = (
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
    'refactoring',
    'sortUses',
    'usesKeep',
    'dfmPropertyRules',
    'index.exclude',
    'stringLiteral',
    'memberOrder',
    'testUnits',
    'minConfidence',
    'exclude',
    'mcp.globalSettings',
    'format');

implementation

end.
