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
    FShortCutsOf: TFunc<TFunc<string, string>>;
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
    /// <summary>Sichtbare Befehle der angemeldeten Module (#1455, IAtlasCommandSource), bei jedem Aufruf neu
    /// gefragt: Sie kommen und gehen mit ihrem Modul.</summary>
    function ModuleCommands(const AShortCuts: TFunc<string, string>): TArray<TAtlasCommand>;
    /// <summary>Befehl AId eines Moduls ausführen; False, wenn ihn keins anbietet.</summary>
    function RunModuleCommand(const AId: string): Boolean;
    /// <summary>Tasten aller Atlas-Befehle, einmal je Aufruf ausgewertet (ShortCutsOf); nil ohne.</summary>
    function ShortCuts: TFunc<string, string>;
    /// <summary>Atlas-Befehl mit seiner Taste aus AShortCuts (nil: ohne Taste).</summary>
    class function WithShortCut(const ACommand: TAtlasCommand; const AShortCuts: TFunc<string, string>): TAtlasCommand;
      static;
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
    /// <summary>Liefert das Nachschlagen „Taste eines Atlas-Befehls als Text ('' ohne)“, gesetzt von der
    /// Komposition (#520); einmal je Liste gefragt.</summary>
    property ShortCutsOf: TFunc<TFunc<string, string>> read FShortCutsOf write FShortCutsOf;
    /// <summary>Zusatzquelle beim Öffnen (Issues, #1270); nil bzw. Ergebnis nil = nur Befehle.</summary>
    property SourceOf: TFunc<IAtlasPaletteSource> read FSourceOf write FSourceOf;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
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
  begin
    BindingServices.AddKeyBinding([FOwner.FKey], Open, nil);
  end;
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
  mKeyboard: IOTAKeyboardServices;
begin
  inherited Create;
  FHistory := TAtlasCommandHistory.Create;
  // Fehlt, unbrauchbar oder gesperrt: leer anfangen; TAtlasDataFile legt Unbrauchbares beiseite und
  // protokolliert, eine gesperrte Datei schreibt SaveToFile nicht (Bericht N3).
  FHistory.LoadFromFile(HistoryFile);
  FAtlasCommands := TList<TPair<TAtlasCommand, TProc>>.Create;
  FVisible := TDictionary<string, TFunc<Boolean>>.Create;
  FBindingIndex := -1;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, mKeyboard) then
  begin
    FBinding := TBinding.Create;
    FBindingRef := FBinding;
    FBinding.FOwner := Self;
    Rebind;
  end;
end;

procedure TAtlasIdePalette.Rebind;
var
  mKey: Word;
begin
  if FBinding = nil then
  begin
    Exit;
  end;
  mKey := Word(TAtlasIdeSettings.Current.PaletteKey);
  if not TAtlasIdeKeys.Decide(mKey, TAtlasIdeSettings.Current.PaletteKeyPriority,
    TAtlasStrings.Text(TAtlasTextId.SettingsPaletteKey)) then
  begin
    mKey := 0;
  end;
  if (mKey = FKey) and ((FBindingIndex >= 0) = (mKey <> 0)) then
  begin
    Exit;
  end;
  FKey := mKey;
  if FKey = 0 then
  begin
    TAtlasIdeKeys.Unbind(FBindingIndex);
  end
  else
  begin
    TAtlasIdeKeys.Bind(FBinding, FBindingIndex);
  end;
end;

destructor TAtlasIdePalette.Destroy;
var
  mKeyboard: IOTAKeyboardServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if FBinding <> nil then
  begin
    FBinding.FOwner := nil;
  end;
  if (FBindingIndex >= 0) and Supports(BorlandIDEServices, IOTAKeyboardServices, mKeyboard) then
  begin
    mKeyboard.RemoveKeyboardBinding(FBindingIndex);
  end;
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
  mCommand: TAtlasCommand;
begin
  mCommand := Default(TAtlasCommand);
  mCommand.Id := AId;
  mCommand.Caption := 'Atlas: ' + ACaption;
  mCommand.Description := ADescription;
  mCommand.IsAtlas := True;
  FAtlasCommands.Add(TPair<TAtlasCommand, TProc>.Create(mCommand, AProc));
