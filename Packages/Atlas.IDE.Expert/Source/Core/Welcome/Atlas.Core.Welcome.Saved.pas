unit Atlas.Core.Welcome.Saved;

// Bereich „Weiterarbeiten“ der Willkommensseite (#755), Reiter „Gemerkt“,
// Teil ohne VCL und Open Tools API: persönliche Notizen (#545), benannte
// Lesezeichen (#622) und angeheftete Favoriten (#458) aller Projekte in einer
// Liste mit Art, Text bzw. Name, Datei und Zeile sowie Projekt, dazu Filter
// und das Sprungziel eines Favoriten.
// - Gelesen werden nur die Dateien dieser Funktionen, ohne Server:
//   %LOCALAPPDATA%\Atlas\Notes\*.json (TAtlasNotes.LoadAll), die Lesezeichen
//   neben den .dproj der zuletzt geöffneten Projekte (TAtlasBookmarks.Load)
//   und %APPDATA%\Atlas\favorites.json (TAtlasFavorites.LoadFromFile).
// - Reihenfolge: je Projekt (nach Name) erst die Notizen, dann die
//   Lesezeichen, jeweils nach Datei und Zeile; Favoriten gelten für alle
//   Projekte und stehen am Ende in der Reihenfolge des Anheftens.
// - Ein Favorit kennt nur Typ, Member und Unit. Sein Sprungziel ist die
//   Deklaration in der Unit (DeclarationLine); die Datei der Unit kommt aus
//   dem Index-Cache auf der Platte (FindUnit, #760).
// - Lesezeichen liegen je Projektordner. Zu einer Projektgruppe in der Liste
//   der IDE zählen auch die Ordner ihrer Projekte (GroupProjects).

interface

uses
  System.SysUtils,
  Atlas.Core.Notes.Store,
  Atlas.Core.Bookmarks.Store,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Welcome.IndexFiles;

type
{$SCOPEDENUMS ON}
  TAtlasSavedKind = (Note, Bookmark, Favorite);
{$SCOPEDENUMS OFF}

  TAtlasSavedItem = record
    Kind: TAtlasSavedKind;
    /// <summary>Kennung der Notiz bzw. des Lesezeichens; beim Favoriten der Schlüssel "typ|member".</summary>
    Id: string;
    /// <summary>Titel der Notiz, Name des Lesezeichens bzw. "TDataSet.Open".</summary>
    Text: string;
    /// <summary>Vollständiger Pfad; '' beim Favoriten.</summary>
    FileName: string;
    /// <summary>Zeile, 0-basiert; -1 ohne (Favorit).</summary>
    Line: Integer;
    /// <summary>Pfad der Projektdatei; '' beim Favoriten (gilt für alle Projekte).</summary>
    Project: string;
    /// <summary>Lesezeichen: Methode; Notiz: weitere Zeilen; Favorit: Signatur.</summary>
    Detail: string;
    /// <summary>Notiz verwaist bzw. Lesezeichen nicht gefunden (letzte bekannte Zeile).</summary>
    Lost: Boolean;
    /// <summary>Nur Favorit: Unit, Typ und Member.</summary>
    UnitName: string;
    TypeName: string;
    Member: string;
    /// <summary>„Kunde.pas:42“; beim Favoriten die Unit.</summary>
    function Place: string;
    /// <summary>Name des Projekts ohne Endung; '' beim Favoriten.</summary>
    function ProjectName: string;
  end;

  TAtlasSavedItems = TArray<TAtlasSavedItem>;

  TAtlasWelcomeSaved = class
  public
    class function FromNotes(const ABooks: TArray<TAtlasNoteBook>): TAtlasSavedItems; static;
    /// <summary>Lesezeichen; dieselbe Datei (Projekte im selben Ordner) zählt einmal.</summary>
    class function FromBookmarks(const ALists: TArray<TAtlasBookmarkList>): TAtlasSavedItems; static;
    class function FromFavorites(const AFavorites: TArray<TAtlasFavorite>): TAtlasSavedItems; static;
    /// <summary>Alle Einträge in der Reihenfolge der Liste (siehe Kopf der Unit).</summary>
    class function Collect(const ABooks: TArray<TAtlasNoteBook>; const ALists: TArray<TAtlasBookmarkList>;
      const AFavorites: TArray<TAtlasFavorite>): TAtlasSavedItems; static;
    /// <summary>Einträge, deren Text, Datei, Projekt, Detail oder Unit jedes Wort von APattern enthält
    /// (Groß/klein egal); leeres Muster: alle.</summary>
    class function Filter(const AItems: TAtlasSavedItems; const APattern: string): TAtlasSavedItems; static;
    /// <summary>Zeile (0-basiert) der Deklaration von ATypeName.AMember in AText: Methodenkopf in der
    /// Typdeklaration, sonst Implementierung, sonst die erste Zeile nach "ATypeName =" mit AMember als Wort;
    /// ohne Typ der erste Routinenkopf AMember. -1, wenn nichts passt.</summary>
    class function DeclarationLine(const AText, ATypeName, AMember: string): Integer; static;
    /// <summary>Datei der Unit AUnitName unter AFiles; '' ohne.</summary>
    class function FindUnit(const AFiles: TArray<TAtlasIndexFile>; const AUnitName: string): string; static;
    /// <summary>Projekte der Projektgruppe AGroupFile mit dem Inhalt AText (&lt;Projects Include="…"/&gt;),
    /// relative Pfade aufgelöst gegen den Ordner der Gruppe.</summary>
    class function GroupProjects(const AGroupFile, AText: string): TArray<string>; static;
    /// <summary>ARelative (mit „\“ oder „/“, auch „..“) gegen den Ordner AFolder; absolute Pfade bleiben.</summary>
    class function ResolvePath(const AFolder, ARelative: string): string; static;
  end;

