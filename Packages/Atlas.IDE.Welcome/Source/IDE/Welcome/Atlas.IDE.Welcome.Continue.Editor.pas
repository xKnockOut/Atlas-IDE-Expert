unit Atlas.IDE.Welcome.Continue.Editor;

// Zugriff des Bereichs „Weiterarbeiten“ (#755) auf Editor und Projekte der
// IDE: offene Reiter in der Reihenfolge des Editorfensters mit Cursorstelle
// und Methode, Ziel eines Projekts (gespeicherte Projektgruppe, sonst das
// Projekt), Öffnen von Projekt und Reiter, Text einer Datei (Puffer oder
// Platte). Abgeteilt aus Atlas.IDE.Welcome.Continue (Atlas-Befunde).

interface

uses
  System.Generics.Collections,
  Atlas.Core.Welcome.Continue;

type
  /// <summary>Offene Reiter in ihrer Reihenfolge mit der Cursorstelle und aktive Datei.</summary>
  TAtlasContinueSnapshot = record
    Tabs: TArray<TAtlasWorkTab>;
    Active: string;
  end;

  TAtlasIdeContinueEditor = class
  public
    /// <summary>Offene Reiter festhalten; AChanges (großgeschriebener Pfad → letzte Änderung) bekommt die
    /// Methode an der Änderungsstelle.</summary>
    class function TakeSnapshot(AChanges: TDictionary<string, TAtlasWorkTab>): TAtlasContinueSnapshot; static;
    class function ProjectOpen(const AFileName: string): Boolean; static;
    /// <summary>Gespeicherte Projektgruppe, zu der das Projekt AFileName gehört, sonst das Projekt.</summary>
    class function TargetOf(const AFileName: string): string; static;
    /// <summary>Ziel des offenen Projekts bzw. der offenen Gruppe; '' ohne.</summary>
    class function CurrentTarget: string; static;
    /// <summary>Projekt öffnen, wenn es existiert und noch nicht offen ist.</summary>
    class procedure EnsureProject(const AProject: string); static;
    /// <summary>Datei öffnen, Cursor an Zeile und Spalte des Reiters (ab 1).</summary>
    class procedure OpenTab(const ATab: TAtlasWorkTab); static;
    /// <summary>Offene Datei: der Text des Puffers; sonst die Platte.</summary>
    class function FileText(const AFileName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Files.TextFile,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Projects.Summaries;

type
  /// <summary>Quelltext-Puffer der offenen Reiter (großgeschriebener Pfad) mit Reiter und Dateiname.</summary>
  TOpenTabs = record
    Buffers: TDictionary<string, IOTAEditBuffer>;
    Files: TArray<string>;
    Tabs: TArray<TAtlasWorkTab>;
  end;

function IsPascal(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk') or (mExtension = '.inc');
end;

/// <summary>Beschriftungen eines Reiter-Steuerelements (veröffentlichte Eigenschaft „Tabs“ als TStrings).</summary>
function TabsOf(AComponent: TComponent): TArray<string>;
var
  mValue: TObject;
begin
  Result := nil;
  if (AComponent = nil) or not IsPublishedProp(AComponent, 'Tabs') or
    (PropType(AComponent, 'Tabs') <> tkClass) then
  begin
    Exit;
  end;
  mValue := GetObjectProp(AComponent, 'Tabs');
  if mValue is TStrings then
  begin
    Result := TStrings(mValue).ToStringArray;
  end;
end;

/// <summary>Formular des obersten Editorfensters; nil ohne.</summary>
function EditForm: TCustomForm;
var
  mServices: INTAEditorServices;
  mWindow: INTAEditWindow;
begin
  Result := nil;
  if Supports(BorlandIDEServices, INTAEditorServices, mServices) then
  begin
    mWindow := mServices.TopEditWindow;
    if mWindow <> nil then
    begin
      Result := mWindow.Form;
    end;
  end;
end;

function TabCaptions: TArray<string>;
var
  mForm: TCustomForm;
  mIndex: Integer;
begin
  // Das Editorfenster der IDE führt seine Reiter in einem Steuerelement „TabControl“ (TTabSet-Abkömmling); ohne
  // es gilt die Reihenfolge der Puffer.
  Result := nil;
  mForm := EditForm;
  if mForm = nil then
  begin
    Exit;
  end;
  Result := TabsOf(mForm.FindComponent('TabControl'));
  mIndex := 0;
  while (Length(Result) = 0) and (mIndex < mForm.ComponentCount) do
  begin
    Result := TabsOf(mForm.Components[mIndex]);
    Inc(mIndex);
  end;
end;

/// <summary>Reiter des Editors AEditor in AOpen aufnehmen (nur Quelltext mit Ansicht, jede Datei einmal).</summary>
procedure AddEditor(var AOpen: TOpenTabs; const AEditor: IOTAEditor);
var
  mSource: IOTASourceEditor;
  mBuffer: IOTAEditBuffer;
  mView: IOTAEditView;
  mName: string;
  mTab: TAtlasWorkTab;
begin
  if (AEditor = nil) or (AEditor.FileName = '') or AOpen.Buffers.ContainsKey(AnsiUpperCase(AEditor.FileName)) then
  begin
    Exit;
  end;
  if not Supports(AEditor, IOTASourceEditor, mSource) or (mSource.EditViewCount = 0) or
    not Supports(AEditor, IOTAEditBuffer, mBuffer) then
  begin
    Exit;
  end;
  mName := AEditor.FileName;
  AOpen.Buffers.Add(AnsiUpperCase(mName), mBuffer);
  mView := mBuffer.TopView;
  if mView = nil then
  begin
    mView := mSource.EditViews[0];
  end;
  mTab := TAtlasWorkTab.Create(mName, 0, 0);
  if mView <> nil then
  begin
    mTab := TAtlasWorkTab.Create(mName, mView.CursorPos.Line, mView.CursorPos.Col);
  end;
  AOpen.Files := AOpen.Files + [mName];
  AOpen.Tabs := AOpen.Tabs + [mTab];
end;

/// <summary>Offene Reiter: Quelltext-Editoren mit Ansicht.</summary>
procedure CollectTabs(const AModules: IOTAModuleServices; var AOpen: TOpenTabs);
var
  mModule: IOTAModule;
  mIndex, mFileIndex: Integer;
begin
  for mIndex := 0 to AModules.ModuleCount - 1 do
  begin
    mModule := AModules.Modules[mIndex];
    if mModule <> nil then
    begin
      for mFileIndex := 0 to mModule.ModuleFileCount - 1 do
      begin
        AddEditor(AOpen, mModule.ModuleFileEditors[mFileIndex]);
      end;
    end;
  end;
end;

/// <summary>AOpen.Tabs in der Reihenfolge der Reiter im Editorfenster.</summary>
function OrderedTabs(const AOpen: TOpenTabs): TArray<TAtlasWorkTab>;
var
  mName: string;
  mTab: TAtlasWorkTab;
begin
  Result := nil;
  for mName in TAtlasWelcomeContinue.OrderByTabs(AOpen.Files, TabCaptions) do
  begin
    for mTab in AOpen.Tabs do
    begin
      if SameText(mTab.FileName, mName) then
      begin
        Result := Result + [mTab];
        Break;
      end;
    end;
  end;
end;

/// <summary>Methode an der letzten Änderung bzw. (aktiver Reiter) am Cursor, aus dem Text des Puffers.</summary>
procedure AddMethods(var ASnapshot: TAtlasContinueSnapshot; const AOpen: TOpenTabs;
  AChanges: TDictionary<string, TAtlasWorkTab>);
var
  mBuffer: IOTAEditBuffer;
  mChange: TAtlasWorkTab;
  mPosition: Integer;
  mKey, mText: string;
begin
  for mPosition := 0 to High(ASnapshot.Tabs) do
  begin
    mKey := AnsiUpperCase(ASnapshot.Tabs[mPosition].FileName);
    if not IsPascal(mKey) or not AOpen.Buffers.TryGetValue(mKey, mBuffer) then
    begin
      Continue;
    end;
    mText := '';
    if AChanges.TryGetValue(mKey, mChange) then
    begin
      mText := TAtlasEditorBuffer.Text(mBuffer);
      mChange.Method := TAtlasWelcomeContinue.MethodAt(mText, mChange.Line);
      AChanges.AddOrSetValue(mKey, mChange);
    end;
    if SameText(ASnapshot.Tabs[mPosition].FileName, ASnapshot.Active) then
    begin
      if mText = '' then
      begin
        mText := TAtlasEditorBuffer.Text(mBuffer);
      end;
      ASnapshot.Tabs[mPosition].Method := TAtlasWelcomeContinue.MethodAt(mText, ASnapshot.Tabs[mPosition].Line);
    end;
  end;
end;

{ TAtlasIdeContinueEditor }

class function TAtlasIdeContinueEditor.TakeSnapshot(
  AChanges: TDictionary<string, TAtlasWorkTab>): TAtlasContinueSnapshot;
var
  mModules: IOTAModuleServices;
  mEditors: IOTAEditorServices;
  mOpen: TOpenTabs;
begin
  Result := Default(TAtlasContinueSnapshot);
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mOpen := Default(TOpenTabs);
  mOpen.Buffers := TDictionary<string, IOTAEditBuffer>.Create;
  try
    CollectTabs(mModules, mOpen);
    Result.Tabs := OrderedTabs(mOpen);
    if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) and (mEditors.TopBuffer <> nil) then
    begin
      Result.Active := mEditors.TopBuffer.FileName;
    end;
    AddMethods(Result, mOpen, AChanges);
  finally
    mOpen.Buffers.Free;
  end;
end;

class function TAtlasIdeContinueEditor.ProjectOpen(const AFileName: string): Boolean;
var
  mModules: IOTAModuleServices;
begin
  Result := Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.FindModule(AFileName) <> nil);
