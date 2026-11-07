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
  mIndex: Integer;
begin
  Result := Trim(APath);
  for mIndex := Length(Result) downto 1 do
  begin
    if CharInSet(Result[mIndex], ['\', '/']) then
    begin
      Exit(Copy(Result, mIndex + 1, MaxInt));
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
  mSummary: TAtlasProjectSummary;
begin
  Result := '';
  if Project = '' then
  begin
    Exit;
  end;
  mSummary := TAtlasProjectSummary.Create(Project);
  Result := mSummary.Name;
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
  mIndex, mPosition: Integer;
  mItem: TAtlasSavedItem;
begin
  for mIndex := 1 to High(AItems) do
  begin
    mItem := AItems[mIndex];
    mPosition := mIndex - 1;
    while (mPosition >= 0) and (Compare(AItems[mPosition], mItem) > 0) do
    begin
      AItems[mPosition + 1] := AItems[mPosition];
      Dec(mPosition);
    end;
    AItems[mPosition + 1] := mItem;
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
  mFavorite: TAtlasFavorite;
  mItem: TAtlasSavedItem;
begin
  Result := nil;
  for mFavorite in AFavorites do
  begin
    mItem := Default(TAtlasSavedItem);
    mItem.Kind := TAtlasSavedKind.Favorite;
    mItem.Id := mFavorite.Key;
    mItem.Text := mFavorite.DisplayName;
    mItem.Line := -1;
    mItem.Detail := mFavorite.Signature;
    mItem.UnitName := mFavorite.UnitName;
    mItem.TypeName := mFavorite.TypeName;
    mItem.Member := mFavorite.Member;
    Result := Result + [mItem];
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
  mWords: TArray<string>;
  mWord, mHaystack: string;
  mItem: TAtlasSavedItem;
  mMatches: Boolean;
begin
  mWords := LowerCase(APattern).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if Length(mWords) = 0 then
  begin
    Exit(AItems);
  end;
  Result := nil;
  for mItem in AItems do
  begin
    mHaystack := LowerCase(mItem.Text + #1 + NameOfPath(mItem.FileName) + #1 + mItem.ProjectName + #1 + mItem.Detail +
      #1 + mItem.UnitName);
    mMatches := True;
    for mWord in mWords do
    begin
      if Pos(mWord, mHaystack) = 0 then
      begin
        mMatches := False;
        Break;
      end;
    end;
    if mMatches then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

/// <summary>Enthält ALine AWord als ganzes Wort (Groß/klein egal)?</summary>
function HasWord(const ALine, AWord: string): Boolean;
var
  mLower, mWanted: string;
  mStart, mFound: Integer;
begin
  Result := False;
  if AWord = '' then
  begin
    Exit;
  end;
  mLower := LowerCase(ALine);
  mWanted := LowerCase(AWord);
  mStart := 1;
  repeat
    mFound := Pos(mWanted, mLower, mStart);
    if mFound = 0 then
    begin
      Exit;
    end;
    if ((mFound = 1) or not TTextChars.IsIdentChar(mLower[mFound - 1])) and
      ((mFound + Length(mWanted) > Length(mLower)) or not TTextChars.IsIdentChar(mLower[mFound + Length(mWanted)])) then
    begin
      Exit(True);
    end;
    mStart := mFound + 1;
  until False;
end;

/// <summary>Beginnt ALine (ohne Leerraum) mit "ATypeName =" bzw. "ATypeName&lt;…&gt; ="?</summary>
function IsTypeHead(const ALine, ATypeName: string): Boolean;
var
  mText: string;
  mIndex: Integer;
begin
  mText := TrimLeft(ALine);
  Result := False;
  if not SameText(Copy(mText, 1, Length(ATypeName)), ATypeName) then
  begin
    Exit;
  end;
  mIndex := Length(ATypeName) + 1;
  if (mIndex <= Length(mText)) and TTextChars.IsIdentChar(mText[mIndex]) then
  begin
    Exit;
  end;
  // Generische Parameter überspringen.
  if (mIndex <= Length(mText)) and (mText[mIndex] = '<') then
  begin
    while (mIndex <= Length(mText)) and (mText[mIndex] <> '>') do
    begin
      Inc(mIndex);
    end;
    Inc(mIndex);
  end;
  while (mIndex <= Length(mText)) and (mText[mIndex] = ' ') do
  begin
    Inc(mIndex);
  end;
  Result := (mIndex <= Length(mText)) and (mText[mIndex] = '=');
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
  mWanted: string;
  mDeclaration, mBody: Integer;
begin
  Result := -1;
  if Trim(AMember) = '' then
  begin
    Exit;
  end;
  mWanted := AMember;
  if ATypeName <> '' then
  begin
    mWanted := ATypeName + '.' + AMember;
  end;
  // Methoden und Routinen: zuerst die Deklaration, sonst die Implementierung.
  FindMethod(AText, mWanted, mDeclaration, mBody);
  Result := mDeclaration;
  // Eigenschaften, Felder und Ereignisse: in der Deklaration des Typs.
  if (Result < 0) and (ATypeName <> '') then
  begin
    Result := MemberLine(AText, ATypeName, AMember);
  end;
  if Result < 0 then
  begin
    Result := mBody;
  end;
end;

class function TAtlasWelcomeSaved.ResolvePath(const AFolder, ARelative: string): string;
var
  mParts, mKept: TArray<string>;
  mPart, mPath: string;
begin
  mPath := Trim(ARelative).Replace('/', '\');
  // Laufwerk („C:\…“) oder Netzwerkpfad („\\server\…“): schon absolut.
  if ((Length(mPath) >= 2) and (mPath[2] = ':')) or mPath.StartsWith('\\') or (Trim(AFolder) = '') then
  begin
    Exit(mPath);
  end;
  mPath := Trim(AFolder).Replace('/', '\');
  if not mPath.EndsWith('\') then
  begin
    mPath := mPath + '\';
  end;
  mPath := mPath + Trim(ARelative).Replace('/', '\');
  mParts := mPath.Split(['\']);
  mKept := nil;
  for mPart in mParts do
  begin
    if mPart = '.' then
    begin
      Continue;
    end;
    // „..“ nimmt den letzten Teil weg, aber nie das Laufwerk.
    if mPart = '..' then
    begin
      if Length(mKept) > 1 then
      begin
        SetLength(mKept, Length(mKept) - 1);
      end;
      Continue;
    end;
    mKept := mKept + [mPart];
  end;
  Result := string.Join('\', mKept);
end;

class function TAtlasWelcomeSaved.GroupProjects(const AGroupFile, AText: string): TArray<string>;
const
  cMarker = 'include="';
var
  mLower, mFolder, mValue: string;
  mStart, mFound, mStop, mIndex: Integer;
begin
  Result := nil;
  mFolder := '';
  for mIndex := Length(AGroupFile) downto 1 do
  begin
    if CharInSet(AGroupFile[mIndex], ['\', '/']) then
    begin
      mFolder := Copy(AGroupFile, 1, mIndex - 1);
      Break;
    end;
  end;
  mLower := LowerCase(AText);
  mStart := 1;
  repeat
    mFound := Pos('<projects ', mLower, mStart);
    if mFound = 0 then
    begin
      Break;
    end;
    mStop := Pos('>', mLower, mFound);
    if mStop = 0 then
    begin
      Break;
    end;
    mIndex := Pos(cMarker, mLower, mFound);
    if (mIndex > 0) and (mIndex < mStop) then
    begin
      Inc(mIndex, Length(cMarker));
      mValue := Copy(AText, mIndex, Pos('"', AText, mIndex) - mIndex);
      if Trim(mValue) <> '' then
      begin
        Result := Result + [ResolvePath(mFolder, mValue)];
      end;
    end;
    mStart := mStop + 1;
  until False;
end;

class function TAtlasWelcomeSaved.FindUnit(const AFiles: TArray<TAtlasIndexFile>; const AUnitName: string): string;
var
  mEntry: TAtlasIndexFile;
begin
  Result := '';
  if Trim(AUnitName) = '' then
  begin
    Exit;
  end;
  for mEntry in AFiles do
  begin
    if SameText(mEntry.UnitName, Trim(AUnitName)) then
    begin
      Exit(mEntry.FileName);
    end;
  end;
end;

end.
