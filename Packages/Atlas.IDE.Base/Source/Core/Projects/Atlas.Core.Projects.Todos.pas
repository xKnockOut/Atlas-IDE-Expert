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
  mValue: TJSONValue;
begin
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
  begin
    Result := TJSONString(mValue).Value;
  end
  else
  begin
    Result := '';
  end;
end;

function NumberOf(AObject: TJSONObject; const AName: string): Integer;
var
  mValue: TJSONValue;
begin
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsInt;
  end
  else
  begin
    Result := 0;
  end;
end;

function JsonText(const AValue: string): string;
var
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(AValue);
  try
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

/// <summary>AValue an AList anhängen, wenn es nicht leer und noch nicht drin ist (Groß-/Kleinschreibung
/// egal).</summary>
procedure AddDistinct(var AList: TArray<string>; const AValue: string);
var
  mItem: string;
begin
  if AValue = '' then
  begin
    Exit;
  end;
  for mItem in AList do
  begin
    if SameText(mItem, AValue) then
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

/// <summary>AJson als JSON-Wert; nil bei ungültigem Text.</summary>
function ParseJson(const AJson: string): TJSONValue;
begin
  try
    Result := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      Result := nil;
  end;
end;

/// <summary>Feld AName von AValue, wenn AValue ein Objekt und das Feld ein Array ist; sonst nil.</summary>
function ArrayOf(AValue: TJSONValue; const AName: string): TJSONArray;
begin
  Result := nil;
  if (AValue is TJSONObject) and (TJSONObject(AValue).GetValue(AName) is TJSONArray) then
  begin
    Result := TJSONArray(TJSONObject(AValue).GetValue(AName));
  end;
end;

/// <summary>Objekte von AArray in Reihenfolge; andere Werte fallen weg; leer ohne Array.</summary>
function ObjectsOf(AArray: TJSONArray): TArray<TJSONObject>;
var
  mIndex: Integer;
begin
  Result := nil;
  if AArray = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AArray.Count - 1 do
  begin
    if AArray.Items[mIndex] is TJSONObject then
    begin
      Result := Result + [TJSONObject(AArray.Items[mIndex])];
    end;
  end;
end;

/// <summary>Eintrag eines Todos der Datei AFileName; Position 0-basiert, nie negativ.</summary>
function TodoEntryOf(const AFileName: string; ATodo: TJSONObject): TAtlasResultEntry;
begin
  Result := TAtlasResultEntry.Create(AFileName, NumberOf(ATodo, 'line') - 1, NumberOf(ATodo, 'character') - 1);
  if Result.Line < 0 then
  begin
    Result.Line := 0;
  end;
  if Result.Character < 0 then
  begin
    Result.Character := 0;
  end;
  Result.Text := TAtlasTodoList.Caption(TextOf(ATodo, 'keyword'), NumberOf(ATodo, 'priority'),
    TextOf(ATodo, 'category'), TextOf(ATodo, 'owner'), TextOf(ATodo, 'text'));
end;

/// <summary>Kategorie, Person und Marke eines Todos in AChoices aufnehmen.</summary>
procedure AddTodoChoices(var AChoices: TAtlasTodoChoices; ATodo: TJSONObject);
begin
  AddDistinct(AChoices.Categories, TextOf(ATodo, 'category'));
  AddDistinct(AChoices.Owners, TextOf(ATodo, 'owner'));
  // Erledigt ist kein Filter nach Marke, sondern „Erledigte zeigen“.
  if not SameText(TextOf(ATodo, 'keyword'), 'DONE') then
  begin
    AddDistinct(AChoices.Keywords, UpperCase(TextOf(ATodo, 'keyword')));
  end;
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
  mClean: TAtlasTodoFilter;
  mParts: TArray<string>;

  procedure Add(const AName, AValue: string);
  begin
    if AValue <> '' then
    begin
      mParts := mParts + [JsonText(AName) + ': ' + JsonText(AValue)];
    end;
  end;

begin
  mClean := Trimmed;
  mParts := nil;
  Add('category', mClean.Category);
  Add('owner', mClean.Owner);
  Add('unit', mClean.UnitName);
  Add('keyword', mClean.Keyword);
  if mClean.IncludeDone then
  begin
    mParts := mParts + ['"includeDone": true'];
  end;
  Result := '{' + string.Join(', ', mParts) + '}';
