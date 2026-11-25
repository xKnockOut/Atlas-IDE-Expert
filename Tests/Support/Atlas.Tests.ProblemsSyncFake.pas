unit Atlas.Tests.ProblemsSyncFake;

// Fälschungen für IAtlasProblemsServer und IAtlasProblemsEditors: kein
// Server, keine Threads, keine IDE. TAtlasProblemsServerFake schreibt mit, was
// der Ablauf der Probleme verlangt („sync:<Datei>“, „close:<Datei>“,
// „pause:<an/aus>“, „start“ bzw. „start+workspace“, „stop“, „target“), und
// hält Aufträge fest, bis der Test sie mit TakePulls abholt und die Antwort
// selbst über TAtlasProblemsResults.Document gibt. Was die IDE zeigt (Editor,
// geöffnete Dateien, Text auf der Platte, Debugger, Fehler der IDE), setzt der
// Test über die Eigenschaften von TAtlasProblemsEditorsFake.

interface

uses
  System.Classes,
  System.Generics.Collections,
  Atlas.Plugin.Problems.Contract,
  Atlas.Core.Problems.Contract.Sync;

type
  TAtlasProblemsServerFake = class(TInterfacedObject, IAtlasProblemsServer)
  private
    FCalls: TStringList;
    FSynced: TDictionary<string, string>;
    FSyncedOrder: TStringList;
    FPulls: TAtlasProblemsPulls;
    FPulling: Boolean;
    FSession: Integer;
    FStartable: Boolean;
    FRefreshCount: Integer;
    FProjectsRemoved: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    { IAtlasProblemsServer }
    function Connect(AStart: Boolean): Integer;
    procedure Sync(const AFileName, AText: string);
    procedure Close(const AFileName: string);
    function SyncedFiles: TArray<string>;
    function SyncedText(const AFileName: string; out AText: string): Boolean;
    function RefreshCount: Integer;
    function ProjectsRemoved: Integer;
    procedure PauseProjectCheck(APaused: Boolean);
    procedure UpdateTarget;
    procedure StartPulls(AWorkspace: Boolean);
    procedure StopPulls;
    function Pulling: Boolean;
    procedure Pull(const APulls: TAtlasProblemsPulls);
    function Idle: Boolean;
    procedure Collect;
    procedure WaitStopped;
    { Steuerung durch den Test }
    /// <summary>Wartende Aufträge; leert sie (danach Idle).</summary>
    function TakePulls: TAtlasProblemsPulls;
    /// <summary>Server neu gestartet: neue Kennung der Sitzung, abgeglichene Dateien weg.</summary>
    procedure Restart;
    /// <summary>Aufrufe, durch Komma getrennt; leert die Liste.</summary>
    function TakeCalls: string;
    /// <summary>Kennung der laufenden Sitzung; 0 = keine.</summary>
    property Session: Integer read FSession write FSession;
    /// <summary>Connect(True) startet eine Sitzung.</summary>
    property Startable: Boolean read FStartable write FStartable;
    property RefreshCounter: Integer read FRefreshCount write FRefreshCount;
    property RemovedProjects: Integer read FProjectsRemoved write FProjectsRemoved;
  end;

  TAtlasProblemsEditorsFake = class(TInterfacedObject, IAtlasProblemsEditors)
  private
    FEditor: TAtlasProblemsEditor;
    FHasEditor: Boolean;
    FCodeInFront: Boolean;
    FOpen: TStringList;
    FDisk: TDictionary<string, string>;
    FDebugging: Boolean;
    FIdeErrorsOn: Boolean;
    FIdeErrors: TDictionary<string, TArray<TAtlasProblem>>;
  public
    constructor Create;
    destructor Destroy; override;
    { IAtlasProblemsEditors }
    function ActiveEditor(out AEditor: TAtlasProblemsEditor): Boolean;
    function IsOpen(const AFileName: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function Debugging: Boolean;
    function IdeErrorsEnabled: Boolean;
    function IdeErrors(const AFileName: string; out AErrors: TArray<TAtlasProblem>): Boolean;
    { Steuerung durch den Test }
    /// <summary>Oberer Editor mit AFileName und AText; jeder Aufruf mit anderem Text ist ein neuer Pufferstand.
    /// AFileName '' = kein Editor.</summary>
    procedure ShowEditor(const AFileName, AText: string; AModified: Boolean);
    procedure SetIdeErrors(const AFileName: string; const AErrors: TArray<TAtlasProblem>);
    property Open: TStringList read FOpen;
    property Disk: TDictionary<string, string> read FDisk;
    property InDebugger: Boolean read FDebugging write FDebugging;
    property IdeErrorsOn: Boolean read FIdeErrorsOn write FIdeErrorsOn;
    /// <summary>Code vorn (sonst Designer oder Willkommensseite); anfangs True.</summary>
    property CodeInFront: Boolean read FCodeInFront write FCodeInFront;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasProblemsServerFake }

constructor TAtlasProblemsServerFake.Create;
begin
  inherited Create;
  FCalls := TStringList.Create;
  FSynced := TDictionary<string, string>.Create;
  FSyncedOrder := TStringList.Create;
  FSession := 1;
end;

destructor TAtlasProblemsServerFake.Destroy;
begin
  FSyncedOrder.Free;
  FSynced.Free;
  FCalls.Free;
  inherited Destroy;
end;

function TAtlasProblemsServerFake.Connect(AStart: Boolean): Integer;
begin
  if (FSession = 0) and AStart and FStartable then
  begin
    FSession := 1;
  end;
  Result := FSession;
end;

