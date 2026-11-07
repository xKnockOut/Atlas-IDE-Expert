unit Atlas.Common.Projects.DprojReader;

// Wertet eine .dproj-Datei für eine Konfiguration und Plattform aus.
//
// Die Datei ist ein MSBuild-Projekt. Ausgewertet werden die PropertyGroups
// und ItemGroups der obersten Ebene in Dateireihenfolge, mit Bedingungen und
// $(Name)-Verweisen; Imports (CodeGear.Delphi.Targets) werden nicht geladen.
// Das genügt für Suchpfade, Defines, Namespaces und Hauptdatei, weil die IDE
// diese Werte vollständig in die .dproj schreibt.
// Für jedes Symbol in DCC_Define merkt sich der Reader, welche Ebene es
// hinzugefügt hat (#102): Base, Base_<Plattform>, Cfg_n oder Cfg_n_<Plattform>
// aus der Bedingung der PropertyGroup.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract;

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
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Projects.Internals.Xml,
  Atlas.Common.Projects.Internals.MSBuild,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDprojReaderText = (ConfigurationDoesNotExistIn, PlatformIsNotActivatedIn, Project, Configuration, Platform,
    RootElementProjectExpected);

const
  cTexts: array[TDprojReaderText] of TAtlasText = (
    (De: 'Konfiguration "%s" gibt es im Projekt nicht (vorhanden: %s).';
     En: 'Configuration "%s" does not exist in the project (available: %s).'),
    (De: 'Plattform "%s" ist im Projekt nicht aktiviert (vorhanden: %s).';
     En: 'Platform "%s" is not activated in the project (available: %s).'),
    (De: 'Projekt'; En: 'Project'),
    (De: 'Konfiguration'; En: 'Configuration'),
    (De: ', Plattform '; En: ', platform '),
    (De: '%s: Wurzelelement <Project> erwartet'; En: '%s: root element <Project> expected'));

{$SCOPEDENUMS OFF}

function UniqueUpper(const AItems: TArray<string>): TArray<string>;
var
  mItems: TList<string>;
  mItem: string;
begin
  mItems := TList<string>.Create;
  try
    for mItem in AItems do
    begin
      if not mItems.Contains(UpperCase(mItem)) then
      begin
        mItems.Add(UpperCase(mItem));
      end;
    end;
    Result := mItems.ToArray;
  finally
    mItems.Free;
  end;
end;

function UniquePaths(const ABase: string; const AItems: TArray<string>): TArray<string>;
var
  mItems: TList<string>;
  mItem: string;
  mPath: string;
  mKnown: TList<string>;
begin
  mItems := TList<string>.Create;
  mKnown := TList<string>.Create;
  try
    for mItem in AItems do
    begin
      mPath := TProjectPaths.Combine(ABase, mItem);
      if not mKnown.Contains(LowerCase(mPath)) then
      begin
        mKnown.Add(LowerCase(mPath));
        mItems.Add(mPath);
      end;
    end;
    Result := mItems.ToArray;
  finally
    mKnown.Free;
    mItems.Free;
  end;
end;

/// <summary>Ebene einer PropertyGroup aus ihrer Bedingung, z. B. "'$(Cfg_1_Win64)'!=''" →
/// "Konfiguration Debug, Plattform Win64"; ohne Ebene "Projekt".</summary>
function LevelOf(const ACondition, AConfig: string): string;
var
  mStart, mStop: Integer;
  mName, mPlatform: string;
begin
  Result := cTexts[TDprojReaderText.Project].Text;
  mStart := Pos('$(Base', ACondition);
  if mStart = 0 then
  begin
    mStart := Pos('$(Cfg_', ACondition);
  end;
  if mStart = 0 then
  begin
    Exit;
  end;
  mStop := PosEx(')', ACondition, mStart);
  if mStop = 0 then
  begin
    Exit;
  end;
  mName := Copy(ACondition, mStart + 2, mStop - mStart - 2);
  mPlatform := '';
  if StartsText('Base_', mName) then
  begin
    mPlatform := Copy(mName, 6, MaxInt);
  end
  else if StartsText('Cfg_', mName) and (PosEx('_', mName, 5) > 0) then
  begin
    mPlatform := Copy(mName, PosEx('_', mName, 5) + 1, MaxInt);
  end;
  if StartsText('Cfg_', mName) then
  begin
    Result := cTexts[TDprojReaderText.Configuration].Text;
    if AConfig <> '' then
    begin
      Result := Result + ' ' + AConfig;
    end;
  end;
  if mPlatform <> '' then
  begin
    Result := Result + cTexts[TDprojReaderText.Platform].Text + mPlatform;
  end;
