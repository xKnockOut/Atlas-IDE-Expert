unit Atlas.Core.Bookmarks.Tests;

// Tests der benannten Lesezeichen (#622): Wiederfinden (Methode verschoben,
// Zeile in der Methode verschoben, Methode gelöscht, Datei ohne die Methode
// ausgetauscht, Überladungen, außerhalb jeder Methode), Liste (Umbenennen,
// Löschen, Ziehen, Filter), Namensvorschlag und Ablage (Format, relative
// Pfade, unbekannte Felder, höheres Format, lokal und für das Team,
// .git/info/exclude).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBookmarkFindTests = class
  public
    /// <summary>Akzeptanzkriterium: Das Lesezeichen überlebt das Verschieben der Methode um 50 Zeilen.</summary>
    [Test]
    procedure FollowsMethodMovedByFiftyLines;
    /// <summary>Akzeptanzkriterium (DUnitX): Zeile innerhalb der Methode verschoben.</summary>
    [Test]
    procedure FollowsLineMovedInsideMethod;
    /// <summary>Akzeptanzkriterium (DUnitX): Methode gelöscht.</summary>
    [Test]
    procedure MethodDeletedIsLost;
    /// <summary>Gleicher Zeilentext in einer anderen Methode zählt nicht: zuerst die Methode.</summary>
    [Test]
    procedure IgnoresSameLineInOtherMethod;
    /// <summary>Akzeptanzkriterium: Datei extern ohne die Methode ausgetauscht – „nicht gefunden“, bleibt in der
    /// Liste; kommt die Methode zurück, gilt es wieder.</summary>
    [Test]
    procedure ReplacedFileKeepsLostBookmark;
    [Test]
    procedure MissingFileLosesBookmarks;
    [Test]
    procedure OverloadPrefersSameParameters;
    [Test]
    procedure ChangedLineStaysAndLearnsText;
    [Test]
    procedure OutsideMethodSearchesWholeFile;
    [Test]
    procedure CaptureRemembersMethodAndOffset;
    [Test]
    procedure RepeatedLineKeepsItsPlace;
  end;

  [TestFixture]
  TAtlasBookmarkListTests = class
  public
    [Test]
    procedure AddRenameAndRemove;
    [Test]
    procedure MoveBeforeReorders;
    [Test]
    procedure FilterMatchesEveryWord;
    [Test]
    procedure AtLineSkipsLostBookmarks;
    [Test]
    procedure FilesAndLostCount;
    [Test]
    procedure SuggestsMethodAndLineStart;
    [Test]
    procedure SuggestionOutsideMethod;
    [Test]
    procedure LocationNamesFileLineAndMethod;
    /// <summary>„Gehe zu Lesezeichen…“: unscharfe Suche der Befehlspalette über Name und Ort.</summary>
    [Test]
    procedure PaletteFindsByNameAndLocation;
  end;

  [TestFixture]
  TAtlasBookmarkStorageTests = class
  private
    FFolder: string;
    function Project: string;
    function UnitFile: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FileForLiesNextToProject;
    [Test]
    procedure JsonRoundTripWithRelativePaths;
    [Test]
    procedure ParsesDocumentedFormat;
    [Test]
    procedure KeepsUnknownFields;
    [Test]
    procedure RejectsInvalidAndNewerFormat;
    /// <summary>Akzeptanzkriterium „überlebt einen IDE-Neustart“: Speichern und wieder Laden.</summary>
    [Test]
    procedure SaveAndLoadLocal;
    [Test]
    procedure SharedFallsBackToLocalUntilCreated;
    [Test]
    procedure EmptyListRemovesFile;
    [Test]
    procedure SaveKeepsNewerFormatFile;
    /// <summary>Unbrauchbare Datei liegt danach als .defekt daneben; eine beim Lesen gesperrte wird nicht
    /// überschrieben (Bericht N3).</summary>
    [Test]
    procedure BrokenFileSetAsideLockedFileKept;
    [Test]
    procedure LoadWithoutFileIsEmpty;
    [Test]
    procedure LocalFileIsExcludedFromGit;
    [Test]
    procedure WorktreeUsesCommonExclude;
    [Test]
    procedure SharedFileIsNotExcluded;
    [Test]
    procedure WithoutRepositoryNothingIsExcluded;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Bookmarks.Store;

const
  KundeFile = 'C:\Projekte\Source\Kunde.pas';
  KundeProject = 'C:\Projekte\Demo.dproj';
  RoundLine = '  Result := Round(X * Faktor) / Faktor;';

procedure WriteText(const AFileName, AText: string);
begin
  TFile.WriteAllBytes(AFileName, TEncoding.UTF8.GetBytes(AText));
end;

