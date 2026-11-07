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
    cSearchPathCommand = 'atlas.addSearchPath';
    cAddUnitCommand = 'atlas.addUnitToProject';
    cInfoCommand = 'atlas.showInfo';
    cKind = 'quickfix';
    /// <summary>Höchstens so viele Ordner werden angeboten.</summary>
    cMaxFolders = 3;
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
  mCommand: TJSONObject;
begin
  mCommand := TJSONObject.Create;
  mCommand.AddPair('title', ATitle);
  mCommand.AddPair('command', ACommand);
  mCommand.AddPair('arguments', AArguments);
  Result := TJSONObject.Create;
  Result.AddPair('title', ATitle);
  Result.AddPair('kind', TLspMissingUnit.cKind);
  if APreferred then
  begin
    Result.AddPair('isPreferred', TJSONBool.Create(True));
  end;
  Result.AddPair('command', mCommand);
end;

function Arguments(const AValues: array of string): TJSONArray;
var
  mValue: string;
begin
  Result := TJSONArray.Create;
  for mValue in AValues do
  begin
    Result.Add(mValue);
  end;
end;

function InfoAction(const ATitle, AText: string): TJSONObject;
begin
  Result := CommandAction(ATitle, TLspMissingUnit.cInfoCommand, Arguments([AText]), False);
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
  mFolder, mConfig: string;
begin
  Result := nil;
  mConfig := ASetup.Project.Config;
  mFolder := TMissingUnitSearch.RelativePath(ASetup.Project.FileName, AHit.Folder);
  if mConfig <> '' then
  begin
    Result := Result + [CommandAction(cTexts[TLspMissingUnitText.AddFolderToTheSearch].Fmt([mFolder, mConfig,
      HitOrigin(AHit)]), TLspMissingUnit.cSearchPathCommand,
      Arguments([ASetup.Project.FileName, mFolder, mConfig]), AFirst)];
  end;
  Result := Result + [CommandAction(cTexts[TLspMissingUnitText.AddFolderToTheSearch2].Fmt([mFolder, HitOrigin(AHit)]),
    TLspMissingUnit.cSearchPathCommand,
    Arguments([ASetup.Project.FileName, mFolder, '']), AFirst and (mConfig = ''))];
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
  mHit: TMissingUnitHit;
  mPlatforms: TArray<string>;
  mOffered: Integer;
  mSourceOffered: Boolean;
begin
  Result := nil;
  mPlatforms := nil;
  mOffered := 0;
  mSourceOffered := False;
  for mHit in AHits do
  begin
    // Nur in der Bibliothek einer anderen Plattform: kein Pfad, sondern der Hinweis.
    if mHit.Place = TMissingUnitPlace.OtherPlatformLibrary then
    begin
      if IndexText(mHit.Detail, mPlatforms) < 0 then
      begin
        mPlatforms := mPlatforms + [mHit.Detail];
      end;
    end
    else if mOffered < cMaxFolders then
    begin
      Result := Result + FolderActions(ASetup, mHit, mOffered = 0);
      if not mSourceOffered and SameText(ExtractFileExt(mHit.FileName), '.pas') then
      begin
        mSourceOffered := True;
        Result := Result + [CommandAction(cTexts[TLspMissingUnitText.AddToTheProject].Fmt([
          ExtractFileName(mHit.FileName)]),
          cAddUnitCommand, Arguments([ASetup.Project.FileName, mHit.FileName]), False)];
      end;
      Inc(mOffered);
    end;
  end;
  if mOffered = 0 then
  begin
    Result := FallbackActions(ASetup, mPlatforms, ASearched);
  end;
end;

class function TLspMissingUnit.Actions(AEnabled: Boolean; AFirstLine, ALastLine: Integer;
  const AMessages: TArray<TCompilerMessage>; const AResolve: TMissingUnitResolve): TArray<TJSONObject>;
var
  mMessage: TCompilerMessage;
  mUnitName: string;
  mSeen: TArray<string>;
  mSetup: TMissingUnitSetup;
  mHits: TArray<TMissingUnitHit>;
  mSearched: TArray<string>;
begin
  Result := nil;
  if not AEnabled or not Assigned(AResolve) then
  begin
    Exit;
  end;
  mSeen := nil;
  for mMessage in AMessages do
  begin
    if not Handles(mMessage.Code) or (mMessage.Line < AFirstLine) or (mMessage.Line > ALastLine) then
    begin
      Continue;
    end;
    mUnitName := TMissingUnitSearch.UnitOfMessage(mMessage.Code, mMessage.Text);
    // Dieselbe Unit kommt bei mehreren Plattformen oder als F2613 und F1026 doppelt.
    if (mUnitName = '') or (IndexText(mUnitName, mSeen) >= 0) then
    begin
      Continue;
    end;
    mSeen := mSeen + [mUnitName];
    if not AResolve(mUnitName, mSetup) then
    begin
      Continue;
    end;
    mSetup.UnitName := mUnitName;
    mHits := TMissingUnitSearch.Search(mSetup, mSearched);
    Result := Result + ActionsFor(mSetup, mHits, mSearched);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.MissingUnit', cTexts);

end.
