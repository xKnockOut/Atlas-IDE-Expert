unit Atlas.IDE.UnitSearch.Actions;

// Fenster „Units suchen“ (#777, #786) in der IDE: die Anfragen an den Server
// und die Aktionen des Fensters, ohne das Fenster selbst (das öffnet und
// verdrahtet Atlas.IDE.UnitSearch.Commands).
// - LoadEntries: Einträge über atlas.server.units, offene Module markiert.
// - Preview: Vorschau über atlas.server.unitPreview (Formularskizze und
//   „Verwendet von“ nach den Einstellungen).
// - LoadUseInfo: „schon in uses“ und Kreise der Zielunit (atlas.useUnitInfo).
// - Run: Öffnen, Formular öffnen, In uses aufnehmen (atlas.server.addUses),
//   Testunits öffnen (atlas.server.testUnit), Im Projektmanager zeigen, Im
//   Explorer zeigen. UseUnits fügt in einen gewählten Abschnitt ein.
// Meldungen nur als Zeile in der Meldungsansicht, nie als Dialog.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.Session,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.UseUnit,
  Atlas.UI.UnitSearch.Data;

type
  TAtlasIdeUnitSearchActions = class
  private class var
    FSessionOf: TFunc<TLspSession>;
    FMessage: TProc<string>;
  public
    /// <summary>ASessionOf: laufende Sitzung (Server bei Bedarf gestartet) oder nil; AMessage: Zeile für
    /// die Meldungsansicht.</summary>
    class procedure Install(const ASessionOf: TFunc<TLspSession>; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    class function Session: TLspSession; static;
    class procedure Say(const AText: string); static;
    /// <summary>Aktion der IDE mit dem Namen AName ausführen; False ohne.</summary>
    class function RunNamedAction(const AName: string): Boolean; static;
    /// <summary>Datei, in deren uses „Unit verwenden“ und „In uses aufnehmen“ einfügen können.</summary>
    class function UsesTarget(const AFileName: string): Boolean; static;
    /// <summary>Einträge vom Server, offene Module markiert; False mit Meldung ohne Antwort.</summary>
    class function LoadEntries(ALive: TLspSession; const AActiveProject: string;
      out AEntries: TAtlasUnitEntries): Boolean; static;
    /// <summary>Vorschau einer Unit; ohne Server oder Antwort nur der Dateiname.</summary>
    class function Preview(const AEntry: TAtlasUnitEntry): TAtlasUnitPreview; static;
    /// <summary>„schon in uses“ und Kreise der Zielunit (#786); False ohne Antwort.</summary>
    class function LoadUseInfo(ALive: TLspSession; const ATarget: string; out AInfo: TAtlasUseUnitInfo): Boolean;
      static;
    /// <summary>Aktion des Fensters für die gewählten Einträge; ATarget ist die Datei für „In uses aufnehmen“.
    /// </summary>
    class procedure Run(AAction: TAtlasUnitSearchAction; const AEntries: TArray<TAtlasUnitEntry>;
      const ATarget: string); static;
    /// <summary>„Unit verwenden“: Einträge in den Abschnitt ASection von ATarget aufnehmen.</summary>
    class procedure UseUnits(const AEntries: TArray<TAtlasUnitEntry>; const ATarget: string;
      ASection: TAtlasUseUnitSection); static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  System.JSON,
  System.Generics.Collections,
  Vcl.ActnList,
  ToolsAPI,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.TestUnit,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.UI.Strings,
  Atlas.UI.Search.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit;

const
  UnitsCommand = 'atlas.server.units';
  PreviewCommand = 'atlas.server.unitPreview';
  AddUsesCommand = 'atlas.server.addUses';
  TestUnitCommand = 'atlas.server.testUnit';
  // Die Liste kann bei großen Bibliotheken dauern; die Vorschau soll das Tippen nicht aufhalten.
  UnitsTimeoutMs = 30000;
  PreviewTimeoutMs = 5000;
  CommandTimeoutMs = 30000;
  ProjectManagerActionName = 'ViewPrjMgrCommand';

function UriToPath(AUri: string): string;
begin
  Result := TLspSession.UriToPath(AUri);
end;

function OpenModules: TArray<string>;
var
  Services: IOTAModuleServices;
  Index: Integer;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, Services) then
  begin
    for Index := 0 to Services.ModuleCount - 1 do
    begin
      Result := Result + [Services.Modules[Index].FileName];
    end;
  end;
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
    begin
      Files.AddOrSetValue(LowerCase(FileName), True);
    end;
    for Index := 0 to High(AEntries) do
    begin
      AEntries[Index].IsOpen := Files.ContainsKey(LowerCase(AEntries[Index].FileName));
    end;
  finally
    Files.Free;
  end;
