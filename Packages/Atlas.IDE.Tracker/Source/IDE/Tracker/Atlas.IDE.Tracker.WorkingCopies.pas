unit Atlas.IDE.Tracker.WorkingCopies;

// Arbeitskopien je Tracker-Projekt (#1926) in der IDE.
// - FolderOf: Haupt-Arbeitskopie eines Projekts (bzw. des „Gilt für“ eines
//   gewählten Tracker-Projekts, #1927) aus issues.projects über
//   TAtlasTrackerProjects.WorkingFolder; ohne "paths" der Ordner der Datei.
//   „Beginnen“, „Beenden“, Zeiterfassung und der Reiter „Entwicklung“ arbeiten
//   dort.
// - Heads: Branch und Art dort, wenn die Zeile eigene Arbeitskopien nennt
//   (sonst gilt der Stand aus der Projekt-Zusammenfassung wie bisher). Im
//   Hintergrund abgefragt (TAtlasIdeVcs.Run), eine Minute gemerkt; danach
//   meldet der Haken Changed. Nur im Hauptthread aufrufen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.VersionControl.Contract;

type
  /// <summary>Gemerkter Stand einer Arbeitskopie.</summary>
  TAtlasTrackerWorkingHead = record
    Kind: TAtlasVcsKind;
    Branch: string;
    Tick: UInt64;
    Querying: Boolean;
  end;

  /// <summary>Gemeinsamer Zwischenspeicher; als Schnittstelle gehalten, damit eine Abfrage im Hintergrund ihn
  /// auch nach Stop noch erreicht.</summary>
  IAtlasTrackerWorkingHeads = interface
    ['{3C8E1B57-9D2A-4F6E-B1A0-7E5D4C2B9A13}']
    /// <summary>Stand in AFolder; False, solange noch nichts bekannt ist (die Abfrage läuft dann).</summary>
    function HeadOf(const AFolder: string; out AHead: TAtlasTrackerWorkingHead): Boolean;
    /// <summary>AFolder beim nächsten HeadOf neu abfragen (nach „Beginnen“).</summary>
    procedure Forget(const AFolder: string);
    /// <summary>Haken lösen; danach fragt HeadOf nichts mehr ab.</summary>
    procedure Stop;
  end;

  TAtlasIdeTrackerWorkingCopies = class
  public const
    /// <summary>So lange gilt ein abgefragter Branch.</summary>
    cHeadCacheMs = 60000;
    /// <summary>Zeitlimit je Abfrage.</summary>
    cVcsTimeoutMs = 5000;
  public
    /// <summary>Haupt-Arbeitskopie für AProject; '' ohne Projekt.</summary>
    class function FolderOf(const AProject: string): string; static;
    /// <summary>Alle Arbeitskopien für AProject (Haupt zuerst); nur [FolderOf] ohne eigene "paths".</summary>
    class function FoldersOf(const AProject: string): TArray<string>; static;
    /// <summary>Die geltende Zeile nennt eigene Arbeitskopien ("paths").</summary>
    class function HasOwnFolders(const AProject: string): Boolean; static;
    /// <summary>Zwischenspeicher für Heads; AChanged nach jeder fertigen Abfrage (Hauptthread).</summary>
    class function CreateHeads(const AChanged: TProc): IAtlasTrackerWorkingHeads; static;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Projects,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Contracts.VersionControl;

type
  TAtlasTrackerWorkingHeads = class(TInterfacedObject, IAtlasTrackerWorkingHeads)
  private
    FHeads: TDictionary<string, TAtlasTrackerWorkingHead>;
    FChanged: TProc;
    FStopped: Boolean;
    procedure Query(const AKey, AFolder: string);
    procedure Done(const AKey: string; const AHead: TAtlasTrackerWorkingHead);
  public
    constructor Create(const AChanged: TProc);
    destructor Destroy; override;
    function HeadOf(const AFolder: string; out AHead: TAtlasTrackerWorkingHead): Boolean;
    procedure Forget(const AFolder: string);
    procedure Stop;
  end;

/// <summary>Persönliche Zeilen und Verbindungen aus den Einstellungen; False, wenn sie nicht lesbar sind.</summary>
function ReadMappings(out AMappings: TArray<TAtlasTrackerProjectMapping>;
  out AConnections: TArray<TAtlasTrackerConnection>): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  AMappings := nil;
  AConnections := nil;
  Result := False;
  try
    mSettings := TAtlasIdeSettings.Current;
    AMappings := TAtlasTrackerProjects.Read(mSettings.IssuesProjects);
    AConnections := TAtlasTrackerConnections.Read(mSettings.IssuesConnections);
    Result := True;
  except
    // Einstellungen nicht lesbar: wie ohne Zuordnung.
    on E: Exception do
    begin
      TAtlasGuard.Report(TAtlasFeature.Tracker, E);
    end;
  end;
end;

/// <summary>Geltende persönliche Zeile für AProject; -1 ohne.</summary>
function MappingOf(const AProject: string; out AMappings: TArray<TAtlasTrackerProjectMapping>): Integer;
var
  mConnections: TArray<TAtlasTrackerConnection>;
  mResolution: TAtlasTrackerResolution;
begin
  Result := -1;
  if (Trim(AProject) = '') or not ReadMappings(AMappings, mConnections) then
  begin
    Exit;
  end;
  mResolution := TAtlasTrackerProjects.Resolve(TAtlasTrackerTarget.Create('', '', '', ''), AMappings, mConnections,
    AProject, TAtlasIdeFiles.GroupOfProject(AProject));
  Result := mResolution.Index;
end;

{ TAtlasIdeTrackerWorkingCopies }

