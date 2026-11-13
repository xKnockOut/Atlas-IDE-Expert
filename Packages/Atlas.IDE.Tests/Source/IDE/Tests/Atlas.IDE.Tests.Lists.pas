unit Atlas.IDE.Tests.Lists;

// Testlisten im Fenster „Atlas-Tests“ (#2167, tests.lists) in der IDE:
// - Listen des gewählten Testprojekts: „im Projekt“ aus atlas.json neben der
//   .dproj (Schlüssel testLists, für das Team unter Versionsverwaltung) und
//   „nur für mich“ aus %LOCALAPPDATA%\Atlas\test-lists.json
//   (Atlas.Core.Tests.ListFile), dort auch die zuletzt ausgeführte Liste.
//   atlas.json wird gezielt geändert (TAtlasJsonText): Kommentare, Reihenfolge
//   und Kodierung bleiben.
// - Reiter, Kopfzeile und Menüs (Atlas.UI.Tests.ListBar); im Reiter einer
//   Liste zeigt der Baum nur ihre Tests (Atlas.Core.Tests.ListView), Filter
//   und Suche gelten weiter.
// - Ausführen: Kategorie-Regeln als --include/--exclude, sonst die Namen
//   (TAtlasTestListModel.RunArguments) über den Läufer; aus dem Reiter, der
//   Palette („Testliste ausführen: <Name>“) und mit tests.lists.runKey die
//   zuletzt benutzte Liste.
// Den Stand des Fensters (Testprojekt, Units, Knoten) liefert
// Atlas.IDE.Tests.Explorer über Connect; es findet die Listen über Instance.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Tests.Explorer,
  Atlas.Core.Tests.Lists,
  Atlas.Core.Tests.ListText,
  Atlas.IDE.Tests.Runner,
  Atlas.UI.Tests.ExplorerFrame;

type
  /// <summary>Stand des Fensters: Testprojekt (.dproj) und, wenn verlangt, Units und Knoten des Baums.</summary>
  TAtlasTestListSource = record
    Project: string;
    Units: TArray<TAtlasTestUnitInput>;
    Nodes: TArray<TAtlasTestNode>;
  end;

  /// <summary>Liefert den Stand; AWithUnits: auch Units und Knoten (liest die Testunits).</summary>
  TAtlasTestListSourceFunc = reference to function(AWithUnits: Boolean): TAtlasTestListSource;

  TAtlasIdeTestLists = class
  private const
    /// <summary>Höchstens so oft liest die Palette die Listen neu.</summary>
    cRefreshMs = 5000;
  private class var
    FInstance: TAtlasIdeTestLists;
  private
    FTests: TAtlasIdeTests;
    FSource: TAtlasTestListSourceFunc;
    FOnChanged: TProc;
    FProject: string;
    FLists: TAtlasTestLists;
    FLastRun: string;
    FCurrent: Integer;
    FLoadedAt: UInt64;
    procedure Load(const AProject: string);
    procedure LoadPersonal(out ALists: TAtlasTestLists; out ALastRun: string);
    function SaveProject: Boolean;
    function SavePersonal: Boolean;
    function Save(AStore: TAtlasTestListStore): Boolean;
    procedure Changed;
    procedure ShowLists;
    function Taken(AExcept: Integer): TArray<string>;
    function Edit(var AList: TAtlasTestList; ANew: Boolean; AExcept: Integer): Boolean;
    function SelectedNames(out ASource: TAtlasTestListSource): TArray<string>;
    procedure TabChosen(AIndex: Integer);
    procedure NewList;
    procedure EditList(AIndex: Integer);
    procedure Duplicate(AIndex: Integer);
    procedure DeleteList(AIndex: Integer);
    procedure AddTo(AIndex: Integer);
    procedure RemoveSelected;
    procedure Run(AIndex: Integer);
  public
    /// <summary>ATests gehört dem Aufrufer und lebt länger. Das Objekt ist bis zu seiner Freigabe Instance.
    /// </summary>
    constructor Create(ATests: TAtlasIdeTests);
    destructor Destroy; override;
    /// <summary>Testlisten gewünscht (tests.run und tests.lists)?</summary>
    class function Wanted: Boolean; static;
    /// <summary>Stand des Fensters und Meldung „Liste geändert“ (Baum neu zeigen); nil löst beides.</summary>
    procedure Connect(const ASource: TAtlasTestListSourceFunc; const AOnChanged: TProc);
    /// <summary>Listen des Testprojekts AProject neu lesen und im Fenster zeigen (Fenster neu eingelesen).</summary>
    procedure Refresh(const AProject: string);
    /// <summary>Reiter und Menüs von AFrame an diese Listen binden.</summary>
    procedure Wire(AFrame: TAtlasTestsExplorerFrame);
    /// <summary>Sichtbarkeit im Baum: im Reiter einer Liste nur ihre Tests (AVisible: Filter und Suche); setzt die
    /// Kopfzeile von AFrame.</summary>
    function Filter(AFrame: TAtlasTestsExplorerFrame; const AUnits: TArray<TAtlasTestUnitInput>;
      const ANodes: TArray<TAtlasTestNode>; const AVisible: TArray<Boolean>): TArray<Boolean>;
    /// <summary>Namen der Listen des Testprojekts (Palette); liest höchstens alle cRefreshMs neu.</summary>
    function Names: TArray<string>;
    /// <summary>Liste AName ausführen (Palette).</summary>
    procedure RunByName(const AName: string);
    /// <summary>Zuletzt benutzte Liste ausführen (Taste); False ohne eine.</summary>
    function RunLast: Boolean;
    /// <summary>tests.lists geändert: Reiter zeigen bzw. verbergen.</summary>
    procedure ApplySettings;
    /// <summary>Texte der Beschreibung in der Sprache der Oberfläche.</summary>
    class function Texts: TAtlasTestListTexts; static;
    /// <summary>Die Testlisten des Moduls (für das Fenster, das sonst ein Feld bräuchte); nil ohne.</summary>
    class property Instance: TAtlasIdeTestLists read FInstance;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.JSON,
  System.UITypes,
  Vcl.Dialogs,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Tests.ListFile,
  Atlas.Core.Tests.ListView,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Tests.ExplorerWindow,
  Atlas.UI.Tests.ListBar,
  Atlas.UI.Tests.ListDialog,
  Atlas.UI.Tests.Strings;