function Join(const ALines: TArray<string>): string;
begin
  Result := string.Join(#13#10, ALines);
end;

function Insert(const ALines: TArray<string>; AAt: Integer; const ANew: TArray<string>): TArray<string>;
begin
  Result := Copy(ALines, 0, AAt) + ANew + Copy(ALines, AAt, Length(ALines) - AAt);
end;

function Without(const ALines: TArray<string>; AAt, ACount: Integer): TArray<string>;
begin
  Result := Copy(ALines, 0, AAt) + Copy(ALines, AAt + ACount, Length(ALines) - AAt - ACount);
end;

function IndexOfLine(const ALines: TArray<string>; const AText: string): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to High(ALines) do
    if ALines[Index] = AText then
      Exit(Index);
end;

/// <summary>Kleine Unit mit zwei Methoden; Runde enthält RoundLine.</summary>
function Code: TArray<string>;
begin
  Result := ['unit Kunde;', '', 'interface', '', 'type', '  TKunde = class', '  public',
    '    function Runde(X: Double): Double;', '    procedure Laden;', '  end;', '', 'implementation', '',
    'function TKunde.Runde(X: Double): Double;', 'var', '  Faktor: Double;', 'begin', '  Faktor := 100;',
    RoundLine, '  if Result < 0 then', '    Result := 0;', 'end;', '', 'procedure TKunde.Laden;', 'begin',
    '  Pruefen;', 'end;', '', 'end.'];
end;

/// <summary>Eine Methode mit ACount Zeilen (Kopf bis end).</summary>
function Filler(const AName: string; ACount: Integer): TArray<string>;
var
  Index: Integer;
begin
  Result := ['procedure ' + AName + ';', 'begin'];
  for Index := 1 to ACount - 3 do
    Result := Result + ['  Schritt' + IntToStr(Index) + ';'];
  Result := Result + ['end;'];
end;

function NewMark(const ALines: TArray<string>; ALine: Integer): TAtlasBookmark;
begin
  Result := Default(TAtlasBookmark);
  Result.Id := 'a';
  Result.Name := 'Rundung';
  Result.FileName := KundeFile;
  TAtlasBookmarks.Capture(Join(ALines), ALine, Result);
end;

{ TAtlasBookmarkFindTests }

procedure TAtlasBookmarkFindTests.FollowsMethodMovedByFiftyLines;
var
  Lines, Moved: TArray<string>;
  List: TAtlasBookmarkList;
  Line, Old, Start: Integer;
begin
  Lines := Code;
  Old := IndexOfLine(Lines, RoundLine);
  List := TAtlasBookmarkList.Create(KundeProject);
  List.Add(KundeFile, Join(Lines), Old, 'Rundung', 0);
  // 50 Zeilen (eine neue Methode) vor TKunde.Runde.
  Start := IndexOfLine(Lines, 'function TKunde.Runde(X: Double): Double;');
  Moved := Insert(Lines, Start, Filler('Vorher', 50));
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasBookmarks.Find(Join(Moved), List.Bookmarks[0], Line)));
  Assert.AreEqual(Old + 50, Line);
  Assert.IsTrue(List.Relocate(KundeFile, Join(Moved)));
  Assert.AreEqual(Old + 50, List.Bookmarks[0].Line);
  Assert.IsFalse(List.Bookmarks[0].Lost);
  Assert.AreEqual('TKunde.Runde', List.Bookmarks[0].Method);
  // Und zurück: die Methode wieder 50 Zeilen nach oben.
  Assert.IsTrue(List.Relocate(KundeFile, Join(Lines)));
  Assert.AreEqual(Old, List.Bookmarks[0].Line);
  Assert.IsFalse(List.Relocate(KundeFile, Join(Lines)), 'Unverändert: nichts zu speichern');
end;

procedure TAtlasBookmarkFindTests.FollowsLineMovedInsideMethod;
var
  Lines, Moved: TArray<string>;
  Mark: TAtlasBookmark;
  Line, Old, Assign: Integer;
begin
  Lines := Code;
  Old := IndexOfLine(Lines, RoundLine);
  Mark := NewMark(Lines, Old);
  // Zeile vor "Faktor := 100;" gezogen und zwei Zeilen dazwischen eingefügt.
  Moved := Without(Lines, Old, 1);
  Assign := IndexOfLine(Moved, '  Faktor := 100;');
  Moved := Insert(Moved, Assign, [RoundLine, '  // Erst runden', '  Pruefen;']);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasBookmarks.Find(Join(Moved), Mark, Line)));
  Assert.AreEqual(Assign, Line);
  Assert.AreEqual(RoundLine, Moved[Line]);
end;

procedure TAtlasBookmarkFindTests.MethodDeletedIsLost;
var
  Lines, Gone: TArray<string>;
  List: TAtlasBookmarkList;
  Line, Old, Start: Integer;
begin
  Lines := Code;
  Old := IndexOfLine(Lines, RoundLine);
  List := TAtlasBookmarkList.Create(KundeProject);
  List.Add(KundeFile, Join(Lines), Old, 'Rundung', 0);
  // TKunde.Runde samt Leerzeile entfernen (Kopf bis end;).
  Start := IndexOfLine(Lines, 'function TKunde.Runde(X: Double): Double;');
  Gone := Without(Lines, Start, 10);
  Assert.AreEqual(-1, IndexOfLine(Gone, RoundLine));
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned), Ord(TAtlasBookmarks.Find(Join(Gone), List.Bookmarks[0], Line)));
  Assert.AreEqual(Old, Line, 'Letzte bekannte Zeile');
  Assert.IsTrue(List.Relocate(KundeFile, Join(Gone)));
  Assert.AreEqual(1, Integer(List.Count), 'Bleibt in der Liste');
  Assert.IsTrue(List.Bookmarks[0].Lost);
  Assert.AreEqual(Old, List.Bookmarks[0].Line);
  Assert.AreEqual(1, List.LostCount);
  Assert.IsFalse(List.Relocate(KundeFile, Join(Gone)), 'Schon „nicht gefunden“');
end;

procedure TAtlasBookmarkFindTests.IgnoresSameLineInOtherMethod;
var
  Lines, Changed: TArray<string>;
  Mark: TAtlasBookmark;
  Line, Start: Integer;
begin
  Lines := Code;
  Mark := NewMark(Lines, IndexOfLine(Lines, RoundLine));
  // Runde heißt jetzt Runden; dieselbe Zeile steht zusätzlich in Laden.
  Changed := Copy(Lines);
  Start := IndexOfLine(Changed, 'function TKunde.Runde(X: Double): Double;');
  Changed[Start] := 'function TKunde.Runden(X: Double): Double;';
  Changed := Insert(Changed, IndexOfLine(Changed, '  Pruefen;'), [RoundLine]);
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned), Ord(TAtlasBookmarks.Find(Join(Changed), Mark, Line)));
end;

