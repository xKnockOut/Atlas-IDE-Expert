unit Atlas.IDE.Tests.UntestedProject;

// Befehl „Ungetestete Methoden des Projekts“ (#1783): fragt den laufenden
// Server im Hintergrund (atlas/untestedMethods für das Projekt der Unit im
// oberen Editor, Tiefe und private Methoden wie die Marke „getestet von“)
// und schreibt je Unit eine Zeile und je ungetesteter Methode eine
// anklickbare Zeile in die Meldungsansicht; die Units mit den meisten
// ungetesteten Methoden zuerst. Gezählt werden Methoden, die ein Test
// aufruft; das ist keine Abdeckungsmessung.

interface

uses
  Atlas.Core.Tests.Untested,
  Atlas.IDE.Tests.Output,
  Atlas.IDE.Tests.CoveredBy;

type
  TAtlasIdeUntestedProject = class
  private type
    /// <summary>Lebt, solange der Befehl lebt; die Antwort prüft es. Busy: eine Anfrage läuft.</summary>
    TState = class(TInterfacedObject)
    public
      Alive: Boolean;
      Busy: Boolean;
    end;
  private
    FOutput: TAtlasIdeTestsOutput;
    FScopeOf: TAtlasCoveredByScopeFunc;
    FState: TState;
    FStateRef: IInterface;
    procedure Answered(const AJson: string);
    procedure Report(const AProject: TAtlasUntestedProject);
  public
    /// <summary>AOutput gehört dem Aufrufer und lebt länger; AScopeOf liefert den Scope des Moduls.</summary>
    constructor Create(AOutput: TAtlasIdeTestsOutput; const AScopeOf: TAtlasCoveredByScopeFunc);
    destructor Destroy; override;
    /// <summary>Befehl „Ungetestete Methoden des Projekts“.</summary>
    procedure Run;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session.Json,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Tests.Strings,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings;

const
  // Der Server begrenzt sich auf 60 s; etwas Luft für Index und Antwort.
  cTimeoutMs = 90000;

function UriToPath(AUri: string): string;
begin
  Result := TLspSessionJson.UriToPath(AUri);
end;

/// <summary>Unit im oberen Editor; '' ohne.</summary>
function TopUnit: string;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
begin
  Result := '';
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  if (mView <> nil) and (mView.Buffer <> nil) and SameText(ExtractFileExt(mView.Buffer.FileName), '.pas') then
  begin
    Result := mView.Buffer.FileName;
  end;
end;

/// <summary>Abbruch der Anfrage, wenn der Befehl geht; eigene Routine, damit die Referenz nur AState einfängt.
/// </summary>
function CancelledFor(const AState: IInterface): TFunc<Boolean>;
var
  mState: IInterface;
begin
  mState := AState;
  Result :=
    function: Boolean
    begin
      Result := not TAtlasIdeUntestedProject.TState(mState as TObject).Alive;
    end;
end;

{ TAtlasIdeUntestedProject }

constructor TAtlasIdeUntestedProject.Create(AOutput: TAtlasIdeTestsOutput; const AScopeOf: TAtlasCoveredByScopeFunc);
begin
  inherited Create;
  FOutput := AOutput;
  FScopeOf := AScopeOf;
  FState := TState.Create;
  FState.Alive := True;
  FStateRef := FState;
end;

destructor TAtlasIdeUntestedProject.Destroy;
begin
  if FState <> nil then
  begin
    FState.Alive := False;
  end;
  FStateRef := nil;
  FScopeOf := nil;
  inherited Destroy;
end;

procedure TAtlasIdeUntestedProject.Run;
var
  mSettings: TAtlasPluginSettings;
  mFileName: string;
  mSelf: TAtlasIdeUntestedProject;
  mState: IInterface;
begin
  if FState.Busy then
  begin
    Exit;
  end;
  mFileName := TopUnit;
  if mFileName = '' then
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.UntestedProjectNoFile));
    FOutput.ShowView;
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Current;
  mSelf := Self;
  mState := FStateRef;
  FState.Busy := Assigned(FScopeOf) and TAtlasIdeHost.RunRequestAsync(FScopeOf(), TAtlasFeature.Build,
    TAtlasServerRequest.Create(TAtlasUntested.cProjectMethod,
    TAtlasUntested.ProjectParams(TLspSessionJson.PathToUri(mFileName), mSettings.TestsCoveredByDepth,
    mSettings.TestsCoveredByPrivate), cTimeoutMs, CancelledFor(mState)),
    procedure(AJson: string)
    begin
      // Der Befehl kann vor der Antwort gehen (Tests ausführen aus): dann nichts mehr anfassen (Regel 3).
      if TState(mState as TObject).Alive then
      begin
        mSelf.Answered(AJson);
      end;
    end);
  if FState.Busy then
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.UntestedProjectRunning));
  end
  else
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.UntestedProjectNoServer));
  end;
  FOutput.ShowView;
end;

procedure TAtlasIdeUntestedProject.Answered(const AJson: string);
var
  mProject: TAtlasUntestedProject;
begin
  FState.Busy := False;
  if (AJson = '') or not TAtlasUntested.FromJson(AJson, UriToPath, mProject) then
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.UntestedProjectFailed));
  end
  else
  begin
    Report(mProject);
  end;
  FOutput.ShowView;
end;

procedure TAtlasIdeUntestedProject.Report(const AProject: TAtlasUntestedProject);
var
  mUnit: TAtlasUntestedUnit;
  mMethod: TAtlasUntestedMethod;
begin
  for mUnit in AProject.Units do
  begin
    if mUnit.HasTestUnit then
    begin
      FOutput.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.UntestedProjectUnit,
        [mUnit.UnitName, mUnit.Tested, mUnit.Total, Length(mUnit.Untested)]));
    end
    else
    begin
      FOutput.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.UntestedProjectNoTestUnit,
        [mUnit.UnitName, Length(mUnit.Untested)]));
    end;
    for mMethod in mUnit.Untested do
    begin
      FOutput.Jump(mUnit.FileName, mMethod.Name, mMethod.Line, mMethod.Character);
    end;
  end;
  if Length(AProject.Units) = 0 then
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.UntestedProjectNone));
  end
  else
  begin
    FOutput.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.UntestedProjectSummary,
      [AProject.UntestedCount, Length(AProject.Units)]));
  end;
  if AProject.Skipped > 0 then
  begin
    FOutput.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.UntestedProjectSkipped, [AProject.Skipped]));
  end
  else if AProject.Incomplete then
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.UntestedProjectIncomplete));
  end;
end;

end.
