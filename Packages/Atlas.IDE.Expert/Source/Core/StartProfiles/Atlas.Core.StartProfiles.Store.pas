unit Atlas.Core.StartProfiles.Store;

// Startprofile (#575), Teil ohne VCL und Open Tools API: benannte Sätze aus
// Parametern, Arbeitsordner, Umgebungsvariablen und Host-Anwendung, die Atlas
// als Startoptionen in das Projekt schreibt („Start“ und „Ohne Debugger
// starten“ der IDE nutzen sie dann).
// - Gemeinsame Profile stehen in der Projektdatei .atlas im Repository
//   ("startProfiles", #486; gelesen von Atlas.Core.Settings.TeamFile, dort
//   ohne Zugangsdaten und absolute Pfade). Pfade gelten ab dem Ordner der
//   .atlas.
// - Persönliche Profile, das aktive Profil und die Startoptionen von vor dem
//   ersten Profil liegen nur lokal je Projekt:
//   %LOCALAPPDATA%\Atlas\startprofiles\<schlüssel>.json (Schlüssel wie die
//   Projekt-Zusammenfassung #592, TAtlasProjectSummaries.KeyOf). Pfade dürfen
//   absolut sein; relative gelten ab dem Ordner der .dproj.
// - Format 1 (UTF-8 ohne BOM; Kommentare // und /* */ werden beim Lesen
//   übergangen, beim Schreiben nicht erhalten):
//     {"format": 1, "project": "C:\\Projekte\\App.dproj", "active": "Demo",
//      "profiles": [{"name": "Lokal", "parameters": "-db C:\\Daten\\test.fdb",
//        "workingDir": "C:\\Daten", "host": "", "environment": {"MODUS": "test"}}],
//      "original": {"parameters": "", "workingDir": "", "host": "", "environment": ""},
//      "temporary": {"parameters": "", "workingDir": "", "host": "", "environment": "",
//        "written": "--run:… --exitbehavior:Continue"}}
// - Vorübergehende Startparameter (Test debuggen, #585): "temporary" hält die
//   Startoptionen von davor und die geschriebenen Parameter, bis der Lauf
//   endet. Bleibt der Eintrag nach einem Absturz der IDE stehen, stellt Atlas
//   die Startoptionen beim nächsten Mal wieder her, aber nur, wenn die
//   Parameter noch die geschriebenen sind.
// - Vorrang: Gleichnamige Profile (ohne Groß-/Kleinschreibung) kommen aus
//   .atlas; die Liste hat erst die gemeinsamen, dann die persönlichen.
// - Startoptionen in der .dproj (Run › Parameter der IDE): Debugger_RunParams,
//   Debugger_CWD, Debugger_HostApplication, Debugger_EnvVars. Umgebungsvariablen
//   stehen dort als "NAME=Wert;…;$(Debugger_EnvVars)", ein Eintrag mit „;“
//   in Anführungszeichen. Makros wie $(BDS) in Pfaden bleiben stehen, die IDE
//   setzt sie ein.
// - Für die Willkommensseite (#764) liest ForProject die Profile eines
//   Projekts ohne IDE.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.TeamFile;

