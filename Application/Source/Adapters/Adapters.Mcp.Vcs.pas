unit Adapters.Mcp.Vcs;

// Host-Adapter zwischen Mcp und dem Host: Die MCP-Werkzeuge lesen Änderungen und Verlauf über IMcpVcs, der Host
// erkennt Git oder SVN über seinen Zugang zur Versionsverwaltung (TCoreVcsAccess, Core.VersionControlChanges,
// Core.Hotspots, Core.SymbolHistory). Erzeugt nur in Shell.* und in Tests; kennt nur den Contract und den Host.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.History.Contract,
  Atlas.Common.Hotspots.Contract,
  Mcp.Contract.Vcs,
  Core.VersionControlChanges;

type
  /// <summary>Geladene Änderungen; gibt AChanges mit frei.</summary>
  TMcpVcsChangesAdapter = class(TInterfacedObject, IMcpVcsChanges)
  private
    FChanges: TVcsChanges;
  public
    /// <summary>Übernimmt AChanges.</summary>
    constructor Create(AChanges: TVcsChanges);
    destructor Destroy; override;
    function Name: string;
    function Git: Boolean;
    function RepoRoot: string;
    function Files: TArray<string>;
    function LineChanged(const AFileName: string; ALine: Integer): Boolean;
  end;

  TMcpVcsAdapter = class(TInterfacedObject, IMcpVcs)
  private
    FAccess: TFunc<TCoreVcsAccess>;
  public
    /// <summary>AAccess liefert für jede Anfrage einen neuen Zugang (Prozess, Runner, Öffnen).</summary>
    constructor Create(const AAccess: TFunc<TCoreVcsAccess>);
    /// <summary>Neuer Adapter als Interface (ohne Leck bei direkter Übergabe).</summary>
    class function New(const AAccess: TFunc<TCoreVcsAccess>): IMcpVcs; static;
    function Changes(const ARoot, ABase: string; const ASettings: TServerSettings; out AChanges: IMcpVcsChanges;
      out AError: string): Boolean;
    function Hotspots(const AFolder: string; const ASettings: TServerSettings; out AVcs: IHotspotVcs;
      out AError: string): Boolean;
    function SymbolHistory(const AFolder: string; const ASettings: TServerSettings; out AVcs: ISymbolHistoryVcs;
      out AError: string): Boolean;
  end;

implementation

uses
  Atlas.Common.History.ChangedFiles,
  Core.Hotspots,
  Core.SymbolHistory;

const
  /// <summary>Vergleichsbasis ohne eigene Basis: nicht eingecheckte Änderungen (SVN nimmt BASE).</summary>
  cHead = 'HEAD';

{ TMcpVcsChangesAdapter }

constructor TMcpVcsChangesAdapter.Create(AChanges: TVcsChanges);
begin
  inherited Create;
  FChanges := AChanges;
end;

destructor TMcpVcsChangesAdapter.Destroy;
begin
  FChanges.Free;
  inherited;
end;

function TMcpVcsChangesAdapter.Name: string;
begin
  Result := FChanges.Name;
end;

function TMcpVcsChangesAdapter.Git: Boolean;
begin
  Result := FChanges is TGitChanges;
end;

function TMcpVcsChangesAdapter.RepoRoot: string;
begin
  Result := FChanges.RepoRoot;
end;

function TMcpVcsChangesAdapter.Files: TArray<string>;
begin
  Result := FChanges.Files;
end;

function TMcpVcsChangesAdapter.LineChanged(const AFileName: string; ALine: Integer): Boolean;
var
  mLines: TChangedLines;
begin
  Result := TChangedFiles.LinesOf(FChanges.Lines, FChanges.RepoRoot, AFileName, mLines) and mLines.Contains(ALine);
end;

{ TMcpVcsAdapter }

constructor TMcpVcsAdapter.Create(const AAccess: TFunc<TCoreVcsAccess>);
begin
  inherited Create;
  FAccess := AAccess;
end;

class function TMcpVcsAdapter.New(const AAccess: TFunc<TCoreVcsAccess>): IMcpVcs;
begin
  Result := TMcpVcsAdapter.Create(AAccess);
end;

function TMcpVcsAdapter.Changes(const ARoot, ABase: string; const ASettings: TServerSettings;
  out AChanges: IMcpVcsChanges; out AError: string): Boolean;
var
  mAccess: TCoreVcsAccess;
  mVcs: TVcsChanges;
  mRef: string;
begin
  AChanges := nil;
  AError := '';
  mRef := ABase;
  if mRef = '' then
  begin
    mRef := cHead;
  end;
  // Über eine Variable halten: Detect gibt einen Probelauf frei, bevor es den nächsten startet.
  mAccess := FAccess();
  mVcs := nil;
  try
    mVcs := TVcsChanges.Detect(mAccess, ARoot, ASettings.VcsProvider, ASettings.VcsGitPath, ASettings.VcsSvnPath,
      ASettings.VcsTimeoutSeconds);
    // Ohne Basis: nicht eingecheckte Änderungen gegenüber HEAD (SVN: BASE); mit Basis seit der Abzweigung.
    mVcs.Load(mRef, ABase <> '', ABase = '', True, True);
    AChanges := TMcpVcsChangesAdapter.Create(mVcs);
  except
    on E: EVcsChanges do
    begin
      mVcs.Free;
      AError := E.Message;
    end;
  end;
  Result := AChanges <> nil;
end;

function TMcpVcsAdapter.Hotspots(const AFolder: string; const ASettings: TServerSettings; out AVcs: IHotspotVcs;
  out AError: string): Boolean;
var
  mAccess: TCoreVcsAccess;
begin
  mAccess := FAccess();
  Result := TCoreHotspotVcs.Detect(mAccess, AFolder, ASettings, AVcs, AError);
end;

function TMcpVcsAdapter.SymbolHistory(const AFolder: string; const ASettings: TServerSettings;
  out AVcs: ISymbolHistoryVcs; out AError: string): Boolean;
var
  mAccess: TCoreVcsAccess;
begin
  mAccess := FAccess();
  Result := TCoreSymbolHistoryVcs.DetectHistory(mAccess, AFolder, ASettings, AVcs, AError);
end;

end.