procedure TAtlasBookmarkFindTests.ReplacedFileKeepsLostBookmark;
var
  Lines: TArray<string>;
  List: TAtlasBookmarkList;
  Old: Integer;
begin
  Lines := Code;
  Old := IndexOfLine(Lines, RoundLine);
  List := TAtlasBookmarkList.Create(KundeProject);
  List.Add(KundeFile, Join(Lines), Old, 'Rundung', 0);
  Assert.IsTrue(List.Relocate(KundeFile, Join(['unit Kunde;', '', 'interface', '', 'implementation', '', 'end.'])));
  Assert.AreEqual(1, Integer(List.Count));
  Assert.IsTrue(List.Bookmarks[0].Lost);
  Assert.AreEqual('Rundung', List.Bookmarks[0].Name);
  Assert.AreEqual('TKunde.Runde', List.Bookmarks[0].Method, 'Die Methode bleibt gemerkt');
  // Die Methode kommt zurück (z. B. Datei wiederhergestellt): wieder gültig.
  Assert.IsTrue(List.Relocate(KundeFile, Join(Lines)));
  Assert.IsFalse(List.Bookmarks[0].Lost);
  Assert.AreEqual(Old, List.Bookmarks[0].Line);
end;

procedure TAtlasBookmarkFindTests.MissingFileLosesBookmarks;
var
  List: TAtlasBookmarkList;
begin
  List := TAtlasBookmarkList.Create(KundeProject);
  List.Add(KundeFile, Join(Code), 18, 'Rundung', 0);
  List.Add('C:\Projekte\Source\Andere.pas', Join(Code), 18, 'Andere', 0);
  Assert.IsTrue(List.LoseFile('c:/projekte/source/KUNDE.pas'));
  Assert.IsTrue(List.Bookmarks[0].Lost);
  Assert.IsFalse(List.Bookmarks[1].Lost);
  Assert.IsFalse(List.LoseFile(KundeFile), 'Schon „nicht gefunden“');
end;

procedure TAtlasBookmarkFindTests.OverloadPrefersSameParameters;
var
  Lines, Swapped: TArray<string>;
  Mark: TAtlasBookmark;
  Line: Integer;
begin
  Lines := ['unit Werte;', '', 'interface', '', 'implementation', '', 'procedure Zeige(A: Integer); overload;',
    'begin', '  Ausgeben(A);', 'end;', '', 'procedure Zeige(const A: string); overload;', 'begin', '  Ausgeben(A);',
    'end;', '', 'end.'];
  Mark := NewMark(Lines, 13);
  Assert.AreEqual('Zeige', Mark.Method);
  Assert.AreEqual('string', Mark.Signature);
  Assert.AreEqual(2, Mark.Offset);
  // Die Überladungen tauschen die Plätze: das Lesezeichen geht mit der string-Fassung.
  Swapped := ['unit Werte;', '', 'interface', '', 'implementation', '', 'procedure Zeige(const A: string); overload;',
    'begin', '  Ausgeben(A);', 'end;', '', 'procedure Zeige(A: Integer); overload;', 'begin', '  Ausgeben(A);',
    'end;', '', 'end.'];
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasBookmarks.Find(Join(Swapped), Mark, Line)));
  Assert.AreEqual(8, Line);
end;

procedure TAtlasBookmarkFindTests.ChangedLineStaysAndLearnsText;
var
  Lines, Edited: TArray<string>;
  List: TAtlasBookmarkList;
  Line, Old: Integer;
begin
  Lines := Code;
  Old := IndexOfLine(Lines, RoundLine);
  List := TAtlasBookmarkList.Create(KundeProject);
  List.Add(KundeFile, Join(Lines), Old, 'Rundung', 0);
  Edited := Copy(Lines);
  Edited[Old] := '  Result := Round(X * Faktor + 0.5) / Faktor;';
  Assert.AreEqual(Ord(TAtlasLineMatch.Changed), Ord(TAtlasBookmarks.Find(Join(Edited), List.Bookmarks[0], Line)));
  Assert.AreEqual(Old, Line);
  Assert.IsTrue(List.Relocate(KundeFile, Join(Edited)));
  Assert.AreEqual('Result := Round(X * Faktor + 0.5) / Faktor;', List.Bookmarks[0].Preview);
  Assert.IsFalse(List.Bookmarks[0].Lost);
end;

procedure TAtlasBookmarkFindTests.OutsideMethodSearchesWholeFile;
var
  Lines, Moved: TArray<string>;
  Mark: TAtlasBookmark;
  Line, Old: Integer;
begin
  Lines := Code;
  Old := IndexOfLine(Lines, '  TKunde = class');
  Mark := NewMark(Lines, Old);
  Assert.AreEqual('', Mark.Method);
  Moved := Insert(Lines, 2, ['// Kopf', '// noch mehr', '']);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasBookmarks.Find(Join(Moved), Mark, Line)));
  Assert.AreEqual(Old + 3, Line);
end;

procedure TAtlasBookmarkFindTests.CaptureRemembersMethodAndOffset;
var
  Lines: TArray<string>;
  Mark: TAtlasBookmark;
  Start: Integer;
begin
  Lines := Code;
  Start := IndexOfLine(Lines, 'function TKunde.Runde(X: Double): Double;');
  Mark := NewMark(Lines, IndexOfLine(Lines, RoundLine));
  Assert.AreEqual('TKunde.Runde', Mark.Method);
  Assert.AreEqual('double', Mark.Signature);
  Assert.AreEqual(IndexOfLine(Lines, RoundLine) - Start, Mark.Offset);
  Assert.AreEqual('Result := Round(X * Faktor) / Faktor;', Mark.Preview);
  Assert.AreEqual(2, Integer(Length(Mark.Anchor.Before)));
  // Auf der Kopfzeile: Abstand 0.
  Mark := NewMark(Lines, Start);
  Assert.AreEqual('TKunde.Runde', Mark.Method);
  Assert.AreEqual(0, Mark.Offset);