end;

/// <summary>Gespeicherte Hauptprojektgruppe der IDE; nil ohne (die Vorgabegruppe liegt nicht auf der Platte).
/// </summary>
function SavedGroup: IOTAProjectGroup;
var
  mModules: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Result := mModules.MainProjectGroup;
  end;
  if (Result <> nil) and ((Result.FileName = '') or not FileExists(Result.FileName)) then
  begin
    Result := nil;
  end;
end;

class function TAtlasIdeContinueEditor.TargetOf(const AFileName: string): string;
var
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  // Projektgruppe: nur eine gespeicherte.
  if SameText(ExtractFileExt(AFileName), '.groupproj') then
  begin
    Result := '';
    if FileExists(AFileName) then
    begin
      Result := AFileName;
    end;
    Exit;
  end;
  Result := TAtlasIdeProjectSummaries.ProjectFileOf(AFileName);
  mGroup := SavedGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    if (mGroup.Projects[mIndex] <> nil) and
      SameText(TAtlasIdeProjectSummaries.ProjectFileOf(mGroup.Projects[mIndex].FileName), Result) then
    begin
      Exit(mGroup.FileName);
    end;
  end;
end;

class function TAtlasIdeContinueEditor.CurrentTarget: string;
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mProject: IOTAProject;
begin
  Result := '';
  mGroup := SavedGroup;
  if mGroup <> nil then
  begin
    Exit(mGroup.FileName);
  end;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mProject := mModules.GetActiveProject;
  if (mProject <> nil) and (mProject.FileName <> '') then
  begin
    Result := TAtlasIdeProjectSummaries.ProjectFileOf(mProject.FileName);
  end;