type
{$SCOPEDENUMS ON}
  /// <summary>Herkunft eines Startprofils.</summary>
  TAtlasStartProfileSource = (
    /// <summary>Projektdatei .atlas im Repository (für alle im Team).</summary>
    Team,
    /// <summary>Nur auf diesem Rechner.</summary>
    Personal);
{$SCOPEDENUMS OFF}

  /// <summary>Startoptionen eines Projekts, wie die IDE sie für Konfiguration und Plattform ablegt.</summary>
  TAtlasStartOptions = record
    /// <summary>Debugger_RunParams.</summary>
    Parameters: string;
    /// <summary>Debugger_CWD; '' = Ordner der EXE.</summary>
    WorkingDir: string;
    /// <summary>Debugger_HostApplication (DLLs und Packages); '' = keine.</summary>
    Host: string;
    /// <summary>Debugger_EnvVars, roh wie in der .dproj.</summary>
    Environment: string;
    function SameAs(const AOther: TAtlasStartOptions): Boolean;
    function IsEmpty: Boolean;
  end;

  /// <summary>Ein Profil mit Herkunft und Basis seiner relativen Pfade.</summary>
  TAtlasStartProfileEntry = record
    Profile: TAtlasStartProfile;
    Source: TAtlasStartProfileSource;
    /// <summary>Ordner der .atlas bzw. der .dproj.</summary>
    BaseFolder: string;
  end;

  /// <summary>Lokale Datei je Projekt: persönliche Profile, aktives Profil, Startoptionen von vorher.</summary>
  TAtlasStartProfileState = record
    /// <summary>.dproj, zu der die Datei gehört.</summary>
    Project: string;
    /// <summary>Name des aktiven Profils; '' = keins (es gelten die Startoptionen der IDE).</summary>
    Active: string;
    Profiles: TArray<TAtlasStartProfile>;
    /// <summary>Original ist gesetzt: Startoptionen, bevor Atlas das erste Profil setzte.</summary>
    HasOriginal: Boolean;
    Original: TAtlasStartOptions;
    /// <summary>Vorübergehende Startparameter sind gesetzt (#585): TemporaryBefore galt davor, TemporaryWritten
    /// hat Atlas geschrieben.</summary>
    HasTemporary: Boolean;
    TemporaryBefore: TAtlasStartOptions;
    TemporaryWritten: string;
    /// <summary>Index des persönlichen Profils AName (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    function IndexOf(const AName: string): Integer;
  end;

  TAtlasStartProfiles = class
  public const
    Format = 1;
    /// <summary>Unterordner von %LOCALAPPDATA%\Atlas.</summary>
    FolderName = 'startprofiles';
    /// <summary>Namen der Startoptionen in der .dproj.</summary>
    ParametersOption = 'Debugger_RunParams';
    WorkingDirOption = 'Debugger_CWD';
    HostOption = 'Debugger_HostApplication';
    EnvironmentOption = 'Debugger_EnvVars';
    /// <summary>Verweis auf die geerbten Umgebungsvariablen, wie ihn die IDE schreibt.</summary>
    InheritEnvironment = '$(Debugger_EnvVars)';
  public
    /// <summary>Leerer Stand für AProject.</summary>
    class function Empty(const AProject: string): TAtlasStartProfileState; static;
    /// <summary>AFolder\&lt;schlüssel&gt;.json; AFolder ist der Ordner "startprofiles".</summary>
    class function FileFor(const AFolder, AProject: string): string; static;
    /// <summary>Liest den Text der Datei; bei ungültigem Inhalt oder höherem Format leer (AValid False).</summary>
    class function Parse(const AText, AProject: string; out AValid: Boolean): TAtlasStartProfileState; overload;
      static;
    class function Parse(const AText, AProject: string): TAtlasStartProfileState; overload; static;
    /// <summary>Format einer Datei (0 ohne oder bei ungültigem Inhalt).</summary>
    class function FormatOf(const AText: string): Integer; static;
    /// <summary>Text der Datei (eingerückt, CRLF).</summary>
    class function ToJson(const AState: TAtlasStartProfileState): string; static;
    /// <summary>Datei zu AProject lesen; ohne oder bei unlesbarer Datei leer.</summary>
    class function Load(const AFolder, AProject: string): TAtlasStartProfileState; static;
    /// <summary>Schreiben (über eine temporäre Datei); False bei Fehler oder höherem Format der vorhandenen.
    /// </summary>
    class function Save(const AFolder: string; const AState: TAtlasStartProfileState): Boolean; static;
    /// <summary>Profile zur Auswahl: die gültigen aus ATeam, dann die persönlichen, die dort fehlen.</summary>
    class function Merge(const ATeam: TAtlasTeamSettings;
      const AState: TAtlasStartProfileState): TArray<TAtlasStartProfileEntry>; static;
    /// <summary>Load und Merge für ein Projekt ohne IDE (Willkommensseite #764).</summary>
    class function ForProject(const AFolder, AProject: string;
      const ATeam: TAtlasTeamSettings): TArray<TAtlasStartProfileEntry>; static;
    /// <summary>Profil AName (ohne Groß-/Kleinschreibung) in AEntries.</summary>
    class function Find(const AEntries: TArray<TAtlasStartProfileEntry>; const AName: string;
      out AEntry: TAtlasStartProfileEntry): Boolean; static;
    /// <summary>Startoptionen eines Profils: Pfade ab BaseFolder, Umgebung mit Erbe.</summary>
    class function OptionsOf(const AEntry: TAtlasStartProfileEntry): TAtlasStartOptions; static;
    /// <summary>APath ab ABase; leer, Makro ($(…)) oder absolut bleibt, wie es ist.</summary>
    class function ResolvePath(const ABase, APath: string): string; static;
    /// <summary>"NAME=Wert;…" ohne Erbe; Einträge mit „;“ oder „"“ in Anführungszeichen.</summary>
    class function EncodeEnvironment(const AVariables: TArray<TAtlasTeamVariable>): string; static;
    /// <summary>Wert für Debugger_EnvVars: EncodeEnvironment und $(Debugger_EnvVars); '' ohne Variablen.</summary>
    class function EnvironmentValue(const AVariables: TArray<TAtlasTeamVariable>): string; static;
    /// <summary>Umkehrung: Einträge "NAME=Wert"; Erbe und Einträge ohne „=“ fallen weg.</summary>
    class function DecodeEnvironment(const AText: string): TArray<TAtlasTeamVariable>; static;
    /// <summary>Persönliches Profil AName aus den Startoptionen der IDE („Aktuelle Startoptionen speichern“).
    /// </summary>
    class function ProfileFromOptions(const AName: string; const AOptions: TAtlasStartOptions): TAtlasStartProfile;
      static;
    /// <summary>Persönliches Profil anlegen oder gleichnamiges ersetzen; False bei leerem Namen.</summary>
    class function PutPersonal(var AState: TAtlasStartProfileState; const AProfile: TAtlasStartProfile): Boolean;
      static;
    /// <summary>AName aktiv; beim ersten Profil merkt sich der Stand ACurrent als Startoptionen von vorher.</summary>
    class procedure Activate(var AState: TAtlasStartProfileState; const AName: string;
      const ACurrent: TAtlasStartOptions); static;
    /// <summary>Kein Profil mehr; True mit den gemerkten Startoptionen, die wieder gelten sollen.</summary>
    class function Deactivate(var AState: TAtlasStartProfileState; out AOriginal: TAtlasStartOptions): Boolean;
      static;
    /// <summary>Startoptionen für einen vorübergehenden Lauf: ACurrent mit den Parametern AParameters (Arbeitsordner,
    /// Host und Umgebung bleiben, z. B. die eines aktiven Startprofils).</summary>
    class function TemporaryOptions(const ACurrent: TAtlasStartOptions; const AParameters: string): TAtlasStartOptions;
      static;
    /// <summary>Vorübergehende Parameter AWritten merken; ACurrent galt davor. Ist schon ein Eintrag offen, bleiben
    /// dessen Startoptionen von davor (sonst gälten nach dem Lauf die vorübergehenden).</summary>
    class procedure BeginTemporary(var AState: TAtlasStartProfileState; const ACurrent: TAtlasStartOptions;
      const AWritten: string); static;
    /// <summary>Lauf beendet: Eintrag entfernen; True mit den Startoptionen von davor, wenn sie wieder gelten sollen
    /// (die Parameter ACurrent sind noch die geschriebenen; hat sie jemand geändert, bleiben sie).</summary>
    class function EndTemporary(var AState: TAtlasStartProfileState; const ACurrent: TAtlasStartOptions;
      out ABefore: TAtlasStartOptions): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.JSON,
  Atlas.Text.Jsonc,
  Atlas.Text.Checkin,
  Atlas.Core.Projects.Summary;