end;

procedure TAtlasBookmarkFindTests.RepeatedLineKeepsItsPlace;
var
  Lines, Moved: TArray<string>;
  Mark: TAtlasBookmark;
  Line: Integer;
begin
  // Zweimal "Inc(N);" in der Methode: es gilt die Stelle mit dem passenden Umfeld, nicht die erste.
  Lines := ['unit Zaehler;', '', 'implementation', '', 'procedure Zaehle;', 'begin', '  A;', '  Inc(N);', '  B;',
    '  C;', '  D;', '  Inc(N);', '  E;', 'end;', '', 'end.'];
  Mark := NewMark(Lines, 11);
  Assert.AreEqual(7, Mark.Offset);
  Moved := Insert(Lines, 4, Filler('Davor', 20));
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasBookmarks.Find(Join(Moved), Mark, Line)));
  Assert.AreEqual(31, Line);
end;

{ TAtlasBookmarkListTests }

procedure TAtlasBookmarkListTests.AddRenameAndRemove;
var
  List: TAtlasBookmarkList;
  Id, Other: string;
begin
  List := TAtlasBookmarkList.Create(KundeProject);
  Id := List.Add(KundeFile, Join(Code), 18, '  Rundung  ', EncodeDate(2026, 10, 15));
  Other := List.Add(KundeFile, Join(Code), 25, 'Laden', 0);
  Assert.AreNotEqual('', Id);
  Assert.AreNotEqual(Id, Other);
  Assert.AreEqual(2, Integer(List.Count));
  Assert.AreEqual('Rundung', List.Bookmarks[0].Name);
  Assert.IsTrue(List.Bookmarks[0].Created = EncodeDate(2026, 10, 15));
  Assert.AreEqual(0, List.IndexOf(UpperCase(Id)));
  Assert.IsTrue(List.Rename(Id, 'Rundung prüfen'));
  Assert.AreEqual('Rundung prüfen', List.Bookmarks[0].Name);
  Assert.IsFalse(List.Rename(Id, '   '), 'Leerer Name');
  Assert.IsFalse(List.Rename('unbekannt', 'X'));
  Assert.IsTrue(List.Remove(Id));
  Assert.IsFalse(List.Remove(Id));
  Assert.AreEqual(1, Integer(List.Count));
  Assert.AreEqual(Other, List.Bookmarks[0].Id);
end;

procedure TAtlasBookmarkListTests.MoveBeforeReorders;
var
  List: TAtlasBookmarkList;
  A, B, C: string;

  function Order: string;
  var
    Mark: TAtlasBookmark;
  begin
    Result := '';
    for Mark in List.Bookmarks do
      Result := Result + Mark.Name;
  end;

begin
  List := TAtlasBookmarkList.Create(KundeProject);
  A := List.Add(KundeFile, Join(Code), 18, 'A', 0);
  B := List.Add(KundeFile, Join(Code), 19, 'B', 0);
  C := List.Add(KundeFile, Join(Code), 20, 'C', 0);
  Assert.IsTrue(List.MoveBefore(C, A));
  Assert.AreEqual('CAB', Order);
  Assert.IsTrue(List.MoveBefore(C, ''));
  Assert.AreEqual('ABC', Order);
  Assert.IsTrue(List.MoveBefore(A, C));
  Assert.AreEqual('BAC', Order);
  Assert.IsFalse(List.MoveBefore(A, C), 'Steht schon davor');
  Assert.IsFalse(List.MoveBefore(C, ''), 'Steht schon am Ende');
  Assert.IsFalse(List.MoveBefore(A, A));
  Assert.IsFalse(List.MoveBefore(A, 'unbekannt'));
  Assert.IsFalse(List.MoveBefore('unbekannt', A));
  Assert.AreEqual('BAC', Order);
end;

procedure TAtlasBookmarkListTests.FilterMatchesEveryWord;
var
  List: TAtlasBookmarkList;
  Found: TArray<Integer>;
begin
  List := TAtlasBookmarkList.Create(KundeProject);
  List.Add(KundeFile, Join(Code), 18, 'Rundung', 0);
  List.Add('C:\Projekte\Source\Lager.pas', Join(Code), 25, 'Laden prüfen', 0);
  Assert.AreEqual(2, Integer(Length(List.Filter(''))));
  Found := List.Filter('kunde round');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Found[0]);
  Found := List.Filter('LAGER laden');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(1, Found[0]);
  // Methode zählt mit, der Ordner nicht.
  Assert.AreEqual(1, Integer(Length(List.Filter('TKunde.Runde'))));
  Assert.AreEqual(0, Integer(Length(List.Filter('projekte'))));
  Assert.AreEqual(0, Integer(Length(List.Filter('rundung lager'))));
end;

procedure TAtlasBookmarkListTests.AtLineSkipsLostBookmarks;
var
  List: TAtlasBookmarkList;
begin
  List := TAtlasBookmarkList.Create(KundeProject);
  List.Add(KundeFile, Join(Code), 18, 'Eins', 0);
  List.Add(KundeFile, Join(Code), 18, 'Zwei', 0);
  Assert.AreEqual(2, Integer(Length(List.AtLine('c:/projekte/source/kunde.pas', 18))));
  Assert.AreEqual(0, Integer(Length(List.AtLine(KundeFile, 17))));
  List.Bookmarks[1].Lost := True;
  Assert.AreEqual(1, Integer(Length(List.AtLine(KundeFile, 18))));
  Assert.AreEqual(2, Integer(Length(List.ForFile(KundeFile))));
