unit Atlas.Core.Bookmarks.Store;

// Benannte Lesezeichen (#622), ohne VCL und Open Tools API: Liste je Projekt
// (Anlegen, Umbenennen, Löschen, Umsortieren, Filtern, Wiederfinden) und die
// Ablage. Dieselbe Liste hält die schnellen Lesezeichen (#1104, Art Quick,
// nummeriert 1–9 oder unnummeriert, ohne Namen); ihre Befehle stehen in
// Atlas.Core.Bookmarks.Quick.
//
// Ein Lesezeichen merkt sich Datei, Methode (voller Name wie
// TKunde.Laden, dazu die Parametertypen für Überladungen), den Abstand der
// Zeile zum Methodenanfang (Kopfzeile) und den Zeilentext samt je zwei
// Nachbarzeilen (Atlas.Core.Editor.LineAnchor). Find sucht es im aktuellen
// Text wieder:
//   1. Mit Methode: zuerst die Methode (Rümpfe aus Atlas.Core.Editor.
//      MethodToggle, gleicher Name; bei Überladungen zuerst gleiche
//      Parametertypen), dann den Zeilentext in ihrem Rumpf, am nächsten zur
//      Zeile Methodenanfang + Abstand. Fehlt die Methode oder der Text in
//      ihr, ist das Lesezeichen „nicht gefunden“ (Lost) und behält seine
//      letzte Zeile.
//   2. Ohne Methode (etwa im interface-Teil): der Zeilentext in der ganzen
//      Datei wie bei den Notizen (#545).
// Ein nicht gefundenes Lesezeichen bleibt in der Liste und wird beim
// nächsten Wiederfinden wieder gültig.
//
// Ablage je Projekt in einer Datei neben der .dproj (FileFor):
//   - lokal (bookmarks.shared aus): .atlas-bookmarks.json; Save trägt sie in
//     .git/info/exclude des Repositorys ein (nur lokal, nichts Eingechecktes
//     ändert sich), damit sie nicht versehentlich eingecheckt wird;
//   - für das Team (bookmarks.shared an): atlas-bookmarks.json zum
//     Einchecken. Gibt es sie noch nicht, liest Load die lokale Datei, und
//     das nächste Speichern legt die Datei des Teams damit an.
// Projekte im selben Ordner teilen sich die Datei. Dateipfade stehen relativ
// zum Ordner der Datei (mit "/"), damit sie in jedem Klon gelten.
// Lesbar ohne Server und ohne geöffnetes Projekt (Load), etwa für
// „Weiterarbeiten“ auf der Willkommensseite (#755).
// Lesen und Schreiben über TAtlasDataFile (Bericht N3): atomar ersetzt
// (früher Löschen und Umbenennen), eine unbrauchbare Datei liegt danach als
// .defekt daneben; eine beim Lesen gesperrte merkt sich die Liste
// (KeptFile), und Save überschreibt sie nicht.
//
// Format 2 (UTF-8 ohne BOM; Zeiten in UTC wie "2026-10-15T09:30:00Z"):
//   {
//     "format": 2,
//     "project": "Demo.dproj",
//     "bookmarks": [
//       {"id": "5f0c…", "name": "Rundung prüfen", "file": "Source/Kunde.pas",
//        "method": "TKunde.Runde", "signature": "double", "offset": 2,
//        "line": 42, "lineText": "Result := Round(X * 100) / 100;",
//        "before": ["begin", "…"], "after": ["end;", "…"],
//        "created": "…", "lost": true},
//       {"id": "9a1d…", "kind": "quick", "number": 3, "file": "…", "line": 33, …}
//     ]
//   }
// "kind" ist "named" (#622, Vorgabe) oder "quick" (#1104); "number" (1–9)
// fehlt bei unnummerierten, "name" bei schnellen ohne Namen. Format 1 (ohne
// "kind" und "number") liest diese Fassung unverändert als benannte
// Lesezeichen; das nächste Speichern schreibt Format 2.
// Die Reihenfolge der Liste ist die der Lesezeichen (sortiert per Ziehen).
// "line" zählt ab 1 (wie im Editor); "method", "signature" und "offset" nur
// innerhalb einer Methode; "lost" nur bei nicht gefundenen Lesezeichen.
// Unbekannte Felder (oben und je Lesezeichen) bleiben beim Schreiben
// erhalten; "format" steigt nur bei einer inkompatiblen Änderung, eine Datei
// mit höherem Format wird weder gelesen noch überschrieben. Eine leere Liste
// löscht ihre Datei.
// Nicht threadsicher: Die IDE liest und schreibt nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Editor.MethodToggle;

