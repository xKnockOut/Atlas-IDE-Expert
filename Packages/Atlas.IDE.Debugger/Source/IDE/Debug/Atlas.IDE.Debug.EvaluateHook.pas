unit Atlas.IDE.Debug.EvaluateHook;

// Strg+F7 an das Fenster „Auswerten“ (#784, debug.evaluateWindow.replaceCtrlF7):
//   - Atlas hängt sich in die Aktion „Auswerten/Ändern“ der IDE
//     (EvaluateActionNames, sonst die Aktion mit Strg+F7). Entscheidet
//     AIntercepts beim Ausführen True und ist die Umschalttaste nicht
//     gedrückt (Strg+Umschalt+F7 oder Umschalt+Klick im Menü), ruft Atlas
//     AShow, sonst die Aktion wie ohne Atlas.
//   - RunOriginal bzw. OpenIdeDialog öffnet den Dialog der IDE (Befehl
//     Atlas.DebugEvaluateIdeDialog).
//   - Wird die Aktion freigegeben, löst sich der Haken (FreeNotification).
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Actions;

type
  /// <summary>Hängt an der IDE-Aktion „Auswerten/Ändern“ (wie TTraceHook in Atlas.IDE.Debug.OwnCode).</summary>
  TAtlasIdeEvaluateHook = class(TComponent)
  private
    FAction: TContainedAction;
    FOriginal: TNotifyEvent;
    FBypass: Boolean;
    FIntercepts: TFunc<Boolean>;
    FShow: TProc;
    procedure Execute(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AAction: TContainedAction; const AIntercepts: TFunc<Boolean>; const AShow: TProc);
      reintroduce;
    destructor Destroy; override;
    /// <summary>Haken an die Aktion der IDE; nil, wenn sie fehlt (protokolliert).</summary>
    class function Install(const AIntercepts: TFunc<Boolean>; const AShow: TProc): TAtlasIdeEvaluateHook; static;
    /// <summary>Die Aktion „Auswerten/Ändern“ der IDE; nil ohne.</summary>
    class function FindEvaluateAction: TContainedAction; static;
    /// <summary>Die Aktion der IDE wie ohne Atlas ausführen.</summary>
    procedure RunOriginal;
    /// <summary>Dialog der IDE über AHook, ohne Haken (nil) über die Aktion direkt.</summary>
    class procedure OpenIdeDialog(AHook: TAtlasIdeEvaluateHook); static;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.ActnList,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard;

const
  // Name der IDE-Aktion „Auswerten/Ändern“ je Delphi-Version; ungeprüft, siehe Handtest AW15.
  EvaluateActionNames: array[0..2] of string = ('RunEvaluateModifyCommand', 'RunEvaluateCommand',
    'DebugEvaluateCommand');

/// <summary>Erste Aktion in AServices, für die AMatch zutrifft; nil ohne.</summary>
function FirstAction(const AServices: INTAServices; const AMatch: TFunc<TContainedAction, Boolean>):
  TContainedAction;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := 0;
  while (Result = nil) and (mIndex < AServices.ActionList.ActionCount) do
  begin
    if AMatch(AServices.ActionList.Actions[mIndex]) then
    begin
      Result := AServices.ActionList.Actions[mIndex];
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Bedingung: Aktion heißt AName.</summary>
function NamedAs(const AName: string): TFunc<TContainedAction, Boolean>;
begin
  Result :=
    function(AAction: TContainedAction): Boolean
    begin
      Result := SameText(AAction.Name, AName);
    end;
end;

/// <summary>Bedingung: Aktion mit Strg+F7.</summary>
function WithCtrlF7: TFunc<TContainedAction, Boolean>;
begin
  Result :=
    function(AAction: TContainedAction): Boolean
    begin
      Result := (AAction is TCustomAction) and (TCustomAction(AAction).ShortCut = ShortCut(VK_F7, [ssCtrl]));
    end;
end;

{ TAtlasIdeEvaluateHook }

constructor TAtlasIdeEvaluateHook.Create(AAction: TContainedAction; const AIntercepts: TFunc<Boolean>;
  const AShow: TProc);
begin
  inherited Create(nil);
  FIntercepts := AIntercepts;
  FShow := AShow;
  FAction := AAction;
  FOriginal := AAction.OnExecute;
  FAction.OnExecute := Execute;
  FAction.FreeNotification(Self);
end;

destructor TAtlasIdeEvaluateHook.Destroy;
begin
  if FAction <> nil then
  begin
    FAction.RemoveFreeNotification(Self);
    FAction.OnExecute := FOriginal;
  end;
  FIntercepts := nil;
  FShow := nil;
  inherited Destroy;
end;

class function TAtlasIdeEvaluateHook.FindEvaluateAction: TContainedAction;
var
  mServices: INTAServices;
  mName: string;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  for mName in EvaluateActionNames do
  begin
    if Result = nil then
    begin
      Result := FirstAction(mServices, NamedAs(mName));
    end;
  end;
  // Ersatz: die Aktion mit Strg+F7.
  if Result = nil then
  begin
    Result := FirstAction(mServices, WithCtrlF7());
  end;
end;

class function TAtlasIdeEvaluateHook.Install(const AIntercepts: TFunc<Boolean>;
  const AShow: TProc): TAtlasIdeEvaluateHook;
var
  mAction: TContainedAction;
begin
  Result := nil;
  mAction := FindEvaluateAction;
  if mAction = nil then
  begin
    TAtlasGuard.Log('Auswerten: Aktion „Auswerten/Ändern“ der IDE nicht gefunden; Strg+F7 bleibt unverändert');
    Exit;
  end;
  TAtlasGuard.Log('Auswerten: Strg+F7 über die IDE-Aktion ' + mAction.Name);
  Result := TAtlasIdeEvaluateHook.Create(mAction, AIntercepts, AShow);
end;

procedure TAtlasIdeEvaluateHook.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FAction) then
  begin
    FAction := nil;
  end;
end;

procedure TAtlasIdeEvaluateHook.Execute(Sender: TObject);
begin
  if FBypass or (FAction = nil) then
  begin
    Exit;
  end;
  if Assigned(FIntercepts) and FIntercepts() and (GetKeyState(VK_SHIFT) >= 0) then
  begin
    TAtlasGuard.Run(TAtlasFeature.Debugger, FShow);
    Exit;
  end;
  RunOriginal;
end;

class procedure TAtlasIdeEvaluateHook.OpenIdeDialog(AHook: TAtlasIdeEvaluateHook);
var
  mAction: TContainedAction;
begin
  if AHook <> nil then
  begin
    AHook.RunOriginal;
    Exit;
  end;
  mAction := FindEvaluateAction;
  if mAction <> nil then
  begin
    mAction.Execute;
  end;
end;

procedure TAtlasIdeEvaluateHook.RunOriginal;
begin
  if FAction = nil then
  begin
    Exit;
  end;
  if Assigned(FOriginal) then
  begin
    FOriginal(FAction);
    Exit;
  end;
  // Ohne eigenes OnExecute erledigt die IDE die Aktion über ihre Liste: kurz abhängen und ausführen.
  FBypass := True;
  FAction.OnExecute := nil;
  try
    FAction.Execute;
  finally
    if FAction <> nil then
    begin
      FAction.OnExecute := Execute;
    end;
    FBypass := False;
  end;
end;

end.