function FolderOf(const AFileName: string): string;
var
  Index: Integer;
begin
  for Index := Length(AFileName) downto 1 do
    if (AFileName[Index] = '\') or (AFileName[Index] = '/') then
      Exit(Copy(AFileName, 1, Index - 1));
  Result := '';
end;

function Quote(const AText: string): string;
var
  Value: TJSONString;
begin
  Value := TJSONString.Create(AText);
  try
    Result := Value.ToJSON;
  finally
    Value.Free;
  end;
end;

function StringOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function ReadText(const AFileName: string): string;
var
  Stream: TFileStream;
  Bytes: TBytes;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Bytes, Stream.Size);
    if Length(Bytes) > 0 then
      Stream.ReadBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
  end;
  // Mit oder ohne BOM (nach Bearbeiten im Editor der IDE).
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    Result := TEncoding.UTF8.GetString(Bytes, 3, Length(Bytes) - 3)
  else
    Result := TEncoding.UTF8.GetString(Bytes);
end;

procedure WriteText(const AFileName, AText: string);
var
  Stream: TFileStream;
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(Bytes) > 0 then
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
  end;
end;

function ReadProfile(AValue: TJSONValue; out AProfile: TAtlasStartProfile): Boolean;
var
  Entry, Environment: TJSONObject;
  Index: Integer;
  Variable: TAtlasTeamVariable;
