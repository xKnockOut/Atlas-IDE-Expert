unit Core.Mcp.BuildTools;

// Host-Rolle Core: MCP-Modus (--mcp, #48), Werkzeuge für Builds in der IDE (get_last_build, build_project),
// das Profil aus „Mit Profil ausführen“ (get_profile, #2057) und die Erklärung von Compilermeldungen an ihrer
// Stelle (explain_compiler_message, #2621).

interface

uses
  Core.Mcp.Context;

/// <summary>Meldet get_last_build an.</summary>
procedure AddGetLastBuild(const AContext: TMcpToolContext);
/// <summary>Meldet build_project an.</summary>
procedure AddBuildProject(const AContext: TMcpToolContext);
/// <summary>Meldet get_profile an.</summary>
procedure AddGetProfile(const AContext: TMcpToolContext);
/// <summary>Meldet explain_compiler_message an.</summary>
procedure AddExplainCompilerMessage(const AContext: TMcpToolContext);

implementation

uses
  System.SysUtils,
  // Inline-Funktionen von TJSONArray (H2443).
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Common.Mcp.ProfileTools,
  Atlas.Text.Profile,
  Atlas.Common.Compiler.IdeBuild,
  Atlas.Common.Index.CacheDirectory,
  Atlas.Common.Mcp.CompilerMessageTools,
  Atlas.Common.Mcp.IndexTools,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Configuration.Contract,
  Core.Mcp.Ide,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpBuildText = (GetLastBuildTool, GetLastBuildProject, BuildProjectTool, BuildProjectProject, BuildProjectMode,
    BuildProjectConfiguration, BuildProjectPlatform, GetProfileTool, GetProfileTop, GetProfileUnit, GetProfileRun,
    GetProfileCompareWith, GetProfileFormat, GetProfileOwnCode, ExplainTool, ExplainCode, ExplainMessage, ExplainFile,
    ExplainLine, ExplainColumn, ExplainMessages, ExplainDelphiVersion, ExplainFormat);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpBuildText] of TAtlasText = (
    (De: 'Ergebnis des letzten Builds, den der Benutzer in der IDE gestartet hat: Erfolg, Art, Zeitpunkt, Dauer, ' +
    'Projekt, Konfiguration, Plattform und alle Compilermeldungen mit Datei, Zeile, Spalte, Code und Text.';
    En: 'Result of the last build the user started in the IDE: success, kind, time, duration, project, ' +
    'configuration, platform and all compiler messages with file, line, column, code and text.'),
    (De: 'Projekt (Name oder .dproj) zum Filtern; leer = letzter Build';
    En: 'Project (name or .dproj) to filter by; empty = last build'),
    (De: 'Baut ein Projekt in der laufenden RAD-Studio-IDE über das Atlas-Plugin (#261), auch ohne ' +
    'Kommandozeilen-Compiler (Starter Edition), und liefert Ergebnis und alle Compilermeldungen wie ' +
    'get_last_build. Das Projekt muss in der IDE offen sein; ohne project baut es das aktive Projekt, wenn ' +
    'es unter dem Arbeitsordner liegt. Wartet bis zum Ende des Builds.';
    En: 'Builds a project in the running RAD Studio IDE through the Atlas plugin (#261), also without a ' +
    'command-line compiler (Starter Edition), and returns the result and all compiler messages like ' +
    'get_last_build. The project must be open in the IDE; without project it builds the active project if it ' +
    'lies below the working folder. Waits until the build has finished.'),
    (De: 'Projekt (.dproj mit Pfad, Dateiname oder Name); leer = aktives Projekt der IDE';
    En: 'Project (.dproj with path, file name or name); empty = active project of the IDE'),
    (De: 'make: geänderte Units, build: alles neu, check: nur Syntax';
    En: 'make: changed units, build: everything, check: syntax only'),
    (De: 'z. B. Debug oder Release; leer = aktive Konfiguration';
    En: 'e.g. Debug or Release; empty = active configuration'),
    (De: 'z. B. Win32 oder Win64; leer = aktive Plattform'; En: 'e.g. Win32 or Win64; empty = active platform'),
    (De: 'Profil eines Laufs mit „Mit Profil ausführen“ in der IDE (#2057): die teuersten Methoden nach ' +
    'Eigenanteil (Proben, in denen sie gerade rechnete) und Gesamtanteil (irgendwo im Aufrufstapel) mit Datei ' +
    'und heißester Zeile; RTL und VCL zusammengefasst, solange ownCode an ist. Mit compareWith der Vergleich ' +
    'zweier Läufe. Gespeichert bleiben die letzten fünf Läufe. Lesend.';
    En: 'Profile of a run with "Run with profile" in the IDE (#2057): the most expensive methods by self share ' +
    '(samples in which they were computing) and total share (anywhere in the call stack) with file and hottest ' +
    'line; RTL and VCL summarized while ownCode is on. With compareWith the comparison of two runs. The last ' +
    'five runs are kept. Read-only.'),
    (De: 'Anzahl Methoden; Vorgabe 10, höchstens 100'; En: 'Number of methods; default 10, at most 100'),
    (De: 'Nur Methoden dieser Unit bzw. Datei (Teil des Namens)'; En: 'Only methods of this unit or file (part ' +
    'of the name)'),
    (De: 'Lauf: leer = neuester, 2 = zweitneuester, oder Dateiname'; En: 'Run: empty = newest, 2 = second newest, ' +
    'or file name'),
    (De: 'Zweiter Lauf zum Vergleich (wie run)'; En: 'Second run to compare with (like run)'),
    (De: 'text (Vorgabe) oder json'; En: 'text (default) or json'),
    (De: 'RTL, VCL und andere Bibliotheken zu ihrem Aufruf aus eigenem Code zusammenfassen; Vorgabe true';
    En: 'Summarize RTL, VCL and other libraries into their call from own code; default true'),
    (De: 'Erklärt Compilermeldungen an ihrer Stelle (#2621): je Meldung die allgemeine Erklärung (Name, Ursache, ' +
    'Beispiel), die passende bekannte Delphi-Falle mit dem Merkmal im Code (z. B. zwei gleich gebaute ' +
    'Methodenreferenztypen unter Delphi 12, TMonitor aus Vcl.Forms, Exit([...]), Units, die Free Pascal nicht ' +
    'verlangt), die Atlas-Regel, die das schon beim Tippen meldet, und eine Korrektur: als Diff, wenn sie sicher ' +
    'ist, sonst als Text. Mehrere Meldungen auf einmal über messages (z. B. aus build_project oder ' +
    'get_last_build); Folgefehler sind markiert. Ohne file und line nur die allgemeine Erklärung. Lesend.';
    En: 'Explains compiler messages at their place (#2621): for each message the general explanation (name, ' +
    'cause, example), the matching known Delphi pitfall with its mark in the code (e.g. two method reference ' +
    'types of the same shape under Delphi 12, TMonitor from Vcl.Forms, Exit([...]), units Free Pascal does not ' +
    'require), the Atlas rule that reports it while typing, and a fix: as a diff when it is safe, otherwise as ' +
    'text. Several messages at once via messages (e.g. from build_project or get_last_build); follow-up errors ' +
    'are marked. Without file and line only the general explanation. Read-only.'),
    (De: 'Meldungsnummer, z. B. E2010; leer = aus message'; En: 'Message number, e.g. E2010; empty = from message'),
    (De: 'Meldungstext, deutsch oder englisch'; En: 'Message text, German or English'),
    (De: 'Datei der Meldung (relativ zum Projekt oder absolut)';
    En: 'File of the message (relative to the project or absolute)'),
    (De: 'Zeile der Meldung (ab 1)'; En: 'Line of the message (from 1)'),
    (De: 'Spalte der Meldung (ab 1), optional'; En: 'Column of the message (from 1), optional'),
    (De: 'Mehrere Meldungen statt der Einzelfelder, je mit code, message, file, line, column';
    En: 'Several messages instead of the single fields, each with code, message, file, line, column'),
    (De: 'Delphi-Version für die DocWiki-Links, z. B. 12 oder 37.0; leer = delphiVersion aus atlas.json';
    En: 'Delphi version for the DocWiki links, e.g. 12 or 37.0; empty = delphiVersion from atlas.json'),
    (De: 'text (Vorgabe) oder json'; En: 'text (default) or json'));

