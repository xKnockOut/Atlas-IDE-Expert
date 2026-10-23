unit Atlas.Core.Debug.IgnoreList;

// Exceptions, die Atlas beim Debuggen still fortsetzt (#517, #783), ohne VCL
// und Open Tools API:
//   - Klassen („Klasse künftig ignorieren“ im Exception-Verlauf, #517):
//     gelten für alle Projekte, Groß-/Kleinschreibung egal.
//   - Orte („Nur an dieser Stelle ignorieren“ in der Exception-Leiste, #783):
//     Klasse + Datei + Zeile je Projekt.
// Die Liste der IDE („Diese Exception-Klasse ignorieren“ in den
// Debugger-Optionen) bleibt unberührt; Atlas setzt still fort, indem es den
// Dialog der IDE mit „Fortsetzen“ schließt (Atlas.IDE.Debug.ExceptionDialog).
// Ablage %LOCALAPPDATA%\Atlas\debug-ignore.json über TAtlasDataFile (atomar,
// unbrauchbare Datei als .defekt daneben), Format 1:
//   {"format": 1, "classes": ["EConvertError"],
//    "locations": [{"project": "C:\\App\\App.dproj", "class": "EConvertError",
//                   "file": "C:\\App\\Unit1.pas", "line": 42}]}

interface

uses
  System.SysUtils;

