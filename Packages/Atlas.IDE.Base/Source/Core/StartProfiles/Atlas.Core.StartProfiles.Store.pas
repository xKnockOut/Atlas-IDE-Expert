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
//   absolut sein; relative gelten ab dem Ordner der .dproj. Lesen und
//   Schreiben über TAtlasDataFile: atomar ersetzt (früher Löschen
//   und Umbenennen), eine unbrauchbare Datei (etwa nach einem Tippfehler beim
//   Bearbeiten von Hand) liegt danach als .defekt daneben und steht im
//   Protokoll, eine beim Lesen gesperrte wird nicht überschrieben.
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
    /// <summary>Vorhandene Datei, die beim Lesen gesperrt war: Save überschreibt sie nicht, sonst gingen ihre
    /// Profile verloren. '' sonst.</summary>
    KeptFile: string;
    /// <summary>Index des persönlichen Profils AName (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    function IndexOf(const AName: string): Integer;
  end;

  TAtlasStartProfiles = class
  public const
    cFormat = 1;
    /// <summary>Unterordner von %LOCALAPPDATA%\Atlas.</summary>
    cFolderName = 'startprofiles';
    /// <summary>Namen der Startoptionen in der .dproj.</summary>
    cParametersOption = 'Debugger_RunParams';
    cWorkingDirOption = 'Debugger_CWD';
    cHostOption = 'Debugger_HostApplication';
    cEnvironmentOption = 'Debugger_EnvVars';
    /// <summary>Verweis auf die geerbten Umgebungsvariablen, wie ihn die IDE schreibt.</summary>
    cInheritEnvironment = '$(Debugger_EnvVars)';
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
    /// <summary>Datei zu AProject über TAtlasDataFile.Load lesen; leer ohne, bei unbrauchbarer (dann als
    /// .defekt beiseitegelegt) oder gesperrter Datei (dann KeptFile).</summary>
    class function Load(const AFolder, AProject: string): TAtlasStartProfileState; static;
    /// <summary>Ersetzt die Datei atomar; False bei Fehler (einmal protokolliert), bei höherem Format der
    /// vorhandenen, wenn sie gerade nicht lesbar ist oder beim Laden gesperrt war (AState.KeptFile).</summary>
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
  System.Generics.Collections,
  Winapi.Windows,
  System.Classes,
  System.JSON,
  Atlas.Text.Json,
  Atlas.Text.Jsonc,
  Atlas.Text.Checkin,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Files.DataFile;

function FolderOf(const AFileName: string): string;
var
  mIndex: Integer;
