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
  System.StrUtils;

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
    Result.AddPair('isPreferred', TJSONBool.Create(True));
  Result.AddPair('command', Command);
end;

function Arguments(const AValues: array of string): TJSONArray;
var
  Value: string;
begin
  Result := TJSONArray.Create;
  for Value in AValues do
    Result.Add(Value);
end;

function InfoAction(const ATitle, AText: string): TJSONObject;
begin
  Result := CommandAction(ATitle, TLspMissingUnit.InfoCommand, Arguments([AText]), False);
end;

class function TLspMissingUnit.PlatformText(const AUnitName, APlatform: string;
  const APlatforms: TArray<string>): string;
begin
  Result := Format('%s gibt es für %s nicht (nur %s)', [AUnitName, APlatform, string.Join(', ', APlatforms)]);
end;

class function TLspMissingUnit.NotFoundText(const AUnitName: string; const ASearched: TArray<string>): string;
begin
  Result := Format('%s nicht gefunden', [AUnitName]);
  if Length(ASearched) > 0 then
    Result := Result + '. Durchsucht: ' + string.Join('; ', ASearched);
end;

class function TLspMissingUnit.ActionsFor(const ASetup: TMissingUnitSetup; const AHits: TArray<TMissingUnitHit>;
  const ASearched: TArray<string>): TArray<TJSONObject>;
var
  Hit: TMissingUnitHit;
  Folder, Origin, Config: string;
  Platforms: TArray<string>;
  Offered: Integer;
  SourceOffered: Boolean;
begin
  Result := nil;
  Platforms := nil;
  Offered := 0;
  SourceOffered := False;
  Config := ASetup.Project.Config;
  for Hit in AHits do
  begin
    // Nur in der Bibliothek einer anderen Plattform: kein Pfad, sondern der Hinweis.
    if Hit.Place = TMissingUnitPlace.OtherPlatformLibrary then
    begin
      if IndexText(Hit.Detail, Platforms) < 0 then
        Platforms := Platforms + [Hit.Detail];
      Continue;
    end;
    if Offered >= MaxFolders then
      Continue;
    Folder := TMissingUnitSearch.RelativePath(ASetup.Project.FileName, Hit.Folder);
    Origin := '';
    if Hit.Place = TMissingUnitPlace.OtherTarget then
      Origin := Format(' (steht in %s)', [Hit.Detail])
    else if Hit.Place = TMissingUnitPlace.GroupProject then
      Origin := Format(' (aus %s)', [Hit.Detail]);
    if Config <> '' then
      Result := Result + [CommandAction(Format('Ordner %s in den Suchpfad von %s aufnehmen%s',
        [Folder, Config, Origin]), SearchPathCommand, Arguments([ASetup.Project.FileName, Folder, Config]),
        Offered = 0)];
    Result := Result + [CommandAction(Format('Ordner %s in den Suchpfad aller Konfigurationen aufnehmen%s',
      [Folder, Origin]), SearchPathCommand, Arguments([ASetup.Project.FileName, Folder, '']),
      (Offered = 0) and (Config = ''))];
    if not SourceOffered and SameText(ExtractFileExt(Hit.FileName), '.pas') then
    begin
      SourceOffered := True;
      Result := Result + [CommandAction(Format('%s ins Projekt aufnehmen', [ExtractFileName(Hit.FileName)]),
        AddUnitCommand, Arguments([ASetup.Project.FileName, Hit.FileName]), False)];
    end;
    Inc(Offered);
  end;
  if Offered > 0 then
    Exit;
  if Length(Platforms) > 0 then
    Result := [InfoAction(PlatformText(ASetup.UnitName, ASetup.Project.Platform, Platforms),
      PlatformText(ASetup.UnitName, ASetup.Project.Platform, Platforms))]
  else
    Result := [InfoAction(Format('%s nicht gefunden: durchsuchte Orte anzeigen', [ASetup.UnitName]),
      NotFoundText(ASetup.UnitName, ASearched))];
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
    Exit;
  Seen := nil;
  for Message in AMessages do
  begin
    if not Handles(Message.Code) or (Message.Line < AFirstLine) or (Message.Line > ALastLine) then
      Continue;
    UnitName := TMissingUnitSearch.UnitOfMessage(Message.Code, Message.Text);
    // Dieselbe Unit kommt bei mehreren Plattformen oder als F2613 und F1026 doppelt.
    if (UnitName = '') or (IndexText(UnitName, Seen) >= 0) then
      Continue;
    Seen := Seen + [UnitName];
    if not AResolve(UnitName, Setup) then
      Continue;
    Setup.UnitName := UnitName;
    Hits := TMissingUnitSearch.Search(Setup, Searched);
    Result := Result + ActionsFor(Setup, Hits, Searched);
  end;
end;

end.