const
  cKind = 'Testlisten';

function PersonalFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasTestListFile.cFileName);
end;

function SettingsFile(const AProject: string): string;
begin
  Result := '';
  if AProject <> '' then
  begin
    Result := TPath.Combine(ExtractFileDir(AProject), TAtlasSettingsFiles.cProjectName);
  end;
end;

/// <summary>Einträge der Ablage „nur für mich“ (leer ohne Datei); Kept: vorhanden, aber nicht gelesen.</summary>
function ReadPersonal(out AProjects: TAtlasTestListProjects): TAtlasDataLoad;
var
  mProjects: TAtlasTestListProjects;
begin
  mProjects := nil;
  Result := TAtlasDataFile.Load(PersonalFile, cKind,
    function(const AText: string): Boolean
    begin
      mProjects := TAtlasTestListFile.Parse(AText);
      // ToJson schreibt immer "format"; ohne ist die Datei unbrauchbar.
      Result := TAtlasTestListFile.FormatOf(AText) >= 1;
    end);
  AProjects := mProjects;
end;

/// <summary>Darf die Ablage „nur für mich“ geschrieben werden? Nicht, wenn sie gesperrt oder nicht lesbar ist
/// oder eine neuere Fassung sie geschrieben hat.</summary>
function PersonalWritable(ALoad: TAtlasDataLoad): Boolean;
var
  mText: string;
begin
  Result := TAtlasDataFile.Writable(ALoad);
  if Result and TAtlasDataFile.TryRead(PersonalFile, mText) then
  begin
    Result := TAtlasTestListFile.FormatOf(mText) <= TAtlasTestListFile.cFormat;
  end;
end;

/// <summary>Listen aus atlas.json neben AProject.</summary>
function ProjectLists(const AProject: string): TAtlasTestLists;
var
  mHasBom: Boolean;
  mRoot: TJSONObject;
begin
  Result := nil;
  mRoot := TAtlasJsonText.Parse(TAtlasProjectSettings.ReadText(SettingsFile(AProject), mHasBom));
  try
    if mRoot <> nil then
    begin
      Result := TAtlasTestListModel.Parse(TAtlasJsonText.ValueAt(mRoot, TAtlasTestListModel.cKeyTestLists),
        TAtlasTestListStore.Project);
    end;
  finally
    mRoot.Free;
  end;
end;

{ TAtlasIdeTestLists }

