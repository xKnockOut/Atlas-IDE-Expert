unit Atlas.Common.Projects.GroupReader;

// Liest die Projekte einer Projektgruppe (.groupproj, #648). Die Datei ist ein
// MSBuild-Projekt; jedes Projekt steht als <Projects Include="…"> in einer
// ItemGroup, relativ zum Ordner der Gruppe. Übernommen werden nur
// Delphi-Projekte (.dproj), in Dateireihenfolge und ohne Duplikate.

interface

uses
  System.SysUtils;

type
  TGroupProjReader = class
  public
    /// <summary>Absolute Pfade der Delphi-Projekte aus AText der Gruppe AFileName. EProjectError bei ungültigem
    /// XML.</summary>
    class function Read(const AFileName, AText: string): TArray<string>; static;
    /// <summary>Liest die Datei von der Platte (Kodierung wird erkannt) und wertet sie aus.</summary>
    class function Load(const AFileName: string): TArray<string>; static;
  end;

implementation

uses
  Atlas.Common.Projects.Contract,
  System.Generics.Collections,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Projects.Internals.Xml,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TGroupReaderText = (RootElementProjectExpected);

const
  cTexts: array[TGroupReaderText] of TAtlasText = (
    (De: '%s: Wurzelelement <Project> erwartet'; En: '%s: root element <Project> expected'));

{$SCOPEDENUMS OFF}

/// <summary>Projekte (.dproj) aus einer ItemGroup, relativ zu ADirectory aufgelöst und je Datei einmal.</summary>
procedure AddProjects(AGroup: TXmlElement; const ADirectory: string; AFound: TList<string>;
  ASeen: TDictionary<string, Boolean>);
var
  mIndex: Integer;
  mItem: TXmlElement;
  mInclude, mFileName: string;
begin
  for mIndex := 0 to AGroup.ChildCount - 1 do
  begin
    mItem := AGroup[mIndex];
    mInclude := Trim(mItem.Attribute('Include'));
    if (mItem.Name <> 'Projects') or not SameText(TProjectPaths.Extension(mInclude), '.dproj') then
    begin
      Continue;
    end;
    mFileName := TProjectPaths.Combine(ADirectory, mInclude);
    if not ASeen.ContainsKey(AnsiUpperCase(mFileName)) then
    begin
      ASeen.Add(AnsiUpperCase(mFileName), True);
      AFound.Add(mFileName);
    end;
  end;
end;

class function TGroupProjReader.Read(const AFileName, AText: string): TArray<string>;
var
  mRoot: TXmlElement;
  mIndex: Integer;
  mDirectory: string;
  mFound: TList<string>;
  mSeen: TDictionary<string, Boolean>;
begin
  try
    mRoot := TXmlReader.Parse(AText);
  except
    on E: EXmlError do
      raise EProjectError.CreateFmt('%s: %s', [AFileName, E.Message]);
  end;
  mDirectory := TProjectPaths.DirectoryOf(AFileName);
  mFound := TList<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    if mRoot.Name <> 'Project' then
    begin
      raise EProjectError.CreateFmt(cTexts[TGroupReaderText.RootElementProjectExpected].Text, [AFileName]);
    end;
    for mIndex := 0 to mRoot.ChildCount - 1 do
    begin
      if mRoot[mIndex].Name = 'ItemGroup' then
      begin
        AddProjects(mRoot[mIndex], mDirectory, mFound, mSeen);
      end;
    end;
    Result := mFound.ToArray;
  finally
    mSeen.Free;
    mFound.Free;
    mRoot.Free;
  end;
end;

class function TGroupProjReader.Load(const AFileName: string): TArray<string>;
var
  mFileFormat: TFileFormat;
begin
  Result := Read(AFileName, TFileEncoding.LoadFromFile(AFileName, mFileFormat));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Projects.GroupReader', cTexts);

end.