end;

function FormFileOf(const AFileName: string): string;
begin
  Result := ChangeFileExt(AFileName, '.dfm');
  if FileExists(Result) then
  begin
    Exit;
  end;
  Result := ChangeFileExt(AFileName, '.fmx');
  if not FileExists(Result) then
  begin
    Result := '';
  end;
end;

function ShowForm(const AFileName: string): Boolean;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index: Integer;
  FormEditor: IOTAFormEditor;
begin
  Result := False;
  if not TAtlasIdeNavigation.ShowFile(AFileName) or not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Exit;
  end;
  Module := Modules.FindModule(AFileName);
  if Module = nil then
  begin
    Exit;
  end;
  for Index := 0 to Module.ModuleFileCount - 1 do
  begin
    if Supports(Module.ModuleFileEditors[Index], IOTAFormEditor, FormEditor) then
    begin
      FormEditor.Show;
      Exit(True);
    end;
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
    begin
      Result := Result + ', ';
    end;
    Result := Result + Entry.Name;
  end;
end;

/// <summary>Der Server braucht den Text des Puffers, nicht den der Platte.</summary>
procedure SyncBuffer(ALive: TLspSession; const AFileName: string);
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index: Integer;
  Editor: IOTASourceEditor;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
  begin
    Exit;
  end;
  Module := Modules.FindModule(AFileName);
  if Module = nil then
  begin
    Exit;
  end;
  for Index := 0 to Module.ModuleFileCount - 1 do
  begin
    if Supports(Module.ModuleFileEditors[Index], IOTASourceEditor, Editor) and (Editor.EditViewCount > 0) then
    begin
      ALive.Sync(AFileName, TAtlasEditorBuffer.Text(Editor.EditViews[0].Buffer));
      Exit;
    end;
  end;
end;

{ TAtlasIdeUnitSearchActions }

class procedure TAtlasIdeUnitSearchActions.Install(const ASessionOf: TFunc<TLspSession>;
  const AMessage: TProc<string>);
begin
  FSessionOf := ASessionOf;
  FMessage := AMessage;
end;

class procedure TAtlasIdeUnitSearchActions.Uninstall;
begin
  FSessionOf := nil;
  FMessage := nil;
end;

class function TAtlasIdeUnitSearchActions.Session: TLspSession;
begin
  Result := nil;
  if Assigned(FSessionOf) then
  begin
    Result := FSessionOf();
  end;
end;

class procedure TAtlasIdeUnitSearchActions.Say(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

class function TAtlasIdeUnitSearchActions.RunNamedAction(const AName: string): Boolean;
var
  Services: INTAServices;
  Index: Integer;
begin
  Result := False;
  if not Supports(BorlandIDEServices, INTAServices, Services) or (Services.ActionList = nil) then
  begin
    Exit;
  end;
  for Index := 0 to Services.ActionList.ActionCount - 1 do
  begin
    if SameText(Services.ActionList.Actions[Index].Name, AName) then
    begin
      Exit(Services.ActionList.Actions[Index].Execute);
    end;
  end;
end;

class function TAtlasIdeUnitSearchActions.UsesTarget(const AFileName: string): Boolean;
begin
  Result := (AFileName <> '') and (SameText(ExtractFileExt(AFileName), '.pas') or
    SameText(ExtractFileExt(AFileName), '.dpr') or SameText(ExtractFileExt(AFileName), '.dpk'));
end;

class function TAtlasIdeUnitSearchActions.LoadEntries(ALive: TLspSession; const AActiveProject: string;
  out AEntries: TAtlasUnitEntries): Boolean;
var
  mAnswer: TJSONValue;
begin
  AEntries := nil;
  try
    mAnswer := ALive.RunCommand(UnitsCommand,
      TAtlasUnitSearch.UnitsArguments(TAtlasIdeSettings.Current.UnitSearchFormCaptions), UnitsTimeoutMs);
  except
    on E: ELspClientError do
    begin
      Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit(False);
    end;
  end;
  try
    AEntries := TAtlasUnitSearch.FromJson(mAnswer, AActiveProject, UriToPath);
  finally
    mAnswer.Free;
  end;
  MarkOpen(AEntries);
  Result := True;
end;

/// <summary>Argumente von atlas.server.unitPreview: Uri und die gewünschten Teile.</summary>
function PreviewArguments(const AFileName: string): string;
var
  mArguments: TJSONArray;
  mFlags: TJSONObject;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TLspSession.PathToUri(AFileName));
    mFlags := TJSONObject.Create;
    mFlags.AddPair('form', TJSONBool.Create(TAtlasIdeSettings.Current.UnitSearchPreviewForm));
    mFlags.AddPair('usedBy', TJSONBool.Create(TAtlasIdeSettings.Current.UnitSearchPreviewUsedBy));
    mArguments.Add(mFlags);
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

