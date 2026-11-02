unit Atlas.Core.Projects.Todos;

// TODO-Liste des Projekts (#68), ohne VCL und Open Tools API: liest die
// Antwort von atlas.server.todos im Modus "json" und macht daraus Einträge
// für das Ergebnisfenster (#400), nach Unit gruppiert, Doppelklick springt.
// Die IDE-To-Do-Liste zeigt nur { TODO }-Kommentare; diese Liste zeigt auch
// // TODO und // FIXME (und eigene Marken aus der Option "keywords" der
// Regel todo-comment). Erledigte Einträge (DONE) liefert der Server ohne
// Filter nicht.
// Filter (TAtlasTodoFilter): Kategorie, Person, Unit, Marke und „Erledigte
// zeigen“ gehen als drittes Argument an den Server (dessen Filter); die
// Vorschläge des Filterdialogs (TAtlasTodoChoices) stammen aus der letzten
// Antwort.
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
  /// <summary>Filter der TODO-Liste (#68); leere Felder filtern nicht.</summary>
  TAtlasTodoFilter = record
    Category: string;
    Owner: string;
    /// <summary>Unit-Name oder Pfad relativ zum Projekt.</summary>
    UnitName: string;
    Keyword: string;
    /// <summary>Auch erledigte Einträge (DONE).</summary>
    IncludeDone: Boolean;
    /// <summary>Kein Feld gesetzt und keine erledigten: die Vorgabe des Servers.</summary>
    function IsEmpty: Boolean;
    /// <summary>Felder ohne Leerraum am Rand.</summary>
    function Trimmed: TAtlasTodoFilter;
    /// <summary>Argument "filter" für atlas.server.todos, z. B. {"category": "GUI", "includeDone": true}; '{}' ohne
    /// Filter.</summary>
    function ToJson: string;
    /// <summary>Kurzform für den Titel im Stil der IDE-To-Do-Liste: "-cGUI, -oMarco, Main, FIXME, DONE"; '' ohne
    /// Filter.</summary>
    function Describe: string;
  end;

  /// <summary>Vorschläge für den Filterdialog: Werte der letzten Antwort, ohne Dubletten (Groß-/Kleinschreibung egal),
  /// sortiert.</summary>
  TAtlasTodoChoices = record
    Categories: TArray<string>;
    Owners: TArray<string>;
    Units: TArray<string>;
    Keywords: TArray<string>;
  end;

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
    /// <summary>Kategorien, Personen, Units und Marken aus einer Antwort (Modus json); False bei ungültiger
    /// Antwort (AChoices leer).</summary>
    class function Choices(const AJson: string; out AChoices: TAtlasTodoChoices): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.JSON;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONString then
  begin
    Result := TJSONString(Value).Value;
  end
  else
  begin
    Result := '';
  end;
end;

