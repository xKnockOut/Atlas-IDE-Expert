unit Argus.IDE.Commands.Palette;

// Befehlspalette (#502) in der IDE: Strg+Umschalt+P öffnet sie über dem
// aktiven Fenster. Quellen: sichtbare, aktivierte Aktionen aus
// INTAServices.ActionList (Beschriftung, Menüpfad, Tastenkürzel) und die
// Argus-Befehle, die sich mit RegisterCommand anmelden. Der Verlauf liegt in
// %APPDATA%\Argus\palette.json.
// Abgrenzung zu IDE Insight (Strg+.): Das ist modal, durchsucht zusätzlich
// Optionen, Dateien und Komponenten, kennt aber keine Argus-Befehle und
// keinen Verlauf. Strg+Umschalt+P ist in der IDE „Tastenmakro abspielen“;
// die Palette übernimmt das Kürzel.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Menus,
  ToolsAPI,
  Argus.Core.Commands.Palette;

type
  TArgusIdePalette = class
  private type
    TBinding = class(TNotifierObject, IOTAKeyboardBinding)
    private
      FOwner: TArgusIdePalette;
      procedure Open(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
    public
      function GetBindingType: TBindingType;
      function GetDisplayName: string;
      function GetName: string;
      procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
    end;
  private
    FHistory: TArgusCommandHistory;
    FArgusCommands: TList<TPair<TArgusCommand, TProc>>;
    FBinding: TBinding;
    FBindingIndex: Integer;
    function HistoryFile: string;
    function Collect: TArray<TArgusCommand>;
    procedure Run(const ACommand: TArgusCommand);
    class function MenuPaths: TDictionary<TBasicAction, string>; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Argus-Befehl für die Palette (Beschriftung mit „Argus: “ davor).</summary>
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc);
    /// <summary>Palette über dem aktiven Fenster öffnen.</summary>
    procedure Show;
  end;

implementation

uses
  System.IOUtils,
  System.Types,
  System.Actions,
  Vcl.ActnList,
  Vcl.Forms,
  Argus.UI.Commands.Palette,
  Argus.IDE.Editor.Style;

{ TArgusIdePalette.TBinding }

function TArgusIdePalette.TBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TArgusIdePalette.TBinding.GetDisplayName: string;
begin
  Result := 'Argus-Befehlspalette';
end;

function TArgusIdePalette.TBinding.GetName: string;
begin
  Result := 'Argus.CommandPalette';
end;

procedure TArgusIdePalette.TBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  BindingServices.AddKeyBinding([ShortCut(Ord('P'), [ssCtrl, ssShift])], Open, nil);
end;

procedure TArgusIdePalette.TBinding.Open(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  if FOwner <> nil then
    try
      FOwner.Show;
    except
      // Keine Exception an die IDE (#493).
    end;
end;

{ TArgusIdePalette }

constructor TArgusIdePalette.Create;
var
  Keyboard: IOTAKeyboardServices;
begin
  inherited Create;
  FHistory := TArgusCommandHistory.Create;
  try
    FHistory.LoadFromFile(HistoryFile);
  except
    // Verlauf kaputt: leer anfangen.
  end;
  FArgusCommands := TList<TPair<TArgusCommand, TProc>>.Create;
  FBindingIndex := -1;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
  begin
    FBinding := TBinding.Create;
    FBinding.FOwner := Self;
    FBindingIndex := Keyboard.AddKeyboardBinding(FBinding);
  end;
end;

destructor TArgusIdePalette.Destroy;
var
  Keyboard: IOTAKeyboardServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if FBinding <> nil then
    FBinding.FOwner := nil;
  if (FBindingIndex >= 0) and Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
    Keyboard.RemoveKeyboardBinding(FBindingIndex);
  FArgusCommands.Free;
  FHistory.Free;
  inherited;
end;

function TArgusIdePalette.HistoryFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'Argus'), 'palette.json');
end;

procedure TArgusIdePalette.RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc);
var
  Command: TArgusCommand;
