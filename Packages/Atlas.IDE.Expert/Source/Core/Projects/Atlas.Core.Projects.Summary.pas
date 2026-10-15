unit Atlas.Core.Projects.Summary;

// Projekt-Zusammenfassung (#592), ohne VCL und Open Tools API: je Projekt
// eine kleine JSON-Datei mit dem, was Atlas zuletzt über das Projekt wusste.
// Die Willkommensseite liest nur diese Dateien und startet keinen Server;
// spätere Bereiche (#755 Weiterarbeiten, #758 Projektverlauf, #762, #763,
// #764) bauen darauf auf.
//
// Ablage: %LOCALAPPDATA%\Atlas\projects\<schlüssel>.json. Der Schlüssel ist
// FNV-1a (64 Bit) über die UTF-16-Codeeinheiten (je zwei Bytes, niedriges
// zuerst) des normierten Projektpfads, als 16 Hexziffern klein geschrieben.
// Normiert: ohne Leerraum am Rand, „/“ wird „\“, ASCII-Buchstaben groß.
// Beispiel: "C:\Projekte\Demo.dproj" → siehe Tests (KeyOf).
//
// Format 1 (UTF-8 ohne BOM; Zeiten in UTC als "2026-10-15T09:30:00Z"):
//   {
//     "format": 1,
//     "project": "C:\\Projekte\\Demo.dproj",
//     "lastOpened": "…", "lastClosed": "…",   // fehlt = unbekannt
//     "hidden": true,                           // nur, wenn aus der Liste entfernt
//     "vcs": {"at": "…", "kind": "git|svn|none", "branch": "main",
//             "revision": "…", "changed": 3, "ahead": 1, "behind": 0},
//     "build": {"at": "…", "kind": "build|make|check|…", "configuration": "Debug",
//               "platform": "Win32", "succeeded": true, "errors": 0,
//               "warnings": 0, "hints": 0, "first": {…}},
//     "check": {"at": "…", "errors": 2, "first": {"file": "…", "line": 12,
//               "column": 5, "code": "E2003", "text": "…"}},
//     "rules": {"at": "…", "newHits": 3}
//   }
// "changed", "ahead", "behind" = -1: unbekannt. "first" ist die erste Fehler-
// meldung (Zeile und Spalte ab 1). "build" ist der letzte Lauf des Benutzers,
// "check" die letzte Hintergrundprüfung (#548), "rules" neue Regeltreffer
// gegenüber der Baseline (#97, nur wenn bekannt).
//
// Erweitern: Neue Felder und Abschnitte dürfen jederzeit dazukommen, ohne
// "format" zu erhöhen. Leser übergehen, was sie nicht kennen; Schreiber
// behalten es (auch innerhalb bekannter Abschnitte, z. B. "build.metrics"
// aus #758). "format" steigt nur bei einer inkompatiblen Änderung; eine
// Datei mit höherem "format" liest diese Fassung nicht und überschreibt sie
// nicht.
// Nicht threadsicher je Datei: Die IDE schreibt nur im Hauptthread.

interface

uses
  System.SysUtils;