begin
  AProfile := Default(TAtlasStartProfile);
  Result := False;
  if not (AValue is TJSONObject) then
    Exit;
  Entry := TJSONObject(AValue);
  AProfile.Name := Trim(StringOf(Entry, 'name'));
  AProfile.Parameters := StringOf(Entry, 'parameters');
  AProfile.WorkingDir := Trim(StringOf(Entry, 'workingDir'));
  AProfile.Host := Trim(StringOf(Entry, 'host'));
  if Entry.GetValue('environment') is TJSONObject then
  begin
    Environment := TJSONObject(Entry.GetValue('environment'));
    for Index := 0 to Environment.Count - 1 do
      if Environment.Pairs[Index].JsonValue is TJSONString then
      begin
        Variable.Name := Trim(Environment.Pairs[Index].JsonString.Value);
        Variable.Value := TJSONString(Environment.Pairs[Index].JsonValue).Value;
        if Variable.Name <> '' then
          AProfile.Environment := AProfile.Environment + [Variable];
      end;
  end;
  Result := AProfile.Name <> '';
end;

function ReadOptions(AValue: TJSONValue; out AOptions: TAtlasStartOptions): Boolean;
begin
  AOptions := Default(TAtlasStartOptions);
  Result := AValue is TJSONObject;
  if not Result then
    Exit;
  AOptions.Parameters := StringOf(TJSONObject(AValue), 'parameters');
  AOptions.WorkingDir := StringOf(TJSONObject(AValue), 'workingDir');
  AOptions.Host := StringOf(TJSONObject(AValue), 'host');
  AOptions.Environment := StringOf(TJSONObject(AValue), 'environment');
end;

function ReadTemporary(AValue: TJSONValue; var AState: TAtlasStartProfileState): Boolean;
begin
  Result := ReadOptions(AValue, AState.TemporaryBefore);
  if Result then
    AState.TemporaryWritten := StringOf(TJSONObject(AValue), 'written');
end;

function SplitEnvironment(const AText: string): TArray<string>;
var
  Index: Integer;
  Current: string;
  Quoted: Boolean;
