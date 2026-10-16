unit Atlas.IDE.UnitSearch.Commands;

// Fenster „Units suchen“ (#777) in der IDE:
// - Zeigen: Einträge über atlas.server.units, offene Module markiert, Lage und
//   Wahl aus %LOCALAPPDATA%\Atlas\unitsearch.json; Vorschau über
//   atlas.server.unitPreview (Formularskizze und „Verwendet von“ nach den
//   Einstellungen).
// - Aktionen: Öffnen, Formular öffnen, In uses aufnehmen (atlas.server.addUses
//   in die Unit des obersten Editors), Testunits öffnen
//   (atlas.server.testUnit), Im Projektmanager zeigen, Im Explorer zeigen.
//   „Im Projektmanager zeigen“ öffnet den Projektmanager und nennt das
//   Projekt; einen Knoten auswählen kann die Open Tools API nicht.
// - Strg+F12: Die IDE-Aktion „Units“ (ViewUnitCommand, ersatzweise die Aktion
//   mit Strg+F12) ruft das Atlas-Fenster auf, solange unitSearch.enabled und
//   unitSearch.replaceIdeDialog an sind. Mit gedrückter Umschalttaste, ohne
//   Server und über den Befehl „IDE-Dialog Units suchen“ kommt der IDE-Dialog.
//   Die Einstellungen gelten ohne Neustart; Uninstall stellt die Aktion zurück.
//   Die Tastenkürzel-Übersicht (#520) fragt die übernommene Aktion über
//   HookedAction ab und zeigt Strg+F12 dann als Atlas-Taste.
// Meldungen nur als Zeile in der Meldungsansicht, nie als Dialog.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Lsp.Session;

type
  TAtlasIdeUnitSearch = class
  private class var
    FSessionOf: TFunc<TLspSession>;
    FMessage: TProc<string>;
    FHook: TComponent;
  private
    class function Session: TLspSession; static;
    class procedure Say(const AText: string); static;
  public
    /// <summary>ASessionOf: laufende Sitzung (Server bei Bedarf gestartet) oder nil; AMessage: Zeile für
    /// die Meldungsansicht. Hängt sich an die IDE-Aktion für Strg+F12.</summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>Atlas-Fenster zeigen; abgeschaltet den IDE-Dialog, ohne Server mit AFallback ebenso.</summary>
    class procedure Show(AFallback: Boolean); overload; static;
    class procedure Show; overload; static;
    /// <summary>Den Dialog der IDE (Ansicht › Units) ohne Umweg über Atlas.</summary>
    class procedure ShowIdeDialog; static;
    /// <summary>Die Aktion der IDE, an die sich Atlas für Strg+F12 gehängt hat; nil ohne (#520).</summary>
    class function HookedAction: TBasicAction; static;
    /// <summary>Datei für Lage und Wahl des Fensters.</summary>
    class function StateFile: string; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Winapi.Windows,
  Winapi.ShellAPI,
  System.Types,
  System.JSON,
  System.IOUtils,
  System.Actions,
  System.Generics.Collections,
  Vcl.ActnList,
  Vcl.Forms,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.TestUnit,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.State,
  Atlas.UI.Strings,
  Atlas.UI.UnitSearch.Window,
  Atlas.IDE.Editor.Buffer,
  Atlas.IDE.Editor.Style,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Hover.Editor,
  Atlas.IDE.Settings.Store,
  Atlas.Core.Editor.WorkspacePlan;

const
  UnitsCommand = 'atlas.server.units';
  PreviewCommand = 'atlas.server.unitPreview';
  AddUsesCommand = 'atlas.server.addUses';
  TestUnitCommand = 'atlas.server.testUnit';
  // Die Liste kann bei großen Bibliotheken dauern; die Vorschau soll das Tippen nicht aufhalten.
  UnitsTimeoutMs = 30000;
  PreviewTimeoutMs = 5000;
  CommandTimeoutMs = 30000;
  IdeActionName = 'ViewUnitCommand';
  ProjectManagerActionName = 'ViewPrjMgrCommand';

