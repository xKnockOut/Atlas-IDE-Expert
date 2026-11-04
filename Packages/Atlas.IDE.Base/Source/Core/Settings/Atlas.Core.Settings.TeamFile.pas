unit Atlas.Core.Settings.TeamFile;

// Projektdatei .atlas (#486): Einstellungen des Plugins für alle im Team, im
// Repository eingecheckt. Persönliche Einstellungen (Registry) bleiben davon
// getrennt; die Einstellungen des Servers stehen in atlas.json (#403). Teil
// ohne VCL und Open Tools API: Datei finden, lesen, prüfen und den Vorrang vor
// den persönlichen Einstellungen bestimmen.
// - Ort: der nächste Ordner mit .atlas ab dem Ordner der .dproj aufwärts bis
//   zur Wurzel des Repositorys (nächster Ordner mit .git oder .svn); ohne
//   Repository bis zum Ordner der geöffneten .groupproj, wenn sie darüber
//   liegt, sonst nur der Ordner der .dproj. Danach der Ordner der .groupproj
//   (etwa eine Gruppe außerhalb des Repositorys). Relative Pfade gelten ab
//   dem Ordner der Datei.
// - Format: JSON mit Kommentaren (// und /* */) und Schema-Version:
//     {"version": 1,
//      "naming": {"field": "F", "parameter": "A", "local": "L",         #452
//                 "constant": "c"},                                   #1111
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
//                  "url": "https://firma.youtrack.cloud", "project": "ATL"},
//      "vcs": {"provider": "svn", "mainBranch": "trunk"},              #1286
//      "hidden": [{"setting": "BlockEndLabels", "file": "Source/Kunde.pas", #628
//                  "anchor": "TKunde.Speichern"}],
//      "debugDisplayRules": {                                            #854
//        "FireDAC.Comp.Client.TFDConnection": "{ConnectionName} ({DriverName})",
//        "TKunde": {"template": "{Name}, {Ort}", "children": ["Name", "Ort"]}}}
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
  System.SysUtils,
  Atlas.Core.Settings.HiddenPlaces;

