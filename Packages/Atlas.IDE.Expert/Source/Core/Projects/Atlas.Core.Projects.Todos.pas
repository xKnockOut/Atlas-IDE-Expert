unit Atlas.Core.Projects.Todos;

// TODO-Liste des Projekts (#68), ohne VCL und Open Tools API: liest die
// Antwort von atlas.server.todos im Modus "json" und macht daraus Einträge
// für das Ergebnisfenster (#400), nach Unit gruppiert, Doppelklick springt.
// Die IDE-To-Do-Liste zeigt nur { TODO }-Kommentare; diese Liste zeigt auch
// // TODO und // FIXME (und eigene Marken aus der Option "keywords" der
// Regel todo-comment). Erledigte Einträge (DONE) liefert der Server ohne
// Filter nicht.
//
// Antwort (Format 1, Zeilen und Spalten ab 1):
//   {"format": 1, "root": "C:\\Projekte\\Kasse", "summary": {…},
//    "files": [{"file": "Source/Main.pas", "unit": "Main", "todos": [
//      {"keyword": "TODO", "done": false, "priority": 1, "owner": "Marco",
//       "category": "GUI", "text": "Fokus setzen", "line": 12, "character": 3}]}]}

interface

uses
  Atlas.Core.Results.Model;

type
  TAtlasTodoList = class
  public
    /// <summary>Einträge aus der Antwort; Positionen 0-basiert, Text wie Caption. False bei ungültiger Antwort
    /// (AEntries leer); eine gültige Antwort ohne Einträge liefert True.</summary>
    class function Entries(const AJson: string; out AEntries: TArray<TAtlasResultEntry>): Boolean; static;
    /// <summary>"TODO 2 [GUI, Marco]: Text"; Priorität 0, leere Kategorie und Person fallen weg.</summary>
    class function Caption(const AKeyword: string; APriority: Integer; const ACategory, AOwner,
      AText: string): string; static;
    /// <summary>Absoluter Pfad mit „\“: APath, wenn er absolut ist, sonst ARoot\APath.</summary>
    class function FullPath(const ARoot, APath: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value
  else
    Result := '';
end;

function NumberOf(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
    Result := TJSONNumber(Value).AsInt
  else
    Result := 0;
end;

{ TAtlasTodoList }

class function TAtlasTodoList.Caption(const AKeyword: string; APriority: Integer; const ACategory, AOwner,
  AText: string): string;
var
  Details: string;
begin
  Result := AKeyword;
  if APriority > 0 then
    Result := Result + ' ' + IntToStr(APriority);
  Details := ACategory;
  if AOwner <> '' then
  begin
    if Details <> '' then
      Details := Details + ', ';
    Details := Details + AOwner;
  end;
  if Details <> '' then
    Result := Result + ' [' + Details + ']';
  if AText <> '' then
    Result := Result + ': ' + AText;
end;

class function TAtlasTodoList.FullPath(const ARoot, APath: string): string;
var
  Path: string;
begin
  Path := StringReplace(APath, '/', '\', [rfReplaceAll]);
  // Laufwerk (C:\…) oder UNC (\\server\…): schon absolut.
  if ((Length(Path) >= 2) and (Path[2] = ':')) or ((Length(Path) >= 1) and (Path[1] = '\')) or (ARoot = '') then
    Exit(Path);
  Result := StringReplace(ARoot, '/', '\', [rfReplaceAll]);
  if Result[Length(Result)] <> '\' then
    Result := Result + '\';
  Result := Result + Path;
end;

class function TAtlasTodoList.Entries(const AJson: string; out AEntries: TArray<TAtlasResultEntry>): Boolean;
var
  Value: TJSONValue;
  Root, FileItem, Todo: TJSONObject;
  Files, Todos: TJSONArray;
  FileIndex, TodoIndex: Integer;
  Entry: TAtlasResultEntry;
  FileName, RootPath: string;
begin
  AEntries := nil;
  Result := False;
  Value := nil;
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if not (Value is TJSONObject) then
      Exit;
    Root := TJSONObject(Value);
    if not (Root.GetValue('files') is TJSONArray) then
      Exit;
    RootPath := TextOf(Root, 'root');
    Files := TJSONArray(Root.GetValue('files'));
    for FileIndex := 0 to Files.Count - 1 do
    begin
      if not (Files.Items[FileIndex] is TJSONObject) then
        Continue;
      FileItem := TJSONObject(Files.Items[FileIndex]);
      FileName := FullPath(RootPath, TextOf(FileItem, 'file'));
      if not (FileItem.GetValue('todos') is TJSONArray) then
        Continue;
      Todos := TJSONArray(FileItem.GetValue('todos'));
      for TodoIndex := 0 to Todos.Count - 1 do
      begin
        if not (Todos.Items[TodoIndex] is TJSONObject) then
          Continue;
        Todo := TJSONObject(Todos.Items[TodoIndex]);
        Entry := TAtlasResultEntry.Create(FileName, NumberOf(Todo, 'line') - 1, NumberOf(Todo, 'character') - 1);
        if Entry.Line < 0 then
          Entry.Line := 0;
        if Entry.Character < 0 then
          Entry.Character := 0;
        Entry.Text := Caption(TextOf(Todo, 'keyword'), NumberOf(Todo, 'priority'), TextOf(Todo, 'category'),
          TextOf(Todo, 'owner'), TextOf(Todo, 'text'));
        AEntries := AEntries + [Entry];
      end;
    end;
    Result := True;
  finally
    Value.Free;
  end;
end;

end.