end;

procedure TAtlasBookmarkListTests.FilesAndLostCount;
var
  List: TAtlasBookmarkList;
  Files: TArray<string>;
begin
  List := TAtlasBookmarkList.Create(KundeProject);
  List.Add(KundeFile, Join(Code), 18, 'Eins', 0);
  List.Add('C:\Projekte\Source\Lager.pas', Join(Code), 18, 'Zwei', 0);
  List.Add('c:\projekte\source\KUNDE.pas', Join(Code), 25, 'Drei', 0);
  Files := List.Files;
  Assert.AreEqual(2, Integer(Length(Files)));
  Assert.AreEqual(KundeFile, Files[0]);
  Assert.AreEqual(0, List.LostCount);
  List.LoseFile(KundeFile);
  Assert.AreEqual(2, List.LostCount);
end;

procedure TAtlasBookmarkListTests.SuggestsMethodAndLineStart;
var
  Lines: TArray<string>;
begin
  Lines := Code;
  Assert.AreEqual('Runde: Result := Round(X * Faktor) / Faktor;',
    TAtlasBookmarks.SuggestName(KundeFile, Join(Lines), IndexOfLine(Lines, RoundLine)));
  Lines[IndexOfLine(Lines, RoundLine)] := '  Result := Round(X * Faktor) / Faktor + Zuschlag(Kunde, Datum, Waehrung);';
  Assert.AreEqual('Runde: Result := Round(X * Faktor) / Faktor + Z…',
    TAtlasBookmarks.SuggestName(KundeFile, Join(Lines), 18));
  // Leere Zeile in der Methode: nur der Methodenname.
  Lines[18] := '';
  Assert.AreEqual('Runde', TAtlasBookmarks.SuggestName(KundeFile, Join(Lines), 18));
end;

procedure TAtlasBookmarkListTests.SuggestionOutsideMethod;
begin
  Assert.AreEqual('TKunde = class', TAtlasBookmarks.SuggestName(KundeFile, Join(Code), 5));
  Assert.AreEqual('Kunde.pas:2', TAtlasBookmarks.SuggestName(KundeFile, Join(Code), 1));
end;

procedure TAtlasBookmarkListTests.LocationNamesFileLineAndMethod;
var
  List: TAtlasBookmarkList;
begin
  List := TAtlasBookmarkList.Create(KundeProject);
  List.Add(KundeFile, Join(Code), 18, 'Rundung', 0);
  List.Add(KundeFile, Join(Code), 5, 'Klasse', 0);
  Assert.AreEqual('Kunde.pas:19 › TKunde.Runde', TAtlasBookmarks.Location(List.Bookmarks[0]));
  Assert.AreEqual('Kunde.pas:6', TAtlasBookmarks.Location(List.Bookmarks[1]));
end;

procedure TAtlasBookmarkListTests.PaletteFindsByNameAndLocation;
var
  List: TAtlasBookmarkList;
  Commands: TArray<TAtlasCommand>;
  Command: TAtlasCommand;
  Mark: TAtlasBookmark;
  Order: TArray<Integer>;
begin
  List := TAtlasBookmarkList.Create(KundeProject);
  List.Add(KundeFile, Join(Code), 18, 'Rundung prüfen', 0);
  List.Add('C:\Projekte\Source\Lager.pas', Join(Code), 25, 'Bestand laden', 0);
  List.Add(KundeFile, Join(Code), 5, 'Klasse aufteilen', 0);
  // Wie TAtlasIdeBookmarks.GoToBookmark: Name als Beschriftung, Ort als Pfad.
  Commands := nil;
  for Mark in List.Bookmarks do
  begin
    Command := Default(TAtlasCommand);
    Command.Id := Mark.Id;
    Command.Caption := Mark.Name;
    Command.Path := TAtlasBookmarks.Location(Mark);
    Commands := Commands + [Command];
  end;
  // Ohne Eingabe: Reihenfolge der Liste.
  Order := TAtlasCommandPalette.Order(Commands, '', nil, True);
  Assert.AreEqual(3, Integer(Length(Order)));
  Assert.AreEqual(0, Order[0]);
  Assert.AreEqual(2, Order[2]);
  // Unscharf über den Namen: Wortanfänge.
  Order := TAtlasCommandPalette.Order(Commands, 'rp', nil, True);
  Assert.IsTrue(Length(Order) > 0);
  Assert.AreEqual(0, Order[0]);
  // Über den Ort: Dateiname, der im Namen nicht vorkommt.
  Order := TAtlasCommandPalette.Order(Commands, 'lager', nil, True);
  Assert.IsTrue(Length(Order) > 0);
  Assert.AreEqual(1, Order[0]);
end;

{ TAtlasBookmarkStorageTests }

procedure TAtlasBookmarkStorageTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasBookmarks' + IntToStr(Random(1000000)));
  ForceDirectories(TPath.Combine(FFolder, 'Source'));
end;

procedure TAtlasBookmarkStorageTests.TearDown;
begin
  if DirectoryExists(FFolder) then
    TDirectory.Delete(FFolder, True);
  // Der Leckmonitor misst den Saldo von Setup und TearDown.
  FFolder := '';
end;

function TAtlasBookmarkStorageTests.Project: string;
begin
  Result := TPath.Combine(FFolder, 'Demo.dproj');
end;

function TAtlasBookmarkStorageTests.UnitFile: string;
begin
  Result := TPath.Combine(TPath.Combine(FFolder, 'Source'), 'Kunde.pas');
end;

