unit Atlas.Common.Lsp.MissingUnit;

// „Unit nicht gefunden“ über das Protokoll (#550): Code-Aktionen auf Zeilen
// mit F2613 oder F1026 des letzten Compilerlaufs (atlas/compilerMessages,
// #528), nur mit refactoring.missingUnit. Die Suche steht in Atlas.Common.
// Projects.MissingUnit; den Zugang zu Projekt, Gruppe, Bibliothek und Index
// gibt der Aufrufer (AResolve). Alle Aktionen tragen Client-Befehle, denn die
// Projektoptionen ändert das Plugin über die IDE (#396):
//   - atlas.addSearchPath [dproj, Ordner relativ zur .dproj, Konfiguration]:
//     „Ordner in den Suchpfad dieser Konfiguration aufnehmen“ bzw. mit
//     Konfiguration '' „… aller Konfigurationen“ (Basis).
//   - atlas.addUnitToProject [dproj, Datei]: „Unit ins Projekt aufnehmen“,
//     nur für gefundene Quellen (.pas).
//   - atlas.showInfo [Text]: Die Unit gibt es nur für andere Plattformen
//     (statt eines Pfads) oder sie ist nirgends zu finden (mit den durch-
//     suchten Orten). Der Titel der Aktion sagt es schon im Menü.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Projects.MissingUnit;

type
  /// <summary>Suche für die Unit AUnitName vorbereiten; False ohne Projekt.</summary>
  TMissingUnitResolve = reference to function(const AUnitName: string; out ASetup: TMissingUnitSetup): Boolean;

  TLspMissingUnit = class
  public const
    SearchPathCommand = 'atlas.addSearchPath';
    AddUnitCommand = 'atlas.addUnitToProject';
    InfoCommand = 'atlas.showInfo';
    Kind = 'quickfix';
    /// <summary>Höchstens so viele Ordner werden angeboten.</summary>
    MaxFolders = 3;
  public
    /// <summary>F2613 oder F1026?</summary>
    class function Handles(const ACode: string): Boolean; static;
    /// <summary>Code-Aktionen für die Meldungen AMessages (Zeilen ab 0) auf den Zeilen AFirstLine..ALastLine.
    /// </summary>
    class function Actions(AEnabled: Boolean; AFirstLine, ALastLine: Integer;
      const AMessages: TArray<TCompilerMessage>; const AResolve: TMissingUnitResolve): TArray<TJSONObject>; static;
    /// <summary>Code-Aktionen zu den Treffern einer Suche.</summary>
    class function ActionsFor(const ASetup: TMissingUnitSetup; const AHits: TArray<TMissingUnitHit>;
      const ASearched: TArray<string>): TArray<TJSONObject>; static;
    /// <summary>„Winapi.Windows gibt es für Linux64 nicht (nur Win32, Win64)“.</summary>
    class function PlatformText(const AUnitName, APlatform: string; const APlatforms: TArray<string>): string;
      static;
    /// <summary>„X nicht gefunden“, mit ASearched die durchsuchten Orte.</summary>
    class function NotFoundText(const AUnitName: string; const ASearched: TArray<string>): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspMissingUnitText = (DoesNotExistForOnly, NotFound, AddFolderToTheSearch, AddFolderToTheSearch2,
    NotFoundShowSearchedLocations, AddToTheProject, Searched, IsIn, From);

const
  cTexts: array[TLspMissingUnitText] of TAtlasText = (
    (De: '%s gibt es für %s nicht (nur %s)'; En: '%s does not exist for %s (only %s)'),
    (De: '%s nicht gefunden'; En: '%s not found'),
    (De: 'Ordner %s in den Suchpfad von %s aufnehmen%s'; En: 'Add folder %s to the search path of %s%s'),
    (De: 'Ordner %s in den Suchpfad aller Konfigurationen aufnehmen%s';
     En: 'Add folder %s to the search path of all configurations%s'),
    (De: '%s nicht gefunden: durchsuchte Orte anzeigen'; En: '%s not found: show searched locations'),
    (De: '%s ins Projekt aufnehmen'; En: 'Add %s to the project'),
    (De: '. Durchsucht: '; En: '. Searched: '),
    (De: ' (steht in %s)'; En: ' (is in %s)'),
    (De: ' (aus %s)'; En: ' (from %s)'));