class function TAtlasIdeUnitSearchActions.Preview(const AEntry: TAtlasUnitEntry): TAtlasUnitPreview;
var
  mAnswer: TJSONValue;
  mLive: TLspSession;
begin
  Result := Default(TAtlasUnitPreview);
  Result.FileName := AEntry.FileName;
  Result.UsedBy := -1;
  mLive := Session;
  if mLive = nil then
  begin
    Exit;
  end;
  try
    mAnswer := mLive.RunCommand(PreviewCommand, PreviewArguments(AEntry.FileName), PreviewTimeoutMs);
  except
    on E: ELspClientError do
    begin
      Exit;
    end;
  end;
  try
    Result := TAtlasUnitPreview.FromJson(mAnswer, UriToPath);
  finally
    mAnswer.Free;
  end;
end;

class function TAtlasIdeUnitSearchActions.LoadUseInfo(ALive: TLspSession; const ATarget: string;
  out AInfo: TAtlasUseUnitInfo): Boolean;
var
  Answer: TJSONValue;
begin
  AInfo := Default(TAtlasUseUnitInfo);
  SyncBuffer(ALive, ATarget);
  try
    Answer := ALive.RunCommand(TAtlasUseUnit.Command, TAtlasUseUnit.Arguments(TLspSession.PathToUri(ATarget)),
      CommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      Exit(False);
    end;
  end;
  try
    Result := (Answer <> nil) and TAtlasUseUnit.Parse(Answer.ToJSON, AInfo);
  finally
    Answer.Free;
  end;
end;

/// <summary>Testunit einer Unit über atlas.server.testUnit öffnen; False, wenn es nicht weitergehen soll (kein
/// Server, Fehler).</summary>
function OpenTestOf(ALive: TLspSession; const AEntry: TAtlasUnitEntry): Boolean;
var
  mValues: TJSONArray;
  mArguments: string;
  mAnswer: TJSONValue;
  mInfo: TAtlasTestUnitInfo;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(TLspSession.PathToUri(AEntry.FileName));
    mValues.Add(0);
    mArguments := mValues.ToJSON;
  finally
    mValues.Free;
  end;
  try
    mAnswer := ALive.RunCommand(TestUnitCommand, mArguments, CommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      TAtlasIdeUnitSearchActions.Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit(False);
    end;
  end;
  try
    mInfo := TAtlasTestUnitInfo.FromJson(mAnswer, UriToPath);
  finally
    mAnswer.Free;
  end;
  if mInfo.CounterpartFile <> '' then
  begin
    TAtlasIdeNavigation.GoToLocation(mInfo.CounterpartFile, 0, 0);
  end
  else
  begin
    TAtlasIdeUnitSearchActions.Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchNoTests, [AEntry.Name]));
  end;
  Result := True;
end;

procedure OpenTests(const AEntries: TArray<TAtlasUnitEntry>);
var
  mEntry: TAtlasUnitEntry;
  mLive: TLspSession;
begin
  for mEntry in AEntries do
  begin
    if mEntry.Kind = TAtlasUnitKind.Test then
    begin
      TAtlasIdeNavigation.GoToLocation(mEntry.FileName, 0, 0);
      Continue;
    end;
    mLive := TAtlasIdeUnitSearchActions.Session;
    if (mLive = nil) or not OpenTestOf(mLive, mEntry) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Namen ohne Include-Dateien.</summary>
function UsesNames(const AEntries: TArray<TAtlasUnitEntry>): TArray<string>;
var
  Entry: TAtlasUnitEntry;
begin
  Result := nil;
  for Entry in AEntries do
  begin
    if Entry.Kind <> TAtlasUnitKind.Include then
    begin
      Result := Result + [Entry.Name];
    end;
  end;
end;

/// <summary>atlas.server.addUses mit AArguments ausführen und als ein Rückgängig-Schritt anwenden.</summary>
procedure RunAddUses(ALive: TLspSession; const AEntries: TArray<TAtlasUnitEntry>; const ATarget,
  AArguments: string);
var
  Answer, EditValue, AddedValue: TJSONValue;
  Edit: TLspWorkspaceEdit;
  Outcome: TAtlasWorkspaceEditResult;
  Added: Integer;
