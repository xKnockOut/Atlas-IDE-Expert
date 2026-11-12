unit Atlas.IDE.UnitSearch.Commands;

// Fenster „Units suchen“ (#777) in der IDE:
// - Zeigen: Lage und Wahl aus %LOCALAPPDATA%\Atlas\unitsearch.json; Einträge,
//   Vorschau und Aktionen (Öffnen, In uses aufnehmen, Testunits …) laufen
//   über Atlas.IDE.UnitSearch.Actions.
// - Strg+F12: Die IDE-Aktion „Units“ (ViewUnitCommand, ersatzweise die Aktion
//   mit Strg+F12) ruft das Atlas-Fenster auf, solange unitSearch.enabled und
//   unitSearch.replaceIdeDialog an sind. Mit gedrückter Umschalttaste, ohne
//   Server und über den Befehl „IDE-Dialog Units suchen“ kommt der IDE-Dialog.
//   Die Einstellungen gelten ohne Neustart; Uninstall stellt die Aktion zurück.
//   Die Tastenkürzel-Übersicht (#520) fragt die übernommene Aktion über
//   HookedAction ab und zeigt Strg+F12 dann als Atlas-Taste.
// - Alt+F11 und Umschalt+F12 (#786): Derselbe Baustein übernimmt die
//   IDE-Aktionen „Unit verwenden“ (FileUseUnitCommand) und „Formulare“
//   (ViewFormCommand, ersatzweise die Aktion mit der Taste) nach
//   unitSearch.replaceUseUnitDialog bzw. unitSearch.replaceFormsDialog. Das
//   Fenster öffnet dann im Modus „Unit verwenden in <Unit>“ (Kreise und
//   „schon in uses“ über atlas.useUnitInfo, Einfügen in den gewählten
//   Abschnitt über atlas.server.addUses mit {"section"}, ein
//   Rückgängig-Schritt) bzw. „Formulare suchen“ (Filter t:form|frame|dm,
//   Enter öffnet den Designer). Umschalt, ohne Server und die Befehle
//   „IDE-Dialog Unit verwenden“ / „IDE-Dialog Formulare“ holen die Dialoge
//   der IDE.
// Meldungen nur als Zeile in der Meldungsansicht, nie als Dialog.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Lsp.Session,
  Atlas.Core.UnitSearch.UseUnit,
  Atlas.IDE.UnitSearch.Actions;

type
  TAtlasIdeUnitSearch = class
  private class var
    FHooks: array[TAtlasUnitSearchMode] of TComponent;
  private
    class function Session: TLspSession; static;
    class procedure Say(const AText: string); static;
  public
    /// <summary>ASessionOf: laufende Sitzung (Server bei Bedarf gestartet) oder nil; AMessage: Zeile für
    /// die Meldungsansicht; ARunAsync: Serverbefehl im Hintergrund. Hängt sich an die IDE-Aktion für Strg+F12.
    /// </summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>;
      const ARunAsync: TAtlasUnitSearchCommandAsync); static;
    class procedure Uninstall; static;
    /// <summary>Atlas-Fenster zeigen; abgeschaltet den IDE-Dialog, ohne Server mit AFallback ebenso.</summary>
    class procedure Show(AFallback: Boolean); overload; static;
    class procedure Show; overload; static;
    /// <summary>Fenster im Modus AMode (#786); abgeschaltet oder ohne Server mit AFallback der IDE-Dialog.</summary>
    class procedure Show(AMode: TAtlasUnitSearchMode; AFallback: Boolean); overload; static;
    /// <summary>„Unit verwenden“ in die Unit des obersten Editors (#786).</summary>
    class procedure ShowUseUnit; static;
    /// <summary>„Formulare suchen“ (#786).</summary>
    class procedure ShowForms; static;
    /// <summary>Den Dialog der IDE (Ansicht › Units) ohne Umweg über Atlas.</summary>
    class procedure ShowIdeDialog; overload; static;
    class procedure ShowIdeDialog(AMode: TAtlasUnitSearchMode); overload; static;
    /// <summary>Datei › Unit verwenden der IDE (#786).</summary>
    class procedure ShowUseUnitIdeDialog; static;
    /// <summary>Ansicht › Formulare der IDE (#786).</summary>
    class procedure ShowFormsIdeDialog; static;
    /// <summary>Die Aktion der IDE, an die sich Atlas für Strg+F12 gehängt hat; nil ohne (#520).</summary>
    class function HookedAction: TBasicAction; static;
    /// <summary>Datei für Lage und Wahl des Fensters.</summary>
    class function StateFile: string; static;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Winapi.Windows,
  System.Types,
  System.IOUtils,
  System.Actions,
  Vcl.ActnList,
  Vcl.Forms,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.State,
  Atlas.UI.Search.Strings,
  Atlas.UI.UnitSearch.Data,
  Atlas.UI.UnitSearch.Window,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