{$SCOPEDENUMS OFF}

class function TLspMissingUnit.Handles(const ACode: string): Boolean;
begin
  Result := MatchText(Trim(ACode), ['F2613', 'F1026']);
end;

function CommandAction(const ATitle, ACommand: string; AArguments: TJSONArray; APreferred: Boolean): TJSONObject;
var
  Command: TJSONObject;
begin
  Command := TJSONObject.Create;
  Command.AddPair('title', ATitle);
  Command.AddPair('command', ACommand);
  Command.AddPair('arguments', AArguments);
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('kind', TLspMissingUnit.Kind);
  if APreferred then
  begin
    Result.AddPair('isPreferred', TJSONBool.Create(True));
  end;
  Result.AddPair('command', Command);
end;

function Arguments(const AValues: array of string): TJSONArray;
var
  Value: string;
begin
  Result := TJSONArray.Create;
  for Value in AValues do
  begin
    Result.Add(Value);
  end;
end;

function InfoAction(const ATitle, AText: string): TJSONObject;
begin
  Result := CommandAction(ATitle, TLspMissingUnit.InfoCommand, Arguments([AText]), False);
end;

class function TLspMissingUnit.PlatformText(const AUnitName, APlatform: string;
  const APlatforms: TArray<string>): string;
begin
  Result := cTexts[TLspMissingUnitText.DoesNotExistForOnly].Fmt([AUnitName, APlatform, string.Join(', ', APlatforms)]);
end;

class function TLspMissingUnit.NotFoundText(const AUnitName: string; const ASearched: TArray<string>): string;
begin
  Result := cTexts[TLspMissingUnitText.NotFound].Fmt([AUnitName]);
  if Length(ASearched) > 0 then
  begin
    Result := Result + cTexts[TLspMissingUnitText.Searched].Text + string.Join('; ', ASearched);
  end;
end;

/// <summary>Herkunft eines Funds für den Titel: anderes Ziel oder Projektgruppe; sonst ''.</summary>
function HitOrigin(const AHit: TMissingUnitHit): string;
begin
  Result := '';
  if AHit.Place = TMissingUnitPlace.OtherTarget then
  begin
    Result := cTexts[TLspMissingUnitText.IsIn].Fmt([AHit.Detail]);
  end
  else if AHit.Place = TMissingUnitPlace.GroupProject then
  begin
    Result := cTexts[TLspMissingUnitText.From].Fmt([AHit.Detail]);
  end;
end;

/// <summary>Suchpfad-Aktionen für den Ordner des Funds AHit; AFirst: der erste Fund ist bevorzugt.</summary>
function FolderActions(const ASetup: TMissingUnitSetup; const AHit: TMissingUnitHit;
  AFirst: Boolean): TArray<TJSONObject>;
var
  Folder, Config: string;
begin
  Result := nil;
  Config := ASetup.Project.Config;
  Folder := TMissingUnitSearch.RelativePath(ASetup.Project.FileName, AHit.Folder);
  if Config <> '' then
  begin
    Result := Result + [CommandAction(cTexts[TLspMissingUnitText.AddFolderToTheSearch].Fmt([Folder, Config,
      HitOrigin(AHit)]), TLspMissingUnit.SearchPathCommand,
      Arguments([ASetup.Project.FileName, Folder, Config]), AFirst)];
  end;
  Result := Result + [CommandAction(cTexts[TLspMissingUnitText.AddFolderToTheSearch2].Fmt([Folder, HitOrigin(AHit)]),
    TLspMissingUnit.SearchPathCommand,
    Arguments([ASetup.Project.FileName, Folder, '']), AFirst and (Config = ''))];