begin
  Result := nil;
  Current := '';
  Quoted := False;
  for Index := 1 to Length(AText) do
    if AText[Index] = '"' then
      Quoted := not Quoted
    else if (AText[Index] = ';') and not Quoted then
    begin
      Result := Result + [Current];
      Current := '';
    end
    else
      Current := Current + AText[Index];
  Result := Result + [Current];
end;

{ TAtlasStartOptions }

function TAtlasStartOptions.SameAs(const AOther: TAtlasStartOptions): Boolean;
begin
  Result := (Parameters = AOther.Parameters) and (WorkingDir = AOther.WorkingDir) and (Host = AOther.Host) and
    (Environment = AOther.Environment);
end;

function TAtlasStartOptions.IsEmpty: Boolean;
begin
  Result := (Parameters = '') and (WorkingDir = '') and (Host = '') and (Environment = '');
end;

{ TAtlasStartProfileState }

function TAtlasStartProfileState.IndexOf(const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Profiles) do
    if SameText(Profiles[Index].Name, Trim(AName)) then
      Exit(Index);
  Result := -1;
end;

{ TAtlasStartProfiles }

class function TAtlasStartProfiles.Empty(const AProject: string): TAtlasStartProfileState;
begin
  Result := Default(TAtlasStartProfileState);
  Result.Project := AProject;
end;

class function TAtlasStartProfiles.FileFor(const AFolder, AProject: string): string;
begin
  Result := TAtlasProjectSummaries.FileFor(AFolder, AProject);
end;

class function TAtlasStartProfiles.Parse(const AText, AProject: string; out AValid: Boolean): TAtlasStartProfileState;
var
  Root: TJSONValue;
  Value: TJSONValue;
  Index: Integer;
  Profile: TAtlasStartProfile;
begin
  Result := Empty(AProject);
  AValid := False;
  if Trim(AText) = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(TJsoncScanner.StripComments(AText));
  try
    if not (Root is TJSONObject) then
      Exit;
    Value := TJSONObject(Root).GetValue('format');
    if (Value is TJSONNumber) and (TJSONNumber(Value).AsInt > Format) then
      Exit;
    AValid := True;
    if StringOf(TJSONObject(Root), 'project') <> '' then
      Result.Project := StringOf(TJSONObject(Root), 'project');
    Result.Active := Trim(StringOf(TJSONObject(Root), 'active'));
    Value := TJSONObject(Root).GetValue('profiles');
    if Value is TJSONArray then
      for Index := 0 to TJSONArray(Value).Count - 1 do
        if ReadProfile(TJSONArray(Value).Items[Index], Profile) and (Result.IndexOf(Profile.Name) < 0) then
          Result.Profiles := Result.Profiles + [Profile];
    Result.HasOriginal := ReadOptions(TJSONObject(Root).GetValue('original'), Result.Original);
    Result.HasTemporary := ReadTemporary(TJSONObject(Root).GetValue('temporary'), Result);
  finally
    Root.Free;
  end;
end;

class function TAtlasStartProfiles.Parse(const AText, AProject: string): TAtlasStartProfileState;
var
  Valid: Boolean;
begin
  Result := Parse(AText, AProject, Valid);
end;

class function TAtlasStartProfiles.FormatOf(const AText: string): Integer;
var
  Root, Value: TJSONValue;
begin
  Result := 0;
  if Trim(AText) = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(TJsoncScanner.StripComments(AText));
  try
    if not (Root is TJSONObject) then
      Exit;
    Value := TJSONObject(Root).GetValue('format');
    if Value is TJSONNumber then
      Result := TJSONNumber(Value).AsInt;
  finally
    Root.Free;
  end;
end;

class function TAtlasStartProfiles.ToJson(const AState: TAtlasStartProfileState): string;
const
  NewLine = #13#10;
var
  Lines: TStringBuilder;
  Index, Variable: Integer;
  Profile: TAtlasStartProfile;
  Separator: string;