end;

/// <summary>Sammelt Konfigurationen und aktivierte Plattformen aus dem ganzen Baum.</summary>
procedure CollectTargets(AElement: TXmlElement; var AConfigs, APlatforms: TArray<string>);
var
  mIndex: Integer;
  mValue: string;
begin
  if AElement.Name = 'BuildConfiguration' then
  begin
    mValue := Trim(AElement.Attribute('Include'));
    if (mValue <> '') and not SameText(mValue, 'Base') and (IndexText(mValue, AConfigs) < 0) then
    begin
      AConfigs := AConfigs + [mValue];
    end;
  end
  else if (AElement.Name = 'Platform') and AElement.HasAttribute('value') then
  begin
    mValue := Trim(AElement.Attribute('value'));
    if SameText(Trim(AElement.Text), 'True') and (mValue <> '') and (IndexText(mValue, APlatforms) < 0) then
    begin
      APlatforms := APlatforms + [mValue];
    end;
  end;
  for mIndex := 0 to AElement.ChildCount - 1 do
  begin
    CollectTargets(AElement[mIndex], AConfigs, APlatforms);
  end;
end;

type
  /// <summary>Zustand beim Auswerten einer .dproj.</summary>
  TDprojState = record
    Options: TDprojOptions;
    Directory: string;
    Properties: TMSBuildProperties;
    Units: TList<TProjectUnit>;
    Origins: TList<TPair<string, string>>;
  end;

procedure PresetProperties(const AState: TDprojState; const AFileName: string);
var
  mVariable: TPair<string, string>;
begin
  for mVariable in AState.Options.Variables do
  begin
    AState.Properties.SetValue(mVariable.Key, mVariable.Value);
  end;
  AState.Properties.SetValue('MSBuildProjectDirectory', AState.Directory);
  AState.Properties.SetValue('MSBuildProjectName', TProjectPaths.BaseName(AFileName));
  if AState.Options.Config <> '' then
  begin
    AState.Properties.SetValue('Config', AState.Options.Config);
  end;
  if AState.Options.Platform <> '' then
  begin
    AState.Properties.SetValue('Platform', AState.Options.Platform);
  end;
end;

function Defines(const AState: TDprojState): TArray<string>;
begin
  Result := UniqueUpper(TProjectPaths.SplitList(AState.Properties.Get('DCC_Define')));
end;

/// <summary>Übernimmt die Eigenschaft AItem der PropertyGroup AGroup; neue Symbole in DCC_Define merkt sich der
/// Reader mit ihrer Ebene (#102).</summary>
procedure ReadProperty(const AState: TDprojState; AGroup, AItem: TXmlElement);
var
  mBefore: TArray<string>;
  mDefine: string;
  mIsDefine: Boolean;
begin
  // Vorgegebene Konfiguration und Plattform haben Vorrang vor den Vorgaben der Datei.
  if ((AState.Options.Config <> '') and SameText(AItem.Name, 'Config')) or
    ((AState.Options.Platform <> '') and SameText(AItem.Name, 'Platform')) or
    not AState.Properties.Evaluate(AItem.Attribute('Condition')) then
  begin
    Exit;
  end;
  mIsDefine := SameText(AItem.Name, 'DCC_Define');
  mBefore := nil;
  if mIsDefine then
  begin
    mBefore := Defines(AState);
  end;
  AState.Properties.SetValue(AItem.Name, AState.Properties.Expand(Trim(AItem.Text)));
  if not mIsDefine then
  begin
    Exit;
  end;
  for mDefine in Defines(AState) do
  begin
    if IndexStr(mDefine, mBefore) < 0 then
    begin
      AState.Origins.Add(TPair<string, string>.Create(mDefine,
        LevelOf(AGroup.Attribute('Condition'), AState.Properties.Get('Config'))));
    end;
  end;
end;

/// <summary>Übernimmt die Units (DCCReference auf .pas) einer ItemGroup.</summary>
procedure ReadItems(const AState: TDprojState; AGroup: TXmlElement);
var
  mIndex: Integer;
  mItem: TXmlElement;
  mInclude: string;
  mUnit: TProjectUnit;
begin
  for mIndex := 0 to AGroup.ChildCount - 1 do
  begin
    mItem := AGroup[mIndex];
    if (mItem.Name <> 'DCCReference') or not AState.Properties.Evaluate(mItem.Attribute('Condition')) then
    begin
      Continue;
    end;
    mInclude := AState.Properties.Expand(mItem.Attribute('Include'));
    if TProjectPaths.Extension(mInclude) = '.pas' then
    begin
      mUnit.Name := TProjectPaths.BaseName(mInclude);
      mUnit.FileName := TProjectPaths.Combine(AState.Directory, mInclude);
      AState.Units.Add(mUnit);
    end;
  end;
