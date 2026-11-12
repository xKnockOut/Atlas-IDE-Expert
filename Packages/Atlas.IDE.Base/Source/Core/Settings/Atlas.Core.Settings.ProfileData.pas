unit Atlas.Core.Settings.ProfileData;

// Erzeugt von Tools/Update-ConfigDoc.ps1 aus Setup/Profile/*.json;
// nicht von Hand ändern. Eingebaute Profile für den Import der Einstellungen (#723).

interface

/// <summary>Dateinamen der eingebauten Profile (wie in Setup\Profile).</summary>
function AtlasProfileFiles: TArray<string>;
/// <summary>Inhalt eines eingebauten Profils; leer, wenn der Name unbekannt ist.</summary>
function AtlasProfileJson(const AFileName: string): string;

implementation

uses
  System.SysUtils;

const
  cProfile0: array[0..72] of string = (
    '{',
    '  "format": "atlas-settings",',
    '  "formatVersion": 1,',
    '  "schemaVersion": 1,',
    '  "name": "Alles an, auch experimentell",',
    '  "nameEn": "Everything on, including experimental",',
    '  "description": "Wie „Alles an“, dazu der Hauptschalter experimental.enabled und alle experimentellen Funktionen (#834). Andere Werte bleiben (Zusammenführen).",',
    '  "descriptionEn": "Like “Everything on”, plus the master switch experimental.enabled and every experimental feature (#834). Other values stay (merge).",',
    '  "mode": "merge",',
    '  "settings": {',
    '    "completion.enabled": true,',
    '    "highlight.pairColors": true,',
    '    "highlight.pairGuides": true,',
    '    "highlight.pairOwners": true,',
    '    "highlight.inactiveDim": true,',
    '    "problems.enabled": true,',
    '    "inlayHints.parameterNames": true,',
    '    "notes.enabled": true,',
    '    "bookmarks.named": true,',
    '    "codeLens.metrics": true,',
    '    "codeLens.tests": true,',
    '    "keys.generateMenu": true,',
    '    "todos.list": true,',
    '    "baseline.update": true,',
    '    "metrics.report": true,',
    '    "dfmRules.apply": true,',
    '    "editor.hoverTooltip": true,',
    '    "completion.filterChips": true,',
    '    "completion.preview": true,',
    '    "completion.groupInherited": true,',
    '    "completion.learning": true,',
    '    "completion.favorites": true,',
    '    "build.checkOnSave": true,',
    '    "compiler.mcpBuild": true,',
    '    "build.onOpen": true,',
    '    "startProfiles.enabled": true,',
    '    "startProfiles.statusField": true,',
    '    "tests.run": true,',
    '    "tests.afterBuild": true,',
    '    "tests.debug": true,',
    '    "build.releaseGuard": true,',
    '    "welcomePage.enabled": true,',
    '    "welcomePage.projectSetup": true,',
    '    "welcomePage.tests.ci.login": true,',
    '    "welcomePage.quickActions": true,',
    '    "shortcutTips.enabled": true,',
    '    "notifications.enabled": true,',
    '    "experimental.enabled": true,',
    '    "editor.multiCursor": true,',
    '    "editor.linkedEditing": true,',
    '    "editor.stickyScroll": true,',
    '    "editor.smartPaste": "both",',
    '    "completion.typeConversion": "helper",',
    '    "completion.assignAllFields": true,',
    '    "editor.minimap": true,',
    '    "editor.designerBar.tabOrderClick": true,',
    '    "editor.designerBar.align": true,',
    '    "designer.undo": true,',
    '    "debug.enabled": true,',
    '    "issues.enabled": true,',
    '    "analysis.enabled": true,',
    '    "tests.enabled": true,',
    '    "buildTools.enabled": true,',
    '    "buildPipeline.enabled": true,',
    '    "bookmarks.enabled": true,',
    '    "vcs.enabled": true,',
    '    "assistants.enabled": true,',
    '    "designer.enabled": true,',
    '    "help.enabled": true,',
    '    "ruleChecks.enabled": true,',
    '    "search.enabled": true',
    '  }',
    '}');
  cProfile1: array[0..61] of string = (
    '{',
    '  "format": "atlas-settings",',
    '  "formatVersion": 1,',
    '  "schemaVersion": 1,',
    '  "name": "Alles an",',
    '  "nameEn": "Everything on",',
    '  "description": "Alle Funktionen mit Schnellschalter an (außer dem Diagnosemodus). Andere Werte bleiben (Zusammenführen).",',
    '  "descriptionEn": "Every feature with a quick toggle on (except the diagnostic mode). Other values stay (merge).",',
    '  "mode": "merge",',
    '  "settings": {',
    '    "completion.enabled": true,',
    '    "highlight.pairColors": true,',
    '    "highlight.pairGuides": true,',
    '    "highlight.pairOwners": true,',
    '    "highlight.inactiveDim": true,',
    '    "problems.enabled": true,',
    '    "inlayHints.parameterNames": true,',
    '    "notes.enabled": true,',
    '    "bookmarks.named": true,',
    '    "codeLens.metrics": true,',
    '    "codeLens.tests": true,',
    '    "keys.generateMenu": true,',
    '    "todos.list": true,',
    '    "baseline.update": true,',
    '    "metrics.report": true,',
    '    "dfmRules.apply": true,',
    '    "editor.hoverTooltip": true,',
    '    "completion.filterChips": true,',
    '    "completion.preview": true,',
    '    "completion.groupInherited": true,',
    '    "completion.learning": true,',
    '    "completion.favorites": true,',
    '    "build.checkOnSave": true,',
    '    "compiler.mcpBuild": true,',
    '    "build.onOpen": true,',
    '    "startProfiles.enabled": true,',
    '    "startProfiles.statusField": true,',
    '    "tests.run": true,',
    '    "tests.afterBuild": true,',
    '    "tests.debug": true,',
    '    "build.releaseGuard": true,',
    '    "welcomePage.enabled": true,',
    '    "welcomePage.projectSetup": true,',
    '    "welcomePage.tests.ci.login": true,',
    '    "welcomePage.quickActions": true,',
    '    "shortcutTips.enabled": true,',
    '    "notifications.enabled": true,',
    '    "debug.enabled": true,',
    '    "issues.enabled": true,',
    '    "analysis.enabled": true,',
    '    "tests.enabled": true,',
    '    "buildTools.enabled": true,',
    '    "buildPipeline.enabled": true,',
    '    "bookmarks.enabled": true,',
    '    "vcs.enabled": true,',
    '    "assistants.enabled": true,',
    '    "designer.enabled": true,',
    '    "help.enabled": true,',
    '    "ruleChecks.enabled": true,',
    '    "search.enabled": true',
    '  }',
    '}');
  cProfile2: array[0..10] of string = (
    '{',
    '  "format": "atlas-settings",',
    '  "formatVersion": 1,',
    '  "schemaVersion": 1,',
    '  "name": "Atlas-Standard",',
    '  "nameEn": "Atlas default",',
    '  "description": "Alle Bereiche auf die Standardwerte von Atlas (Ersetzen). Projekt- und Teamwerte bleiben unberührt.",',
    '  "descriptionEn": "Resets all areas to the Atlas defaults (replace). Project and team values stay untouched.",',
    '  "mode": "replace",',
    '  "settings": {}',
    '}');
  cProfile3: array[0..61] of string = (
    '{',
    '  "format": "atlas-settings",',
    '  "formatVersion": 1,',
    '  "schemaVersion": 1,',
    '  "name": "Minimal",',
    '  "nameEn": "Minimal",',
    '  "description": "Nur die Vervollständigung; alle Zusatzfunktionen mit Schnellschalter aus. Andere Werte bleiben (Zusammenführen).",',
    '  "descriptionEn": "Completion only; every add-on feature with a quick toggle off. Other values stay (merge).",',
    '  "mode": "merge",',
    '  "settings": {',
    '    "diagnosticMode.enabled": false,',
    '    "highlight.pairColors": false,',
    '    "highlight.pairGuides": false,',
    '    "highlight.pairOwners": false,',
    '    "highlight.inactiveDim": false,',
    '    "problems.enabled": false,',
    '    "inlayHints.parameterNames": false,',
    '    "notes.enabled": false,',
    '    "bookmarks.named": false,',
    '    "codeLens.metrics": false,',
    '    "codeLens.tests": false,',
    '    "keys.generateMenu": false,',
    '    "todos.list": false,',
    '    "baseline.update": false,',
    '    "metrics.report": false,',
    '    "dfmRules.apply": false,',
    '    "editor.hoverTooltip": false,',
    '    "completion.filterChips": false,',
    '    "completion.preview": false,',
    '    "completion.groupInherited": false,',
    '    "completion.learning": false,',
    '    "completion.favorites": false,',
    '    "build.checkOnSave": false,',
    '    "compiler.mcpBuild": false,',
    '    "build.onOpen": false,',
    '    "startProfiles.enabled": false,',
    '    "startProfiles.statusField": false,',
    '    "tests.run": false,',
    '    "tests.afterBuild": false,',
    '    "tests.debug": false,',
    '    "build.releaseGuard": false,',
    '    "welcomePage.enabled": false,',
    '    "welcomePage.projectSetup": false,',
    '    "welcomePage.tests.ci.login": false,',
    '    "welcomePage.quickActions": false,',
    '    "shortcutTips.enabled": false,',
    '    "notifications.enabled": false,',
    '    "debug.enabled": false,',
    '    "issues.enabled": false,',
    '    "analysis.enabled": false,',
    '    "tests.enabled": false,',
    '    "buildTools.enabled": false,',
    '    "buildPipeline.enabled": false,',
    '    "bookmarks.enabled": false,',
    '    "vcs.enabled": false,',
    '    "assistants.enabled": false,',
    '    "designer.enabled": false,',
    '    "help.enabled": false,',
    '    "ruleChecks.enabled": false,',
    '    "search.enabled": false',
    '  }',
    '}');
  cProfile4: array[0..25] of string = (
    '{',
    '  "format": "atlas-settings",',
    '  "formatVersion": 1,',
    '  "schemaVersion": 1,',
    '  "name": "Nur Code Insight",',
    '  "nameEn": "Code Insight only",',
    '  "description": "Alle Module aus (Debugger, Issue-Tracker, Analyse, Tests, Build-Werkzeuge, Lesezeichen, Designer, Hilfe, Prüfregeln, Suche, Willkommensseite, #1454); der Kern mit Vervollständigung, ' +
      'Hover, Diagnosen und Editor wie „Atlas-Standard“ (Ersetzen). Projekt- und Teamwerte bleiben unberührt.",',
    '  "descriptionEn": "All modules off (debugger, issue tracker, analysis, tests, build tools, bookmarks, designer, rule checks, search, welcome page, #1454); the core with completion, hover, diagnostics' +
      ' and editor as in “Atlas default” (replace). Project and team values stay untouched.",',
    '  "mode": "replace",',
    '  "settings": {',
    '    "debug.enabled": false,',
    '    "issues.enabled": false,',
    '    "analysis.enabled": false,',
    '    "tests.enabled": false,',
    '    "buildTools.enabled": false,',
    '    "buildPipeline.enabled": false,',
    '    "bookmarks.enabled": false,',
    '    "vcs.enabled": false,',
    '    "assistants.enabled": false,',
    '    "designer.enabled": false,',
    '    "help.enabled": false,',
    '    "ruleChecks.enabled": false,',
    '    "search.enabled": false,',
    '    "welcomePage.enabled": false',
    '  }',
    '}');

function Joined(const ALines: array of string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
  begin
    Result := Result + mLine + #10;
  end;
end;

function AtlasProfileFiles: TArray<string>;
begin
  SetLength(Result, 5);
  Result[0] := 'alles-an-experimentell.json';
  Result[1] := 'alles-an.json';
  Result[2] := 'atlas-standard.json';
  Result[3] := 'minimal.json';
  Result[4] := 'nur-code-insight.json';
end;

function AtlasProfileJson(const AFileName: string): string;
begin
  Result := '';
  if SameText(AFileName, 'alles-an-experimentell.json') then
  begin
    Result := Joined(cProfile0);
  end;
  if SameText(AFileName, 'alles-an.json') then
  begin
    Result := Joined(cProfile1);
  end;
  if SameText(AFileName, 'atlas-standard.json') then
  begin
    Result := Joined(cProfile2);
  end;
  if SameText(AFileName, 'minimal.json') then
  begin
    Result := Joined(cProfile3);
  end;
  if SameText(AFileName, 'nur-code-insight.json') then
  begin
    Result := Joined(cProfile4);
  end;
end;

end.
