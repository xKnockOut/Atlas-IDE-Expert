unit Atlas.IDE.Debug.NoteValues;

// Werte für „Debug-Zustand festhalten“ (#582): lokale Variablen und die
// überwachten Ausdrücke des Fensters „Variablen“ (#853) am aktuellen Halt,
// auch wenn das Fenster zu ist.
//   - Die Namen der lokalen Variablen liefert der Server (wie im Fenster,
//     TAtlasVariables.cCommand), die Ausdrücke kommen aus der Ablage des
//     Fensters (je Projekt).
//   - Ausgewertet wird über TAtlasIdeVariablesLists in Zeitscheiben ohne
//     Nebenwirkungen; Werte strukturierter Typen gehen als Ganzes in die
//     Notiz (Teile zerlegt TAtlasDebugNote.ValuesOf), Felder werden nicht
//     nachgeladen.
//   - Fertig ist die Sammlung, wenn alles ausgewertet ist, nach cTimeoutMs
//     oder wenn das Programm weiterläuft; was dann fehlt, steht als „nicht
//     ausgewertet“ in der Notiz.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  Atlas.Core.Debug.Note,
  Atlas.IDE.Debug.StopView,
  Atlas.IDE.Debug.Variables,
  Atlas.IDE.Debug.VariablesLists,
  Atlas.IDE.Debug.VariablesStore;

type
  /// <summary>Werte des Halts sind gesammelt.</summary>
  TAtlasNoteValuesDone = reference to procedure(const ALocals, AWatches: TAtlasDebugNoteValues);

  TAtlasIdeDebugNoteValues = class(TAtlasIdeDebugStopView)
  public const
    cTickMs = 10;
    cRequestTimeoutMs = 3000;
    /// <summary>Länger wartet die Notiz nicht auf Werte.</summary>
    cTimeoutMs = 5000;
  private class var
    FLive: TAtlasIdeDebugNoteValues;
  private
    FSession: TAtlasVariablesSessionFunc;
    FRun: TAtlasVariablesRunner;
    FLists: TAtlasIdeVariablesLists;
    FStore: TAtlasIdeVariablesStore;
    FDone: TAtlasNoteValuesDone;
    FFileName: string;
    FLine: Integer;
    FStarted: UInt64;
    procedure Accept(ARequest: Integer; const AAnswer: string);
    procedure Finish;
  protected
    procedure SessionResumed; override;
    procedure SessionEnded; override;
    procedure Ask; override;
    procedure EvaluateSlice; override;
  public
    constructor Create(const ASession: TAtlasVariablesSessionFunc; const ARun: TAtlasVariablesRunner);
    destructor Destroy; override;
    /// <summary>Werte am Halt AFileName, ALine (1-basiert) sammeln; ADone kommt genau einmal, auch ohne Ort oder
    /// Server (dann nur mit den Ausdrücken). Ohne angehaltenes Programm sofort mit leeren Listen.</summary>
    procedure Collect(const AFileName: string; ALine: Integer; const ADone: TAtlasNoteValuesDone);
    /// <summary>Sammelt gerade?</summary>
    function Busy: Boolean;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Debug.StopProgress,
  Atlas.Core.Debug.Variables,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Report;

/// <summary>Antwort des Servers an AValues, solange es dieselbe Sammlung gibt.</summary>
function Answered(AValues: TAtlasIdeDebugNoteValues; ARequest: Integer): TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    begin
      if TAtlasIdeDebugNoteValues.FLive = AValues then
      begin
        AValues.Accept(ARequest, AAnswer);
      end;
    end;
end;

{ TAtlasIdeDebugNoteValues }

constructor TAtlasIdeDebugNoteValues.Create(const ASession: TAtlasVariablesSessionFunc;
  const ARun: TAtlasVariablesRunner);
begin
  inherited Create;
  FSession := ASession;
  FRun := ARun;
  FLists := TAtlasIdeVariablesLists.Create(nil);
  FStore := TAtlasIdeVariablesStore.Create;
  CreateTimer(cTickMs);
  FLive := Self;
  Listen;
end;

destructor TAtlasIdeDebugNoteValues.Destroy;
begin
  if FLive = Self then
  begin
    FLive := nil;
  end;
  FDone := nil;
  FreeAndNil(FStore);
  FreeAndNil(FLists);
  FFileName := '';
  inherited Destroy;
