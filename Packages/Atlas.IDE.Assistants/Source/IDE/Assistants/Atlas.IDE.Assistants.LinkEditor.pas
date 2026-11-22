unit Atlas.IDE.Assistants.LinkEditor;

// Assistenten-Kopplung (#2377), Adapter zur Open Tools API: was die Werkzeuge des verbundenen Assistenten über
// die IDE wissen und in ihr tun. Arbeitsordner (Ordner der Projekte der Gruppe), offene Reiter in ihrer
// Reihenfolge, Auswahl bzw. Schreibmarke im Editor (Spalten des Editors in Zeichen umgerechnet, Tabs beachtet),
// Datei öffnen und einen Bereich markieren, Zustand und Speichern einer Datei, Befunde der Atlas-Prüfung und
// Compilermeldungen aus dem Problemspeicher (#909) und der aktuelle Text einer Datei (Puffer, sonst Platte) für
// den Vergleich. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Assistants.Contract.Link;

type
  TAtlasIdeLinkEditor = class
  public const
    /// <summary>Längster Auswahltext, der an den Assistenten geht.</summary>
    cMaxSelectionChars = 200000;
  public
    class function Folders: TArray<string>; static;
    class function Tabs: TArray<TAtlasLinkTab>; static;
    /// <summary>Auswahl bzw. Schreibmarke im Editor; den Text holt sie nur, wenn sich der Bereich gegenüber
    /// ACacheKey geändert hat (große Auswahlen kosten sonst bei jedem Takt).</summary>
    class function Selection(var ACacheKey, ACacheText: string): TAtlasLinkSelection; static;
    class function OpenFile(const ARequest: TAtlasLinkOpenRequest): TAtlasLinkOpenResult; static;
    class function Document(const AFileName: string): TAtlasLinkDocument; static;
    class function Save(const AFileName: string): Boolean; static;
    class function Diagnostics(const AFileName: string): TArray<TAtlasLinkDiagnostic>; static;
    /// <summary>Text der Datei, wie sie gerade ist: Puffer, sonst Platte; '' für eine neue Datei.</summary>
    class function CurrentText(const AFileName: string): string; static;
    /// <summary>Zeilen der Auswahl bzw. der Schreibmarke im Editor (0-basiert) für at_mentioned.</summary>
    class function Mention(out AFileName: string; out ALineStart, ALineEnd: Integer): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Plugin.Files.Contract,
  Atlas.Core.Lsp.Session.Json,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Assistants.LinkState,
  Atlas.IDE.Foundation.Host,
  Atlas.ToolsApi.Editor.Buffer,
  Atlas.ToolsApi.Editor.Tabs,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Files.DirtyExport,
  Atlas.IDE.Problems.Controller;

const
  cSeverityNames: array[TAtlasProblemSeverity] of string = ('Error', 'Warning', 'Information', 'Hint');

/// <summary>Aufnahme von AFolder in AList ohne Doppelte.</summary>
procedure AddFolder(var AList: TArray<string>; const AFolder: string);
var
  mFolder: string;
begin
  if AFolder = '' then
  begin
    Exit;
  end;
  for mFolder in AList do
  begin
    if SameText(mFolder, AFolder) then
    begin
      Exit;
    end;
  end;
  AList := AList + [AFolder];
end;

class function TAtlasIdeLinkEditor.Folders: TArray<string>;
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mProject: IOTAProject;
  mIndex: Integer;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    mGroup := mModules.MainProjectGroup;
    if mGroup <> nil then
    begin
      for mIndex := 0 to mGroup.ProjectCount - 1 do
      begin
        AddFolder(Result, ExtractFileDir(mGroup.Projects[mIndex].FileName));
      end;
    end;
    mProject := mModules.GetActiveProject;
    if mProject <> nil then
    begin
      AddFolder(Result, ExtractFileDir(mProject.FileName));
    end;
  end;
  if Result = nil then
  begin
    AddFolder(Result, ExtractFileDir(TAtlasEditorBuffer.TopFileName));
  end;
