unit Atlas.IDE.Debug.RunMenu;

// Menü Start (RunMenu) der IDE für die Einträge des Debuggers: „Beim nächsten
// Ereignis anhalten“ (#856), „Anhalten bei Datenzugriff“ (#870) und „Erneut
// anhängen“ (#2171). Nur im Hauptthread.

interface

uses
  System.Classes,
  Vcl.Menus;

type
  TAtlasIdeRunMenu = class
  public
    /// <summary>Menü Start im Hauptmenü der IDE; nil ohne.</summary>
    class function Find: TMenuItem; static;
    /// <summary>Neuer Eintrag AName mit ACaption hinten im Menü Start; nil ohne Menü. Der Aufrufer gibt ihn frei.
    /// </summary>
    class function AddItem(const AName, ACaption: string; const AOnClick: TNotifyEvent): TMenuItem; static;
    /// <summary>AItem (nil: nichts) zeigen bzw. verbergen.</summary>
    class procedure ShowItem(AItem: TMenuItem; AVisible: Boolean); static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI;

const
  cRunMenuName = 'RunMenu';

{ TAtlasIdeRunMenu }

class function TAtlasIdeRunMenu.Find: TMenuItem;
var
  mServices: INTAServices;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.MainMenu = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.MainMenu.Items.Count - 1 do
  begin
    if SameText(mServices.MainMenu.Items[mIndex].Name, cRunMenuName) then
    begin
      Exit(mServices.MainMenu.Items[mIndex]);
    end;
  end;
end;

class function TAtlasIdeRunMenu.AddItem(const AName, ACaption: string; const AOnClick: TNotifyEvent): TMenuItem;
var
  mParent: TMenuItem;
begin
  Result := nil;
  mParent := Find;
  if mParent = nil then
  begin
    Exit;
  end;
  Result := TMenuItem.Create(nil);
  Result.Name := AName;
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
  mParent.Add(Result);
end;

class procedure TAtlasIdeRunMenu.ShowItem(AItem: TMenuItem; AVisible: Boolean);
begin
  if Assigned(AItem) then
  begin
    AItem.Visible := AVisible;
  end;
end;

end.