type
  {$SCOPEDENUMS ON}
  /// <summary>Named: benanntes Lesezeichen (#622); Quick: schnelles Lesezeichen aus dem Zeilenrand oder per Taste
  /// (#1104), nummeriert oder unnummeriert, meist ohne Namen.</summary>
  TAtlasBookmarkKind = (Named, Quick);
  {$SCOPEDENUMS OFF}

  TAtlasBookmark = record
    /// <summary>Eindeutig in der Liste (GUID ohne Klammern, klein).</summary>
    Id: string;
    /// <summary>Bei schnellen Lesezeichen leer, bis man ihnen einen Namen gibt.</summary>
    Name: string;
    Kind: TAtlasBookmarkKind;
    /// <summary>1–9 bei nummerierten Lesezeichen, sonst 0.</summary>
    Number: Integer;
    /// <summary>Vollständiger Pfad der Datei.</summary>
    FileName: string;
    /// <summary>Voller Name der Methode, z. B. TKunde.Laden; leer außerhalb einer Methode.</summary>
    Method: string;
    /// <summary>Parametertypen der Methode (klein, mit Komma) für Überladungen.</summary>
    Signature: string;
    /// <summary>Abstand der Zeile zur Kopfzeile der Methode.</summary>
    Offset: Integer;
    Anchor: TAtlasLineAnchor;
    /// <summary>UTC.</summary>
    Created: TDateTime;
    /// <summary>„Nicht gefunden“: Methode oder Zeile fehlt; Anchor.Line ist die letzte bekannte Zeile.</summary>
    Lost: Boolean;
    /// <summary>Unbekannte Felder als JSON-Objekt; bleiben beim Schreiben erhalten.</summary>
    Extra: string;
    /// <summary>Zeile, 0-basiert.</summary>
    function Line: Integer;
    /// <summary>Zeilenvorschau: der normierte Zeilentext.</summary>
    function Preview: string;
    /// <summary>Name, ohne Namen der kurze Methodenname, sonst „Datei.pas:Zeile“ (#1104).</summary>
    function DisplayName: string;
    /// <summary>Ohne eigenen Namen (DisplayName ist dann abgeleitet und wird grau gezeigt).</summary>
    function Unnamed: Boolean;
  end;

  /// <summary>Lesezeichen eines Projekts in der Reihenfolge der Liste.</summary>
  TAtlasBookmarkList = record
    /// <summary>Pfad der Projektdatei.</summary>
    Project: string;
    Bookmarks: TArray<TAtlasBookmark>;
    /// <summary>Gelesener Text der Datei; ToJson behält daraus unbekannte Felder.</summary>
    Raw: string;
    /// <summary>Vorhandene Datei, die beim Lesen gesperrt war: Save überschreibt sie nicht, sonst gingen ihre
    /// Lesezeichen verloren (Bericht N3). '' sonst.</summary>
    KeptFile: string;
    class function Create(const AProject: string): TAtlasBookmarkList; static;
    function Count: Integer;
    function IndexOf(const AId: string): Integer;
    /// <summary>Alle gefundenen Lesezeichen an ALine (0-basiert) in AFileName.</summary>
    function AtLine(const AFileName: string; ALine: Integer): TArray<TAtlasBookmark>;
    /// <summary>Alle Lesezeichen der Datei, auch nicht gefundene.</summary>
    function ForFile(const AFileName: string): TArray<TAtlasBookmark>;
    /// <summary>Dateien mit Lesezeichen, jede einmal.</summary>
    function Files: TArray<string>;
    function LostCount: Integer;
    /// <summary>Neues Lesezeichen AName an ALine von AText (Text der Datei), am Ende der Liste; liefert seine
    /// Kennung.</summary>
    function Add(const AFileName, AText: string; ALine: Integer; const AName: string; ANowUtc: TDateTime): string;
    /// <summary>Index des Lesezeichens mit Nummer ANumber (1–9); -1 ohne.</summary>
    function IndexOfNumber(ANumber: Integer): Integer;
    /// <summary>Name ändern; False ohne dieses Lesezeichen oder mit leerem Namen. Ein schnelles Lesezeichen wird
    /// dabei zum benannten (#1104) und behält seine Nummer.</summary>
    function Rename(const AId, AName: string): Boolean;
    function Remove(const AId: string): Boolean;
    /// <summary>Ziehen in der Liste: AId vor ABeforeId stellen ('' = ans Ende). False, wenn sich nichts ändert.
    /// </summary>
    function MoveBefore(const AId, ABeforeId: string): Boolean;
    /// <summary>Lesezeichen von AFileName gegen dessen aktuellen Text wiederfinden (Find); gefundene merken den
    /// neuen Stand, die übrigen werden „nicht gefunden“. True, wenn sich etwas geändert hat.</summary>
    function Relocate(const AFileName, AText: string): Boolean;
    /// <summary>Die Datei fehlt: alle ihre Lesezeichen „nicht gefunden“. True, wenn sich etwas geändert hat.
    /// </summary>
    function LoseFile(const AFileName: string): Boolean;
    /// <summary>Indizes der Lesezeichen, deren Name, Datei, Methode oder Zeilenvorschau jedes Wort von APattern
    /// enthält (Groß/klein egal), in der Reihenfolge der Liste; leeres Muster: alle.</summary>
    function Filter(const APattern: string): TArray<Integer>;
  end;

  TAtlasBookmarks = class
  public const
    /// <summary>Format, das diese Fassung liest und schreibt (2: Art und Nummer, #1104).</summary>
    cFormat = 2;
    /// <summary>Lokale Datei neben der .dproj (nicht eingecheckt).</summary>
    cLocalFileName = '.atlas-bookmarks.json';
    /// <summary>Datei des Teams neben der .dproj (bookmarks.shared).</summary>
    cSharedFileName = 'atlas-bookmarks.json';
    /// <summary>Länge des Zeilenbeginns im Namensvorschlag.</summary>
    cSuggestLength = 40;
  public
    /// <summary>Datei der Lesezeichen zu AProject: lokal bzw. für das Team.</summary>
    class function FileFor(const AProject: string; AShared: Boolean): string; static;
    /// <summary>Gleiche Datei: Groß-/Kleinschreibung (ASCII), „/“ und „\“ sowie Leerraum am Rand egal.
    /// </summary>
    class function SameFile(const A, B: string): Boolean; static;
    class function NewId: string; static;
    /// <summary>Anker, Methode, Parametertypen und Abstand für ALine von AText in ABookmark.</summary>
    class procedure Capture(const AText: string; ALine: Integer; var ABookmark: TAtlasBookmark); static;
    /// <summary>Sucht ABookmark in AText (Ablauf oben). ALine ist die gefundene Zeile, bei Orphaned („nicht
    /// gefunden“) die bisherige; Same heißt: an der bisherigen Zeile.</summary>
    class function Find(const AText: string; const ABookmark: TAtlasBookmark; out ALine: Integer): TAtlasLineMatch;
      static;
    /// <summary>Namensvorschlag für ALine von AText: kurzer Methodenname und Zeilenbeginn, z. B.
    /// „Runde: Result := Round(X * 100) / 100;“; ohne beides „Kunde.pas:42“.</summary>
    class function SuggestName(const AFileName, AText: string; ALine: Integer): string; static;
    /// <summary>Ort für Listen und die Befehlspalette: „Kunde.pas:42 › TKunde.Runde“, ohne Methode
    /// „Kunde.pas:42“.</summary>
    class function Location(const ABookmark: TAtlasBookmark): string; static;
    /// <summary>Liest AJson; relative Dateipfade gelten zu AFolder. False bei ungültigem Inhalt oder höherem
    /// Format; AList ist dann leer.</summary>
    class function Parse(const AJson, AFolder: string; out AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>JSON mit Dateipfaden relativ zu AFolder (sofern darunter oder daneben auf demselben Laufwerk).
    /// </summary>
    class function ToJson(const AList: TAtlasBookmarkList; const AFolder: string): string; static;
    /// <summary>Format einer Datei (0 ohne oder bei ungültigem Inhalt).</summary>
    class function FormatOf(const AJson: string): Integer; static;
    /// <summary>Liest AFileName für AProject über TAtlasDataFile.Load; False ohne, bei unbrauchbarer (dann als
    /// .defekt beiseitegelegt) oder gesperrter Datei (dann KeptFile). AList ist dann leer mit Project = AProject.
    /// </summary>
    class function LoadFile(const AFileName, AProject: string; out AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>Lesezeichen zu AProject ohne Server und ohne IDE (#755). AShared: Datei des Teams, ersatzweise
    /// die lokale, solange es die des Teams noch nicht gibt.</summary>
    class function Load(const AProject: string; AShared: Boolean; out AList: TAtlasBookmarkList): Boolean; static;
    /// <summary>Ersetzt die Datei atomar; ohne Lesezeichen wird sie gelöscht. Die lokale Datei trägt sich in
    /// .git/info/exclude ein. False bei Fehler (einmal protokolliert), wenn die vorhandene Datei ein höheres
    /// Format hat, gerade nicht lesbar ist oder beim Laden gesperrt war (AList.KeptFile).</summary>
    class function Save(const AList: TAtlasBookmarkList; AShared: Boolean): Boolean; static;
    /// <summary>Trägt AFileName in .git/info/exclude des Repositorys darüber ein (auch Worktrees); True, wenn
    /// der Eintrag danach dort steht. False ohne Git-Repository.</summary>
    class function ExcludeFromGit(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  Winapi.Windows,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Math,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Files.DataFile;

const
  // Bekannte Felder; alles andere bleibt beim Schreiben erhalten.
  cTopKeys: array[0..2] of string = ('format', 'project', 'bookmarks');
  cMarkKeys: array[0..13] of string = ('id', 'name', 'kind', 'number', 'file', 'method', 'signature', 'offset',
    'line', 'lineText', 'before', 'after', 'created', 'lost');
  cKindNames: array[TAtlasBookmarkKind] of string = ('named', 'quick');
  // Kommentar in .git/info/exclude für Git, keine Oberfläche.
  cExcludeComment = '# Atlas: persönliche Lesezeichen (#622)'; // german-ok

{ TAtlasBookmark }

function TAtlasBookmark.Line: Integer;
begin
  Result := Anchor.Line;
end;

function TAtlasBookmark.Preview: string;
begin
  Result := Anchor.Text;
end;

function TAtlasBookmark.Unnamed: Boolean;
begin
  Result := Trim(Name) = '';
end;

/// <summary>Dateiname ohne Ordner; unabhängig vom Trennzeichen des Systems.</summary>
function ShortName(const AFileName: string): string; forward;

function TAtlasBookmark.DisplayName: string;
var
  mDot: Integer;
begin
  if not Unnamed then
  begin
    Exit(Name);
  end;
  Result := Method;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
  if Result = '' then
  begin
    Result := ShortName(FileName) + ':' + IntToStr(Line + 1);
  end;
end;

{ TAtlasBookmarkList }

class function TAtlasBookmarkList.Create(const AProject: string): TAtlasBookmarkList;
begin
  Result := Default(TAtlasBookmarkList);
  Result.Project := AProject;
end;

function TAtlasBookmarkList.Count: Integer;
begin
  Result := Length(Bookmarks);
end;

function TAtlasBookmarkList.IndexOf(const AId: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(Bookmarks) do
  begin
    if SameText(Bookmarks[mIndex].Id, AId) then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasBookmarkList.IndexOfNumber(ANumber: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if ANumber <= 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to High(Bookmarks) do
  begin
    if Bookmarks[mIndex].Number = ANumber then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasBookmarkList.AtLine(const AFileName: string; ALine: Integer): TArray<TAtlasBookmark>;
var
  mMark: TAtlasBookmark;
begin
  Result := nil;
  for mMark in Bookmarks do
  begin
    if not mMark.Lost and (mMark.Line = ALine) and TAtlasBookmarks.SameFile(mMark.FileName, AFileName) then
    begin
      Result := Result + [mMark];
    end;
  end;
end;

function TAtlasBookmarkList.ForFile(const AFileName: string): TArray<TAtlasBookmark>;
var
  mMark: TAtlasBookmark;
begin
  Result := nil;
  for mMark in Bookmarks do
  begin
    if TAtlasBookmarks.SameFile(mMark.FileName, AFileName) then
    begin
      Result := Result + [mMark];
    end;
  end;
end;

function TAtlasBookmarkList.Files: TArray<string>;
var
  mMark: TAtlasBookmark;
  mName: string;
  mKnown: Boolean;
begin
  Result := nil;
  for mMark in Bookmarks do
  begin
    mKnown := False;
    for mName in Result do
    begin
      if TAtlasBookmarks.SameFile(mName, mMark.FileName) then
      begin
        mKnown := True;
        Break;
      end;
    end;
    if not mKnown then
    begin
      Result := Result + [mMark.FileName];
    end;
  end;
end;

function TAtlasBookmarkList.LostCount: Integer;
var
  mMark: TAtlasBookmark;
begin
  Result := 0;
  for mMark in Bookmarks do
  begin
    if mMark.Lost then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasBookmarkList.Add(const AFileName, AText: string; ALine: Integer; const AName: string;
  ANowUtc: TDateTime): string;
var
  mMark: TAtlasBookmark;
begin
  mMark := Default(TAtlasBookmark);
  mMark.Id := TAtlasBookmarks.NewId;
  mMark.Name := Trim(AName);
  mMark.FileName := AFileName;
  TAtlasBookmarks.Capture(AText, ALine, mMark);
  mMark.Created := ANowUtc;
  Bookmarks := Bookmarks + [mMark];
  Result := mMark.Id;
end;

function TAtlasBookmarkList.Rename(const AId, AName: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AId);
  Result := (mIndex >= 0) and (Trim(AName) <> '');
  if not Result then
  begin
    Exit;
  end;
  Bookmarks[mIndex].Name := Trim(AName);
  Bookmarks[mIndex].Kind := TAtlasBookmarkKind.Named;
end;

function TAtlasBookmarkList.Remove(const AId: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := IndexOf(AId);
  Result := mIndex >= 0;
  if Result then
  begin
    Delete(Bookmarks, mIndex, 1);
  end;
end;

function TAtlasBookmarkList.MoveBefore(const AId, ABeforeId: string): Boolean;
var
  mFrom, mTarget: Integer;
  mMark: TAtlasBookmark;
begin
  Result := False;
  mFrom := IndexOf(AId);
  if (mFrom < 0) or SameText(AId, ABeforeId) then
  begin
    Exit;
  end;
  mTarget := Length(Bookmarks);
  if ABeforeId <> '' then
  begin
    mTarget := IndexOf(ABeforeId);
    if mTarget < 0 then
    begin
      Exit;
    end;
  end;
  // Steht schon direkt davor (bzw. schon am Ende): nichts zu tun.
  if (mTarget = mFrom + 1) or ((ABeforeId = '') and (mFrom = High(Bookmarks))) then
  begin
    Exit;
  end;
  mMark := Bookmarks[mFrom];
  Delete(Bookmarks, mFrom, 1);
  if mTarget > mFrom then
  begin
    Dec(mTarget);
  end;
  Insert(mMark, Bookmarks, mTarget);
  Result := True;
end;

/// <summary>Zeilen und Methoden eines Textes einmal für alle Lesezeichen einer Datei.</summary>
type
  TParsedText = record
    Lines: TArray<string>;
    Places: TArray<TAtlasMethodPlace>;
    class function Create(const AText: string): TParsedText; static;
  end;

class function TParsedText.Create(const AText: string): TParsedText;
begin
  Result.Lines := TAtlasLineAnchors.Lines(AText);
  Result.Places := TAtlasMethodToggle.Places(AText);
end;

procedure CaptureIn(const AText: TParsedText; ALine: Integer; var ABookmark: TAtlasBookmark);
var
  mPlace: TAtlasMethodPlace;
begin
  ABookmark.Anchor := TAtlasLineAnchors.Capture(AText.Lines, ALine);
  ABookmark.Method := '';
  ABookmark.Signature := '';
  ABookmark.Offset := 0;
  if TAtlasMethodToggle.BodyAt(AText.Places, ALine, mPlace) then
  begin
    ABookmark.Method := mPlace.Name;
    ABookmark.Signature := mPlace.Signature;
    ABookmark.Offset := ALine - mPlace.FirstLine;
  end;
end;

/// <summary>Zeilentext von ABookmark im Rumpf APlace suchen. Rang bei Überladungen: gleiche Parametertypen vor
/// anderen, unveränderte Zeile vor geänderter. False, wenn der Rumpf nicht passt.</summary>
function MatchInPlace(const AText: TParsedText; const ABookmark: TAtlasBookmark; const APlace: TAtlasMethodPlace;
  out AMatch: TAtlasLineMatch; out ALine, ARank: Integer): Boolean;
var
  mAnchor: TAtlasLineAnchor;
begin
  ALine := -1;
  ARank := 0;
  AMatch := TAtlasLineMatch.Orphaned;
  Result := APlace.IsBody and SameText(APlace.Name, ABookmark.Method);
  if not Result then
  begin
    Exit;
  end;
  mAnchor := ABookmark.Anchor;
  mAnchor.Line := Min(APlace.FirstLine + Max(0, ABookmark.Offset), APlace.LastLine);
  AMatch := TAtlasLineAnchors.Locate(AText.Lines, mAnchor, APlace.FirstLine, APlace.LastLine, ALine);
  Result := AMatch <> TAtlasLineMatch.Orphaned;
  if not SameText(APlace.Signature, ABookmark.Signature) then
  begin
    Inc(ARank, 2);
  end;
  if AMatch = TAtlasLineMatch.Changed then
  begin
    Inc(ARank);
  end;
end;

function FindIn(const AText: TParsedText; const ABookmark: TAtlasBookmark; out ALine: Integer): TAtlasLineMatch;
var
  mPlace: TAtlasMethodPlace;
  mMatch, mBestMatch: TAtlasLineMatch;
  mLine, mRank, mBestRank, mBestLine: Integer;
begin
  ALine := ABookmark.Anchor.Line;
  // Außerhalb einer Methode: Zeilentext in der ganzen Datei.
  if ABookmark.Method = '' then
  begin
    Exit(TAtlasLineAnchors.Locate(AText.Lines, ABookmark.Anchor, ALine));
  end;
  // Zuerst die Methode, dann der Zeilentext in ihrem Rumpf; bei gleichem Rang die nächste Zeile.
  Result := TAtlasLineMatch.Orphaned;
  mBestRank := MaxInt;
  mBestLine := -1;
  mBestMatch := TAtlasLineMatch.Orphaned;
  for mPlace in AText.Places do
  begin
    if MatchInPlace(AText, ABookmark, mPlace, mMatch, mLine, mRank) and ((mRank < mBestRank) or
      ((mRank = mBestRank) and (Abs(mLine - ABookmark.Anchor.Line) < Abs(mBestLine - ABookmark.Anchor.Line)))) then
    begin
      mBestRank := mRank;
      mBestLine := mLine;
      mBestMatch := mMatch;
    end;
  end;
  if mBestLine < 0 then
  begin
    Exit;
  end;
  ALine := mBestLine;
  if mBestMatch = TAtlasLineMatch.Changed then
  begin
    Result := TAtlasLineMatch.Changed;
  end
  else if mBestLine = ABookmark.Anchor.Line then
  begin
    Result := TAtlasLineMatch.Same;
  end
  else
  begin
    Result := TAtlasLineMatch.Moved;
  end;
end;

function SameMark(const A, B: TAtlasBookmark): Boolean;
begin
  Result := A.Anchor.SameAs(B.Anchor) and (A.Method = B.Method) and (A.Signature = B.Signature) and
    (A.Offset = B.Offset);
end;

function TAtlasBookmarkList.Relocate(const AFileName, AText: string): Boolean;
var
  mParsed: TParsedText;
  mIndex, mLine: Integer;
  mFound: TAtlasBookmark;
  mReady: Boolean;
begin
  Result := False;
  mReady := False;
  mParsed := Default(TParsedText);
  for mIndex := 0 to High(Bookmarks) do
  begin
    if not TAtlasBookmarks.SameFile(Bookmarks[mIndex].FileName, AFileName) then
    begin
      Continue;
    end;
    // Erst parsen, wenn die Datei Lesezeichen hat.
    if not mReady then
    begin
      mParsed := TParsedText.Create(AText);
      mReady := True;
    end;
    if FindIn(mParsed, Bookmarks[mIndex], mLine) = TAtlasLineMatch.Orphaned then
    begin
      if not Bookmarks[mIndex].Lost then
      begin
        Bookmarks[mIndex].Lost := True;
        Result := True;
      end;
      Continue;
    end;
    // Gefunden: neuen Stand merken, damit das Lesezeichen auch weiteren Änderungen folgt.
    mFound := Bookmarks[mIndex];
    CaptureIn(mParsed, mLine, mFound);
    if Bookmarks[mIndex].Lost or not SameMark(Bookmarks[mIndex], mFound) then
    begin
      mFound.Lost := False;
      Bookmarks[mIndex] := mFound;
      Result := True;
    end;
  end;
end;

function TAtlasBookmarkList.LoseFile(const AFileName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(Bookmarks) do
  begin
    if TAtlasBookmarks.SameFile(Bookmarks[mIndex].FileName, AFileName) and not Bookmarks[mIndex].Lost then
    begin
      Bookmarks[mIndex].Lost := True;
      Result := True;
    end;
  end;
end;

function ShortName(const AFileName: string): string;
var
  mIndex: Integer;
begin
  Result := AFileName;
  for mIndex := Length(Result) downto 1 do
  begin
    if CharInSet(Result[mIndex], ['\', '/']) then
    begin
      Exit(Copy(Result, mIndex + 1, MaxInt));
    end;
  end;
end;

function TAtlasBookmarkList.Filter(const APattern: string): TArray<Integer>;
var
  mWords: TArray<string>;
  mPart, mHaystack: string;
  mIndex: Integer;
  mMatches: Boolean;
begin
  Result := nil;
  mWords := LowerCase(Trim(APattern)).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  for mIndex := 0 to High(Bookmarks) do
  begin
    mHaystack := LowerCase(Bookmarks[mIndex].DisplayName + #10 + ShortName(Bookmarks[mIndex].FileName) + #10 +
      Bookmarks[mIndex].Method + #10 + Bookmarks[mIndex].Preview);
    mMatches := True;
    for mPart in mWords do
    begin
      if Pos(mPart, mHaystack) = 0 then
      begin
        mMatches := False;
        Break;
      end;
    end;
    if mMatches then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

{ JSON-Helfer }

function Known(const AKeys: array of string; const AName: string): Boolean;
var
  mKey: string;
begin
  Result := False;
  for mKey in AKeys do
  begin
    if mKey = AName then
    begin
      Exit(True);
    end;
  end;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONString then
  begin
    Result := TJSONString(mValue).Value;
  end;
end;

function NumberOf(AObject: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  mValue: TJSONValue;
begin
  Result := ADefault;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONNumber then
  begin
    Result := TJSONNumber(mValue).AsInt;
  end
  else if mValue is TJSONString then
  begin
    Result := StrToIntDef(TJSONString(mValue).Value, ADefault);
  end;
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  Result := False;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if mValue is TJSONBool then
  begin
    Result := SameText(mValue.Value, 'true');
  end;
end;

function TextsOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  mValue: TJSONValue;
  mList: TJSONArray;
  mIndex: Integer;
begin
  Result := nil;
  if AObject = nil then
  begin
    Exit;
  end;
  mValue := AObject.GetValue(AName);
  if not (mValue is TJSONArray) then
  begin
    Exit;
  end;
  mList := TJSONArray(mValue);
  for mIndex := 0 to mList.Count - 1 do
  begin
    if (mList.Items[mIndex] is TJSONString) and (Length(Result) < TAtlasLineAnchors.cContextLines) then
    begin
      Result := Result + [TJSONString(mList.Items[mIndex]).Value];
    end;
  end;
end;

function TextsJson(const ATexts: TArray<string>): TJSONArray;
var
  mText: string;
begin
  Result := TJSONArray.Create;
  for mText in ATexts do
  begin
    Result.Add(mText);
  end;
end;

/// <summary>Unbekannte Felder aus AOriginal (darf nil sein) an ATarget anhängen.</summary>
procedure KeepUnknown(ATarget, AOriginal: TJSONObject; const AKeys: array of string);
var
  mIndex: Integer;
  mPair: TJSONPair;
begin
  if AOriginal = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to AOriginal.Count - 1 do
  begin
    mPair := AOriginal.Pairs[mIndex];
    if not Known(AKeys, mPair.JsonString.Value) then
    begin
      ATarget.AddPair(mPair.JsonString.Value, TJSONValue(mPair.JsonValue.Clone));
    end;
  end;
end;

/// <summary>Nur die unbekannten Felder eines Lesezeichens als JSON-Objekt; '' ohne.</summary>
function ExtraOf(AObject: TJSONObject): string;
var
  mExtra: TJSONObject;
begin
  Result := '';
  mExtra := TJSONObject.Create;
  try
    KeepUnknown(mExtra, AObject, cMarkKeys);
    if mExtra.Count > 0 then
    begin
      Result := mExtra.ToJSON;
    end;
  finally
    mExtra.Free;
  end;
end;

function ParseObject(const AJson: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AJson = '' then
  begin
    Exit;
  end;
  try
    mValue := TJSONObject.ParseJSONValue(AJson);
  except
    on Exception do
      mValue := nil;
  end;
  if mValue is TJSONObject then
  begin
    Result := TJSONObject(mValue);
  end
  else
  begin
    mValue.Free;
  end;
end;

function ReadText(const AFileName: string): string;
var
  mBytes: TBytes;
begin
  mBytes := TFile.ReadAllBytes(AFileName);
  // Mit oder ohne BOM.
  if (Length(mBytes) >= 3) and (mBytes[0] = $EF) and (mBytes[1] = $BB) and (mBytes[2] = $BF) then
  begin
    Result := TEncoding.UTF8.GetString(mBytes, 3, Length(mBytes) - 3);
  end
  else
  begin
    Result := TEncoding.UTF8.GetString(mBytes);
  end;
end;

/// <summary>Absoluter Pfad (Laufwerk, UNC oder Wurzel)?</summary>
function IsAbsolute(const APath: string): Boolean;
begin
  Result := (APath <> '') and (CharInSet(APath[1], ['\', '/']) or ((Length(APath) >= 2) and (APath[2] = ':')));
end;

/// <summary>Pfad aus der Datei: "/" als Trenner, relativ zu AFolder.</summary>
function FromStored(const AStored, AFolder: string): string;
var
  mPath: string;
begin
  mPath := AStored.Replace('\', PathDelim).Replace('/', PathDelim);
  if IsAbsolute(AStored) or (AFolder = '') then
  begin
    Result := mPath;
  end
  else
  begin
    Result := ExpandFileName(IncludeTrailingPathDelimiter(AFolder) + mPath);
  end;
end;

/// <summary>Pfad für die Datei: relativ zu AFolder, wenn möglich, mit "/".</summary>
function ToStored(const AFileName, AFolder: string): string;
begin
  Result := AFileName;
  if AFolder <> '' then
  begin
    Result := ExtractRelativePath(IncludeTrailingPathDelimiter(AFolder), AFileName);
  end;
  Result := Result.Replace('\', '/');
end;

function MarkOf(AObject: TJSONObject; const AFolder: string; out AMark: TAtlasBookmark): Boolean;
begin
  AMark := Default(TAtlasBookmark);
  AMark.Id := TextOf(AObject, 'id');
  AMark.FileName := TextOf(AObject, 'file');
  // Ohne Kennung oder Datei lässt sich das Lesezeichen weder zeigen noch ändern.
  Result := (AMark.Id <> '') and (AMark.FileName <> '');
  if not Result then
  begin
    Exit;
  end;
  AMark.FileName := FromStored(AMark.FileName, AFolder);
  AMark.Name := TextOf(AObject, 'name');
  // Format 1 kennt nur benannte Lesezeichen; unbekannte Arten gelten ebenfalls als benannt.
  if SameText(TextOf(AObject, 'kind'), cKindNames[TAtlasBookmarkKind.Quick]) then
  begin
    AMark.Kind := TAtlasBookmarkKind.Quick;
  end;
  AMark.Number := NumberOf(AObject, 'number', 0);
  if (AMark.Number < 1) or (AMark.Number > 9) then
  begin
    AMark.Number := 0;
  end;
  AMark.Method := TextOf(AObject, 'method');
  AMark.Signature := TextOf(AObject, 'signature');
  AMark.Offset := Max(0, NumberOf(AObject, 'offset', 0));
  AMark.Anchor.Line := Max(0, NumberOf(AObject, 'line', 1) - 1);
  AMark.Anchor.Text := TextOf(AObject, 'lineText');
  AMark.Anchor.Before := TextsOf(AObject, 'before');
  AMark.Anchor.After := TextsOf(AObject, 'after');
  AMark.Created := TAtlasProjectSummaries.TimeOf(TextOf(AObject, 'created'));
  AMark.Lost := FlagOf(AObject, 'lost');
  AMark.Extra := ExtraOf(AObject);
  // Benannte ohne Namen: Datei und Zeile; schnelle bleiben ohne Namen (DisplayName).
  if (AMark.Kind = TAtlasBookmarkKind.Named) and (Trim(AMark.Name) = '') then
  begin
    AMark.Name := ShortName(AMark.FileName) + ':' + IntToStr(AMark.Line + 1);
  end;
end;

function MarkJson(const AMark: TAtlasBookmark; const AFolder: string): TJSONObject;
var
  mExtra: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', AMark.Id);
  if (AMark.Kind = TAtlasBookmarkKind.Named) or not AMark.Unnamed then
  begin
    Result.AddPair('name', AMark.Name);
  end;
  Result.AddPair('kind', cKindNames[AMark.Kind]);
  if AMark.Number > 0 then
  begin
    Result.AddPair('number', TJSONNumber.Create(AMark.Number));
  end;
  Result.AddPair('file', ToStored(AMark.FileName, AFolder));
  if AMark.Method <> '' then
  begin
    Result.AddPair('method', AMark.Method);
    Result.AddPair('signature', AMark.Signature);
    Result.AddPair('offset', TJSONNumber.Create(AMark.Offset));
  end;
  Result.AddPair('line', TJSONNumber.Create(AMark.Line + 1));
  Result.AddPair('lineText', AMark.Anchor.Text);
  Result.AddPair('before', TextsJson(AMark.Anchor.Before));
  Result.AddPair('after', TextsJson(AMark.Anchor.After));
  if AMark.Created > 0 then
  begin
    Result.AddPair('created', TAtlasProjectSummaries.TimeText(AMark.Created));
  end;
  if AMark.Lost then
  begin
    Result.AddPair('lost', TJSONBool.Create(True));
  end;
  mExtra := ParseObject(AMark.Extra);
  try
    KeepUnknown(Result, mExtra, cMarkKeys);
  finally
    mExtra.Free;
  end;
end;

{ TAtlasBookmarks }

class function TAtlasBookmarks.FileFor(const AProject: string; AShared: Boolean): string;
var
  mFolder: string;
begin
  Result := '';
  if Trim(AProject) = '' then
  begin
    Exit;
  end;
  mFolder := ExtractFilePath(Trim(AProject));
  if mFolder <> '' then
  begin
    mFolder := IncludeTrailingPathDelimiter(mFolder);
  end;
  if AShared then
  begin
    Result := mFolder + cSharedFileName;
  end
  else
  begin
    Result := mFolder + cLocalFileName;
  end;
end;

class function TAtlasBookmarks.SameFile(const A, B: string): Boolean;
begin
  Result := TAtlasProjectSummaries.NormalizedPath(A) = TAtlasProjectSummaries.NormalizedPath(B);
end;

class function TAtlasBookmarks.NewId: string;
var
  mGuid: TGUID;
begin
  if CreateGUID(mGuid) <> 0 then
  begin
    // Ohne GUID: Zeitpunkt und Zufall genügen für eine Liste.
    Exit(LowerCase(IntToHex(Trunc(Now * 86400000), 12) + IntToHex(Random(MaxInt), 8)));
  end;
  Result := LowerCase(GUIDToString(mGuid));
  Result := Copy(Result, 2, Length(Result) - 2);
end;

class procedure TAtlasBookmarks.Capture(const AText: string; ALine: Integer; var ABookmark: TAtlasBookmark);
begin
  CaptureIn(TParsedText.Create(AText), ALine, ABookmark);
end;

class function TAtlasBookmarks.Find(const AText: string; const ABookmark: TAtlasBookmark;
  out ALine: Integer): TAtlasLineMatch;
begin
  Result := FindIn(TParsedText.Create(AText), ABookmark, ALine);
end;

class function TAtlasBookmarks.SuggestName(const AFileName, AText: string; ALine: Integer): string;
var
  mMark: TAtlasBookmark;
  mMethod, mStart: string;
  mDot: Integer;
begin
  mMark := Default(TAtlasBookmark);
  Capture(AText, ALine, mMark);
  mMethod := mMark.Method;
  mDot := LastDelimiter('.', mMethod);
  if mDot > 0 then
  begin
    mMethod := Copy(mMethod, mDot + 1, MaxInt);
  end;
  mStart := mMark.Anchor.Text;
  if Length(mStart) > cSuggestLength then
  begin
    mStart := TrimRight(Copy(mStart, 1, cSuggestLength)) + '…';
  end;
  if (mMethod <> '') and (mStart <> '') then
  begin
    Result := mMethod + ': ' + mStart;
  end
  else if mMethod <> '' then
  begin
    Result := mMethod;
  end
  else if mStart <> '' then
  begin
    Result := mStart;
  end
  else
  begin
    Result := ShortName(AFileName) + ':' + IntToStr(ALine + 1);
  end;
end;

class function TAtlasBookmarks.Location(const ABookmark: TAtlasBookmark): string;
begin
  Result := ShortName(ABookmark.FileName) + ':' + IntToStr(ABookmark.Line + 1);
  if ABookmark.Method <> '' then
  begin
    Result := Result + ' › ' + ABookmark.Method;
  end;
end;

class function TAtlasBookmarks.FormatOf(const AJson: string): Integer;
var
  mRoot: TJSONObject;
begin
  mRoot := ParseObject(AJson);
  try
    Result := NumberOf(mRoot, 'format', 0);
  finally
    mRoot.Free;
  end;
end;

class function TAtlasBookmarks.Parse(const AJson, AFolder: string; out AList: TAtlasBookmarkList): Boolean;
var
  mRoot: TJSONObject;
  mValue: TJSONValue;
  mList: TJSONArray;
  mIndex: Integer;
  mMark: TAtlasBookmark;
begin
  AList := TAtlasBookmarkList.Create('');
  Result := False;
  mRoot := ParseObject(AJson);
  try
    if mRoot = nil then
    begin
      Exit;
    end;
    // Ohne "format" gilt 1; ein höheres Format kennt diese Fassung nicht.
    if NumberOf(mRoot, 'format', 1) > cFormat then
    begin
      Exit;
    end;
    AList.Raw := AJson;
    AList.Project := TextOf(mRoot, 'project');
    if AList.Project <> '' then
    begin
      AList.Project := FromStored(AList.Project, AFolder);
    end;
    mValue := mRoot.GetValue('bookmarks');
    if mValue is TJSONArray then
    begin
      mList := TJSONArray(mValue);
      for mIndex := 0 to mList.Count - 1 do
      begin
        if (mList.Items[mIndex] is TJSONObject) and MarkOf(TJSONObject(mList.Items[mIndex]), AFolder, mMark) then
        begin
          AList.Bookmarks := AList.Bookmarks + [mMark];
        end;
      end;
    end;
    Result := True;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasBookmarks.ToJson(const AList: TAtlasBookmarkList; const AFolder: string): string;
var
  mOriginal, mRoot: TJSONObject;
  mList: TJSONArray;
  mMark: TAtlasBookmark;
begin
  mOriginal := ParseObject(AList.Raw);
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mRoot.AddPair('project', ToStored(AList.Project, AFolder));
    mList := TJSONArray.Create;
    mRoot.AddPair('bookmarks', mList);
    for mMark in AList.Bookmarks do
    begin
      mList.AddElement(MarkJson(mMark, AFolder));
    end;
    KeepUnknown(mRoot, mOriginal, cTopKeys);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
    mOriginal.Free;
  end;
end;

class function TAtlasBookmarks.LoadFile(const AFileName, AProject: string; out AList: TAtlasBookmarkList): Boolean;
var
  mList: TAtlasBookmarkList;
  mParsed: Boolean;
  mLoad: TAtlasDataLoad;
begin
  AList := TAtlasBookmarkList.Create(AProject);
  Result := False;
  if AFileName = '' then
  begin
    Exit;
  end;
  mParsed := False;
  mLoad := TAtlasDataFile.Load(AFileName, 'Lesezeichen',
    function(const AText: string): Boolean
    begin
      mParsed := Parse(AText, ExtractFilePath(AFileName), mList);
      // Ein höheres Format ist nicht unbrauchbar: nicht beiseitelegen; Save überschreibt es nicht.
      Result := mParsed or (FormatOf(AText) > cFormat);
    end);
  Result := mParsed and (mLoad = TAtlasDataLoad.Loaded);
  if Result then
  begin
    AList := mList;
    // Mehrere Projekte im Ordner teilen sich die Datei; es gilt das angefragte.
    AList.Project := AProject;
  end
  else if not TAtlasDataFile.Writable(mLoad) then
  begin
    AList.KeptFile := AFileName;
  end;
end;

class function TAtlasBookmarks.Load(const AProject: string; AShared: Boolean; out AList: TAtlasBookmarkList): Boolean;
var
  mFileName: string;
begin
  mFileName := FileFor(AProject, AShared);
  // Datei des Teams gibt es noch nicht: mit den lokalen Lesezeichen anfangen.
  if AShared and not FileExists(mFileName) then
  begin
    mFileName := FileFor(AProject, False);
  end;
  Result := LoadFile(mFileName, AProject, AList);
end;

class function TAtlasBookmarks.Save(const AList: TAtlasBookmarkList; AShared: Boolean): Boolean;
var
  mFileName, mText: string;
begin
  Result := False;
  mFileName := FileFor(AList.Project, AShared);
  // Beim Laden gesperrt: Die Liste kennt den Inhalt der Datei nicht.
  if (mFileName = '') or SameFileName(mFileName, AList.KeptFile) then
  begin
    Exit;
  end;
  try
    // Eine neuere Fassung hat die Datei geschrieben oder sie ist gerade nicht lesbar: nicht überschreiben.
    if FileExists(mFileName) and (not TAtlasDataFile.TryRead(mFileName, mText) or (FormatOf(mText) > cFormat)) then
    begin
      Exit;
    end;
    if AList.Count = 0 then
    begin
      // Keine Lesezeichen mehr: keine leere Datei liegen lassen.
      Result := not FileExists(mFileName) or System.SysUtils.DeleteFile(mFileName);
      Exit;
    end;
    // Atomar ersetzt, UTF-8 ohne BOM wie JSON üblich.
    TAtlasDataFile.Write(mFileName, ToJson(AList, ExtractFilePath(mFileName)));
    Result := True;
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten('Lesezeichen', E);
  end;
  // Die lokale Datei gehört nicht ins Repository; ohne Git bleibt es beim Speichern.
  if Result and not AShared then
  begin
    ExcludeFromGit(mFileName);
  end;
end;

/// <summary>Git-Ordner zu ADir: ".git" als Ordner oder als Datei "gitdir: …" (Worktree, Submodul), bei einem
/// Worktree der gemeinsame Ordner aus "commondir". '' ohne.</summary>
function GitFolderOf(const ADir: string): string;
var
  mGit, mLine, mCommon: string;
begin
  Result := '';
  mGit := IncludeTrailingPathDelimiter(ADir) + '.git';
  if DirectoryExists(mGit) then
  begin
    Exit(mGit);
  end;
  if not FileExists(mGit) then
  begin
    Exit;
  end;
  mLine := Trim(ReadText(mGit));
  if not mLine.StartsWith('gitdir:') then
  begin
    Exit;
  end;
  Result := Trim(Copy(mLine, Length('gitdir:') + 1, MaxInt)).Replace('/', PathDelim).Replace('\', PathDelim);
  if not IsAbsolute(Result) then
  begin
    Result := ExpandFileName(IncludeTrailingPathDelimiter(ADir) + Result);
  end;
  mCommon := IncludeTrailingPathDelimiter(Result) + 'commondir';
  if FileExists(mCommon) then
  begin
    mLine := Trim(ReadText(mCommon)).Replace('/', PathDelim).Replace('\', PathDelim);
    if IsAbsolute(mLine) then
    begin
      Result := mLine;
    end
    else
    begin
      Result := ExpandFileName(IncludeTrailingPathDelimiter(Result) + mLine);
    end;
  end;
end;

class function TAtlasBookmarks.ExcludeFromGit(const AFileName: string): Boolean;
var
  mDir, mParent, mGit, mExclude, mPattern, mText: string;
  mLine: string;
begin
  Result := False;
  try
    mDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(AFileName)));
    mGit := '';
    while mDir <> '' do
    begin
      mGit := GitFolderOf(mDir);
      if mGit <> '' then
      begin
        Break;
      end;
      mParent := ExcludeTrailingPathDelimiter(ExtractFilePath(mDir));
      if (mParent = '') or SameText(mParent, mDir) then
      begin
        Exit;
      end;
      mDir := mParent;
    end;
    if mGit = '' then
    begin
      Exit;
    end;
    // Muster ab der Wurzel des Arbeitsverzeichnisses, nur diese eine Datei.
    mPattern := '/' + ExtractRelativePath(IncludeTrailingPathDelimiter(mDir),
      ExpandFileName(AFileName)).Replace('\', '/');
    mExclude := IncludeTrailingPathDelimiter(mGit) + 'info' + PathDelim + 'exclude';
    mText := '';
    if FileExists(mExclude) then
    begin
      mText := ReadText(mExclude);
    end;
    for mLine in mText.Replace(#13, '').Split([#10]) do
    begin
      if Trim(mLine) = mPattern then
      begin
        Exit(True);
      end;
    end;
    if (mText <> '') and not mText.EndsWith(#10) then
    begin
      mText := mText + #10;
    end;
    mText := mText + cExcludeComment + #10 + mPattern + #10;
    // Atomar: Ein Abbruch kürzt die Datei von Git nicht (Bericht N3).
    TAtlasDataFile.Write(mExclude, mText);
    Result := True;
  except
    // Kein Schreibrecht o. Ä.: Die Lesezeichen sind trotzdem gespeichert.
    on Exception do
      Result := False;
  end;
end;

end.