function NumberOf(AObject: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if Value is TJSONNumber then
  begin
    Result := TJSONNumber(Value).AsInt;
  end
  else
  begin
    Result := 0;
  end;
end;

function JsonText(const AValue: string): string;
var
  Value: TJSONString;
begin
  Value := TJSONString.Create(AValue);
  try
    Result := Value.ToJSON;
  finally
    Value.Free;
  end;
end;

/// <summary>AValue an AList anhängen, wenn es nicht leer und noch nicht drin ist (Groß-/Kleinschreibung egal).</summary>
procedure AddDistinct(var AList: TArray<string>; const AValue: string);
var
  Item: string;
begin
  if AValue = '' then
  begin
    Exit;
  end;
  for Item in AList do
  begin
    if SameText(Item, AValue) then
    begin
      Exit;
    end;
  end;
  AList := AList + [AValue];
end;

procedure SortTexts(var AList: TArray<string>);
begin
  TArray.Sort<string>(AList, TComparer<string>.Construct(
    function(const ALeft, ARight: string): Integer
    begin
      Result := CompareText(ALeft, ARight);
      if Result = 0 then
      begin
        Result := CompareStr(ALeft, ARight);
      end;
    end));
end;

{ TAtlasTodoFilter }

function TAtlasTodoFilter.IsEmpty: Boolean;
begin
  Result := (Trim(Category) = '') and (Trim(Owner) = '') and (Trim(UnitName) = '') and (Trim(Keyword) = '') and
    not IncludeDone;
end;

function TAtlasTodoFilter.Trimmed: TAtlasTodoFilter;
begin
  Result := Self;
  Result.Category := Trim(Category);
  Result.Owner := Trim(Owner);
  Result.UnitName := Trim(UnitName);
  Result.Keyword := Trim(Keyword);
end;

function TAtlasTodoFilter.ToJson: string;
var
  Clean: TAtlasTodoFilter;
  Parts: TArray<string>;

  procedure Add(const AName, AValue: string);
  begin
    if AValue <> '' then
    begin
      Parts := Parts + [JsonText(AName) + ': ' + JsonText(AValue)];
    end;
  end;

begin
  Clean := Trimmed;
  Parts := nil;
  Add('category', Clean.Category);
  Add('owner', Clean.Owner);
  Add('unit', Clean.UnitName);
  Add('keyword', Clean.Keyword);
  if Clean.IncludeDone then
  begin
    Parts := Parts + ['"includeDone": true'];
  end;
  Result := '{' + string.Join(', ', Parts) + '}';
end;

function TAtlasTodoFilter.Describe: string;
var
  Clean: TAtlasTodoFilter;
  Parts: TArray<string>;
begin
  Clean := Trimmed;
  Parts := nil;
  if Clean.Category <> '' then
  begin
    Parts := Parts + ['-c' + Clean.Category];
  end;
  if Clean.Owner <> '' then
  begin
    Parts := Parts + ['-o' + Clean.Owner];
  end;
  if Clean.UnitName <> '' then
  begin
    Parts := Parts + [Clean.UnitName];
  end;
  if Clean.Keyword <> '' then
  begin
    Parts := Parts + [UpperCase(Clean.Keyword)];
  end;
  if Clean.IncludeDone then
  begin
    Parts := Parts + ['DONE'];
  end;
  Result := string.Join(', ', Parts);
end;

{ TAtlasTodoList }

class function TAtlasTodoList.Caption(const AKeyword: string; APriority: Integer; const ACategory, AOwner,
  AText: string): string;
var
  Details: string;
begin
  Result := AKeyword;
  if APriority > 0 then
  begin
    Result := Result + ' ' + IntToStr(APriority);
  end;
  Details := ACategory;
  if AOwner <> '' then
  begin
    if Details <> '' then
    begin
      Details := Details + ', ';
    end;
    Details := Details + AOwner;
  end;
  if Details <> '' then
  begin
    Result := Result + ' [' + Details + ']';
  end;
  if AText <> '' then
  begin
    Result := Result + ': ' + AText;
  end;
end;

class function TAtlasTodoList.FullPath(const ARoot, APath: string): string;
var
  Path: string;
begin
  Path := StringReplace(APath, '/', '\', [rfReplaceAll]);
  // Laufwerk (C:\…) oder UNC (\\server\…): schon absolut.
  if ((Length(Path) >= 2) and (Path[2] = ':')) or ((Length(Path) >= 1) and (Path[1] = '\')) or (ARoot = '') then
  begin
    Exit(Path);
  end;
  Result := StringReplace(ARoot, '/', '\', [rfReplaceAll]);
  if Result[Length(Result)] <> '\' then
  begin
    Result := Result + '\';
  end;
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
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    Root := TJSONObject(Value);
    if not (Root.GetValue('files') is TJSONArray) then
    begin
      Exit;
    end;
    RootPath := TextOf(Root, 'root');
    Files := TJSONArray(Root.GetValue('files'));
    for FileIndex := 0 to Files.Count - 1 do
    begin
      if not (Files.Items[FileIndex] is TJSONObject) then
      begin
        Continue;
      end;
      FileItem := TJSONObject(Files.Items[FileIndex]);
      FileName := FullPath(RootPath, TextOf(FileItem, 'file'));
      if not (FileItem.GetValue('todos') is TJSONArray) then
      begin
        Continue;
      end;
      Todos := TJSONArray(FileItem.GetValue('todos'));
      for TodoIndex := 0 to Todos.Count - 1 do
      begin
        if not (Todos.Items[TodoIndex] is TJSONObject) then
        begin
          Continue;
        end;
        Todo := TJSONObject(Todos.Items[TodoIndex]);
        Entry := TAtlasResultEntry.Create(FileName, NumberOf(Todo, 'line') - 1, NumberOf(Todo, 'character') - 1);
        if Entry.Line < 0 then
        begin
          Entry.Line := 0;
        end;
        if Entry.Character < 0 then
        begin
          Entry.Character := 0;
        end;
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

class function TAtlasTodoList.Choices(const AJson: string; out AChoices: TAtlasTodoChoices): Boolean;
var
  Value: TJSONValue;
  Root, FileItem, Todo: TJSONObject;
  Files, Todos: TJSONArray;
  FileIndex, TodoIndex: Integer;
begin
  AChoices := Default(TAtlasTodoChoices);
  Result := False;
  try
    Value := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Value := nil;
  end;
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    Root := TJSONObject(Value);
    if not (Root.GetValue('files') is TJSONArray) then
    begin
      Exit;
    end;
    Files := TJSONArray(Root.GetValue('files'));
    for FileIndex := 0 to Files.Count - 1 do
    begin
      if not (Files.Items[FileIndex] is TJSONObject) then
      begin
        Continue;
      end;
      FileItem := TJSONObject(Files.Items[FileIndex]);
      AddDistinct(AChoices.Units, TextOf(FileItem, 'unit'));
      if not (FileItem.GetValue('todos') is TJSONArray) then
      begin
        Continue;
      end;
      Todos := TJSONArray(FileItem.GetValue('todos'));
      for TodoIndex := 0 to Todos.Count - 1 do
      begin
        if not (Todos.Items[TodoIndex] is TJSONObject) then
        begin
          Continue;
        end;
        Todo := TJSONObject(Todos.Items[TodoIndex]);
        AddDistinct(AChoices.Categories, TextOf(Todo, 'category'));
        AddDistinct(AChoices.Owners, TextOf(Todo, 'owner'));
        // Erledigt ist kein Filter nach Marke, sondern „Erledigte zeigen“.
        if not SameText(TextOf(Todo, 'keyword'), 'DONE') then
        begin
          AddDistinct(AChoices.Keywords, UpperCase(TextOf(Todo, 'keyword')));
        end;
      end;
    end;
    SortTexts(AChoices.Categories);
    SortTexts(AChoices.Owners);
    SortTexts(AChoices.Units);
    SortTexts(AChoices.Keywords);
    Result := True;
  finally
    Value.Free;
  end;
end;

end.
