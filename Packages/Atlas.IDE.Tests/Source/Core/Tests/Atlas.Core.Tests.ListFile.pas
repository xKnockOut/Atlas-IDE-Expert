unit Atlas.Core.Tests.ListFile;

// Ablage „nur für mich“ der Testlisten (#2167), ohne VCL und Open Tools API:
// je Testprojekt die eigenen Listen und die zuletzt ausgeführte Liste (für
// die Taste tests.lists.runKey, auch bei einer Liste aus atlas.json).
// - Datei %LOCALAPPDATA%\Atlas\test-lists.json, Format 1 (UTF-8):
//     {"format": 1, "projects": [
//       {"project": "C:\\Projekt\\Tests.dproj", "lastRun": "Vor dem Commit",
//        "lists": [{"name": "Parser", "tests": ["Parser.Tests"]}]}]}
//   Zuletzt benutztes Projekt zuerst, höchstens cMaxProjects; ein höheres
//   Format bleibt unangetastet. Die Listen liest und schreibt
//   TAtlasTestListModel (Parse, ToJson); Lesen und Schreiben der Datei macht
//   die IDE-Schicht über TAtlasDataFile (Atlas.IDE.Tests.Lists).

interface

uses
  Atlas.Core.Tests.Lists;

type
  /// <summary>Eintrag eines Testprojekts.</summary>
  TAtlasTestListProject = record
    /// <summary>Testprojekt (.dproj).</summary>
    Project: string;
    /// <summary>Name der zuletzt ausgeführten Liste; '' ohne.</summary>
    LastRun: string;
    /// <summary>Listen „nur für mich“.</summary>
    Lists: TAtlasTestLists;
    function IsEmpty: Boolean;
  end;

  TAtlasTestListProjects = TArray<TAtlasTestListProject>;

  TAtlasTestListFile = class
  public const
    cFormat = 1;
    cFileName = 'test-lists.json';
    cMaxProjects = 100;
  public
    /// <summary>Einträge aus dem Text der Datei; leer bei ungültigem Inhalt oder höherem Format.</summary>
    class function Parse(const AText: string): TAtlasTestListProjects; static;
    /// <summary>Format der Datei (0 ohne oder bei ungültigem Inhalt).</summary>
    class function FormatOf(const AText: string): Integer; static;
    /// <summary>Text der Datei (eingerückt, CRLF).</summary>
    class function ToJson(const AProjects: TAtlasTestListProjects): string; static;
    /// <summary>Index des Eintrags zu AProject (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    class function IndexOf(const AProjects: TAtlasTestListProjects; const AProject: string): Integer; static;
    /// <summary>Eintrag AEntry vorn ablegen (ersetzt den desselben Projekts); ein leerer Eintrag entfällt.</summary>
    class procedure Put(var AProjects: TAtlasTestListProjects; const AEntry: TAtlasTestListProject); static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.Json;

const
  cNewLine = #13#10;
  /// <summary>Teile eines Eintrags je Projekt in der Datei.</summary>
  cProjectJson = '    {"project": ';
  cLastRunJson = ', "lastRun": ';
  cListsJson = '     "lists": ';
  cListsIndent = '     ';

{ TAtlasTestListProject }

function TAtlasTestListProject.IsEmpty: Boolean;
begin
  Result := (LastRun = '') and (Length(Lists) = 0);
end;

{ TAtlasTestListFile }

class function TAtlasTestListFile.FormatOf(const AText: string): Integer;
var
  mRoot: TJSONValue;
begin
  Result := 0;
  mRoot := nil;
  if Trim(AText) <> '' then
  begin
    mRoot := TJSONObject.ParseJSONValue(AText);
  end;
  try
    if mRoot is TJSONObject then
    begin
      Result := TJsonRead.IntOr(TJSONObject(mRoot), 'format', 0);
    end;
  finally
    mRoot.Free;
  end;
end;

/// <summary>Eintrag aus dem Objekt AObject; False ohne Projekt.</summary>
function ReadEntry(AObject: TJSONObject; out AEntry: TAtlasTestListProject): Boolean;
var
  mLists: TJSONValue;
begin
  AEntry := Default(TAtlasTestListProject);
  AEntry.Project := TJsonRead.TrimmedText(AObject, 'project');
  AEntry.LastRun := TJsonRead.TrimmedText(AObject, 'lastRun');
  mLists := AObject.GetValue('lists');
  if mLists is TJSONArray then
  begin
    AEntry.Lists := TAtlasTestListModel.Parse(mLists.ToJSON, TAtlasTestListStore.Personal);
  end;
  Result := AEntry.Project <> '';
end;

class function TAtlasTestListFile.Parse(const AText: string): TAtlasTestListProjects;
var
  mRoot, mItems: TJSONValue;
  mIndex: Integer;
  mEntry: TAtlasTestListProject;
begin
  Result := nil;
  if (Trim(AText) = '') or (FormatOf(AText) > cFormat) then
  begin
    Exit;
  end;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mItems := TJSONObject(mRoot).GetValue('projects');
    if not (mItems is TJSONArray) then
    begin
      Exit;
    end;
    for mIndex := 0 to TJSONArray(mItems).Count - 1 do
    begin
      if (TJSONArray(mItems).Items[mIndex] is TJSONObject) and
        ReadEntry(TJSONObject(TJSONArray(mItems).Items[mIndex]), mEntry) and (IndexOf(Result, mEntry.Project) < 0) and
        (Length(Result) < cMaxProjects) then
      begin
        Result := Result + [mEntry];
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasTestListFile.ToJson(const AProjects: TAtlasTestListProjects): string;
var
  mText: TStringBuilder;
  mIndex: Integer;
begin
  mText := TStringBuilder.Create;
  try
    mText.Append('{' + cNewLine + '  "format": ' + IntToStr(cFormat) + ',' + cNewLine + '  "projects": [');
    for mIndex := 0 to High(AProjects) do
    begin
      if mIndex > 0 then
      begin
        mText.Append(',');
      end;
      mText.Append(cNewLine + cProjectJson + TJsonText.Quote(AProjects[mIndex].Project) + cLastRunJson +
        TJsonText.Quote(AProjects[mIndex].LastRun) + ',' + cNewLine + cListsJson +
        TAtlasTestListModel.ToJson(AProjects[mIndex].Lists, cListsIndent) + '}');
    end;
    if Length(AProjects) > 0 then
    begin
      mText.Append(cNewLine + '  ');
    end;
    mText.Append(']' + cNewLine + '}' + cNewLine);
    Result := mText.ToString;
  finally
    mText.Free;
  end;
end;

class function TAtlasTestListFile.IndexOf(const AProjects: TAtlasTestListProjects; const AProject: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AProjects) do
  begin
    if AnsiSameText(AProjects[mIndex].Project, Trim(AProject)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class procedure TAtlasTestListFile.Put(var AProjects: TAtlasTestListProjects; const AEntry: TAtlasTestListProject);
var
  mKept: TAtlasTestListProjects;
  mEntry: TAtlasTestListProject;
begin
  mKept := nil;
  if (Trim(AEntry.Project) <> '') and not AEntry.IsEmpty then
  begin
    mKept := [AEntry];
  end;
  for mEntry in AProjects do
  begin
    if not AnsiSameText(mEntry.Project, Trim(AEntry.Project)) and (Length(mKept) < cMaxProjects) then
    begin
      mKept := mKept + [mEntry];
    end;
  end;
  AProjects := mKept;
end;

end.
