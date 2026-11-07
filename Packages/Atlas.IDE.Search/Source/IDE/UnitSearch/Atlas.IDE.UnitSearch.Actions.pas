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
  cUnitsCommand = 'atlas.server.units';
  cPreviewCommand = 'atlas.server.unitPreview';
  cAddUsesCommand = 'atlas.server.addUses';
  cTestUnitCommand = 'atlas.server.testUnit';
  // Die Liste kann bei großen Bibliotheken dauern; die Vorschau soll das Tippen nicht aufhalten.
  cUnitsTimeoutMs = 30000;
  cPreviewTimeoutMs = 5000;
  cCommandTimeoutMs = 30000;
  cProjectManagerActionName = 'ViewPrjMgrCommand';

function UriToPath(AUri: string): string;
begin
  Result := TLspSession.UriToPath(AUri);
end;

function OpenModules: TArray<string>;
var
  mServices: IOTAModuleServices;
  mIndex: Integer;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    for mIndex := 0 to mServices.ModuleCount - 1 do
    begin
      Result := Result + [mServices.Modules[mIndex].FileName];
    end;
  end;
end;

procedure MarkOpen(var AEntries: TAtlasUnitEntries);
var
  mFiles: TDictionary<string, Boolean>;
  mFileName: string;
  mIndex: Integer;
begin
  mFiles := TDictionary<string, Boolean>.Create;
  try
    for mFileName in OpenModules do
    begin
      mFiles.AddOrSetValue(LowerCase(mFileName), True);
    end;
    for mIndex := 0 to High(AEntries) do
    begin
      AEntries[mIndex].IsOpen := mFiles.ContainsKey(LowerCase(AEntries[mIndex].FileName));
    end;
  finally
    mFiles.Free;
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
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mIndex: Integer;
  mFormEditor: IOTAFormEditor;
begin
  Result := False;
  if not TAtlasIdeNavigation.ShowFile(AFileName) or not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mModule := mModules.FindModule(AFileName);
  if mModule = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mModule.ModuleFileCount - 1 do
  begin
    if Supports(mModule.ModuleFileEditors[mIndex], IOTAFormEditor, mFormEditor) then
    begin
      mFormEditor.Show;
      Exit(True);
    end;
  end;
end;

function UnitList(const AEntries: TArray<TAtlasUnitEntry>): string;
var
  mEntry: TAtlasUnitEntry;
begin
  Result := '';
  for mEntry in AEntries do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + mEntry.Name;
  end;
end;

/// <summary>Der Server braucht den Text des Puffers, nicht den der Platte.</summary>
procedure SyncBuffer(ALive: TLspSession; const AFileName: string);
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mIndex: Integer;
  mEditor: IOTASourceEditor;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mModule := mModules.FindModule(AFileName);
  if mModule = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mModule.ModuleFileCount - 1 do
  begin
    if Supports(mModule.ModuleFileEditors[mIndex], IOTASourceEditor, mEditor) and (mEditor.EditViewCount > 0) then
    begin
      ALive.Sync(AFileName, TAtlasEditorBuffer.Text(mEditor.EditViews[0].Buffer));
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
  mServices: INTAServices;
  mIndex: Integer;