procedure TAtlasBookmarkStorageTests.FileForLiesNextToProject;
begin
  Assert.AreEqual(TPath.Combine(FFolder, '.atlas-bookmarks.json'), TAtlasBookmarks.FileFor(Project, False));
  Assert.AreEqual(TPath.Combine(FFolder, 'atlas-bookmarks.json'), TAtlasBookmarks.FileFor(Project, True));
  Assert.AreEqual('', TAtlasBookmarks.FileFor('  ', False));
end;

procedure TAtlasBookmarkStorageTests.JsonRoundTripWithRelativePaths;
var
  List, Back: TAtlasBookmarkList;
  Json: string;
  Root: TJSONValue;
  Mark: TJSONObject;
begin
  List := TAtlasBookmarkList.Create(Project);
  List.Add(UnitFile, Join(Code), 18, 'Rundung', EncodeDate(2026, 10, 15) + EncodeTime(9, 30, 0, 0));
  List.Add(UnitFile, Join(Code), 5, 'Klasse', 0);
  List.Bookmarks[1].Lost := True;
  Json := TAtlasBookmarks.ToJson(List, IncludeTrailingPathDelimiter(FFolder));
  Root := TJSONObject.ParseJSONValue(Json);
  try
    Assert.AreEqual('Demo.dproj', TJSONObject(Root).GetValue('project').Value);
    Mark := TJSONObject(TJSONArray(TJSONObject(Root).GetValue('bookmarks')).Items[0]);
    Assert.AreEqual('Source/Kunde.pas', Mark.GetValue('file').Value);
    Assert.AreEqual('19', Mark.GetValue('line').Value, '1-basiert');
    Assert.AreEqual('TKunde.Runde', Mark.GetValue('method').Value);
    Assert.AreEqual('2026-10-15T09:30:00Z', Mark.GetValue('created').Value);
    Assert.IsNull(Mark.GetValue('lost'));
  finally
    Root.Free;
  end;
  Assert.IsTrue(TAtlasBookmarks.Parse(Json, IncludeTrailingPathDelimiter(FFolder), Back));
  Assert.AreEqual(2, Integer(Back.Count));
  Assert.AreEqual(Project, Back.Project);
  Assert.IsTrue(TAtlasBookmarks.SameFile(UnitFile, Back.Bookmarks[0].FileName));
  Assert.AreEqual(List.Bookmarks[0].Id, Back.Bookmarks[0].Id);
  Assert.AreEqual('Rundung', Back.Bookmarks[0].Name);
  Assert.AreEqual('TKunde.Runde', Back.Bookmarks[0].Method);
  Assert.AreEqual('double', Back.Bookmarks[0].Signature);
  Assert.AreEqual(List.Bookmarks[0].Offset, Back.Bookmarks[0].Offset);
  Assert.IsTrue(List.Bookmarks[0].Anchor.SameAs(Back.Bookmarks[0].Anchor));
  Assert.IsTrue(Abs(List.Bookmarks[0].Created - Back.Bookmarks[0].Created) < 1 / 86400);
  Assert.IsFalse(Back.Bookmarks[0].Lost);
  Assert.IsTrue(Back.Bookmarks[1].Lost);
  Assert.AreEqual('', Back.Bookmarks[1].Method);
end;

procedure TAtlasBookmarkStorageTests.ParsesDocumentedFormat;
const
  Json = '{"format": 1, "project": "Demo.dproj", "bookmarks": [' +
    '{"id": "5f0c", "name": "Rundung prüfen", "file": "Source/Kunde.pas", "method": "TKunde.Runde",' +
    ' "signature": "double", "offset": 5, "line": 19, "lineText": "Result := Round(X * Faktor) / Faktor;",' +
    ' "before": ["Faktor := 100;", "begin"], "after": ["if Result < 0 then", "Result := 0;"],' +
    ' "created": "2026-10-15T09:30:00Z", "lost": true},' +
    '{"id": "", "file": "Source/Kunde.pas"}, {"id": "ohne-datei"}, 7,' +
    '{"id": "ohne-name", "file": "Source/Kunde.pas", "line": 3}]}';
var
  List: TAtlasBookmarkList;
  Line: Integer;
begin
  Assert.IsTrue(TAtlasBookmarks.Parse(Json, IncludeTrailingPathDelimiter(FFolder), List));
  Assert.AreEqual(2, Integer(List.Count), 'Einträge ohne Kennung oder Datei fallen weg');
  Assert.AreEqual('Rundung prüfen', List.Bookmarks[0].Name);
  Assert.AreEqual(18, List.Bookmarks[0].Line);
  Assert.AreEqual(5, List.Bookmarks[0].Offset);
  Assert.IsTrue(List.Bookmarks[0].Lost);
  Assert.AreEqual('Faktor := 100;', List.Bookmarks[0].Anchor.Before[0]);
  Assert.AreEqual('Kunde.pas:3', List.Bookmarks[1].Name, 'Ohne Namen: Datei und Zeile');
  // Das gelesene Lesezeichen findet sich im Code wieder.
  Assert.AreEqual(Ord(TAtlasLineMatch.Same), Ord(TAtlasBookmarks.Find(Join(Code), List.Bookmarks[0], Line)));
  Assert.AreEqual(18, Line);
end;

procedure TAtlasBookmarkStorageTests.KeepsUnknownFields;
const
  Json = '{"format": 1, "project": "Demo.dproj", "team": {"owner": "Marco"}, "bookmarks": [' +
    '{"id": "a", "name": "A", "file": "Source/Kunde.pas", "line": 1, "lineText": "unit Kunde;", "color": "red"}]}';
var
  List: TAtlasBookmarkList;
  Json2: string;
  Root: TJSONObject;
  Mark: TJSONObject;