type
  /// <summary>Hängt sich an OnExecute der IDE-Aktion „Units“ und gibt sie beim Freigeben zurück.</summary>
  TUnitDialogHook = class(TComponent)
  private
    FAction: TContainedAction;
    FOriginal: TNotifyEvent;
    FBypass: Boolean;
    procedure Execute(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AAction: TContainedAction); reintroduce;
    destructor Destroy; override;
    /// <summary>Ursprüngliches Verhalten der Aktion (IDE-Dialog).</summary>
    procedure RunOriginal;
  end;

  /// <summary>Ein offenes Fenster samt Zustand und Ziel für „In uses aufnehmen“.</summary>
  TOpenSearch = class
  public
    Window: TAtlasUnitSearchWindow;
    State: TAtlasUnitSearchState;
    /// <summary>Datei des obersten Editors beim Öffnen; '' ohne.</summary>
    Target: string;
    destructor Destroy; override;
  end;

var
  Current: TOpenSearch;

function FindIdeAction: TContainedAction;
var
  Services: INTAServices;
  Index: Integer;
  Action: TContainedAction;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
    Exit;
  for Index := 0 to Services.ActionList.ActionCount - 1 do
  begin
    Action := Services.ActionList.Actions[Index];
    if SameText(Action.Name, IdeActionName) then
      Exit(Action);
  end;
  // Ersatz: die Aktion mit Strg+F12.
  for Index := 0 to Services.ActionList.ActionCount - 1 do
  begin
    Action := Services.ActionList.Actions[Index];
    if (Action is TCustomAction) and (TCustomAction(Action).ShortCut = ShortCut(VK_F12, [ssCtrl])) then
      Exit(Action);
  end;
end;

function RunNamedAction(const AName: string): Boolean;
var
  Services: INTAServices;
  Index: Integer;
begin
  Result := False;
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
    Exit;
  for Index := 0 to Services.ActionList.ActionCount - 1 do
    if SameText(Services.ActionList.Actions[Index].Name, AName) then
      Exit(Services.ActionList.Actions[Index].Execute);
end;

function Settings: TAtlasPluginSettings;
begin
  Result := TAtlasIdeSettings.Current;
end;

function UriToPath(AUri: string): string;
begin
  Result := TLspSession.UriToPath(AUri);
end;

{ TUnitDialogHook }

constructor TUnitDialogHook.Create(AAction: TContainedAction);
begin
  inherited Create(nil);
  FAction := AAction;
  FOriginal := AAction.OnExecute;
  FAction.OnExecute := Execute;
  FAction.FreeNotification(Self);
end;

destructor TUnitDialogHook.Destroy;
begin
  if FAction <> nil then
  begin
    FAction.RemoveFreeNotification(Self);
    FAction.OnExecute := FOriginal;
  end;
  inherited Destroy;
end;

procedure TUnitDialogHook.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FAction) then
    FAction := nil;
end;

procedure TUnitDialogHook.RunOriginal;
begin
  if FAction = nil then
    Exit;
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
      FAction.OnExecute := Execute;
    FBypass := False;
  end;
end;

procedure TUnitDialogHook.Execute(Sender: TObject);
var
  Plugin: TAtlasPluginSettings;
begin
  if FBypass then
    Exit;
  Plugin := Settings;
  // Umschalttaste (etwa beim Klick ins Menü Ansicht) holt den IDE-Dialog.
  if not Plugin.UnitSearchEnabled or not Plugin.UnitSearchReplaceIdeDialog or (GetKeyState(VK_SHIFT) < 0) then
  begin
    RunOriginal;
    Exit;
  end;
  // Abgeschaltet nach Fehlern (#493) oder Fehler beim Öffnen: Strg+F12 darf nie ins Leere gehen.
  if TAtlasGuard.Disabled(TAtlasFeature.EditorCommands) then
  begin
    RunOriginal;
    Exit;
  end;
  if not TAtlasGuard.Run(TAtlasFeature.EditorCommands,
    procedure
    begin
      TAtlasIdeUnitSearch.Show(True);
    end) then
    RunOriginal;
end;

{ TOpenSearch }

destructor TOpenSearch.Destroy;
begin
  State.Free;
  inherited Destroy;
end;

{ Hilfen der Aktionen }

