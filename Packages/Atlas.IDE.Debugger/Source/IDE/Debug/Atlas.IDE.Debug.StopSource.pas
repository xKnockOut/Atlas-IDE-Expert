unit Atlas.IDE.Debug.StopSource;

// Halt der Debug-Sitzung für andere Module (#1873): stellt
// IAtlasDebugStopSource bereit. Das Modul Tests („Test daraus anlegen …“)
// fragt den Vertrag über die Registry und kennt den Debugger nicht.
//   - StopFrame: Rahmen des Halts. Steht der oberste Rahmen in eigenem Code
//     (#578), ist er es und wird ausgewertet; sonst der erste eigene Rahmen
//     (Exception in RTL oder VCL), dessen Werte nur aus der Kopfzeile kommen.
//     Klasse und Meldung der Exception, wenn der Exception-Verlauf (#517)
//     diesen Halt aufgenommen hat.
//   - Evaluate: über TAtlasIdeDebugEvaluator ohne Nebenwirkungen (nur Felder),
//     auf Wunsch mit Gettern; Zeitgrenze wie bei den Visualisierern.
// Nur im Hauptthread verwenden.

interface

uses
  Atlas.IDE.Debug.Exceptions,
  Atlas.IDE.Contracts.DebugStop;

type
  TAtlasIdeDebugStopSource = class(TInterfacedObject, IAtlasDebugStopSource)
  private class var
    /// <summary>Zuletzt aufgenommener Halt wegen einer Exception (für Klasse und Meldung).</summary>
    FLast: TAtlasDebugExceptionStop;
    FHandler: Integer;
    class procedure ExceptionTaken(const AStop: TAtlasDebugExceptionStop); static;
  public
    constructor Create;
    destructor Destroy; override;
    function StopFrame(out AFrame: TAtlasDebugStopFrame): Boolean;
    function Evaluate(const AExpression: string; AProperties: Boolean; out AText: string): Boolean;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.OwnCode,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Sources,
  Atlas.IDE.Debug.Evaluator;

constructor TAtlasIdeDebugStopSource.Create;
begin
  inherited Create;
  FLast := Default(TAtlasDebugExceptionStop);
  FHandler := TAtlasIdeDebugExceptions.AddExceptionHandler(ExceptionTaken);
end;

destructor TAtlasIdeDebugStopSource.Destroy;
begin
  TAtlasIdeDebugExceptions.RemoveExceptionHandler(FHandler);
  FHandler := 0;
  FLast := Default(TAtlasDebugExceptionStop);
  inherited Destroy;
end;

class procedure TAtlasIdeDebugStopSource.ExceptionTaken(const AStop: TAtlasDebugExceptionStop);
begin
  FLast := AStop;
end;

function TAtlasIdeDebugStopSource.StopFrame(out AFrame: TAtlasDebugStopFrame): Boolean;
var
  mThread: IOTAThread;
  mFrames: TAtlasDebugFrames;
  mIndex: Integer;
begin
  AFrame := Default(TAtlasDebugStopFrame);
  mThread := TAtlasIdeDebugSession.StoppedThread;
  if (mThread = nil) or (TAtlasIdeDebugSession.ReadStack(mThread, TAtlasDebugCallStack.cMaxFrames,
    mFrames) <> TAtlasDebugStackRead.Ready) then
  begin
    Exit(False);
  end;
  TAtlasIdeDebugSources.MarkFrames(mFrames);
  // Erster eigener Rahmen mit Quelltext, ohne eigenen der oberste mit Quelltext.
  mIndex := TAtlasDebugOwnCode.LocationIndex(mFrames, True);
  if mIndex < 0 then
  begin
    Exit(False);
  end;
  AFrame.FileName := TAtlasIdeDebugSources.Resolve(mFrames[mIndex].FileName);
  if AFrame.FileName = '' then
  begin
    AFrame.FileName := mFrames[mIndex].FileName;
  end;
  AFrame.Line := mFrames[mIndex].Line;
  AFrame.Header := mFrames[mIndex].Header;
  AFrame.Current := mIndex = 0;
  if FLast.Stop = TAtlasIdeDebugSession.StopCount then
  begin
    AFrame.ExceptionClass := FLast.Exception.ExceptionClass;
    AFrame.ExceptionMessage := FLast.Exception.Message;
  end;
  Result := True;
end;

function TAtlasIdeDebugStopSource.Evaluate(const AExpression: string; AProperties: Boolean;
  out AText: string): Boolean;
var
  mEvaluation: TAtlasVisualizerEvaluation;
begin
  mEvaluation := TAtlasVisualizerEvaluation.Fields;
  if AProperties then
  begin
    mEvaluation := TAtlasVisualizerEvaluation.Properties;
  end;
  Result := TAtlasIdeDebugEvaluator.Evaluate(AExpression, mEvaluation,
    TAtlasIdeSettings.Current.DebugVisualizerTimeoutMs, AText);
end;

end.