type
  TAtlasDebugIgnoredLocation = record
    Project: string;
    ExceptionClass: string;
    FileName: string;
    /// <summary>1-basiert.</summary>
    Line: Integer;
    class function Create(const AProject, AClass, AFileName: string; ALine: Integer): TAtlasDebugIgnoredLocation;
      static;
    function Matches(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
  end;

  TAtlasDebugIgnoreList = record
  public const
    Format = 1;
    FileName = 'debug-ignore.json';
  public
    Classes: TArray<string>;
    Locations: TArray<TAtlasDebugIgnoredLocation>;
    class function Empty: TAtlasDebugIgnoreList; static;
    function IgnoresClass(const AClass: string): Boolean;
    /// <summary>True, wenn die Klasse neu dazukam.</summary>
    function AddClass(const AClass: string): Boolean;
    /// <summary>True, wenn die Klasse in der Liste stand.</summary>
    function RemoveClass(const AClass: string): Boolean;
    function IgnoresLocation(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
    function AddLocation(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
    function RemoveLocation(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
    /// <summary>Wird die Exception still fortgesetzt (Klasse oder Ort)?</summary>
    function Ignores(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
    /// <summary>Orte eines Projekts.</summary>
    function LocationsOf(const AProject: string): TArray<TAtlasDebugIgnoredLocation>;
    function ToJson: string;
    /// <summary>Liest das Format; AValid False bei unbrauchbarem Text. Unbrauchbare Einträge entfallen.</summary>
    class function Parse(const AText: string; out AValid: Boolean): TAtlasDebugIgnoreList; static;
    class function Load(const AFolder: string): TAtlasDebugIgnoreList; static;
    class function Save(const AFolder: string; const AList: TAtlasDebugIgnoreList): Boolean; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections,
  System.IOUtils,
  Atlas.Core.Files.DataFile;

function SamePath(const ALeft, ARight: string): Boolean;
begin
  Result := SameText(ExcludeTrailingPathDelimiter(ALeft), ExcludeTrailingPathDelimiter(ARight));
end;

{ TAtlasDebugIgnoredLocation }

class function TAtlasDebugIgnoredLocation.Create(const AProject, AClass, AFileName: string;
  ALine: Integer): TAtlasDebugIgnoredLocation;
begin
  Result.Project := AProject;
  Result.ExceptionClass := AClass;
  Result.FileName := AFileName;
  Result.Line := ALine;
end;

function TAtlasDebugIgnoredLocation.Matches(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
begin
  Result := (Line = ALine) and SameText(ExceptionClass, AClass) and SamePath(FileName, AFileName) and
    SamePath(Project, AProject);
end;

{ TAtlasDebugIgnoreList }

class function TAtlasDebugIgnoreList.Empty: TAtlasDebugIgnoreList;
begin
  Result.Classes := nil;
  Result.Locations := nil;
end;

function TAtlasDebugIgnoreList.IgnoresClass(const AClass: string): Boolean;
var
  Name: string;
begin
  for Name in Classes do
    if SameText(Name, AClass) then
      Exit(True);
  Result := False;
end;

function TAtlasDebugIgnoreList.AddClass(const AClass: string): Boolean;
begin
  Result := (Trim(AClass) <> '') and not IgnoresClass(AClass);
  if Result then
    Classes := Classes + [Trim(AClass)];
end;

function TAtlasDebugIgnoreList.RemoveClass(const AClass: string): Boolean;
var
  Index: Integer;
begin
  for Index := High(Classes) downto 0 do
    if SameText(Classes[Index], AClass) then
    begin
      Delete(Classes, Index, 1);
      Exit(True);
    end;
  Result := False;
end;

function TAtlasDebugIgnoreList.IgnoresLocation(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
var
  Location: TAtlasDebugIgnoredLocation;
begin
  for Location in Locations do
    if Location.Matches(AProject, AClass, AFileName, ALine) then
      Exit(True);
  Result := False;
end;

function TAtlasDebugIgnoreList.AddLocation(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
begin
  Result := (AClass <> '') and (AFileName <> '') and (ALine > 0) and
    not IgnoresLocation(AProject, AClass, AFileName, ALine);
  if Result then
    Locations := Locations + [TAtlasDebugIgnoredLocation.Create(AProject, AClass, AFileName, ALine)];
end;

function TAtlasDebugIgnoreList.RemoveLocation(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
var
  Index: Integer;
begin
  for Index := High(Locations) downto 0 do
    if Locations[Index].Matches(AProject, AClass, AFileName, ALine) then
    begin
      Delete(Locations, Index, 1);
      Exit(True);
    end;
  Result := False;
end;

function TAtlasDebugIgnoreList.Ignores(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
begin
  Result := IgnoresClass(AClass) or IgnoresLocation(AProject, AClass, AFileName, ALine);
end;

function TAtlasDebugIgnoreList.LocationsOf(const AProject: string): TArray<TAtlasDebugIgnoredLocation>;
var
  Location: TAtlasDebugIgnoredLocation;
begin
  Result := nil;
  for Location in Locations do
    if SamePath(Location.Project, AProject) then
      Result := Result + [Location];
end;

function TAtlasDebugIgnoreList.ToJson: string;
var
  Root, Item: TJSONObject;
  List: TJSONArray;
  Name: string;
  Location: TAtlasDebugIgnoredLocation;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('format', TJSONNumber.Create(Format));
    List := TJSONArray.Create;
    for Name in Classes do
      List.Add(Name);
    Root.AddPair('classes', List);
    List := TJSONArray.Create;
    for Location in Locations do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('project', Location.Project);
      Item.AddPair('class', Location.ExceptionClass);
      Item.AddPair('file', Location.FileName);
      Item.AddPair('line', TJSONNumber.Create(Location.Line));
      List.AddElement(Item);
    end;
    Root.AddPair('locations', List);
    Result := Root.Format(2);
  finally
    Root.Free;
  end;
end;

function StringOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value
  else
    Result := '';
end;

function IntegerOf(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt
  else
    Result := 0;
end;

class function TAtlasDebugIgnoreList.Parse(const AText: string; out AValid: Boolean): TAtlasDebugIgnoreList;
var
  Root: TJSONValue;
  Value: TJSONValue;
  Item: TJSONValue;
  Location: TJSONObject;
begin
  Result := Empty;
  AValid := False;
  Root := TJSONObject.ParseJSONValue(AText);
  try
    if not (Root is TJSONObject) then
      Exit;
    AValid := True;
    Value := TJSONObject(Root).GetValue('classes');
    if Value is TJSONArray then
      for Item in TJSONArray(Value) do
        if Item is TJSONString then
          Result.AddClass(TJSONString(Item).Value);
    Value := TJSONObject(Root).GetValue('locations');
    if Value is TJSONArray then
      for Item in TJSONArray(Value) do
        if Item is TJSONObject then
        begin
          Location := TJSONObject(Item);
          Result.AddLocation(StringOf(Location, 'project'), StringOf(Location, 'class'),
            StringOf(Location, 'file'), IntegerOf(Location, 'line'));
        end;
  finally
    Root.Free;
  end;
end;

class function TAtlasDebugIgnoreList.Load(const AFolder: string): TAtlasDebugIgnoreList;
var
  List: TAtlasDebugIgnoreList;
  Valid: Boolean;
begin
  Result := Empty;
  if AFolder = '' then
    Exit;
  List := Empty;
  Valid := False;
  if TAtlasDataFile.Load(TPath.Combine(AFolder, FileName), 'Exceptions ignorieren',
    function(const AText: string): Boolean
    begin
      List := Parse(AText, Valid);
      Result := Valid;
    end) = TAtlasDataLoad.Loaded then
    Result := List;
end;

class function TAtlasDebugIgnoreList.Save(const AFolder: string; const AList: TAtlasDebugIgnoreList): Boolean;
begin
  Result := False;
  if AFolder = '' then
    Exit;
  try
    TAtlasDataFile.Write(TPath.Combine(AFolder, FileName), AList.ToJson);
    Result := True;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Exceptions ignorieren', E);
  end;
end;

end.