const
  // Aktionen der IDE je Modus (#777, #786) und ihre Standardtasten als Ersatz.
  cIdeActionNames: array[TAtlasUnitSearchMode] of string = ('ViewUnitCommand', 'FileUseUnitCommand',
    'ViewFormCommand');
  cIdeActionKeys: array[TAtlasUnitSearchMode] of string = ('Ctrl+F12', 'Alt+F11', 'Shift+F12');

type
  /// <summary>Hängt sich an OnExecute der IDE-Aktion „Units“, „Unit verwenden“ oder „Formulare“ und gibt sie
  /// beim Freigeben zurück.</summary>
  TUnitDialogHook = class(TComponent)
  private
    FAction: TContainedAction;
    FOriginal: TNotifyEvent;
    FBypass: Boolean;
    FMode: TAtlasUnitSearchMode;
    procedure Execute(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AAction: TContainedAction; AMode: TAtlasUnitSearchMode); reintroduce;
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
    Mode: TAtlasUnitSearchMode;
    destructor Destroy; override;
  end;

var
  Current: TOpenSearch;

function FindIdeAction(AMode: TAtlasUnitSearchMode): TContainedAction;
var
  mServices: INTAServices;
  mIndex: Integer;
  mAction: TContainedAction;
  mKey: TShortCut;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    mAction := mServices.ActionList.Actions[mIndex];
    if SameText(mAction.Name, cIdeActionNames[AMode]) then
    begin
      Exit(mAction);
    end;
  end;
  // Ersatz: die Aktion mit der Standardtaste.
  mKey := TextToShortCut(cIdeActionKeys[AMode]);
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    mAction := mServices.ActionList.Actions[mIndex];
    if (mAction is TCustomAction) and (TCustomAction(mAction).ShortCut = mKey) then
    begin
      Exit(mAction);
    end;
  end;
end;

/// <summary>Übernimmt Atlas die IDE-Aktion des Modus (unitSearch.replace…)?</summary>
function Replaces(const APlugin: TAtlasPluginSettings; AMode: TAtlasUnitSearchMode): Boolean;
begin
  case AMode of
    TAtlasUnitSearchMode.UseUnit: Result := APlugin.UnitSearchReplaceUseUnitDialog;
    TAtlasUnitSearchMode.Forms: Result := APlugin.UnitSearchReplaceFormsDialog;
  else
    Result := APlugin.UnitSearchReplaceIdeDialog;
  end;
end;

function Settings: TAtlasPluginSettings;
begin
  Result := TAtlasIdeSettings.Current;
end;

{ TUnitDialogHook }

constructor TUnitDialogHook.Create(AAction: TContainedAction; AMode: TAtlasUnitSearchMode);
begin
  inherited Create(nil);
  FAction := AAction;
  FMode := AMode;
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
  begin
    FAction := nil;
  end;
end;

procedure TUnitDialogHook.RunOriginal;
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

