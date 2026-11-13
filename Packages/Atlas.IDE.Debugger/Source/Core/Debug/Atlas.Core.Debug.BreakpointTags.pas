unit Atlas.Core.Debug.BreakpointTags;

// Etiketten der Haltepunkte (#863), ohne VCL und Open Tools API: frei
// vergebbare Stichwörter („Import“, „Bug 4711“), mehrere je Haltepunkt.
// Etiketten sind persönlich: Ablage %LOCALAPPDATA%\Atlas\breakpoint-tags.json
// über TAtlasDataFile (atomar, unbrauchbare Datei als .defekt daneben), neben
// den anderen persönlichen Ablagen des Debuggers. Schlüssel ist Projekt,
// Datei und Zeile (ab 1); wandert ein Haltepunkt, nimmt Move seine Etiketten
// mit.
// Etiketten ohne Groß-/Kleinschreibung verglichen, ohne Leerraum am Rand und
// ohne Doppel; die erste Schreibweise bleibt. Ein Haltepunkt ohne Etiketten
// fällt aus der Ablage.
// Format 1:
//   {"format": 1,
//    "breakpoints": [{"project": "C:\\App\\App.dproj", "file": "C:\\App\\Kunde.pas",
//                     "line": 42, "tags": ["Import", "Bug 4711"]}]}
// Nicht threadsicher: Die IDE liest und schreibt nur im Hauptthread.

interface

uses
  System.SysUtils;

type
  TAtlasBreakpointTagEntry = record
    Project: string;
    FileName: string;
    /// <summary>Ab 1.</summary>
    Line: Integer;
    Tags: TArray<string>;
    function Matches(const AProject, AFileName: string; ALine: Integer): Boolean;
  end;

  TAtlasBreakpointTags = record
  public const
    cFormat = 1;
    cFileName = 'breakpoint-tags.json';
  public
    Entries: TArray<TAtlasBreakpointTagEntry>;
    class function Empty: TAtlasBreakpointTags; static;
    /// <summary>Trimmt und lässt leere Etiketten und Doppel (ohne Groß/klein) weg.</summary>
    class function Normalize(const ATags: TArray<string>): TArray<string>; static;
    function IndexOf(const AProject, AFileName: string; ALine: Integer): Integer;
    function TagsOf(const AProject, AFileName: string; ALine: Integer): TArray<string>;
    /// <summary>Ersetzt die Etiketten; True bei einer Änderung.</summary>
    function SetTags(const AProject, AFileName: string; ALine: Integer; const ATags: TArray<string>): Boolean;
    /// <summary>True, wenn das Etikett neu dazukam.</summary>
    function AddTag(const AProject, AFileName: string; ALine: Integer; const ATag: string): Boolean;
    /// <summary>True, wenn das Etikett am Haltepunkt stand.</summary>
    function RemoveTag(const AProject, AFileName: string; ALine: Integer; const ATag: string): Boolean;
    /// <summary>Haltepunkt gelöscht: Etiketten vergessen. True, wenn welche da waren.</summary>
    function Forget(const AProject, AFileName: string; ALine: Integer): Boolean;
    /// <summary>Haltepunkt gewandert: Etiketten mitnehmen (ersetzen die am Ziel). True bei einer Änderung.
    /// </summary>
    function Move(const AProject, AFromFile: string; AFromLine: Integer; const AToFile: string;
      AToLine: Integer): Boolean;
    /// <summary>Alle Etiketten eines Projekts, ohne Doppel, alphabetisch.</summary>
    function AllTags(const AProject: string): TArray<string>;
    /// <summary>Vervollständigung: Etiketten von AllTags, die mit APrefix beginnen (ohne Groß/klein), dann
    /// die, die APrefix enthalten.</summary>
    function Complete(const AProject, APrefix: string): TArray<string>;
    function ToJson: string;
    /// <summary>Liest das Format; AValid False bei unbrauchbarem Text. Unbrauchbare Einträge entfallen.</summary>
    class function Parse(const AText: string; out AValid: Boolean): TAtlasBreakpointTags; static;
    class function Load(const AFolder: string): TAtlasBreakpointTags; static;
    class function Save(const AFolder: string; const ATags: TAtlasBreakpointTags): Boolean; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  Atlas.Core.Files.DataFile,
  Atlas.Text.Json;

const
  cKind = 'Breakpoint tags';
  cKeyFormat = 'format';
  cKeyBreakpoints = 'breakpoints';
  cKeyProject = 'project';
  cKeyFile = 'file';
  cKeyLine = 'line';
  cKeyTags = 'tags';
  cJsonIndent = 2;