begin
  try
    Answer := ALive.RunCommand(AddUsesCommand, AArguments, CommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      TAtlasIdeUnitSearchActions.Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
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
      begin
        Added := TJSONArray(AddedValue).Count;
      end;
    end;
  finally
    Answer.Free;
  end;
  if Edit.IsEmpty then
  begin
    TAtlasIdeUnitSearchActions.Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchUsesAdded,
      [0, ExtractFileName(ATarget)]));
    Exit;
  end;
  Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
    TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchAddUses) + ': ' + UnitList(AEntries));
  if Outcome.Error <> '' then
  begin
    TAtlasIdeUnitSearchActions.Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
  end
  else
  begin
    TAtlasIdeUnitSearchActions.Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchUsesAdded,
      [Added, ExtractFileName(ATarget)]));
  end;
end;

/// <summary>Sitzung für das Einfügen in ATarget, Puffer abgeglichen; nil mit Meldung.</summary>
function AddUsesSession(const ATarget: string): TLspSession;
begin
  Result := nil;
  if not TAtlasIdeUnitSearchActions.UsesTarget(ATarget) then
  begin
    TAtlasIdeUnitSearchActions.Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchUsesNone));
    Exit;
  end;
  Result := TAtlasIdeUnitSearchActions.Session;
  if Result = nil then
  begin
    TAtlasIdeUnitSearchActions.Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchNoServer));
    Exit;
  end;
  SyncBuffer(Result, ATarget);
end;

procedure AddUses(const AEntries: TArray<TAtlasUnitEntry>; const ATarget: string);
var
  Values, Names: TJSONArray;
  Name, Arguments: string;
  Live: TLspSession;
begin
  Live := AddUsesSession(ATarget);
  if Live = nil then
  begin
    Exit;
  end;
  Values := TJSONArray.Create;
  try
    Values.Add(TLspSession.PathToUri(ATarget));
    Names := TJSONArray.Create;
    for Name in UsesNames(AEntries) do
    begin
      Names.Add(Name);
    end;
    Values.AddElement(Names);
    Arguments := Values.ToJSON;
  finally
    Values.Free;
  end;
  RunAddUses(Live, AEntries, ATarget, Arguments);
end;

class procedure TAtlasIdeUnitSearchActions.UseUnits(const AEntries: TArray<TAtlasUnitEntry>; const ATarget: string;
  ASection: TAtlasUseUnitSection);
var
  Live: TLspSession;
begin
  if Length(AEntries) = 0 then
  begin
    Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.UseUnitNothing));
    Exit;
  end;
  Live := AddUsesSession(ATarget);
  if Live <> nil then
  begin
    RunAddUses(Live, AEntries, ATarget, TAtlasUseUnit.AddUsesArguments(TLspSession.PathToUri(ATarget),
      UsesNames(AEntries), ASection));
  end;
end;

procedure OpenForms(const AEntries: TArray<TAtlasUnitEntry>);
var
  mEntry: TAtlasUnitEntry;
begin
  for mEntry in AEntries do
  begin
    if (FormFileOf(mEntry.FileName) = '') or not ShowForm(mEntry.FileName) then
    begin
      TAtlasIdeUnitSearchActions.Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchNoForm, [mEntry.Name]));
    end;
  end;
end;

procedure ShowProjects(const AEntries: TArray<TAtlasUnitEntry>);
var
  mEntry: TAtlasUnitEntry;
  mProject: string;
begin
  // Die Open Tools API wählt keinen Knoten im Projektmanager aus: öffnen und das Projekt nennen.
  TAtlasIdeUnitSearchActions.RunNamedAction(ProjectManagerActionName);
  for mEntry in AEntries do
  begin
    mProject := string.Join(', ', mEntry.Projects);
    if mProject = '' then
    begin
      mProject := TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchNoProject);
    end;
    TAtlasIdeUnitSearchActions.Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchProjectOf,
      [mEntry.Name, mProject]));
  end;
end;

class procedure TAtlasIdeUnitSearchActions.Run(AAction: TAtlasUnitSearchAction;
  const AEntries: TArray<TAtlasUnitEntry>; const ATarget: string);
var
  mEntry: TAtlasUnitEntry;
begin
  if Length(AEntries) = 0 then
  begin
    Exit;
  end;
  case AAction of
    TAtlasUnitSearchAction.Open:
      for mEntry in AEntries do
      begin
        TAtlasIdeNavigation.GoToLocation(mEntry.FileName, 0, 0);
      end;
    TAtlasUnitSearchAction.OpenForm:
      OpenForms(AEntries);
    TAtlasUnitSearchAction.AddUses:
      AddUses(AEntries, ATarget);
    TAtlasUnitSearchAction.OpenTests:
      OpenTests(AEntries);
    TAtlasUnitSearchAction.ShowProject:
      ShowProjects(AEntries);
    TAtlasUnitSearchAction.ShowExplorer:
      ShellExecute(0, 'open', 'explorer.exe', PChar('/select,"' + AEntries[0].FileName + '"'), nil, SW_SHOWNORMAL);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

end.