procedure TUnitDialogHook.Execute(Sender: TObject);
var
  mPlugin: TAtlasPluginSettings;
begin
  if FBypass then
  begin
    Exit;
  end;
  mPlugin := Settings;
  // Umschalttaste (etwa beim Klick ins Menü Ansicht) holt den IDE-Dialog.
  if not mPlugin.UnitSearchEnabled or not Replaces(mPlugin, FMode) or (GetKeyState(VK_SHIFT) < 0) then
  begin
    RunOriginal;
    Exit;
  end;
  // Abgeschaltet nach Fehlern (#493) oder Fehler beim Öffnen: Die Taste darf nie ins Leere gehen.
  if TAtlasGuard.Disabled(TAtlasFeature.UnitSearch) then
  begin
    RunOriginal;
    Exit;
  end;
  if not TAtlasGuard.Run(TAtlasFeature.UnitSearch,
    procedure
    begin
      TAtlasIdeUnitSearch.Show(FMode, True);
    end) then
  begin
    RunOriginal;
  end;
end;

{ TOpenSearch }

destructor TOpenSearch.Destroy;
begin
  State.Free;
  inherited Destroy;
end;

{ Hilfen }

procedure GroupInfo(out AGroupFile, AActiveProject, ARoot: string);
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mProject: IOTAProject;
begin
  AGroupFile := '';
  AActiveProject := '';
  ARoot := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  if mGroup <> nil then
  begin
    AGroupFile := mGroup.FileName;
  end;
  mProject := mServices.GetActiveProject;
  if mProject <> nil then
  begin
    AActiveProject := ChangeFileExt(ExtractFileName(mProject.FileName), '');
    if AGroupFile = '' then
    begin
      AGroupFile := mProject.FileName;
    end;
  end;
  if AGroupFile <> '' then
  begin
    ARoot := ExtractFileDir(AGroupFile);
  end;
end;

function TopFile: string;
var
  mEditors: IOTAEditorServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) and (mEditors.TopBuffer <> nil) then
  begin
    Result := mEditors.TopBuffer.FileName;
  end;
end;

{ TAtlasIdeUnitSearch }

class procedure TAtlasIdeUnitSearch.Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>;
  const ARunAsync: TAtlasUnitSearchCommandAsync);
var
  mAction: TContainedAction;
  mMode: TAtlasUnitSearchMode;
begin
  TAtlasIdeUnitSearchActions.Install(ASessionOf, AMessage, ARunAsync);
  for mMode := Low(TAtlasUnitSearchMode) to High(TAtlasUnitSearchMode) do
  begin
    FHooks[mMode] := nil;
    mAction := FindIdeAction(mMode);
    if mAction <> nil then
    begin
      FHooks[mMode] := TUnitDialogHook.Create(mAction, mMode);
    end
    else
    begin
      TAtlasGuard.Log('Units suchen: IDE-Aktion für ' + cIdeActionKeys[mMode] + ' nicht gefunden');
    end;
  end;
end;

class procedure TAtlasIdeUnitSearch.Uninstall;
var
  mMode: TAtlasUnitSearchMode;
begin
  if Current <> nil then
  begin
    Current.Window.OnClosed := nil;
    Current.Window.Free;
    FreeAndNil(Current);
  end;
  for mMode := Low(TAtlasUnitSearchMode) to High(TAtlasUnitSearchMode) do
  begin
    FreeAndNil(FHooks[mMode]);
  end;
  TAtlasIdeUnitSearchActions.Uninstall;
end;

class function TAtlasIdeUnitSearch.Session: TLspSession;
begin
  Result := TAtlasIdeUnitSearchActions.Session;
end;

class procedure TAtlasIdeUnitSearch.Say(const AText: string);
begin
  TAtlasIdeUnitSearchActions.Say(AText);
end;

class function TAtlasIdeUnitSearch.StateFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'), 'unitsearch.json');
end;