constructor TAtlasIdeTestLists.Create(ATests: TAtlasIdeTests);
begin
  inherited Create;
  FTests := ATests;
  FCurrent := -1;
  FInstance := Self;
end;

destructor TAtlasIdeTestLists.Destroy;
begin
  if FInstance = Self then
  begin
    FInstance := nil;
  end;
  FSource := nil;
  FOnChanged := nil;
  inherited;
end;

class function TAtlasIdeTestLists.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestRun and TAtlasIdeSettings.Current.TestsLists;
end;

class function TAtlasIdeTestLists.Texts: TAtlasTestListTexts;
begin
  Result := Default(TAtlasTestListTexts);
  Result.Rules[TAtlasTestListRuleKind.Category, False] := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsCategoryIs);
  Result.Rules[TAtlasTestListRuleKind.Category, True] :=
    TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsCategoryIsNot);
  Result.Rules[TAtlasTestListRuleKind.Pattern, False] := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsUnitMatches);
  Result.Rules[TAtlasTestListRuleKind.Pattern, True] :=
    TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsUnitMatchesNot);
  Result.Rules[TAtlasTestListRuleKind.State, False] := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsStateIs);
  Result.Rules[TAtlasTestListRuleKind.State, True] := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsStateIsNot);
  Result.States[TAtlasTestListState.Failed] := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsStateFailed);
  Result.States[TAtlasTestListState.NotRun] := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsStateNotRun);
  Result.States[TAtlasTestListState.Stale] := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsStateStale);
  Result.AndText := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsAnd);
  Result.Fixed := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsFixed);
end;

procedure TAtlasIdeTestLists.Connect(const ASource: TAtlasTestListSourceFunc; const AOnChanged: TProc);
begin
  FSource := ASource;
  FOnChanged := AOnChanged;
end;

procedure TAtlasIdeTestLists.LoadPersonal(out ALists: TAtlasTestLists; out ALastRun: string);
var
  mProjects: TAtlasTestListProjects;
  mIndex: Integer;
begin
  ALists := nil;
  ALastRun := '';
  ReadPersonal(mProjects);
  mIndex := TAtlasTestListFile.IndexOf(mProjects, FProject);
  if mIndex >= 0 then
  begin
    ALists := mProjects[mIndex].Lists;
    ALastRun := mProjects[mIndex].LastRun;
  end;
end;

procedure TAtlasIdeTestLists.Load(const AProject: string);
var
  mCurrent: string;
  mPersonal: TAtlasTestLists;
  mList: TAtlasTestList;
begin
  // Der gewählte Reiter bleibt über den Namen, auch wenn Listen dazukommen.
  mCurrent := '';
  if (FCurrent >= 0) and (FCurrent <= High(FLists)) and SameText(AProject, FProject) then
  begin
    mCurrent := FLists[FCurrent].Name;
  end;
  FProject := AProject;
  FLists := nil;
  FLastRun := '';
  FLoadedAt := GetTickCount64;
  if (FProject = '') or not Wanted then
  begin
    FCurrent := -1;
    Exit;
  end;
  FLists := ProjectLists(FProject);
  LoadPersonal(mPersonal, FLastRun);
  // Gleichnamige eigene Listen treten hinter die des Projekts zurück.
  for mList in mPersonal do
  begin
    if TAtlasTestListModel.IndexOf(FLists, mList.Name) < 0 then
    begin
      FLists := FLists + [mList];
    end;
  end;
  FCurrent := TAtlasTestListModel.IndexOf(FLists, mCurrent);
end;

function TAtlasIdeTestLists.SaveProject: Boolean;
var
  mFile, mJson, mText: string;
  mContent: TAtlasTextFileContent;
  mLists: TAtlasTestLists;