begin
  Command := Default(TArgusCommand);
  Command.Id := AId;
  Command.Caption := 'Argus: ' + ACaption;
  Command.Description := ADescription;
  Command.IsArgus := True;
  FArgusCommands.Add(TPair<TArgusCommand, TProc>.Create(Command, AProc));
end;

class function TArgusIdePalette.MenuPaths: TDictionary<TBasicAction, string>;
var
  Services: INTAServices;

  procedure Walk(AItem: TMenuItem; const APath: string);
  var
    Index: Integer;
    Child: TMenuItem;
    Caption: string;
  begin
    for Index := 0 to AItem.Count - 1 do
    begin
      Child := AItem.Items[Index];
      Caption := TArgusCommandPalette.CleanCaption(Child.Caption);
      if (Child.Action <> nil) and not Result.ContainsKey(Child.Action) then
        Result.Add(Child.Action, APath);
      if Child.Count > 0 then
        if APath = '' then
          Walk(Child, Caption)
        else
          Walk(Child, APath + ' › ' + Caption);
    end;
  end;

begin
  Result := TDictionary<TBasicAction, string>.Create;
  if Supports(BorlandIDEServices, INTAServices, Services) and (Services.MainMenu <> nil) then
    Walk(Services.MainMenu.Items, '');
end;

function TArgusIdePalette.Collect: TArray<TArgusCommand>;
var
  Services: INTAServices;
  Paths: TDictionary<TBasicAction, string>;
  Index: Integer;
  Action: TCustomAction;
  Command: TArgusCommand;
  Seen: TDictionary<string, Boolean>;
  Pair: TPair<TArgusCommand, TProc>;
begin
  Result := nil;
  for Pair in FArgusCommands do
    Result := Result + [Pair.Key];
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
    Exit;
  Paths := MenuPaths;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Index := 0 to Services.ActionList.ActionCount - 1 do
    begin
      if not (Services.ActionList.Actions[Index] is TCustomAction) then
        Continue;
      Action := TCustomAction(Services.ActionList.Actions[Index]);
      if (Action.Name = '') or not Action.Visible or not Action.Enabled or (Action.Caption = '') or
        Seen.ContainsKey(Action.Name) then
        Continue;
      Seen.Add(Action.Name, True);
      Command := Default(TArgusCommand);
      Command.Id := Action.Name;
      Command.Caption := TArgusCommandPalette.CleanCaption(Action.Caption);
      if not Paths.TryGetValue(Action, Command.Path) then
        Command.Path := Action.Category;
      if Action.ShortCut <> 0 then
        Command.ShortCut := ShortCutToText(Action.ShortCut);
      Command.Description := Action.Hint;
      Result := Result + [Command];
    end;
  finally
    Seen.Free;
    Paths.Free;
  end;
end;

procedure TArgusIdePalette.Run(const ACommand: TArgusCommand);
var
  Pair: TPair<TArgusCommand, TProc>;
  Services: INTAServices;
  Index: Integer;
  Action: TContainedAction;
begin
  FHistory.Executed(ACommand.Id);
  try
    FHistory.SaveToFile(HistoryFile);
  except
  end;
  if ACommand.IsArgus then
  begin
    for Pair in FArgusCommands do
      if Pair.Key.Id = ACommand.Id then
        Pair.Value();
    Exit;
  end;
  // Die Aktion neu suchen: Sie kann inzwischen freigegeben sein.
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
    Exit;
  for Index := 0 to Services.ActionList.ActionCount - 1 do
  begin
    Action := Services.ActionList.Actions[Index];
    if SameText(Action.Name, ACommand.Id) then
    begin
      Action.Update;
      if not (Action is TCustomAction) or TCustomAction(Action).Enabled then
        Action.Execute;
      Exit;
    end;
  end;
end;

procedure TArgusIdePalette.Show;
var
  Window: TArgusPaletteWindow;
  Area: TRect;
begin
  Window := TArgusPaletteWindow.CreatePalette(Application, Collect, FHistory, TArgusIdeStyle.Colors);
  Window.OnExecute :=
    procedure(ACommand: TArgusCommand)
    begin
      Run(ACommand);
    end;
  if Screen.ActiveForm <> nil then
    Area := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  Window.ShowOver(Area);
end;

end.