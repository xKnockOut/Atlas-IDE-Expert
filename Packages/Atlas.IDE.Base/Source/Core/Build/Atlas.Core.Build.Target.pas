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
  mDefine, mOther: string;
  mFound: Boolean;
begin
  Result := SameText(Project, AOther.Project) and SameText(Config, AOther.Config) and
    SameText(Platform, AOther.Platform) and (Length(Defines) = Length(AOther.Defines));
  if not Result then
  begin
    Exit;
  end;
  for mDefine in Defines do
  begin
    mFound := False;
    for mOther in AOther.Defines do
    begin
      mFound := mFound or SameText(mDefine, mOther);
    end;
    if not mFound then
    begin
      Exit(False);
    end;
  end;
end;

class function TAtlasBuildTarget.ParseDefines(const AValue: string): TArray<string>;
var
  mPart, mName, mKnown: string;
  mDuplicate: Boolean;
begin
  Result := nil;
  for mPart in AValue.Split([';']) do
  begin
    mName := UpperCase(Trim(mPart));
    // $(DCC_Define) verweist auf geerbte Werte; die liefert die IDE schon mit.
    if (mName = '') or mName.StartsWith('$(') then
    begin
      Continue;
    end;
    mDuplicate := False;
    for mKnown in Result do
    begin
      mDuplicate := mDuplicate or (mKnown = mName);
    end;
    if not mDuplicate then
    begin
      Result := Result + [mName];
    end;
  end;
end;

function TAtlasBuildTarget.SelectArguments(const AUri: string; AAction: TAtlasBuildTargetAction): TJSONArray;
var
  mOptions: TJSONObject;
  mItems: TJSONArray;
  mDefine: string;
begin
  mOptions := TJSONObject.Create;
  mOptions.AddPair('uri', AUri);
  if AAction = TAtlasBuildTargetAction.Select then
  begin
    mOptions.AddPair('config', Config);
    mOptions.AddPair('platform', Platform);
    mItems := TJSONArray.Create;
    for mDefine in Defines do
    begin
      mItems.Add(mDefine);
    end;
    mOptions.AddPair('defines', mItems);
  end;
  Result := TJSONArray.Create;
  Result.AddElement(mOptions);
end;

class function TAtlasBuildTarget.FromSelection(const AResult: TJSONValue; const AProject: string;
  out AConfig, APlatform: string): Boolean;
var
  mProjects, mItem: TJSONValue;
begin
  AConfig := '';
  APlatform := '';
  Result := False;
  if not (AResult is TJSONObject) then
  begin
    Exit;
  end;
  mProjects := TJSONObject(AResult).GetValue('projects');
  if not (mProjects is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mProjects) do
  begin
    if (mItem is TJSONObject) and SameText(TJSONObject(mItem).GetValue<string>('project', ''), AProject) then
    begin
      AConfig := TJSONObject(mItem).GetValue<string>('config', '');
      APlatform := TJSONObject(mItem).GetValue<string>('platform', '');
      Exit(True);
    end;
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
  mKnown: TAtlasBuildTarget;
begin
  Result := TAtlasBuildTargetAction.None;
  if FPending or (ACurrent.Project = '') then
  begin
    Exit;
  end;
  if not FKnown.TryGetValue(Key(ACurrent.Project), mKnown) then
  begin
    FPending := True;
    Exit(TAtlasBuildTargetAction.Query);
  end;
  // Projekt, das der Server nicht kennt: nichts senden.
  if mKnown.Project = '' then
  begin
    Exit;
  end;
  if ACurrent.SameAs(mKnown) then
  begin
    Exit;
  end;
  FKnown.AddOrSetValue(Key(ACurrent.Project), ACurrent);
  FPending := True;
  Result := TAtlasBuildTargetAction.Select;
end;

procedure TAtlasBuildTargetTracker.Baseline(const AProject, AConfig, APlatform: string;
  const ADefines: TArray<string>; AFound: Boolean);
begin
  if AFound then
  begin
    FKnown.AddOrSetValue(Key(AProject), TAtlasBuildTarget.Create(AProject, AConfig, APlatform, ADefines));
  end
  else
  begin
    FKnown.AddOrSetValue(Key(AProject), Default(TAtlasBuildTarget));
  end;
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
