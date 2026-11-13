unit Atlas.IDE.Debug.BreakpointListMenu;

// Haltepunkte auf Methoden (#855): Einträge „Haltepunkt auf Methoden …“ und
// „Haltepunktgruppen der Methoden …“ im Kontextmenü der Haltepunktliste der IDE.
// Die Open Tools API bietet für die Haltepunktliste kein Kontextmenü an (nur
// für Projektverwaltung und Editor). Daher wie beim Ereignisprotokoll (#580):
// gesucht wird ein Formular, dessen Name oder Klasse „Breakpoint“ enthält
// (TAtlasMethodBreakpoints.IsBreakpointList), darin das Kontextmenü des
// Formulars oder des ersten Steuerelements mit einem. Die IDE legt das Fenster
// erst beim ersten Zeigen an; Attach wird deshalb beim Start, bei jeder
// Debug-Sitzung und bei jedem Befehl erneut gerufen und tut nichts, solange die
// Einträge hängen. Die Einträge gehören dieser Komponente: Release nimmt sie
// aus dem Menü, verschwindet das Menü vorher, vergisst sie es
// (FreeNotification). Was gefunden wurde, steht einmal im Diagnoseprotokoll.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Menus;

type
  TAtlasIdeBreakpointListMenu = class(TComponent)
  private
    FMenu: TPopupMenu;
    FItems: TArray<TMenuItem>;
    FActions: TArray<TProc>;
    FLogged: Boolean;
    function FindMenu(out ADetails: string): TPopupMenu;
    procedure ItemClick(Sender: TObject);
    procedure Follow(AMenu: TPopupMenu);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    /// <summary>ACaptions und AActions gleich lang: ein Eintrag je Befehl, davor ein Trennstrich.</summary>
    constructor CreateMenu(const ACaptions: TArray<string>; const AActions: TArray<TProc>);
    destructor Destroy; override;
    /// <summary>Einträge anhängen, wenn die Haltepunktliste ein Kontextmenü hat und sie noch nicht dran sind.
    /// </summary>
    procedure Attach;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Debug.MethodBreakpoints;

const
  cFormDetail = ' form %s (%s)';
  cMenuDetail = ' menu %s (%s)';

type
  TControlAccess = class(TControl);

/// <summary>Kontextmenü von AControl oder dem ersten Steuerelement darunter (Tiefensuche), das eins hat.</summary>
function MenuBelow(AControl: TControl): TPopupMenu;
var
  mIndex: Integer;
begin
  Result := TControlAccess(AControl).PopupMenu;
  if (Result <> nil) or not (AControl is TWinControl) then
  begin
    Exit;
  end;
  for mIndex := 0 to TWinControl(AControl).ControlCount - 1 do
  begin
    Result := MenuBelow(TWinControl(AControl).Controls[mIndex]);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
end;

constructor TAtlasIdeBreakpointListMenu.CreateMenu(const ACaptions: TArray<string>; const AActions: TArray<TProc>);
var
  mIndex: Integer;
begin
  inherited Create(nil);
  FActions := AActions;
  SetLength(FItems, Length(ACaptions) + 1);
  FItems[0] := TMenuItem.Create(Self);
  FItems[0].Caption := cLineCaption;
  for mIndex := 0 to High(ACaptions) do
  begin
    FItems[mIndex + 1] := TMenuItem.Create(Self);
    FItems[mIndex + 1].Caption := ACaptions[mIndex];
    FItems[mIndex + 1].Tag := mIndex;
    FItems[mIndex + 1].OnClick := ItemClick;
  end;
end;

destructor TAtlasIdeBreakpointListMenu.Destroy;
var
  mItem: TMenuItem;
begin
  // Aus dem fremden Menü nehmen, bevor die Einträge mit dieser Komponente verschwinden.
  for mItem in FItems do
  begin
    if (mItem <> nil) and (mItem.Parent <> nil) then
    begin
      mItem.Parent.Remove(mItem);
    end;
  end;
  Follow(nil);
  FActions := nil;
  inherited Destroy;
end;

procedure TAtlasIdeBreakpointListMenu.Follow(AMenu: TPopupMenu);
begin
  if FMenu <> nil then
  begin
    FMenu.RemoveFreeNotification(Self);
  end;
  FMenu := AMenu;
  if FMenu <> nil then
  begin
    FMenu.FreeNotification(Self);
  end;
end;

procedure TAtlasIdeBreakpointListMenu.Notification(AComponent: TComponent; Operation: TOperation);
var
  mIndex: Integer;
begin
  inherited Notification(AComponent, Operation);
  if Operation <> opRemove then
  begin
    Exit;
  end;
  if AComponent = FMenu then
  begin
    FMenu := nil;
  end;
  // Gibt das fremde Menü seine Einträge frei, sind auch unsere weg.
  for mIndex := 0 to High(FItems) do
  begin
    if FItems[mIndex] = AComponent then
    begin
      FItems[mIndex] := nil;
    end;
  end;
end;

function TAtlasIdeBreakpointListMenu.FindMenu(out ADetails: string): TPopupMenu;
var
  mIndex: Integer;
  mForm: TCustomForm;
  mDetails: TStringBuilder;
begin
  Result := nil;
  mDetails := TStringBuilder.Create;
  try
    for mIndex := 0 to Screen.CustomFormCount - 1 do
    begin
      mForm := Screen.CustomForms[mIndex];
      if not TAtlasMethodBreakpoints.IsBreakpointList(mForm.Name, mForm.ClassName) then
      begin
        Continue;
      end;
      Result := MenuBelow(mForm);
      mDetails.AppendFormat(cFormDetail, [mForm.Name, mForm.ClassName]);
      if Result <> nil then
      begin
        mDetails.AppendFormat(cMenuDetail, [Result.Name, Result.ClassName]);
        Break;
      end;
    end;
    ADetails := mDetails.ToString;
  finally
    mDetails.Free;
  end;
end;

procedure TAtlasIdeBreakpointListMenu.Attach;
var
  mMenu: TPopupMenu;
  mItem: TMenuItem;
  mDetails: string;
begin
  if (FMenu <> nil) and (FItems <> nil) and (FItems[0] <> nil) and (FItems[0].Parent <> nil) then
  begin
    Exit;
  end;
  mMenu := FindMenu(mDetails);
  if (mMenu = nil) or (FItems = nil) then
  begin
    Exit;
  end;
  for mItem in FItems do
  begin
    // Ein vom fremden Menü freigegebener Eintrag kommt nicht wieder; die übrigen hängen trotzdem.
    if (mItem <> nil) and (mItem.Parent = nil) then
    begin
      mMenu.Items.Add(mItem);
    end;
  end;
  Follow(mMenu);
  if not FLogged then
  begin
    FLogged := True;
    TAtlasGuard.Log('Breakpoint list menu (#855): attached to' + mDetails);
  end;
end;

procedure TAtlasIdeBreakpointListMenu.ItemClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := TMenuItem(Sender).Tag;
  if (mIndex >= 0) and (mIndex <= High(FActions)) and Assigned(FActions[mIndex]) then
  begin
    FActions[mIndex]();
  end;
end;

end.