begin
  Assert.IsTrue(TAtlasBookmarks.Parse(Json, IncludeTrailingPathDelimiter(FFolder), List));
  List.Rename('a', 'B');
  Json2 := TAtlasBookmarks.ToJson(List, IncludeTrailingPathDelimiter(FFolder));
  Root := TJSONObject(TJSONObject.ParseJSONValue(Json2));
  try
    Assert.IsNotNull(Root.GetValue('team'));
    Mark := TJSONObject(TJSONArray(Root.GetValue('bookmarks')).Items[0]);
    Assert.AreEqual('red', Mark.GetValue('color').Value);
    Assert.AreEqual('B', Mark.GetValue('name').Value);
  finally
    Root.Free;
  end;
end;

procedure TAtlasBookmarkStorageTests.RejectsInvalidAndNewerFormat;
var
  List: TAtlasBookmarkList;
begin
  Assert.IsFalse(TAtlasBookmarks.Parse('', FFolder, List));
  Assert.IsFalse(TAtlasBookmarks.Parse('kein json', FFolder, List));
  Assert.IsFalse(TAtlasBookmarks.Parse('[1, 2]', FFolder, List));
  Assert.IsFalse(TAtlasBookmarks.Parse('{"format": 3, "bookmarks": []}', FFolder, List));
  Assert.AreEqual(0, Integer(List.Count));
  Assert.IsTrue(TAtlasBookmarks.Parse('{"bookmarks": []}', FFolder, List), 'Ohne format gilt 1');
  Assert.AreEqual(3, TAtlasBookmarks.FormatOf('{"format": 3}'));
  Assert.AreEqual(0, TAtlasBookmarks.FormatOf('kaputt'));
end;

procedure TAtlasBookmarkStorageTests.SaveAndLoadLocal;
var
  List, Back: TAtlasBookmarkList;
  Bytes: TBytes;
begin
  List := TAtlasBookmarkList.Create(Project);
  List.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(List, False));
  Assert.IsTrue(FileExists(TPath.Combine(FFolder, '.atlas-bookmarks.json')));
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, 'atlas-bookmarks.json')));
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, '.atlas-bookmarks.json.tmp')));
  Bytes := TFile.ReadAllBytes(TPath.Combine(FFolder, '.atlas-bookmarks.json'));
  Assert.AreEqual(Ord('{'), Integer(Bytes[0]), 'Ohne BOM');
  // „IDE-Neustart“: frisch laden, Lesezeichen und Methode sind wieder da.
  Assert.IsTrue(TAtlasBookmarks.Load(Project, False, Back));
  Assert.AreEqual(1, Integer(Back.Count));
  Assert.AreEqual(Project, Back.Project);
  Assert.AreEqual('Rundung', Back.Bookmarks[0].Name);
  Assert.IsTrue(TAtlasBookmarks.SameFile(UnitFile, Back.Bookmarks[0].FileName));
  Assert.AreEqual('TKunde.Runde', Back.Bookmarks[0].Method);
  // Auch ein anderes Projekt im selben Ordner liest dieselbe Datei.
  Assert.IsTrue(TAtlasBookmarks.Load(TPath.Combine(FFolder, 'Zweites.dproj'), False, Back));
  Assert.AreEqual(1, Integer(Back.Count));
  Assert.AreEqual(TPath.Combine(FFolder, 'Zweites.dproj'), Back.Project);
end;

procedure TAtlasBookmarkStorageTests.SharedFallsBackToLocalUntilCreated;
var
  List, Back: TAtlasBookmarkList;
begin
  List := TAtlasBookmarkList.Create(Project);
  List.Add(UnitFile, Join(Code), 18, 'Lokal', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(List, False));
  // Team-Ablage eingeschaltet: zunächst die lokalen Lesezeichen.
  Assert.IsTrue(TAtlasBookmarks.Load(Project, True, Back));
  Assert.AreEqual('Lokal', Back.Bookmarks[0].Name);
  Back.Rename(Back.Bookmarks[0].Id, 'Team');
  Assert.IsTrue(TAtlasBookmarks.Save(Back, True));
  Assert.IsTrue(FileExists(TPath.Combine(FFolder, 'atlas-bookmarks.json')));
  // Ab jetzt gilt die Datei des Teams.
  Assert.IsTrue(TAtlasBookmarks.Load(Project, True, Back));
  Assert.AreEqual('Team', Back.Bookmarks[0].Name);
  Assert.IsTrue(TAtlasBookmarks.Load(Project, False, Back));
  Assert.AreEqual('Lokal', Back.Bookmarks[0].Name, 'Die lokale Datei bleibt unberührt');
end;

procedure TAtlasBookmarkStorageTests.EmptyListRemovesFile;
var
  List: TAtlasBookmarkList;
begin
  List := TAtlasBookmarkList.Create(Project);
  List.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(List, False));
  List.Remove(List.Bookmarks[0].Id);
  Assert.IsTrue(TAtlasBookmarks.Save(List, False));
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, '.atlas-bookmarks.json')));
  Assert.IsTrue(TAtlasBookmarks.Save(List, False), 'Ohne Datei nichts zu tun');
end;

procedure TAtlasBookmarkStorageTests.SaveKeepsNewerFormatFile;
var
  List: TAtlasBookmarkList;
  FileName: string;
begin
  FileName := TPath.Combine(FFolder, '.atlas-bookmarks.json');
  WriteText(FileName, '{"format": 3, "bookmarks": []}');
  Assert.IsFalse(TAtlasBookmarks.Load(Project, False, List));
  Assert.AreEqual(0, Integer(List.Count));
  Assert.AreEqual(Project, List.Project);
  List.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsFalse(TAtlasBookmarks.Save(List, False));
  Assert.AreEqual(3, TAtlasBookmarks.FormatOf(TFile.ReadAllText(FileName)));
