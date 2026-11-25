unit Atlas.IDE.Debug.Trace;

// Schritte „Einzelne Anweisung“ (F7) und „Bis zur nächsten Quelltextzeile“
// (Umschalt+F7) der IDE für alle Debugger-Funktionen von Atlas (#578, #850).
// Was der Benutzer gedrückt hat, meldet die Open Tools API nicht. Atlas hängt
// sich deshalb an die beiden Aktionen der IDE (RunTraceIntoCommand bzw.
// RunTraceToSourceCommand, sonst die Aktion mit F7 bzw. Umschalt+F7) und
// meldet den Schritt vor dem Ausführen an alle angemeldeten Empfänger; danach
// läuft die Aktion wie bisher. Ein Haken je Aktion für alle Empfänger: Hingen
// mehrere Funktionen eigene Haken an dieselbe Aktion, stellte das Abmelden in
// anderer Reihenfolge als dem Anmelden eine Methode eines schon freigegebenen
// Hakens als OnExecute wieder her.
// StepInto setzt aus Atlas heraus mit „Einzelne Anweisung“ fort (Schrittfilter
// nach dem Zurückkehren); die Empfänger erfahren das mit Origin = Atlas, als
// hätte der Benutzer an dieser Stelle F7 gedrückt.
// Rückgabewerte (#844) melden sich zusätzlich für „Gesamte Routine“ (F8,
// RunStepOverCommand) und „Bis zur Rückkehr ausführen“ (Umschalt+F8,
// RunRunUntilReturnCommand) an (AddStepHandler mit den gewünschten Arten);
// jeder Empfänger erfährt nur seine Arten, Atlas hängt nur an Aktionen, die
// ein Empfänger will.
// Ohne Empfänger hängt Atlas an keiner Aktion. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Actions,
  Atlas.ToolsApi.Commands.ActionHook;

type
  {$SCOPEDENUMS ON}
  TAtlasTraceKind = (TraceInto, TraceToSource, StepOver, RunUntilReturn);
  /// <summary>User: Taste, Menü oder Symbolleiste der IDE; Atlas: TAtlasIdeDebugTrace.StepInto.</summary>
  TAtlasTraceOrigin = (User, Atlas);
  {$SCOPEDENUMS OFF}

  TAtlasTraceKinds = set of TAtlasTraceKind;

  TAtlasTraceEvent = reference to procedure(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin);

  TAtlasIdeDebugTrace = class
  public const
    /// <summary>Namen der Aktionen in der Aktionsliste der IDE.</summary>
    cActionNames: array[TAtlasTraceKind] of string = ('RunTraceIntoCommand', 'RunTraceToSourceCommand',
      'RunStepOverCommand', 'RunRunUntilReturnCommand');
    /// <summary>Arten von AddHandler: die beiden Schritte hinein.</summary>
    cTraceKinds: TAtlasTraceKinds = [TAtlasTraceKind.TraceInto, TAtlasTraceKind.TraceToSource];
  private type
    /// <summary>Hängt an einer Aktion: meldet den Schritt, dann die Aktion wie bisher.</summary>
    THook = class(TAtlasIdeActionHook)
    private
      FKind: TAtlasTraceKind;
    protected
      procedure Intercept; override;
    public
      constructor Create(AKind: TAtlasTraceKind; AAction: TContainedAction); reintroduce;
    end;
    THandler = record
      Name: string;
      Kinds: TAtlasTraceKinds;
      Event: TAtlasTraceEvent;
    end;
  private class var
    FHooks: array[TAtlasTraceKind] of THook;
    FHandlers: TArray<THandler>;
    class function FindAction(AKind: TAtlasTraceKind): TContainedAction; static;
    class procedure Notify(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin); static;
    class procedure Hook; static;
    class procedure Unhook; static;
  public
    /// <summary>Empfänger unter AName für F7 und Umschalt+F7 anmelden (ein zweiter Aufruf mit demselben Namen
    /// ersetzt ihn); hängt Atlas an die Aktionen.</summary>
    class procedure AddHandler(const AName: string; const AEvent: TAtlasTraceEvent); static;
    /// <summary>Wie AddHandler, für die Schritte AKinds.</summary>
    class procedure AddStepHandler(const AName: string; AKinds: TAtlasTraceKinds; const AEvent: TAtlasTraceEvent);
      static;
    /// <summary>Empfänger abmelden; beim letzten hängt Atlas sich von den Aktionen ab.</summary>
    class procedure RemoveHandler(const AName: string); static;
    /// <summary>Aus Atlas „Einzelne Anweisung“: Empfänger melden (Origin Atlas), dann fortsetzen; False ohne
    /// angehaltenen Prozess.</summary>
    class function StepInto: Boolean; static;
    class procedure Release; static;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.ActnList,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.IDE.Debug.Session;

{ TAtlasIdeDebugTrace.THook }

constructor TAtlasIdeDebugTrace.THook.Create(AKind: TAtlasTraceKind; AAction: TContainedAction);
begin
  FKind := AKind;
  inherited Create(AAction);
end;