procedure TAtlasProblemsServerFake.Sync(const AFileName, AText: string);
begin
  FCalls.Add('sync:' + AFileName);
  if not FSynced.ContainsKey(AFileName) then
  begin
    FSyncedOrder.Add(AFileName);
  end;
  FSynced.AddOrSetValue(AFileName, AText);
end;

procedure TAtlasProblemsServerFake.Close(const AFileName: string);
var
  mIndex: Integer;
begin
  FCalls.Add('close:' + AFileName);
  FSynced.Remove(AFileName);
  mIndex := FSyncedOrder.IndexOf(AFileName);
  if mIndex >= 0 then
  begin
    FSyncedOrder.Delete(mIndex);
  end;
end;

function TAtlasProblemsServerFake.SyncedFiles: TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, FSyncedOrder.Count);
  for mIndex := 0 to FSyncedOrder.Count - 1 do
  begin
    Result[mIndex] := FSyncedOrder[mIndex];
  end;
end;

function TAtlasProblemsServerFake.SyncedText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FSynced.TryGetValue(AFileName, AText);
end;

function TAtlasProblemsServerFake.RefreshCount: Integer;
begin
  Result := FRefreshCount;
end;

function TAtlasProblemsServerFake.ProjectsRemoved: Integer;
begin
  Result := FProjectsRemoved;
end;

procedure TAtlasProblemsServerFake.PauseProjectCheck(APaused: Boolean);
const
  cStates: array[Boolean] of string = ('aus', 'an');
begin
  FCalls.Add('pause:' + cStates[APaused]);
end;

procedure TAtlasProblemsServerFake.UpdateTarget;
begin
  FCalls.Add('target');
end;

procedure TAtlasProblemsServerFake.StartPulls(AWorkspace: Boolean);
const
  cStarts: array[Boolean] of string = ('start', 'start+workspace');
begin
  if not FPulling then
  begin
    FCalls.Add(cStarts[AWorkspace]);
  end;
  FPulling := True;
end;

procedure TAtlasProblemsServerFake.StopPulls;
begin
  FCalls.Add('stop');
  FPulling := False;
  FPulls := nil;
end;

function TAtlasProblemsServerFake.Pulling: Boolean;
begin
  Result := FPulling;
end;

procedure TAtlasProblemsServerFake.Pull(const APulls: TAtlasProblemsPulls);
begin
  FPulls := FPulls + APulls;
end;

function TAtlasProblemsServerFake.Idle: Boolean;
begin
  Result := Length(FPulls) = 0;
end;

procedure TAtlasProblemsServerFake.Collect;
begin
  // Keine Threads.
end;

procedure TAtlasProblemsServerFake.WaitStopped;
begin
  // Keine Threads.
end;

function TAtlasProblemsServerFake.TakePulls: TAtlasProblemsPulls;
begin
  Result := FPulls;
  FPulls := nil;
end;

procedure TAtlasProblemsServerFake.Restart;
begin
  Inc(FSession);
  FSynced.Clear;
  FSyncedOrder.Clear;
end;

function TAtlasProblemsServerFake.TakeCalls: string;
begin
  FCalls.Delimiter := ',';
  FCalls.StrictDelimiter := True;
  Result := FCalls.DelimitedText;
  FCalls.Clear;
end;

{ TAtlasProblemsEditorsFake }

constructor TAtlasProblemsEditorsFake.Create;
begin
  inherited Create;
  FOpen := TStringList.Create;
  FOpen.CaseSensitive := False;
  FDisk := TDictionary<string, string>.Create;
  FIdeErrors := TDictionary<string, TArray<TAtlasProblem>>.Create;
  FCodeInFront := True;
end;

destructor TAtlasProblemsEditorsFake.Destroy;
begin
  FIdeErrors.Free;
  FDisk.Free;
  FOpen.Free;
  inherited Destroy;
end;

function TAtlasProblemsEditorsFake.ActiveEditor(out AEditor: TAtlasProblemsEditor): Boolean;
begin
  AEditor := FEditor;
  AEditor.CodeInFront := FCodeInFront;
  Result := FHasEditor;
end;

function TAtlasProblemsEditorsFake.IsOpen(const AFileName: string): Boolean;
begin
  Result := FOpen.IndexOf(AFileName) >= 0;
end;

function TAtlasProblemsEditorsFake.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FDisk.TryGetValue(AFileName, AText);
end;

function TAtlasProblemsEditorsFake.Debugging: Boolean;
begin
  Result := FDebugging;
end;

function TAtlasProblemsEditorsFake.IdeErrorsEnabled: Boolean;
begin
  Result := FIdeErrorsOn;
end;

function TAtlasProblemsEditorsFake.IdeErrors(const AFileName: string; out AErrors: TArray<TAtlasProblem>): Boolean;
begin
  Result := FIdeErrors.TryGetValue(AFileName, AErrors);
end;

procedure TAtlasProblemsEditorsFake.ShowEditor(const AFileName, AText: string; AModified: Boolean);
begin
  FHasEditor := AFileName <> '';
  if not SameFileName(AFileName, FEditor.FileName) or (AText <> FEditor.Text) then
  begin
    FEditor.Version := FEditor.Version + 1;
  end;
  FEditor.FileName := AFileName;
  FEditor.Text := AText;
  FEditor.Modified := AModified;
  if FHasEditor and (FOpen.IndexOf(AFileName) < 0) then
  begin
    FOpen.Add(AFileName);
  end;
end;

procedure TAtlasProblemsEditorsFake.SetIdeErrors(const AFileName: string; const AErrors: TArray<TAtlasProblem>);
begin
  FIdeErrors.AddOrSetValue(AFileName, AErrors);
end;

end.