class function TAtlasIdeUnitSearch.HookedAction: TBasicAction;
begin
  Result := nil;
  if FHooks[TAtlasUnitSearchMode.Search] <> nil then
  begin
    Result := TUnitDialogHook(FHooks[TAtlasUnitSearchMode.Search]).FAction;
  end;
end;

class procedure TAtlasIdeUnitSearch.ShowIdeDialog;
begin
  ShowIdeDialog(TAtlasUnitSearchMode.Search);
end;

class procedure TAtlasIdeUnitSearch.ShowIdeDialog(AMode: TAtlasUnitSearchMode);
begin
  if FHooks[AMode] <> nil then
  begin
    TUnitDialogHook(FHooks[AMode]).RunOriginal;
  end
  else
  begin
    TAtlasIdeUnitSearchActions.RunNamedAction(cIdeActionNames[AMode]);
  end;
end;

class procedure TAtlasIdeUnitSearch.ShowUseUnitIdeDialog;
begin
  ShowIdeDialog(TAtlasUnitSearchMode.UseUnit);
end;

class procedure TAtlasIdeUnitSearch.ShowFormsIdeDialog;
begin
  ShowIdeDialog(TAtlasUnitSearchMode.Forms);
end;

class procedure TAtlasIdeUnitSearch.Show;
begin
  Show(False);
end;

class procedure TAtlasIdeUnitSearch.Show(AFallback: Boolean);
begin
  Show(TAtlasUnitSearchMode.Search, AFallback);
end;

class procedure TAtlasIdeUnitSearch.ShowUseUnit;
begin
  Show(TAtlasUnitSearchMode.UseUnit, False);
end;

class procedure TAtlasIdeUnitSearch.ShowForms;
begin
  Show(TAtlasUnitSearchMode.Forms, False);
end;

/// <summary>Einstellungen des neuen Fensters im Modus AMode; ATargetFile ist die Unit für „Unit verwenden“.
/// </summary>
function OptionsFor(AMode: TAtlasUnitSearchMode; const ATargetFile: string): TAtlasUnitSearchOptions;
var
  mPlugin: TAtlasPluginSettings;
begin
  mPlugin := Settings;
  Result := Default(TAtlasUnitSearchOptions);
  Result.Filters := mPlugin.UnitSearchFilters;
  Result.FilterSyntax := mPlugin.UnitSearchFilterSyntax;
  Result.Preview := mPlugin.UnitSearchPreview;
  Result.PreviewForm := mPlugin.UnitSearchPreviewForm;
  Result.PreviewUsedBy := mPlugin.UnitSearchPreviewUsedBy;
  Result.PreviewAutoCollapse := mPlugin.UnitSearchPreviewAutoCollapse;
  Result.MultiSelect := mPlugin.UnitSearchMultiSelect;
  Result.Actions := mPlugin.UnitSearchActions;
  Result.AddUses := mPlugin.UnitSearchActionsAddUses;
  Result.RememberCollapsed := mPlugin.UnitSearchRememberCollapsed;
  Result.PathStyle := TAtlasUnitSearch.PathStyleFromText(mPlugin.UnitSearchPathStyle);
  Result.Grouping := TAtlasUnitSearch.GroupingFromText(mPlugin.UnitSearchGroupBy);
  Result.DefaultOrigins := TAtlasUnitSearch.OriginsForScope(mPlugin.UnitSearchDefaultScope);
  GroupInfo(Result.GroupFile, Result.ActiveProject, Result.Root);
  Result.Mode := AMode;
  if AMode = TAtlasUnitSearchMode.UseUnit then
  begin
    Result.TargetUnit := ChangeFileExt(ExtractFileName(ATargetFile), '');
  end;
end;

