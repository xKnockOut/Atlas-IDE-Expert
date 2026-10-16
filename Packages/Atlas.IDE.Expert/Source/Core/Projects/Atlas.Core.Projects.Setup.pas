unit Atlas.Core.Projects.Setup;

// Einrichtung eines Projekts für Atlas (#759), ohne VCL und Open Tools API:
// Vorlagen für atlas.json, wohin die Datei kommt und welche Schritte offen
// sind. Anders als die Einrichtungs-Prüfliste (#625, Atlas.Core.Setup.Checklist)
// gilt sie je Projekt.
//
// Schritte (Karte auf der Willkommensseite):
//   1. Projekt gefunden – erledigt, sobald es ein Projekt gibt.
//   2. atlas.json anlegen – erledigt, wenn neben der Projektdatei (.dproj bzw.
//      .groupproj) eine atlas.json (oder die frühere delphi-lsp.json) liegt.
//   3. Baseline erzeugen (#97) – erledigt, wenn im Projektordner eine Baseline
//      liegt (atlas-baseline.json oder der frühere Name).
//   4. Suchpfade und Defines prüfen – erledigt, wenn die letzte Prüfung
//      (Abschnitt "setup.paths" der Projekt-Zusammenfassung) nichts fand.
// Vollständig eingerichtet ist ein Projekt, wenn alle Schritte erledigt sind;
// „Für dieses Projekt nicht mehr fragen“ ("setup.dismissed") blendet die
// Karte ebenfalls aus.
//
// Vorlagen: Setup\Vorlagen\atlas-<kennung>.json liegen der Installation bei
// (Ordner Vorlagen neben der BPL oder eine Ebene darüber, wie die Doku #766);
// fehlt eine Datei, gilt die eingebaute Fassung (gleicher Inhalt, die Tests
// vergleichen beide). Vor dem Schreiben prüft TAtlasSchemaCheck den Inhalt
// gegen atlas.schema.json (nur Schlüssel des Projekts).

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary;

type
{$SCOPEDENUMS ON}
  /// <summary>Vorlagen in der Reihenfolge der Auswahlliste; Existing ist die Vorgabe.</summary>
  TAtlasSetupTemplate = (Existing, NewStrict, Legacy);
  TAtlasSetupStep = (Found, Config, Baseline, Paths);
{$SCOPEDENUMS OFF}

  TAtlasSetupFileExists = reference to function(const AFileName: string): Boolean;
  TAtlasSetupReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Was die Schritte brauchen: Dateien neben dem Projekt und der Abschnitt "setup".</summary>
  TAtlasSetupFacts = record
    /// <summary>Projektdatei (.dproj, .groupproj); '' = kein Projekt.</summary>
    Project: string;
    /// <summary>atlas.json oder delphi-lsp.json liegt neben der Projektdatei.</summary>
    ConfigExists: Boolean;
    /// <summary>Baseline liegt im Projektordner.</summary>
    BaselineExists: Boolean;
    Setup: TAtlasProjectSetup;
  end;

  TAtlasProjectSetups = class
  public const
    ConfigName = 'atlas.json';
    LegacyConfigName = 'delphi-lsp.json';
    /// <summary>Ordner der Vorlagen in der Installation (Setup.Core.Installer.TemplatesFolder).</summary>
    TemplatesFolder = 'Vorlagen';
    /// <summary>$schema der Vorlagen, wie in docs/Konfiguration.md.</summary>
    SchemaUrl = 'https://raw.githubusercontent.com/xKnockOut/Atlas/main/schemas/atlas.schema.json';
  public
    /// <summary>"existing", "strict", "legacy".</summary>
    class function TemplateId(ATemplate: TAtlasSetupTemplate): string; static;
    /// <summary>Umkehrung von TemplateId (Groß-/Kleinschreibung egal); False bei unbekannter Kennung.</summary>
    class function TemplateOf(const AId: string; out ATemplate: TAtlasSetupTemplate): Boolean; static;
    /// <summary>"atlas-existing.json" usw.</summary>
    class function TemplateFile(ATemplate: TAtlasSetupTemplate): string; static;
    /// <summary>Eingebaute Fassung der Vorlage (Zeilen mit #10), gleich der Datei in Setup\Vorlagen.</summary>
    class function BuiltIn(ATemplate: TAtlasSetupTemplate): string; static;
    /// <summary>Ordner Vorlagen in APluginDir oder eine Ebene darüber, wenn die Vorlage der Vorgabe dort liegt;
    /// '' ohne.</summary>
    class function TemplateFolder(const APluginDir: string; const AExists: TAtlasSetupFileExists): string; static;
    /// <summary>Text der Vorlage aus AFolder, sonst die eingebaute Fassung.</summary>
    class function TemplateText(ATemplate: TAtlasSetupTemplate; const AFolder: string;
      const ARead: TAtlasSetupReadText): string; static;
    /// <summary>Ziel der neuen Datei: atlas.json im Ordner der Projektdatei; '' ohne Projekt.</summary>
    class function ConfigTarget(const AProject: string): string; static;
    /// <summary>Vorhandene Konfiguration neben AProject (atlas.json vor delphi-lsp.json); '' ohne.</summary>
    class function ExistingConfig(const AProject: string; const AExists: TAtlasSetupFileExists): string; static;
    /// <summary>Prüft ATemplateText gegen ASchemaJson (Ort "project"); AIssues wie TAtlasSchemaCheck.</summary>
    class function ValidTemplate(const ATemplateText, ASchemaJson: string; out AIssues: TArray<string>): Boolean;
      static;
    /// <summary>Ist der Schritt erledigt?</summary>
    class function StepDone(AStep: TAtlasSetupStep; const AFacts: TAtlasSetupFacts): Boolean; static;
    /// <summary>Alle Schritte erledigt.</summary>
    class function Complete(const AFacts: TAtlasSetupFacts): Boolean; static;
    /// <summary>Offene Schritte in ihrer Reihenfolge.</summary>
    class function OpenSteps(const AFacts: TAtlasSetupFacts): TArray<TAtlasSetupStep>; static;
    /// <summary>Karte zeigen: mit Projekt, nicht abgewählt und nicht vollständig eingerichtet.</summary>
    class function NeedsCard(const AFacts: TAtlasSetupFacts): Boolean; static;
  end;