begin
  Lines := TStringBuilder.Create;
  try
    Lines.Append('{' + NewLine);
    Lines.Append('  "format": ' + IntToStr(Format) + ',' + NewLine);
    Lines.Append('  "project": ' + Quote(AState.Project) + ',' + NewLine);
    Lines.Append('  "active": ' + Quote(AState.Active) + ',' + NewLine);
    Lines.Append('  "profiles": [');
    for Index := 0 to High(AState.Profiles) do
    begin
      Profile := AState.Profiles[Index];
      if Index > 0 then
        Lines.Append(',');
      Lines.Append(NewLine + '    {' + NewLine);
      Lines.Append('      "name": ' + Quote(Profile.Name) + ',' + NewLine);
      Lines.Append('      "parameters": ' + Quote(Profile.Parameters) + ',' + NewLine);
      Lines.Append('      "workingDir": ' + Quote(Profile.WorkingDir) + ',' + NewLine);
      Lines.Append('      "host": ' + Quote(Profile.Host) + ',' + NewLine);
      Lines.Append('      "environment": {');
      Separator := '';
      for Variable := 0 to High(Profile.Environment) do
      begin
        Lines.Append(Separator + Quote(Profile.Environment[Variable].Name) + ': ' +
          Quote(Profile.Environment[Variable].Value));
        Separator := ', ';
      end;
      Lines.Append('}' + NewLine + '    }');
    end;
    if Length(AState.Profiles) > 0 then
      Lines.Append(NewLine + '  ');
    Lines.Append(']');
    if AState.HasOriginal then
    begin
      Lines.Append(',' + NewLine + '  "original": {' + NewLine);
      Lines.Append('    "parameters": ' + Quote(AState.Original.Parameters) + ',' + NewLine);
      Lines.Append('    "workingDir": ' + Quote(AState.Original.WorkingDir) + ',' + NewLine);
      Lines.Append('    "host": ' + Quote(AState.Original.Host) + ',' + NewLine);
      Lines.Append('    "environment": ' + Quote(AState.Original.Environment) + NewLine);
      Lines.Append('  }');
    end;
    if AState.HasTemporary then
    begin
      Lines.Append(',' + NewLine + '  "temporary": {' + NewLine);
      Lines.Append('    "parameters": ' + Quote(AState.TemporaryBefore.Parameters) + ',' + NewLine);
      Lines.Append('    "workingDir": ' + Quote(AState.TemporaryBefore.WorkingDir) + ',' + NewLine);
      Lines.Append('    "host": ' + Quote(AState.TemporaryBefore.Host) + ',' + NewLine);
      Lines.Append('    "environment": ' + Quote(AState.TemporaryBefore.Environment) + ',' + NewLine);
      Lines.Append('    "written": ' + Quote(AState.TemporaryWritten) + NewLine);
      Lines.Append('  }');
    end;
    Lines.Append(NewLine + '}' + NewLine);
    Result := Lines.ToString;
  finally
    Lines.Free;
  end;
end;

class function TAtlasStartProfiles.Load(const AFolder, AProject: string): TAtlasStartProfileState;
var
  FileName: string;
begin
  Result := Empty(AProject);
  if (AFolder = '') or (Trim(AProject) = '') then
    Exit;
  FileName := FileFor(AFolder, AProject);
  if not FileExists(FileName) then
    Exit;
  try
    Result := Parse(ReadText(FileName), AProject);
  except
    // Gesperrt oder unlesbar: wie ohne Datei.
    on Exception do
      Result := Empty(AProject);
  end;
end;

class function TAtlasStartProfiles.Save(const AFolder: string; const AState: TAtlasStartProfileState): Boolean;
var
  FileName, Temp: string;
