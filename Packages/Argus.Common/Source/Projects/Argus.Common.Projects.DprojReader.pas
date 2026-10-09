unit Argus.Common.Projects.DprojReader;

// Wertet eine .dproj-Datei für eine Konfiguration und Plattform aus.
//
// Die Datei ist ein MSBuild-Projekt. Ausgewertet werden die PropertyGroups
// und ItemGroups der obersten Ebene in Dateireihenfolge, mit Bedingungen und
// $(Name)-Verweisen; Imports (CodeGear.Delphi.Targets) werden nicht geladen.
// Das genügt für Suchpfade, Defines, Namespaces und Hauptdatei, weil die IDE
// diese Werte vollständig in die .dproj schreibt.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Argus.Common.Projects.Contract;

type
  TDprojOptions = record
    /// <summary>Konfiguration, z. B. Debug; '' = Vorgabe der Datei.</summary>
    Config: string;
    /// <summary>Plattform, z. B. Win64; '' = Vorgabe der Datei.</summary>
    Platform: string;
    /// <summary>Vorbelegte Eigenschaften wie BDS oder Umgebungsvariablen.</summary>
    Variables: TArray<TPair<string, string>>;
    /// <summary>Für Exists(...) in Bedingungen; nil = immer falsch.</summary>
    FileExists: TFunc<string, Boolean>;
  end;

  TDprojReader = class
  public
    /// <summary>Wertet den Inhalt AText der Datei AFileName aus. EProjectError bei ungültigem XML.</summary>
    class function Read(const AFileName, AText: string; const AOptions: TDprojOptions): TProjectInfo; static;
    /// <summary>Liest die Datei von der Platte (Kodierung wird erkannt) und wertet sie aus.</summary>
    class function Load(const AFileName: string; const AOptions: TDprojOptions): TProjectInfo; static;
    /// <summary>'' wenn AConfig und APlatform ('' = unverändert) im Projekt vorkommen, sonst der Grund (#46).</summary>
    class function CheckTarget(const AProject: TProjectInfo; const AConfig, APlatform: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  Argus.Common.Documents.FileEncoding,
  Argus.Common.Projects.Paths,
  Argus.Common.Projects.Internals.Xml,
  Argus.Common.Projects.Internals.MSBuild;

function UniqueUpper(const AItems: TArray<string>): TArray<string>;
var
  Items: TList<string>;
  Item: string;
begin
  Items := TList<string>.Create;
  try
    for Item in AItems do
      if not Items.Contains(UpperCase(Item)) then
        Items.Add(UpperCase(Item));
    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

function UniquePaths(const ABase: string; const AItems: TArray<string>): TArray<string>;
var
  Items: TList<string>;
  Item: string;
  Path: string;
  Known: TList<string>;
begin
  Items := TList<string>.Create;
  Known := TList<string>.Create;
  try
    for Item in AItems do
    begin
      Path := TProjectPaths.Combine(ABase, Item);
      if not Known.Contains(LowerCase(Path)) then
      begin
        Known.Add(LowerCase(Path));
        Items.Add(Path);
      end;
    end;
    Result := Items.ToArray;
  finally
    Known.Free;
    Items.Free;
  end;
end;

/// <summary>Sammelt Konfigurationen und aktivierte Plattformen aus dem ganzen Baum.</summary>
procedure CollectTargets(AElement: TXmlElement; var AConfigs, APlatforms: TArray<string>);
var
  Index: Integer;
  Value: string;
begin
  if AElement.Name = 'BuildConfiguration' then
  begin
    Value := Trim(AElement.Attribute('Include'));
    if (Value <> '') and not SameText(Value, 'Base') and (IndexText(Value, AConfigs) < 0) then
      AConfigs := AConfigs + [Value];
  end
  else if (AElement.Name = 'Platform') and AElement.HasAttribute('value') then
  begin
    Value := Trim(AElement.Attribute('value'));
    if SameText(Trim(AElement.Text), 'True') and (Value <> '') and (IndexText(Value, APlatforms) < 0) then
      APlatforms := APlatforms + [Value];
  end;
  for Index := 0 to AElement.ChildCount - 1 do
    CollectTargets(AElement[Index], AConfigs, APlatforms);
end;

{ TDprojReader }

class function TDprojReader.Read(const AFileName, AText: string; const AOptions: TDprojOptions): TProjectInfo;
var
  Root: TXmlElement;
  Group: TXmlElement;
  Item: TXmlElement;
  Properties: TMSBuildProperties;
  Variable: TPair<string, string>;
  GroupIndex: Integer;
  ItemIndex: Integer;
  Directory: string;
  Units: TList<TProjectUnit>;
  ProjectUnit: TProjectUnit;
  Include: string;
begin
  try
    Root := TXmlReader.Parse(AText);
  except
    on E: EXmlError do
      raise EProjectError.CreateFmt('%s: %s', [AFileName, E.Message]);
  end;
  Directory := TProjectPaths.DirectoryOf(AFileName);
  Properties := TMSBuildProperties.Create(AOptions.FileExists);
  Units := TList<TProjectUnit>.Create;
  try
    if Root.Name <> 'Project' then
      raise EProjectError.CreateFmt('%s: Wurzelelement <Project> erwartet', [AFileName]);
    for Variable in AOptions.Variables do
      Properties.SetValue(Variable.Key, Variable.Value);
    Properties.SetValue('MSBuildProjectDirectory', Directory);
    Properties.SetValue('MSBuildProjectName', TProjectPaths.BaseName(AFileName));
    if AOptions.Config <> '' then
      Properties.SetValue('Config', AOptions.Config);
    if AOptions.Platform <> '' then
      Properties.SetValue('Platform', AOptions.Platform);

    for GroupIndex := 0 to Root.ChildCount - 1 do
    begin
      Group := Root[GroupIndex];
      if not Properties.Evaluate(Group.Attribute('Condition')) then
        Continue;
      if Group.Name = 'PropertyGroup' then
      begin
        for ItemIndex := 0 to Group.ChildCount - 1 do
        begin
          Item := Group[ItemIndex];
          // Vorgegebene Konfiguration und Plattform haben Vorrang vor den Vorgaben der Datei.
          if ((AOptions.Config <> '') and SameText(Item.Name, 'Config')) or
            ((AOptions.Platform <> '') and SameText(Item.Name, 'Platform')) then
            Continue;
          if Properties.Evaluate(Item.Attribute('Condition')) then
            Properties.SetValue(Item.Name, Properties.Expand(Trim(Item.Text)));
        end;
      end
      else if Group.Name = 'ItemGroup' then
      begin
        for ItemIndex := 0 to Group.ChildCount - 1 do
        begin
          Item := Group[ItemIndex];
          if (Item.Name <> 'DCCReference') or not Properties.Evaluate(Item.Attribute('Condition')) then
            Continue;
          Include := Properties.Expand(Item.Attribute('Include'));
          if TProjectPaths.Extension(Include) <> '.pas' then
            Continue;
          ProjectUnit.Name := TProjectPaths.BaseName(Include);
          ProjectUnit.FileName := TProjectPaths.Combine(Directory, Include);
          Units.Add(ProjectUnit);
        end;
      end;
    end;

    Result.FileName := AFileName;
    if Properties.Get('MainSource') <> '' then
      Result.MainSource := TProjectPaths.Combine(Directory, Properties.Get('MainSource'))
    else
      Result.MainSource := '';
    Result.Config := Properties.Get('Config');
    Result.Platform := Properties.Get('Platform');
    Result.Defines := UniqueUpper(TProjectPaths.SplitList(Properties.Get('DCC_Define')));
    Result.SearchPaths := UniquePaths(Directory, TProjectPaths.SplitList(Properties.Get('DCC_UnitSearchPath')));
    Result.Namespaces := TProjectPaths.SplitList(Properties.Get('DCC_Namespace'));
    Result.Units := Units.ToArray;
    Result.Properties := Properties.ToArray;
    Result.Configs := nil;
    Result.Platforms := nil;
    CollectTargets(Root, Result.Configs, Result.Platforms);
  finally
    Units.Free;
    Properties.Free;
    Root.Free;
  end;
end;

class function TDprojReader.Load(const AFileName: string; const AOptions: TDprojOptions): TProjectInfo;
var
  FileFormat: TFileFormat;
begin
  Result := Read(AFileName, TFileEncoding.LoadFromFile(AFileName, FileFormat), AOptions);
end;

class function TDprojReader.CheckTarget(const AProject: TProjectInfo; const AConfig, APlatform: string): string;
begin
  Result := '';
  // Ohne Angaben in der Datei (ältere Projekte) wird nichts abgelehnt.
  if (AConfig <> '') and (Length(AProject.Configs) > 0) and (IndexText(AConfig, AProject.Configs) < 0) then
    Exit(Format('Konfiguration "%s" gibt es im Projekt nicht (vorhanden: %s).',
      [AConfig, string.Join(', ', AProject.Configs)]));
  if (APlatform <> '') and (Length(AProject.Platforms) > 0) and (IndexText(APlatform, AProject.Platforms) < 0) then
    Exit(Format('Plattform "%s" ist im Projekt nicht aktiviert (vorhanden: %s).',
      [APlatform, string.Join(', ', AProject.Platforms)]));
end;

end.
