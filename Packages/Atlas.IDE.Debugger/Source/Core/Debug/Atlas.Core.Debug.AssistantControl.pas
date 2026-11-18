unit Atlas.Core.Debug.AssistantControl;

// Kern der Debug-Steuerung für KI-Assistenten (#1874), ohne IDE: Startparameter aus dem Auftrag (eigene Argumente
// oder die des Projekts, mit test nur dieser DUnitX-Test), Rahmen des Aufrufstapels für den Vertrag
// IAtlasDebugControl, Ort des Halts (erster Rahmen mit Quelltext) und Grund des Halts als festes Wort des Protokolls
// (exception, breakpoint, step, pause). Die IDE-Schicht ist Atlas.IDE.Debug.AssistantControl.

interface

uses
  Atlas.Core.Debug.CallStack,
  Atlas.Core.DebugControl.Types;

type
  {$SCOPEDENUMS ON}
  /// <summary>Was zum Halt geführt hat; Exception vor Haltepunkt vor Schritt.</summary>
  TAtlasDebugAssistantStop = (Pause, Step, Breakpoint, Exception);
  {$SCOPEDENUMS OFF}

  TAtlasDebugAssistantControl = class
  public const
    cStopNames: array[TAtlasDebugAssistantStop] of string = ('pause', 'step', 'breakpoint', 'exception');
  public
    /// <summary>Startparameter: ALaunch.Arguments, sonst AExisting (die des Projekts); mit ALaunch.Test dazu
    /// --run:&lt;Test&gt; und --exitbehavior:Continue (sonst wartet das Testprogramm am Ende auf Enter).</summary>
    class function Parameters(const AExisting: string; const ALaunch: TAtlasDebugControlLaunch): string; static;
    /// <summary>Braucht der Start vorübergehende Parameter (eigene Argumente oder ein Test)?</summary>
    class function NeedsParameters(const ALaunch: TAtlasDebugControlLaunch): Boolean; static;
    /// <summary>Höchstens AMax Rahmen aus AFrames für den Vertrag.</summary>
    class function Frames(const AFrames: TAtlasDebugFrames; AMax: Integer): TArray<TAtlasDebugControlFrame>; static;
    /// <summary>Erster Rahmen mit Quelltext; False ohne.</summary>
    class function Location(const AFrames: TAtlasDebugFrames; out AFileName: string; out ALine: Integer): Boolean;
      static;
    /// <summary>Grund des Halts aus den Beobachtungen der IDE-Schicht.</summary>
    class function StopOf(AException, ABreakpoint, AStepped: Boolean): TAtlasDebugAssistantStop; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.CommandLine;

{ TAtlasDebugAssistantControl }

class function TAtlasDebugAssistantControl.NeedsParameters(const ALaunch: TAtlasDebugControlLaunch): Boolean;
begin
  Result := (Trim(ALaunch.Arguments) <> '') or (Trim(ALaunch.Test) <> '');
end;

class function TAtlasDebugAssistantControl.Parameters(const AExisting: string;
  const ALaunch: TAtlasDebugControlLaunch): string;
begin
  Result := Trim(ALaunch.Arguments);
  if Result = '' then
  begin
    Result := Trim(AExisting);
  end;
  if Trim(ALaunch.Test) = '' then
  begin
    Exit;
  end;
  Result := Trim(Result + ' ' + TTextCommandLine.QuoteForParamStr('--run:' + Trim(ALaunch.Test)) +
    ' --exitbehavior:Continue');
end;

class function TAtlasDebugAssistantControl.Frames(const AFrames: TAtlasDebugFrames;
  AMax: Integer): TArray<TAtlasDebugControlFrame>;
var
  mCount, mIndex: Integer;
begin
  Result := nil;
  mCount := Length(AFrames);
  if mCount > AMax then
  begin
    mCount := AMax;
  end;
  if mCount <= 0 then
  begin
    Exit;
  end;
  SetLength(Result, mCount);
  for mIndex := 0 to mCount - 1 do
  begin
    Result[mIndex].FileName := AFrames[mIndex].FileName;
    Result[mIndex].Line := AFrames[mIndex].Line;
    Result[mIndex].Header := AFrames[mIndex].Header;
    Result[mIndex].Own := AFrames[mIndex].Own;
  end;
end;

class function TAtlasDebugAssistantControl.Location(const AFrames: TAtlasDebugFrames; out AFileName: string;
  out ALine: Integer): Boolean;
var
  mFrame: TAtlasDebugFrame;
begin
  AFileName := '';
  ALine := 0;
  for mFrame in AFrames do
  begin
    if mFrame.HasSource then
    begin
      AFileName := mFrame.FileName;
      ALine := mFrame.Line;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasDebugAssistantControl.StopOf(AException, ABreakpoint,
  AStepped: Boolean): TAtlasDebugAssistantStop;
begin
  if AException then
  begin
    Exit(TAtlasDebugAssistantStop.Exception);
  end;
  if ABreakpoint then
  begin
    Exit(TAtlasDebugAssistantStop.Breakpoint);
  end;
  if AStepped then
  begin
    Exit(TAtlasDebugAssistantStop.Step);
  end;
  Result := TAtlasDebugAssistantStop.Pause;
end;

end.
