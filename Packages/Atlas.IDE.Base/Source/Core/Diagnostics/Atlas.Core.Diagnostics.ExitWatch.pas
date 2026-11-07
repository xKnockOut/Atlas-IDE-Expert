unit Atlas.Core.Diagnostics.ExitWatch;

// Meldet, wenn eine Komponente zerstört wird. Base hängt sich so an das Hauptfenster der IDE: Mit installierten
// Modulen ruft die IDE die finalization von Base beim Beenden nicht mehr auf; ohne diesen Schritt fehlte der ganze
// Abbau, und der nächste Start meldete einen Absturz.

interface

uses
  System.SysUtils,
  System.Classes;

type
  TAtlasExitWatch = class(TComponent)
  private
    FTarget: TComponent;
    FOnExit: TProc;
  protected
    procedure Notification(AComponent: TComponent; AOperation: TOperation); override;
  public
    /// <summary>AOnExit läuft einmal, während ATarget zerstört wird. Wird die Wache vorher freigegeben, nicht
    /// mehr.</summary>
    constructor Create(ATarget: TComponent; const AOnExit: TProc); reintroduce;
  end;

implementation

constructor TAtlasExitWatch.Create(ATarget: TComponent; const AOnExit: TProc);
begin
  inherited Create(nil);
  FTarget := ATarget;
  FOnExit := AOnExit;
  FTarget.FreeNotification(Self);
end;

procedure TAtlasExitWatch.Notification(AComponent: TComponent; AOperation: TOperation);
var
  mOnExit: TProc;
begin
  inherited;
  if (AOperation = opRemove) and (AComponent = FTarget) then
  begin
    FTarget := nil;
    mOnExit := FOnExit;
    FOnExit := nil;
    if Assigned(mOnExit) then
    begin
      mOnExit();
    end;
  end;
end;

end.
