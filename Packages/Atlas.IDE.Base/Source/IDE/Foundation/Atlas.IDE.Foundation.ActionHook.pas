unit Atlas.IDE.Foundation.ActionHook;

// Haken an einer Aktion der IDE (Units, Unit verwenden, Formulare, Auswerten/Ändern, Einzelschritte): Der Haken
// setzt sich als OnExecute der Aktion, merkt sich das bisherige OnExecute und stellt es beim Freigeben wieder her.
// Gibt die IDE die Aktion vorher frei, vergisst er sie (FreeNotification). RunOriginal führt die Aktion aus wie ohne
// Atlas; hat sie kein eigenes OnExecute, erledigt die IDE sie über ihre Aktionsliste, dafür hängt sich der Haken
// für die Dauer des Aufrufs ab. Nachfahren entscheiden in Intercept, was beim Auslösen geschieht.
// Nur im Hauptthread.

interface

uses
  System.Classes,
  System.Actions;

type
  TAtlasIdeActionHook = class(TComponent)
  private
    FAction: TContainedAction;
    FOriginal: TNotifyEvent;
    FBypass: Boolean;
    procedure Execute(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    /// <summary>Die Aktion wurde ausgelöst (nie während RunOriginal und nie nach dem Freigeben der Aktion).
    /// </summary>
    procedure Intercept; virtual; abstract;
  public
    /// <summary>Hängt sich an AAction; AAction darf nicht nil sein.</summary>
    constructor Create(AAction: TContainedAction); reintroduce;
    destructor Destroy; override;
    /// <summary>Die Aktion wie ohne Atlas ausführen; ohne Aktion (von der IDE freigegeben) nichts.</summary>
    procedure RunOriginal;
    /// <summary>Die Aktion der IDE; nil, nachdem die IDE sie freigegeben hat.</summary>
    property Action: TContainedAction read FAction;
  end;

implementation

{ TAtlasIdeActionHook }

constructor TAtlasIdeActionHook.Create(AAction: TContainedAction);
begin
  inherited Create(nil);
  FAction := AAction;
  FOriginal := AAction.OnExecute;
  FAction.OnExecute := Execute;
  FAction.FreeNotification(Self);
end;

destructor TAtlasIdeActionHook.Destroy;
begin
  if FAction <> nil then
  begin
    FAction.RemoveFreeNotification(Self);
    FAction.OnExecute := FOriginal;
  end;
  inherited Destroy;
end;

procedure TAtlasIdeActionHook.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FAction) then
  begin
    FAction := nil;
  end;
end;

procedure TAtlasIdeActionHook.Execute(Sender: TObject);
begin
  if FBypass or (FAction = nil) then
  begin
    Exit;
  end;
  Intercept;
end;

procedure TAtlasIdeActionHook.RunOriginal;
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