end;

procedure TAtlasIdePalette.RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc;
  const AVisible: TFunc<Boolean>);
begin
  RegisterCommand(AId, ACaption, ADescription, AProc);
  if Assigned(AVisible) then
  begin
    FVisible.AddOrSetValue(AId, AVisible);
  end;
end;

function TAtlasIdePalette.IsVisible(const AId: string): Boolean;
var
  mVisible: TFunc<Boolean>;
begin
  Result := not FVisible.TryGetValue(AId, mVisible) or mVisible();
end;

function TAtlasIdePalette.ModuleCommands(const AShortCuts: TFunc<string, string>): TArray<TAtlasCommand>;
var
  mModuleCommand: TAtlasModuleCommand;
  mCommand: TAtlasCommand;
begin
  Result := nil;
  for mModuleCommand in TAtlasModuleContributions.Commands(AtlasModuleRegistry) do
  begin
    if TAtlasModuleContributions.IsVisible(mModuleCommand) then
    begin
      mCommand := Default(TAtlasCommand);
      mCommand.Id := mModuleCommand.Id;
      mCommand.Caption := 'Atlas: ' + mModuleCommand.Caption;
      mCommand.Description := mModuleCommand.Description;
      mCommand.IsAtlas := True;
      Result := Result + [WithShortCut(mCommand, AShortCuts)];
    end;
  end;
end;

function TAtlasIdePalette.RunModuleCommand(const AId: string): Boolean;
var
  mCommand: TAtlasModuleCommand;
begin
  Result := TAtlasModuleContributions.FindCommand(AtlasModuleRegistry, AId, mCommand) and Assigned(mCommand.Run);
  if Result then
  begin
    mCommand.Run();
  end;
end;

function TAtlasIdePalette.ShortCuts: TFunc<string, string>;
begin
  Result := nil;
  if Assigned(FShortCutsOf) then
  begin
    Result := FShortCutsOf();
  end;
end;

class function TAtlasIdePalette.WithShortCut(const ACommand: TAtlasCommand;
  const AShortCuts: TFunc<string, string>): TAtlasCommand;
begin
  Result := ACommand;
  if (Result.ShortCut = '') and Assigned(AShortCuts) then
  begin
    Result.ShortCut := AShortCuts(Result.Id);
  end;
end;

class function TAtlasIdePalette.MenuPaths: TDictionary<TBasicAction, string>;
var
  mServices: INTAServices;

  procedure Walk(AItem: TMenuItem; const APath: string);
  var
    mIndex: Integer;
    mChild: TMenuItem;
    mCaption: string;
  begin
    for mIndex := 0 to AItem.Count - 1 do
    begin
      mChild := AItem.Items[mIndex];
      mCaption := TAtlasCommandPalette.CleanCaption(mChild.Caption);
      if (mChild.Action <> nil) and not Result.ContainsKey(mChild.Action) then
      begin
        Result.Add(mChild.Action, APath);
      end;
      if mChild.Count > 0 then
      begin
        if APath = '' then
        begin
          Walk(mChild, mCaption);
        end
        else
        begin
          Walk(mChild, APath + ' › ' + mCaption);
        end;
      end;
    end;
  end;

begin
  Result := TDictionary<TBasicAction, string>.Create;
  if Supports(BorlandIDEServices, INTAServices, mServices) and (mServices.MainMenu <> nil) then
  begin
    Walk(mServices.MainMenu.Items, '');
  end;
end;

function TAtlasIdePalette.Collect: TArray<TAtlasCommand>;
var
  mServices: INTAServices;
  mPaths: TDictionary<TBasicAction, string>;
  mIndex: Integer;
  mAction: TCustomAction;
  mCommand: TAtlasCommand;
  mSeen: TDictionary<string, Boolean>;