/// <summary>Derselbe Modus für dieselbe Unit: offenes Fenster nach vorn holen (True); ein anderes offenes
/// Fenster wird geschlossen.</summary>
function BringCurrentToFront(AMode: TAtlasUnitSearchMode; const ATargetFile: string): Boolean;
begin
  Result := False;
  if Current = nil then
  begin
    Exit;
  end;
  Result := (Current.Mode = AMode) and ((AMode <> TAtlasUnitSearchMode.UseUnit) or
    SameText(Current.Target, ATargetFile));
  if Result then
  begin
    Current.Window.Show;
    Current.Window.SetFocus;
    Exit;
  end;
  Current.Window.Close;
  if Current <> nil then
  begin
    Current.Window.OnClosed := nil;
    FreeAndNil(Current);
  end;
end;

/// <summary>Zustand beim Schließen speichern und das Fenster vergessen.</summary>
procedure ForgetCurrent;
begin
  if Current = nil then
  begin
    Exit;
  end;
  try
    Current.State.SaveToFile(TAtlasIdeUnitSearch.StateFile);
  except
    // Die Meldung kann den Pfad enthalten; ReportNotWritten nennt nur die Klasse.
    on E: Exception do
    begin
      TAtlasDataFile.ReportNotWritten('Zustand von Units suchen', E);
    end;
  end;
  FreeAndNil(Current);
end;

procedure WireEvents(ASearch: TOpenSearch);
var
  mTargetFile: string;
begin
  // Läuft OnUse nach dem Schließen, ist ASearch frei: nur die Datei von oben.
  mTargetFile := ASearch.Target;
  ASearch.Window.OnClosed :=
    procedure
    begin
      ForgetCurrent;
    end;
  ASearch.Window.OnPreview :=
    function(const AEntry: TAtlasUnitEntry): TAtlasUnitPreview
    begin
      Result := TAtlasIdeUnitSearchActions.Preview(AEntry);
    end;
  ASearch.Window.OnAction :=
    procedure(AAction: TAtlasUnitSearchAction; const AEntries: TArray<TAtlasUnitEntry>)
    var
      mTarget: string;
      mChosen: TArray<TAtlasUnitEntry>;
    begin
      mTarget := '';
      if Current <> nil then
      begin
        mTarget := Current.Target;
      end;
      mChosen := AEntries;
      TAtlasGuard.Run(TAtlasFeature.UnitSearch,
        procedure
        begin
          TAtlasIdeUnitSearchActions.Run(AAction, mChosen, mTarget);
        end);
    end;
  ASearch.Window.OnUse :=
    procedure(const AEntries: TArray<TAtlasUnitEntry>; ASection: TAtlasUseUnitSection)
    var
      mChosen: TArray<TAtlasUnitEntry>;
    begin
      mChosen := AEntries;
      TAtlasGuard.Run(TAtlasFeature.UnitSearch,
        procedure
        begin
          TAtlasIdeUnitSearchActions.UseUnits(mChosen, mTargetFile, ASection);
        end);
    end;
end;

/// <summary>Rückruf für „schon in uses“ (#786); eigene Routine, damit die anonyme Methode nur ihren Parameter
/// festhält.</summary>
function UseInfoArrived(ASearch: TOpenSearch): TProc<TAtlasUseUnitInfo>;
var
  mSearch: TOpenSearch;
begin
  mSearch := ASearch;
  Result :=
    procedure(AInfo: TAtlasUseUnitInfo)
    begin
      if Current = mSearch then
      begin
        mSearch.Window.SetUseInfo(AInfo);
      end;
    end;
end;

/// <summary>Rückruf für die Einträge; danach im Modus „Unit verwenden“ Kreise und „schon in uses“ der Zielunit
/// (#786), ohne Antwort ohne Kennzeichen.</summary>
function EntriesArrived(ASearch: TOpenSearch; ALive: TLspSession): TProc<TAtlasUnitEntries>;
var
  mSearch: TOpenSearch;
  mLive: TLspSession;
