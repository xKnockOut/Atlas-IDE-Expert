unit Atlas.IDE.Bookmarks.Composition.Todos;

// TODO-Liste des aktiven Projekts (#68), aus Atlas.IDE.Bookmarks.Composition
// gelöst: fragt den Server über TAtlasIdeHost im Scope des Moduls (seine
// Antwort erreicht das Modul nur, solange es angemeldet ist, Regel 3) und
// zeigt die Einträge im Ergebnisfenster. Nur im Hauptthread.

interface

uses
  Atlas.Core.Modules.Contract;

/// <summary>Alle TODOs des aktiven Projekts.</summary>
procedure AllProjectTodos(const AScope: IAtlasModuleScope);
/// <summary>Filterdialog der TODO-Liste mit dem letzten Filter; „Anzeigen“ fragt mit dem neuen Filter.</summary>
procedure FilterProjectTodos(const AScope: IAtlasModuleScope);

implementation

uses
  System.SysUtils,
  System.JSON,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Results.Model,
  Atlas.Core.Projects.Todos,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.UI.Todos.Dialog,
  Atlas.UI.Bookmarks.Strings;

const
  TodosCommand = 'atlas.server.todos';
  TodosTimeoutMs = 120000;

var
  /// <summary>Letzter Filter der TODO-Liste (#68) in dieser Sitzung; Vorgabe für den Filterdialog.</summary>
  GTodoFilter: TAtlasTodoFilter;
  /// <summary>Vorschläge für den Filterdialog aus der letzten Liste.</summary>
  GTodoChoices: TAtlasTodoChoices;

/// <summary>Argumente für atlas.server.todos im Modus json: [uri, "json", filter].</summary>
function TodoArguments(const AProject: string; const AFilter: TAtlasTodoFilter): string;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TLspSession.PathToUri(AProject));
    mArguments.Add('json');
    mArguments.AddElement(TJSONObject.ParseJSONValue(AFilter.ToJson));
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

/// <summary>Antwort des Servers zur TODO-Liste im Ergebnisfenster zeigen (Hauptthread).</summary>
procedure ShowTodos(const AAnswer, AName, ADescribed: string; const AFilter: TAtlasTodoFilter);
var
  mEntries: TArray<TAtlasResultEntry>;
  mChoices: TAtlasTodoChoices;
begin
  if not TAtlasTodoList.Entries(AAnswer, mEntries) then
  begin
    TAtlasIdeHost.Warning(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoListFailed));
    Exit;
  end;
  // Vorschläge nur aus der ungefilterten Liste: sonst schrumpfen sie mit jedem Filter.
  if AFilter.IsEmpty and TAtlasTodoList.Choices(AAnswer, mChoices) then
  begin
    GTodoChoices := mChoices;
  end;
  if (Length(mEntries) = 0) and (ADescribed = '') then
  begin
    TAtlasIdeHost.Warning(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.TodoListEmpty, [AName]));
  end
  else if Length(mEntries) = 0 then
  begin
    TAtlasIdeHost.Warning(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.TodoListNoMatch, [AName, ADescribed]));
  end
  else if ADescribed = '' then
  begin
    TAtlasIdeResultsWindow.ShowEntries(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.TodoListTitle,
      [AName, Length(mEntries)]), mEntries);
  end
  else
  begin
    TAtlasIdeResultsWindow.ShowEntries(TAtlasBookmarksStrings.Fmt(TAtlasBookmarksTextId.TodoListFilteredTitle,
      [AName, ADescribed, Length(mEntries)]), mEntries);
  end;
end;

/// <summary>Rückruf der TODO-Liste; eigene Routine, damit er nur seine Werte festhält.</summary>
function TodosDone(const AName, ADescribed: string; const AFilter: TAtlasTodoFilter): TProc<string>;
begin
  Result :=
    procedure(AAnswer: string)
    begin
      ShowTodos(AAnswer, AName, ADescribed, AFilter);
    end;
end;

/// <summary>TODO-Liste des aktiven Projekts (#68) im Ergebnisfenster: Daten vom Server (startet ihn bei Bedarf) im
/// Hintergrund mit dem Filter AFilter (Filter des Servers), nach Unit gruppiert; Doppelklick springt zum
/// Kommentar.</summary>
procedure ProjectTodos(const AScope: IAtlasModuleScope; const AFilter: TAtlasTodoFilter);
var
  mProject: IOTAProject;
  mName, mDescribed: string;
  mFilter: TAtlasTodoFilter;
begin
  // Abgeschaltet: auch über Tastenkürzel oder „Ausprobieren“ nichts tun.
  if (AScope = nil) or not TAtlasIdeSettings.Current.TodoList then
  begin
    Exit;
  end;
  mProject := GetActiveProject;
  if (mProject = nil) or (mProject.FileName = '') then
  begin
    TAtlasIdeHost.Warning(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoListNoProject));
    Exit;
  end;
  mName := ChangeFileExt(ExtractFileName(mProject.FileName), '');
  mFilter := AFilter.Trimmed;
  mDescribed := mFilter.Describe;
  if TAtlasIdeHost.ActiveSession = nil then
  begin
    TAtlasIdeHost.Warning(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoListFailed));
    Exit;
  end;
  if not TAtlasIdeHost.RunCommandAsync(AScope, TAtlasFeature.Palette, TodosCommand,
    TodoArguments(mProject.FileName, mFilter), TodosTimeoutMs, TodosDone(mName, mDescribed, mFilter)) then
  begin
    // Ein Befehl im Hintergrund läuft schon (etwa die Werte nach einem Build): später noch einmal.
    TAtlasIdeHost.Warning(TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.TodoListBusy));
  end;
end;

procedure AllProjectTodos(const AScope: IAtlasModuleScope);
begin
  ProjectTodos(AScope, Default(TAtlasTodoFilter));
end;

/// <summary>Filterdialog der TODO-Liste (#68) mit dem letzten Filter; „Anzeigen“ fragt mit dem neuen Filter.</summary>
procedure FilterProjectTodos(const AScope: IAtlasModuleScope);
var
  mFilter: TAtlasTodoFilter;
begin
  if not TAtlasIdeSettings.Current.TodoList then
  begin
    Exit;
  end;
  mFilter := GTodoFilter;
  if not TAtlasTodoFilterDialog.Execute(GTodoChoices, mFilter) then
  begin
    Exit;
  end;
  GTodoFilter := mFilter;
  ProjectTodos(AScope, mFilter);
end;

end.