end;

procedure TAtlasBookmarkStorageTests.LoadWithoutFileIsEmpty;
var
  List: TAtlasBookmarkList;
begin
  Assert.IsFalse(TAtlasBookmarks.Load(Project, False, List));
  Assert.AreEqual(0, Integer(List.Count));
  Assert.AreEqual(Project, List.Project);
  Assert.IsFalse(TAtlasBookmarks.Load(Project, True, List));
  Assert.IsFalse(TAtlasBookmarks.Load('', False, List));
end;

procedure TAtlasBookmarkStorageTests.LocalFileIsExcludedFromGit;
var
  List: TAtlasBookmarkList;
  Exclude, Text: string;
  Sub: string;
begin
  // Repository eine Ebene über dem Projekt: Muster mit Unterordner.
  ForceDirectories(TPath.Combine(TPath.Combine(FFolder, '.git'), 'info'));
  Exclude := TPath.Combine(TPath.Combine(TPath.Combine(FFolder, '.git'), 'info'), 'exclude');
  WriteText(Exclude, '# vorhanden' + #10 + '*.bak');
  Sub := TPath.Combine(FFolder, 'App');
  ForceDirectories(Sub);
  List := TAtlasBookmarkList.Create(TPath.Combine(Sub, 'App.dproj'));
  List.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(List, False));
  Text := TFile.ReadAllText(Exclude);
  Assert.IsTrue(Text.StartsWith('# vorhanden' + #10 + '*.bak' + #10), Text);
  Assert.IsTrue(Text.Contains(#10 + '/App/.atlas-bookmarks.json' + #10), Text);
  // Zweites Speichern trägt nicht noch einmal ein.
  Assert.IsTrue(TAtlasBookmarks.Save(List, False));
  Assert.AreEqual(Text, TFile.ReadAllText(Exclude));
  Assert.IsTrue(TAtlasBookmarks.ExcludeFromGit(TAtlasBookmarks.FileFor(List.Project, False)));
end;

procedure TAtlasBookmarkStorageTests.WorktreeUsesCommonExclude;
var
  Main, Tree, Admin, Exclude: string;
begin
  // Hauptrepository in Main, Worktree in Tree mit ".git"-Datei und commondir.
  Main := TPath.Combine(FFolder, 'Main');
  Tree := TPath.Combine(FFolder, 'Tree');
  Admin := TPath.Combine(TPath.Combine(TPath.Combine(Main, '.git'), 'worktrees'), 'Tree');
  ForceDirectories(Admin);
  ForceDirectories(Tree);
  WriteText(TPath.Combine(Tree, '.git'), 'gitdir: ' + Admin.Replace('\', '/') + #10);
  WriteText(TPath.Combine(Admin, 'commondir'), '../..' + #10);
  Assert.IsTrue(TAtlasBookmarks.ExcludeFromGit(TPath.Combine(Tree, '.atlas-bookmarks.json')));
  Exclude := TPath.Combine(TPath.Combine(TPath.Combine(Main, '.git'), 'info'), 'exclude');
  Assert.IsTrue(FileExists(Exclude));
  Assert.IsTrue(TFile.ReadAllText(Exclude).Contains('/.atlas-bookmarks.json' + #10));
end;

procedure TAtlasBookmarkStorageTests.SharedFileIsNotExcluded;
var
  List: TAtlasBookmarkList;
begin
  ForceDirectories(TPath.Combine(FFolder, '.git'));
  List := TAtlasBookmarkList.Create(Project);
  List.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(List, True));
  Assert.IsFalse(FileExists(TPath.Combine(TPath.Combine(TPath.Combine(FFolder, '.git'), 'info'), 'exclude')));
end;

procedure TAtlasBookmarkStorageTests.WithoutRepositoryNothingIsExcluded;
var
  List: TAtlasBookmarkList;
begin
  List := TAtlasBookmarkList.Create(Project);
  List.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(List, False), 'Speichern klappt auch ohne Git');
  Assert.IsFalse(DirectoryExists(TPath.Combine(FFolder, '.git')));
end;

procedure TAtlasBookmarkStorageTests.BrokenFileSetAsideLockedFileKept;
var
  List: TAtlasBookmarkList;
  FileName: string;
  Lock: TFileStream;
begin
  FileName := TPath.Combine(FFolder, '.atlas-bookmarks.json');
  WriteText(FileName, '{"bookmarks": [');
  Assert.IsFalse(TAtlasBookmarks.Load(Project, False, List));
  Assert.AreEqual(Project, List.Project);
  Assert.IsTrue(FileExists(FileName + TAtlasDataFile.DefectExtension), 'beiseitegelegt');
  Assert.IsFalse(FileExists(FileName));
  List.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(List, False));
  Lock := TFileStream.Create(FileName, fmOpenRead or fmShareExclusive);
  try
    Assert.IsFalse(TAtlasBookmarks.Load(Project, False, List));
  finally
    Lock.Free;
  end;
  Assert.AreEqual(0, Integer(List.Count));
  Assert.AreEqual(FileName, List.KeptFile);
  List.Add(UnitFile, Join(Code), 18, 'Ersatz', 0);
  Assert.IsFalse(TAtlasBookmarks.Save(List, False), 'beim Laden gesperrt: nicht überschreiben');
  Assert.Contains(TFile.ReadAllText(FileName), 'Rundung');
  Assert.DoesNotContain(TFile.ReadAllText(FileName), 'Ersatz');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBookmarkFindTests);
  TDUnitX.RegisterTestFixture(TAtlasBookmarkListTests);
  TDUnitX.RegisterTestFixture(TAtlasBookmarkStorageTests);

end.