procedure TAtlasIdeDebugTrace.THook.Intercept;
begin
  // Melden darf den Schritt nie verhindern; jeder Empfänger läuft unter der Sicherung.
  TAtlasIdeDebugTrace.Notify(FKind, TAtlasTraceOrigin.User);
  RunOriginal;
end;

{ TAtlasIdeDebugTrace }

class function TAtlasIdeDebugTrace.FindAction(AKind: TAtlasTraceKind): TContainedAction;
var
  mServices: INTAServices;
  mIndex: Integer;
  mAction: TContainedAction;
  mShortCut: TShortCut;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    mAction := mServices.ActionList.Actions[mIndex];
    if SameText(mAction.Name, cActionNames[AKind]) then
    begin
      Exit(mAction);
    end;
  end;
  // Ersatz: die Aktion mit dem üblichen Tastenkürzel.
  case AKind of
    TAtlasTraceKind.TraceToSource:
      mShortCut := ShortCut(VK_F7, [ssShift]);
    TAtlasTraceKind.StepOver:
      mShortCut := ShortCut(VK_F8, []);
    TAtlasTraceKind.RunUntilReturn:
      mShortCut := ShortCut(VK_F8, [ssShift]);
  else
    mShortCut := ShortCut(VK_F7, []);
  end;
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    mAction := mServices.ActionList.Actions[mIndex];
    if (mAction is TCustomAction) and (TCustomAction(mAction).ShortCut = mShortCut) then
    begin
      Exit(mAction);
    end;
  end;
end;

class procedure TAtlasIdeDebugTrace.Notify(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin);
var
  mHandlers: TArray<THandler>;
  mHandler: THandler;
begin
  // Kopie: Ein Empfänger darf sich dabei abmelden.
  mHandlers := Copy(FHandlers);
  for mHandler in mHandlers do
  begin
    if Assigned(mHandler.Event) and (AKind in mHandler.Kinds) then
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger,
        procedure
        begin
          mHandler.Event(AKind, AOrigin);
        end);
    end;
  end;
end;

class procedure TAtlasIdeDebugTrace.Hook;
var
  mKind: TAtlasTraceKind;
  mAction: TContainedAction;
  mWanted: TAtlasTraceKinds;
  mHandler: THandler;
begin
  mWanted := [];
  for mHandler in FHandlers do
  begin
    mWanted := mWanted + mHandler.Kinds;
  end;
  for mKind := Low(TAtlasTraceKind) to High(TAtlasTraceKind) do
  begin
    if (FHooks[mKind] <> nil) or not (mKind in mWanted) then
    begin
      Continue;
    end;
    mAction := FindAction(mKind);
    if mAction <> nil then
    begin
      FHooks[mKind] := THook.Create(mKind, mAction);
    end
    else
    begin
      TAtlasGuard.Log(Format('Debugger: Aktion %s nicht gefunden; der Schritt bleibt unverändert',
        [cActionNames[mKind]]));
    end;
  end;
end;

class procedure TAtlasIdeDebugTrace.Unhook;
var
  mKind: TAtlasTraceKind;
begin
  for mKind := Low(TAtlasTraceKind) to High(TAtlasTraceKind) do
  begin
    FreeAndNil(FHooks[mKind]);
  end;
end;

class procedure TAtlasIdeDebugTrace.AddHandler(const AName: string; const AEvent: TAtlasTraceEvent);
begin
  AddStepHandler(AName, cTraceKinds, AEvent);
end;

class procedure TAtlasIdeDebugTrace.AddStepHandler(const AName: string; AKinds: TAtlasTraceKinds;
  const AEvent: TAtlasTraceEvent);
var
  mIndex: Integer;
  mHandler: THandler;
begin
  for mIndex := 0 to High(FHandlers) do
  begin
    if SameText(FHandlers[mIndex].Name, AName) then
    begin
      FHandlers[mIndex].Kinds := AKinds;
      FHandlers[mIndex].Event := AEvent;
      Hook;
      Exit;
    end;
  end;
  mHandler.Name := AName;
  mHandler.Kinds := AKinds;
  mHandler.Event := AEvent;
  SetLength(FHandlers, Length(FHandlers) + 1);
  FHandlers[High(FHandlers)] := mHandler;
  Hook;
end;

class procedure TAtlasIdeDebugTrace.RemoveHandler(const AName: string);
var
  mIndex: Integer;
begin
  for mIndex := High(FHandlers) downto 0 do
  begin
    if SameText(FHandlers[mIndex].Name, AName) then
    begin
      FHandlers[mIndex].Event := nil;
      Delete(FHandlers, mIndex, 1);
    end;
  end;
  if Length(FHandlers) = 0 then
  begin
    Unhook;
  end;
end;

class function TAtlasIdeDebugTrace.StepInto: Boolean;
begin
  Result := TAtlasIdeDebugSession.StoppedThread <> nil;
  if not Result then
  begin
    Exit;
  end;
  Notify(TAtlasTraceKind.TraceInto, TAtlasTraceOrigin.Atlas);
  Result := TAtlasIdeDebugSession.RunMode(ormStmtStepInto);
end;

class procedure TAtlasIdeDebugTrace.Release;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FHandlers) do
  begin
    FHandlers[mIndex].Event := nil;
  end;
  FHandlers := nil;
  Unhook;
end;

end.
