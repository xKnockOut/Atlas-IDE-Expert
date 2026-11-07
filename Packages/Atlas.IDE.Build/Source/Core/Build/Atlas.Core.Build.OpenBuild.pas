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
// - Vorgaben für Konfiguration und Plattform (#1293, build.onOpenConfig,
//   build.onOpenPlatform): TAtlasOpenBuildSettings.PickTarget wählt je Projekt die Konfiguration in
//   der Schreibweise des Projekts; fehlt sie dort, bleibt es bei der
//   Einstellung des Projekts. Die Plattform prüft die IDE-Schicht über die
//   im Projekt aktivierten Plattformen.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.OpenBuildSettings;

type
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
    cRequestedBy = 'open';
    cMaxAttempts = 10;
    /// <summary>Ein Lauf im Hintergrund der IDE gilt nach dieser Zeit ohne Ende als beendet.</summary>
    cMaxRunMs = 30 * 60 * 1000;
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
    /// <summary>Schlüssel eines Projekts: Pfad ohne Endung, klein.</summary>
    class function KeyOf(const AFileName: string): string; static;
    class function IsGroupFile(const AFileName: string): Boolean; static;
    class function IsProjectFile(const AFileName: string): Boolean; static;
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

class function TAtlasOpenBuild.KeyOf(const AFileName: string): string;
begin
  Result := TAtlasOpenBuildSettings.StripProjectExt(LowerCase(Trim(AFileName)));
end;

class function TAtlasOpenBuild.IsGroupFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.groupproj');
end;

class function TAtlasOpenBuild.IsProjectFile(const AFileName: string): Boolean;
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(AFileName));
  Result := (mExt = '.dproj') or (mExt = '.dpr') or (mExt = '.dpk') or (mExt = '.groupproj');
end;

function TAtlasOpenBuild.PendingIndex(const AFileName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to FPending.Count - 1 do
  begin
    if SameText(FPending[mIndex], AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
end;

procedure TAtlasOpenBuild.AddPending(const AFileName: string; ANowMs: Int64);
begin
  FLastOpened := ANowMs;
  if PendingIndex(AFileName) < 0 then
  begin
    FPending.Add(AFileName);
  end;
end;

procedure TAtlasOpenBuild.Opened(const AFileName: string; ANowMs: Int64);
begin
  if (Trim(AFileName) = '') or not IsProjectFile(AFileName) then
  begin
    Exit;
  end;
  FAttempts.AddOrSetValue(KeyOf(AFileName), 0);
  AddPending(AFileName, ANowMs);
end;

procedure TAtlasOpenBuild.Closed(const AFileName: string);
var
  mIndex: Integer;
begin
  FDone.Remove(KeyOf(AFileName));
  FAttempts.Remove(KeyOf(AFileName));
  mIndex := PendingIndex(AFileName);
  if mIndex >= 0 then
  begin
    FPending.Delete(mIndex);
  end;
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
  mKey: string;
  mAttempts: Integer;
begin
  mKey := KeyOf(AFileName);
  if not FAttempts.TryGetValue(mKey, mAttempts) then
  begin
    mAttempts := 0;
  end;
  Inc(mAttempts);
  Result := mAttempts < cMaxAttempts;
  if Result then
  begin
    FAttempts.AddOrSetValue(mKey, mAttempts);
    AddPending(AFileName, ANowMs);
  end
  else
  begin
    FAttempts.Remove(mKey);
  end;
end;

function TAtlasOpenBuild.Select(const AProjects, AExclude: TArray<string>): TArray<string>;
var
  mProject, mKey, mExcluded: string;
  mSkip: Boolean;
begin
  // Was Take geliefert hat, ist damit erledigt; Retry merkt Unaufgelöstes vorher neu vor.
  Result := nil;
  for mProject in AProjects do
  begin
    mKey := KeyOf(mProject);
    if (mKey = '') or FDone.ContainsKey(mKey) then
    begin
      Continue;
    end;
    mSkip := False;
    for mExcluded in AExclude do
    begin
      if SameText(TAtlasOpenBuildSettings.NameOf(mProject), mExcluded) then
      begin
        mSkip := True;
      end;
    end;
    // Auch ausgeschlossene gelten als erledigt: bis zum Schließen nicht noch einmal prüfen.
    FDone.Add(mKey, True);
    if not mSkip then
    begin
      Result := Result + [mProject];
    end;
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
  mProject: string;
begin
  FRunProjects.Clear;
  FRunResults.Clear;
  FCancelReason := '';
  for mProject in AProjects do
  begin
    FRunProjects.Add(mProject);
  end;
  FRunStartedAt := ANowMs;
  FRunning := True;
end;

function TAtlasOpenBuild.InRun(const AFileName: string): Boolean;
var
  mProject: string;
begin
  Result := False;
  if not FRunning then
  begin
    Exit;
  end;
  for mProject in FRunProjects do
  begin
    if KeyOf(mProject) = KeyOf(AFileName) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TAtlasOpenBuild.ProjectFinished(const AFileName: string; ASucceeded: Boolean);
begin
  if InRun(AFileName) then
  begin
    FRunResults.AddOrSetValue(KeyOf(AFileName), ASucceeded);
  end;
end;

procedure TAtlasOpenBuild.ProjectCancelled(const AFileName, AReason: string);
begin
  if not InRun(AFileName) then
  begin
    Exit;
  end;
  if FCancelReason = '' then
  begin
    FCancelReason := AReason;
  end;
  // Abgebrochen zählt als „nicht gebaut“: kein Eintrag in FRunResults.
  FRunResults.Remove(KeyOf(AFileName));
end;

function TAtlasOpenBuild.RunComplete: Boolean;
var
  mProject: string;
begin
  Result := FRunning;
  for mProject in FRunProjects do
  begin
    if not FRunResults.ContainsKey(KeyOf(mProject)) then
    begin
      Exit(False);
    end;
  end;
end;

function TAtlasOpenBuild.RunOverdue(ANowMs: Int64): Boolean;
begin
  Result := FRunning and (ANowMs - FRunStartedAt > cMaxRunMs);
end;

function TAtlasOpenBuild.RunFinished: TAtlasOpenBuildResult;
var
  mProject: string;
  mSucceeded: Boolean;
begin
  Result := Default(TAtlasOpenBuildResult);
  Result.CancelReason := FCancelReason;
  for mProject in FRunProjects do
  begin
    Inc(Result.Total);
    if not FRunResults.TryGetValue(KeyOf(mProject), mSucceeded) then
    begin
      Inc(Result.NotBuilt);
      Result.NotBuiltNames := Result.NotBuiltNames + [TAtlasOpenBuildSettings.NameOf(mProject)];
    end
    else if mSucceeded then
    begin
      Inc(Result.Succeeded);
    end
    else
    begin
      Inc(Result.Failed);
      Result.FailedNames := Result.FailedNames + [TAtlasOpenBuildSettings.NameOf(mProject)];
    end;
  end;
  FRunning := False;
  FRunProjects.Clear;
  FRunResults.Clear;
  FCancelReason := '';
end;

end.