end;

class procedure TAtlasIdeContinueEditor.EnsureProject(const AProject: string);
var
  mActions: IOTAActionServices;
begin
  if (AProject = '') or not FileExists(AProject) or ProjectOpen(AProject) then
  begin
    Exit;
  end;
  if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    mActions.OpenProject(AProject, True);
  end;
end;

class procedure TAtlasIdeContinueEditor.OpenTab(const ATab: TAtlasWorkTab);
var
  mLine, mColumn: Integer;
begin
  // Die Zusammenfassung zählt ab 1, der Editor ab 0.
  mLine := ATab.Line - 1;
  if mLine < 0 then
  begin
    mLine := 0;
  end;
  mColumn := ATab.Column - 1;
  if mColumn < 0 then
  begin
    mColumn := 0;
  end;
  TAtlasIdeResults.Open(ATab.FileName, mLine, mColumn);
end;

class function TAtlasIdeContinueEditor.FileText(const AFileName: string): string;
var
  mBuffer: IOTAEditBuffer;
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mIndex: Integer;
begin
  mModule := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    mModule := mModules.FindModule(AFileName);
  end;
  if mModule <> nil then
  begin
    for mIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      if SameText(mModule.ModuleFileEditors[mIndex].FileName, AFileName) and
        Supports(mModule.ModuleFileEditors[mIndex], IOTAEditBuffer, mBuffer) then
      begin
        Exit(TAtlasEditorBuffer.Text(mBuffer));
      end;
    end;
  end;
  Result := TAtlasTextFile.LoadText(AFileName);
end;

end.
