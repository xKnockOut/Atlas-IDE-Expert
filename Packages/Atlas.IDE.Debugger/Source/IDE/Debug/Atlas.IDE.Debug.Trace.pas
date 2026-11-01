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
// Ohne Empfänger hängt Atlas an keiner Aktion. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Actions;

type
  {$SCOPEDENUMS ON}
  TAtlasTraceKind = (TraceInto, TraceToSource);
  /// <summary>User: Taste, Menü oder Symbolleiste der IDE; Atlas: TAtlasIdeDebugTrace.StepInto.</summary>
  TAtlasTraceOrigin = (User, Atlas);
  {$SCOPEDENUMS OFF}

  TAtlasTraceEvent = reference to procedure(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin);

  TAtlasIdeDebugTrace = class
  public const
    /// <summary>Namen der Aktionen in der Aktionsliste der IDE.</summary>
    ActionNames: array[TAtlasTraceKind] of string = ('RunTraceIntoCommand', 'RunTraceToSourceCommand');
  private type
    /// <summary>Hängt an einer Aktion: meldet den Schritt, dann die Aktion wie bisher.</summary>
    THook = class(TComponent)
    private
      FKind: TAtlasTraceKind;
      FAction: TContainedAction;
      FOriginal: TNotifyEvent;
      FBypass: Boolean;
      procedure Execute(Sender: TObject);
    protected
      procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    public
      constructor Create(AKind: TAtlasTraceKind; AAction: TContainedAction); reintroduce;
      destructor Destroy; override;
    end;
    THandler = record
      Name: string;
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
    /// <summary>Empfänger unter AName anmelden (ein zweiter Aufruf mit demselben Namen ersetzt ihn); hängt Atlas
    /// beim ersten an die Aktionen.</summary>
    class procedure AddHandler(const AName: string; const AEvent: TAtlasTraceEvent); static;
    /// <summary>Empfänger abmelden; beim letzten hängt Atlas sich von den Aktionen ab.</summary>
    class procedure RemoveHandler(const AName: string); static;
    /// <summary>Hängt Atlas an der Aktion? (Studie, Diagnose)</summary>
    class function Hooked(AKind: TAtlasTraceKind): Boolean; static;
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
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Debug.Session;

{ TAtlasIdeDebugTrace.THook }

constructor TAtlasIdeDebugTrace.THook.Create(AKind: TAtlasTraceKind; AAction: TContainedAction);
begin
  inherited Create(nil);
  FKind := AKind;
  FAction := AAction;
  FOriginal := AAction.OnExecute;
  FAction.OnExecute := Execute;
  FAction.FreeNotification(Self);
end;

destructor TAtlasIdeDebugTrace.THook.Destroy;
begin
  if FAction <> nil then
  begin
    FAction.RemoveFreeNotification(Self);
    FAction.OnExecute := FOriginal;
  end;
  inherited Destroy;
end;

procedure TAtlasIdeDebugTrace.THook.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FAction) then
    FAction := nil;
end;

procedure TAtlasIdeDebugTrace.THook.Execute(Sender: TObject);
begin
  if FBypass or (FAction = nil) then
    Exit;
  // Melden darf den Schritt nie verhindern; jeder Empfänger läuft unter der Sicherung.
  TAtlasIdeDebugTrace.Notify(FKind, TAtlasTraceOrigin.User);
  if Assigned(FOriginal) then
  begin
    FOriginal(Sender);
    Exit;
  end;
  // Ohne eigenes OnExecute erledigt die IDE die Aktion über ihre Liste: kurz abhängen und ausführen.
  FBypass := True;
  FAction.OnExecute := nil;
  try
    FAction.Execute;
  finally
    if FAction <> nil then
      FAction.OnExecute := Execute;
    FBypass := False;
  end;
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
    Exit;
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    mAction := mServices.ActionList.Actions[mIndex];
    if SameText(mAction.Name, ActionNames[AKind]) then
      Exit(mAction);
  end;
  // Ersatz: die Aktion mit dem üblichen Tastenkürzel.
  if AKind = TAtlasTraceKind.TraceInto then
    mShortCut := ShortCut(VK_F7, [])
  else
    mShortCut := ShortCut(VK_F7, [ssShift]);
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    mAction := mServices.ActionList.Actions[mIndex];
    if (mAction is TCustomAction) and (TCustomAction(mAction).ShortCut = mShortCut) then
      Exit(mAction);
  end;
end;

class procedure TAtlasIdeDebugTrace.Hook;
var
  mKind: TAtlasTraceKind;
  mAction: TContainedAction;
begin
  for mKind := Low(TAtlasTraceKind) to High(TAtlasTraceKind) do
  begin
    if FHooks[mKind] <> nil then
      Continue;
    mAction := FindAction(mKind);
    if mAction <> nil then
      FHooks[mKind] := THook.Create(mKind, mAction)
    else
      TAtlasGuard.Log(Format('Debugger: Aktion %s nicht gefunden; der Schritt bleibt unverändert',
        [ActionNames[mKind]]));
  end;
end;

class procedure TAtlasIdeDebugTrace.Unhook;
var
  mKind: TAtlasTraceKind;
begin
  for mKind := Low(TAtlasTraceKind) to High(TAtlasTraceKind) do
    FreeAndNil(FHooks[mKind]);
end;

class procedure TAtlasIdeDebugTrace.AddHandler(const AName: string; const AEvent: TAtlasTraceEvent);
var
  mIndex: Integer;
  mHandler: THandler;
begin
  for mIndex := 0 to High(FHandlers) do
    if SameText(FHandlers[mIndex].Name, AName) then
    begin
      FHandlers[mIndex].Event := AEvent;
      Exit;
    end;
  mHandler.Name := AName;
  mHandler.Event := AEvent;
  FHandlers := FHandlers + [mHandler];
  Hook;
end;

class procedure TAtlasIdeDebugTrace.RemoveHandler(const AName: string);
var
  mIndex: Integer;
begin
  for mIndex := High(FHandlers) downto 0 do
    if SameText(FHandlers[mIndex].Name, AName) then
    begin
      FHandlers[mIndex].Event := nil;
      Delete(FHandlers, mIndex, 1);
    end;
  if Length(FHandlers) = 0 then
    Unhook;
end;

class procedure TAtlasIdeDebugTrace.Notify(AKind: TAtlasTraceKind; AOrigin: TAtlasTraceOrigin);
var
  mHandlers: TArray<THandler>;
  mHandler: THandler;
begin
  // Kopie: Ein Empfänger darf sich dabei abmelden.
  mHandlers := Copy(FHandlers);
  for mHandler in mHandlers do
    if Assigned(mHandler.Event) then
      TAtlasGuard.Run(TAtlasFeature.Debugger,
        procedure
        begin
          mHandler.Event(AKind, AOrigin);
        end);
end;

class function TAtlasIdeDebugTrace.Hooked(AKind: TAtlasTraceKind): Boolean;
begin
  Result := FHooks[AKind] <> nil;
end;

class function TAtlasIdeDebugTrace.StepInto: Boolean;
begin
  Result := TAtlasIdeDebugSession.StoppedThread <> nil;
  if not Result then
    Exit;
  Notify(TAtlasTraceKind.TraceInto, TAtlasTraceOrigin.Atlas);
  Result := TAtlasIdeDebugSession.RunMode(ormStmtStepInto);
end;

class procedure TAtlasIdeDebugTrace.Release;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FHandlers) do
    FHandlers[mIndex].Event := nil;
  FHandlers := nil;
  Unhook;
end;

end.
