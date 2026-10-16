unit Atlas.Core.Build.OpenBuild;

// Einmal bauen beim Öffnen (build.onOpen), ohne Open Tools API: Wird in der
// IDE ein Projekt oder eine Projektgruppe geöffnet, merkt Atlas das vor und
// lässt die Projekte einmal compilieren (Make), erzeugen (Build) oder prüfen,
// sobald die IDE ruhig ist.
// - Opened merkt die geöffnete Datei vor; fällig ist der Lauf DelayMs nach
//   dem letzten Öffnen und erst, wenn der Benutzer mindestens DelayMs keine
//   Eingabe gemacht hat. Während eines Builds des Benutzers, im Debugger und
//   während des eigenen Laufs ist nichts fällig; was vorgemerkt ist, bleibt.
// - Take liefert die vorgemerkten Dateien; die IDE-Schicht macht daraus die
//   Projekte (bei einer Gruppe alle oder nur das aktive). Ist eine Datei noch
//   nicht geladen, merkt Retry sie erneut vor, höchstens MaxAttempts-mal.
// - Select lässt Projekte weg, die seit dem Öffnen schon gebaut wurden,
//   doppelte (.dpr und .dproj zählen als ein Projekt) und ausgeschlossene
//   (build.onOpenExclude, Projektname ohne Endung); die übrigen gelten danach
//   als gebaut. Erst Closed (Projekt geschlossen) gibt ein Projekt wieder
//   frei: einmal je Öffnen.
// - RunStarted/ProjectFinished/ProjectCancelled/RunFinished zählen das
//   Ergebnis des eigenen Laufs für die Benachrichtigung.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Build.Events;