end;

procedure ReadGroups(const AState: TDprojState; ARoot: TXmlElement);
var
  mIndex, mItem: Integer;
  mGroup: TXmlElement;
begin
  for mIndex := 0 to ARoot.ChildCount - 1 do
  begin
    mGroup := ARoot[mIndex];
    if not AState.Properties.Evaluate(mGroup.Attribute('Condition')) then
    begin
      Continue;
    end;
    if mGroup.Name = 'PropertyGroup' then
    begin
      for mItem := 0 to mGroup.ChildCount - 1 do
      begin
        ReadProperty(AState, mGroup, mGroup[mItem]);
      end;
    end
    else if mGroup.Name = 'ItemGroup' then
    begin
      ReadItems(AState, mGroup);
    end;
  end;
end;

function ProjectInfo(const AState: TDprojState; const AFileName: string; ARoot: TXmlElement): TProjectInfo;
begin
  Result.FileName := AFileName;
  Result.MainSource := '';
  if AState.Properties.Get('MainSource') <> '' then
  begin
    Result.MainSource := TProjectPaths.Combine(AState.Directory, AState.Properties.Get('MainSource'));
  end;
  Result.Config := AState.Properties.Get('Config');
  Result.Platform := AState.Properties.Get('Platform');
  Result.Defines := Defines(AState);
  Result.DefineOrigins := AState.Origins.ToArray;
  Result.SearchPaths := UniquePaths(AState.Directory,
    TProjectPaths.SplitList(AState.Properties.Get('DCC_UnitSearchPath')));
  Result.Namespaces := TProjectPaths.SplitList(AState.Properties.Get('DCC_Namespace'));
  Result.Units := AState.Units.ToArray;
  Result.Properties := AState.Properties.ToArray;
  Result.Configs := nil;
  Result.Platforms := nil;
  CollectTargets(ARoot, Result.Configs, Result.Platforms);
end;

{ TDprojReader }

class function TDprojReader.Read(const AFileName, AText: string; const AOptions: TDprojOptions): TProjectInfo;
var
  mRoot: TXmlElement;
  mState: TDprojState;
begin
  try
    mRoot := TXmlReader.Parse(AText);
  except
    on E: EXmlError do
      raise EProjectError.CreateFmt('%s: %s', [AFileName, E.Message]);
  end;
  mState.Options := AOptions;
  mState.Directory := TProjectPaths.DirectoryOf(AFileName);
  mState.Properties := TMSBuildProperties.Create(AOptions.FileExists);
  mState.Units := TList<TProjectUnit>.Create;
  mState.Origins := TList<TPair<string, string>>.Create;
  try
    if mRoot.Name <> 'Project' then
    begin
      raise EProjectError.CreateFmt(cTexts[TDprojReaderText.RootElementProjectExpected].Text, [AFileName]);
    end;
    PresetProperties(mState, AFileName);
    ReadGroups(mState, mRoot);
    Result := ProjectInfo(mState, AFileName, mRoot);
  finally
    mState.Origins.Free;
    mState.Units.Free;
    mState.Properties.Free;
    mRoot.Free;
  end;
end;

class function TDprojReader.Load(const AFileName: string; const AOptions: TDprojOptions): TProjectInfo;
var
  mFileFormat: TFileFormat;
begin
  Result := Read(AFileName, TFileEncoding.LoadFromFile(AFileName, mFileFormat), AOptions);
end;

class function TDprojReader.CheckTarget(const AProject: TProjectInfo; const AConfig, APlatform: string): string;
begin
  Result := '';
  // Ohne Angaben in der Datei (ältere Projekte) wird nichts abgelehnt.
  if (AConfig <> '') and (Length(AProject.Configs) > 0) and (IndexText(AConfig, AProject.Configs) < 0) then
  begin
    Exit(cTexts[TDprojReaderText.ConfigurationDoesNotExistIn].Fmt([AConfig, string.Join(', ', AProject.Configs)]));
  end;
  if (APlatform <> '') and (Length(AProject.Platforms) > 0) and (IndexText(APlatform, AProject.Platforms) < 0) then
  begin
    Exit(cTexts[TDprojReaderText.PlatformIsNotActivatedIn].Fmt([APlatform, string.Join(', ', AProject.Platforms)]));
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Projects.DprojReader', cTexts);

end.
