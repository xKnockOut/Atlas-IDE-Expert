unit Atlas.IDE.Commands.Palette;

// Befehlspalette (#502) in der IDE: Strg+Umschalt+P öffnet sie über dem
// aktiven Fenster. Quellen: sichtbare, aktivierte Aktionen aus
// INTAServices.ActionList (Beschriftung, Menüpfad, Tastenkürzel) und die
// Atlas-Befehle, die sich mit RegisterCommand anmelden. Der Verlauf liegt in
// %APPDATA%\Atlas\palette.json.
// Abgrenzung zu IDE Insight (Strg+.): Das ist modal, durchsucht zusätzlich
// Optionen, Dateien und Komponenten, kennt aber keine Atlas-Befehle und
// keinen Verlauf. Strg+Umschalt+P ist in der IDE „Tastenmakro abspielen“;
// die Palette übernimmt das Kürzel.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Commands.Palette;

type
  TAtlasIdePalette = class
  private type
    TBinding = class(TNotifierObject, IOTAKeyboardBinding)
    private
      FOwner: TAtlasIdePalette;
      procedure Open(const Context: IOTAKeyContext; KeyCode: TShortCut; var BindingResult: TKeyBindingResult);
    public
      function GetBindingType: TBindingType;
      function GetDisplayName: string;
      function GetName: string;
      procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
    end;
  private
    FHistory: TAtlasCommandHistory;
    FAtlasCommands: TList<TPair<TAtlasCommand, TProc>>;
    FBinding: TBinding;
    // Hält das Binding am Leben: Abmelden gibt die Referenz der IDE frei, Rebind meldet es neu an.
    FBindingRef: IOTAKeyboardBinding;
    FBindingIndex: Integer;
    FKey: Word;
    function HistoryFile: string;
    function Collect: TArray<TAtlasCommand>;
    procedure Run(const ACommand: TAtlasCommand);
    class function MenuPaths: TDictionary<TBasicAction, string>; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Atlas-Befehl für die Palette (Beschriftung mit „Atlas: “ davor).</summary>
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc);
    /// <summary>Nur die Atlas-Befehle (Suchfeld der Willkommensseite, #760).</summary>
    function AtlasCommands: TArray<TAtlasCommand>;
    /// <summary>Atlas-Befehl AId ausführen wie aus der Palette (mit Verlauf).</summary>
    procedure Execute(const AId: string);
    /// <summary>Palette über dem aktiven Fenster öffnen.</summary>
    procedure Show;
    /// <summary>Tastenkürzel nach den Einstellungen (neu) belegen; bei Konflikt ohne Vorrang keins (#494).</summary>
    procedure Rebind;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  System.IOUtils,
  System.Types,
  System.Actions,
  Vcl.ActnList,
  Vcl.Forms,
  Atlas.UI.Commands.Palette,
  Atlas.UI.Strings,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Settings.Store,
  Atlas.IDE.Commands.Keys;

{ TAtlasIdePalette.TBinding }

function TAtlasIdePalette.TBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TAtlasIdePalette.TBinding.GetDisplayName: string;
begin
  Result := 'Atlas-Befehlspalette';
end;

function TAtlasIdePalette.TBinding.GetName: string;
begin
  Result := 'Atlas.CommandPalette';
end;

procedure TAtlasIdePalette.TBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  if (FOwner <> nil) and (FOwner.FKey <> 0) then
    BindingServices.AddKeyBinding([FOwner.FKey], Open, nil);
end;

procedure TAtlasIdePalette.TBinding.Open(const Context: IOTAKeyContext; KeyCode: TShortCut;
  var BindingResult: TKeyBindingResult);
begin
  BindingResult := krHandled;
  if FOwner <> nil then
    try
      FOwner.Show;
    except
      // Keine Exception an die IDE (#493).
      on E: Exception do
        TAtlasGuard.Report(TAtlasFeature.Palette, E);
    end;
end;

{ TAtlasIdePalette }

constructor TAtlasIdePalette.Create;
var
  Keyboard: IOTAKeyboardServices;