type
  /// <summary>Stelle einer Meldung; Zeile und Spalte ab 1, 0 = ohne.</summary>
  TAtlasProjectLocation = record
    FileName: string;
    Line: Integer;
    Column: Integer;
    Code: string;
    Text: string;
    function IsEmpty: Boolean;
  end;

  /// <summary>Stand der Versionsverwaltung beim letzten Abfragen.</summary>
  TAtlasProjectVcs = record
    Known: Boolean;
    /// <summary>Zeitpunkt der Abfrage (UTC).</summary>
    At: TDateTime;
    /// <summary>"git", "svn" oder "none" (keine Arbeitskopie bzw. abgeschaltet).</summary>
    Kind: string;
    /// <summary>Git: Branch ('' bei losgelöstem HEAD); SVN: Pfad wie "trunk".</summary>
    Branch: string;
    Revision: string;
    /// <summary>Geänderte und neue Dateien; -1 unbekannt.</summary>
    Changed: Integer;
    /// <summary>Commits vor bzw. hinter dem Upstream; -1 unbekannt.</summary>
    Ahead: Integer;
    Behind: Integer;
    class function Empty: TAtlasProjectVcs; static;
    /// <summary>Gehört zu einer Arbeitskopie (Git oder SVN).</summary>
    function InWorkingCopy: Boolean;
  end;

  /// <summary>Letzter Build des Benutzers (#527).</summary>
  TAtlasProjectBuild = record
    Known: Boolean;
    At: TDateTime;
    Kind: string;
    Configuration: string;
    Platform: string;
    Succeeded: Boolean;
    Errors: Integer;
    Warnings: Integer;
    Hints: Integer;
    First: TAtlasProjectLocation;
    class function Empty: TAtlasProjectBuild; static;
  end;

  /// <summary>Letzte Hintergrundprüfung (#548).</summary>
  TAtlasProjectCheck = record
    Known: Boolean;
    At: TDateTime;
    Errors: Integer;
    First: TAtlasProjectLocation;
    class function Empty: TAtlasProjectCheck; static;
  end;

  /// <summary>Neue Regeltreffer gegenüber der Baseline (#97).</summary>
  TAtlasProjectRules = record
    Known: Boolean;
    At: TDateTime;
    NewHits: Integer;
    class function Empty: TAtlasProjectRules; static;
  end;

  TAtlasProjectSummary = record
    /// <summary>Vollständiger Pfad der Projektdatei (.dproj, .groupproj …).</summary>
    Project: string;
    /// <summary>UTC; 0 = unbekannt.</summary>
    LastOpened: TDateTime;
    LastClosed: TDateTime;
    /// <summary>„Aus Liste entfernen“ auf der Willkommensseite; Öffnen hebt es auf.</summary>
    Hidden: Boolean;
    Vcs: TAtlasProjectVcs;
    Build: TAtlasProjectBuild;
    Check: TAtlasProjectCheck;
    Rules: TAtlasProjectRules;
    /// <summary>Gelesener Text der Datei; ToJson behält daraus alle unbekannten Felder.</summary>
    Raw: string;
    class function Create(const AProject: string): TAtlasProjectSummary; static;
    /// <summary>Dateiname ohne Endung.</summary>
    function Name: string;
  end;

  TAtlasProjectSummaryChange = reference to procedure(var ASummary: TAtlasProjectSummary);

  TAtlasProjectSummaries = class
  public const
    /// <summary>Format, das diese Fassung liest und schreibt.</summary>
    Format = 1;
    /// <summary>Unterordner von %LOCALAPPDATA%\Atlas.</summary>
    FolderName = 'projects';
  public
    /// <summary>Normierter Pfad für Vergleich und Schlüssel.</summary>
    class function NormalizedPath(const AProject: string): string; static;
    /// <summary>16 Hexziffern (FNV-1a 64 über den normierten Pfad).</summary>
    class function KeyOf(const AProject: string): string; static;
    /// <summary>AFolder\&lt;schlüssel&gt;.json; AFolder ist der Ordner "projects".</summary>
    class function FileFor(const AFolder, AProject: string): string; static;
    /// <summary>Zeit in UTC als "2026-10-15T09:30:00Z"; '' für 0.</summary>
    class function TimeText(AUtc: TDateTime): string; static;
    /// <summary>Umkehrung von TimeText; Bruchteile und Zeitzone "Z" erlaubt; 0 bei ungültigem Text.</summary>
    class function TimeOf(const AText: string): TDateTime; static;
    /// <summary>Liest AJson. False bei ungültigem Inhalt oder höherem Format; ASummary ist dann leer.</summary>
    class function Parse(const AJson: string; out ASummary: TAtlasProjectSummary): Boolean; static;
    /// <summary>JSON der Zusammenfassung; unbekannte Felder aus ASummary.Raw bleiben erhalten.</summary>
    class function ToJson(const ASummary: TAtlasProjectSummary): string; static;
    /// <summary>Format einer Datei (0 ohne oder bei ungültigem Inhalt).</summary>
    class function FormatOf(const AJson: string): Integer; static;
    /// <summary>Liest die Datei zu AProject; False ohne oder bei ungültiger Datei (ASummary dann leer mit
    /// Project = AProject).</summary>
    class function Load(const AFolder, AProject: string; out ASummary: TAtlasProjectSummary): Boolean; static;
    /// <summary>Schreibt (über eine temporäre Datei); False bei Fehler oder wenn die vorhandene Datei ein
    /// höheres Format hat.</summary>
    class function Save(const AFolder: string; const ASummary: TAtlasProjectSummary): Boolean; static;
    /// <summary>Lesen, AChange anwenden, schreiben.</summary>
    class function Update(const AFolder, AProject: string; const AChange: TAtlasProjectSummaryChange): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON;

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

