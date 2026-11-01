unit Atlas.Core.Vcs.Composition;

// Auswahl der Umsetzung (#571): automatisch nach gefundener Arbeitskopie und
// nach vcs.provider (auto/git/svn/off).
//   - off: leere Umsetzung (Disabled)
//   - keine Arbeitskopie: leere Umsetzung (NoWorkingCopy)
//   - Arbeitskopie, aber git bzw. svn fehlt: leere Umsetzung (ToolMissing);
//     TAtlasVcsNotices meldet das einmal je Sitzung und Art, Atlas arbeitet
//     ohne diese Versionsverwaltung weiter
//   - sonst Git bzw. SVN über die Kommandozeile
// Open selbst startet keinen Prozess; es prüft nur Dateien (Arbeitskopie,
// Programm in PATH) und darf deshalb auch im Hauptthread laufen.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Atlas.Core.Vcs.Contract;

type
  TAtlasVcsLocate = reference to function(AKind: TAtlasVcsKind): string;

  /// <summary>Einmalige Meldungen der Versionsverwaltung je Sitzung.</summary>
  TAtlasVcsNotices = class
  private class var
    FLock: TCriticalSection;
    FReported: array[TAtlasVcsKind] of Boolean;
    FOnToolMissing: TProc<TAtlasVcsKind>;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>git bzw. svn fehlt: ruft OnToolMissing beim ersten Mal je Art, aus dem aufrufenden Thread;
    /// True, wenn es diesmal gemeldet wurde.</summary>
    class function ToolMissing(AKind: TAtlasVcsKind): Boolean; static;
    /// <summary>Für Tests und nach dem Entladen: wieder melden.</summary>
    class procedure Reset; static;
    class property OnToolMissing: TProc<TAtlasVcsKind> read FOnToolMissing write FOnToolMissing;
  end;

  TAtlasVersionControl = class
  public
    /// <summary>Umsetzung für AFolder. ALocate liefert den Pfad von git bzw. svn ('' = fehlt).</summary>
    class function Open(const AFolder: string; AProvider: TAtlasVcsProvider; const ARunner: IAtlasVcsRunner;
      const ALocate: TAtlasVcsLocate; ATimeoutMs: Cardinal): IAtlasVersionControl; overload; static;
    /// <summary>Wie oben; Programme über TAtlasVcsTools.Find, Zeitlimit TAtlasVcsCommand.DefaultTimeoutMs.</summary>
    class function Open(const AFolder: string; AProvider: TAtlasVcsProvider;
      const ARunner: IAtlasVcsRunner): IAtlasVersionControl; overload; static;
    /// <summary>Umsetzung für eine schon gefundene Arbeitskopie; ohne Programm die leere (ToolMissing).</summary>
    class function ForWorkingCopy(const AWorkingCopy: TAtlasVcsWorkingCopy; const ARunner: IAtlasVcsRunner;
      const AExecutable: string; ATimeoutMs: Cardinal): IAtlasVersionControl; static;
  end;

implementation

uses
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.Detection,
  Atlas.Core.Vcs.Providers.Git,
  Atlas.Core.Vcs.Providers.Svn,
  Atlas.Core.Vcs.Providers.Null;

{ TAtlasVcsNotices }

class constructor TAtlasVcsNotices.Create;
begin
  FLock := TCriticalSection.Create;
end;

class destructor TAtlasVcsNotices.Destroy;
begin
  FOnToolMissing := nil;
  FreeAndNil(FLock);
end;

class function TAtlasVcsNotices.ToolMissing(AKind: TAtlasVcsKind): Boolean;
var
  Handler: TProc<TAtlasVcsKind>;
begin
  FLock.Enter;
  try
    Result := not FReported[AKind];
    FReported[AKind] := True;
    Handler := FOnToolMissing;
  finally
    FLock.Leave;
  end;
  if Result and Assigned(Handler) then
    Handler(AKind);
end;

class procedure TAtlasVcsNotices.Reset;
var
  Kind: TAtlasVcsKind;
begin
  FLock.Enter;
  try
    for Kind := Low(TAtlasVcsKind) to High(TAtlasVcsKind) do
      FReported[Kind] := False;
  finally
    FLock.Leave;
  end;
end;

{ TAtlasVersionControl }

class function TAtlasVersionControl.ForWorkingCopy(const AWorkingCopy: TAtlasVcsWorkingCopy;
  const ARunner: IAtlasVcsRunner; const AExecutable: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
begin
  if AWorkingCopy.Kind = TAtlasVcsKind.None then
    Exit(TAtlasNullVersionControl.Create(TAtlasVcsOutcome.NoWorkingCopy));
  if AExecutable = '' then
  begin
    TAtlasVcsNotices.ToolMissing(AWorkingCopy.Kind);
    Exit(TAtlasNullVersionControl.Create(TAtlasVcsOutcome.ToolMissing));
  end;
  if AWorkingCopy.Kind = TAtlasVcsKind.Git then
    Result := TAtlasGitVersionControl.Create(AWorkingCopy.Root, ARunner, AExecutable, ATimeoutMs)
  else
    Result := TAtlasSvnVersionControl.Create(AWorkingCopy.Root, ARunner, AExecutable, ATimeoutMs);
end;

class function TAtlasVersionControl.Open(const AFolder: string; AProvider: TAtlasVcsProvider;
  const ARunner: IAtlasVcsRunner; const ALocate: TAtlasVcsLocate; ATimeoutMs: Cardinal): IAtlasVersionControl;
var
  WorkingCopy: TAtlasVcsWorkingCopy;
begin
  if AProvider = TAtlasVcsProvider.Off then
    Exit(TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled));
  WorkingCopy := TAtlasVcsDetection.Find(AFolder, AProvider);
  if WorkingCopy.Kind = TAtlasVcsKind.None then
    Exit(TAtlasNullVersionControl.Create(TAtlasVcsOutcome.NoWorkingCopy));
  Result := ForWorkingCopy(WorkingCopy, ARunner, ALocate(WorkingCopy.Kind), ATimeoutMs);
end;

class function TAtlasVersionControl.Open(const AFolder: string; AProvider: TAtlasVcsProvider;
  const ARunner: IAtlasVcsRunner): IAtlasVersionControl;
begin
  Result := Open(AFolder, AProvider, ARunner,
    function(AKind: TAtlasVcsKind): string
    begin
      Result := TAtlasVcsTools.Find(AKind);
    end,
    TAtlasVcsCommand.DefaultTimeoutMs);
end;

end.