begin
  inherited Create;
  FHistory := TAtlasCommandHistory.Create;
  try
    FHistory.LoadFromFile(HistoryFile);
  except
    // Verlauf kaputt: leer anfangen.
  end;
  FAtlasCommands := TList<TPair<TAtlasCommand, TProc>>.Create;
  FBindingIndex := -1;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
  begin
    FBinding := TBinding.Create;
    FBindingRef := FBinding;
    FBinding.FOwner := Self;
    Rebind;
  end;
end;

procedure TAtlasIdePalette.Rebind;
var
  Key: Word;
begin
  if FBinding = nil then
    Exit;
  Key := Word(TAtlasIdeSettings.Current.PaletteKey);
  if not TAtlasIdeKeys.Decide(Key, TAtlasIdeSettings.Current.PaletteKeyPriority,
    TAtlasStrings.Text(TAtlasTextId.SettingsPaletteKey)) then
    Key := 0;
  if (Key = FKey) and ((FBindingIndex >= 0) = (Key <> 0)) then
    Exit;
  FKey := Key;
  if FKey = 0 then
    TAtlasIdeKeys.Unbind(FBindingIndex)
  else
    TAtlasIdeKeys.Bind(FBinding, FBindingIndex);
end;

destructor TAtlasIdePalette.Destroy;
var
  Keyboard: IOTAKeyboardServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if FBinding <> nil then
    FBinding.FOwner := nil;
  if (FBindingIndex >= 0) and Supports(BorlandIDEServices, IOTAKeyboardServices, Keyboard) then
    Keyboard.RemoveKeyboardBinding(FBindingIndex);
  FAtlasCommands.Free;
  FHistory.Free;
  inherited;
end;

function TAtlasIdePalette.HistoryFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'Atlas'), 'palette.json');
end;

procedure TAtlasIdePalette.RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc);
var
  Command: TAtlasCommand;
begin
  Command := Default(TAtlasCommand);
  Command.Id := AId;
  Command.Caption := 'Atlas: ' + ACaption;
  Command.Description := ADescription;
  Command.IsAtlas := True;
  FAtlasCommands.Add(TPair<TAtlasCommand, TProc>.Create(Command, AProc));
end;

class function TAtlasIdePalette.MenuPaths: TDictionary<TBasicAction, string>;
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
      Caption := TAtlasCommandPalette.CleanCaption(Child.Caption);
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

function TAtlasIdePalette.Collect: TArray<TAtlasCommand>;
var
  Services: INTAServices;
  Paths: TDictionary<TBasicAction, string>;
  Index: Integer;
  Action: TCustomAction;
  Command: TAtlasCommand;
  Seen: TDictionary<string, Boolean>;
  Pair: TPair<TAtlasCommand, TProc>;
begin
  Result := nil;
  for Pair in FAtlasCommands do
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
      Command := Default(TAtlasCommand);
      Command.Id := Action.Name;
      Command.Caption := TAtlasCommandPalette.CleanCaption(Action.Caption);
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

function TAtlasIdePalette.AtlasCommands: TArray<TAtlasCommand>;
var
  Pair: TPair<TAtlasCommand, TProc>;
begin
  Result := nil;
  for Pair in FAtlasCommands do
    Result := Result + [Pair.Key];
end;

procedure TAtlasIdePalette.Execute(const AId: string);
var
  Pair: TPair<TAtlasCommand, TProc>;
begin
  for Pair in FAtlasCommands do
    if Pair.Key.Id = AId then
    begin
      Run(Pair.Key);
      Exit;
    end;
end;

procedure TAtlasIdePalette.Run(const ACommand: TAtlasCommand);
var
  Pair: TPair<TAtlasCommand, TProc>;
  Services: INTAServices;
  Index: Integer;
  Action: TContainedAction;
begin
  FHistory.Executed(ACommand.Id);
  try
    FHistory.SaveToFile(HistoryFile);
  except
  end;
  if ACommand.IsAtlas then
  begin
    for Pair in FAtlasCommands do
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

procedure TAtlasIdePalette.Show;
var
  Window: TAtlasPaletteWindow;
  Area: TRect;
begin
  Window := TAtlasPaletteWindow.CreatePalette(Application, Collect, FHistory, TAtlasIdeStyle.Colors);
  Window.OnExecute :=
    procedure(ACommand: TAtlasCommand)
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