function SamePath(const ALeft, ARight: string): Boolean;
begin
  Result := SameText(ALeft.Replace('/', '\'), ARight.Replace('/', '\'));
end;

function IndexOfTag(const ATags: TArray<string>; const ATag: string): Integer;
begin
  for Result := 0 to High(ATags) do
  begin
    if SameText(ATags[Result], ATag) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function SameTags(const ALeft, ARight: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(ALeft) = Length(ARight);
  for mIndex := 0 to High(ALeft) do
  begin
    Result := Result and (ALeft[mIndex] = ARight[mIndex]);
  end;
end;

{ TAtlasBreakpointTagEntry }

function TAtlasBreakpointTagEntry.Matches(const AProject, AFileName: string; ALine: Integer): Boolean;
begin
  Result := (Line = ALine) and SamePath(FileName, AFileName) and SamePath(Project, AProject);
end;

{ TAtlasBreakpointTags }

class function TAtlasBreakpointTags.Empty: TAtlasBreakpointTags;
begin
  Result.Entries := nil;
end;

class function TAtlasBreakpointTags.Normalize(const ATags: TArray<string>): TArray<string>;
var
  mTag, mTrimmed: string;
begin
  Result := nil;
  for mTag in ATags do
  begin
    mTrimmed := Trim(mTag);
    if (mTrimmed <> '') and (IndexOfTag(Result, mTrimmed) < 0) then
    begin
      Result := Result + [mTrimmed];
    end;
  end;
end;

function TAtlasBreakpointTags.IndexOf(const AProject, AFileName: string; ALine: Integer): Integer;
begin
  for Result := 0 to High(Entries) do
  begin
    if Entries[Result].Matches(AProject, AFileName, ALine) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function TAtlasBreakpointTags.TagsOf(const AProject, AFileName: string; ALine: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := IndexOf(AProject, AFileName, ALine);
  if mIndex >= 0 then
  begin
    Result := Copy(Entries[mIndex].Tags);
  end;
end;

function TAtlasBreakpointTags.SetTags(const AProject, AFileName: string; ALine: Integer;
  const ATags: TArray<string>): Boolean;
var
  mIndex: Integer;
  mTags: TArray<string>;
  mEntry: TAtlasBreakpointTagEntry;
begin
  mTags := Normalize(ATags);
  mIndex := IndexOf(AProject, AFileName, ALine);
  if mIndex < 0 then
  begin
    Result := (Length(mTags) > 0) and (AFileName <> '') and (ALine > 0);
    if Result then
    begin
      mEntry.Project := AProject;
      mEntry.FileName := AFileName;
      mEntry.Line := ALine;
      mEntry.Tags := mTags;
      Entries := Entries + [mEntry];
    end;
    Exit;
  end;
  Result := not SameTags(Entries[mIndex].Tags, mTags);
  if Length(mTags) = 0 then
  begin
    Delete(Entries, mIndex, 1);
  end
  else
  begin
    Entries[mIndex].Tags := mTags;
  end;
end;

function TAtlasBreakpointTags.AddTag(const AProject, AFileName: string; ALine: Integer; const ATag: string): Boolean;
var
  mTags: TArray<string>;
begin
  mTags := TagsOf(AProject, AFileName, ALine);
  Result := (Trim(ATag) <> '') and (IndexOfTag(mTags, Trim(ATag)) < 0);
  if Result then
  begin
    Result := SetTags(AProject, AFileName, ALine, mTags + [ATag]);
  end;
end;

function TAtlasBreakpointTags.RemoveTag(const AProject, AFileName: string; ALine: Integer;
  const ATag: string): Boolean;
var
  mTags: TArray<string>;
  mIndex: Integer;
begin
  mTags := TagsOf(AProject, AFileName, ALine);
  mIndex := IndexOfTag(mTags, Trim(ATag));
  Result := mIndex >= 0;
  if Result then
  begin
    Delete(mTags, mIndex, 1);
    SetTags(AProject, AFileName, ALine, mTags);
  end;
end;

function TAtlasBreakpointTags.Forget(const AProject, AFileName: string; ALine: Integer): Boolean;
begin
  Result := SetTags(AProject, AFileName, ALine, nil);
end;

function TAtlasBreakpointTags.Move(const AProject, AFromFile: string; AFromLine: Integer; const AToFile: string;
  AToLine: Integer): Boolean;
var
  mTags: TArray<string>;
begin
  if SamePath(AFromFile, AToFile) and (AFromLine = AToLine) then
  begin
    Exit(False);
  end;
  mTags := TagsOf(AProject, AFromFile, AFromLine);
  Result := Length(mTags) > 0;
  if Result then
  begin
    Forget(AProject, AFromFile, AFromLine);
    SetTags(AProject, AToFile, AToLine, mTags);
  end;
end;

function TAtlasBreakpointTags.AllTags(const AProject: string): TArray<string>;
var
  mEntry: TAtlasBreakpointTagEntry;
  mTag: string;
begin
  Result := nil;
  for mEntry in Entries do
  begin
    if SamePath(mEntry.Project, AProject) then
    begin
      for mTag in mEntry.Tags do
      begin
        if IndexOfTag(Result, mTag) < 0 then
        begin
          Result := Result + [mTag];
        end;
      end;
    end;
  end;
  TArray.Sort<string>(Result, TComparer<string>.Construct(
    function(const ALeft, ARight: string): Integer
    begin
      Result := CompareText(ALeft, ARight);
      if Result = 0 then
      begin
        Result := CompareStr(ALeft, ARight);
      end;
    end));
end;

function TAtlasBreakpointTags.Complete(const AProject, APrefix: string): TArray<string>;
var
  mTag, mPrefix: string;
  mInside: TArray<string>;
begin
  Result := nil;
  mInside := nil;
  mPrefix := Trim(APrefix).ToLower;
  for mTag in AllTags(AProject) do
  begin
    if mTag.ToLower.StartsWith(mPrefix) then
    begin
      Result := Result + [mTag];
    end
    else if mTag.ToLower.Contains(mPrefix) then
    begin
      mInside := mInside + [mTag];
    end;
  end;
  Result := Result + mInside;
end;

function EntryJson(const AEntry: TAtlasBreakpointTagEntry): TJSONObject;
var
  mList: TJSONArray;
  mTag: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair(cKeyProject, AEntry.Project);
  Result.AddPair(cKeyFile, AEntry.FileName);
  Result.AddPair(cKeyLine, TJSONNumber.Create(AEntry.Line));
  mList := TJSONArray.Create;
  for mTag in AEntry.Tags do
  begin
    mList.Add(mTag);
  end;
  Result.AddPair(cKeyTags, mList);
end;

function TAtlasBreakpointTags.ToJson: string;
var
  mRoot: TJSONObject;
  mList: TJSONArray;
  mEntry: TAtlasBreakpointTagEntry;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair(cKeyFormat, TJSONNumber.Create(cFormat));
    mList := TJSONArray.Create;
    for mEntry in Entries do
    begin
      mList.AddElement(EntryJson(mEntry));
    end;
    mRoot.AddPair(cKeyBreakpoints, mList);
    Result := mRoot.Format(cJsonIndent);
  finally
    mRoot.Free;
  end;
end;

function TagsJson(AObject: TJSONObject): TArray<string>;
var
  mValue, mItem: TJSONValue;
begin
  Result := nil;
  mValue := AObject.GetValue(cKeyTags);
  if not (mValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mValue) do
  begin
    // Zahlen erben in Delphi 12 und FPC noch von TJSONString: ausdrücklich ausschließen.
    if (mItem is TJSONString) and not (mItem is TJSONNumber) then
    begin
      Result := Result + [TJSONString(mItem).Value];
    end;
  end;
end;

procedure ParseEntry(AItem: TJSONValue; var ATags: TAtlasBreakpointTags);
var
  mObject: TJSONObject;
begin
  if not (AItem is TJSONObject) then
  begin
    Exit;
  end;
  mObject := TJSONObject(AItem);
  ATags.SetTags(TJsonRead.Text(mObject, cKeyProject), TJsonRead.Text(mObject, cKeyFile),
    TJsonRead.Int(mObject, cKeyLine), TagsJson(mObject));
end;

class function TAtlasBreakpointTags.Parse(const AText: string; out AValid: Boolean): TAtlasBreakpointTags;
var
  mRoot, mValue, mItem: TJSONValue;
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
    mValue := TJSONObject(mRoot).GetValue(cKeyBreakpoints);
    if mValue is TJSONArray then
    begin
      for mItem in TJSONArray(mValue) do
      begin
        ParseEntry(mItem, Result);
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasBreakpointTags.Load(const AFolder: string): TAtlasBreakpointTags;
var
  mTags: TAtlasBreakpointTags;
  mValid: Boolean;
begin
  Result := Empty;
  if AFolder = '' then
  begin
    Exit;
  end;
  mTags := Empty;
  mValid := False;
  if TAtlasDataFile.Load(TPath.Combine(AFolder, cFileName), cKind,
    function(const AText: string): Boolean
    begin
      mTags := Parse(AText, mValid);
      Result := mValid;
    end) = TAtlasDataLoad.Loaded then
  begin
    Result := mTags;
  end;
end;

class function TAtlasBreakpointTags.Save(const AFolder: string; const ATags: TAtlasBreakpointTags): Boolean;
begin
  Result := False;
  if AFolder = '' then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(TPath.Combine(AFolder, cFileName), ATags.ToJson);
    Result := True;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cKind, E);
  end;
end;

end.