begin
  for mIndex := Length(AFileName) downto 1 do
  begin
    if (AFileName[mIndex] = '\') or (AFileName[mIndex] = '/') then
    begin
      Exit(Copy(AFileName, 1, mIndex - 1));
    end;
  end;
  Result := '';
end;

function Quote(const AText: string): string;
var
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(AText);
  try
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

function ReadProfile(AValue: TJSONValue; out AProfile: TAtlasStartProfile): Boolean;
var
  mEntry, mEnvironment: TJSONObject;
  mIndex: Integer;
  mVariable: TAtlasTeamVariable;
begin
  AProfile := Default(TAtlasStartProfile);
  Result := False;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mEntry := TJSONObject(AValue);
  AProfile.Name := Trim(TJsonRead.Text(mEntry, 'name'));
  AProfile.Parameters := TJsonRead.Text(mEntry, 'parameters');
  AProfile.WorkingDir := Trim(TJsonRead.Text(mEntry, 'workingDir'));
  AProfile.Host := Trim(TJsonRead.Text(mEntry, 'host'));
  if mEntry.GetValue('environment') is TJSONObject then
  begin
    mEnvironment := TJSONObject(mEntry.GetValue('environment'));
    for mIndex := 0 to mEnvironment.Count - 1 do
    begin
      if mEnvironment.Pairs[mIndex].JsonValue is TJSONString then
      begin
        mVariable.Name := Trim(mEnvironment.Pairs[mIndex].JsonString.Value);
        mVariable.Value := TJSONString(mEnvironment.Pairs[mIndex].JsonValue).Value;
        if mVariable.Name <> '' then
        begin
          AProfile.Environment := AProfile.Environment + [mVariable];
        end;
      end;
    end;
  end;
  Result := AProfile.Name <> '';
end;

function ReadOptions(AValue: TJSONValue; out AOptions: TAtlasStartOptions): Boolean;
begin
  AOptions := Default(TAtlasStartOptions);
  Result := AValue is TJSONObject;
  if not Result then
  begin
    Exit;
  end;
  AOptions.Parameters := TJsonRead.Text(TJSONObject(AValue), 'parameters');
  AOptions.WorkingDir := TJsonRead.Text(TJSONObject(AValue), 'workingDir');
  AOptions.Host := TJsonRead.Text(TJSONObject(AValue), 'host');
  AOptions.Environment := TJsonRead.Text(TJSONObject(AValue), 'environment');
end;

function ReadTemporary(AValue: TJSONValue; var AState: TAtlasStartProfileState): Boolean;
begin
  Result := ReadOptions(AValue, AState.TemporaryBefore);
  if Result then
  begin
    AState.TemporaryWritten := TJsonRead.Text(TJSONObject(AValue), 'written');
  end;
end;

function SplitEnvironment(const AText: string): TArray<string>;
var
  mIndex: Integer;
  mCurrent: string;
  mQuoted: Boolean;
begin
  Result := nil;
  mCurrent := '';
  mQuoted := False;
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = '"' then
    begin
      mQuoted := not mQuoted;
    end
    else if (AText[mIndex] = ';') and not mQuoted then
    begin
      Result := Result + [mCurrent];
      mCurrent := '';
    end
    else
    begin
      mCurrent := mCurrent + AText[mIndex];
    end;
  end;
  Result := Result + [mCurrent];
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
  mIndex: Integer;
begin
  for mIndex := 0 to High(Profiles) do
  begin
    if SameText(Profiles[mIndex].Name, Trim(AName)) then
    begin
      Exit(mIndex);
    end;
  end;
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
  mRoot: TJSONValue;
  mValue: TJSONValue;
  mIndex: Integer;
  mProfile: TAtlasStartProfile;
begin
  Result := Empty(AProject);
  AValid := False;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  mRoot := TJSONObject.ParseJSONValue(TJsoncScanner.StripComments(AText));
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mValue := TJSONObject(mRoot).GetValue('format');
    if (mValue is TJSONNumber) and (TJSONNumber(mValue).AsInt > cFormat) then
    begin
      Exit;
    end;
    AValid := True;
    if TJsonRead.Text(TJSONObject(mRoot), 'project') <> '' then
    begin
      Result.Project := TJsonRead.Text(TJSONObject(mRoot), 'project');
    end;
    Result.Active := Trim(TJsonRead.Text(TJSONObject(mRoot), 'active'));
    mValue := TJSONObject(mRoot).GetValue('profiles');
    if mValue is TJSONArray then
    begin
      for mIndex := 0 to TJSONArray(mValue).Count - 1 do
      begin
        if ReadProfile(TJSONArray(mValue).Items[mIndex], mProfile) and (Result.IndexOf(mProfile.Name) < 0) then
        begin
          Result.Profiles := Result.Profiles + [mProfile];
        end;
      end;
    end;
    Result.HasOriginal := ReadOptions(TJSONObject(mRoot).GetValue('original'), Result.Original);
    Result.HasTemporary := ReadTemporary(TJSONObject(mRoot).GetValue('temporary'), Result);
  finally
    mRoot.Free;
  end;
end;

class function TAtlasStartProfiles.Parse(const AText, AProject: string): TAtlasStartProfileState;
var
  mValid: Boolean;
begin
  Result := Parse(AText, AProject, mValid);
end;

class function TAtlasStartProfiles.FormatOf(const AText: string): Integer;
var
  mRoot, mValue: TJSONValue;
begin
  Result := 0;
  if Trim(AText) = '' then
  begin
    Exit;
  end;
  mRoot := TJSONObject.ParseJSONValue(TJsoncScanner.StripComments(AText));
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mValue := TJSONObject(mRoot).GetValue('format');
    if mValue is TJSONNumber then
    begin
      Result := TJSONNumber(mValue).AsInt;
    end;
  finally
    mRoot.Free;
  end;
end;

/// <summary>Ein Profil als JSON-Objekt, eingerückt wie in ToJson.</summary>
function ProfileJson(const AProfile: TAtlasStartProfile): string;
const
  cNewLine = #13#10;
var
  mVariable: Integer;
  mSeparator: string;
begin
  Result := cNewLine + '    {' + cNewLine +
    '      "name": ' + Quote(AProfile.Name) + ',' + cNewLine +
    '      "parameters": ' + Quote(AProfile.Parameters) + ',' + cNewLine +
    '      "workingDir": ' + Quote(AProfile.WorkingDir) + ',' + cNewLine +
    '      "host": ' + Quote(AProfile.Host) + ',' + cNewLine +
    '      "environment": {';
  mSeparator := '';
  for mVariable := 0 to High(AProfile.Environment) do
  begin
    Result := Result + mSeparator + Quote(AProfile.Environment[mVariable].Name) + ': ' +
      Quote(AProfile.Environment[mVariable].Value);
    mSeparator := ', ';
  end;
  Result := Result + '}' + cNewLine + '    }';
end;

class function TAtlasStartProfiles.ToJson(const AState: TAtlasStartProfileState): string;
const
  cNewLine = #13#10;
var
  mLines: TStringBuilder;
  mIndex: Integer;
begin
  mLines := TStringBuilder.Create;
  try
    mLines.Append('{' + cNewLine);
    mLines.Append('  "format": ' + IntToStr(cFormat) + ',' + cNewLine);
    mLines.Append('  "project": ' + Quote(AState.Project) + ',' + cNewLine);
    mLines.Append('  "active": ' + Quote(AState.Active) + ',' + cNewLine);
    mLines.Append('  "profiles": [');
    for mIndex := 0 to High(AState.Profiles) do
    begin
      if mIndex > 0 then
      begin
        mLines.Append(',');
      end;
      mLines.Append(ProfileJson(AState.Profiles[mIndex]));
    end;
    if Length(AState.Profiles) > 0 then
    begin
      mLines.Append(cNewLine + '  ');
    end;
    mLines.Append(']');
    if AState.HasOriginal then
    begin
      mLines.Append(',' + cNewLine + '  "original": {' + cNewLine);
      mLines.Append('    "parameters": ' + Quote(AState.Original.Parameters) + ',' + cNewLine);
      mLines.Append('    "workingDir": ' + Quote(AState.Original.WorkingDir) + ',' + cNewLine);
      mLines.Append('    "host": ' + Quote(AState.Original.Host) + ',' + cNewLine);
      mLines.Append('    "environment": ' + Quote(AState.Original.Environment) + cNewLine);
      mLines.Append('  }');
    end;
    if AState.HasTemporary then
    begin
      mLines.Append(',' + cNewLine + '  "temporary": {' + cNewLine);
      mLines.Append('    "parameters": ' + Quote(AState.TemporaryBefore.Parameters) + ',' + cNewLine);
      mLines.Append('    "workingDir": ' + Quote(AState.TemporaryBefore.WorkingDir) + ',' + cNewLine);
      mLines.Append('    "host": ' + Quote(AState.TemporaryBefore.Host) + ',' + cNewLine);
      mLines.Append('    "environment": ' + Quote(AState.TemporaryBefore.Environment) + ',' + cNewLine);
      mLines.Append('    "written": ' + Quote(AState.TemporaryWritten) + cNewLine);
      mLines.Append('  }');
    end;
    mLines.Append(cNewLine + '}' + cNewLine);
    Result := mLines.ToString;
  finally
    mLines.Free;
  end;
end;

class function TAtlasStartProfiles.Load(const AFolder, AProject: string): TAtlasStartProfileState;
var
  mFileName: string;
  mState: TAtlasStartProfileState;
  mValid: Boolean;
  mLoad: TAtlasDataLoad;
begin
  Result := Empty(AProject);
  if (AFolder = '') or (Trim(AProject) = '') then
  begin
    Exit;
  end;
  mFileName := FileFor(AFolder, AProject);
  mValid := False;
  mLoad := TAtlasDataFile.Load(mFileName, 'Startprofile',
    function(const AText: string): Boolean
    begin
      mState := Parse(AText, AProject, mValid);
      // Ein höheres Format ist nicht unbrauchbar: nicht beiseitelegen; Save überschreibt es nicht.
      Result := mValid or (FormatOf(AText) > cFormat);
    end);
  if mValid and (mLoad = TAtlasDataLoad.Loaded) then
  begin
    Result := mState;
  end
  else if not TAtlasDataFile.Writable(mLoad) then
  begin
    Result.KeptFile := mFileName;
  end;
end;

class function TAtlasStartProfiles.Save(const AFolder: string; const AState: TAtlasStartProfileState): Boolean;
var
  mFileName, mText: string;
begin
  Result := False;
  if (AFolder = '') or (Trim(AState.Project) = '') then
  begin
    Exit;
  end;
  mFileName := FileFor(AFolder, AState.Project);
  // Beim Laden gesperrt: Der Stand kennt den Inhalt der Datei nicht.
  if SameFileName(mFileName, AState.KeptFile) then
  begin
    Exit;
  end;
  try
    // Eine neuere Fassung hat die Datei geschrieben oder sie ist gerade nicht lesbar: nicht überschreiben.
    if FileExists(mFileName) and (not TAtlasDataFile.TryRead(mFileName, mText) or (FormatOf(mText) > cFormat)) then
    begin
      Exit;
    end;
    // Atomar ersetzt, UTF-8 ohne BOM.
    TAtlasDataFile.Write(mFileName, ToJson(AState));
    Result := True;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Startprofile', E);
  end;
end;

class function TAtlasStartProfiles.Merge(const ATeam: TAtlasTeamSettings;
  const AState: TAtlasStartProfileState): TArray<TAtlasStartProfileEntry>;
var
  mEntry, mKnown: TAtlasStartProfileEntry;
  mProfile: TAtlasStartProfile;
  mCandidates: TArray<TAtlasStartProfileEntry>;
  mFound: Boolean;
begin
  Result := nil;
  mCandidates := nil;
  if ATeam.Valid then
  begin
    for mProfile in ATeam.StartProfiles do
    begin
      mEntry.Profile := mProfile;
      mEntry.Source := TAtlasStartProfileSource.Team;
      mEntry.BaseFolder := ATeam.Folder;
      mCandidates := mCandidates + [mEntry];
    end;
  end;
  for mProfile in AState.Profiles do
  begin
    mEntry.Profile := mProfile;
    mEntry.Source := TAtlasStartProfileSource.Personal;
    mEntry.BaseFolder := FolderOf(AState.Project);
    mCandidates := mCandidates + [mEntry];
  end;
  for mEntry in mCandidates do
  begin
    mFound := False;
    for mKnown in Result do
    begin
      if SameText(mKnown.Profile.Name, mEntry.Profile.Name) then
      begin
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Result := Result + [mEntry];
    end;
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
  mEntry: TAtlasStartProfileEntry;
begin
  AEntry := Default(TAtlasStartProfileEntry);
  Result := False;
  if Trim(AName) = '' then
  begin
    Exit;
  end;
  for mEntry in AEntries do
  begin
    if SameText(mEntry.Profile.Name, Trim(AName)) then
    begin
      AEntry := mEntry;
      Exit(True);
    end;
  end;
end;

class function TAtlasStartProfiles.ResolvePath(const ABase, APath: string): string;
var
  mPath: string;
begin
  mPath := Trim(APath);
  if (mPath = '') or (Copy(mPath, 1, 2) = '$(') or TTextCheckin.IsAbsolutePath(mPath) or (ABase = '') then
  begin
    Exit(mPath);
  end;
  Result := TAtlasTeamFile.Combine(ABase, mPath);
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
  mVariable: TAtlasTeamVariable;
  mItem: string;
begin
  Result := '';
  for mVariable in AVariables do
  begin
    if Trim(mVariable.Name) = '' then
    begin
      Continue;
    end;
    mItem := Trim(mVariable.Name) + '=' + StringReplace(mVariable.Value, '"', '', [rfReplaceAll]);
    if Pos(';', mItem) > 0 then
    begin
      mItem := '"' + mItem + '"';
    end;
    if Result <> '' then
    begin
      Result := Result + ';';
    end;
    Result := Result + mItem;
  end;
end;

class function TAtlasStartProfiles.EnvironmentValue(const AVariables: TArray<TAtlasTeamVariable>): string;
begin
  Result := EncodeEnvironment(AVariables);
  if Result <> '' then
  begin
    Result := Result + ';' + cInheritEnvironment;
  end;
end;

class function TAtlasStartProfiles.DecodeEnvironment(const AText: string): TArray<TAtlasTeamVariable>;
var
  mItem: string;
  mVariable: TAtlasTeamVariable;
  mEquals: Integer;
begin
  Result := nil;
  for mItem in SplitEnvironment(AText) do
  begin
    if SameText(Trim(mItem), cInheritEnvironment) then
    begin
      Continue;
    end;
    mEquals := Pos('=', mItem);
    if mEquals <= 1 then
    begin
      Continue;
    end;
    mVariable.Name := Trim(Copy(mItem, 1, mEquals - 1));
    mVariable.Value := Copy(mItem, mEquals + 1, MaxInt);
    if mVariable.Name <> '' then
    begin
      Result := Result + [mVariable];
    end;
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
  mIndex: Integer;
  mProfile: TAtlasStartProfile;
begin
  mProfile := AProfile;
  mProfile.Name := Trim(mProfile.Name);
  Result := mProfile.Name <> '';
  if not Result then
  begin
    Exit;
  end;
  mIndex := AState.IndexOf(mProfile.Name);
  if mIndex >= 0 then
  begin
    AState.Profiles[mIndex] := mProfile;
  end
  else
  begin
    AState.Profiles := AState.Profiles + [mProfile];
  end;
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