implementation

uses
  Atlas.Core.Settings.SchemaCheck;

const
  TemplateIds: array[TAtlasSetupTemplate] of string = ('existing', 'strict', 'legacy');

  // Gleich Setup\Vorlagen\atlas-*.json (Atlas.Core.Projects.Setup.Tests vergleicht beide).
  ExistingText =
    '{' + #10 +
    '  "$schema": "' + TAtlasProjectSetups.SchemaUrl + '",' + #10 +
    '  "profile": "standard",' + #10 +
    '  "minConfidence": "medium",' + #10 +
    '  "testProfile": "fast",' + #10 +
    '  "exclude": ["ThirdParty/**", "__history/**", "__recovery/**"]' + #10 +
    '}' + #10;
  StrictText =
    '{' + #10 +
    '  "$schema": "' + TAtlasProjectSetups.SchemaUrl + '",' + #10 +
    '  "profile": "strict",' + #10 +
    '  "minConfidence": "low",' + #10 +
    '  "testProfile": "standard",' + #10 +
    '  "exclude": ["__history/**", "__recovery/**"]' + #10 +
    '}' + #10;
  LegacyText =
    '{' + #10 +
    '  "$schema": "' + TAtlasProjectSetups.SchemaUrl + '",' + #10 +
    '  "profile": "standard",' + #10 +
    '  "minConfidence": "high",' + #10 +
    '  "excludeTests": true,' + #10 +
    '  "exclude": ["ThirdParty/**", "__history/**", "__recovery/**"],' + #10 +
    '  "overrides": [' + #10 +
    '    { "files": ["Generated/**"], "rules": { "*": "off" } }' + #10 +
    '  ]' + #10 +
    '}' + #10;

function FolderOf(const AFileName: string): string;
var
  Index: Integer;
