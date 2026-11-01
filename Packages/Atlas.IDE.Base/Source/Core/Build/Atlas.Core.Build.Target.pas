unit Atlas.Core.Build.Target;

// Gewählte Build-Konfiguration, Zielplattform und bedingte Symbole des aktiven
// Projekts (#615), ohne Open Tools API. Der Server blendet {$IFDEF}-Zweige nach
// seiner Auswahl ab; wechselt der Benutzer in der Projektverwaltung
// Konfiguration oder Plattform oder ändert er die Defines in den
// Projektoptionen, muss der Server davon erfahren (atlas.server.selectBuild).
//
// Der Tracker entscheidet je Projekt, was zu tun ist:
// - Query: Für das Projekt ist noch nichts bekannt. Der Server nennt seine
//   Auswahl; Baseline übernimmt sie (die Defines gelten als gleich, der Server
//   liest dieselbe .dproj).
// - Select: Die IDE weicht vom zuletzt bekannten Stand ab; Konfiguration,
//   Plattform und Defines gehen an den Server.
// Solange eine Anfrage läuft, entscheidet er nichts Neues (Finished).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  {$SCOPEDENUMS ON}
  TAtlasBuildTargetAction = (None, Query, Select);
  {$SCOPEDENUMS OFF}

  TAtlasBuildTarget = record
    /// <summary>Absoluter Pfad der .dproj.</summary>
    Project: string;
    Config: string;
    Platform: string;
    /// <summary>Bedingte Symbole (DCC_Define) in Großschreibung, ohne Doppelte.</summary>
    Defines: TArray<string>;
    class function Create(const AProject, AConfig, APlatform: string;
      const ADefines: TArray<string>): TAtlasBuildTarget; static;
    /// <summary>Gleiches Projekt, gleiche Konfiguration und Plattform (ohne Groß/klein) und dieselben Symbole
    /// in beliebiger Reihenfolge.</summary>
    function SameAs(const AOther: TAtlasBuildTarget): Boolean;
    /// <summary>DCC_Define der IDE ("DEBUG;$(DCC_Define);Foo") als Symbole: getrennt an ";", ohne Leere
    /// und Makros, groß geschrieben, ohne Doppelte.</summary>
    class function ParseDefines(const AValue: string): TArray<string>; static;
    /// <summary>Argumente für atlas.server.selectBuild: [{uri}] für Query, [{uri, config, platform, defines}]
    /// für Select. AUri ist die URI der .dproj. Der Aufrufer übernimmt das Array.</summary>
    function SelectArguments(const AUri: string; AAction: TAtlasBuildTargetAction): TJSONArray;
    /// <summary>Auswahl des Servers zu AProject aus der Antwort {"projects": [{project, config, platform}]};
    /// False, wenn der Server das Projekt nicht nennt.</summary>
    class function FromSelection(const AResult: TJSONValue; const AProject: string;
      out AConfig, APlatform: string): Boolean; static;
  end;

  TAtlasBuildTargetTracker = class
  private
    // Zuletzt bekannter Stand des Servers je Projekt (Schlüssel klein).
    FKnown: TDictionary<string, TAtlasBuildTarget>;
    FPending: Boolean;
    class function Key(const AProject: string): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Was für den Stand ACurrent der IDE zu tun ist. Bei Select gilt ACurrent danach als bekannt.</summary>
    function Decide(const ACurrent: TAtlasBuildTarget): TAtlasBuildTargetAction;
    /// <summary>Antwort auf Query: Auswahl des Servers für AProject; ohne Projekt beim Server (AFound = False)
    /// nichts mehr senden. ADefines sind die Symbole der IDE zur Zeit der Anfrage.</summary>
    procedure Baseline(const AProject, AConfig, APlatform: string; const ADefines: TArray<string>;
      AFound: Boolean);
    /// <summary>Anfrage beendet (erfolgreich oder nicht).</summary>
    procedure Finished;
    /// <summary>Neue Sitzung: Der Server beginnt mit der Auswahl der Datei.</summary>
    procedure Reset;
    property Pending: Boolean read FPending;
  end;

implementation

{ TAtlasBuildTarget }

class function TAtlasBuildTarget.Create(const AProject, AConfig, APlatform: string;
  const ADefines: TArray<string>): TAtlasBuildTarget;
begin
  Result.Project := AProject;
  Result.Config := AConfig;
  Result.Platform := APlatform;
  Result.Defines := ADefines;
end;

function TAtlasBuildTarget.SameAs(const AOther: TAtlasBuildTarget): Boolean;
var
  Define, Other: string;
  Found: Boolean;
