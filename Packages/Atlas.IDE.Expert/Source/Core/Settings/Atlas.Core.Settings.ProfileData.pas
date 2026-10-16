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
  Profile0: array[0..47] of string = (
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
    '    "notifications.enabled": true',
    '  }',
    '}');
  Profile1: array[0..10] of string = (
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
  Profile2: array[0..47] of string = (
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
    '    "notifications.enabled": false',
    '  }',
    '}');

function Joined(const ALines: array of string): string;
var
  Line: string;
begin
  Result := '';
  for Line in ALines do
    Result := Result + Line + #10;
end;

function AtlasProfileFiles: TArray<string>;
begin
  SetLength(Result, 3);
  Result[0] := 'alles-an.json';
  Result[1] := 'atlas-standard.json';
  Result[2] := 'minimal.json';
end;

function AtlasProfileJson(const AFileName: string): string;
begin
  Result := '';
  if SameText(AFileName, 'alles-an.json') then
    Result := Joined(Profile0);
  if SameText(AFileName, 'atlas-standard.json') then
    Result := Joined(Profile1);
  if SameText(AFileName, 'minimal.json') then
    Result := Joined(Profile2);
end;

end.
