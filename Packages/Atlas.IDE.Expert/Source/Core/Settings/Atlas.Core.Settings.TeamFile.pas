unit Atlas.Core.Settings.TeamFile;

// Projektdatei .atlas (#486): Einstellungen des Plugins für alle im Team, im
// Repository eingecheckt. Persönliche Einstellungen (Registry) bleiben davon
// getrennt; die Einstellungen des Servers stehen in atlas.json (#403). Teil
// ohne VCL und Open Tools API: Datei finden, lesen, prüfen und den Vorrang vor
// den persönlichen Einstellungen bestimmen.
// - Ort: Ordner der .dproj, sonst der nächsthöhere Ordner mit .git (Wurzel des
//   Repositorys). Relative Pfade gelten ab dem Ordner der Datei.
// - Format: JSON mit Kommentaren (// und /* */) und Schema-Version:
//     {"version": 1,
//      "naming": {"field": "F", "parameter": "A", "local": "L"},        #452
//      "snippets": "Vorlagen\\Snippets",                               #51
//      "formatFunctions": [{"name": "Log", "formatIndex": 0}],         #451
//      "sqlTargets": ["TMyQuery.SQL"],                                  #462
//      "fileMethods": ["TDateien.Laden"],                               #478
//      "mainThreadExceptions": ["TLogger.Write"],                       #484
//      "startProfiles": [{"name": "Demo", "parameters": "-demo",        #575
//        "workingDir": "Bin", "host": "", "environment": {"MODUS": "demo"}}],
//      "ci": {"provider": "jenkins", "url": "https://ci.firma.de",      #763
//             "job": "kasse", "multibranch": true},
//      "tracker": {"provider": "youtrack",                              #765
//                  "url": "https://firma.youtrack.cloud", "project": "ATL"}}
// - Verboten und beim Lesen ignoriert (mit Meldung, Atlas.Text.Checkin):
//   Zugangsdaten (Schlüssel wie token oder password auf jeder Ebene, Adressen
//   mit Benutzer oder Token, Umgebungsvariablen wie DB_PASSWORD), absolute
//   Pfade und relative Pfade, die aus der Wurzel herausführen. Ein Startprofil
//   mit solchem Inhalt entfällt ganz. Benutzer und Token für CI und Tracker
//   gehören in den Anmeldespeicher von Windows.
// - Fehlerhafte Datei (kein JSON oder kein Objekt): Valid ist False, es gelten
//   nur die persönlichen Einstellungen. Unbekannte Schlüssel und falsche Typen
//   werden gemeldet und übergangen; der Rest gilt.
// - Vorrang: ein Wert aus .atlas schlägt die persönliche Einstellung (Präfixe,
//   Format-Index und Startprofil gleichen Namens); Listen ergänzen sich, die
//   Einträge der Projektdatei zuerst.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Präfix-Arten der Benennung (#452).</summary>
  TAtlasNamingKind = (Field, Parameter, Local);

  /// <summary>Art einer Meldung zur Projektdatei.</summary>
  TAtlasTeamIssueKind = (
    /// <summary>Kein JSON oder kein Objekt; die Datei gilt nicht.</summary>
    Syntax,
    /// <summary>"version" fehlt oder ist neuer als CurrentVersion.</summary>
    Version,
    UnknownKey,
    WrongType,
    InvalidValue,
    Credential,
    AbsolutePath,
    OutsidePath);
{$SCOPEDENUMS OFF}

  /// <summary>Meldung zur Projektdatei; den Text bildet die Oberfläche aus Kind und Path.</summary>
  TAtlasTeamIssue = record
    Kind: TAtlasTeamIssueKind;
    /// <summary>Betroffene Einstellung, z. B. "naming.field" oder "startProfiles[Demo].host"; '' für die Datei.
    /// </summary>
    Path: string;
    class function Create(AKind: TAtlasTeamIssueKind; const APath: string): TAtlasTeamIssue; static;
  end;

  /// <summary>Format-artige Funktion mit dem Index ihres Formatparameters (ab 0, #451).</summary>
  TAtlasFormatFunction = record
    Name: string;
    FormatIndex: Integer;
    class function Create(const AName: string; AFormatIndex: Integer): TAtlasFormatFunction; static;
  end;

  TAtlasTeamVariable = record
    Name: string;
    Value: string;
  end;

  /// <summary>Gemeinsames Startprofil (#575, Schnellaktion „Startprofil“ #764).</summary>
  TAtlasStartProfile = record
    Name: string;
    Parameters: string;
    /// <summary>Arbeitsordner relativ zur Projektdatei; '' = Vorgabe der IDE.</summary>
    WorkingDir: string;
    /// <summary>Host-Anwendung relativ zur Projektdatei oder mit Makro ($(BDS)…); '' = keine.</summary>
    Host: string;
    Environment: TArray<TAtlasTeamVariable>;
  end;

  /// <summary>Build-Server des Projekts (#763); Benutzer und Token im Anmeldespeicher von Windows.</summary>
  TAtlasTeamCi = record
    /// <summary>"jenkins".</summary>
    Provider: string;
    Url: string;
    Job: string;
    /// <summary>Multibranch-Job: es gilt der Job des aktuellen Branches.</summary>
    Multibranch: Boolean;
    function Configured: Boolean;
  end;

  /// <summary>Issue-Tracker des Projekts (#765); das Token im Anmeldespeicher von Windows.</summary>
  TAtlasTeamTracker = record
    /// <summary>"github" oder "youtrack".</summary>
    Provider: string;
    Url: string;
    /// <summary>Projektkürzel (YouTrack "ATL") bzw. "owner/repo" (GitHub).</summary>
    Project: string;
    function Configured: Boolean;
  end;

  /// <summary>Eine Zeile der Anzeige „aus .atlas“.</summary>
  TAtlasTeamValue = record
    Key: string;
    Value: string;
  end;

  /// <summary>Inhalt der Projektdatei nach dem Lesen; nur erlaubte Werte.</summary>
  TAtlasTeamSettings = record
    /// <summary>.dproj, für die der Stand gilt; '' ohne Projekt (setzt die IDE-Schicht).</summary>
    Project: string;
    /// <summary>Vollständiger Pfad der Datei; '' ohne Projektdatei.</summary>
    FileName: string;
    /// <summary>Ordner der Datei; Basis relativer Pfade.</summary>
    Folder: string;
    /// <summary>Wurzel, die kein Pfad verlassen darf (Repository, sonst Folder).</summary>
    Root: string;
    /// <summary>Datei ist JSON mit einem Objekt; sonst gelten nur die persönlichen Einstellungen.</summary>
    Valid: Boolean;
    Version: Integer;
    Naming: array[TAtlasNamingKind] of string;
    HasNaming: array[TAtlasNamingKind] of Boolean;
    /// <summary>Ordner der Projekt-Snippets, wie in der Datei (relativ); '' = keiner.</summary>
    Snippets: string;
    FormatFunctions: TArray<TAtlasFormatFunction>;
    SqlTargets: TArray<string>;
    FileMethods: TArray<string>;
    MainThreadExceptions: TArray<string>;
    StartProfiles: TArray<TAtlasStartProfile>;
    Ci: TAtlasTeamCi;
    Tracker: TAtlasTeamTracker;
    Issues: TArray<TAtlasTeamIssue>;
    /// <summary>Es gibt eine Projektdatei (gültig oder nicht).</summary>
    function Exists: Boolean;
    /// <summary>Vollständiger Ordner der Projekt-Snippets; '' ohne.</summary>
    function SnippetFolder: string;
    /// <summary>Die Datei setzt mindestens einen Wert.</summary>
    function HasValues: Boolean;
    function IndexOfProfile(const AName: string): Integer;
  end;

  /// <summary>Gibt es die Datei bzw. den Ordner (.git darf beides sein)?</summary>
  TAtlasTeamFileExists = reference to function(const APath: string): Boolean;

  TAtlasTeamFile = class
  public const
    FileName = '.atlas';
    CurrentVersion = 1;
  public
    /// <summary>Projektdatei zum Ordner einer .dproj: dort, sonst im nächsthöheren Ordner mit .git; '' ohne.
    /// </summary>
    class function Locate(const AProjectFolder: string; const AExists: TAtlasTeamFileExists): string; static;
    /// <summary>Nächster Ordner mit .git ab AFolder aufwärts, sonst AFolder.</summary>
    class function RootOf(const AFolder: string; const AExists: TAtlasTeamFileExists): string; static;
    /// <summary>Liest den Text der Datei AFileName; ARoot begrenzt die Pfade ('' = Ordner der Datei).</summary>
    class function Parse(const AText, AFileName, ARoot: string): TAtlasTeamSettings; static;
    /// <summary>Ohne Projektdatei.</summary>
    class function Empty: TAtlasTeamSettings; static;
    /// <summary>Inhalt einer neuen Projektdatei mit Version und Beispielen als Kommentar.</summary>
    class function Skeleton: string; static;
    /// <summary>Präfix aus der Projektdatei, sonst APersonal.</summary>
    class function Prefix(const ATeam: TAtlasTeamSettings; AKind: TAtlasNamingKind;
      const APersonal: string): string; static;
    /// <summary>Einträge von ATeam, dann die von APersonal, die dort fehlen (ohne Groß-/Kleinschreibung).</summary>
    class function MergeNames(const ATeam, APersonal: TArray<string>): TArray<string>; static;
    /// <summary>Wie MergeNames; bei gleichem Namen gilt der Index aus ATeam.</summary>
    class function MergeFormatFunctions(const ATeam,
      APersonal: TArray<TAtlasFormatFunction>): TArray<TAtlasFormatFunction>; static;
    /// <summary>Wie MergeNames; bei gleichem Namen gilt das Profil aus ATeam.</summary>
    class function MergeStartProfiles(const ATeam,
      APersonal: TArray<TAtlasStartProfile>): TArray<TAtlasStartProfile>; static;
    /// <summary>Gesetzte Werte zur Anzeige „aus .atlas“, in der Reihenfolge des Formats.</summary>
    class function Values(const ATeam: TAtlasTeamSettings): TArray<TAtlasTeamValue>; static;
    /// <summary>Schlüssel einer Präfix-Art: "field", "parameter", "local".</summary>
    class function NamingKey(AKind: TAtlasNamingKind): string; static;
    /// <summary>ARelative an AFolder gehängt, „.“ und „..“ aufgelöst, Trenner „\“.</summary>
    class function Combine(const AFolder, ARelative: string): string; static;
  end;

