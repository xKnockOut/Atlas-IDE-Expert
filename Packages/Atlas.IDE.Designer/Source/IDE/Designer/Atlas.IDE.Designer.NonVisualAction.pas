unit Atlas.IDE.Designer.NonVisualAction;

// Aktion der IDE hinter Strg+H im Formular-Designer (nicht sichtbare Komponenten ein- und ausblenden) für den Knopf
// der Designer-Leiste (Atlas.IDE.Designer.Bar): finden, Zustand lesen, auslösen. Die Aktionsliste der IDE hat
// Tausende Einträge, der Takt der Leiste fragt fünfmal je Sekunde; der Index der Aktion wird deshalb gemerkt.
// Nur im Hauptthread.

interface

uses
  System.Actions;

type
  TAtlasIdeNonVisualAction = class
  private const
    cName = 'ToggleNonVisualComponentVisibilityCommand';
  private
    FIndex: Integer;
    FLogged: Boolean;
    function Find: TContainedAction;
  public
    constructor Create;
    /// <summary>False, wenn die IDE die Aktion nicht hat. Sonst nach Update der Aktion AEnabled und APressed
    /// (eingeschaltet = nicht sichtbare Komponenten ausgeblendet); bei einer Aktion ohne diese Angaben bleiben
    /// beide unverändert.</summary>
    function State(var AEnabled, APressed: Boolean): Boolean;
    /// <summary>Löst die Aktion aus, wenn sie eingeschaltet ist; False, wenn die IDE sie nicht hat.</summary>
    function Toggle: Boolean;
  end;

implementation

uses
  System.SysUtils,
  Vcl.ActnList,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard;

{ TAtlasIdeNonVisualAction }

constructor TAtlasIdeNonVisualAction.Create;
begin
  inherited Create;
  FIndex := -1;
end;

function TAtlasIdeNonVisualAction.Find: TContainedAction;
var
  mServices: INTAServices;
  mList: TCustomActionList;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  mList := mServices.ActionList;
  if (FIndex >= 0) and (FIndex < mList.ActionCount) and SameText(mList.Actions[FIndex].Name, cName) then
  begin
    Exit(mList.Actions[FIndex]);
  end;
  FIndex := -1;
  for mIndex := 0 to mList.ActionCount - 1 do
  begin
    if SameText(mList.Actions[mIndex].Name, cName) then
    begin
      FIndex := mIndex;
      Exit(mList.Actions[mIndex]);
    end;
  end;
  if not FLogged then
  begin
    FLogged := True;
    TAtlasGuard.Log('Designer-Leiste: IDE-Aktion ' + cName + ' nicht gefunden');
  end;
end;

function TAtlasIdeNonVisualAction.State(var AEnabled, APressed: Boolean): Boolean;
var
  mAction: TContainedAction;
begin
  mAction := Find;
  Result := mAction <> nil;
  if not Result then
  begin
    Exit;
  end;
  mAction.Update;
  if mAction is TCustomAction then
  begin
    AEnabled := TCustomAction(mAction).Enabled;
    APressed := TCustomAction(mAction).Checked;
  end;
end;

function TAtlasIdeNonVisualAction.Toggle: Boolean;
var
  mAction: TContainedAction;
begin
  mAction := Find;
  Result := mAction <> nil;
  if not Result then
  begin
    Exit;
  end;
  mAction.Update;
  if (mAction is TCustomAction) and not TCustomAction(mAction).Enabled then
  begin
    Exit;
  end;
  mAction.Execute;
end;

end.