type
  /// <summary>Welche Projekte einer Projektgruppe gebaut werden (build.onOpenScope).</summary>
  TAtlasOpenBuildScope = (All, Active);

  /// <summary>Ergebnis eines Laufs beim Öffnen.</summary>
  TAtlasOpenBuildResult = record
    Total: Integer;
    Succeeded: Integer;
    Failed: Integer;
    /// <summary>Ohne Ergebnis: abgebrochen (z. B. Release-Wächter mit build.gate = block) oder nie gestartet.
    /// </summary>
    NotBuilt: Integer;
    /// <summary>Projektnamen ohne Endung, in der Reihenfolge des Laufs.</summary>
    FailedNames: TArray<string>;
    NotBuiltNames: TArray<string>;
    /// <summary>Erster Grund eines Abbruchs; '' ohne.</summary>
    CancelReason: string;
    function AllSucceeded: Boolean;
  end;

  TAtlasOpenBuild = class
  public const
    /// <summary>Auftraggeber in den Compile-Ereignissen (#527): kein Build des Benutzers, also keine Tests nach
    /// dem Build (#69).</summary>
    RequestedBy = 'open';
    MaxAttempts = 10;
    DefaultDelayMs = 3000;
    MinDelayMs = 500;
    MaxDelayMs = 60000;
    /// <summary>Ein Lauf im Hintergrund der IDE gilt nach dieser Zeit ohne Ende als beendet.</summary>
    MaxRunMs = 30 * 60 * 1000;
    KindNames: array[0..2] of string = ('check', 'make', 'build');
    ScopeNames: array[TAtlasOpenBuildScope] of string = ('all', 'active');
  private
    FPending: TList<string>;
    /// <summary>Versuche je vorgemerkter Datei (Schlüssel KeyOf), auch über Take hinweg.</summary>
    FAttempts: TDictionary<string, Integer>;
    FDone: TDictionary<string, Boolean>;
    FLastOpened: Int64;
    FBuildRunning: Boolean;
    FRunning: Boolean;
    FRunProjects: TList<string>;
    FRunResults: TDictionary<string, Boolean>;
    FCancelReason: string;
    FRunStartedAt: Int64;
    function PendingIndex(const AFileName: string): Integer;
    procedure AddPending(const AFileName: string; ANowMs: Int64);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Ein Projekt (.dproj, .dpr, .dpk) oder eine Projektgruppe (.groupproj) wurde geöffnet.</summary>
    procedure Opened(const AFileName: string; ANowMs: Int64);
    /// <summary>Ein Projekt oder eine Gruppe wird geschlossen: Vormerkung weg, beim nächsten Öffnen wieder bauen.
    /// </summary>
    procedure Closed(const AFileName: string);
    /// <summary>Ein Lauf ist fällig. AIdleMs: Zeit seit der letzten Eingabe des Benutzers.</summary>
    function Due(ANowMs: Int64; ADelayMs: Integer; AIdleMs: Int64; ADebugging: Boolean): Boolean;
    /// <summary>Vorgemerkte Dateien in der Reihenfolge des Öffnens; leert die Vormerkung.</summary>
    function Take: TArray<string>;
    /// <summary>AFileName war noch nicht geladen: erneut vormerken (bis MaxAttempts).</summary>
    function Retry(const AFileName: string; ANowMs: Int64): Boolean;
    /// <summary>Zu bauende Projekte aus AProjects (Reihenfolge bleibt); markiert sie als gebaut.</summary>
    function Select(const AProjects, AExclude: TArray<string>): TArray<string>;
    procedure BuildStarted;
    procedure BuildFinished;
    procedure RunStarted(const AProjects: TArray<string>; ANowMs: Int64);
    procedure ProjectFinished(const AFileName: string; ASucceeded: Boolean);
    procedure ProjectCancelled(const AFileName, AReason: string);
    /// <summary>Gehört AFileName zum laufenden eigenen Lauf?</summary>
    function InRun(const AFileName: string): Boolean;
    /// <summary>Alle Projekte des Laufs haben ein Ergebnis.</summary>
    function RunComplete: Boolean;
    /// <summary>Der eigene Lauf dauert länger als MaxRunMs (Ende nie gemeldet).</summary>
    function RunOverdue(ANowMs: Int64): Boolean;
    function RunFinished: TAtlasOpenBuildResult;
    /// <summary>AFileName ohne Endung .dproj, .dpr, .dpk bzw. .groupproj; andere Endungen bleiben.</summary>
    class function StripProjectExt(const AFileName: string): string; static;
    /// <summary>Schlüssel eines Projekts: Pfad ohne Endung, klein.</summary>
    class function KeyOf(const AFileName: string): string; static;
    /// <summary>Projektname ohne Pfad und Endung (beide Trenner, auch unter Linux).</summary>
    class function NameOf(const AFileName: string): string; static;
    class function IsGroupFile(const AFileName: string): Boolean; static;
    class function IsProjectFile(const AFileName: string): Boolean; static;
    /// <summary>check, make oder build; sonst Make.</summary>
    class function KindOf(const AName: string): TAtlasCompileKind; static;
    class function KindName(AKind: TAtlasCompileKind): string; static;
    class function ScopeOf(const AName: string): TAtlasOpenBuildScope; static;
    /// <summary>Namen aus build.onOpenExclude (Komma, Semikolon oder Zeilenumbruch), ohne Endung und Leerraum.
    /// </summary>
    class function ParseExclude(const AText: string): TArray<string>; static;
    class function NormalizedExclude(const AText: string): string; static;
    property Running: Boolean read FRunning;
    property BuildRunning: Boolean read FBuildRunning;
    property LastOpened: Int64 read FLastOpened;
  end;

implementation

{ TAtlasOpenBuildResult }

function TAtlasOpenBuildResult.AllSucceeded: Boolean;
begin
  Result := (Total > 0) and (Succeeded = Total);
end;

{ TAtlasOpenBuild }

constructor TAtlasOpenBuild.Create;
begin
  inherited Create;
  FPending := TList<string>.Create;
  FAttempts := TDictionary<string, Integer>.Create;
  FDone := TDictionary<string, Boolean>.Create;
  FRunProjects := TList<string>.Create;
  FRunResults := TDictionary<string, Boolean>.Create;
end;

destructor TAtlasOpenBuild.Destroy;
begin
  FRunResults.Free;
  FRunProjects.Free;
  FDone.Free;
  FAttempts.Free;
  FPending.Free;
  inherited;
end;

class function TAtlasOpenBuild.StripProjectExt(const AFileName: string): string;
var
  Ext: string;
begin
  // Nur Endungen von Projekten: Namen wie "Atlas.IDE.Expert" behalten ihre Punkte.
  Result := AFileName;
  Ext := LowerCase(ExtractFileExt(Result));
  if (Ext = '.dproj') or (Ext = '.dpr') or (Ext = '.dpk') or (Ext = '.groupproj') then
    Result := Copy(Result, 1, Length(Result) - Length(Ext));