implementation

uses
  System.JSON,
  Atlas.Text.Jsonc,
  Atlas.Text.Checkin;

const
  NamingKeys: array[TAtlasNamingKind] of string = ('field', 'parameter', 'local');

function IsSeparator(ACh: Char): Boolean;
begin
  Result := (ACh = '\') or (ACh = '/');
end;

function WithoutTrailing(const APath: string): string;
begin
  Result := APath;
  while (Length(Result) > 1) and IsSeparator(Result[Length(Result)]) do
    Delete(Result, Length(Result), 1);
end;

function JoinPath(const AFolder, AName: string): string;
begin
  Result := WithoutTrailing(AFolder) + '\' + AName;
end;

/// <summary>Übergeordneter Ordner; '' oberhalb von Laufwerk oder Server.</summary>
function ParentOf(const AFolder: string): string;
var
  Path: string;
  Index: Integer;
begin
  Result := '';
  Path := WithoutTrailing(AFolder);
  for Index := Length(Path) downto 1 do
    if IsSeparator(Path[Index]) then
    begin
      Result := Copy(Path, 1, Index - 1);
      Break;
    end;
  if (Result <> '') and IsSeparator(Result[Length(Result)]) then
    Result := '';
end;

function FolderOf(const AFileName: string): string;
var
  Index: Integer;
begin
  for Index := Length(AFileName) downto 1 do
    if IsSeparator(AFileName[Index]) then
      Exit(Copy(AFileName, 1, Index - 1));
  Result := '';
end;

function IsPrefixText(const AText: string): Boolean;
var
  Ch: Char;
begin
  for Ch in AText do
    if not CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Exit(False);
  Result := True;
end;

function IsHttpUrl(const AText: string): Boolean;
var
  Lower: string;
begin
  Lower := LowerCase(AText);
  Result := (Copy(Lower, 1, 7) = 'http://') or (Copy(Lower, 1, 8) = 'https://');
end;

{ TAtlasTeamIssue }

class function TAtlasTeamIssue.Create(AKind: TAtlasTeamIssueKind; const APath: string): TAtlasTeamIssue;
begin
  Result.Kind := AKind;
  Result.Path := APath;
end;

{ TAtlasFormatFunction }

class function TAtlasFormatFunction.Create(const AName: string; AFormatIndex: Integer): TAtlasFormatFunction;
begin
  Result.Name := AName;
  Result.FormatIndex := AFormatIndex;
end;

{ TAtlasTeamCi }

function TAtlasTeamCi.Configured: Boolean;
begin
  Result := (Provider <> '') and (Url <> '') and (Job <> '');
end;

{ TAtlasTeamTracker }

function TAtlasTeamTracker.Configured: Boolean;
begin
  Result := (Provider <> '') and (Url <> '');
end;

{ TAtlasTeamSettings }

function TAtlasTeamSettings.Exists: Boolean;
begin
  Result := FileName <> '';
end;

function TAtlasTeamSettings.SnippetFolder: string;
begin
  Result := '';
  if Snippets <> '' then
    Result := TAtlasTeamFile.Combine(Folder, Snippets);
end;

function TAtlasTeamSettings.HasValues: Boolean;
begin
  Result := Length(TAtlasTeamFile.Values(Self)) > 0;
end;

function TAtlasTeamSettings.IndexOfProfile(const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(StartProfiles) do
    if SameText(StartProfiles[Index].Name, AName) then
      Exit(Index);
  Result := -1;
end;

type
  /// <summary>Liest das Wurzelobjekt der Projektdatei in TAtlasTeamSettings.</summary>
  TTeamReader = class
  private
    FTeam: TAtlasTeamSettings;
    procedure Report(AKind: TAtlasTeamIssueKind; const APath: string);
    /// <summary>Meldet AKey als Zugangsdaten, wenn er danach aussieht.</summary>
    function IsCredential(const AKey, APath: string): Boolean;
    /// <summary>Meldet Zugangsdaten in einem unbekannten Wert (Schlüssel, Adressen).</summary>
    procedure ScanCredentials(AValue: TJSONValue; const APath: string);
    function ReadString(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
    function ReadUrl(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
    /// <summary>Relativer Pfad, der in der Wurzel bleibt.</summary>
    function ReadPath(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
    function ReadNames(AValue: TJSONValue; const APath: string): TArray<string>;
    procedure ReadNaming(AValue: TJSONValue);
    procedure ReadFormatFunctions(AValue: TJSONValue);
    function ReadEnvironment(AValue: TJSONValue; const APath: string;
      out AVariables: TArray<TAtlasTeamVariable>): Boolean;
    function ReadStartProfile(AValue: TJSONValue; const APath: string; out AProfile: TAtlasStartProfile): Boolean;
    procedure ReadStartProfiles(AValue: TJSONValue);
    procedure ReadCi(AValue: TJSONValue);
    procedure ReadTracker(AValue: TJSONValue);
    procedure ReadVersion(AValue: TJSONValue);
  public
    constructor Create(const AFileName, ARoot: string);
    procedure Read(ARoot: TJSONObject);
    procedure Invalid;
    property Team: TAtlasTeamSettings read FTeam;
  end;

constructor TTeamReader.Create(const AFileName, ARoot: string);
begin
  inherited Create;
  FTeam := TAtlasTeamFile.Empty;
  FTeam.FileName := AFileName;
  FTeam.Folder := FolderOf(AFileName);
  FTeam.Root := ARoot;
  if FTeam.Root = '' then
    FTeam.Root := FTeam.Folder;
end;

procedure TTeamReader.Report(AKind: TAtlasTeamIssueKind; const APath: string);
begin
  FTeam.Issues := FTeam.Issues + [TAtlasTeamIssue.Create(AKind, APath)];
end;

procedure TTeamReader.Invalid;
begin
  FTeam.Valid := False;
  Report(TAtlasTeamIssueKind.Syntax, '');
end;

function TTeamReader.IsCredential(const AKey, APath: string): Boolean;
begin
  Result := TTextCheckin.IsCredentialKey(AKey);
  if Result then
    Report(TAtlasTeamIssueKind.Credential, APath);
end;

procedure TTeamReader.ScanCredentials(AValue: TJSONValue; const APath: string);
var
  Index: Integer;
  Key: string;
begin
  if AValue is TJSONObject then
    for Index := 0 to TJSONObject(AValue).Count - 1 do
    begin
      Key := TJSONObject(AValue).Pairs[Index].JsonString.Value;
      if not IsCredential(Key, APath + '.' + Key) then
        ScanCredentials(TJSONObject(AValue).Pairs[Index].JsonValue, APath + '.' + Key);
    end
  else if AValue is TJSONArray then
    for Index := 0 to TJSONArray(AValue).Count - 1 do
      ScanCredentials(TJSONArray(AValue).Items[Index], APath)
  else if (AValue is TJSONString) and TTextCheckin.HasUrlCredentials(TJSONString(AValue).Value) then
    Report(TAtlasTeamIssueKind.Credential, APath);
end;

function TTeamReader.ReadString(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
begin
  AText := '';
  Result := AValue is TJSONString;
  if not Result then
  begin
    Report(TAtlasTeamIssueKind.WrongType, APath);
    Exit;
  end;
  AText := Trim(TJSONString(AValue).Value);
  if TTextCheckin.HasUrlCredentials(AText) then
  begin
    Report(TAtlasTeamIssueKind.Credential, APath);
    AText := '';
    Result := False;
  end;
end;

function TTeamReader.ReadUrl(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
begin
  Result := ReadString(AValue, APath, AText);
  if Result and (AText <> '') and not IsHttpUrl(AText) then
  begin
    Report(TAtlasTeamIssueKind.InvalidValue, APath);
    AText := '';
    Result := False;
  end;
end;

function TTeamReader.ReadPath(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
begin
  Result := ReadString(AValue, APath, AText);
  if not Result or (AText = '') then
    Exit;
  if TTextCheckin.IsAbsolutePath(AText) then
    Report(TAtlasTeamIssueKind.AbsolutePath, APath)
  else if not TTextCheckin.StaysInside(FTeam.Root, FTeam.Folder, AText) then
    Report(TAtlasTeamIssueKind.OutsidePath, APath)
  else
    Exit(True);
  AText := '';
  Result := False;
end;

function TTeamReader.ReadNames(AValue: TJSONValue; const APath: string): TArray<string>;
var
  Index: Integer;
  Item, Text: string;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Report(TAtlasTeamIssueKind.WrongType, APath);
    Exit;
  end;
  for Index := 0 to TJSONArray(AValue).Count - 1 do
  begin
    Item := Format('%s[%d]', [APath, Index]);
    if not ReadString(TJSONArray(AValue).Items[Index], Item, Text) then
      Continue;
    if Text = '' then
      Report(TAtlasTeamIssueKind.InvalidValue, Item)
    else
      Result := Result + [Text];
  end;
end;

procedure TTeamReader.ReadNaming(AValue: TJSONValue);
var
  Index: Integer;
  Key, Path, Text: string;
  Kind: TAtlasNamingKind;
  Known: Boolean;
begin
  if not (AValue is TJSONObject) then
  begin
    Report(TAtlasTeamIssueKind.WrongType, 'naming');
    Exit;
  end;
  for Index := 0 to TJSONObject(AValue).Count - 1 do
  begin
    Key := TJSONObject(AValue).Pairs[Index].JsonString.Value;
    Path := 'naming.' + Key;
    if IsCredential(Key, Path) then
      Continue;
    Known := False;
    for Kind := Low(TAtlasNamingKind) to High(TAtlasNamingKind) do
      if Key = NamingKeys[Kind] then
      begin
        Known := True;
        if not ReadString(TJSONObject(AValue).Pairs[Index].JsonValue, Path, Text) then
          Break;
        if not IsPrefixText(Text) then
        begin
          Report(TAtlasTeamIssueKind.InvalidValue, Path);
          Break;
        end;
        FTeam.Naming[Kind] := Text;
        FTeam.HasNaming[Kind] := True;
      end;
    if not Known then
      Report(TAtlasTeamIssueKind.UnknownKey, Path);
  end;
end;

procedure TTeamReader.ReadFormatFunctions(AValue: TJSONValue);
var
  Index, Pair, FormatIndex: Integer;
  Item, Key, Name: string;
  Entry: TJSONObject;
  Value: TJSONValue;
  Ok: Boolean;
begin
  if not (AValue is TJSONArray) then
  begin
    Report(TAtlasTeamIssueKind.WrongType, 'formatFunctions');
    Exit;
  end;
  for Index := 0 to TJSONArray(AValue).Count - 1 do
  begin
    Item := Format('formatFunctions[%d]', [Index]);
    if not (TJSONArray(AValue).Items[Index] is TJSONObject) then
    begin
      Report(TAtlasTeamIssueKind.WrongType, Item);
      Continue;
    end;
    Entry := TJSONObject(TJSONArray(AValue).Items[Index]);
    Name := '';
    FormatIndex := -1;
    Ok := True;
    for Pair := 0 to Entry.Count - 1 do
    begin
      Key := Entry.Pairs[Pair].JsonString.Value;
      Value := Entry.Pairs[Pair].JsonValue;
      if IsCredential(Key, Item + '.' + Key) then
        Continue;
      if Key = 'name' then
        Ok := ReadString(Value, Item + '.name', Name) and Ok
      else if Key = 'formatIndex' then
      begin
        if Value is TJSONNumber then
          FormatIndex := TJSONNumber(Value).AsInt
        else
        begin
          Report(TAtlasTeamIssueKind.WrongType, Item + '.formatIndex');
          Ok := False;
        end;
      end
      else
        Report(TAtlasTeamIssueKind.UnknownKey, Item + '.' + Key);
    end;
    if not Ok then
      Continue;
    if (Name = '') or (FormatIndex < 0) then
    begin
      Report(TAtlasTeamIssueKind.InvalidValue, Item);
      Continue;
    end;
    FTeam.FormatFunctions := TAtlasTeamFile.MergeFormatFunctions(FTeam.FormatFunctions,
      [TAtlasFormatFunction.Create(Name, FormatIndex)]);
  end;
end;

function TTeamReader.ReadEnvironment(AValue: TJSONValue; const APath: string;
  out AVariables: TArray<TAtlasTeamVariable>): Boolean;
var
  Index: Integer;
  Variable: TAtlasTeamVariable;
  Path: string;
begin
  AVariables := nil;
  if not (AValue is TJSONObject) then
  begin
    Report(TAtlasTeamIssueKind.WrongType, APath);
    Exit(False);
  end;
  Result := True;
  for Index := 0 to TJSONObject(AValue).Count - 1 do
  begin
    Variable.Name := TJSONObject(AValue).Pairs[Index].JsonString.Value;
    Path := APath + '.' + Variable.Name;
    if TTextCheckin.IsCredentialName(Variable.Name) then
    begin
      Report(TAtlasTeamIssueKind.Credential, Path);
      Result := False;
      Continue;
    end;
    if not ReadString(TJSONObject(AValue).Pairs[Index].JsonValue, Path, Variable.Value) then
    begin
      Result := False;
      Continue;
    end;
    if TTextCheckin.ContainsMachinePath(Variable.Value) then
    begin
      Report(TAtlasTeamIssueKind.AbsolutePath, Path);
      Result := False;
      Continue;
    end;
    AVariables := AVariables + [Variable];
  end;
end;

function TTeamReader.ReadStartProfile(AValue: TJSONValue; const APath: string;
  out AProfile: TAtlasStartProfile): Boolean;
var
  Index: Integer;
  Entry: TJSONObject;
  Key, Path: string;
  Value: TJSONValue;
begin
  AProfile := Default(TAtlasStartProfile);
  if not (AValue is TJSONObject) then
  begin
    Report(TAtlasTeamIssueKind.WrongType, APath);
    Exit(False);
  end;
  Entry := TJSONObject(AValue);
  Path := APath;
  Value := Entry.GetValue('name');
  if (Value is TJSONString) and (Trim(TJSONString(Value).Value) <> '') then
    Path := Format('startProfiles[%s]', [Trim(TJSONString(Value).Value)]);
  Result := True;
  for Index := 0 to Entry.Count - 1 do
  begin
    Key := Entry.Pairs[Index].JsonString.Value;
    Value := Entry.Pairs[Index].JsonValue;
    if IsCredential(Key, Path + '.' + Key) then
      Result := False
    else if Key = 'name' then
      Result := ReadString(Value, Path + '.name', AProfile.Name) and Result
    else if Key = 'parameters' then
    begin
      if not ReadString(Value, Path + '.parameters', AProfile.Parameters) then
        Result := False
      else if TTextCheckin.ContainsMachinePath(AProfile.Parameters) then
      begin
        Report(TAtlasTeamIssueKind.AbsolutePath, Path + '.parameters');
        Result := False;
      end;
    end
    else if Key = 'workingDir' then
      Result := ReadPath(Value, Path + '.workingDir', AProfile.WorkingDir) and Result
    else if Key = 'host' then
      Result := ReadPath(Value, Path + '.host', AProfile.Host) and Result
    else if Key = 'environment' then
      Result := ReadEnvironment(Value, Path + '.environment', AProfile.Environment) and Result
    else
    begin
      Report(TAtlasTeamIssueKind.UnknownKey, Path + '.' + Key);
      ScanCredentials(Value, Path + '.' + Key);
    end;
  end;
  if Result and (AProfile.Name = '') then
  begin
    Report(TAtlasTeamIssueKind.InvalidValue, Path + '.name');
    Result := False;
  end;
end;

procedure TTeamReader.ReadStartProfiles(AValue: TJSONValue);
var
  Index: Integer;
  Profile: TAtlasStartProfile;
begin
  if not (AValue is TJSONArray) then
  begin
    Report(TAtlasTeamIssueKind.WrongType, 'startProfiles');
    Exit;
  end;
  for Index := 0 to TJSONArray(AValue).Count - 1 do
  begin
    if not ReadStartProfile(TJSONArray(AValue).Items[Index], Format('startProfiles[%d]', [Index]), Profile) then
      Continue;
    if FTeam.IndexOfProfile(Profile.Name) >= 0 then
      Report(TAtlasTeamIssueKind.InvalidValue, Format('startProfiles[%s]', [Profile.Name]))
    else
      FTeam.StartProfiles := FTeam.StartProfiles + [Profile];
  end;
end;

procedure TTeamReader.ReadCi(AValue: TJSONValue);
var
  Index: Integer;
  Key, Path: string;
  Value: TJSONValue;
  Ci: TAtlasTeamCi;
begin
  if not (AValue is TJSONObject) then
  begin
    Report(TAtlasTeamIssueKind.WrongType, 'ci');
    Exit;
  end;
  Ci := Default(TAtlasTeamCi);
  Ci.Provider := 'jenkins';
  for Index := 0 to TJSONObject(AValue).Count - 1 do
  begin
    Key := TJSONObject(AValue).Pairs[Index].JsonString.Value;
    Value := TJSONObject(AValue).Pairs[Index].JsonValue;
    Path := 'ci.' + Key;
    if IsCredential(Key, Path) then
      Continue;
    if Key = 'provider' then
    begin
      if ReadString(Value, Path, Ci.Provider) then
      begin
        Ci.Provider := LowerCase(Ci.Provider);
        if Ci.Provider <> 'jenkins' then
        begin
          Report(TAtlasTeamIssueKind.InvalidValue, Path);
          Exit;
        end;
      end
      else
        Exit;
    end
    else if Key = 'url' then
      ReadUrl(Value, Path, Ci.Url)
    else if Key = 'job' then
      ReadString(Value, Path, Ci.Job)
    else if Key = 'multibranch' then
    begin
      if Value is TJSONBool then
        Ci.Multibranch := TJSONBool(Value).AsBoolean
      else
        Report(TAtlasTeamIssueKind.WrongType, Path);
    end
    else
    begin
      Report(TAtlasTeamIssueKind.UnknownKey, Path);
      ScanCredentials(Value, Path);
    end;
  end;
  FTeam.Ci := Ci;
end;

procedure TTeamReader.ReadTracker(AValue: TJSONValue);
var
  Index: Integer;
  Key, Path: string;
  Value: TJSONValue;
  Tracker: TAtlasTeamTracker;
begin
  if not (AValue is TJSONObject) then
  begin
    Report(TAtlasTeamIssueKind.WrongType, 'tracker');
    Exit;
  end;
  Tracker := Default(TAtlasTeamTracker);
  for Index := 0 to TJSONObject(AValue).Count - 1 do
  begin
    Key := TJSONObject(AValue).Pairs[Index].JsonString.Value;
    Value := TJSONObject(AValue).Pairs[Index].JsonValue;
    Path := 'tracker.' + Key;
    if IsCredential(Key, Path) then
      Continue;
    if Key = 'provider' then
    begin
      if ReadString(Value, Path, Tracker.Provider) then
      begin
        Tracker.Provider := LowerCase(Tracker.Provider);
        if (Tracker.Provider <> 'github') and (Tracker.Provider <> 'youtrack') then
        begin
          Report(TAtlasTeamIssueKind.InvalidValue, Path);
          Exit;
        end;
      end
      else
        Exit;
    end
    else if Key = 'url' then
      ReadUrl(Value, Path, Tracker.Url)
    else if Key = 'project' then
      ReadString(Value, Path, Tracker.Project)
    else
    begin
      Report(TAtlasTeamIssueKind.UnknownKey, Path);
      ScanCredentials(Value, Path);
    end;
  end;
  if (Tracker.Provider = '') and (Tracker.Url <> '') then
  begin
    Report(TAtlasTeamIssueKind.InvalidValue, 'tracker.provider');
    Exit;
  end;
  FTeam.Tracker := Tracker;
end;

procedure TTeamReader.ReadVersion(AValue: TJSONValue);
var
  Version: Integer;
begin
  if not (AValue is TJSONNumber) then
  begin
    Report(TAtlasTeamIssueKind.WrongType, 'version');
    Exit;
  end;
  Version := TJSONNumber(AValue).AsInt;
  if Version < 1 then
  begin
    Report(TAtlasTeamIssueKind.InvalidValue, 'version');
    Exit;
  end;
  FTeam.Version := Version;
  if Version > TAtlasTeamFile.CurrentVersion then
    Report(TAtlasTeamIssueKind.Version, 'version');
end;

procedure TTeamReader.Read(ARoot: TJSONObject);
var
  Index: Integer;
  Key: string;
  Value: TJSONValue;
  HasVersion: Boolean;
begin
  FTeam.Valid := True;
  HasVersion := False;
  for Index := 0 to ARoot.Count - 1 do
  begin
    Key := ARoot.Pairs[Index].JsonString.Value;
    Value := ARoot.Pairs[Index].JsonValue;
    if IsCredential(Key, Key) or (Key = '$schema') then
      Continue;
    if Key = 'version' then
    begin
      HasVersion := True;
      ReadVersion(Value);
    end
    else if Key = 'naming' then
      ReadNaming(Value)
    else if Key = 'snippets' then
      ReadPath(Value, Key, FTeam.Snippets)
    else if Key = 'formatFunctions' then
      ReadFormatFunctions(Value)
    else if Key = 'sqlTargets' then
      FTeam.SqlTargets := TAtlasTeamFile.MergeNames(ReadNames(Value, Key), nil)
    else if Key = 'fileMethods' then
      FTeam.FileMethods := TAtlasTeamFile.MergeNames(ReadNames(Value, Key), nil)
    else if Key = 'mainThreadExceptions' then
      FTeam.MainThreadExceptions := TAtlasTeamFile.MergeNames(ReadNames(Value, Key), nil)
    else if Key = 'startProfiles' then
      ReadStartProfiles(Value)
    else if Key = 'ci' then
      ReadCi(Value)
    else if Key = 'tracker' then
      ReadTracker(Value)
    else
    begin
      Report(TAtlasTeamIssueKind.UnknownKey, Key);
      ScanCredentials(Value, Key);
    end;
  end;
  if not HasVersion then
    Report(TAtlasTeamIssueKind.Version, 'version');
end;

{ TAtlasTeamFile }

class function TAtlasTeamFile.Empty: TAtlasTeamSettings;
begin
  Result := Default(TAtlasTeamSettings);
  Result.Version := CurrentVersion;
end;

class function TAtlasTeamFile.RootOf(const AFolder: string; const AExists: TAtlasTeamFileExists): string;
var
  Folder: string;
begin
  Folder := WithoutTrailing(AFolder);
  while Folder <> '' do
  begin
    if AExists(JoinPath(Folder, '.git')) then
      Exit(Folder);
    Folder := ParentOf(Folder);
  end;
  Result := WithoutTrailing(AFolder);
end;

class function TAtlasTeamFile.Locate(const AProjectFolder: string; const AExists: TAtlasTeamFileExists): string;
var
  Root: string;
begin
  Result := '';
  if AProjectFolder = '' then
    Exit;
  if AExists(JoinPath(AProjectFolder, FileName)) then
    Exit(JoinPath(AProjectFolder, FileName));
  Root := RootOf(AProjectFolder, AExists);
  if not SameText(Root, WithoutTrailing(AProjectFolder)) and AExists(JoinPath(Root, FileName)) then
    Result := JoinPath(Root, FileName);
end;

class function TAtlasTeamFile.Parse(const AText, AFileName, ARoot: string): TAtlasTeamSettings;
var
  Reader: TTeamReader;
  Value: TJSONValue;
begin
  Reader := TTeamReader.Create(AFileName, ARoot);
  try
    Value := nil;
    if Trim(AText) <> '' then
      Value := TJSONObject.ParseJSONValue(TJsoncScanner.StripComments(AText));
    try
      if Value is TJSONObject then
        Reader.Read(TJSONObject(Value))
      else
        Reader.Invalid;
    finally
      Value.Free;
    end;
    Result := Reader.Team;
  finally
    Reader.Free;
  end;
end;

class function TAtlasTeamFile.Skeleton: string;
const
  Lines: array[0..29] of string = (
    '{',
    '  // Projekteinstellungen von Atlas für alle im Team (eingecheckt). Persönliche',
    '  // Einstellungen stehen unter Tools > Optionen > Atlas; ein Wert aus dieser',
    '  // Datei hat Vorrang. Keine Zugangsdaten und keine absoluten Pfade: Atlas',
    '  // ignoriert solche Einträge. Pfade relativ zu dieser Datei.',
    '  "version": 1,',
    '  "naming": {',
    '    // "field": "F", "parameter": "A", "local": "L"',
    '  },',
    '  // Ordner mit Code-Vorlagen des Projekts (*.atlas-snippet wie unter %APPDATA%\Atlas\Snippets):',
    '  // "snippets": "Vorlagen\\Snippets",',
    '  "formatFunctions": [',
    '    // {"name": "Log", "formatIndex": 0}',
    '  ],',
    '  "sqlTargets": [',
    '    // "TMyQuery.SQL"',
    '  ],',
    '  "fileMethods": [',
    '    // "TDateien.Laden"',
    '  ],',
    '  "mainThreadExceptions": [',
    '    // "TLogger.Write"',
    '  ],',
    '  "startProfiles": [',
    '    // {"name": "Demo", "parameters": "-demo", "workingDir": "Bin", "environment": {"MODUS": "demo"}}',
    '  ],',
    '  // Build-Server und Issue-Tracker; Benutzer und Token im Anmeldespeicher von Windows:',
    '  // "ci": {"provider": "jenkins", "url": "https://ci.example.com", "job": "projekt", "multibranch": false},',
    '  // "tracker": {"provider": "youtrack", "url": "https://example.youtrack.cloud", "project": "ATL"},',
    '}');
var
  Line: string;
begin
  Result := '';
  for Line in Lines do
    Result := Result + Line + #13#10;
end;

class function TAtlasTeamFile.Prefix(const ATeam: TAtlasTeamSettings; AKind: TAtlasNamingKind;
  const APersonal: string): string;
begin
  Result := APersonal;
  if ATeam.Valid and ATeam.HasNaming[AKind] then
    Result := ATeam.Naming[AKind];
end;

class function TAtlasTeamFile.MergeNames(const ATeam, APersonal: TArray<string>): TArray<string>;
var
  Item, Known: string;
  Found: Boolean;
begin
  Result := nil;
  for Item in ATeam + APersonal do
  begin
    Found := False;
    for Known in Result do
      if SameText(Known, Item) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Result := Result + [Item];
  end;
end;

class function TAtlasTeamFile.MergeFormatFunctions(const ATeam,
  APersonal: TArray<TAtlasFormatFunction>): TArray<TAtlasFormatFunction>;
var
  Item, Known: TAtlasFormatFunction;
  Found: Boolean;
begin
  Result := nil;
  for Item in ATeam + APersonal do
  begin
    Found := False;
    for Known in Result do
      if SameText(Known.Name, Item.Name) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Result := Result + [Item];
  end;
end;

class function TAtlasTeamFile.MergeStartProfiles(const ATeam,
  APersonal: TArray<TAtlasStartProfile>): TArray<TAtlasStartProfile>;
var
  Item, Known: TAtlasStartProfile;
  Found: Boolean;
begin
  Result := nil;
  for Item in ATeam + APersonal do
  begin
    Found := False;
    for Known in Result do
      if SameText(Known.Name, Item.Name) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Result := Result + [Item];
  end;
end;

class function TAtlasTeamFile.Values(const ATeam: TAtlasTeamSettings): TArray<TAtlasTeamValue>;

  procedure Add(const AKey, AValue: string);
  var
    Value: TAtlasTeamValue;
  begin
    Value.Key := AKey;
    Value.Value := AValue;
    Result := Result + [Value];
  end;

var
  Kind: TAtlasNamingKind;
  Item: TAtlasFormatFunction;
  Profile: TAtlasStartProfile;
  Text: string;
begin
  Result := nil;
  if not ATeam.Valid then
    Exit;
  for Kind := Low(TAtlasNamingKind) to High(TAtlasNamingKind) do
    if ATeam.HasNaming[Kind] then
      Add('naming.' + NamingKeys[Kind], '"' + ATeam.Naming[Kind] + '"');
  if ATeam.Snippets <> '' then
    Add('snippets', ATeam.Snippets);
  if Length(ATeam.FormatFunctions) > 0 then
  begin
    Text := '';
    for Item in ATeam.FormatFunctions do
    begin
      if Text <> '' then
        Text := Text + ', ';
      Text := Text + Format('%s (%d)', [Item.Name, Item.FormatIndex]);
    end;
    Add('formatFunctions', Text);
  end;
  if Length(ATeam.SqlTargets) > 0 then
    Add('sqlTargets', string.Join(', ', ATeam.SqlTargets));
  if Length(ATeam.FileMethods) > 0 then
    Add('fileMethods', string.Join(', ', ATeam.FileMethods));
  if Length(ATeam.MainThreadExceptions) > 0 then
    Add('mainThreadExceptions', string.Join(', ', ATeam.MainThreadExceptions));
  if Length(ATeam.StartProfiles) > 0 then
  begin
    Text := '';
    for Profile in ATeam.StartProfiles do
    begin
      if Text <> '' then
        Text := Text + ', ';
      Text := Text + Profile.Name;
    end;
    Add('startProfiles', Text);
  end;
  if ATeam.Ci.Configured then
    Add('ci', Format('%s, %s, %s', [ATeam.Ci.Provider, ATeam.Ci.Url, ATeam.Ci.Job]));
  if ATeam.Tracker.Configured then
  begin
    Text := ATeam.Tracker.Provider + ', ' + ATeam.Tracker.Url;
    if ATeam.Tracker.Project <> '' then
      Text := Text + ', ' + ATeam.Tracker.Project;
    Add('tracker', Text);
  end;
end;

class function TAtlasTeamFile.NamingKey(AKind: TAtlasNamingKind): string;
begin
  Result := NamingKeys[AKind];
end;

class function TAtlasTeamFile.Combine(const AFolder, ARelative: string): string;
var
  Lead, Path, Part: string;
  Parts: TArray<string>;
  Start, Index: Integer;
begin
  Lead := '';
  Path := AFolder + '\' + ARelative;
  if (Length(AFolder) >= 2) and IsSeparator(AFolder[1]) and IsSeparator(AFolder[2]) then
    Lead := '\\'
  else if (AFolder <> '') and IsSeparator(AFolder[1]) then
    Lead := '\';
  Parts := nil;
  Start := 1;
  for Index := 1 to Length(Path) + 1 do
    if (Index > Length(Path)) or IsSeparator(Path[Index]) then
    begin
      Part := Copy(Path, Start, Index - Start);
      Start := Index + 1;
      if (Part = '') or (Part = '.') then
        Continue;
      if Part = '..' then
      begin
        if Length(Parts) > 1 then
          SetLength(Parts, Length(Parts) - 1);
        Continue;
      end;
      Parts := Parts + [Part];
    end;
  Result := Lead + string.Join('\', Parts);
end;

end.
