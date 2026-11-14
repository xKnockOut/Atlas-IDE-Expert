unit Shell.Composition.Profiler;

// Internals-Rolle Shell: Befehle des Stichproben-Profilers (#2057) atlas.server.profilerStart, …Status und …Stop.
// Gemessen wird im Server, weil er unter Windows ein 64-Bit-Prozess ist (Prober aus Shell.Platform); die Läufe liegen
// im Cache unter profiles, wo auch get_profile sie liest. Logik in Atlas.Common.Lsp.Profiler.

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Lsp.Profiler,
  Shell.Composition.Refactorings.Services;

type
  TShellProfiler = class(TShellRefactoringPart)
  private
    FProfiler: TLspProfiler;
  public
    constructor Create(const AServices: TShellRefactoringServices);
    destructor Destroy; override;
    procedure Register(ACommands: TLspCommands); override;
    function Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>; override;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Profiling.Contract,
  Atlas.Common.Profiling.Profile,
  Shell.Platform;

constructor TShellProfiler.Create(const AServices: TShellRefactoringServices);
begin
  inherited Create(AServices);
  FProfiler := TLspProfiler.Create(
    function: IAtlasProfileSampler
    begin
      Result := TShellPlatform.ProfileSampler;
    end, TAtlasProfileStore.Folder(TIndexCacheDirectory.DefaultRoot));
end;

destructor TShellProfiler.Destroy;
begin
  FreeAndNil(FProfiler);
  inherited;
end;

procedure TShellProfiler.Register(ACommands: TLspCommands);
begin
  FProfiler.Register(ACommands);
end;

function TShellProfiler.Actions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
begin
  Result := nil;
end;

end.