begin
  Result := AtlasCommands;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  mPaths := MenuPaths;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
    begin
      if not (mServices.ActionList.Actions[mIndex] is TCustomAction) then
      begin
        Continue;
      end;
      mAction := TCustomAction(mServices.ActionList.Actions[mIndex]);
      if (mAction.Name = '') or not mAction.Visible or not mAction.Enabled or (mAction.Caption = '') or
        mSeen.ContainsKey(mAction.Name) then
      begin
        Continue;
      end;
      mSeen.Add(mAction.Name, True);
      mCommand := Default(TAtlasCommand);
      mCommand.Id := mAction.Name;
      mCommand.Caption := TAtlasCommandPalette.CleanCaption(mAction.Caption);
      if not mPaths.TryGetValue(mAction, mCommand.Path) then
      begin
        mCommand.Path := mAction.Category;
      end;
      if mAction.ShortCut <> 0 then
      begin
        mCommand.ShortCut := ShortCutToText(mAction.ShortCut);
      end;
      mCommand.Description := mAction.Hint;
      Result := Result + [mCommand];
    end;
  finally
    mSeen.Free;
    mPaths.Free;
  end;
end;

function TAtlasIdePalette.AtlasCommands: TArray<TAtlasCommand>;
var
  mPair: TPair<TAtlasCommand, TProc>;
  mShortCuts: TFunc<string, string>;
begin
  mShortCuts := ShortCuts();
  Result := nil;
  for mPair in FAtlasCommands do
  begin
    if IsVisible(mPair.Key.Id) then
    begin
      Result := Result + [WithShortCut(mPair.Key, mShortCuts)];
    end;
  end;
  Result := Result + ModuleCommands(mShortCuts);
end;

procedure TAtlasIdePalette.Execute(const AId: string);
var
  mPair: TPair<TAtlasCommand, TProc>;
  mCommand: TAtlasCommand;
begin
  for mPair in FAtlasCommands do
  begin
    if mPair.Key.Id = AId then
    begin
      Run(mPair.Key);
      Exit;
    end;
  end;
  for mCommand in ModuleCommands(nil) do
  begin
    if mCommand.Id = AId then
    begin
      Run(mCommand);
      Exit;
    end;
  end;
end;

/// <summary>Führt die Aktion der IDE mit dem Namen AId aus, wenn es sie noch gibt und sie aktiv ist.</summary>
procedure RunIdeAction(const AId: string);
var
  mServices: INTAServices;
  mIndex: Integer;
  mAction: TContainedAction;
begin
  // Die Aktion neu suchen: Sie kann inzwischen freigegeben sein.
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    mAction := mServices.ActionList.Actions[mIndex];
    if SameText(mAction.Name, AId) then
    begin
      mAction.Update;
      if not (mAction is TCustomAction) or TCustomAction(mAction).Enabled then
      begin
        mAction.Execute;
      end;
      Exit;
    end;
  end;
end;

procedure TAtlasIdePalette.Run(const ACommand: TAtlasCommand);
var
  mPair: TPair<TAtlasCommand, TProc>;
  mFound: Boolean;
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
    mFound := False;
    for mPair in FAtlasCommands do
    begin
      if mPair.Key.Id = ACommand.Id then
      begin
        mPair.Value();
        mFound := True;
      end;
    end;
    if not mFound then
    begin
      RunModuleCommand(ACommand.Id);
    end;
  end
  else
  begin
    RunIdeAction(ACommand.Id);
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
  mWindow: TAtlasPaletteWindow;
  mArea: TRect;
  mSource: IAtlasPaletteSource;
begin
  mWindow := TAtlasPaletteWindow.CreatePalette(Application, Collect, FHistory, TAtlasIdeStyle.Colors);
  mWindow.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    begin
      Run(ACommand);
    end;
  mSource := nil;
  if Assigned(FSourceOf) then
  begin
    mSource := FSourceOf();
  end;
  if mSource <> nil then
  begin
    Attach(mWindow, mSource);
  end;
  if Screen.ActiveForm <> nil then
  begin
    mArea := Screen.ActiveForm.BoundsRect;
  end
  else if Application.MainForm <> nil then
  begin
    mArea := Application.MainForm.BoundsRect;
  end
  else
  begin
    mArea := Screen.WorkAreaRect;
  end;
  mWindow.ShowOver(mArea);
end;

end.