function OpenModules: TArray<string>;
var
  Services: IOTAModuleServices;
  Index: Integer;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    for Index := 0 to Services.ModuleCount - 1 do
      Result := Result + [Services.Modules[Index].FileName];
end;

procedure MarkOpen(var AEntries: TAtlasUnitEntries);
var
  Files: TDictionary<string, Boolean>;
  FileName: string;
  Index: Integer;
begin
  Files := TDictionary<string, Boolean>.Create;
  try
    for FileName in OpenModules do
      Files.AddOrSetValue(LowerCase(FileName), True);
    for Index := 0 to High(AEntries) do
      AEntries[Index].IsOpen := Files.ContainsKey(LowerCase(AEntries[Index].FileName));
  finally
    Files.Free;
  end;
end;

procedure GroupInfo(out AGroupFile, AActiveProject, ARoot: string);
var
  Services: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Project: IOTAProject;
begin
  AGroupFile := '';
  AActiveProject := '';
  ARoot := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Group := Services.MainProjectGroup;
  if Group <> nil then
    AGroupFile := Group.FileName;
  Project := Services.GetActiveProject;
  if Project <> nil then
  begin
    AActiveProject := ChangeFileExt(ExtractFileName(Project.FileName), '');
    if AGroupFile = '' then
      AGroupFile := Project.FileName;
  end;
  if AGroupFile <> '' then
    ARoot := ExtractFileDir(AGroupFile);
end;

function TopFile: string;
var
  Editors: IOTAEditorServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAEditorServices, Editors) and (Editors.TopBuffer <> nil) then
    Result := Editors.TopBuffer.FileName;
end;

function FormFileOf(const AFileName: string): string;
begin
  Result := ChangeFileExt(AFileName, '.dfm');
  if FileExists(Result) then
    Exit;
  Result := ChangeFileExt(AFileName, '.fmx');
  if not FileExists(Result) then
    Result := '';
end;

function ShowForm(const AFileName: string): Boolean;
var
  Actions: IOTAActionServices;
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index: Integer;
  FormEditor: IOTAFormEditor;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAActionServices, Actions) or not Actions.OpenFile(AFileName) or
    not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Module := Modules.FindModule(AFileName);
  if Module = nil then
    Exit;
  for Index := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[Index], IOTAFormEditor, FormEditor) then
    begin
      FormEditor.Show;
      Exit(True);
    end;
end;

function UnitList(const AEntries: TArray<TAtlasUnitEntry>): string;
var
  Entry: TAtlasUnitEntry;
begin
  Result := '';
  for Entry in AEntries do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Entry.Name;
  end;
end;

{ TAtlasIdeUnitSearch }

class procedure TAtlasIdeUnitSearch.Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>);
var
  Action: TContainedAction;
begin
  FSessionOf := ASessionOf;
  FMessage := AMessage;
  FHook := nil;
  Action := FindIdeAction;
  if Action <> nil then
    FHook := TUnitDialogHook.Create(Action)
  else
    TAtlasGuard.Log('Units suchen: IDE-Aktion für Strg+F12 nicht gefunden');
end;

class procedure TAtlasIdeUnitSearch.Uninstall;
begin
  if Current <> nil then
  begin
    Current.Window.OnClosed := nil;
    Current.Window.Free;
    FreeAndNil(Current);
  end;
  FreeAndNil(FHook);
  FSessionOf := nil;
  FMessage := nil;
end;

class function TAtlasIdeUnitSearch.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
    Result := FSessionOf();
end;

class procedure TAtlasIdeUnitSearch.Say(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

class function TAtlasIdeUnitSearch.StateFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'unitsearch.json');
end;

class function TAtlasIdeUnitSearch.HookedAction: TBasicAction;
begin
  Result := nil;
  if FHook <> nil then
    Result := TUnitDialogHook(FHook).FAction;
end;

class procedure TAtlasIdeUnitSearch.ShowIdeDialog;
begin
  if FHook <> nil then
    TUnitDialogHook(FHook).RunOriginal
  else
    RunNamedAction(IdeActionName);
end;

class procedure TAtlasIdeUnitSearch.Show;
begin
  Show(False);
end;