class function TAtlasIdeTrackerWorkingCopies.FolderOf(const AProject: string): string;
var
  mMappings: TArray<TAtlasTrackerProjectMapping>;
  mConnections: TArray<TAtlasTrackerConnection>;
begin
  Result := '';
  if Trim(AProject) = '' then
  begin
    Exit;
  end;
  ReadMappings(mMappings, mConnections);
  Result := TAtlasTrackerProjects.WorkingFolder(mMappings, mConnections, AProject,
    TAtlasIdeFiles.GroupOfProject(AProject));
end;

class function TAtlasIdeTrackerWorkingCopies.FoldersOf(const AProject: string): TArray<string>;
var
  mMappings: TArray<TAtlasTrackerProjectMapping>;
  mIndex: Integer;
begin
  mIndex := MappingOf(AProject, mMappings);
  if (mIndex >= 0) and (Length(mMappings[mIndex].Paths) > 0) then
  begin
    Exit(mMappings[mIndex].Folders);
  end;
  Result := nil;
  if FolderOf(AProject) <> '' then
  begin
    Result := [FolderOf(AProject)];
  end;
end;

class function TAtlasIdeTrackerWorkingCopies.HasOwnFolders(const AProject: string): Boolean;
var
  mMappings: TArray<TAtlasTrackerProjectMapping>;
  mIndex: Integer;
begin
  mIndex := MappingOf(AProject, mMappings);
  Result := (mIndex >= 0) and (Length(mMappings[mIndex].Paths) > 0);
end;

class function TAtlasIdeTrackerWorkingCopies.CreateHeads(const AChanged: TProc): IAtlasTrackerWorkingHeads;
begin
  Result := TAtlasTrackerWorkingHeads.Create(AChanged);
end;

{ TAtlasTrackerWorkingHeads }

constructor TAtlasTrackerWorkingHeads.Create(const AChanged: TProc);
begin
  inherited Create;
  FHeads := TDictionary<string, TAtlasTrackerWorkingHead>.Create;
  FChanged := AChanged;
end;

destructor TAtlasTrackerWorkingHeads.Destroy;
begin
  FHeads.Free;
  inherited Destroy;
end;

procedure TAtlasTrackerWorkingHeads.Stop;
begin
  FStopped := True;
  FChanged := nil;
end;

procedure TAtlasTrackerWorkingHeads.Forget(const AFolder: string);
begin
  FHeads.Remove(TAtlasProjectSummaries.NormalizedPath(AFolder));
end;

function TAtlasTrackerWorkingHeads.HeadOf(const AFolder: string; out AHead: TAtlasTrackerWorkingHead): Boolean;
var
  mKey: string;
  mKnown: Boolean;
begin
  AHead := Default(TAtlasTrackerWorkingHead);
  mKey := TAtlasProjectSummaries.NormalizedPath(AFolder);
  if mKey = '' then
  begin
    Exit(False);
  end;
  mKnown := FHeads.TryGetValue(mKey, AHead);
  Result := mKnown and (AHead.Tick > 0);
  if FStopped or (mKnown and (AHead.Querying or
    (GetTickCount64 - AHead.Tick < TAtlasIdeTrackerWorkingCopies.cHeadCacheMs))) then
  begin
    Exit;
  end;
  Query(mKey, AFolder);
end;

procedure TAtlasTrackerWorkingHeads.Query(const AKey, AFolder: string);
var
  mHead, mOld: TAtlasTrackerWorkingHead;
  mKeep: IAtlasTrackerWorkingHeads;
  mOwner: TAtlasTrackerWorkingHeads;
  mFolder, mKey: string;
begin
  if not FHeads.TryGetValue(AKey, mOld) then
  begin
    mOld := Default(TAtlasTrackerWorkingHead);
  end;
  mOld.Querying := True;
  FHeads.AddOrSetValue(AKey, mOld);
  // Die Schnittstelle hält das Objekt bis zum Ende der Abfrage.
  mKeep := Self;
  mOwner := Self;
  mFolder := AFolder;
  mKey := AKey;
  mHead := Default(TAtlasTrackerWorkingHead);
  if not TAtlasIdeVcs.Run(
    procedure
    var
      mVcs: IAtlasVersionControl;
      mVcsHead: TAtlasVcsHead;
    begin
      mVcs := TAtlasIdeVcs.ForFolder(mFolder, TAtlasIdeTrackerWorkingCopies.cVcsTimeoutMs);
      if mVcs = nil then
      begin
        Exit;
      end;
      mHead.Kind := mVcs.Kind;
      if mVcs.Head(mVcsHead) = TAtlasVcsOutcome.Ok then
      begin
        mHead.Branch := mVcsHead.Branch;
        if mVcsHead.Detached then
        begin
          mHead.Branch := mVcsHead.ShortRevision(mHead.Kind);
        end;
      end;
    end,
    procedure
    begin
      mOwner.Done(mKey, mHead);
      mKeep := nil;
    end) then
  begin
    // Ohne Modul Versionsverwaltung: nichts bekannt, nicht erneut fragen.
    mOld.Querying := False;
    mOld.Tick := GetTickCount64;
    FHeads.AddOrSetValue(AKey, mOld);
  end;
end;

procedure TAtlasTrackerWorkingHeads.Done(const AKey: string; const AHead: TAtlasTrackerWorkingHead);
var
  mHead: TAtlasTrackerWorkingHead;
begin
  mHead := AHead;
  mHead.Querying := False;
  mHead.Tick := GetTickCount64;
  FHeads.AddOrSetValue(AKey, mHead);
  if not FStopped and Assigned(FChanged) then
  begin
    FChanged();
  end;
end;

end.
