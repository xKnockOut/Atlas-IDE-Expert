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
// Tastenkürzel-Übersicht (#520): Atlas-Befehle zeigen ihre Taste (ShortCutOf),
// ein Befehl mit Sichtbarkeit (RegisterCommand mit AVisible) erscheint nur,
// solange seine Einstellung an ist.
// Tastenkürzel-Tipps (#600): Run meldet jeden Befehl als Aufruf ohne Kürzel
// (TAtlasIdeShortcutTips.Invoked), auch Aktionen der IDE.
// Zusatzquelle (#1270): SourceOf liefert beim Öffnen die Quelle (Issues im
// Tracker); sie erfährt jede Eingabe und zeigt ihre Treffer als Gruppe unter
// den Befehlen.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Commands.Palette,
  Atlas.UI.Commands.Palette;

type
  /// <summary>Ohne Referenzzählung (TNoRefCountObject): Die Composition gibt die Palette frei.</summary>
  TAtlasIdePalette = class(TNoRefCountObject, IAtlasCommandRegistry)
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
    // Befehle mit Sichtbarkeit nach einer Einstellung (#520); ohne Eintrag immer sichtbar.
    FVisible: TDictionary<string, TFunc<Boolean>>;
    FShortCutOf: TFunc<string, string>;
    FSourceOf: TFunc<IAtlasPaletteSource>;
    FBinding: TBinding;
    // Hält das Binding am Leben: Abmelden gibt die Referenz der IDE frei, Rebind meldet es neu an.
    FBindingRef: IOTAKeyboardBinding;
    FBindingIndex: Integer;
    FKey: Word;
    function HistoryFile: string;
    function Collect: TArray<TAtlasCommand>;
    procedure Run(const ACommand: TAtlasCommand);
    class function MenuPaths: TDictionary<TBasicAction, string>; static;
    function IsVisible(const AId: string): Boolean;
    /// <summary>Atlas-Befehl mit seiner Taste aus ShortCutOf.</summary>
    function WithShortCut(const ACommand: TAtlasCommand): TAtlasCommand;
    /// <summary>Zusatzquelle an das Fenster hängen (#1270); eigene Routine, damit die anonymen Methoden nur
    /// Fenster und Quelle halten.</summary>
    class procedure Attach(AWindow: TAtlasPaletteWindow; const ASource: IAtlasPaletteSource); static;
    class function GroupShower(AWindow: TAtlasPaletteWindow): TProc<TAtlasPaletteGroup>; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Atlas-Befehl für die Palette (Beschriftung mit „Atlas: “ davor).</summary>
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc); overload;
    /// <summary>Wie oben; der Befehl erscheint nur, solange AVisible True liefert (#520).</summary>
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc;
      const AVisible: TFunc<Boolean>); overload;
    /// <summary>Nur die Atlas-Befehle (Suchfeld der Willkommensseite, #760).</summary>
    function AtlasCommands: TArray<TAtlasCommand>;
    /// <summary>Atlas-Befehl AId ausführen wie aus der Palette (mit Verlauf).</summary>
    procedure Execute(const AId: string);
    /// <summary>Palette über dem aktiven Fenster öffnen.</summary>
    procedure Show;
    /// <summary>Tastenkürzel nach den Einstellungen (neu) belegen; bei Konflikt ohne Vorrang keins (#494).</summary>
    procedure Rebind;
    /// <summary>Taste eines Atlas-Befehls als Text ('' ohne), gesetzt von der Komposition (#520).</summary>
    property ShortCutOf: TFunc<string, string> read FShortCutOf write FShortCutOf;
    /// <summary>Zusatzquelle beim Öffnen (Issues, #1270); nil bzw. Ergebnis nil = nur Befehle.</summary>
    property SourceOf: TFunc<IAtlasPaletteSource> read FSourceOf write FSourceOf;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  System.IOUtils,
  System.Types,
  System.Actions,
  Vcl.ActnList,
  Vcl.Forms,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Keys,
  Atlas.IDE.Commands.ShortcutTips;

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
  // Fehlt, unbrauchbar oder gesperrt: leer anfangen; TAtlasDataFile legt Unbrauchbares beiseite und
  // protokolliert, eine gesperrte Datei schreibt SaveToFile nicht (Bericht N3).
  FHistory.LoadFromFile(HistoryFile);
  FAtlasCommands := TList<TPair<TAtlasCommand, TProc>>.Create;
  FVisible := TDictionary<string, TFunc<Boolean>>.Create;
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
  FVisible.Free;
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

procedure TAtlasIdePalette.RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc;
  const AVisible: TFunc<Boolean>);
begin
  RegisterCommand(AId, ACaption, ADescription, AProc);
  if Assigned(AVisible) then
    FVisible.AddOrSetValue(AId, AVisible);
end;

function TAtlasIdePalette.IsVisible(const AId: string): Boolean;
var
  Visible: TFunc<Boolean>;
begin
  Result := not FVisible.TryGetValue(AId, Visible) or Visible();
end;

function TAtlasIdePalette.WithShortCut(const ACommand: TAtlasCommand): TAtlasCommand;
begin
  Result := ACommand;
  if (Result.ShortCut = '') and Assigned(FShortCutOf) then
    Result.ShortCut := FShortCutOf(Result.Id);
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
    if IsVisible(Pair.Key.Id) then
      Result := Result + [WithShortCut(Pair.Key)];
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
    if IsVisible(Pair.Key.Id) then
      Result := Result + [WithShortCut(Pair.Key)];
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
    // Der Befehl läuft trotzdem; der Grund steht einmal im Protokoll.
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Verlauf der Befehlspalette', E);
  end;
  // Vor dem Ausführen: Die Aktion der IDE zählt dann nicht noch einmal über OnActionExecute.
  TAtlasIdeShortcutTips.Invoked(ACommand.Id);
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

class function TAtlasIdePalette.GroupShower(AWindow: TAtlasPaletteWindow): TProc<TAtlasPaletteGroup>;
begin
  // Die Quelle ruft das nur bis Closed; das Fenster meldet Closed vor dem Freigeben.
  Result :=
    procedure(AGroup: TAtlasPaletteGroup)
    begin
      AWindow.SetGroup(AGroup);
    end;
end;

class procedure TAtlasIdePalette.Attach(AWindow: TAtlasPaletteWindow; const ASource: IAtlasPaletteSource);
begin
  AWindow.OnPattern :=
    procedure(APattern: string)
    begin
      ASource.Changed(APattern);
    end;
  AWindow.OnGroupExecute :=
    procedure(AItem: TAtlasCommand; AAction: TAtlasPaletteAction)
    begin
      ASource.Execute(AItem, AAction);
    end;
  AWindow.OnClosed :=
    procedure
    begin
      ASource.Closed;
    end;
  ASource.Opened(GroupShower(AWindow));
end;

procedure TAtlasIdePalette.Show;
var
  Window: TAtlasPaletteWindow;
  Area: TRect;
  mSource: IAtlasPaletteSource;
begin
  Window := TAtlasPaletteWindow.CreatePalette(Application, Collect, FHistory, TAtlasIdeStyle.Colors);
  Window.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    begin
      Run(ACommand);
    end;
  mSource := nil;
  if Assigned(FSourceOf) then
    mSource := FSourceOf();
  if mSource <> nil then
    Attach(Window, mSource);
  if Screen.ActiveForm <> nil then
    Area := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  Window.ShowOver(Area);
end;

end.