begin
  Result := SameText(Project, AOther.Project) and SameText(Config, AOther.Config) and
    SameText(Platform, AOther.Platform) and (Length(Defines) = Length(AOther.Defines));
  if not Result then
    Exit;
  for Define in Defines do
  begin
    Found := False;
    for Other in AOther.Defines do
      Found := Found or SameText(Define, Other);
    if not Found then
      Exit(False);
  end;
end;

class function TAtlasBuildTarget.ParseDefines(const AValue: string): TArray<string>;
var
  Part, Name, Known: string;
  Duplicate: Boolean;
begin
  Result := nil;
  for Part in AValue.Split([';']) do
  begin
    Name := UpperCase(Trim(Part));
    // $(DCC_Define) verweist auf geerbte Werte; die liefert die IDE schon mit.
    if (Name = '') or Name.StartsWith('$(') then
      Continue;
    Duplicate := False;
    for Known in Result do
      Duplicate := Duplicate or (Known = Name);
    if not Duplicate then
      Result := Result + [Name];
  end;
end;

function TAtlasBuildTarget.SelectArguments(const AUri: string; AAction: TAtlasBuildTargetAction): TJSONArray;
var
  Options: TJSONObject;
  Items: TJSONArray;
  Define: string;
begin
  Options := TJSONObject.Create;
  Options.AddPair('uri', AUri);
  if AAction = TAtlasBuildTargetAction.Select then
  begin
    Options.AddPair('config', Config);
    Options.AddPair('platform', Platform);
    Items := TJSONArray.Create;
    for Define in Defines do
      Items.Add(Define);
    Options.AddPair('defines', Items);
  end;
  Result := TJSONArray.Create;
  Result.AddElement(Options);
end;

class function TAtlasBuildTarget.FromSelection(const AResult: TJSONValue; const AProject: string;
  out AConfig, APlatform: string): Boolean;
var
  Projects, Item: TJSONValue;
begin
  AConfig := '';
  APlatform := '';
  Result := False;
  if not (AResult is TJSONObject) then
    Exit;
  Projects := TJSONObject(AResult).GetValue('projects');
  if not (Projects is TJSONArray) then
    Exit;
  for Item in TJSONArray(Projects) do
    if (Item is TJSONObject) and SameText(TJSONObject(Item).GetValue<string>('project', ''), AProject) then
    begin
      AConfig := TJSONObject(Item).GetValue<string>('config', '');
      APlatform := TJSONObject(Item).GetValue<string>('platform', '');
      Exit(True);
    end;
end;

{ TAtlasBuildTargetTracker }

constructor TAtlasBuildTargetTracker.Create;
begin
  inherited Create;
  FKnown := TDictionary<string, TAtlasBuildTarget>.Create;
end;

destructor TAtlasBuildTargetTracker.Destroy;
begin
  FKnown.Free;
  inherited Destroy;
end;

class function TAtlasBuildTargetTracker.Key(const AProject: string): string;
begin
  Result := AnsiLowerCase(AProject);
end;

function TAtlasBuildTargetTracker.Decide(const ACurrent: TAtlasBuildTarget): TAtlasBuildTargetAction;
var
  Known: TAtlasBuildTarget;
begin
  Result := TAtlasBuildTargetAction.None;
  if FPending or (ACurrent.Project = '') then
    Exit;
  if not FKnown.TryGetValue(Key(ACurrent.Project), Known) then
  begin
    FPending := True;
    Exit(TAtlasBuildTargetAction.Query);
  end;
  // Projekt, das der Server nicht kennt: nichts senden.
  if Known.Project = '' then
    Exit;
  if ACurrent.SameAs(Known) then
    Exit;
  FKnown.AddOrSetValue(Key(ACurrent.Project), ACurrent);
  FPending := True;
  Result := TAtlasBuildTargetAction.Select;
end;

procedure TAtlasBuildTargetTracker.Baseline(const AProject, AConfig, APlatform: string;
  const ADefines: TArray<string>; AFound: Boolean);
begin
  if AFound then
    FKnown.AddOrSetValue(Key(AProject), TAtlasBuildTarget.Create(AProject, AConfig, APlatform, ADefines))
  else
    FKnown.AddOrSetValue(Key(AProject), Default(TAtlasBuildTarget));
end;

procedure TAtlasBuildTargetTracker.Finished;
begin
  FPending := False;
end;

procedure TAtlasBuildTargetTracker.Reset;
begin
  FKnown.Clear;
  FPending := False;
end;

end.
