unit Atlas.Common.Projects.GroupReader;

// Liest die Projekte einer Projektgruppe (.groupproj, #648). Die Datei ist ein
// MSBuild-Projekt; jedes Projekt steht als <Projects Include="…"> in einer
// ItemGroup, relativ zum Ordner der Gruppe. Übernommen werden nur
// Delphi-Projekte (.dproj), in Dateireihenfolge und ohne Duplikate.

interface

uses
  System.SysUtils,
  Atlas.Common.Projects.Contract;

type
  TGroupProjReader = class
  public
    /// <summary>Absolute Pfade der Delphi-Projekte aus AText der Gruppe AFileName. EProjectError bei ungültigem XML.</summary>
    class function Read(const AFileName, AText: string): TArray<string>; static;
    /// <summary>Liest die Datei von der Platte (Kodierung wird erkannt) und wertet sie aus.</summary>
    class function Load(const AFileName: string): TArray<string>; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Projects.Internals.Xml;

class function TGroupProjReader.Read(const AFileName, AText: string): TArray<string>;
var
  Root, Group, Item: TXmlElement;
  GroupIndex, ItemIndex: Integer;
  Directory, Include, FileName: string;
  Found: TList<string>;
  Seen: TDictionary<string, Boolean>;
begin
  try
    Root := TXmlReader.Parse(AText);
  except
    on E: EXmlError do
      raise EProjectError.CreateFmt('%s: %s', [AFileName, E.Message]);
  end;
  Directory := TProjectPaths.DirectoryOf(AFileName);
  Found := TList<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    if Root.Name <> 'Project' then
      raise EProjectError.CreateFmt('%s: Wurzelelement <Project> erwartet', [AFileName]);
    for GroupIndex := 0 to Root.ChildCount - 1 do
    begin
      Group := Root[GroupIndex];
      if Group.Name <> 'ItemGroup' then
        Continue;
      for ItemIndex := 0 to Group.ChildCount - 1 do
      begin
        Item := Group[ItemIndex];
        if Item.Name <> 'Projects' then
          Continue;
        Include := Trim(Item.Attribute('Include'));
        if not SameText(TProjectPaths.Extension(Include), '.dproj') then
          Continue;
        FileName := TProjectPaths.Combine(Directory, Include);
        if Seen.ContainsKey(AnsiUpperCase(FileName)) then
          Continue;
        Seen.Add(AnsiUpperCase(FileName), True);
        Found.Add(FileName);
      end;
    end;
    Result := Found.ToArray;
  finally
    Seen.Free;
    Found.Free;
    Root.Free;
  end;
end;

class function TGroupProjReader.Load(const AFileName: string): TArray<string>;
var
  FileFormat: TFileFormat;
begin
  Result := Read(AFileName, TFileEncoding.LoadFromFile(AFileName, FileFormat));
end;

end.