procedure RunAction(AAction: TAtlasUnitSearchAction; const AEntries: TArray<TAtlasUnitEntry>;
  const ATarget: string); forward;

class procedure TAtlasIdeUnitSearch.Show(AFallback: Boolean);
var
  Plugin: TAtlasPluginSettings;
  Options: TAtlasUnitSearchOptions;
  Search: TOpenSearch;
  Area: TRect;
  Running: TLspSession;
begin
  Plugin := Settings;
  // Abgeschaltet: der Dialog der IDE übernimmt.
  if not Plugin.UnitSearchEnabled then
  begin
    ShowIdeDialog;
    Exit;
  end;
  Running := Session;
  if Running = nil then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.UnitSearchNoServer));
    if AFallback then
      ShowIdeDialog;
    Exit;
  end;
  if Current <> nil then
  begin
    Current.Window.Show;
    Current.Window.SetFocus;
    Exit;
  end;
  Options := Default(TAtlasUnitSearchOptions);
  Options.Filters := Plugin.UnitSearchFilters;
  Options.FilterSyntax := Plugin.UnitSearchFilterSyntax;
  Options.Preview := Plugin.UnitSearchPreview;
  Options.PreviewForm := Plugin.UnitSearchPreviewForm;
  Options.PreviewUsedBy := Plugin.UnitSearchPreviewUsedBy;
  Options.MultiSelect := Plugin.UnitSearchMultiSelect;
  Options.Actions := Plugin.UnitSearchActions;
  Options.AddUses := Plugin.UnitSearchActionsAddUses;
  Options.RememberCollapsed := Plugin.UnitSearchRememberCollapsed;
  Options.PathStyle := TAtlasUnitSearch.PathStyleFromText(Plugin.UnitSearchPathStyle);
  Options.Grouping := TAtlasUnitSearch.GroupingFromText(Plugin.UnitSearchGroupBy);
  Options.DefaultOrigins := TAtlasUnitSearch.OriginsForScope(Plugin.UnitSearchDefaultScope);
  GroupInfo(Options.GroupFile, Options.ActiveProject, Options.Root);
  Search := TOpenSearch.Create;
  Search.State := TAtlasUnitSearchState.Create;
  try
    Search.State.LoadFromFile(StateFile);
  except
    on E: Exception do
      TAtlasGuard.Log('Units suchen: Zustand nicht lesbar: ' + E.Message);
  end;
  Search.Target := TopFile;
  Search.Window := TAtlasUnitSearchWindow.CreateSearch(Application, Options, Search.State, TAtlasIdeStyle.Colors);
  Current := Search;
  Search.Window.Loading := True;
  Search.Window.OnClosed :=
    procedure
    begin
      if Current = nil then
        Exit;
      try
        Current.State.SaveToFile(StateFile);
      except
        on E: Exception do
          TAtlasGuard.Log('Units suchen: Zustand nicht gespeichert: ' + E.Message);
      end;
      FreeAndNil(Current);
    end;
  Search.Window.OnPreview :=
    function(const AEntry: TAtlasUnitEntry): TAtlasUnitPreview
    var
      Arguments: TJSONArray;
      Flags: TJSONObject;
      Answer: TJSONValue;
      Live: TLspSession;
      Text: string;
    begin
      Result := Default(TAtlasUnitPreview);
      Result.FileName := AEntry.FileName;
      Result.UsedBy := -1;
      Live := Session;
      if Live = nil then
        Exit;
      Arguments := TJSONArray.Create;
      try
        Arguments.Add(TLspSession.PathToUri(AEntry.FileName));
        Flags := TJSONObject.Create;
        Flags.AddPair('form', TJSONBool.Create(Settings.UnitSearchPreviewForm));
        Flags.AddPair('usedBy', TJSONBool.Create(Settings.UnitSearchPreviewUsedBy));
        Arguments.Add(Flags);
        Text := Arguments.ToJSON;
      finally
        Arguments.Free;
      end;
      try
        Answer := Live.RunCommand(PreviewCommand, Text, PreviewTimeoutMs);
      except
        on E: ELspClientError do
          Exit;
      end;
      try
        Result := TAtlasUnitPreview.FromJson(Answer, UriToPath);
      finally
        Answer.Free;
      end;
    end;
  Search.Window.OnAction :=
    procedure(AAction: TAtlasUnitSearchAction; const AEntries: TArray<TAtlasUnitEntry>)
    var
      Target: string;
    begin
      Target := '';
      if Current <> nil then
        Target := Current.Target;
      TAtlasGuard.Run(TAtlasFeature.EditorCommands,
        procedure
        begin
          RunAction(AAction, AEntries, Target);
        end);
    end;
  Area := Screen.MonitorFromWindow(GetForegroundWindow).WorkareaRect;
  Search.Window.ShowOver(Area);
  // Erst nach dem Zeichnen laden: das Fenster zeigt so lange „Units werden geladen …“.
  TAtlasMainThread.ForceQueue(TAtlasFeature.EditorCommands,
    procedure
    var
      Answer: TJSONValue;
      Entries: TAtlasUnitEntries;
      Live: TLspSession;
      Active: string;
    begin
      if Current <> Search then
        Exit;
      Live := Session;
      if Live = nil then
      begin
        Say(TAtlasStrings.Text(TAtlasTextId.UnitSearchNoServer));
        Exit;
      end;
      try
        Answer := Live.RunCommand(UnitsCommand, '[]', UnitsTimeoutMs);
      except
        on E: ELspClientError do
        begin
          Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
          Exit;
        end;
      end;
      try
        Active := Options.ActiveProject;
        Entries := TAtlasUnitSearch.FromJson(Answer, Active, UriToPath);
      finally
        Answer.Free;
      end;
      MarkOpen(Entries);
      if Current = Search then
        Search.Window.SetEntries(Entries);
    end);