begin
  mFile := SettingsFile(FProject);
  mContent := Default(TAtlasTextFileContent);
  mContent.Encoding := TAtlasTextEncoding.Utf8;
  if TFile.Exists(mFile) then
  begin
    mContent := TAtlasTextFile.Load(mFile);
  end;
  mLists := TAtlasTestListModel.OfStore(FLists, TAtlasTestListStore.Project);
  if Length(mLists) = 0 then
  begin
    mText := TAtlasJsonText.Remove(mContent.Text, TAtlasTestListModel.cKeyTestLists);
  end
  else
  begin
    // Zeilenenden wie in der Datei; neue Datei mit CRLF.
    mJson := TAtlasTestListModel.ToJson(mLists, '  ');
    if mContent.Text <> '' then
    begin
      mJson := mJson.Replace(#13#10, TTextLines.LineBreakOf(mContent.Text));
    end;
    mText := TAtlasJsonText.SetValue(mContent.Text, TAtlasTestListModel.cKeyTestLists, mJson);
  end;
  Result := True;
  if mText <> mContent.Text then
  begin
    mContent.Text := mText;
    TAtlasTextFile.Save(mFile, mContent);
  end;
end;

function TAtlasIdeTestLists.SavePersonal: Boolean;
var
  mProjects: TAtlasTestListProjects;
  mEntry: TAtlasTestListProject;
begin
  Result := PersonalWritable(ReadPersonal(mProjects));
  if not Result then
  begin
    Exit;
  end;
  mEntry := Default(TAtlasTestListProject);
  mEntry.Project := FProject;
  mEntry.LastRun := FLastRun;
  mEntry.Lists := TAtlasTestListModel.OfStore(FLists, TAtlasTestListStore.Personal);
  TAtlasTestListFile.Put(mProjects, mEntry);
  TAtlasDataFile.Write(PersonalFile, TAtlasTestListFile.ToJson(mProjects));
end;

function TAtlasIdeTestLists.Save(AStore: TAtlasTestListStore): Boolean;
begin
  Result := False;
  if FProject = '' then
  begin
    Exit;
  end;
  try
    if AStore = TAtlasTestListStore.Project then
    begin
      Result := SaveProject;
    end
    else
    begin
      Result := SavePersonal;
    end;
  except
    on E: Exception do
    begin
      TAtlasDataFile.ReportNotWritten(cKind, E);
      FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ListsSaveFailed, [E.Message]));
    end;
  end;
end;

procedure TAtlasIdeTestLists.Changed;
begin
  ShowLists;
  if Assigned(FOnChanged) then
  begin
    FOnChanged();
  end;
end;

procedure TAtlasIdeTestLists.ShowLists;
var
  mFrame: TAtlasTestsExplorerFrame;
  mTabs: TArray<TAtlasTestsListTab>;
  mIndex: Integer;
begin
  mFrame := TAtlasIdeTestsExplorerWindow.ExistingFrame;
  if mFrame = nil then
  begin
    Exit;
  end;
  mFrame.ListBar.SetActive(Wanted);
  SetLength(mTabs, Length(FLists));
  for mIndex := 0 to High(FLists) do
  begin
    mTabs[mIndex].Caption := FLists[mIndex].Name;
    mTabs[mIndex].InProject := FLists[mIndex].Store = TAtlasTestListStore.Project;
    mTabs[mIndex].Fixed := not FLists[mIndex].IsDynamic;
  end;
  mFrame.ListBar.SetLists(mTabs, FCurrent);
end;

procedure TAtlasIdeTestLists.Refresh(const AProject: string);
begin
  Load(AProject);
  ShowLists;
end;

procedure TAtlasIdeTestLists.Wire(AFrame: TAtlasTestsExplorerFrame);
var
  mHandlers: TAtlasTestsListHandlers;
begin
  mHandlers := Default(TAtlasTestsListHandlers);
  mHandlers.OnTab := TabChosen;
  mHandlers.OnNew := NewList;
  mHandlers.OnEdit := EditList;
  mHandlers.OnDuplicate := Duplicate;
  mHandlers.OnDelete := DeleteList;
  mHandlers.OnRun := Run;
  mHandlers.OnAddTo := AddTo;
  mHandlers.OnRemove := RemoveSelected;
  AFrame.ListBar.Handlers := mHandlers;
  AFrame.ListBar.SetActive(Wanted);
end;

procedure TAtlasIdeTestLists.ApplySettings;
begin
  if not Wanted then
  begin
    FCurrent := -1;
  end;
  Load(FProject);
  Changed;
end;

function TAtlasIdeTestLists.Filter(AFrame: TAtlasTestsExplorerFrame; const AUnits: TArray<TAtlasTestUnitInput>;
  const ANodes: TArray<TAtlasTestNode>; const AVisible: TArray<Boolean>): TArray<Boolean>;
const
  cStores: array[TAtlasTestListStore] of TAtlasTestsTextId = (TAtlasTestsTextId.ListsStoreProject,
    TAtlasTestsTextId.ListsStorePersonal);