const
  // Bekannte Felder; alles andere übernimmt ToJson unverändert aus Raw.
  TopKeys: array[0..8] of string = ('format', 'project', 'lastOpened', 'lastClosed', 'hidden', 'vcs', 'build',
    'check', 'rules');
  VcsKeys: array[0..6] of string = ('at', 'kind', 'branch', 'revision', 'changed', 'ahead', 'behind');
  BuildKeys: array[0..8] of string = ('at', 'kind', 'configuration', 'platform', 'succeeded', 'errors', 'warnings',
    'hints', 'first');
  CheckKeys: array[0..2] of string = ('at', 'errors', 'first');
  RulesKeys: array[0..1] of string = ('at', 'newHits');

{ TAtlasProjectLocation }

function TAtlasProjectLocation.IsEmpty: Boolean;
begin
  Result := FileName = '';
end;

{ TAtlasProjectVcs }

class function TAtlasProjectVcs.Empty: TAtlasProjectVcs;
begin
  Result := Default(TAtlasProjectVcs);
  Result.Changed := -1;
  Result.Ahead := -1;
  Result.Behind := -1;
end;

function TAtlasProjectVcs.InWorkingCopy: Boolean;
begin
  Result := Known and (SameText(Kind, 'git') or SameText(Kind, 'svn'));
end;

{ TAtlasProjectBuild }

class function TAtlasProjectBuild.Empty: TAtlasProjectBuild;
begin
  Result := Default(TAtlasProjectBuild);
end;

{ TAtlasProjectCheck }

class function TAtlasProjectCheck.Empty: TAtlasProjectCheck;
begin
  Result := Default(TAtlasProjectCheck);
end;

{ TAtlasProjectRules }

class function TAtlasProjectRules.Empty: TAtlasProjectRules;
begin
  Result := Default(TAtlasProjectRules);
end;

{ TAtlasProjectSummary }

class function TAtlasProjectSummary.Create(const AProject: string): TAtlasProjectSummary;
begin
  Result := Default(TAtlasProjectSummary);
  Result.Project := AProject;
  Result.Vcs := TAtlasProjectVcs.Empty;
  Result.Build := TAtlasProjectBuild.Empty;
  Result.Check := TAtlasProjectCheck.Empty;
  Result.Rules := TAtlasProjectRules.Empty;
end;

function TAtlasProjectSummary.Name: string;
var
  Index: Integer;