end;

procedure OpenTests(const AEntries: TArray<TAtlasUnitEntry>);
var
  Entry: TAtlasUnitEntry;
  Values: TJSONArray;
  Arguments: string;
  Answer: TJSONValue;
  Info: TAtlasTestUnitInfo;
  Live: TLspSession;
begin
  for Entry in AEntries do
  begin
    if Entry.Kind = TAtlasUnitKind.Test then
    begin
      TAtlasEditorHover.GoToLocation(Entry.FileName, 0, 0);
      Continue;
    end;
    Live := TAtlasIdeUnitSearch.Session;
    if Live = nil then
      Exit;
    Values := TJSONArray.Create;
    try
      Values.Add(TLspSession.PathToUri(Entry.FileName));
      Values.Add(0);
      Arguments := Values.ToJSON;
    finally
      Values.Free;
    end;
    try
      Answer := Live.RunCommand(TestUnitCommand, Arguments, CommandTimeoutMs);
    except
      on E: ELspClientError do
      begin
        TAtlasIdeUnitSearch.Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
        Exit;
      end;
    end;
    try
      Info := TAtlasTestUnitInfo.FromJson(Answer, UriToPath);
    finally
      Answer.Free;
    end;
    if Info.CounterpartFile <> '' then
      TAtlasEditorHover.GoToLocation(Info.CounterpartFile, 0, 0)
    else
      TAtlasIdeUnitSearch.Say(TAtlasStrings.Fmt(TAtlasTextId.UnitSearchNoTests, [Entry.Name]));
  end;
end;

procedure AddUses(const AEntries: TArray<TAtlasUnitEntry>; const ATarget: string);
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index: Integer;
  Editor: IOTASourceEditor;
  Values, Names: TJSONArray;
  Entry: TAtlasUnitEntry;
  Arguments: string;
  Answer, EditValue, AddedValue: TJSONValue;
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
  Added: Integer;
  Live: TLspSession;
