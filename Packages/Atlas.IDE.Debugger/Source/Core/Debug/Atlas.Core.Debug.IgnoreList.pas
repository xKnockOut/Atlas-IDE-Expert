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
    cFormat = 1;
    cFileName = 'debug-ignore.json';
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
  Atlas.Core.Files.DataFile,
  Atlas.Text.Json;

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
  mName: string;
begin
  for mName in Classes do
  begin
    if SameText(mName, AClass) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasDebugIgnoreList.AddClass(const AClass: string): Boolean;
begin
  Result := (Trim(AClass) <> '') and not IgnoresClass(AClass);
  if Result then
  begin
    Classes := Classes + [Trim(AClass)];
  end;
end;

function TAtlasDebugIgnoreList.RemoveClass(const AClass: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := High(Classes) downto 0 do
  begin
    if SameText(Classes[mIndex], AClass) then
    begin
      Delete(Classes, mIndex, 1);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasDebugIgnoreList.IgnoresLocation(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
var
  mLocation: TAtlasDebugIgnoredLocation;
begin
  for mLocation in Locations do
  begin
    if mLocation.Matches(AProject, AClass, AFileName, ALine) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasDebugIgnoreList.AddLocation(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
begin
  Result := (AClass <> '') and (AFileName <> '') and (ALine > 0) and
    not IgnoresLocation(AProject, AClass, AFileName, ALine);
  if Result then
  begin
    Locations := Locations + [TAtlasDebugIgnoredLocation.Create(AProject, AClass, AFileName, ALine)];
  end;
end;

function TAtlasDebugIgnoreList.RemoveLocation(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := High(Locations) downto 0 do
  begin
    if Locations[mIndex].Matches(AProject, AClass, AFileName, ALine) then
    begin
      Delete(Locations, mIndex, 1);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasDebugIgnoreList.Ignores(const AProject, AClass, AFileName: string; ALine: Integer): Boolean;
begin
  Result := IgnoresClass(AClass) or IgnoresLocation(AProject, AClass, AFileName, ALine);
end;

function TAtlasDebugIgnoreList.LocationsOf(const AProject: string): TArray<TAtlasDebugIgnoredLocation>;
var
  mLocation: TAtlasDebugIgnoredLocation;
begin
  Result := nil;
  for mLocation in Locations do
  begin
    if SamePath(mLocation.Project, AProject) then
    begin
      Result := Result + [mLocation];
    end;
  end;
end;

function TAtlasDebugIgnoreList.ToJson: string;
var
  mRoot, mItem: TJSONObject;
  mList: TJSONArray;
  mName: string;
  mLocation: TAtlasDebugIgnoredLocation;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mList := TJSONArray.Create;
    for mName in Classes do
    begin
      mList.Add(mName);
    end;
    mRoot.AddPair('classes', mList);
    mList := TJSONArray.Create;
    for mLocation in Locations do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('project', mLocation.Project);
      mItem.AddPair('class', mLocation.ExceptionClass);
      mItem.AddPair('file', mLocation.FileName);
      mItem.AddPair('line', TJSONNumber.Create(mLocation.Line));
      mList.AddElement(mItem);
    end;
    mRoot.AddPair('locations', mList);
    Result := mRoot.Format(2);
  finally
    mRoot.Free;
  end;
end;

class function TAtlasDebugIgnoreList.Parse(const AText: string; out AValid: Boolean): TAtlasDebugIgnoreList;
var
  mRoot: TJSONValue;
  mValue: TJSONValue;
  mItem: TJSONValue;
  mLocation: TJSONObject;
begin
  Result := Empty;
  AValid := False;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    AValid := True;
    mValue := TJSONObject(mRoot).GetValue('classes');
    if mValue is TJSONArray then
    begin
      for mItem in TJSONArray(mValue) do
      begin
        if mItem is TJSONString then
        begin
          Result.AddClass(TJSONString(mItem).Value);
        end;
      end;
    end;
    mValue := TJSONObject(mRoot).GetValue('locations');
    if mValue is TJSONArray then
    begin
      for mItem in TJSONArray(mValue) do
      begin
        if mItem is TJSONObject then
        begin
          mLocation := TJSONObject(mItem);
          Result.AddLocation(TJsonRead.Text(mLocation, 'project'), TJsonRead.Text(mLocation, 'class'),
            TJsonRead.Text(mLocation, 'file'), TJsonRead.Int(mLocation, 'line'));
        end;
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasDebugIgnoreList.Load(const AFolder: string): TAtlasDebugIgnoreList;
var
  mList: TAtlasDebugIgnoreList;
  mValid: Boolean;
begin
  Result := Empty;
  if AFolder = '' then
  begin
    Exit;
  end;
  mList := Empty;
  mValid := False;
  if TAtlasDataFile.Load(TPath.Combine(AFolder, cFileName), 'Exceptions ignorieren',
    function(const AText: string): Boolean
    begin
      mList := Parse(AText, mValid);
      Result := mValid;
    end) = TAtlasDataLoad.Loaded then
  begin
    Result := mList;
  end;
end;

class function TAtlasDebugIgnoreList.Save(const AFolder: string; const AList: TAtlasDebugIgnoreList): Boolean;
begin
  Result := False;
  if AFolder = '' then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(TPath.Combine(AFolder, cFileName), AList.ToJson);
    Result := True;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Exceptions ignorieren', E);
  end;
end;

end.