end;

class function TAtlasIdeLinkEditor.Tabs: TArray<TAtlasLinkTab>;
var
  mFiles: TArray<string>;
  mModified: TArray<string>;
  mActive: string;
  mIndex: Integer;
begin
  mFiles := TAtlasEditorTabs.Ordered(TAtlasDirtyExport.OpenFiles);
  mModified := TAtlasDirtyExport.ModifiedFiles;
  mActive := TAtlasEditorBuffer.TopFileName;
  Result := nil;
  SetLength(Result, Length(mFiles));
  for mIndex := 0 to High(mFiles) do
  begin
    Result[mIndex].FileName := mFiles[mIndex];
    Result[mIndex].Active := SameText(mFiles[mIndex], mActive);
    Result[mIndex].Dirty := IndexText(mFiles[mIndex], mModified) >= 0;
  end;
end;

/// <summary>Position im Editor (1-basiert, Spalten mit Tabs) als Zeile und Zeichen (0-basiert).</summary>
function PositionOf(const AView: IOTAEditView; ARow, AColumn: Integer): TAtlasLinkPosition;
begin
  Result := TAtlasLinkPosition.At(ARow - 1, TLspSessionJson.ColumnToIndex(TAtlasEditorBuffer.LineText(AView, ARow),
    AColumn, TAtlasEditorBuffer.TabWidth(AView.Buffer)));
end;

class function TAtlasIdeLinkEditor.Selection(var ACacheKey, ACacheText: string): TAtlasLinkSelection;
var
  mView: IOTAEditView;
  mBlock: IOTAEditBlock;
  mKey: string;
begin
  Result := Default(TAtlasLinkSelection);
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or (mView.Buffer.FileName = '') then
  begin
    Exit;
  end;
  Result.Known := True;
  Result.FileName := mView.Buffer.FileName;
  mBlock := mView.Block;
  if (mBlock = nil) or not mBlock.IsValid or (mBlock.Size = 0) then
  begin
    Result.Start := PositionOf(mView, mView.CursorPos.Line, mView.CursorPos.Col);
    Result.Stop := Result.Start;
    Exit;
  end;
  Result.Start := PositionOf(mView, mBlock.StartingRow, mBlock.StartingColumn);
  Result.Stop := PositionOf(mView, mBlock.EndingRow, mBlock.EndingColumn);
  mKey := Format('%s|%d:%d-%d:%d|%d', [Result.FileName, Result.Start.Line, Result.Start.Character, Result.Stop.Line,
    Result.Stop.Character, mBlock.Size]);
  if mKey <> ACacheKey then
  begin
    ACacheKey := mKey;
    ACacheText := Copy(mBlock.Text, 1, cMaxSelectionChars);
  end;
  Result.Text := ACacheText;
end;

/// <summary>Bereich ARange in der obersten Ansicht markieren, wenn sie AFileName zeigt.</summary>
procedure SelectRange(const AFileName, AText: string; const ARange: TAtlasLinkRange);
var
  mView: IOTAEditView;
  mLines: TArray<string>;
  mTabWidth: Integer;
  mPosition: TLspTextPosition;