begin
  Result := False;
  if (AFolder = '') or (Trim(AState.Project) = '') then
    Exit;
  FileName := FileFor(AFolder, AState.Project);
  try
    // Eine neuere Fassung hat die Datei geschrieben: nicht überschreiben.
    if FileExists(FileName) and (FormatOf(ReadText(FileName)) > Format) then
      Exit;
    ForceDirectories(AFolder);
    Temp := FileName + '.tmp';
    WriteText(Temp, ToJson(AState));
    if FileExists(FileName) then
      System.SysUtils.DeleteFile(FileName);
    Result := RenameFile(Temp, FileName);
  except
    on Exception do
      Result := False;
  end;
end;

class function TAtlasStartProfiles.Merge(const ATeam: TAtlasTeamSettings;
  const AState: TAtlasStartProfileState): TArray<TAtlasStartProfileEntry>;
var
  Entry, Known: TAtlasStartProfileEntry;
  Profile: TAtlasStartProfile;
  Candidates: TArray<TAtlasStartProfileEntry>;
  Found: Boolean;
begin
  Result := nil;
  Candidates := nil;
  if ATeam.Valid then
    for Profile in ATeam.StartProfiles do
    begin
      Entry.Profile := Profile;
      Entry.Source := TAtlasStartProfileSource.Team;
      Entry.BaseFolder := ATeam.Folder;
      Candidates := Candidates + [Entry];
    end;
  for Profile in AState.Profiles do
  begin
    Entry.Profile := Profile;
    Entry.Source := TAtlasStartProfileSource.Personal;
    Entry.BaseFolder := FolderOf(AState.Project);
    Candidates := Candidates + [Entry];
  end;
  for Entry in Candidates do
  begin
    Found := False;
    for Known in Result do
      if SameText(Known.Profile.Name, Entry.Profile.Name) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Result := Result + [Entry];
  end;
end;

class function TAtlasStartProfiles.ForProject(const AFolder, AProject: string;
  const ATeam: TAtlasTeamSettings): TArray<TAtlasStartProfileEntry>;
begin
  Result := Merge(ATeam, Load(AFolder, AProject));
end;

class function TAtlasStartProfiles.Find(const AEntries: TArray<TAtlasStartProfileEntry>; const AName: string;
  out AEntry: TAtlasStartProfileEntry): Boolean;
var
  Entry: TAtlasStartProfileEntry;
begin
  AEntry := Default(TAtlasStartProfileEntry);
  Result := False;
  if Trim(AName) = '' then
    Exit;
  for Entry in AEntries do
    if SameText(Entry.Profile.Name, Trim(AName)) then
    begin
      AEntry := Entry;
      Exit(True);
    end;
end;

class function TAtlasStartProfiles.ResolvePath(const ABase, APath: string): string;
var
  Path: string;
begin
  Path := Trim(APath);
  if (Path = '') or (Copy(Path, 1, 2) = '$(') or TTextCheckin.IsAbsolutePath(Path) or (ABase = '') then
    Exit(Path);
  Result := TAtlasTeamFile.Combine(ABase, Path);
end;

class function TAtlasStartProfiles.OptionsOf(const AEntry: TAtlasStartProfileEntry): TAtlasStartOptions;
begin
  Result.Parameters := AEntry.Profile.Parameters;
  Result.WorkingDir := ResolvePath(AEntry.BaseFolder, AEntry.Profile.WorkingDir);
  Result.Host := ResolvePath(AEntry.BaseFolder, AEntry.Profile.Host);
  Result.Environment := EnvironmentValue(AEntry.Profile.Environment);
end;

class function TAtlasStartProfiles.EncodeEnvironment(const AVariables: TArray<TAtlasTeamVariable>): string;
var
  Variable: TAtlasTeamVariable;
  Item: string;
begin
  Result := '';
  for Variable in AVariables do
  begin
    if Trim(Variable.Name) = '' then
      Continue;
    Item := Trim(Variable.Name) + '=' + StringReplace(Variable.Value, '"', '', [rfReplaceAll]);
    if Pos(';', Item) > 0 then
      Item := '"' + Item + '"';
    if Result <> '' then
      Result := Result + ';';
    Result := Result + Item;
  end;