begin
  Result := False;
  if not Supports(BorlandIDEServices, INTAServices, mServices) or (mServices.ActionList = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ActionList.ActionCount - 1 do
  begin
    if SameText(mServices.ActionList.Actions[mIndex].Name, AName) then
    begin
      Exit(mServices.ActionList.Actions[mIndex].Execute);
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
    mAnswer := ALive.RunCommand(cUnitsCommand,
      TAtlasUnitSearch.UnitsArguments(TAtlasIdeSettings.Current.UnitSearchFormCaptions), cUnitsTimeoutMs);
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
    mAnswer := mLive.RunCommand(cPreviewCommand, PreviewArguments(AEntry.FileName), cPreviewTimeoutMs);
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
  mAnswer: TJSONValue;
begin
  AInfo := Default(TAtlasUseUnitInfo);
  SyncBuffer(ALive, ATarget);
  try
    mAnswer := ALive.RunCommand(TAtlasUseUnit.cCommand, TAtlasUseUnit.Arguments(TLspSession.PathToUri(ATarget)),
      cCommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      Exit(False);
    end;
  end;
  try
    Result := (mAnswer <> nil) and TAtlasUseUnit.Parse(mAnswer.ToJSON, AInfo);
  finally
    mAnswer.Free;
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
    mAnswer := ALive.RunCommand(cTestUnitCommand, mArguments, cCommandTimeoutMs);
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
  mEntry: TAtlasUnitEntry;
begin
  Result := nil;
  for mEntry in AEntries do
  begin
    if mEntry.Kind <> TAtlasUnitKind.Include then
    begin
      Result := Result + [mEntry.Name];
    end;
  end;
end;

/// <summary>atlas.server.addUses mit AArguments ausführen und als ein Rückgängig-Schritt anwenden.</summary>
procedure RunAddUses(ALive: TLspSession; const AEntries: TArray<TAtlasUnitEntry>; const ATarget,
  AArguments: string);
var
  mAnswer, mEditValue, mAddedValue: TJSONValue;
  mEdit: TLspWorkspaceEdit;
  mOutcome: TAtlasWorkspaceEditResult;
  mAdded: Integer;
begin
  try
    mAnswer := ALive.RunCommand(cAddUsesCommand, AArguments, cCommandTimeoutMs);
  except
    on E: ELspClientError do
    begin
      TAtlasIdeUnitSearchActions.Say(TAtlasStrings.Fmt(TAtlasTextId.EditorFailed, [E.Message]));
      Exit;
    end;
  end;
  mAdded := 0;
  try
    mEdit := Default(TLspWorkspaceEdit);
    if mAnswer is TJSONObject then
    begin
      mEditValue := TJSONObject(mAnswer).GetValue('edit');
      mEdit := TLspWorkspaceEdit.FromJson(mEditValue);
      mAddedValue := TJSONObject(mAnswer).GetValue('added');
      if mAddedValue is TJSONArray then
      begin
        mAdded := TJSONArray(mAddedValue).Count;
      end;
    end;
  finally
    mAnswer.Free;
  end;
  if mEdit.IsEmpty then
  begin
    TAtlasIdeUnitSearchActions.Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchUsesAdded,
      [0, ExtractFileName(ATarget)]));
    Exit;
  end;
  mOutcome := TAtlasIdeWorkspaceEdit.Apply(mEdit,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits),
    TAtlasSearchStrings.Text(TAtlasSearchTextId.UnitSearchAddUses) + ': ' + UnitList(AEntries));
  if mOutcome.Error <> '' then
  begin
    TAtlasIdeUnitSearchActions.Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mOutcome.Error]));
  end
  else
  begin
    TAtlasIdeUnitSearchActions.Say(TAtlasSearchStrings.Fmt(TAtlasSearchTextId.UnitSearchUsesAdded,
      [mAdded, ExtractFileName(ATarget)]));
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
  mValues, mNames: TJSONArray;
  mName, mArguments: string;
  mLive: TLspSession;
begin
  mLive := AddUsesSession(ATarget);
  if mLive = nil then
  begin
    Exit;
  end;
  mValues := TJSONArray.Create;
  try
    mValues.Add(TLspSession.PathToUri(ATarget));
    mNames := TJSONArray.Create;
    for mName in UsesNames(AEntries) do
    begin
      mNames.Add(mName);
    end;
    mValues.AddElement(mNames);
    mArguments := mValues.ToJSON;
  finally
    mValues.Free;
  end;
  RunAddUses(mLive, AEntries, ATarget, mArguments);
end;

class procedure TAtlasIdeUnitSearchActions.UseUnits(const AEntries: TArray<TAtlasUnitEntry>; const ATarget: string;
  ASection: TAtlasUseUnitSection);
var
  mLive: TLspSession;
begin
  if Length(AEntries) = 0 then
  begin
    Say(TAtlasSearchStrings.Text(TAtlasSearchTextId.UseUnitNothing));
    Exit;
  end;
  mLive := AddUsesSession(ATarget);
  if mLive <> nil then
  begin
    RunAddUses(mLive, AEntries, ATarget, TAtlasUseUnit.AddUsesArguments(TLspSession.PathToUri(ATarget),
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
  TAtlasIdeUnitSearchActions.RunNamedAction(cProjectManagerActionName);
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