begin
  mView := TAtlasEditorBuffer.TopSourceView;
  if (mView = nil) or not SameText(mView.Buffer.FileName, AFileName) then
  begin
    Exit;
  end;
  mLines := AText.Split([#13#10, #10, #13]);
  mTabWidth := TAtlasEditorBuffer.TabWidth(mView.Buffer);
  mView.Block.Style := btNonInclusive;
  mPosition.Line := ARange.Start.Line;
  mPosition.Character := ARange.Start.Character;
  mView.CursorPos := TAtlasIdeNavigation.EditPosOf(mLines, mPosition, mTabWidth);
  mView.Block.BeginBlock;
  mPosition.Line := ARange.Stop.Line;
  mPosition.Character := ARange.Stop.Character;
  mView.CursorPos := TAtlasIdeNavigation.EditPosOf(mLines, mPosition, mTabWidth);
  mView.Block.EndBlock;
  mView.MoveViewToCursor;
  mView.Paint;
end;

class function TAtlasIdeLinkEditor.OpenFile(const ARequest: TAtlasLinkOpenRequest): TAtlasLinkOpenResult;
var
  mText: string;
begin
  Result := Default(TAtlasLinkOpenResult);
  if not Document(ARequest.FileName).Open and not FileExists(ARequest.FileName) then
  begin
    Exit;
  end;
  if not TAtlasIdeNavigation.ShowFile(ARequest.FileName) then
  begin
    Exit;
  end;
  Result.Opened := True;
  mText := CurrentText(ARequest.FileName);
  Result.LineCount := TAtlasLinkText.LineCount(mText);
  SelectRange(ARequest.FileName, mText, TAtlasLinkText.FindRange(mText, ARequest.StartText, ARequest.EndText,
    ARequest.SelectToEndOfLine));
end;

class function TAtlasIdeLinkEditor.Document(const AFileName: string): TAtlasLinkDocument;
var
  mBuffer: TAtlasEditorFile;
begin
  Result := Default(TAtlasLinkDocument);
  if AFileName = '' then
  begin
    Exit;
  end;
  mBuffer := TAtlasIdeHost.EditorFiles.Buffer(AFileName);
  Result.Open := mBuffer.Open;
  Result.Dirty := mBuffer.Modified;
end;

class function TAtlasIdeLinkEditor.Save(const AFileName: string): Boolean;
begin
  Result := TAtlasIdeHost.EditorFiles.Save(AFileName);
end;

class function TAtlasIdeLinkEditor.Diagnostics(const AFileName: string): TArray<TAtlasLinkDiagnostic>;
var
  mStore: TAtlasProblemStore;
  mFiles: TArray<string>;
  mFile: string;
  mProblem: TAtlasProblem;
  mItem: TAtlasLinkDiagnostic;
begin
  Result := nil;
  mStore := TAtlasProblemsController.Current;
  if mStore = nil then
  begin
    Exit;
  end;
  if AFileName <> '' then
  begin
    mFiles := [AFileName];
  end
  else
  begin
    mFiles := TAtlasDirtyExport.OpenFiles;
  end;
  for mFile in mFiles do
  begin
    for mProblem in mStore.ForFile(mFile) do
    begin
      // Inaktive {$IFDEF}-Zweige sind keine Befunde.
      if mProblem.Unnecessary then
      begin
        Continue;
      end;
      mItem := Default(TAtlasLinkDiagnostic);
      mItem.FileName := mFile;
      mItem.Message := mProblem.Message;
      mItem.Severity := cSeverityNames[mProblem.Severity];
      mItem.Source := mProblem.Source;
      mItem.Code := mProblem.Code;
      mItem.Start := TAtlasLinkPosition.At(mProblem.StartLine, mProblem.StartCharacter);
      mItem.Stop := TAtlasLinkPosition.At(mProblem.EndLine, mProblem.EndCharacter);
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasIdeLinkEditor.CurrentText(const AFileName: string): string;
begin
  // Wie die Änderung sie sieht: Puffer, offenes Formular, sonst die Platte mit erkannter Kodierung.
  Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
end;

class function TAtlasIdeLinkEditor.Mention(out AFileName: string; out ALineStart, ALineEnd: Integer): Boolean;
var
  mKey: string;
  mText: string;
  mSelection: TAtlasLinkSelection;
begin
  mKey := '';
  mText := '';
  mSelection := Selection(mKey, mText);
  AFileName := mSelection.FileName;
  ALineStart := mSelection.Start.Line;
  ALineEnd := mSelection.Stop.Line;
  // Endet die Auswahl am Anfang einer Zeile, gehört diese Zeile nicht dazu.
  if (ALineEnd > ALineStart) and (mSelection.Stop.Character = 0) then
  begin
    Dec(ALineEnd);
  end;
  Result := mSelection.Known;
end;

end.