begin
  // Ohne ExtractFileName: Der Pfad hat immer „\“, auch wenn die Tests nicht unter Windows laufen.
  Result := Project;
  for Index := Length(Result) downto 1 do
    if CharInSet(Result[Index], ['\', '/']) then
    begin
      Result := Copy(Result, Index + 1, MaxInt);
      Break;
    end;
  for Index := Length(Result) downto 1 do
    if Result[Index] = '.' then
    begin
      Result := Copy(Result, 1, Index - 1);
      Break;
    end;
end;

{ JSON-Helfer }

function Known(const AKeys: array of string; const AName: string): Boolean;
var
  Key: string;
begin
  Result := False;
  for Key in AKeys do
    if Key = AName then
      Exit(True);
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function NumberOf(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  Value: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt
  else if Value is TJSONString then
    Result := StrToIntDef(TJSONString(Value).Value, ADefault);
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONBool then
    Result := SameText(Value.Value, 'true');
end;

function ObjectOf(AObject: TJSONObject; const AName: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  Value := AObject.GetValue(AName);
  if Value is TJSONObject then
    Result := TJSONObject(Value);
end;

function LocationOf(AObject: TJSONObject): TAtlasProjectLocation;
begin
  Result := Default(TAtlasProjectLocation);
  if AObject = nil then
    Exit;
  Result.FileName := TextOf(AObject, 'file');
  Result.Line := NumberOf(AObject, 'line', 0);
  Result.Column := NumberOf(AObject, 'column', 0);
  Result.Code := TextOf(AObject, 'code');
  Result.Text := TextOf(AObject, 'text');
end;

function LocationJson(const ALocation: TAtlasProjectLocation): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', ALocation.FileName);
  Result.AddPair('line', TJSONNumber.Create(ALocation.Line));
  Result.AddPair('column', TJSONNumber.Create(ALocation.Column));
  if ALocation.Code <> '' then
    Result.AddPair('code', ALocation.Code);
  if ALocation.Text <> '' then
    Result.AddPair('text', ALocation.Text);
end;

/// <summary>Unbekannte Felder aus AOriginal (darf nil sein) an ATarget anhängen.</summary>
procedure KeepUnknown(ATarget, AOriginal: TJSONObject; const AKeys: array of string);
var
  Index: Integer;
  Pair: TJSONPair;
begin
  if AOriginal = nil then
    Exit;
  for Index := 0 to AOriginal.Count - 1 do
  begin
    Pair := AOriginal.Pairs[Index];
    if not Known(AKeys, Pair.JsonString.Value) then
      ATarget.AddPair(Pair.JsonString.Value, TJSONValue(Pair.JsonValue.Clone));
  end;
end;

procedure AddTime(AObject: TJSONObject; const AName: string; AUtc: TDateTime);
begin
  if AUtc > 0 then
    AObject.AddPair(AName, TAtlasProjectSummaries.TimeText(AUtc));
end;

{ TAtlasProjectSummaries }

class function TAtlasProjectSummaries.NormalizedPath(const AProject: string): string;
var
  Index: Integer;
begin
  Result := Trim(AProject);
  for Index := 1 to Length(Result) do
    if Result[Index] = '/' then
      Result[Index] := '\'
    else if CharInSet(Result[Index], ['a'..'z']) then
      Result[Index] := Chr(Ord(Result[Index]) - 32);
end;

class function TAtlasProjectSummaries.KeyOf(const AProject: string): string;
const
  Offset: UInt64 = $CBF29CE484222325;
  Prime: UInt64 = $00000100000001B3;
  Digits: string = '0123456789abcdef';
var
  Text: string;
  Hash: UInt64;
  Index, Shift: Integer;
  Unit_: Word;
begin
  Text := NormalizedPath(AProject);
  Hash := Offset;
  for Index := 1 to Length(Text) do
  begin
    Unit_ := Ord(Text[Index]);
    Hash := (Hash xor (Unit_ and $FF)) * Prime;
    Hash := (Hash xor (Unit_ shr 8)) * Prime;
  end;
  Result := '';
  Shift := 60;
  while Shift >= 0 do
  begin
    Result := Result + Digits[((Hash shr Shift) and $F) + 1];
    Dec(Shift, 4);
  end;
end;

class function TAtlasProjectSummaries.FileFor(const AFolder, AProject: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AFolder) + KeyOf(AProject) + '.json';
end;

class function TAtlasProjectSummaries.TimeText(AUtc: TDateTime): string;
var
  Year, Month, Day, Hour, Minute, Second, MSec: Word;
begin
  Result := '';
  if AUtc <= 0 then
    Exit;
  DecodeDate(AUtc, Year, Month, Day);
  DecodeTime(AUtc, Hour, Minute, Second, MSec);
  Result := System.SysUtils.Format('%.4d-%.2d-%.2dT%.2d:%.2d:%.2dZ', [Year, Month, Day, Hour, Minute, Second]);
end;

class function TAtlasProjectSummaries.TimeOf(const AText: string): TDateTime;
var
  Text: string;
  Year, Month, Day, Hour, Minute, Second: Integer;
  DatePart, TimePart: TDateTime;
begin
  Result := 0;
  Text := Trim(AText);
  // yyyy-mm-ddThh:nn:ss, danach höchstens Bruchteile und "Z".
  if (Length(Text) < 19) or (Text[5] <> '-') or (Text[8] <> '-') or not CharInSet(Text[11], ['T', 't', ' ']) or
    (Text[14] <> ':') or (Text[17] <> ':') then
    Exit;
  Year := StrToIntDef(Copy(Text, 1, 4), -1);
  Month := StrToIntDef(Copy(Text, 6, 2), -1);
  Day := StrToIntDef(Copy(Text, 9, 2), -1);
  Hour := StrToIntDef(Copy(Text, 12, 2), -1);
  Minute := StrToIntDef(Copy(Text, 15, 2), -1);
  Second := StrToIntDef(Copy(Text, 18, 2), -1);
  if (Year < 1) or (Month < 1) or (Day < 1) or (Hour < 0) or (Minute < 0) or (Second < 0) then
    Exit;
  if not TryEncodeDate(Year, Month, Day, DatePart) or not TryEncodeTime(Hour, Minute, Second, 0, TimePart) then
    Exit;
  Result := DatePart + TimePart;
end;

class function TAtlasProjectSummaries.FormatOf(const AJson: string): Integer;
var
  Value: TJSONValue;
begin
  Result := 0;
  Value := nil;
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if Value is TJSONObject then
      Result := NumberOf(TJSONObject(Value), 'format', 0);
  finally
    Value.Free;
  end;
end;

class function TAtlasProjectSummaries.Parse(const AJson: string; out ASummary: TAtlasProjectSummary): Boolean;
var
  Value: TJSONValue;
  Root, Section: TJSONObject;
begin
  ASummary := TAtlasProjectSummary.Create('');
  Result := False;
  Value := nil;
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if not (Value is TJSONObject) then
      Exit;
    Root := TJSONObject(Value);
    // Ohne "format" gilt 1; ein höheres Format kennt diese Fassung nicht.
    if NumberOf(Root, 'format', 1) > Format then
      Exit;
    ASummary.Raw := AJson;
    ASummary.Project := TextOf(Root, 'project');
    ASummary.LastOpened := TimeOf(TextOf(Root, 'lastOpened'));
    ASummary.LastClosed := TimeOf(TextOf(Root, 'lastClosed'));
    ASummary.Hidden := FlagOf(Root, 'hidden');
    Section := ObjectOf(Root, 'vcs');
    if Section <> nil then
    begin
      ASummary.Vcs.Known := True;
      ASummary.Vcs.At := TimeOf(TextOf(Section, 'at'));
      ASummary.Vcs.Kind := LowerCase(TextOf(Section, 'kind'));
      ASummary.Vcs.Branch := TextOf(Section, 'branch');
      ASummary.Vcs.Revision := TextOf(Section, 'revision');
      ASummary.Vcs.Changed := NumberOf(Section, 'changed', -1);
      ASummary.Vcs.Ahead := NumberOf(Section, 'ahead', -1);
      ASummary.Vcs.Behind := NumberOf(Section, 'behind', -1);
    end;
    Section := ObjectOf(Root, 'build');
    if Section <> nil then
    begin
      ASummary.Build.Known := True;
      ASummary.Build.At := TimeOf(TextOf(Section, 'at'));
      ASummary.Build.Kind := TextOf(Section, 'kind');
      ASummary.Build.Configuration := TextOf(Section, 'configuration');
      ASummary.Build.Platform := TextOf(Section, 'platform');
      ASummary.Build.Succeeded := FlagOf(Section, 'succeeded');
      ASummary.Build.Errors := NumberOf(Section, 'errors', 0);
      ASummary.Build.Warnings := NumberOf(Section, 'warnings', 0);
      ASummary.Build.Hints := NumberOf(Section, 'hints', 0);
      ASummary.Build.First := LocationOf(ObjectOf(Section, 'first'));
    end;
    Section := ObjectOf(Root, 'check');
    if Section <> nil then
    begin
      ASummary.Check.Known := True;
      ASummary.Check.At := TimeOf(TextOf(Section, 'at'));
      ASummary.Check.Errors := NumberOf(Section, 'errors', 0);
      ASummary.Check.First := LocationOf(ObjectOf(Section, 'first'));
    end;
    Section := ObjectOf(Root, 'rules');
    if Section <> nil then
    begin
      ASummary.Rules.Known := True;
      ASummary.Rules.At := TimeOf(TextOf(Section, 'at'));
      ASummary.Rules.NewHits := NumberOf(Section, 'newHits', 0);
    end;
    Result := True;
  finally
    Value.Free;
  end;
end;

class function TAtlasProjectSummaries.ToJson(const ASummary: TAtlasProjectSummary): string;
var
  Value: TJSONValue;
  Original, Root, Section: TJSONObject;
begin
  Value := nil;
  if ASummary.Raw <> '' then
    try
      Value := TJSONObject.ParseJSONValue(ASummary.Raw);
    except
      on Exception do
        Value := nil;
    end;
  Root := TJSONObject.Create;
  try
    Original := nil;
    if Value is TJSONObject then
      Original := TJSONObject(Value);
    Root.AddPair('format', TJSONNumber.Create(Format));
    Root.AddPair('project', ASummary.Project);
    AddTime(Root, 'lastOpened', ASummary.LastOpened);
    AddTime(Root, 'lastClosed', ASummary.LastClosed);
    if ASummary.Hidden then
      Root.AddPair('hidden', TJSONBool.Create(True));
    if ASummary.Vcs.Known then
    begin
      Section := TJSONObject.Create;
      Root.AddPair('vcs', Section);
      AddTime(Section, 'at', ASummary.Vcs.At);
      Section.AddPair('kind', ASummary.Vcs.Kind);
      if ASummary.Vcs.Branch <> '' then
        Section.AddPair('branch', ASummary.Vcs.Branch);
      if ASummary.Vcs.Revision <> '' then
        Section.AddPair('revision', ASummary.Vcs.Revision);
      Section.AddPair('changed', TJSONNumber.Create(ASummary.Vcs.Changed));
      Section.AddPair('ahead', TJSONNumber.Create(ASummary.Vcs.Ahead));
      Section.AddPair('behind', TJSONNumber.Create(ASummary.Vcs.Behind));
      KeepUnknown(Section, ObjectOf(Original, 'vcs'), VcsKeys);
    end;
    if ASummary.Build.Known then
    begin
      Section := TJSONObject.Create;
      Root.AddPair('build', Section);
      AddTime(Section, 'at', ASummary.Build.At);
      Section.AddPair('kind', ASummary.Build.Kind);
      Section.AddPair('configuration', ASummary.Build.Configuration);
      Section.AddPair('platform', ASummary.Build.Platform);
      Section.AddPair('succeeded', TJSONBool.Create(ASummary.Build.Succeeded));
      Section.AddPair('errors', TJSONNumber.Create(ASummary.Build.Errors));
      Section.AddPair('warnings', TJSONNumber.Create(ASummary.Build.Warnings));
      Section.AddPair('hints', TJSONNumber.Create(ASummary.Build.Hints));
      if not ASummary.Build.First.IsEmpty then
        Section.AddPair('first', LocationJson(ASummary.Build.First));
      KeepUnknown(Section, ObjectOf(Original, 'build'), BuildKeys);
    end;
    if ASummary.Check.Known then
    begin
      Section := TJSONObject.Create;
      Root.AddPair('check', Section);
      AddTime(Section, 'at', ASummary.Check.At);
      Section.AddPair('errors', TJSONNumber.Create(ASummary.Check.Errors));
      if not ASummary.Check.First.IsEmpty then
        Section.AddPair('first', LocationJson(ASummary.Check.First));
      KeepUnknown(Section, ObjectOf(Original, 'check'), CheckKeys);
    end;
    if ASummary.Rules.Known then
    begin
      Section := TJSONObject.Create;
      Root.AddPair('rules', Section);
      AddTime(Section, 'at', ASummary.Rules.At);
      Section.AddPair('newHits', TJSONNumber.Create(ASummary.Rules.NewHits));
      KeepUnknown(Section, ObjectOf(Original, 'rules'), RulesKeys);
    end;
    KeepUnknown(Root, Original, TopKeys);
    Result := Root.ToJSON;
  finally
    Root.Free;
    Value.Free;
  end;
end;

function ReadText(const AFileName: string): string;
var
  Bytes: TBytes;
begin
  Bytes := TFile.ReadAllBytes(AFileName);
  // Mit oder ohne BOM.
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Result := TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3)
  else
    Result := TEncoding.UTF8.GetString(Bytes);
end;

class function TAtlasProjectSummaries.Load(const AFolder, AProject: string;
  out ASummary: TAtlasProjectSummary): Boolean;
var
  FileName, Text: string;
begin
  ASummary := TAtlasProjectSummary.Create(AProject);
  Result := False;
  if (AFolder = '') or (Trim(AProject) = '') then
    Exit;
  FileName := FileFor(AFolder, AProject);
  if not FileExists(FileName) then
    Exit;
  try
    Text := ReadText(FileName);
  except
    // Gesperrt oder unlesbar: wie ohne Datei.
    on Exception do
      Exit;
  end;
  Result := Parse(Text, ASummary);
  if not Result then
    ASummary := TAtlasProjectSummary.Create(AProject)
  else if ASummary.Project = '' then
    ASummary.Project := AProject;
end;

class function TAtlasProjectSummaries.Save(const AFolder: string; const ASummary: TAtlasProjectSummary): Boolean;
var
  FileName, Temp: string;
begin
  Result := False;
  if (AFolder = '') or (Trim(ASummary.Project) = '') then
    Exit;
  FileName := FileFor(AFolder, ASummary.Project);
  try
    // Eine neuere Fassung hat die Datei geschrieben: nicht überschreiben.
    if FileExists(FileName) and (FormatOf(ReadText(FileName)) > Format) then
      Exit;
    ForceDirectories(AFolder);
    Temp := FileName + '.tmp';
    // Ohne BOM: UTF-8 wie JSON üblich.
    TFile.WriteAllBytes(Temp, TEncoding.UTF8.GetBytes(ToJson(ASummary)));
    if FileExists(FileName) then
      System.SysUtils.DeleteFile(FileName);
    Result := RenameFile(Temp, FileName);
  except
    on Exception do
      Result := False;
  end;
end;

class function TAtlasProjectSummaries.Update(const AFolder, AProject: string;
  const AChange: TAtlasProjectSummaryChange): Boolean;
var
  Summary: TAtlasProjectSummary;
begin
  Result := False;
  if (AFolder = '') or (Trim(AProject) = '') then
    Exit;
  // Ohne lesbare Datei beginnt eine neue; eine Datei mit höherem Format bleibt unangetastet (Save prüft das).
  Load(AFolder, AProject, Summary);
  if Assigned(AChange) then
    AChange(Summary);
  Result := Save(AFolder, Summary);
end;

end.