begin
  mSearch := ASearch;
  mLive := ALive;
  Result :=
    procedure(AEntries: TAtlasUnitEntries)
    begin
      // Inzwischen geschlossen oder neu geöffnet: Die Antwort gehört keinem Fenster mehr.
      if Current <> mSearch then
      begin
        Exit;
      end;
      mSearch.Window.SetEntries(AEntries);
      if (mSearch.Mode = TAtlasUnitSearchMode.UseUnit) and (TAtlasIdeUnitSearchActions.Session = mLive) then
      begin
        TAtlasIdeUnitSearchActions.LoadUseInfo(mLive, mSearch.Target, UseInfoArrived(mSearch));
      end;
    end;
end;

/// <summary>Einträge erst nach dem Zeichnen und im Hintergrund laden: Das Fenster zeigt so lange „Units werden
/// geladen …“ und bleibt bedienbar (atlas.server.units braucht bei großen Gruppen Sekunden).</summary>
procedure LoadLater(ASearch: TOpenSearch; const AActiveProject: string);
var
  mSearch: TOpenSearch;
  mActive: string;
begin
  mSearch := ASearch;
  mActive := AActiveProject;
  TAtlasMainThread.ForceQueue(TAtlasFeature.UnitSearch,
    procedure
    var
      mLive: TLspSession;
    begin
      if Current <> mSearch then
      begin
        Exit;
      end;
      // Startet den Server bei Bedarf; der Befehl selbst läuft dann im Hintergrund.
      mLive := TAtlasIdeUnitSearchActions.Session;
      if (mLive = nil) or not TAtlasIdeUnitSearchActions.LoadEntries(mActive, EntriesArrived(mSearch, mLive)) then
      begin
        TAtlasIdeUnitSearchActions.Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchNoServer));
      end;
    end);
end;

procedure OpenSearch(AMode: TAtlasUnitSearchMode; const ATargetFile: string);
var
  mOptions: TAtlasUnitSearchOptions;
  mSearch: TOpenSearch;
begin
  mOptions := OptionsFor(AMode, ATargetFile);
  mSearch := TOpenSearch.Create;
  mSearch.Mode := AMode;
  mSearch.State := TAtlasUnitSearchState.Create;
  // Fehlt, unbrauchbar oder gesperrt: Vorgaben; TAtlasDataFile legt Unbrauchbares beiseite und protokolliert
  // ohne Pfad, eine gesperrte Datei schreibt SaveToFile nicht.
  mSearch.State.LoadFromFile(TAtlasIdeUnitSearch.StateFile);
  mSearch.Target := ATargetFile;
  mSearch.Window := TAtlasUnitSearchWindow.CreateSearch(Application, mOptions, mSearch.State,
    TAtlasIdeStyle.Colors);
  Current := mSearch;
  WireEvents(mSearch);
  mSearch.Window.ShowOver(Screen.MonitorFromWindow(GetForegroundWindow).WorkareaRect);
  LoadLater(mSearch, mOptions.ActiveProject);
end;

class procedure TAtlasIdeUnitSearch.Show(AMode: TAtlasUnitSearchMode; AFallback: Boolean);
var
  mTargetFile: string;
begin
  // Abgeschaltet: der Dialog der IDE übernimmt.
  if not Settings.UnitSearchEnabled then
  begin
    ShowIdeDialog(AMode);
    Exit;
  end;
  if Session = nil then
  begin
    Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchNoServer));
    if AFallback then
    begin
      ShowIdeDialog(AMode);
    end;
    Exit;
  end;
  mTargetFile := TopFile;
  if (AMode = TAtlasUnitSearchMode.UseUnit) and not TAtlasIdeUnitSearchActions.UsesTarget(mTargetFile) then
  begin
    Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchUsesNone));
    Exit;
  end;
  if not BringCurrentToFront(AMode, mTargetFile) then
  begin
    OpenSearch(AMode, mTargetFile);
  end;
end;

end.