end;

function TAtlasIdeDebugNoteValues.Busy: Boolean;
begin
  Result := Assigned(FDone);
end;

procedure TAtlasIdeDebugNoteValues.Collect(const AFileName: string; ALine: Integer;
  const ADone: TAtlasNoteValuesDone);
var
  mProject: string;
begin
  FDone := ADone;
  FFileName := AFileName;
  FLine := ALine - 1;
  FStarted := GetTickCount64;
  FProgress.Restart(TAtlasIdeDebugSession.StopCount);
  FLists.Cancel;
  FLists.BeginStop;
  FLists[TAtlasVariablesTab.Autos].Replace(nil);
  FLists[TAtlasVariablesTab.Locals].Replace(nil);
  FStore.SwitchProject(mProject);
  FLists[TAtlasVariablesTab.Watch].Replace(FStore.Items(mProject));
  if not StillAtStop then
  begin
    Finish;
    Exit;
  end;
  Ask;
end;

procedure TAtlasIdeDebugNoteValues.Ask;
var
  mSession: TLspSession;
  mText: string;
  mRequest: Integer;
begin
  mRequest := FProgress.NextRequest;
  FProgress.Phase := TAtlasStopPhase.Request;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  // Ohne Ort, Server oder lesbare Datei: nur die Ausdrücke.
  if (FFileName = '') or (FLine < 0) or (mSession = nil) or not Assigned(FRun) or
    not TAtlasIdeFiles.SourceText(FFileName, mText) then
  begin
    Accept(mRequest, '');
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(FFileName, mText);
  if not FRun(TAtlasVariables.cCommand, TAtlasVariables.Arguments(TLspSession.PathToUri(FFileName), FLine, -1),
    cRequestTimeoutMs, Answered(Self, mRequest)) then
  begin
    Accept(mRequest, '');
  end;
end;

procedure TAtlasIdeDebugNoteValues.Accept(ARequest: Integer; const AAnswer: string);
var
  mAnswer: TAtlasVariablesAnswer;
begin
  if not Busy or not FProgress.Accepts(ARequest) then
  begin
    Exit;
  end;
  if not StillAtStop then
  begin
    Finish;
    Exit;
  end;
  if TAtlasVariables.ReadAnswerText(AAnswer, mAnswer) then
  begin
    FLists[TAtlasVariablesTab.Locals].Replace(mAnswer.Locals);
  end;
  BeginEvaluate(cTickMs);
end;

procedure TAtlasIdeDebugNoteValues.EvaluateSlice;
var
  mChanged: Boolean;
begin
  if not Busy or not StillAtStop or (GetTickCount64 - FStarted > cTimeoutMs) then
  begin
    Finish;
    Exit;
  end;
  // Verzögerter Wert (LLDB): warten.
  if FLists.Busy then
  begin
    Exit;
  end;
  case FLists.Slice(TAtlasVariablesTab.Locals, FFileName, FLine, mChanged) of
    TAtlasVariablesStep.Done, TAtlasVariablesStep.Stopped:
      Finish;
    TAtlasVariablesStep.More, TAtlasVariablesStep.Wait: ;
  end;
end;

procedure TAtlasIdeDebugNoteValues.SessionResumed;
begin
  // Weiter mit dem, was da ist: Das Programm läuft, Werte kommen keine mehr.
  if Busy then
  begin
    Finish;
  end;
end;

procedure TAtlasIdeDebugNoteValues.SessionEnded;
begin
  if Busy then
  begin
    Finish;
  end;
end;

procedure TAtlasIdeDebugNoteValues.Finish;
var
  mDone: TAtlasNoteValuesDone;
  mTexts: TAtlasDebugNoteTexts;
begin
  FTimer.Enabled := False;
  FProgress.Discard;
  FLists.Cancel;
  mDone := FDone;
  FDone := nil;
  if not Assigned(mDone) then
  begin
    Exit;
  end;
  mTexts := TAtlasIdeDebugReport.NoteTexts;
  mDone(TAtlasDebugNote.ValuesOf(FLists[TAtlasVariablesTab.Locals], mTexts),
    TAtlasDebugNote.ValuesOf(FLists[TAtlasVariablesTab.Watch], mTexts));
end;

end.