function ToolGetLastBuild(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFileName: string;
  mBuild: TIdeBuild;
begin
  mFileName := TIndexCacheDirectory.BuildFileFor(TIndexCacheDirectory.DefaultRoot, AContext.Root);
  if not FileExists(mFileName) or
    not TMcpBuildTools.FromFileText(TFile.ReadAllText(mFileName, TEncoding.UTF8), mBuild) then
  begin
    Exit(TMcpBuildTools.NoBuild(AContext.Root));
  end;
  Result := TMcpBuildTools.Report(mBuild, AContext.Root, TMcpArgs.OptionalString(AArguments, 'project'));
end;

procedure AddGetLastBuild(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_last_build', cTexts[TMcpBuildText.GetLastBuildTool].Text,
    TMcpArgs.StringSchema(['project'],
      [cTexts[TMcpBuildText.GetLastBuildProject].Text], 0),
    ContextTool(AContext, ToolGetLastBuild));
end;

function ToolBuildProject(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := TMcpBuildTools.Report(BuildInIde(AContext.Root, TMcpArgs.OptionalString(AArguments, 'project'),
    TMcpArgs.OptionalString(AArguments, 'mode'), TMcpArgs.OptionalString(AArguments, 'configuration'),
    TMcpArgs.OptionalString(AArguments, 'platform')), AContext.Root, '');
end;

procedure AddBuildProject(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('build_project', cTexts[TMcpBuildText.BuildProjectTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"project":{"type":"string","description":%s},' +
      '"mode":{"type":"string","enum":["make","build","check"],"default":"make","description":%s},' +
      '"configuration":{"type":"string","description":%s},' +
      '"platform":{"type":"string","description":%s}}}',
      [cTexts[TMcpBuildText.BuildProjectProject].Text,
      cTexts[TMcpBuildText.BuildProjectMode].Text,
      cTexts[TMcpBuildText.BuildProjectConfiguration].Text,
      cTexts[TMcpBuildText.BuildProjectPlatform].Text]),
    ContextTool(AContext, ToolBuildProject), TMcpToolKind.Process);
end;

/// <summary>Gespeicherte Läufe unter AFolder, neueste zuerst; unlesbare Dateien bleiben weg.</summary>
function LoadProfileRuns(const AFolder: string): TArray<TMcpProfileRun>;
var
  mFile: string;
  mRun: TMcpProfileRun;
begin
  Result := nil;
  if not TDirectory.Exists(AFolder) then
  begin
    Exit;
  end;
  for mFile in TAtlasProfileStore.Newest(TDirectory.GetFiles(AFolder, TAtlasProfileStore.cPrefix + '*.json')) do
  begin
    mRun := Default(TMcpProfileRun);
    mRun.Name := ExtractFileName(mFile);
    if TAtlasProfileJson.TryParse(TFile.ReadAllText(mFile, TEncoding.UTF8), mRun.Profile) then
    begin
      Result := Result + [mRun];
    end;
  end;
end;

function ToolGetProfile(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mFolder: string;
  mRuns: TArray<TMcpProfileRun>;
begin
  mFolder := TAtlasProfileStore.Folder(TIndexCacheDirectory.DefaultRoot);
  mRuns := LoadProfileRuns(mFolder);
  if Length(mRuns) = 0 then
  begin
    Exit(TMcpProfileTools.NoRuns(mFolder));
  end;
  Result := TMcpProfileTools.Report(mRuns, TMcpProfileRequest.FromArguments(AArguments));
end;

procedure AddGetProfile(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_profile', cTexts[TMcpBuildText.GetProfileTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"top":{"type":"integer","default":10,"description":%s},' +
      '"unit":{"type":"string","description":%s},' +
      '"run":{"type":"string","description":%s},' +
      '"compareWith":{"type":"string","description":%s},' +
      '"format":{"type":"string","enum":["text","json"],"default":"text","description":%s},' +
      '"ownCode":{"type":"boolean","default":true,"description":%s}}}',
      [cTexts[TMcpBuildText.GetProfileTop].Text,
      cTexts[TMcpBuildText.GetProfileUnit].Text,
      cTexts[TMcpBuildText.GetProfileRun].Text,
      cTexts[TMcpBuildText.GetProfileCompareWith].Text,
      cTexts[TMcpBuildText.GetProfileFormat].Text,
      cTexts[TMcpBuildText.GetProfileOwnCode].Text]),
    ContextTool(AContext, ToolGetProfile));
end;

/// <summary>Liest Dateien unter ARoot (relativ oder absolut); False für Dateien außerhalb, z. B. Meldungen zur RTL.
/// </summary>
function WorkspaceReader(const ARoot: string): TMcpReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    var
      mPath: string;
    begin
      AText := '';
      mPath := AFileName;
      if not TPath.IsPathRooted(mPath) then
      begin
        mPath := TPath.Combine(ARoot, mPath);
      end;
      Result := TMcpPathGuard.Contains(ARoot, mPath) and ReadSourceText(TPath.GetFullPath(mPath), AText);
    end;
end;

function ToolExplainCompilerMessage(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mRequest: TMcpExplainRequest;
begin
  mRequest := Default(TMcpExplainRequest);
  mRequest.Messages := TMcpCompilerMessageTools.MessagesOf(AArguments);
  mRequest.DelphiVersion := BdsVersionOf(TMcpArgs.OptionalString(AArguments, 'delphiVersion'));
  if mRequest.DelphiVersion = '' then
  begin
    mRequest.DelphiVersion := AContext.Group.Main.Configuration.Settings.DelphiVersion;
  end;
  mRequest.Json := SameText(TMcpArgs.OptionalString(AArguments, 'format'), 'json');
  mRequest.ReadText := WorkspaceReader(AContext.Root);
  Result := TMcpCompilerMessageTools.Explain(mRequest);
end;

procedure AddExplainCompilerMessage(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('explain_compiler_message', cTexts[TMcpBuildText.ExplainTool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"code":{"type":"string","description":%s},' +
      '"message":{"type":"string","description":%s},' +
      '"file":{"type":"string","description":%s},' +
      '"line":{"type":"integer","minimum":1,"description":%s},' +
      '"column":{"type":"integer","minimum":1,"description":%s},' +
      '"messages":{"type":"array","items":{"type":"object","properties":{"code":{"type":"string"},' +
      '"message":{"type":"string"},"file":{"type":"string"},"line":{"type":"integer"},' +
      '"column":{"type":"integer"}}},"description":%s},' +
      '"delphiVersion":{"type":"string","description":%s},' +
      '"format":{"type":"string","enum":["text","json"],"description":%s}}}',
      [cTexts[TMcpBuildText.ExplainCode].Text,
      cTexts[TMcpBuildText.ExplainMessage].Text,
      cTexts[TMcpBuildText.ExplainFile].Text,
      cTexts[TMcpBuildText.ExplainLine].Text,
      cTexts[TMcpBuildText.ExplainColumn].Text,
      cTexts[TMcpBuildText.ExplainMessages].Text,
      cTexts[TMcpBuildText.ExplainDelphiVersion].Text,
      cTexts[TMcpBuildText.ExplainFormat].Text]),
    ContextTool(AContext, ToolExplainCompilerMessage));
end;

initialization
  TAtlasTextTables.Add('Core.Mcp.BuildTools', cTexts);

end.