end;

/// <summary>Ohne Ordner: Hinweis auf andere Plattformen bzw. die durchsuchten Orte.</summary>
function FallbackActions(const ASetup: TMissingUnitSetup; const APlatforms, ASearched: TArray<string>):
  TArray<TJSONObject>;
begin
  if Length(APlatforms) > 0 then
  begin
    Result := [InfoAction(TLspMissingUnit.PlatformText(ASetup.UnitName, ASetup.Project.Platform, APlatforms),
      TLspMissingUnit.PlatformText(ASetup.UnitName, ASetup.Project.Platform, APlatforms))];
  end
  else
  begin
    Result := [InfoAction(cTexts[TLspMissingUnitText.NotFoundShowSearchedLocations].Fmt([ASetup.UnitName]),
      TLspMissingUnit.NotFoundText(ASetup.UnitName, ASearched))];
  end;
end;

class function TLspMissingUnit.ActionsFor(const ASetup: TMissingUnitSetup; const AHits: TArray<TMissingUnitHit>;
  const ASearched: TArray<string>): TArray<TJSONObject>;
var
  Hit: TMissingUnitHit;
  Platforms: TArray<string>;
  Offered: Integer;
  SourceOffered: Boolean;
begin
  Result := nil;
  Platforms := nil;
  Offered := 0;
  SourceOffered := False;
  for Hit in AHits do
  begin
    // Nur in der Bibliothek einer anderen Plattform: kein Pfad, sondern der Hinweis.
    if Hit.Place = TMissingUnitPlace.OtherPlatformLibrary then
    begin
      if IndexText(Hit.Detail, Platforms) < 0 then
      begin
        Platforms := Platforms + [Hit.Detail];
      end;
    end
    else if Offered < MaxFolders then
    begin
      Result := Result + FolderActions(ASetup, Hit, Offered = 0);
      if not SourceOffered and SameText(ExtractFileExt(Hit.FileName), '.pas') then
      begin
        SourceOffered := True;
        Result := Result + [CommandAction(cTexts[TLspMissingUnitText.AddToTheProject].Fmt([
          ExtractFileName(Hit.FileName)]),
          AddUnitCommand, Arguments([ASetup.Project.FileName, Hit.FileName]), False)];
      end;
      Inc(Offered);
    end;
  end;
  if Offered = 0 then
  begin
    Result := FallbackActions(ASetup, Platforms, ASearched);
  end;
end;

class function TLspMissingUnit.Actions(AEnabled: Boolean; AFirstLine, ALastLine: Integer;
  const AMessages: TArray<TCompilerMessage>; const AResolve: TMissingUnitResolve): TArray<TJSONObject>;
var
  Message: TCompilerMessage;
  UnitName: string;
  Seen: TArray<string>;
  Setup: TMissingUnitSetup;
  Hits: TArray<TMissingUnitHit>;
  Searched: TArray<string>;
begin
  Result := nil;
  if not AEnabled or not Assigned(AResolve) then
  begin
    Exit;
  end;
  Seen := nil;
  for Message in AMessages do
  begin
    if not Handles(Message.Code) or (Message.Line < AFirstLine) or (Message.Line > ALastLine) then
    begin
      Continue;
    end;
    UnitName := TMissingUnitSearch.UnitOfMessage(Message.Code, Message.Text);
    // Dieselbe Unit kommt bei mehreren Plattformen oder als F2613 und F1026 doppelt.
    if (UnitName = '') or (IndexText(UnitName, Seen) >= 0) then
    begin
      Continue;
    end;
    Seen := Seen + [UnitName];
    if not AResolve(UnitName, Setup) then
    begin
      Continue;
    end;
    Setup.UnitName := UnitName;
    Hits := TMissingUnitSearch.Search(Setup, Searched);
    Result := Result + ActionsFor(Setup, Hits, Searched);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.MissingUnit', cTexts);

end.