end;

class function TAtlasOpenBuild.NameOf(const AFileName: string): string;
var
  Index: Integer;
begin
  Result := AFileName;
  for Index := Length(Result) downto 1 do
    if (Result[Index] = '\') or (Result[Index] = '/') then
    begin
      Result := Copy(Result, Index + 1, MaxInt);
      Break;
    end;
  Result := StripProjectExt(Result);
end;

class function TAtlasOpenBuild.KeyOf(const AFileName: string): string;
begin
  Result := StripProjectExt(LowerCase(Trim(AFileName)));
end;

class function TAtlasOpenBuild.IsGroupFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.groupproj');
end;

class function TAtlasOpenBuild.IsProjectFile(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.dproj') or (Ext = '.dpr') or (Ext = '.dpk') or (Ext = '.groupproj');
end;

class function TAtlasOpenBuild.KindOf(const AName: string): TAtlasCompileKind;
var
  Name: string;
begin
  Name := LowerCase(Trim(AName));
  if Name = 'check' then
    Result := TAtlasCompileKind.Check
  else if Name = 'build' then
    Result := TAtlasCompileKind.Build
  else
    Result := TAtlasCompileKind.Make;
end;

class function TAtlasOpenBuild.KindName(AKind: TAtlasCompileKind): string;
begin
  case AKind of
    TAtlasCompileKind.Check:
      Result := KindNames[0];
    TAtlasCompileKind.Build:
      Result := KindNames[2];
  else
    Result := KindNames[1];
  end;
end;

class function TAtlasOpenBuild.ScopeOf(const AName: string): TAtlasOpenBuildScope;
begin
  if SameText(Trim(AName), ScopeNames[TAtlasOpenBuildScope.Active]) then
    Result := TAtlasOpenBuildScope.Active
  else
    Result := TAtlasOpenBuildScope.All;
end;

class function TAtlasOpenBuild.ParseExclude(const AText: string): TArray<string>;
var
  Part, Name: string;
  Known: TDictionary<string, Boolean>;
begin
  Result := nil;
  Known := TDictionary<string, Boolean>.Create;
  try
    for Part in AText.Split([',', ';', #13, #10]) do
    begin
      Name := NameOf(Trim(Part));
      if (Name = '') or Known.ContainsKey(LowerCase(Name)) then
        Continue;
      Known.Add(LowerCase(Name), True);
      Result := Result + [Name];
    end;
  finally
    Known.Free;
  end;
end;

class function TAtlasOpenBuild.NormalizedExclude(const AText: string): string;
begin
  Result := string.Join(', ', ParseExclude(AText));
end;

function TAtlasOpenBuild.PendingIndex(const AFileName: string): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to FPending.Count - 1 do
    if SameText(FPending[Index], AFileName) then
      Exit(Index);
end;

procedure TAtlasOpenBuild.AddPending(const AFileName: string; ANowMs: Int64);
begin
  FLastOpened := ANowMs;
  if PendingIndex(AFileName) < 0 then
    FPending.Add(AFileName);
end;

procedure TAtlasOpenBuild.Opened(const AFileName: string; ANowMs: Int64);
begin
  if (Trim(AFileName) = '') or not IsProjectFile(AFileName) then
    Exit;
  FAttempts.AddOrSetValue(KeyOf(AFileName), 0);
  AddPending(AFileName, ANowMs);
end;

procedure TAtlasOpenBuild.Closed(const AFileName: string);
var
  Index: Integer;
begin
  FDone.Remove(KeyOf(AFileName));
  FAttempts.Remove(KeyOf(AFileName));
  Index := PendingIndex(AFileName);
  if Index >= 0 then
    FPending.Delete(Index);
end;

function TAtlasOpenBuild.Due(ANowMs: Int64; ADelayMs: Integer; AIdleMs: Int64; ADebugging: Boolean): Boolean;
begin
  Result := (FPending.Count > 0) and (ANowMs - FLastOpened >= ADelayMs) and (AIdleMs >= ADelayMs) and
    not FBuildRunning and not FRunning and not ADebugging;
end;

function TAtlasOpenBuild.Take: TArray<string>;
begin
  Result := FPending.ToArray;
  FPending.Clear;
end;

function TAtlasOpenBuild.Retry(const AFileName: string; ANowMs: Int64): Boolean;
var
  Key: string;
  Attempts: Integer;
begin
  Key := KeyOf(AFileName);
  if not FAttempts.TryGetValue(Key, Attempts) then
    Attempts := 0;
  Inc(Attempts);
  Result := Attempts < MaxAttempts;
  if Result then
  begin
    FAttempts.AddOrSetValue(Key, Attempts);
    AddPending(AFileName, ANowMs);
  end
  else
    FAttempts.Remove(Key);
end;

function TAtlasOpenBuild.Select(const AProjects, AExclude: TArray<string>): TArray<string>;
var
  Project, Key, Excluded: string;
  Skip: Boolean;
begin
  // Was Take geliefert hat, ist damit erledigt; Retry merkt Unaufgelöstes vorher neu vor.
  Result := nil;
  for Project in AProjects do
  begin
    Key := KeyOf(Project);
    if (Key = '') or FDone.ContainsKey(Key) then
      Continue;
    Skip := False;
    for Excluded in AExclude do
      if SameText(NameOf(Project), Excluded) then
        Skip := True;
    // Auch ausgeschlossene gelten als erledigt: bis zum Schließen nicht noch einmal prüfen.
    FDone.Add(Key, True);
    if not Skip then
      Result := Result + [Project];
  end;
end;

procedure TAtlasOpenBuild.BuildStarted;
begin
  FBuildRunning := True;
end;

procedure TAtlasOpenBuild.BuildFinished;
begin
  FBuildRunning := False;
end;

procedure TAtlasOpenBuild.RunStarted(const AProjects: TArray<string>; ANowMs: Int64);
var
  Project: string;
begin
  FRunProjects.Clear;
  FRunResults.Clear;
  FCancelReason := '';
  for Project in AProjects do
    FRunProjects.Add(Project);
  FRunStartedAt := ANowMs;
  FRunning := True;
end;

function TAtlasOpenBuild.InRun(const AFileName: string): Boolean;
var
  Project: string;
begin
  Result := False;
  if not FRunning then
    Exit;
  for Project in FRunProjects do
    if KeyOf(Project) = KeyOf(AFileName) then
      Exit(True);
end;

procedure TAtlasOpenBuild.ProjectFinished(const AFileName: string; ASucceeded: Boolean);
begin
  if InRun(AFileName) then
    FRunResults.AddOrSetValue(KeyOf(AFileName), ASucceeded);
end;

procedure TAtlasOpenBuild.ProjectCancelled(const AFileName, AReason: string);
begin
  if not InRun(AFileName) then
    Exit;
  if FCancelReason = '' then
    FCancelReason := AReason;
  // Abgebrochen zählt als „nicht gebaut“: kein Eintrag in FRunResults.
  FRunResults.Remove(KeyOf(AFileName));
end;

function TAtlasOpenBuild.RunComplete: Boolean;
var
  Project: string;
begin
  Result := FRunning;
  for Project in FRunProjects do
    if not FRunResults.ContainsKey(KeyOf(Project)) then
      Exit(False);
end;

function TAtlasOpenBuild.RunOverdue(ANowMs: Int64): Boolean;
begin
  Result := FRunning and (ANowMs - FRunStartedAt > MaxRunMs);
end;

function TAtlasOpenBuild.RunFinished: TAtlasOpenBuildResult;
var
  Project: string;
  Succeeded: Boolean;
begin
  Result := Default(TAtlasOpenBuildResult);
  Result.CancelReason := FCancelReason;
  for Project in FRunProjects do
  begin
    Inc(Result.Total);
    if not FRunResults.TryGetValue(KeyOf(Project), Succeeded) then
    begin
      Inc(Result.NotBuilt);
      Result.NotBuiltNames := Result.NotBuiltNames + [NameOf(Project)];
    end
    else if Succeeded then
      Inc(Result.Succeeded)
    else
    begin
      Inc(Result.Failed);
      Result.FailedNames := Result.FailedNames + [NameOf(Project)];
    end;
  end;
  FRunning := False;
  FRunProjects.Clear;
  FRunResults.Clear;
  FCancelReason := '';
end;

end.