type
{$SCOPEDENUMS ON}
  /// <summary>Präfix-Arten der Benennung (#452); Constant nur für die Prüfregel naming-prefix (#1111).</summary>
  TAtlasNamingKind = (Field, Parameter, Local, Constant);

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
    /// <summary>Bei Syntax: Zeile und Spalte (ab 1) der ersten fehlerhaften Stelle; 0, wenn unbekannt.</summary>
    Line: Integer;
    Column: Integer;
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

  /// <summary>Versionsverwaltung des Projekts (#1286): Art und Hauptbranch für alle im Team; Vorrang vor der
  /// persönlichen Zeile in vcs.projects.</summary>
  TAtlasTeamVcs = record
    /// <summary>"auto", "git", "svn" oder "off"; '' = nicht gesetzt.</summary>
    Provider: string;
    /// <summary>Hauptbranch, z. B. "develop" bzw. SVN "trunk"; '' = nicht gesetzt.</summary>
    MainBranch: string;
    function Configured: Boolean;
  end;

  /// <summary>Wertdarstellung beim Debuggen für einen Typ (#854, debug.displayRules.project), etwa für fremde
  /// Klassen wie TFDConnection.</summary>
  TAtlasTeamDisplayRule = record
    /// <summary>Typname mit oder ohne Unit.</summary>
    TypeName: string;
    /// <summary>Vorlage wie in // atlas-debug: ('' = nur children).</summary>
    Template: string;
    Children: TArray<string>;
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
    Vcs: TAtlasTeamVcs;
    /// <summary>An einer Stelle oder in einer Datei ausgeblendete Elemente (#628).</summary>
    Hidden: TArray<TAtlasHiddenPlace>;
    /// <summary>Wertdarstellungen beim Debuggen (#854).</summary>
    DisplayRules: TArray<TAtlasTeamDisplayRule>;
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
    DisplayRulesKey = 'debugDisplayRules';
    CurrentVersion = 1;
  public
    /// <summary>Projektdatei zum Ordner einer .dproj ohne Projektgruppe (siehe Kopf); '' ohne.</summary>
    class function Locate(const AProjectFolder: string; const AExists: TAtlasTeamFileExists): string; overload;
      static;
    /// <summary>Projektdatei zum Ordner einer .dproj und dem Ordner der geöffneten .groupproj ('' ohne Gruppe):
    /// nächster Ordner mit .atlas aufwärts bis zur Wurzel, dann der Ordner der Gruppe (siehe Kopf); '' ohne.
    /// </summary>
    class function Locate(const AProjectFolder, AGroupFolder: string; const AExists: TAtlasTeamFileExists): string;
      overload; static;
    /// <summary>Nächster Ordner mit .git oder .svn ab AFolder aufwärts, sonst AFolder.</summary>
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
    /// <summary>Schlüssel einer Präfix-Art: "field", "parameter", "local", "constant".</summary>
    class function NamingKey(AKind: TAtlasNamingKind): string; static;
    /// <summary>ARelative an AFolder gehängt, „.“ und „..“ aufgelöst, Trenner „\“.</summary>
    class function Combine(const AFolder, ARelative: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Text.Jsonc,
  Atlas.Text.Checkin,
  Atlas.Text.DebugDisplay;

const
  NamingKeys: array[TAtlasNamingKind] of string = ('field', 'parameter', 'local', 'constant');

function IsSeparator(ACh: Char): Boolean;
begin
  Result := (ACh = '\') or (ACh = '/');
end;

function WithoutTrailing(const APath: string): string;
begin
  Result := APath;
  while (Length(Result) > 1) and IsSeparator(Result[Length(Result)]) do
  begin
    Delete(Result, Length(Result), 1);
  end;
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
  begin
    if IsSeparator(Path[Index]) then
    begin
      Result := Copy(Path, 1, Index - 1);
      Break;
    end;
  end;
  if (Result <> '') and IsSeparator(Result[Length(Result)]) then
  begin
    Result := '';
  end;
end;

/// <summary>Nächster Ordner mit .git (Ordner oder Datei bei Worktrees) oder .svn ab AFolder aufwärts; '' ohne.
/// </summary>
function RepositoryRoot(const AFolder: string; const AExists: TAtlasTeamFileExists): string;
var
  Folder: string;
begin
  Folder := WithoutTrailing(AFolder);
  while Folder <> '' do
  begin
    if AExists(JoinPath(Folder, '.git')) or AExists(JoinPath(Folder, '.svn')) then
    begin
      Exit(Folder);
    end;
    Folder := ParentOf(Folder);
  end;
  Result := '';
end;

/// <summary>Ist AFolder derselbe Ordner wie AChild oder liegt AChild darunter?</summary>
function FolderContains(const AFolder, AChild: string): Boolean;
var
  Folder, Child: string;
begin
  Folder := WithoutTrailing(AFolder);
  Child := WithoutTrailing(AChild);
  Result := (Folder <> '') and (SameText(Folder, Child) or
    SameText(Folder + '\', Copy(Child, 1, Length(Folder) + 1)));
end;

function FolderOf(const AFileName: string): string;
var
  Index: Integer;
begin
  for Index := Length(AFileName) downto 1 do
  begin
    if IsSeparator(AFileName[Index]) then
    begin
      Exit(Copy(AFileName, 1, Index - 1));
    end;
  end;
  Result := '';
end;

function IsPrefixText(const AText: string): Boolean;
var
  Ch: Char;
begin
  for Ch in AText do
  begin
    if not CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      Exit(False);
    end;
  end;
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
  Result.Line := 0;
  Result.Column := 0;
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

{ TAtlasTeamVcs }

function TAtlasTeamVcs.Configured: Boolean;
begin
  Result := (Provider <> '') or (MainBranch <> '');
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
  begin
    Result := TAtlasTeamFile.Combine(Folder, Snippets);
  end;
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
  begin
    if SameText(StartProfiles[Index].Name, AName) then
    begin
      Exit(Index);
    end;
  end;
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
    procedure ReadVcs(AValue: TJSONValue);
    procedure ReadHidden(AValue: TJSONValue);
    procedure ReadDisplayRules(AValue: TJSONValue);
    procedure ReadVersion(AValue: TJSONValue);
  public
    constructor Create(const AFileName, ARoot: string);
    procedure Read(ARoot: TJSONObject);
    /// <summary>Datei ungültig; ALine/AColumn = erste fehlerhafte Stelle (0 = unbekannt).</summary>
    procedure Invalid(ALine, AColumn: Integer);
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
  begin
    FTeam.Root := FTeam.Folder;
  end;
end;

procedure TTeamReader.Report(AKind: TAtlasTeamIssueKind; const APath: string);
begin
  FTeam.Issues := FTeam.Issues + [TAtlasTeamIssue.Create(AKind, APath)];
end;

procedure TTeamReader.Invalid(ALine, AColumn: Integer);
var
  Issue: TAtlasTeamIssue;
begin
  FTeam.Valid := False;
  Issue := TAtlasTeamIssue.Create(TAtlasTeamIssueKind.Syntax, '');
  Issue.Line := ALine;
  Issue.Column := AColumn;
  FTeam.Issues := FTeam.Issues + [Issue];
end;

function TTeamReader.IsCredential(const AKey, APath: string): Boolean;
begin
  Result := TTextCheckin.IsCredentialKey(AKey);
  if Result then
  begin
    Report(TAtlasTeamIssueKind.Credential, APath);
  end;
end;

procedure TTeamReader.ScanCredentials(AValue: TJSONValue; const APath: string);
var
  Index: Integer;
  Key: string;
begin
  if AValue is TJSONObject then
  begin
    for Index := 0 to TJSONObject(AValue).Count - 1 do
    begin
      Key := TJSONObject(AValue).Pairs[Index].JsonString.Value;
      if not IsCredential(Key, APath + '.' + Key) then
      begin
        ScanCredentials(TJSONObject(AValue).Pairs[Index].JsonValue, APath + '.' + Key);
      end;
    end;
  end
  else if AValue is TJSONArray then
  begin
    for Index := 0 to TJSONArray(AValue).Count - 1 do
    begin
      ScanCredentials(TJSONArray(AValue).Items[Index], APath);
    end;
  end
  else if (AValue is TJSONString) and TTextCheckin.HasUrlCredentials(TJSONString(AValue).Value) then
  begin
    Report(TAtlasTeamIssueKind.Credential, APath);
  end;
end;

function TTeamReader.ReadString(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
begin
  AText := '';
  // TJSONNumber erbt von TJSONString: Zahlen sind hier falsche Typen.
  Result := (AValue is TJSONString) and not (AValue is TJSONNumber);
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
  begin
    Exit;
  end;
  if TTextCheckin.IsAbsolutePath(AText) then
  begin
    Report(TAtlasTeamIssueKind.AbsolutePath, APath);
  end
  else if not TTextCheckin.StaysInside(FTeam.Root, FTeam.Folder, AText) then
  begin
    Report(TAtlasTeamIssueKind.OutsidePath, APath);
  end
  else
  begin
    Exit(True);
  end;
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
    begin
      Continue;
    end;
    if Text = '' then
    begin
      Report(TAtlasTeamIssueKind.InvalidValue, Item);
    end
    else
    begin
      Result := Result + [Text];
    end;
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
    begin
      Continue;
    end;
    Known := False;
    for Kind := Low(TAtlasNamingKind) to High(TAtlasNamingKind) do
    begin
      if Key = NamingKeys[Kind] then
      begin
        Known := True;
        if not ReadString(TJSONObject(AValue).Pairs[Index].JsonValue, Path, Text) then
        begin
          Break;
        end;
        if not IsPrefixText(Text) then
        begin
          Report(TAtlasTeamIssueKind.InvalidValue, Path);
          Break;
        end;
        FTeam.Naming[Kind] := Text;
        FTeam.HasNaming[Kind] := True;
      end;
    end;
    if not Known then
    begin
      Report(TAtlasTeamIssueKind.UnknownKey, Path);
    end;
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
      begin
        Continue;
      end;
      if Key = 'name' then
      begin
        Ok := ReadString(Value, Item + '.name', Name) and Ok;
      end
      else if Key = 'formatIndex' then
      begin
        if Value is TJSONNumber then
        begin
          FormatIndex := TJSONNumber(Value).AsInt;
        end
        else
        begin
          Report(TAtlasTeamIssueKind.WrongType, Item + '.formatIndex');
          Ok := False;
        end;
      end
      else
      begin
        Report(TAtlasTeamIssueKind.UnknownKey, Item + '.' + Key);
      end;
    end;
    if not Ok then
    begin
      Continue;
    end;
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
  begin
    Path := Format('startProfiles[%s]', [Trim(TJSONString(Value).Value)]);
  end;
  Result := True;
  for Index := 0 to Entry.Count - 1 do
  begin
    Key := Entry.Pairs[Index].JsonString.Value;
    Value := Entry.Pairs[Index].JsonValue;
    if IsCredential(Key, Path + '.' + Key) then
    begin
      Result := False;
    end
    else if Key = 'name' then
    begin
      Result := ReadString(Value, Path + '.name', AProfile.Name) and Result;
    end
    else if Key = 'parameters' then
    begin
      if not ReadString(Value, Path + '.parameters', AProfile.Parameters) then
      begin
        Result := False;
      end
      else if TTextCheckin.ContainsMachinePath(AProfile.Parameters) then
      begin
        Report(TAtlasTeamIssueKind.AbsolutePath, Path + '.parameters');
        Result := False;
      end;
    end
    else if Key = 'workingDir' then
    begin
      Result := ReadPath(Value, Path + '.workingDir', AProfile.WorkingDir) and Result;
    end
    else if Key = 'host' then
    begin
      Result := ReadPath(Value, Path + '.host', AProfile.Host) and Result;
    end
    else if Key = 'environment' then
    begin
      Result := ReadEnvironment(Value, Path + '.environment', AProfile.Environment) and Result;
    end
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
    begin
      Continue;
    end;
    if FTeam.IndexOfProfile(Profile.Name) >= 0 then
    begin
      Report(TAtlasTeamIssueKind.InvalidValue, Format('startProfiles[%s]', [Profile.Name]));
    end
    else
    begin
      FTeam.StartProfiles := FTeam.StartProfiles + [Profile];
    end;
  end;
end;

procedure TTeamReader.ReadHidden(AValue: TJSONValue);
var
  Index, Member: Integer;
  Item: TJSONValue;
  Key, Path, Setting, FileName, Anchor: string;
  Usable: Boolean;
begin
  if not (AValue is TJSONArray) then
  begin
    Report(TAtlasTeamIssueKind.WrongType, TAtlasHiddenPlaces.Key);
    Exit;
  end;
  for Index := 0 to TJSONArray(AValue).Count - 1 do
  begin
    Item := TJSONArray(AValue).Items[Index];
    Path := Format('%s[%d]', [TAtlasHiddenPlaces.Key, Index]);
    if not (Item is TJSONObject) then
    begin
      Report(TAtlasTeamIssueKind.WrongType, Path);
      Continue;
    end;
    Setting := '';
    FileName := '';
    Anchor := '';
    Usable := True;
    for Member := 0 to TJSONObject(Item).Count - 1 do
    begin
      Key := TJSONObject(Item).Pairs[Member].JsonString.Value;
      if Key = 'setting' then
      begin
        Usable := ReadString(TJSONObject(Item).Pairs[Member].JsonValue, Path + '.setting', Setting) and Usable;
      end
      else if Key = 'file' then
      begin
        Usable := ReadPath(TJSONObject(Item).Pairs[Member].JsonValue, Path + '.file', FileName) and Usable;
      end
      else if Key = 'anchor' then
      begin
        Usable := ReadString(TJSONObject(Item).Pairs[Member].JsonValue, Path + '.anchor', Anchor) and Usable;
      end
      else
      begin
        Report(TAtlasTeamIssueKind.UnknownKey, Path + '.' + Key);
      end;
    end;
    if not Usable then
    begin
      Continue;
    end;
    if (Setting = '') or (FileName = '') then
    begin
      Report(TAtlasTeamIssueKind.InvalidValue, Path);
      Continue;
    end;
    FTeam.Hidden := FTeam.Hidden + [TAtlasHiddenPlace.Create(Setting, FileName, Anchor)];
  end;
end;

procedure TTeamReader.ReadDisplayRules(AValue: TJSONValue);
var
  Index, Member: Integer;
  Key, Path, Text: string;
  Value, Field: TJSONValue;
  Rule: TAtlasTeamDisplayRule;
  Usable: Boolean;
begin
  if not (AValue is TJSONObject) then
  begin
    Report(TAtlasTeamIssueKind.WrongType, TAtlasTeamFile.DisplayRulesKey);
    Exit;
  end;
  for Index := 0 to TJSONObject(AValue).Count - 1 do
  begin
    Rule := Default(TAtlasTeamDisplayRule);
    Rule.TypeName := Trim(TJSONObject(AValue).Pairs[Index].JsonString.Value);
    Value := TJSONObject(AValue).Pairs[Index].JsonValue;
    Path := TAtlasTeamFile.DisplayRulesKey + '.' + Rule.TypeName;
    Usable := Rule.TypeName <> '';
    if Value is TJSONObject then
    begin
      for Member := 0 to TJSONObject(Value).Count - 1 do
      begin
        Key := TJSONObject(Value).Pairs[Member].JsonString.Value;
        Field := TJSONObject(Value).Pairs[Member].JsonValue;
        if Key = 'template' then
        begin
          Usable := ReadString(Field, Path + '.template', Rule.Template) and Usable;
        end
        else if Key = 'children' then
        begin
          // Liste oder kommagetrennt wie in // atlas-debug-children:
          if (Field is TJSONString) and not (Field is TJSONNumber) then
          begin
            Rule.Children := TDebugDisplayText.SplitNames(Field.Value);
          end
          else
          begin
            Rule.Children := TDebugDisplayText.SplitNames(string.Join(',', ReadNames(Field, Path + '.children')));
          end;
        end
        else
        begin
          Report(TAtlasTeamIssueKind.UnknownKey, Path + '.' + Key);
        end;
      end;
    end
    else if not ReadString(Value, Path, Rule.Template) then
    begin
      Continue;
    end;
    Text := Rule.Template;
    if not Usable or ((Text = '') and (Rule.Children = nil)) or
      ((Text <> '') and not TDebugDisplayTemplate.Parse(Text).Valid) then
    begin
      Report(TAtlasTeamIssueKind.InvalidValue, Path);
      Continue;
    end;
    FTeam.DisplayRules := FTeam.DisplayRules + [Rule];
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
    begin
      Continue;
    end;
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
      begin
        Exit;
      end;
    end
    else if Key = 'url' then
    begin
      ReadUrl(Value, Path, Ci.Url);
    end
    else if Key = 'job' then
    begin
      ReadString(Value, Path, Ci.Job);
    end
    else if Key = 'multibranch' then
    begin
      if Value is TJSONBool then
      begin
        Ci.Multibranch := TJSONBool(Value).AsBoolean;
      end
      else
      begin
        Report(TAtlasTeamIssueKind.WrongType, Path);
      end;
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
    begin
      Continue;
    end;
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
      begin
        Exit;
      end;
    end
    else if Key = 'url' then
    begin
      ReadUrl(Value, Path, Tracker.Url);
    end
    else if Key = 'project' then
    begin
      ReadString(Value, Path, Tracker.Project);
    end
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

procedure TTeamReader.ReadVcs(AValue: TJSONValue);
var
  mIndex: Integer;
  mKey, mPath, mText: string;
  mValue: TJSONValue;
  mVcs: TAtlasTeamVcs;
begin
  if not (AValue is TJSONObject) then
  begin
    Report(TAtlasTeamIssueKind.WrongType, 'vcs');
    Exit;
  end;
  mVcs := Default(TAtlasTeamVcs);
  for mIndex := 0 to TJSONObject(AValue).Count - 1 do
  begin
    mKey := TJSONObject(AValue).Pairs[mIndex].JsonString.Value;
    mValue := TJSONObject(AValue).Pairs[mIndex].JsonValue;
    mPath := 'vcs.' + mKey;
    if IsCredential(mKey, mPath) then
    begin
      Continue;
    end;
    if mKey = 'provider' then
    begin
      if ReadString(mValue, mPath, mText) then
      begin
        mText := LowerCase(Trim(mText));
        if (mText = 'auto') or (mText = 'git') or (mText = 'svn') or (mText = 'off') then
        begin
          mVcs.Provider := mText;
        end
        else
        begin
          Report(TAtlasTeamIssueKind.InvalidValue, mPath);
        end;
      end;
    end
    else if mKey = 'mainBranch' then
    begin
      // Leerzeichen und Steuerzeichen gibt es in keinem Branch-Namen; ein solcher Wert gilt nicht.
      if ReadString(mValue, mPath, mText) then
      begin
        if (Trim(mText) = '') or (Trim(mText).IndexOfAny([' ', #9, #10, #13]) >= 0) then
        begin
          Report(TAtlasTeamIssueKind.InvalidValue, mPath);
        end
        else
        begin
          mVcs.MainBranch := Trim(mText);
        end;
      end;
    end
    else
    begin
      Report(TAtlasTeamIssueKind.UnknownKey, mPath);
      ScanCredentials(mValue, mPath);
    end;
  end;
  FTeam.Vcs := mVcs;
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
  begin
    Report(TAtlasTeamIssueKind.Version, 'version');
  end;
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
    begin
      Continue;
    end;
    if Key = 'version' then
    begin
      HasVersion := True;
      ReadVersion(Value);
    end
    else if Key = 'naming' then
    begin
      ReadNaming(Value);
    end
    else if Key = 'snippets' then
    begin
      ReadPath(Value, Key, FTeam.Snippets);
    end
    else if Key = 'formatFunctions' then
    begin
      ReadFormatFunctions(Value);
    end
    else if Key = 'sqlTargets' then
    begin
      FTeam.SqlTargets := TAtlasTeamFile.MergeNames(ReadNames(Value, Key), nil);
    end
    else if Key = 'fileMethods' then
    begin
      FTeam.FileMethods := TAtlasTeamFile.MergeNames(ReadNames(Value, Key), nil);
    end
    else if Key = 'mainThreadExceptions' then
    begin
      FTeam.MainThreadExceptions := TAtlasTeamFile.MergeNames(ReadNames(Value, Key), nil);
    end
    else if Key = 'startProfiles' then
    begin
      ReadStartProfiles(Value);
    end
    else if Key = 'ci' then
    begin
      ReadCi(Value);
    end
    else if Key = 'tracker' then
    begin
      ReadTracker(Value);
    end
    else if Key = 'vcs' then
    begin
      ReadVcs(Value);
    end
    else if Key = TAtlasHiddenPlaces.Key then
    begin
      ReadHidden(Value);
    end
    else if Key = TAtlasTeamFile.DisplayRulesKey then
    begin
      ReadDisplayRules(Value);
    end
    else
    begin
      Report(TAtlasTeamIssueKind.UnknownKey, Key);
      ScanCredentials(Value, Key);
    end;
  end;
  if not HasVersion then
  begin
    Report(TAtlasTeamIssueKind.Version, 'version');
  end;
end;

{ TAtlasTeamFile }

class function TAtlasTeamFile.Empty: TAtlasTeamSettings;
begin
  Result := Default(TAtlasTeamSettings);
  Result.Version := CurrentVersion;
end;

class function TAtlasTeamFile.RootOf(const AFolder: string; const AExists: TAtlasTeamFileExists): string;
begin
  Result := RepositoryRoot(AFolder, AExists);
  if Result = '' then
  begin
    Result := WithoutTrailing(AFolder);
  end;
end;

class function TAtlasTeamFile.Locate(const AProjectFolder: string; const AExists: TAtlasTeamFileExists): string;
begin
  Result := Locate(AProjectFolder, '', AExists);
end;

class function TAtlasTeamFile.Locate(const AProjectFolder, AGroupFolder: string;
  const AExists: TAtlasTeamFileExists): string;
var
  Folder, Limit, Group: string;
begin
  Result := '';
  Folder := WithoutTrailing(AProjectFolder);
  Group := WithoutTrailing(AGroupFolder);
  if Folder = '' then
  begin
    Exit;
  end;
  // Grenze der Suche aufwärts: Wurzel des Repositorys, ohne Repository die Gruppe darüber, sonst nur der Ordner.
  Limit := RepositoryRoot(Folder, AExists);
  if (Limit = '') and FolderContains(Group, Folder) then
  begin
    Limit := Group;
  end;
  if Limit = '' then
  begin
    Limit := Folder;
  end;
  while Folder <> '' do
  begin
    if AExists(JoinPath(Folder, FileName)) then
    begin
      Exit(JoinPath(Folder, FileName));
    end;
    if SameText(Folder, Limit) then
    begin
      Break;
    end;
    Folder := ParentOf(Folder);
  end;
  // Die Gruppe kann außerhalb des Repositorys liegen (darüber oder daneben).
  if (Group <> '') and AExists(JoinPath(Group, FileName)) then
  begin
    Result := JoinPath(Group, FileName);
  end;
end;

class function TAtlasTeamFile.Parse(const AText, AFileName, ARoot: string): TAtlasTeamSettings;
var
  Reader: TTeamReader;
  Value: TJSONValue;
  Offset, Line, Column: Integer;
begin
  Reader := TTeamReader.Create(AFileName, ARoot);
  try
    Value := nil;
    if Trim(AText) <> '' then
    begin
      Value := TJSONObject.ParseJSONValue(TJsoncScanner.StripComments(AText));
    end;
    try
      if Value is TJSONObject then
      begin
        Reader.Read(TJSONObject(Value));
      end
      else
      begin
        // Wo es hakt, sagt die Meldung mit Zeile und Spalte (sonst sucht man in der Datei nach dem Fehler).
        Line := 0;
        Column := 0;
        Offset := TJsoncScanner.SyntaxError(AText);
        if Offset > 0 then
        begin
          TJsoncScanner.LineColumn(AText, Offset, Line, Column);
        end;
        Reader.Invalid(Line, Column);
      end;
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
  Lines: array[0..33] of string = (
    '{',
    '  // Projekteinstellungen von Atlas für alle im Team (eingecheckt). Persönliche',
    '  // Einstellungen stehen unter Tools > Optionen > Atlas; ein Wert aus dieser',
    '  // Datei hat Vorrang. Keine Zugangsdaten und keine absoluten Pfade: Atlas',
    '  // ignoriert solche Einträge. Pfade relativ zu dieser Datei.',
    '  "version": 1,',
    '  "naming": {',
    '    // "field": "F", "parameter": "A", "local": "L", "constant": "c"',
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
    '  // Im Editor ausgeblendete Elemente („Nur hier“ bzw. „In dieser Datei ausblenden“, #628):',
    '  // "hidden": [{"setting": "BlockEndLabels", "file": "Source/Kunde.pas", "anchor": "TKunde.Speichern"}],',
    '  // Wertdarstellung beim Debuggen für fremde Klassen (eigene: // atlas-debug: über dem Typ, #854):',
    '  // "debugDisplayRules": {"FireDAC.Comp.Client.TFDConnection": "{ConnectionName} ({DriverName})"},',
    '}');
var
  Line: string;
begin
  Result := '';
  for Line in Lines do
  begin
    Result := Result + Line + #13#10;
  end;
end;

class function TAtlasTeamFile.Prefix(const ATeam: TAtlasTeamSettings; AKind: TAtlasNamingKind;
  const APersonal: string): string;
begin
  Result := APersonal;
  if ATeam.Valid and ATeam.HasNaming[AKind] then
  begin
    Result := ATeam.Naming[AKind];
  end;
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
    begin
      if SameText(Known, Item) then
      begin
        Found := True;
        Break;
      end;
    end;
    if not Found then
    begin
      Result := Result + [Item];
    end;
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
    begin
      if SameText(Known.Name, Item.Name) then
      begin
        Found := True;
        Break;
      end;
    end;
    if not Found then
    begin
      Result := Result + [Item];
    end;
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
    begin
      if SameText(Known.Name, Item.Name) then
      begin
        Found := True;
        Break;
      end;
    end;
    if not Found then
    begin
      Result := Result + [Item];
    end;
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
  Place: TAtlasHiddenPlace;
  Rule: TAtlasTeamDisplayRule;
  Text: string;
begin
  Result := nil;
  if not ATeam.Valid then
  begin
    Exit;
  end;
  for Kind := Low(TAtlasNamingKind) to High(TAtlasNamingKind) do
  begin
    if ATeam.HasNaming[Kind] then
    begin
      Add('naming.' + NamingKeys[Kind], '"' + ATeam.Naming[Kind] + '"');
    end;
  end;
  if ATeam.Snippets <> '' then
  begin
    Add('snippets', ATeam.Snippets);
  end;
  if Length(ATeam.FormatFunctions) > 0 then
  begin
    Text := '';
    for Item in ATeam.FormatFunctions do
    begin
      if Text <> '' then
      begin
        Text := Text + ', ';
      end;
      Text := Text + Format('%s (%d)', [Item.Name, Item.FormatIndex]);
    end;
    Add('formatFunctions', Text);
  end;
  if Length(ATeam.SqlTargets) > 0 then
  begin
    Add('sqlTargets', string.Join(', ', ATeam.SqlTargets));
  end;
  if Length(ATeam.FileMethods) > 0 then
  begin
    Add('fileMethods', string.Join(', ', ATeam.FileMethods));
  end;
  if Length(ATeam.MainThreadExceptions) > 0 then
  begin
    Add('mainThreadExceptions', string.Join(', ', ATeam.MainThreadExceptions));
  end;
  if Length(ATeam.StartProfiles) > 0 then
  begin
    Text := '';
    for Profile in ATeam.StartProfiles do
    begin
      if Text <> '' then
      begin
        Text := Text + ', ';
      end;
      Text := Text + Profile.Name;
    end;
    Add('startProfiles', Text);
  end;
  if ATeam.Ci.Configured then
  begin
    Add('ci', Format('%s, %s, %s', [ATeam.Ci.Provider, ATeam.Ci.Url, ATeam.Ci.Job]));
  end;
  if ATeam.Tracker.Configured then
  begin
    Text := ATeam.Tracker.Provider + ', ' + ATeam.Tracker.Url;
    if ATeam.Tracker.Project <> '' then
    begin
      Text := Text + ', ' + ATeam.Tracker.Project;
    end;
    Add('tracker', Text);
  end;
  if ATeam.Vcs.Configured then
  begin
    Text := ATeam.Vcs.Provider;
    if ATeam.Vcs.MainBranch <> '' then
    begin
      if Text <> '' then
      begin
        Text := Text + ', ';
      end;
      Text := Text + ATeam.Vcs.MainBranch;
    end;
    Add('vcs', Text);
  end;
  if Length(ATeam.Hidden) > 0 then
  begin
    Text := '';
    for Place in ATeam.Hidden do
    begin
      if Text <> '' then
      begin
        Text := Text + ', ';
      end;
      Text := Text + Place.Setting + ' ' + Place.FileName;
      if Place.Anchor <> '' then
      begin
        Text := Text + ' (' + Place.Anchor + ')';
      end;
    end;
    Add(TAtlasHiddenPlaces.Key, Text);
  end;
  if Length(ATeam.DisplayRules) > 0 then
  begin
    Text := '';
    for Rule in ATeam.DisplayRules do
    begin
      if Text <> '' then
      begin
        Text := Text + ', ';
      end;
      Text := Text + Rule.TypeName;
    end;
    Add(DisplayRulesKey, Text);
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
  begin
    Lead := '\\';
  end
  else if (AFolder <> '') and IsSeparator(AFolder[1]) then
  begin
    Lead := '\';
  end;
  Parts := nil;
  Start := 1;
  for Index := 1 to Length(Path) + 1 do
  begin
    if (Index > Length(Path)) or IsSeparator(Path[Index]) then
    begin
      Part := Copy(Path, Start, Index - Start);
      Start := Index + 1;
      if (Part = '') or (Part = '.') then
      begin
        Continue;
      end;
      if Part = '..' then
      begin
        if Length(Parts) > 1 then
        begin
          SetLength(Parts, Length(Parts) - 1);
        end;
        Continue;
      end;
      Parts := Parts + [Part];
    end;
  end;
  Result := Lead + string.Join('\', Parts);
end;

end.