begin
  // Ohne ExtractFileDir: Pfade haben immer „\“, auch wenn die Tests nicht unter Windows laufen.
  Result := '';
  for Index := Length(AFileName) downto 1 do
    if CharInSet(AFileName[Index], ['\', '/']) then
      Exit(Copy(AFileName, 1, Index - 1));
end;

function Joined(const AFolder, AName: string): string;
begin
  if (AFolder = '') or CharInSet(AFolder[Length(AFolder)], ['\', '/']) then
    Result := AFolder + AName
  else
    Result := AFolder + '\' + AName;
end;

{ TAtlasProjectSetups }

class function TAtlasProjectSetups.TemplateId(ATemplate: TAtlasSetupTemplate): string;
begin
  Result := TemplateIds[ATemplate];
end;

class function TAtlasProjectSetups.TemplateOf(const AId: string; out ATemplate: TAtlasSetupTemplate): Boolean;
var
  Each: TAtlasSetupTemplate;
begin
  ATemplate := TAtlasSetupTemplate.Existing;
  for Each := Low(TAtlasSetupTemplate) to High(TAtlasSetupTemplate) do
    if SameText(Trim(AId), TemplateIds[Each]) then
    begin
      ATemplate := Each;
      Exit(True);
    end;
  Result := False;
end;

class function TAtlasProjectSetups.TemplateFile(ATemplate: TAtlasSetupTemplate): string;
begin
  Result := 'atlas-' + TemplateIds[ATemplate] + '.json';
end;

class function TAtlasProjectSetups.BuiltIn(ATemplate: TAtlasSetupTemplate): string;
begin
  case ATemplate of
    TAtlasSetupTemplate.NewStrict:
      Result := StrictText;
    TAtlasSetupTemplate.Legacy:
      Result := LegacyText;
  else
    Result := ExistingText;
  end;
end;

class function TAtlasProjectSetups.TemplateFolder(const APluginDir: string;
  const AExists: TAtlasSetupFileExists): string;
var
  Folder, Parent, Candidate: string;
begin
  Result := '';
  if (Trim(APluginDir) = '') or not Assigned(AExists) then
    Exit;
  Folder := APluginDir;
  while (Folder <> '') and CharInSet(Folder[Length(Folder)], ['\', '/']) do
    Delete(Folder, Length(Folder), 1);
  Candidate := Joined(Folder, TemplatesFolder);
  if AExists(Joined(Candidate, TemplateFile(TAtlasSetupTemplate.Existing))) then
    Exit(Candidate);
  // BPL in Win32\ bzw. Win64\: Vorlagen eine Ebene darüber.
  Parent := FolderOf(Folder);
  if Parent = '' then
    Exit;
  Candidate := Joined(Parent, TemplatesFolder);
  if AExists(Joined(Candidate, TemplateFile(TAtlasSetupTemplate.Existing))) then
    Result := Candidate;
end;

class function TAtlasProjectSetups.TemplateText(ATemplate: TAtlasSetupTemplate; const AFolder: string;
  const ARead: TAtlasSetupReadText): string;
var
  Text: string;
begin
  Result := BuiltIn(ATemplate);
  if (AFolder = '') or not Assigned(ARead) then
    Exit;
  if ARead(Joined(AFolder, TemplateFile(ATemplate)), Text) and (Trim(Text) <> '') then
    Result := Text;
end;

class function TAtlasProjectSetups.ConfigTarget(const AProject: string): string;
begin
  Result := '';
  if Trim(AProject) = '' then
    Exit;
  Result := Joined(FolderOf(Trim(AProject)), ConfigName);
end;

class function TAtlasProjectSetups.ExistingConfig(const AProject: string;
  const AExists: TAtlasSetupFileExists): string;
var
  Folder: string;
begin
  Result := '';
  if (Trim(AProject) = '') or not Assigned(AExists) then
    Exit;
  Folder := FolderOf(Trim(AProject));
  if AExists(Joined(Folder, ConfigName)) then
    Result := Joined(Folder, ConfigName)
  else if AExists(Joined(Folder, LegacyConfigName)) then
    Result := Joined(Folder, LegacyConfigName);
end;

class function TAtlasProjectSetups.ValidTemplate(const ATemplateText, ASchemaJson: string;
  out AIssues: TArray<string>): Boolean;
begin
  Result := TAtlasSchemaCheck.Validate(ATemplateText, ASchemaJson, 'project', AIssues);
end;

class function TAtlasProjectSetups.StepDone(AStep: TAtlasSetupStep; const AFacts: TAtlasSetupFacts): Boolean;
begin
  case AStep of
    TAtlasSetupStep.Found:
      Result := Trim(AFacts.Project) <> '';
    TAtlasSetupStep.Config:
      Result := AFacts.ConfigExists;
    TAtlasSetupStep.Baseline:
      Result := AFacts.BaselineExists;
  else
    Result := AFacts.Setup.PathsClean;
  end;
end;

class function TAtlasProjectSetups.Complete(const AFacts: TAtlasSetupFacts): Boolean;
begin
  Result := Length(OpenSteps(AFacts)) = 0;
end;

class function TAtlasProjectSetups.OpenSteps(const AFacts: TAtlasSetupFacts): TArray<TAtlasSetupStep>;
var
  Step: TAtlasSetupStep;
begin
  Result := nil;
  for Step := Low(TAtlasSetupStep) to High(TAtlasSetupStep) do
    if not StepDone(Step, AFacts) then
      Result := Result + [Step];
end;

class function TAtlasProjectSetups.NeedsCard(const AFacts: TAtlasSetupFacts): Boolean;
begin
  Result := (Trim(AFacts.Project) <> '') and not AFacts.Setup.Dismissed and not Complete(AFacts);
end;

end.