end;

class function TAtlasStartProfiles.EnvironmentValue(const AVariables: TArray<TAtlasTeamVariable>): string;
begin
  Result := EncodeEnvironment(AVariables);
  if Result <> '' then
    Result := Result + ';' + InheritEnvironment;
end;

class function TAtlasStartProfiles.DecodeEnvironment(const AText: string): TArray<TAtlasTeamVariable>;
var
  Item: string;
  Variable: TAtlasTeamVariable;
  Equals: Integer;
begin
  Result := nil;
  for Item in SplitEnvironment(AText) do
  begin
    if SameText(Trim(Item), InheritEnvironment) then
      Continue;
    Equals := Pos('=', Item);
    if Equals <= 1 then
      Continue;
    Variable.Name := Trim(Copy(Item, 1, Equals - 1));
    Variable.Value := Copy(Item, Equals + 1, MaxInt);
    if Variable.Name <> '' then
      Result := Result + [Variable];
  end;
end;

class function TAtlasStartProfiles.ProfileFromOptions(const AName: string;
  const AOptions: TAtlasStartOptions): TAtlasStartProfile;
begin
  Result := Default(TAtlasStartProfile);
  Result.Name := Trim(AName);
  Result.Parameters := AOptions.Parameters;
  Result.WorkingDir := Trim(AOptions.WorkingDir);
  Result.Host := Trim(AOptions.Host);
  Result.Environment := DecodeEnvironment(AOptions.Environment);
end;

class function TAtlasStartProfiles.PutPersonal(var AState: TAtlasStartProfileState;
  const AProfile: TAtlasStartProfile): Boolean;
var
  Index: Integer;
  Profile: TAtlasStartProfile;
begin
  Profile := AProfile;
  Profile.Name := Trim(Profile.Name);
  Result := Profile.Name <> '';
  if not Result then
    Exit;
  Index := AState.IndexOf(Profile.Name);
  if Index >= 0 then
    AState.Profiles[Index] := Profile
  else
    AState.Profiles := AState.Profiles + [Profile];
end;

class procedure TAtlasStartProfiles.Activate(var AState: TAtlasStartProfileState; const AName: string;
  const ACurrent: TAtlasStartOptions);
begin
  if not AState.HasOriginal then
  begin
    AState.Original := ACurrent;
    AState.HasOriginal := True;
  end;
  AState.Active := Trim(AName);
end;

class function TAtlasStartProfiles.Deactivate(var AState: TAtlasStartProfileState;
  out AOriginal: TAtlasStartOptions): Boolean;
begin
  AOriginal := AState.Original;
  Result := AState.HasOriginal;
  AState.Active := '';
  AState.HasOriginal := False;
  AState.Original := Default(TAtlasStartOptions);
end;

class function TAtlasStartProfiles.TemporaryOptions(const ACurrent: TAtlasStartOptions;
  const AParameters: string): TAtlasStartOptions;
begin
  Result := ACurrent;
  Result.Parameters := AParameters;
end;

class procedure TAtlasStartProfiles.BeginTemporary(var AState: TAtlasStartProfileState;
  const ACurrent: TAtlasStartOptions; const AWritten: string);
begin
  if not AState.HasTemporary then
  begin
    AState.TemporaryBefore := ACurrent;
    AState.HasTemporary := True;
  end;
  AState.TemporaryWritten := AWritten;
end;

class function TAtlasStartProfiles.EndTemporary(var AState: TAtlasStartProfileState;
  const ACurrent: TAtlasStartOptions; out ABefore: TAtlasStartOptions): Boolean;
begin
  ABefore := AState.TemporaryBefore;
  Result := AState.HasTemporary and (ACurrent.Parameters = AState.TemporaryWritten);
  AState.HasTemporary := False;
  AState.TemporaryBefore := Default(TAtlasStartOptions);
  AState.TemporaryWritten := '';
end;

end.
