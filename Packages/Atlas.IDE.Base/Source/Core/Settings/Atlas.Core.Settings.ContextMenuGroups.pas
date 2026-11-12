unit Atlas.Core.Settings.ContextMenuGroups;

// Untermenüs von Atlas im Kontextmenü des Editors für
// commands.editorContextMenu.groups: kommagetrennte feste Kennungen
// ("navigation,edit,analysis,findings,debug,tests,notes"); unbekannte fallen
// weg, die Reihenfolge ist fest. Liegt bei den Einstellungen, damit der Parser
// ohne das Kontextmenü auskommt. Die Kennungen debug, tests und notes setzen
// die Module an ihren Einträgen (TAtlasMenuEntry.Group).

interface

type
{$SCOPEDENUMS ON}
  TAtlasContextMenuGroup = (Navigation, Edit, Analysis, Findings, Debug, Tests, Notes);
{$SCOPEDENUMS OFF}
  TAtlasContextMenuGroups = set of TAtlasContextMenuGroup;

  TAtlasContextMenuGroupNames = class
  public const
    cAll = [TAtlasContextMenuGroup.Navigation, TAtlasContextMenuGroup.Edit, TAtlasContextMenuGroup.Analysis,
      TAtlasContextMenuGroup.Findings, TAtlasContextMenuGroup.Debug, TAtlasContextMenuGroup.Tests,
      TAtlasContextMenuGroup.Notes];
  public
    class function Name(AGroup: TAtlasContextMenuGroup): string; static;
    class function Parse(const AText: string): TAtlasContextMenuGroups; static;
    class function Text(AGroups: TAtlasContextMenuGroups): string; static;
    /// <summary>Bekannte Namen in fester Reihenfolge, ohne Doppelte.</summary>
    class function Normalize(const AText: string): string; static;
    /// <summary>Zeigt die Einstellung AText das Untermenü mit der Kennung AKey? '' und unbekannte Kennungen
    /// (etwa eines neueren Moduls) immer.</summary>
    class function Shown(const AText, AKey: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

const
  cNames: array[TAtlasContextMenuGroup] of string = ('navigation', 'edit', 'analysis', 'findings', 'debug', 'tests',
    'notes');

class function TAtlasContextMenuGroupNames.Name(AGroup: TAtlasContextMenuGroup): string;
begin
  Result := cNames[AGroup];
end;

class function TAtlasContextMenuGroupNames.Parse(const AText: string): TAtlasContextMenuGroups;
var
  mPart: string;
  mGroup: TAtlasContextMenuGroup;
begin
  Result := [];
  for mPart in AText.Split([',', ';', ' ']) do
  begin
    for mGroup := Low(TAtlasContextMenuGroup) to High(TAtlasContextMenuGroup) do
    begin
      if SameText(Trim(mPart), cNames[mGroup]) then
      begin
        Include(Result, mGroup);
      end;
    end;
  end;
end;

class function TAtlasContextMenuGroupNames.Text(AGroups: TAtlasContextMenuGroups): string;
var
  mGroup: TAtlasContextMenuGroup;
begin
  Result := '';
  for mGroup := Low(TAtlasContextMenuGroup) to High(TAtlasContextMenuGroup) do
  begin
    if mGroup in AGroups then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + cNames[mGroup];
    end;
  end;
end;

class function TAtlasContextMenuGroupNames.Normalize(const AText: string): string;
begin
  Result := Text(Parse(AText));
end;

class function TAtlasContextMenuGroupNames.Shown(const AText, AKey: string): Boolean;
var
  mGroup: TAtlasContextMenuGroup;
begin
  Result := True;
  for mGroup := Low(TAtlasContextMenuGroup) to High(TAtlasContextMenuGroup) do
  begin
    if SameText(AKey, cNames[mGroup]) then
    begin
      Result := mGroup in Parse(AText);
      Exit;
    end;
  end;
end;

end.
