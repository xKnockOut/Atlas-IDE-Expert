unit Atlas.Core.Welcome.Saved;

// Bereich „Weiterarbeiten“ der Willkommensseite (#755), Reiter „Gemerkt“,
// Teil ohne VCL und Open Tools API: persönliche Notizen (#545), benannte
// Lesezeichen (#622) und angeheftete Favoriten (#458) aller Projekte in einer
// Liste mit Art, Text bzw. Name, Datei und Zeile sowie Projekt, dazu Filter
// und das Sprungziel eines Favoriten.
// - Notizen und Lesezeichen liefert das Modul Lesezeichen über den Vertrag
//   IAtlasSavedPlacesSource (#1456); fehlt es, bleiben die Favoriten aus
//   %APPDATA%\Atlas\favorites.json (TAtlasFavorites.LoadFromFile).
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
  Atlas.Core.Completion.Favorites,
  Atlas.Core.SavedPlaces.Contract,
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
    /// <summary>Notizen und Lesezeichen des Moduls Lesezeichen als Einträge.</summary>
    class function FromPlaces(const APlaces: TAtlasSavedPlaces): TAtlasSavedItems; static;
    class function FromFavorites(const AFavorites: TArray<TAtlasFavorite>): TAtlasSavedItems; static;
    /// <summary>Alle Einträge in der Reihenfolge der Liste (siehe Kopf der Unit).</summary>
    class function Collect(const APlaces: TAtlasSavedPlaces; const AFavorites: TArray<TAtlasFavorite>):
      TAtlasSavedItems; static;
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
  begin
    if CharInSet(Result[Index], ['\', '/']) then
    begin
      Exit(Copy(Result, Index + 1, MaxInt));
    end;
  end;
end;

{ TAtlasSavedItem }

function TAtlasSavedItem.Place: string;
begin
  if Kind = TAtlasSavedKind.Favorite then
  begin
    Exit(UnitName);
  end;
  Result := NameOfPath(FileName);
  if Line >= 0 then
  begin
    Result := Result + ':' + IntToStr(Line + 1);
  end;
end;

function TAtlasSavedItem.ProjectName: string;
var
  Summary: TAtlasProjectSummary;
begin
  Result := '';
  if Project = '' then
  begin
    Exit;
  end;
  Summary := TAtlasProjectSummary.Create(Project);
  Result := Summary.Name;
end;

{ Sortieren }

function Compare(const A, B: TAtlasSavedItem): Integer;
begin
  Result := CompareText(A.ProjectName, B.ProjectName);
  if Result = 0 then
  begin
    Result := CompareText(A.Project, B.Project);
  end;
  if Result = 0 then
  begin
    Result := Ord(A.Kind) - Ord(B.Kind);
  end;
  if Result = 0 then
  begin
    Result := CompareText(NameOfPath(A.FileName), NameOfPath(B.FileName));
  end;
  if Result = 0 then
  begin
    Result := CompareText(A.FileName, B.FileName);
  end;
  if Result = 0 then
  begin
    Result := A.Line - B.Line;
  end;
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

class function TAtlasWelcomeSaved.FromPlaces(const APlaces: TAtlasSavedPlaces): TAtlasSavedItems;
var
  mPlace: TAtlasSavedPlace;
  mItem: TAtlasSavedItem;
begin
  Result := nil;
  for mPlace in APlaces do
  begin
    mItem := Default(TAtlasSavedItem);
    mItem.Kind := TAtlasSavedKind.Note;
    if mPlace.Kind = TAtlasSavedPlaceKind.Bookmark then
    begin
      mItem.Kind := TAtlasSavedKind.Bookmark;
    end;
    mItem.Id := mPlace.Id;
    mItem.Text := mPlace.Text;
    mItem.FileName := mPlace.FileName;
    mItem.Line := mPlace.Line;
    mItem.Project := mPlace.Project;
    mItem.Detail := mPlace.Detail;
    mItem.Lost := mPlace.Lost;
    Result := Result + [mItem];
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

class function TAtlasWelcomeSaved.Collect(const APlaces: TAtlasSavedPlaces;
  const AFavorites: TArray<TAtlasFavorite>): TAtlasSavedItems;
begin
  Result := FromPlaces(APlaces);
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
  begin
    Exit(AItems);
  end;
  Result := nil;
  for Item in AItems do
  begin
    Haystack := LowerCase(Item.Text + #1 + NameOfPath(Item.FileName) + #1 + Item.ProjectName + #1 + Item.Detail +
      #1 + Item.UnitName);
    Matches := True;
    for Word in Words do
    begin
      if Pos(Word, Haystack) = 0 then
      begin
        Matches := False;
        Break;
      end;
    end;
    if Matches then
    begin
      Result := Result + [Item];
    end;
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
  begin
    Exit;
  end;
  Lower := LowerCase(ALine);
  Wanted := LowerCase(AWord);
  Start := 1;
  repeat
    Found := Pos(Wanted, Lower, Start);
    if Found = 0 then
    begin
      Exit;
    end;
    if ((Found = 1) or not TTextChars.IsIdentChar(Lower[Found - 1])) and
      ((Found + Length(Wanted) > Length(Lower)) or not TTextChars.IsIdentChar(Lower[Found + Length(Wanted)])) then
    begin
      Exit(True);
    end;
    Start := Found + 1;
  until False;
end;

/// <summary>Beginnt ALine (ohne Leerraum) mit "ATypeName =" bzw. "ATypeName&lt;…&gt; ="?</summary>
function IsTypeHead(const ALine, ATypeName: string): Boolean;
var
  Text: string;
  Index: Integer;
begin
  Text := TrimLeft(ALine);
  Result := False;
  if not SameText(Copy(Text, 1, Length(ATypeName)), ATypeName) then
  begin
    Exit;
  end;
  Index := Length(ATypeName) + 1;
  if (Index <= Length(Text)) and TTextChars.IsIdentChar(Text[Index]) then
  begin
    Exit;
  end;
  // Generische Parameter überspringen.
  if (Index <= Length(Text)) and (Text[Index] = '<') then
  begin
    while (Index <= Length(Text)) and (Text[Index] <> '>') do
    begin
      Inc(Index);
    end;
    Inc(Index);
  end;
  while (Index <= Length(Text)) and (Text[Index] = ' ') do
  begin
    Inc(Index);
  end;
  Result := (Index <= Length(Text)) and (Text[Index] = '=');
end;

/// <summary>Erste Deklaration und erste Implementierung der Methode bzw. Routine AWanted in AText; -1 ohne.
/// </summary>
procedure FindMethod(const AText, AWanted: string; out ADeclaration, ABody: Integer);
var
  mPlace: TAtlasMethodPlace;
begin
  ADeclaration := -1;
  ABody := -1;
  for mPlace in TAtlasMethodToggle.Places(AText) do
  begin
    if not SameText(mPlace.Name, AWanted) then
    begin
      Continue;
    end;
    if not mPlace.IsBody and (ADeclaration < 0) then
    begin
      ADeclaration := mPlace.Line;
    end
    else if mPlace.IsBody and (ABody < 0) then
    begin
      ABody := mPlace.Line;
    end;
  end;
end;

/// <summary>Zeile von AMember (Eigenschaft, Feld, Ereignis) in der Deklaration von ATypeName; -1 ohne.</summary>
function MemberLine(const AText, ATypeName, AMember: string): Integer;
var
  mLines: TArray<string>;
  mIndex, mLine: Integer;
begin
  Result := -1;
  mLines := AText.Replace(#13, '').Split([#10]);
  mIndex := 0;
  while (mIndex <= High(mLines)) and not IsTypeHead(mLines[mIndex], ATypeName) do
  begin
    Inc(mIndex);
  end;
  for mLine := mIndex + 1 to High(mLines) do
  begin
    if HasWord(mLines[mLine], AMember) then
    begin
      Exit(mLine);
    end;
    // Ende der Deklaration.
    if SameText(Trim(mLines[mLine]), 'end;') then
    begin
      Exit;
    end;
  end;
end;

class function TAtlasWelcomeSaved.DeclarationLine(const AText, ATypeName, AMember: string): Integer;
var
  Wanted: string;
  Declaration, Body: Integer;
begin
  Result := -1;
  if Trim(AMember) = '' then
  begin
    Exit;
  end;
  Wanted := AMember;
  if ATypeName <> '' then
  begin
    Wanted := ATypeName + '.' + AMember;
  end;
  // Methoden und Routinen: zuerst die Deklaration, sonst die Implementierung.
  FindMethod(AText, Wanted, Declaration, Body);
  Result := Declaration;
  // Eigenschaften, Felder und Ereignisse: in der Deklaration des Typs.
  if (Result < 0) and (ATypeName <> '') then
  begin
    Result := MemberLine(AText, ATypeName, AMember);
  end;
  if Result < 0 then
  begin
    Result := Body;
  end;
end;

class function TAtlasWelcomeSaved.ResolvePath(const AFolder, ARelative: string): string;
var
  Parts, Kept: TArray<string>;
  Part, Path: string;
begin
  Path := Trim(ARelative).Replace('/', '\');
  // Laufwerk („C:\…“) oder Netzwerkpfad („\\server\…“): schon absolut.
  if ((Length(Path) >= 2) and (Path[2] = ':')) or Path.StartsWith('\\') or (Trim(AFolder) = '') then
  begin
    Exit(Path);
  end;
  Path := Trim(AFolder).Replace('/', '\');
  if not Path.EndsWith('\') then
  begin
    Path := Path + '\';
  end;
  Path := Path + Trim(ARelative).Replace('/', '\');
  Parts := Path.Split(['\']);
  Kept := nil;
  for Part in Parts do
  begin
    if Part = '.' then
    begin
      Continue;
    end;
    // „..“ nimmt den letzten Teil weg, aber nie das Laufwerk.
    if Part = '..' then
    begin
      if Length(Kept) > 1 then
      begin
        SetLength(Kept, Length(Kept) - 1);
      end;
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
  begin
    if CharInSet(AGroupFile[Index], ['\', '/']) then
    begin
      Folder := Copy(AGroupFile, 1, Index - 1);
      Break;
    end;
  end;
  Lower := LowerCase(AText);
  Start := 1;
  repeat
    Found := Pos('<projects ', Lower, Start);
    if Found = 0 then
    begin
      Break;
    end;
    Stop := Pos('>', Lower, Found);
    if Stop = 0 then
    begin
      Break;
    end;
    Index := Pos(Marker, Lower, Found);
    if (Index > 0) and (Index < Stop) then
    begin
      Inc(Index, Length(Marker));
      Value := Copy(AText, Index, Pos('"', AText, Index) - Index);
      if Trim(Value) <> '' then
      begin
        Result := Result + [ResolvePath(Folder, Value)];
      end;
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
  begin
    Exit;
  end;
  for Entry in AFiles do
  begin
    if SameText(Entry.UnitName, Trim(AUnitName)) then
    begin
      Exit(Entry.FileName);
    end;
  end;
end;

end.