var
  mItems: TAtlasTestListItems;
  mMembers: TArray<Boolean>;
  mInList, mTotal: Integer;
  mList: TAtlasTestList;
begin
  Result := AVisible;
  if not Wanted or (FCurrent < 0) or (FCurrent > High(FLists)) then
  begin
    Exit;
  end;
  mList := FLists[FCurrent];
  mItems := TAtlasTestListView.Items(AUnits, ANodes);
  mMembers := TAtlasTestListModel.Members(mList, mItems);
  TAtlasTestListModel.Count(mItems, mMembers, mInList, mTotal);
  AFrame.ListBar.SetHeader(TAtlasTestListText.Describe(mList, Texts) + ' · ' +
    TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ListsCount, [mInList, mTotal]) + ' · ' +
    TAtlasTestsStrings.Text(cStores[mList.Store]));
  Result := TAtlasTestListView.Visible(ANodes, AVisible, mItems, mMembers);
end;

function TAtlasIdeTestLists.Names: TArray<string>;
var
  mList: TAtlasTestList;
begin
  Result := nil;
  if not Wanted or not Assigned(FSource) then
  begin
    Exit;
  end;
  if GetTickCount64 - FLoadedAt > cRefreshMs then
  begin
    Load(FSource(False).Project);
  end;
  for mList in FLists do
  begin
    Result := Result + [mList.Name];
  end;
end;

procedure TAtlasIdeTestLists.TabChosen(AIndex: Integer);
begin
  FCurrent := AIndex;
  if Assigned(FOnChanged) then
  begin
    FOnChanged();
  end;
end;

function TAtlasIdeTestLists.Taken(AExcept: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(FLists) do
  begin
    if mIndex <> AExcept then
    begin
      Result := Result + [FLists[mIndex].Name];
    end;
  end;
end;

function TAtlasIdeTestLists.Edit(var AList: TAtlasTestList; ANew: Boolean; AExcept: Integer): Boolean;
var
  mCategories: TArray<string>;
begin
  mCategories := nil;
  if Assigned(FSource) then
  begin
    mCategories := TAtlasTestListView.Categories(FSource(True).Units);
  end;
  Result := TAtlasTestsListDialog.Execute(AList, ANew, Taken(AExcept), mCategories, Texts);
end;

procedure TAtlasIdeTestLists.NewList;
var
  mList: TAtlasTestList;
begin
  mList := Default(TAtlasTestList);
  mList.Name := TAtlasTestListModel.UniqueName(FLists, TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsDefaultName));
  mList.Store := TAtlasTestListStore.Personal;
  if (FProject = '') or not Edit(mList, True, -1) then
  begin
    Exit;
  end;
  FLists := FLists + [mList];
  FCurrent := High(FLists);
  Save(mList.Store);
  Changed;
end;

procedure TAtlasIdeTestLists.EditList(AIndex: Integer);
var
  mList: TAtlasTestList;
  mOldStore: TAtlasTestListStore;
begin
  if (AIndex < 0) or (AIndex > High(FLists)) then
  begin
    Exit;
  end;
  mList := FLists[AIndex];
  mOldStore := mList.Store;
  if not Edit(mList, False, AIndex) then
  begin
    Exit;
  end;
  FLists[AIndex] := mList;
  // In die andere Ablage verschoben: beide schreiben.
  if mOldStore <> mList.Store then
  begin
    Save(mOldStore);
  end;
  Save(mList.Store);
  Changed;
end;

procedure TAtlasIdeTestLists.Duplicate(AIndex: Integer);
var
  mList: TAtlasTestList;
begin
  if (AIndex < 0) or (AIndex > High(FLists)) then
  begin
    Exit;
  end;
  mList := FLists[AIndex];
  mList.Name := TAtlasTestListModel.UniqueName(FLists, mList.Name);
  // Eine Kopie gehört zuerst nur mir; ins Projekt kommt sie über „Umbenennen …“.
  mList.Store := TAtlasTestListStore.Personal;
  FLists := FLists + [mList];
  FCurrent := High(FLists);
  Save(mList.Store);
  Changed;
end;

procedure TAtlasIdeTestLists.DeleteList(AIndex: Integer);
var
  mStore: TAtlasTestListStore;