end;

function TAtlasTodoFilter.Describe: string;
var
  mClean: TAtlasTodoFilter;
  mParts: TArray<string>;
begin
  mClean := Trimmed;
  mParts := nil;
  if mClean.Category <> '' then
  begin
    mParts := mParts + ['-c' + mClean.Category];
  end;
  if mClean.Owner <> '' then
  begin
    mParts := mParts + ['-o' + mClean.Owner];
  end;
  if mClean.UnitName <> '' then
  begin
    mParts := mParts + [mClean.UnitName];
  end;
  if mClean.Keyword <> '' then
  begin
    mParts := mParts + [UpperCase(mClean.Keyword)];
  end;
  if mClean.IncludeDone then
  begin
    mParts := mParts + ['DONE'];
  end;
  Result := string.Join(', ', mParts);
end;

{ TAtlasTodoList }

class function TAtlasTodoList.Caption(const AKeyword: string; APriority: Integer; const ACategory, AOwner,
  AText: string): string;
var
  mDetails: string;
begin
  Result := AKeyword;
  if APriority > 0 then
  begin
    Result := Result + ' ' + IntToStr(APriority);
  end;
  mDetails := ACategory;
  if AOwner <> '' then
  begin
    if mDetails <> '' then
    begin
      mDetails := mDetails + ', ';
    end;
    mDetails := mDetails + AOwner;
  end;
  if mDetails <> '' then
  begin
    Result := Result + ' [' + mDetails + ']';
  end;
  if AText <> '' then
  begin
    Result := Result + ': ' + AText;
  end;
end;

class function TAtlasTodoList.FullPath(const ARoot, APath: string): string;
var
  mPath: string;
begin
  mPath := StringReplace(APath, '/', '\', [rfReplaceAll]);
  // Laufwerk (C:\…) oder UNC (\\server\…): schon absolut.
  if ((Length(mPath) >= 2) and (mPath[2] = ':')) or ((Length(mPath) >= 1) and (mPath[1] = '\')) or (ARoot = '') then
  begin
    Exit(mPath);
  end;
  Result := StringReplace(ARoot, '/', '\', [rfReplaceAll]);
  if Result[Length(Result)] <> '\' then
  begin
    Result := Result + '\';
  end;
  Result := Result + mPath;
end;

class function TAtlasTodoList.Entries(const AJson: string; out AEntries: TArray<TAtlasResultEntry>): Boolean;
var
  mValue: TJSONValue;
  mFiles: TJSONArray;
  mFileItem, mTodo: TJSONObject;
  mFileName, mRootPath: string;
begin
  AEntries := nil;
  mValue := ParseJson(AJson);
  try
    mFiles := ArrayOf(mValue, 'files');
    Result := mFiles <> nil;
    if not Result then
    begin
      Exit;
    end;
    mRootPath := TextOf(TJSONObject(mValue), 'root');
    for mFileItem in ObjectsOf(mFiles) do
    begin
      mFileName := FullPath(mRootPath, TextOf(mFileItem, 'file'));
      for mTodo in ObjectsOf(ArrayOf(mFileItem, 'todos')) do
      begin
        AEntries := AEntries + [TodoEntryOf(mFileName, mTodo)];
      end;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasTodoList.Choices(const AJson: string; out AChoices: TAtlasTodoChoices): Boolean;
var
  mValue: TJSONValue;
  mFiles: TJSONArray;
  mFileItem, mTodo: TJSONObject;
begin
  AChoices := Default(TAtlasTodoChoices);
  mValue := ParseJson(AJson);
  try
    mFiles := ArrayOf(mValue, 'files');
    Result := mFiles <> nil;
    if not Result then
    begin
      Exit;
    end;
    for mFileItem in ObjectsOf(mFiles) do
    begin
      AddDistinct(AChoices.Units, TextOf(mFileItem, 'unit'));
      for mTodo in ObjectsOf(ArrayOf(mFileItem, 'todos')) do
      begin
        AddTodoChoices(AChoices, mTodo);
      end;
    end;
    SortTexts(AChoices.Categories);
    SortTexts(AChoices.Owners);
    SortTexts(AChoices.Units);
    SortTexts(AChoices.Keywords);
  finally
    mValue.Free;
  end;
end;

end.
