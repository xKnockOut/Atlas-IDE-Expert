unit Atlas.Core.Generate.Contract;

// Gruppen und Listen des Erzeugen-Menüs (#719), wie sie in den Einstellungen stehen
// (keys.generateMenu.groups, keys.generateMenu.hidden). Eigene Unit, damit die Einstellungen sie
// normalisieren können, ohne das Menü (und darüber den LSP-Client) zu importieren (A-09).

interface

type
  {$SCOPEDENUMS ON}
  /// <summary>Recent ist keine eigene Herkunft, nur die Gruppe „Zuletzt gewählt“ oben.</summary>
  TAtlasGenerateGroup = (Recent, Generate, Surround, Templates);
  {$SCOPEDENUMS OFF}

  TAtlasGenerateLists = record
    /// <summary>Durch Komma, Semikolon oder Zeilenwechsel getrennt; getrimmt, ohne leere Einträge.</summary>
    class function Split(const AText: string): TArray<string>; static;
    /// <summary>generate, surround, templates bzw. recent.</summary>
    class function GroupName(AGroup: TAtlasGenerateGroup): string; static;
    class function TryParseGroup(const AName: string; out AGroup: TAtlasGenerateGroup): Boolean; static;
    /// <summary>Bekannte Gruppen ohne Doppelte; leer bzw. ohne bekannte Gruppe: die Vorgabe.</summary>
    class function ParseGroups(const AText: string): TArray<TAtlasGenerateGroup>; static;
    /// <summary>Für die Einstellung: "generate,surround,templates" in der gewählten Reihenfolge.</summary>
    class function NormalizeGroups(const AText: string): string; static;
    /// <summary>Für die Einstellung: getrimmt, ohne leere und doppelte Einträge, mit ", " verbunden.</summary>
    class function NormalizeHidden(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  DefaultGroups: array[0..2] of TAtlasGenerateGroup = (TAtlasGenerateGroup.Generate, TAtlasGenerateGroup.Surround,
    TAtlasGenerateGroup.Templates);

class function TAtlasGenerateLists.Split(const AText: string): TArray<string>;
var
  Item: string;
begin
  Result := nil;
  for Item in AText.Split([',', ';', #10]) do
  begin
    if Trim(Item) <> '' then
    begin
      Result := Result + [Trim(Item)];
    end;
  end;
end;

class function TAtlasGenerateLists.GroupName(AGroup: TAtlasGenerateGroup): string;
begin
  case AGroup of
    TAtlasGenerateGroup.Generate:
      Result := 'generate';
    TAtlasGenerateGroup.Surround:
      Result := 'surround';
    TAtlasGenerateGroup.Templates:
      Result := 'templates';
  else
    Result := 'recent';
  end;
end;

class function TAtlasGenerateLists.TryParseGroup(const AName: string; out AGroup: TAtlasGenerateGroup): Boolean;
var
  Group: TAtlasGenerateGroup;
begin
  for Group := Low(TAtlasGenerateGroup) to High(TAtlasGenerateGroup) do
  begin
    if SameText(Trim(AName), GroupName(Group)) then
    begin
      AGroup := Group;
      Exit(True);
    end;
  end;
  AGroup := TAtlasGenerateGroup.Generate;
  Result := False;
end;

class function TAtlasGenerateLists.ParseGroups(const AText: string): TArray<TAtlasGenerateGroup>;
var
  Item: string;
  Group, Known: TAtlasGenerateGroup;
  Seen: Boolean;
begin
  Result := nil;
  for Item in Split(AText) do
  begin
    // "recent" ist keine Gruppe der Liste; dafür gibt es recentFirst.
    if not TryParseGroup(Item, Group) or (Group = TAtlasGenerateGroup.Recent) then
    begin
      Continue;
    end;
    Seen := False;
    for Known in Result do
    begin
      if Known = Group then
      begin
        Seen := True;
      end;
    end;
    if not Seen then
    begin
      Result := Result + [Group];
    end;
  end;
  if Length(Result) = 0 then
  begin
    for Group in DefaultGroups do
    begin
      Result := Result + [Group];
    end;
  end;
end;

class function TAtlasGenerateLists.NormalizeGroups(const AText: string): string;
var
  Group: TAtlasGenerateGroup;
begin
  Result := '';
  for Group in ParseGroups(AText) do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + GroupName(Group);
  end;
end;

class function TAtlasGenerateLists.NormalizeHidden(const AText: string): string;
var
  Item: string;
  Items: TArray<string>;
begin
  Items := nil;
  for Item in Split(AText) do
  begin
    if IndexText(Item, Items) < 0 then
    begin
      Items := Items + [Item];
    end;
  end;
  Result := string.Join(', ', Items);
end;

end.