begin
  if (ATarget = '') or not SameText(ExtractFileExt(ATarget), '.pas') and
    not SameText(ExtractFileExt(ATarget), '.dpr') and not SameText(ExtractFileExt(ATarget), '.dpk') then
  begin
    TAtlasIdeUnitSearch.Say(TAtlasStrings.Text(TAtlasTextId.UnitSearchUsesNone));
    Exit;
  end;
  Live := TAtlasIdeUnitSearch.Session;
  if Live = nil then
  begin
    TAtlasIdeUnitSearch.Say(TAtlasStrings.Text(TAtlasTextId.UnitSearchNoServer));
    Exit;
  end;
  // Der Server braucht den Text des Puffers, nicht den der Platte.
  if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Module := Modules.FindModule(ATarget);
    if Module <> nil then
      for Index := 0 to Module.ModuleFileCount - 1 do
        if Supports(Module.ModuleFileEditors[Index], IOTASourceEditor, Editor) and (Editor.EditViewCount > 0) then
        begin
          Live.Sync(ATarget, TAtlasEditorBuffer.Text(Editor.EditViews[0].Buffer));
          Break;
        end;
  end;
  Values := TJSONArray.Create;
  try
    Values.Add(TLspSession.PathToUri(ATarget));
    Names := TJSONArray.Create;
    for Entry in AEntries do
      if Entry.Kind <> TAtlasUnitKind.Include then
        Names.Add(Entry.Name);
    Values.Add(Names);
    Arguments := Values.ToJSON;
  finally
    Values.Free;
  end;
  try
    Answer := Live.RunCommand(AddUsesCommand, Arguments, CommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      TAtlasIdeUnitSearch.Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  Added := 0;
  try
    Edit := Default(TLspWorkspaceEdit);
    if Answer is TJSONObject then
    begin
      EditValue := TJSONObject(Answer).GetValue('edit');
      Edit := TLspWorkspaceEdit.FromJson(EditValue);
      AddedValue := TJSONObject(Answer).GetValue('added');
      if AddedValue is TJSONArray then
        Added := TJSONArray(AddedValue).Count;
    end;
  finally
    Answer.Free;
  end;
  if Edit.IsEmpty then
  begin
    TAtlasIdeUnitSearch.Say(TAtlasStrings.Fmt(TAtlasTextId.UnitSearchUsesAdded, [0, ExtractFileName(ATarget)]));
    Exit;
  end;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
    TAtlasStrings.Text(TAtlasTextId.UnitSearchAddUses) + ': ' + UnitList(AEntries));
  if Outcome.Error <> '' then
    TAtlasIdeUnitSearch.Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]))
  else
    TAtlasIdeUnitSearch.Say(TAtlasStrings.Fmt(TAtlasTextId.UnitSearchUsesAdded, [Added, ExtractFileName(ATarget)]));
end;

procedure RunAction(AAction: TAtlasUnitSearchAction; const AEntries: TArray<TAtlasUnitEntry>;
  const ATarget: string);
var
  Entry: TAtlasUnitEntry;
  FormFile, Project: string;
begin
  if Length(AEntries) = 0 then
    Exit;
  case AAction of
    TAtlasUnitSearchAction.Open:
      for Entry in AEntries do
        TAtlasEditorHover.GoToLocation(Entry.FileName, 0, 0);
    TAtlasUnitSearchAction.OpenForm:
      for Entry in AEntries do
      begin
        FormFile := FormFileOf(Entry.FileName);
        if (FormFile = '') or not ShowForm(Entry.FileName) then
          TAtlasIdeUnitSearch.Say(TAtlasStrings.Fmt(TAtlasTextId.UnitSearchNoForm, [Entry.Name]));
      end;
    TAtlasUnitSearchAction.AddUses:
      AddUses(AEntries, ATarget);
    TAtlasUnitSearchAction.OpenTests:
      OpenTests(AEntries);
    TAtlasUnitSearchAction.ShowProject:
      begin
        // Die Open Tools API wählt keinen Knoten im Projektmanager aus: öffnen und das Projekt nennen.
        RunNamedAction(ProjectManagerActionName);
        for Entry in AEntries do
        begin
          Project := string.Join(', ', Entry.Projects);
          if Project = '' then
            Project := TAtlasStrings.Text(TAtlasTextId.UnitSearchNoProject);
          TAtlasIdeUnitSearch.Say(TAtlasStrings.Fmt(TAtlasTextId.UnitSearchProjectOf, [Entry.Name, Project]));
        end;
      end;
    TAtlasUnitSearchAction.ShowExplorer:
      ShellExecute(0, 'open', 'explorer.exe', PChar('/select,"' + AEntries[0].FileName + '"'), nil, SW_SHOWNORMAL);
  end;
end;

end.