implementation

uses
  Atlas.Core.Editor.MethodToggle,
  Atlas.Core.Projects.Summary,
  Atlas.Text.Chars;

function NameOfPath(const APath: string): string;
var
  Index: Integer;
begin
  Result := Trim(APath);
  for Index := Length(Result) downto 1 do
    if CharInSet(Result[Index], ['\', '/']) then
      Exit(Copy(Result, Index + 1, MaxInt));
end;

{ TAtlasSavedItem }

function TAtlasSavedItem.Place: string;
begin
  if Kind = TAtlasSavedKind.Favorite then
    Exit(UnitName);
  Result := NameOfPath(FileName);
  if Line >= 0 then
    Result := Result + ':' + IntToStr(Line + 1);
end;

function TAtlasSavedItem.ProjectName: string;
var
  Summary: TAtlasProjectSummary;
begin
  Result := '';
  if Project = '' then
    Exit;
  Summary := TAtlasProjectSummary.Create(Project);
  Result := Summary.Name;
end;

{ Sortieren }

function Compare(const A, B: TAtlasSavedItem): Integer;
begin
  Result := CompareText(A.ProjectName, B.ProjectName);
  if Result = 0 then
    Result := CompareText(A.Project, B.Project);
  if Result = 0 then
    Result := Ord(A.Kind) - Ord(B.Kind);
  if Result = 0 then
    Result := CompareText(NameOfPath(A.FileName), NameOfPath(B.FileName));
  if Result = 0 then
    Result := CompareText(A.FileName, B.FileName);
  if Result = 0 then
    Result := A.Line - B.Line;
end;

/// <summary>Stabil sortieren (Einfügen); die Listen sind klein.</summary>
procedure SortItems(var AItems: TAtlasSavedItems);
var
  Index, Position: Integer;
  Item: TAtlasSavedItem;
begin
  for Index := 1 to High(AItems) do
  begin
    Item := AItems[Index];
    Position := Index - 1;
    while (Position >= 0) and (Compare(AItems[Position], Item) > 0) do
    begin
      AItems[Position + 1] := AItems[Position];
      Dec(Position);
    end;
    AItems[Position + 1] := Item;
  end;
end;

{ TAtlasWelcomeSaved }

class function TAtlasWelcomeSaved.FromNotes(const ABooks: TArray<TAtlasNoteBook>): TAtlasSavedItems;
var
  Book: TAtlasNoteBook;
  Note: TAtlasNote;
  Item: TAtlasSavedItem;
  Lines: TArray<string>;
begin
  Result := nil;
  for Book in ABooks do
    for Note in Book.Notes do
    begin
      Item := Default(TAtlasSavedItem);
      Item.Kind := TAtlasSavedKind.Note;
      Item.Id := Note.Id;
      Item.Text := Note.Title;
      Item.FileName := Note.FileName;
      Item.Line := Note.Line;
      Item.Project := Book.Project;
      Item.Lost := Note.Orphaned;
      Lines := Note.Text.Split([#10]);
      if Length(Lines) > 1 then
        Item.Detail := Trim(string.Join(' ', Lines));
      Result := Result + [Item];
    end;
end;

class function TAtlasWelcomeSaved.FromBookmarks(const ALists: TArray<TAtlasBookmarkList>): TAtlasSavedItems;
var
  List: TAtlasBookmarkList;
  Mark: TAtlasBookmark;
  Item, Known: TAtlasSavedItem;
  Duplicate: Boolean;
begin
  Result := nil;
  for List in ALists do
    for Mark in List.Bookmarks do
    begin
      Duplicate := False;
      for Known in Result do
        if SameText(Known.Id, Mark.Id) and TAtlasBookmarks.SameFile(Known.FileName, Mark.FileName) then
          Duplicate := True;
      if Duplicate then
        Continue;
      Item := Default(TAtlasSavedItem);
      Item.Kind := TAtlasSavedKind.Bookmark;
      Item.Id := Mark.Id;
      Item.Text := Mark.Name;
      Item.FileName := Mark.FileName;
      Item.Line := Mark.Line;
      Item.Project := List.Project;
      Item.Detail := Mark.Method;
      Item.Lost := Mark.Lost;
      Result := Result + [Item];
    end;
end;

class function TAtlasWelcomeSaved.FromFavorites(const AFavorites: TArray<TAtlasFavorite>): TAtlasSavedItems;
var
  Favorite: TAtlasFavorite;
  Item: TAtlasSavedItem;
begin
  Result := nil;
  for Favorite in AFavorites do
  begin
    Item := Default(TAtlasSavedItem);
    Item.Kind := TAtlasSavedKind.Favorite;
    Item.Id := Favorite.Key;
    Item.Text := Favorite.DisplayName;
    Item.Line := -1;
    Item.Detail := Favorite.Signature;
    Item.UnitName := Favorite.UnitName;
    Item.TypeName := Favorite.TypeName;
    Item.Member := Favorite.Member;
    Result := Result + [Item];
  end;
end;

class function TAtlasWelcomeSaved.Collect(const ABooks: TArray<TAtlasNoteBook>;
  const ALists: TArray<TAtlasBookmarkList>; const AFavorites: TArray<TAtlasFavorite>): TAtlasSavedItems;
begin
  Result := FromNotes(ABooks) + FromBookmarks(ALists);
  SortItems(Result);
  Result := Result + FromFavorites(AFavorites);
end;

class function TAtlasWelcomeSaved.Filter(const AItems: TAtlasSavedItems; const APattern: string): TAtlasSavedItems;
var
  Words: TArray<string>;
  Word, Haystack: string;
  Item: TAtlasSavedItem;
  Matches: Boolean;
begin
  Words := LowerCase(APattern).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if Length(Words) = 0 then
    Exit(AItems);
  Result := nil;
  for Item in AItems do
  begin
    Haystack := LowerCase(Item.Text + #1 + NameOfPath(Item.FileName) + #1 + Item.ProjectName + #1 + Item.Detail +
      #1 + Item.UnitName);
    Matches := True;
    for Word in Words do
      if Pos(Word, Haystack) = 0 then
      begin
        Matches := False;
        Break;
      end;
    if Matches then
      Result := Result + [Item];
  end;
end;

/// <summary>Enthält ALine AWord als ganzes Wort (Groß/klein egal)?</summary>
function HasWord(const ALine, AWord: string): Boolean;
var
  Lower, Wanted: string;
  Start, Found: Integer;
begin
  Result := False;
  if AWord = '' then
    Exit;
  Lower := LowerCase(ALine);
  Wanted := LowerCase(AWord);
  Start := 1;
  repeat
    Found := Pos(Wanted, Lower, Start);
    if Found = 0 then
      Exit;
    if ((Found = 1) or not TTextChars.IsIdentChar(Lower[Found - 1])) and
      ((Found + Length(Wanted) > Length(Lower)) or not TTextChars.IsIdentChar(Lower[Found + Length(Wanted)])) then
      Exit(True);
    Start := Found + 1;
  until False;
end;

/// <summary>Beginnt ALine (ohne Leerraum) mit "ATypeName =" bzw. "ATypeName<…> ="?</summary>
function IsTypeHead(const ALine, ATypeName: string): Boolean;
var
  Text: string;
  Index: Integer;
begin
  Text := TrimLeft(ALine);
  Result := False;
  if not SameText(Copy(Text, 1, Length(ATypeName)), ATypeName) then
    Exit;
  Index := Length(ATypeName) + 1;
  if (Index <= Length(Text)) and TTextChars.IsIdentChar(Text[Index]) then
    Exit;
  // Generische Parameter überspringen.
  if (Index <= Length(Text)) and (Text[Index] = '<') then
  begin
    while (Index <= Length(Text)) and (Text[Index] <> '>') do
      Inc(Index);
    Inc(Index);
  end;
  while (Index <= Length(Text)) and (Text[Index] = ' ') do
    Inc(Index);
  Result := (Index <= Length(Text)) and (Text[Index] = '=');
end;

class function TAtlasWelcomeSaved.DeclarationLine(const AText, ATypeName, AMember: string): Integer;
var
  Places: TArray<TAtlasMethodPlace>;
  Place: TAtlasMethodPlace;
  Wanted: string;
  Lines: TArray<string>;
  Index, Body, Line: Integer;
begin
  Result := -1;
  if Trim(AMember) = '' then
    Exit;
  Wanted := AMember;
  if ATypeName <> '' then
    Wanted := ATypeName + '.' + AMember;
  // Methoden und Routinen: zuerst die Deklaration, sonst die Implementierung.
  Places := TAtlasMethodToggle.Places(AText);
  Body := -1;
  for Place in Places do
    if SameText(Place.Name, Wanted) then
    begin
      if not Place.IsBody then
        Exit(Place.Line);
      if Body < 0 then
        Body := Place.Line;
    end;
  // Eigenschaften, Felder und Ereignisse: in der Deklaration des Typs.
  if ATypeName <> '' then
  begin
    Lines := AText.Replace(#13, '').Split([#10]);
    for Index := 0 to High(Lines) do
      if IsTypeHead(Lines[Index], ATypeName) then
      begin
        for Line := Index + 1 to High(Lines) do
        begin
          if HasWord(Lines[Line], AMember) then
            Exit(Line);
          // Ende der Deklaration.
          if SameText(Trim(Lines[Line]), 'end;') then
            Break;
        end;
        Break;
      end;
  end;
  Result := Body;
end;

class function TAtlasWelcomeSaved.ResolvePath(const AFolder, ARelative: string): string;
var
  Parts, Kept: TArray<string>;
  Part, Path: string;
begin
  Path := Trim(ARelative).Replace('/', '\');
  // Laufwerk („C:\…“) oder Netzwerkpfad („\\server\…“): schon absolut.
  if ((Length(Path) >= 2) and (Path[2] = ':')) or Path.StartsWith('\\') or (Trim(AFolder) = '') then
    Exit(Path);
  Path := Trim(AFolder).Replace('/', '\');
  if not Path.EndsWith('\') then
    Path := Path + '\';
  Path := Path + Trim(ARelative).Replace('/', '\');
  Parts := Path.Split(['\']);
  Kept := nil;
  for Part in Parts do
  begin
    if Part = '.' then
      Continue;
    // „..“ nimmt den letzten Teil weg, aber nie das Laufwerk.
    if Part = '..' then
    begin
      if Length(Kept) > 1 then
        SetLength(Kept, Length(Kept) - 1);
      Continue;
    end;
    Kept := Kept + [Part];
  end;
  Result := string.Join('\', Kept);
end;

class function TAtlasWelcomeSaved.GroupProjects(const AGroupFile, AText: string): TArray<string>;
const
  Marker = 'include="';
var
  Lower, Folder, Value: string;
  Start, Found, Stop, Index: Integer;
begin
  Result := nil;
  Folder := '';
  for Index := Length(AGroupFile) downto 1 do
    if CharInSet(AGroupFile[Index], ['\', '/']) then
    begin
      Folder := Copy(AGroupFile, 1, Index - 1);
      Break;
    end;
  Lower := LowerCase(AText);
  Start := 1;
  repeat
    Found := Pos('<projects ', Lower, Start);
    if Found = 0 then
      Break;
    Stop := Pos('>', Lower, Found);
    if Stop = 0 then
      Break;
    Index := Pos(Marker, Lower, Found);
    if (Index > 0) and (Index < Stop) then
    begin
      Inc(Index, Length(Marker));
      Value := Copy(AText, Index, Pos('"', AText, Index) - Index);
      if Trim(Value) <> '' then
        Result := Result + [ResolvePath(Folder, Value)];
    end;
    Start := Stop + 1;
  until False;
end;

class function TAtlasWelcomeSaved.FindUnit(const AFiles: TArray<TAtlasIndexFile>; const AUnitName: string): string;
var
  Entry: TAtlasIndexFile;
begin
  Result := '';
  if Trim(AUnitName) = '' then
    Exit;
  for Entry in AFiles do
    if SameText(Entry.UnitName, Trim(AUnitName)) then
      Exit(Entry.FileName);
end;

end.