begin
  if (AIndex < 0) or (AIndex > High(FLists)) or (MessageDlg(TAtlasTestsStrings.Fmt(
    TAtlasTestsTextId.ListsDeleteConfirm, [FLists[AIndex].Name]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
  begin
    Exit;
  end;
  mStore := FLists[AIndex].Store;
  Delete(FLists, AIndex, 1);
  FCurrent := -1;
  Save(mStore);
  Changed;
end;

function TAtlasIdeTestLists.SelectedNames(out ASource: TAtlasTestListSource): TArray<string>;
var
  mFrame: TAtlasTestsExplorerFrame;
begin
  Result := nil;
  ASource := Default(TAtlasTestListSource);
  mFrame := TAtlasIdeTestsExplorerWindow.ExistingFrame;
  if (mFrame = nil) or not Assigned(FSource) then
  begin
    Exit;
  end;
  ASource := FSource(True);
  Result := TAtlasTestListView.Names(ASource.Nodes, mFrame.SelectedNodes);
  if Length(Result) = 0 then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.ExplorerNothingSelected));
  end;
end;

procedure TAtlasIdeTestLists.AddTo(AIndex: Integer);
var
  mSource: TAtlasTestListSource;
  mNames: TArray<string>;
  mList: TAtlasTestList;
begin
  mNames := SelectedNames(mSource);
  if Length(mNames) = 0 then
  begin
    Exit;
  end;
  if AIndex < 0 then
  begin
    // „Neue Liste …“: feste Liste mit der Auswahl.
    mList := Default(TAtlasTestList);
    mList.Name := TAtlasTestListModel.UniqueName(FLists,
      TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsDefaultName));
    mList.Store := TAtlasTestListStore.Personal;
    if not Edit(mList, False, -1) then
    begin
      Exit;
    end;
    FLists := FLists + [mList];
    AIndex := High(FLists);
  end;
  if (AIndex > High(FLists)) or FLists[AIndex].IsDynamic then
  begin
    Exit;
  end;
  TAtlasTestListModel.AddTests(FLists[AIndex], mNames);
  Save(FLists[AIndex].Store);
  Changed;
end;

procedure TAtlasIdeTestLists.RemoveSelected;
var
  mSource: TAtlasTestListSource;
  mNames: TArray<string>;
begin
  if (FCurrent < 0) or (FCurrent > High(FLists)) or FLists[FCurrent].IsDynamic then
  begin
    Exit;
  end;
  mNames := SelectedNames(mSource);
  if TAtlasTestListModel.RemoveTests(FLists[FCurrent], mNames) > 0 then
  begin
    Save(FLists[FCurrent].Store);
    Changed;
  end;
end;

procedure TAtlasIdeTestLists.Run(AIndex: Integer);
var
  mSource: TAtlasTestListSource;
  mItems: TAtlasTestListItems;
  mArguments: TArray<string>;
  mList: TAtlasTestList;
begin
  if not Wanted or (AIndex < 0) or (AIndex > High(FLists)) or not Assigned(FSource) then
  begin
    Exit;
  end;
  mList := FLists[AIndex];
  mSource := FSource(True);
  if Length(mSource.Units) = 0 then
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ListsEmpty, [mList.Name]));
    Exit;
  end;
  mItems := TAtlasTestListView.Items(mSource.Units, mSource.Nodes);
  case TAtlasTestListModel.RunArguments(mList, mItems, TAtlasTestListView.Units(mSource.Units), mArguments) of
    TAtlasTestListRun.Empty:
      FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ListsEmpty, [mList.Name]));
    TAtlasTestListRun.TooLong:
      FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ListsTooLong, [mList.Name]));
  else
    FLastRun := mList.Name;
    Save(TAtlasTestListStore.Personal);
    // Eine Testunit des Projekts bestimmt das Testprojekt wie bei „Ausgewählte ausführen“.
    FTests.RunTests(mSource.Units[0].FileName, mArguments);
  end;
end;

procedure TAtlasIdeTestLists.RunByName(const AName: string);
begin
  if Assigned(FSource) then
  begin
    Load(FSource(False).Project);
  end;
  Run(TAtlasTestListModel.IndexOf(FLists, AName));
end;

function TAtlasIdeTestLists.RunLast: Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  if not Wanted or not Assigned(FSource) then
  begin
    Exit;
  end;
  Load(FSource(False).Project);
  mIndex := TAtlasTestListModel.IndexOf(FLists, FLastRun);
  if mIndex >= 0 then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        Run(mIndex);
      end);
    Result := True;
  end;
end;

end.
