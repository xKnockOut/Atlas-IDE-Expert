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
  [Category('Atlas.IDE.Bookmarks')]
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
  [Category('Atlas.IDE.Bookmarks')]
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
  [Category('Atlas.IDE.Bookmarks')]
  TAtlasBookmarkStorageTests = class
  private
    FFolder: string;
    function Project: string;
    function UnitFile: string;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
    /// überschrieben.</summary>
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
  Atlas.Core.Bookmarks.Store,
  Atlas.Core.Marks.Ids;

const
  cKundeFile = 'C:\Projekte\Source\Kunde.pas';
  cKundeProject = 'C:\Projekte\Demo.dproj';
  cRoundLine = '  Result := Round(X * Faktor) / Faktor;';

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
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ALines) do
  begin
    if ALines[mIndex] = AText then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Kleine Unit mit zwei Methoden; Runde enthält RoundLine.</summary>
function Code: TArray<string>;
begin
  Result := ['unit Kunde;', '', 'interface', '', 'type', '  TKunde = class', '  public',
    '    function Runde(X: Double): Double;', '    procedure Laden;', '  end;', '', 'implementation', '',
    'function TKunde.Runde(X: Double): Double;', 'var', '  Faktor: Double;', 'begin', '  Faktor := 100;',
    cRoundLine, '  if Result < 0 then', '    Result := 0;', 'end;', '', 'procedure TKunde.Laden;', 'begin',
    '  Pruefen;', 'end;', '', 'end.'];
end;

/// <summary>Eine Methode mit ACount Zeilen (Kopf bis end).</summary>
function Filler(const AName: string; ACount: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := ['procedure ' + AName + ';', 'begin'];
  for mIndex := 1 to ACount - 3 do
  begin
    Result := Result + ['  Schritt' + IntToStr(mIndex) + ';'];
  end;
  Result := Result + ['end;'];
end;

function NewMark(const ALines: TArray<string>; ALine: Integer): TAtlasBookmark;
begin
  Result := Default(TAtlasBookmark);
  Result.Id := 'a';
  Result.Name := 'Rundung';
  Result.FileName := cKundeFile;
  TAtlasBookmarks.Capture(Join(ALines), ALine, Result);
end;

{ TAtlasBookmarkFindTests }

procedure TAtlasBookmarkFindTests.FollowsMethodMovedByFiftyLines;
var
  mLines, mMoved: TArray<string>;
  mList: TAtlasBookmarkList;
  mLine, mOld, mStart: Integer;
begin
  mLines := Code;
  mOld := IndexOfLine(mLines, cRoundLine);
  mList := TAtlasBookmarkList.Create(cKundeProject);
  mList.Add(cKundeFile, Join(mLines), mOld, 'Rundung', 0);
  // 50 Zeilen (eine neue Methode) vor TKunde.Runde.
  mStart := IndexOfLine(mLines, 'function TKunde.Runde(X: Double): Double;');
  mMoved := Insert(mLines, mStart, Filler('Vorher', 50));
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasBookmarks.Find(Join(mMoved), mList.Bookmarks[0], mLine)));
  Assert.AreEqual(mOld + 50, mLine);
  Assert.IsTrue(mList.Relocate(cKundeFile, Join(mMoved)));
  Assert.AreEqual(mOld + 50, mList.Bookmarks[0].Line);
  Assert.IsFalse(mList.Bookmarks[0].Lost);
  Assert.AreEqual('TKunde.Runde', mList.Bookmarks[0].Method);
  // Und zurück: die Methode wieder 50 Zeilen nach oben.
  Assert.IsTrue(mList.Relocate(cKundeFile, Join(mLines)));
  Assert.AreEqual(mOld, mList.Bookmarks[0].Line);
  Assert.IsFalse(mList.Relocate(cKundeFile, Join(mLines)), 'Unverändert: nichts zu speichern');
end;

procedure TAtlasBookmarkFindTests.FollowsLineMovedInsideMethod;
var
  mLines, mMoved: TArray<string>;
  mMark: TAtlasBookmark;
  mLine, mOld, mAssign: Integer;
begin
  mLines := Code;
  mOld := IndexOfLine(mLines, cRoundLine);
  mMark := NewMark(mLines, mOld);
  // Zeile vor "Faktor := 100;" gezogen und zwei Zeilen dazwischen eingefügt.
  mMoved := Without(mLines, mOld, 1);
  mAssign := IndexOfLine(mMoved, '  Faktor := 100;');
  mMoved := Insert(mMoved, mAssign, [cRoundLine, '  // Erst runden', '  Pruefen;']);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasBookmarks.Find(Join(mMoved), mMark, mLine)));
  Assert.AreEqual(mAssign, mLine);
  Assert.AreEqual(cRoundLine, mMoved[mLine]);
end;

procedure TAtlasBookmarkFindTests.MethodDeletedIsLost;
var
  mLines, mGone: TArray<string>;
  mList: TAtlasBookmarkList;
  mLine, mOld, mStart: Integer;
begin
  mLines := Code;
  mOld := IndexOfLine(mLines, cRoundLine);
  mList := TAtlasBookmarkList.Create(cKundeProject);
  mList.Add(cKundeFile, Join(mLines), mOld, 'Rundung', 0);
  // TKunde.Runde samt Leerzeile entfernen (Kopf bis end;).
  mStart := IndexOfLine(mLines, 'function TKunde.Runde(X: Double): Double;');
  mGone := Without(mLines, mStart, 10);
  Assert.AreEqual(-1, IndexOfLine(mGone, cRoundLine));
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned), Ord(TAtlasBookmarks.Find(Join(mGone), mList.Bookmarks[0], mLine)));
  Assert.AreEqual(mOld, mLine, 'Letzte bekannte Zeile');
  Assert.IsTrue(mList.Relocate(cKundeFile, Join(mGone)));
  Assert.AreEqual(1, Integer(mList.Count), 'Bleibt in der Liste');
  Assert.IsTrue(mList.Bookmarks[0].Lost);
  Assert.AreEqual(mOld, mList.Bookmarks[0].Line);
  Assert.AreEqual(1, mList.LostCount);
  Assert.IsFalse(mList.Relocate(cKundeFile, Join(mGone)), 'Schon „nicht gefunden“');
end;

procedure TAtlasBookmarkFindTests.IgnoresSameLineInOtherMethod;
var
  mLines, mChanged: TArray<string>;
  mMark: TAtlasBookmark;
  mLine, mStart: Integer;
begin
  mLines := Code;
  mMark := NewMark(mLines, IndexOfLine(mLines, cRoundLine));
  // Runde heißt jetzt Runden; dieselbe Zeile steht zusätzlich in Laden.
  mChanged := Copy(mLines);
  mStart := IndexOfLine(mChanged, 'function TKunde.Runde(X: Double): Double;');
  mChanged[mStart] := 'function TKunde.Runden(X: Double): Double;';
  mChanged := Insert(mChanged, IndexOfLine(mChanged, '  Pruefen;'), [cRoundLine]);
  Assert.AreEqual(Ord(TAtlasLineMatch.Orphaned), Ord(TAtlasBookmarks.Find(Join(mChanged), mMark, mLine)));
end;

procedure TAtlasBookmarkFindTests.ReplacedFileKeepsLostBookmark;
var
  mLines: TArray<string>;
  mList: TAtlasBookmarkList;
  mOld: Integer;
begin
  mLines := Code;
  mOld := IndexOfLine(mLines, cRoundLine);
  mList := TAtlasBookmarkList.Create(cKundeProject);
  mList.Add(cKundeFile, Join(mLines), mOld, 'Rundung', 0);
  Assert.IsTrue(mList.Relocate(cKundeFile, Join(['unit Kunde;', '', 'interface', '', 'implementation', '', 'end.'])));
  Assert.AreEqual(1, Integer(mList.Count));
  Assert.IsTrue(mList.Bookmarks[0].Lost);
  Assert.AreEqual('Rundung', mList.Bookmarks[0].Name);
  Assert.AreEqual('TKunde.Runde', mList.Bookmarks[0].Method, 'Die Methode bleibt gemerkt');
  // Die Methode kommt zurück (z. B. Datei wiederhergestellt): wieder gültig.
  Assert.IsTrue(mList.Relocate(cKundeFile, Join(mLines)));
  Assert.IsFalse(mList.Bookmarks[0].Lost);
  Assert.AreEqual(mOld, mList.Bookmarks[0].Line);
end;

procedure TAtlasBookmarkFindTests.MissingFileLosesBookmarks;
var
  mList: TAtlasBookmarkList;
begin
  mList := TAtlasBookmarkList.Create(cKundeProject);
  mList.Add(cKundeFile, Join(Code), 18, 'Rundung', 0);
  mList.Add('C:\Projekte\Source\Andere.pas', Join(Code), 18, 'Andere', 0);
  Assert.IsTrue(mList.LoseFile('c:/projekte/source/KUNDE.pas'));
  Assert.IsTrue(mList.Bookmarks[0].Lost);
  Assert.IsFalse(mList.Bookmarks[1].Lost);
  Assert.IsFalse(mList.LoseFile(cKundeFile), 'Schon „nicht gefunden“');
end;

procedure TAtlasBookmarkFindTests.OverloadPrefersSameParameters;
var
  mLines, mSwapped: TArray<string>;
  mMark: TAtlasBookmark;
  mLine: Integer;
begin
  mLines := ['unit Werte;', '', 'interface', '', 'implementation', '', 'procedure Zeige(A: Integer); overload;',
    'begin', '  Ausgeben(A);', 'end;', '', 'procedure Zeige(const A: string); overload;', 'begin', '  Ausgeben(A);',
    'end;', '', 'end.'];
  mMark := NewMark(mLines, 13);
  Assert.AreEqual('Zeige', mMark.Method);
  Assert.AreEqual('string', mMark.Signature);
  Assert.AreEqual(2, mMark.Offset);
  // Die Überladungen tauschen die Plätze: das Lesezeichen geht mit der string-Fassung.
  mSwapped := ['unit Werte;', '', 'interface', '', 'implementation', '', 'procedure Zeige(const A: string); overload;',
    'begin', '  Ausgeben(A);', 'end;', '', 'procedure Zeige(A: Integer); overload;', 'begin', '  Ausgeben(A);',
    'end;', '', 'end.'];
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasBookmarks.Find(Join(mSwapped), mMark, mLine)));
  Assert.AreEqual(8, mLine);
end;

procedure TAtlasBookmarkFindTests.ChangedLineStaysAndLearnsText;
var
  mLines, mEdited: TArray<string>;
  mList: TAtlasBookmarkList;
  mLine, mOld: Integer;
begin
  mLines := Code;
  mOld := IndexOfLine(mLines, cRoundLine);
  mList := TAtlasBookmarkList.Create(cKundeProject);
  mList.Add(cKundeFile, Join(mLines), mOld, 'Rundung', 0);
  mEdited := Copy(mLines);
  mEdited[mOld] := '  Result := Round(X * Faktor + 0.5) / Faktor;';
  Assert.AreEqual(Ord(TAtlasLineMatch.Changed), Ord(TAtlasBookmarks.Find(Join(mEdited), mList.Bookmarks[0], mLine)));
  Assert.AreEqual(mOld, mLine);
  Assert.IsTrue(mList.Relocate(cKundeFile, Join(mEdited)));
  Assert.AreEqual('Result := Round(X * Faktor + 0.5) / Faktor;', mList.Bookmarks[0].Preview);
  Assert.IsFalse(mList.Bookmarks[0].Lost);
end;

procedure TAtlasBookmarkFindTests.OutsideMethodSearchesWholeFile;
var
  mLines, mMoved: TArray<string>;
  mMark: TAtlasBookmark;
  mLine, mOld: Integer;
begin
  mLines := Code;
  mOld := IndexOfLine(mLines, '  TKunde = class');
  mMark := NewMark(mLines, mOld);
  Assert.AreEqual('', mMark.Method);
  mMoved := Insert(mLines, 2, ['// Kopf', '// noch mehr', '']);
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasBookmarks.Find(Join(mMoved), mMark, mLine)));
  Assert.AreEqual(mOld + 3, mLine);
end;

procedure TAtlasBookmarkFindTests.CaptureRemembersMethodAndOffset;
var
  mLines: TArray<string>;
  mMark: TAtlasBookmark;
  mStart: Integer;
begin
  mLines := Code;
  mStart := IndexOfLine(mLines, 'function TKunde.Runde(X: Double): Double;');
  mMark := NewMark(mLines, IndexOfLine(mLines, cRoundLine));
  Assert.AreEqual('TKunde.Runde', mMark.Method);
  Assert.AreEqual('double', mMark.Signature);
  Assert.AreEqual(IndexOfLine(mLines, cRoundLine) - mStart, mMark.Offset);
  Assert.AreEqual('Result := Round(X * Faktor) / Faktor;', mMark.Preview);
  Assert.AreEqual(2, Integer(Length(mMark.Anchor.Before)));
  // Auf der Kopfzeile: Abstand 0.
  mMark := NewMark(mLines, mStart);
  Assert.AreEqual('TKunde.Runde', mMark.Method);
  Assert.AreEqual(0, mMark.Offset);
end;

procedure TAtlasBookmarkFindTests.RepeatedLineKeepsItsPlace;
var
  mLines, mMoved: TArray<string>;
  mMark: TAtlasBookmark;
  mLine: Integer;
begin
  // Zweimal "Inc(N);" in der Methode: es gilt die Stelle mit dem passenden Umfeld, nicht die erste.
  mLines := ['unit Zaehler;', '', 'implementation', '', 'procedure Zaehle;', 'begin', '  A;', '  Inc(N);', '  B;',
    '  C;', '  D;', '  Inc(N);', '  E;', 'end;', '', 'end.'];
  mMark := NewMark(mLines, 11);
  Assert.AreEqual(7, mMark.Offset);
  mMoved := Insert(mLines, 4, Filler('Davor', 20));
  Assert.AreEqual(Ord(TAtlasLineMatch.Moved), Ord(TAtlasBookmarks.Find(Join(mMoved), mMark, mLine)));
  Assert.AreEqual(31, mLine);
end;

{ TAtlasBookmarkListTests }

procedure TAtlasBookmarkListTests.AddRenameAndRemove;
var
  mList: TAtlasBookmarkList;
  mId, mOther: string;
begin
  mList := TAtlasBookmarkList.Create(cKundeProject);
  mId := mList.Add(cKundeFile, Join(Code), 18, '  Rundung  ', EncodeDate(2026, 10, 15));
  mOther := mList.Add(cKundeFile, Join(Code), 25, 'Laden', 0);
  Assert.AreNotEqual('', mId);
  Assert.AreNotEqual(mId, mOther);
  Assert.AreEqual(2, Integer(mList.Count));
  Assert.AreEqual('Rundung', mList.Bookmarks[0].Name);
  Assert.AreEqual<TDateTime>(EncodeDate(2026, 10, 15), mList.Bookmarks[0].Created);
  Assert.AreEqual(0, mList.IndexOf(UpperCase(mId)));
  Assert.IsTrue(mList.Rename(mId, 'Rundung prüfen'));
  Assert.AreEqual('Rundung prüfen', mList.Bookmarks[0].Name);
  Assert.IsFalse(mList.Rename(mId, '   '), 'Leerer Name');
  Assert.IsFalse(mList.Rename('unbekannt', 'X'));
  Assert.IsTrue(mList.Remove(mId));
  Assert.IsFalse(mList.Remove(mId));
  Assert.AreEqual(1, Integer(mList.Count));
  Assert.AreEqual(mOther, mList.Bookmarks[0].Id);
end;

procedure TAtlasBookmarkListTests.MoveBeforeReorders;
var
  mList: TAtlasBookmarkList;
  A, C: string;

  function Order: string;
  var
    mMark: TAtlasBookmark;
  begin
    Result := '';
    for mMark in mList.Bookmarks do
    begin
      Result := Result + mMark.Name;
    end;
  end;

begin
  mList := TAtlasBookmarkList.Create(cKundeProject);
  A := mList.Add(cKundeFile, Join(Code), 18, 'A', 0);
  mList.Add(cKundeFile, Join(Code), 19, 'B', 0);
  C := mList.Add(cKundeFile, Join(Code), 20, 'C', 0);
  Assert.IsTrue(mList.MoveBefore(C, A));
  Assert.AreEqual('CAB', Order);
  Assert.IsTrue(mList.MoveBefore(C, ''));
  Assert.AreEqual('ABC', Order);
  Assert.IsTrue(mList.MoveBefore(A, C));
  Assert.AreEqual('BAC', Order);
  Assert.IsFalse(mList.MoveBefore(A, C), 'Steht schon davor');
  Assert.IsFalse(mList.MoveBefore(C, ''), 'Steht schon am Ende');
  Assert.IsFalse(mList.MoveBefore(A, A));
  Assert.IsFalse(mList.MoveBefore(A, 'unbekannt'));
  Assert.IsFalse(mList.MoveBefore('unbekannt', A));
  Assert.AreEqual('BAC', Order);
end;

procedure TAtlasBookmarkListTests.FilterMatchesEveryWord;
var
  mList: TAtlasBookmarkList;
  mFound: TArray<Integer>;
begin
  mList := TAtlasBookmarkList.Create(cKundeProject);
  mList.Add(cKundeFile, Join(Code), 18, 'Rundung', 0);
  mList.Add('C:\Projekte\Source\Lager.pas', Join(Code), 25, 'Laden prüfen', 0);
  Assert.AreEqual(2, Integer(Length(mList.Filter(''))));
  mFound := mList.Filter('kunde round');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(0, mFound[0]);
  mFound := mList.Filter('LAGER laden');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(1, mFound[0]);
  // Methode zählt mit, der Ordner nicht.
  Assert.AreEqual(1, Integer(Length(mList.Filter('TKunde.Runde'))));
  Assert.AreEqual(0, Integer(Length(mList.Filter('projekte'))));
  Assert.AreEqual(0, Integer(Length(mList.Filter('rundung lager'))));
end;

procedure TAtlasBookmarkListTests.AtLineSkipsLostBookmarks;
var
  mList: TAtlasBookmarkList;
begin
  mList := TAtlasBookmarkList.Create(cKundeProject);
  mList.Add(cKundeFile, Join(Code), 18, 'Eins', 0);
  mList.Add(cKundeFile, Join(Code), 18, 'Zwei', 0);
  Assert.AreEqual(2, Integer(Length(mList.AtLine('c:/projekte/source/kunde.pas', 18))));
  Assert.AreEqual(0, Integer(Length(mList.AtLine(cKundeFile, 17))));
  mList.Bookmarks[1].Lost := True;
  Assert.AreEqual(1, Integer(Length(mList.AtLine(cKundeFile, 18))));
  Assert.AreEqual(2, Integer(Length(mList.ForFile(cKundeFile))));
end;

procedure TAtlasBookmarkListTests.FilesAndLostCount;
var
  mList: TAtlasBookmarkList;
  mFiles: TArray<string>;
begin
  mList := TAtlasBookmarkList.Create(cKundeProject);
  mList.Add(cKundeFile, Join(Code), 18, 'Eins', 0);
  mList.Add('C:\Projekte\Source\Lager.pas', Join(Code), 18, 'Zwei', 0);
  mList.Add('c:\projekte\source\KUNDE.pas', Join(Code), 25, 'Drei', 0);
  mFiles := mList.Files;
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual(cKundeFile, mFiles[0]);
  Assert.AreEqual(0, mList.LostCount);
  mList.LoseFile(cKundeFile);
  Assert.AreEqual(2, mList.LostCount);
end;

procedure TAtlasBookmarkListTests.SuggestsMethodAndLineStart;
var
  mLines: TArray<string>;
begin
  mLines := Code;
  Assert.AreEqual('Runde: Result := Round(X * Faktor) / Faktor;',
    TAtlasBookmarks.SuggestName(cKundeFile, Join(mLines), IndexOfLine(mLines, cRoundLine)));
  mLines[IndexOfLine(mLines, cRoundLine)] := '  Result := Round(X * Faktor) / Faktor + Zuschlag(Kunde, Datum, Waehrung);';
  Assert.AreEqual('Runde: Result := Round(X * Faktor) / Faktor + Z…',
    TAtlasBookmarks.SuggestName(cKundeFile, Join(mLines), 18));
  // Leere Zeile in der Methode: nur der Methodenname.
  mLines[18] := '';
  Assert.AreEqual('Runde', TAtlasBookmarks.SuggestName(cKundeFile, Join(mLines), 18));
end;

procedure TAtlasBookmarkListTests.SuggestionOutsideMethod;
begin
  Assert.AreEqual('TKunde = class', TAtlasBookmarks.SuggestName(cKundeFile, Join(Code), 5));
  Assert.AreEqual('Kunde.pas:2', TAtlasBookmarks.SuggestName(cKundeFile, Join(Code), 1));
end;

procedure TAtlasBookmarkListTests.LocationNamesFileLineAndMethod;
var
  mList: TAtlasBookmarkList;
begin
  mList := TAtlasBookmarkList.Create(cKundeProject);
  mList.Add(cKundeFile, Join(Code), 18, 'Rundung', 0);
  mList.Add(cKundeFile, Join(Code), 5, 'Klasse', 0);
  Assert.AreEqual('Kunde.pas:19 › TKunde.Runde', TAtlasBookmarks.Location(mList.Bookmarks[0]));
  Assert.AreEqual('Kunde.pas:6', TAtlasBookmarks.Location(mList.Bookmarks[1]));
end;

procedure TAtlasBookmarkListTests.PaletteFindsByNameAndLocation;
var
  mList: TAtlasBookmarkList;
  mCommands: TArray<TAtlasCommand>;
  mCommand: TAtlasCommand;
  mMark: TAtlasBookmark;
  mOrder: TArray<Integer>;
begin
  mList := TAtlasBookmarkList.Create(cKundeProject);
  mList.Add(cKundeFile, Join(Code), 18, 'Rundung prüfen', 0);
  mList.Add('C:\Projekte\Source\Lager.pas', Join(Code), 25, 'Bestand laden', 0);
  mList.Add(cKundeFile, Join(Code), 5, 'Klasse aufteilen', 0);
  // Wie TAtlasIdeBookmarks.GoToBookmark: Name als Beschriftung, Ort als Pfad.
  mCommands := nil;
  for mMark in mList.Bookmarks do
  begin
    mCommand := Default(TAtlasCommand);
    mCommand.Id := mMark.Id;
    mCommand.Caption := mMark.Name;
    mCommand.Path := TAtlasBookmarks.Location(mMark);
    mCommands := mCommands + [mCommand];
  end;
  // Ohne Eingabe: Reihenfolge der Liste.
  mOrder := TAtlasCommandPalette.Order(mCommands, '', nil, True);
  Assert.AreEqual(3, Integer(Length(mOrder)));
  Assert.AreEqual(0, mOrder[0]);
  Assert.AreEqual(2, mOrder[2]);
  // Unscharf über den Namen: Wortanfänge.
  mOrder := TAtlasCommandPalette.Order(mCommands, 'rp', nil, True);
  Assert.IsTrue(Length(mOrder) > 0);
  Assert.AreEqual(0, mOrder[0]);
  // Über den Ort: Dateiname, der im Namen nicht vorkommt.
  mOrder := TAtlasCommandPalette.Order(mCommands, 'lager', nil, True);
  Assert.IsTrue(Length(mOrder) > 0);
  Assert.AreEqual(1, mOrder[0]);
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
  begin
    TDirectory.Delete(FFolder, True);
  end;
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
  mList, mBack: TAtlasBookmarkList;
  mJson: string;
  mRoot: TJSONValue;
  mMark: TJSONObject;
begin
  mList := TAtlasBookmarkList.Create(Project);
  mList.Add(UnitFile, Join(Code), 18, 'Rundung', EncodeDate(2026, 10, 15) + EncodeTime(9, 30, 0, 0));
  mList.Add(UnitFile, Join(Code), 5, 'Klasse', 0);
  mList.Bookmarks[1].Lost := True;
  mJson := TAtlasBookmarks.ToJson(mList, IncludeTrailingPathDelimiter(FFolder));
  mRoot := TJSONObject.ParseJSONValue(mJson);
  try
    Assert.AreEqual('Demo.dproj', TJSONObject(mRoot).GetValue('project').Value);
    mMark := TJSONObject(TJSONArray(TJSONObject(mRoot).GetValue('bookmarks')).Items[0]);
    Assert.AreEqual('Source/Kunde.pas', mMark.GetValue('file').Value);
    Assert.AreEqual('19', mMark.GetValue('line').Value, '1-basiert');
    Assert.AreEqual('TKunde.Runde', mMark.GetValue('method').Value);
    Assert.AreEqual('2026-10-15T09:30:00Z', mMark.GetValue('created').Value);
    Assert.IsNull(mMark.GetValue('lost'));
  finally
    mRoot.Free;
  end;
  Assert.IsTrue(TAtlasBookmarks.Parse(mJson, IncludeTrailingPathDelimiter(FFolder), mBack));
  Assert.AreEqual(2, Integer(mBack.Count));
  Assert.AreEqual(Project, mBack.Project);
  Assert.IsTrue(TAtlasMarkIds.SameFile(UnitFile, mBack.Bookmarks[0].FileName));
  Assert.AreEqual(mList.Bookmarks[0].Id, mBack.Bookmarks[0].Id);
  Assert.AreEqual('Rundung', mBack.Bookmarks[0].Name);
  Assert.AreEqual('TKunde.Runde', mBack.Bookmarks[0].Method);
  Assert.AreEqual('double', mBack.Bookmarks[0].Signature);
  Assert.AreEqual(mList.Bookmarks[0].Offset, mBack.Bookmarks[0].Offset);
  Assert.IsTrue(mList.Bookmarks[0].Anchor.SameAs(mBack.Bookmarks[0].Anchor));
  Assert.IsTrue(Abs(mList.Bookmarks[0].Created - mBack.Bookmarks[0].Created) < 1 / 86400);
  Assert.IsFalse(mBack.Bookmarks[0].Lost);
  Assert.IsTrue(mBack.Bookmarks[1].Lost);
  Assert.AreEqual('', mBack.Bookmarks[1].Method);
end;

procedure TAtlasBookmarkStorageTests.ParsesDocumentedFormat;
const
  cJson = '{"format": 1, "project": "Demo.dproj", "bookmarks": [' +
    '{"id": "5f0c", "name": "Rundung prüfen", "file": "Source/Kunde.pas", "method": "TKunde.Runde",' +
    ' "signature": "double", "offset": 5, "line": 19, "lineText": "Result := Round(X * Faktor) / Faktor;",' +
    ' "before": ["Faktor := 100;", "begin"], "after": ["if Result < 0 then", "Result := 0;"],' +
    ' "created": "2026-10-15T09:30:00Z", "lost": true},' +
    '{"id": "", "file": "Source/Kunde.pas"}, {"id": "ohne-datei"}, 7,' +
    '{"id": "ohne-name", "file": "Source/Kunde.pas", "line": 3}]}';
var
  mList: TAtlasBookmarkList;
  mLine: Integer;
begin
  Assert.IsTrue(TAtlasBookmarks.Parse(cJson, IncludeTrailingPathDelimiter(FFolder), mList));
  Assert.AreEqual(2, Integer(mList.Count), 'Einträge ohne Kennung oder Datei fallen weg');
  Assert.AreEqual('Rundung prüfen', mList.Bookmarks[0].Name);
  Assert.AreEqual(18, mList.Bookmarks[0].Line);
  Assert.AreEqual(5, mList.Bookmarks[0].Offset);
  Assert.IsTrue(mList.Bookmarks[0].Lost);
  Assert.AreEqual('Faktor := 100;', mList.Bookmarks[0].Anchor.Before[0]);
  Assert.AreEqual('Kunde.pas:3', mList.Bookmarks[1].Name, 'Ohne Namen: Datei und Zeile');
  // Das gelesene Lesezeichen findet sich im Code wieder.
  Assert.AreEqual(Ord(TAtlasLineMatch.Same), Ord(TAtlasBookmarks.Find(Join(Code), mList.Bookmarks[0], mLine)));
  Assert.AreEqual(18, mLine);
end;

procedure TAtlasBookmarkStorageTests.KeepsUnknownFields;
const
  cJson = '{"format": 1, "project": "Demo.dproj", "team": {"owner": "Marco"}, "bookmarks": [' +
    '{"id": "a", "name": "A", "file": "Source/Kunde.pas", "line": 1, "lineText": "unit Kunde;", "color": "red"}]}';
var
  mList: TAtlasBookmarkList;
  mJson2: string;
  mRoot: TJSONObject;
  mMark: TJSONObject;
begin
  Assert.IsTrue(TAtlasBookmarks.Parse(cJson, IncludeTrailingPathDelimiter(FFolder), mList));
  mList.Rename('a', 'B');
  mJson2 := TAtlasBookmarks.ToJson(mList, IncludeTrailingPathDelimiter(FFolder));
  mRoot := TJSONObject(TJSONObject.ParseJSONValue(mJson2));
  try
    Assert.IsNotNull(mRoot.GetValue('team'));
    mMark := TJSONObject(TJSONArray(mRoot.GetValue('bookmarks')).Items[0]);
    Assert.AreEqual('red', mMark.GetValue('color').Value);
    Assert.AreEqual('B', mMark.GetValue('name').Value);
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasBookmarkStorageTests.RejectsInvalidAndNewerFormat;
var
  mList: TAtlasBookmarkList;
begin
  Assert.IsFalse(TAtlasBookmarks.Parse('', FFolder, mList));
  Assert.IsFalse(TAtlasBookmarks.Parse('kein json', FFolder, mList));
  Assert.IsFalse(TAtlasBookmarks.Parse('[1, 2]', FFolder, mList));
  Assert.IsFalse(TAtlasBookmarks.Parse('{"format": 3, "bookmarks": []}', FFolder, mList));
  Assert.AreEqual(0, Integer(mList.Count));
  Assert.IsTrue(TAtlasBookmarks.Parse('{"bookmarks": []}', FFolder, mList), 'Ohne format gilt 1');
  Assert.AreEqual(3, TAtlasBookmarks.FormatOf('{"format": 3}'));
  Assert.AreEqual(0, TAtlasBookmarks.FormatOf('kaputt'));
end;

procedure TAtlasBookmarkStorageTests.SaveAndLoadLocal;
var
  mList, mBack: TAtlasBookmarkList;
  mBytes: TBytes;
begin
  mList := TAtlasBookmarkList.Create(Project);
  mList.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(mList, False));
  Assert.IsTrue(FileExists(TPath.Combine(FFolder, '.atlas-bookmarks.json')));
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, 'atlas-bookmarks.json')));
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, '.atlas-bookmarks.json.tmp')));
  mBytes := TFile.ReadAllBytes(TPath.Combine(FFolder, '.atlas-bookmarks.json'));
  Assert.AreEqual(Ord('{'), Integer(mBytes[0]), 'Ohne BOM');
  // „IDE-Neustart“: frisch laden, Lesezeichen und Methode sind wieder da.
  Assert.IsTrue(TAtlasBookmarks.Load(Project, False, mBack));
  Assert.AreEqual(1, Integer(mBack.Count));
  Assert.AreEqual(Project, mBack.Project);
  Assert.AreEqual('Rundung', mBack.Bookmarks[0].Name);
  Assert.IsTrue(TAtlasMarkIds.SameFile(UnitFile, mBack.Bookmarks[0].FileName));
  Assert.AreEqual('TKunde.Runde', mBack.Bookmarks[0].Method);
  // Auch ein anderes Projekt im selben Ordner liest dieselbe Datei.
  Assert.IsTrue(TAtlasBookmarks.Load(TPath.Combine(FFolder, 'Zweites.dproj'), False, mBack));
  Assert.AreEqual(1, Integer(mBack.Count));
  Assert.AreEqual(TPath.Combine(FFolder, 'Zweites.dproj'), mBack.Project);
end;

procedure TAtlasBookmarkStorageTests.SharedFallsBackToLocalUntilCreated;
var
  mList, mBack: TAtlasBookmarkList;
begin
  mList := TAtlasBookmarkList.Create(Project);
  mList.Add(UnitFile, Join(Code), 18, 'Lokal', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(mList, False));
  // Team-Ablage eingeschaltet: zunächst die lokalen Lesezeichen.
  Assert.IsTrue(TAtlasBookmarks.Load(Project, True, mBack));
  Assert.AreEqual('Lokal', mBack.Bookmarks[0].Name);
  mBack.Rename(mBack.Bookmarks[0].Id, 'Team');
  Assert.IsTrue(TAtlasBookmarks.Save(mBack, True));
  Assert.IsTrue(FileExists(TPath.Combine(FFolder, 'atlas-bookmarks.json')));
  // Ab jetzt gilt die Datei des Teams.
  Assert.IsTrue(TAtlasBookmarks.Load(Project, True, mBack));
  Assert.AreEqual('Team', mBack.Bookmarks[0].Name);
  Assert.IsTrue(TAtlasBookmarks.Load(Project, False, mBack));
  Assert.AreEqual('Lokal', mBack.Bookmarks[0].Name, 'Die lokale Datei bleibt unberührt');
end;

procedure TAtlasBookmarkStorageTests.EmptyListRemovesFile;
var
  mList: TAtlasBookmarkList;
begin
  mList := TAtlasBookmarkList.Create(Project);
  mList.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(mList, False));
  mList.Remove(mList.Bookmarks[0].Id);
  Assert.IsTrue(TAtlasBookmarks.Save(mList, False));
  Assert.IsFalse(FileExists(TPath.Combine(FFolder, '.atlas-bookmarks.json')));
  Assert.IsTrue(TAtlasBookmarks.Save(mList, False), 'Ohne Datei nichts zu tun');
end;

procedure TAtlasBookmarkStorageTests.SaveKeepsNewerFormatFile;
var
  mList: TAtlasBookmarkList;
  mFileName: string;
begin
  mFileName := TPath.Combine(FFolder, '.atlas-bookmarks.json');
  WriteText(mFileName, '{"format": 3, "bookmarks": []}');
  Assert.IsFalse(TAtlasBookmarks.Load(Project, False, mList));
  Assert.AreEqual(0, Integer(mList.Count));
  Assert.AreEqual(Project, mList.Project);
  mList.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsFalse(TAtlasBookmarks.Save(mList, False));
  Assert.AreEqual(3, TAtlasBookmarks.FormatOf(TFile.ReadAllText(mFileName, TEncoding.UTF8)));
end;

procedure TAtlasBookmarkStorageTests.LoadWithoutFileIsEmpty;
var
  mList: TAtlasBookmarkList;
begin
  Assert.IsFalse(TAtlasBookmarks.Load(Project, False, mList));
  Assert.AreEqual(0, Integer(mList.Count));
  Assert.AreEqual(Project, mList.Project);
  Assert.IsFalse(TAtlasBookmarks.Load(Project, True, mList));
  Assert.IsFalse(TAtlasBookmarks.Load('', False, mList));
end;

procedure TAtlasBookmarkStorageTests.LocalFileIsExcludedFromGit;
var
  mList: TAtlasBookmarkList;
  mExclude, mText: string;
  mSub: string;
begin
  // Repository eine Ebene über dem Projekt: Muster mit Unterordner.
  ForceDirectories(TPath.Combine(TPath.Combine(FFolder, '.git'), 'info'));
  mExclude := TPath.Combine(TPath.Combine(TPath.Combine(FFolder, '.git'), 'info'), 'exclude');
  WriteText(mExclude, '# vorhanden' + #10 + '*.bak');
  mSub := TPath.Combine(FFolder, 'App');
  ForceDirectories(mSub);
  mList := TAtlasBookmarkList.Create(TPath.Combine(mSub, 'App.dproj'));
  mList.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(mList, False));
  mText := TFile.ReadAllText(mExclude, TEncoding.UTF8);
  Assert.IsTrue(mText.StartsWith('# vorhanden' + #10 + '*.bak' + #10), mText);
  Assert.IsTrue(mText.Contains(#10 + '/App/.atlas-bookmarks.json' + #10), mText);
  // Zweites Speichern trägt nicht noch einmal ein.
  Assert.IsTrue(TAtlasBookmarks.Save(mList, False));
  Assert.AreEqual(mText, TFile.ReadAllText(mExclude, TEncoding.UTF8));
  Assert.IsTrue(TAtlasBookmarks.ExcludeFromGit(TAtlasBookmarks.FileFor(mList.Project, False)));
end;

procedure TAtlasBookmarkStorageTests.WorktreeUsesCommonExclude;
var
  mMain, mTree, mAdmin, mExclude: string;
begin
  // Hauptrepository in Main, Worktree in Tree mit ".git"-Datei und commondir.
  mMain := TPath.Combine(FFolder, 'Main');
  mTree := TPath.Combine(FFolder, 'Tree');
  mAdmin := TPath.Combine(TPath.Combine(TPath.Combine(mMain, '.git'), 'worktrees'), 'Tree');
  ForceDirectories(mAdmin);
  ForceDirectories(mTree);
  WriteText(TPath.Combine(mTree, '.git'), 'gitdir: ' + mAdmin.Replace('\', '/') + #10);
  WriteText(TPath.Combine(mAdmin, 'commondir'), '../..' + #10);
  Assert.IsTrue(TAtlasBookmarks.ExcludeFromGit(TPath.Combine(mTree, '.atlas-bookmarks.json')));
  mExclude := TPath.Combine(TPath.Combine(TPath.Combine(mMain, '.git'), 'info'), 'exclude');
  Assert.IsTrue(FileExists(mExclude));
  Assert.IsTrue(TFile.ReadAllText(mExclude, TEncoding.UTF8).Contains('/.atlas-bookmarks.json' + #10));
end;

procedure TAtlasBookmarkStorageTests.SharedFileIsNotExcluded;
var
  mList: TAtlasBookmarkList;
begin
  ForceDirectories(TPath.Combine(FFolder, '.git'));
  mList := TAtlasBookmarkList.Create(Project);
  mList.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(mList, True));
  Assert.IsFalse(FileExists(TPath.Combine(TPath.Combine(TPath.Combine(FFolder, '.git'), 'info'), 'exclude')));
end;

procedure TAtlasBookmarkStorageTests.WithoutRepositoryNothingIsExcluded;
var
  mList: TAtlasBookmarkList;
begin
  mList := TAtlasBookmarkList.Create(Project);
  mList.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(mList, False), 'Speichern klappt auch ohne Git');
  Assert.IsFalse(DirectoryExists(TPath.Combine(FFolder, '.git')));
end;

procedure TAtlasBookmarkStorageTests.WarmUpFirstUse;
begin
  // Gesperrte Datei: Erstgebrauch der Melde- und Fehlerpfade.
  Setup;
  try
    BrokenFileSetAsideLockedFileKept;
  finally
    TearDown;
  end;
end;

procedure TAtlasBookmarkStorageTests.BrokenFileSetAsideLockedFileKept;
var
  mList: TAtlasBookmarkList;
  mFileName: string;
  mLock: TFileStream;
begin
  mFileName := TPath.Combine(FFolder, '.atlas-bookmarks.json');
  WriteText(mFileName, '{"bookmarks": [');
  Assert.IsFalse(TAtlasBookmarks.Load(Project, False, mList));
  Assert.AreEqual(Project, mList.Project);
  Assert.IsTrue(FileExists(mFileName + TAtlasDataFile.cDefectExtension), 'beiseitegelegt');
  Assert.IsFalse(FileExists(mFileName));
  mList.Add(UnitFile, Join(Code), 18, 'Rundung', 0);
  Assert.IsTrue(TAtlasBookmarks.Save(mList, False));
  mLock := TFileStream.Create(mFileName, fmOpenRead or fmShareExclusive);
  try
    Assert.IsFalse(TAtlasBookmarks.Load(Project, False, mList));
  finally
    mLock.Free;
  end;
  Assert.AreEqual(0, Integer(mList.Count));
  Assert.AreEqual(mFileName, mList.KeptFile);
  mList.Add(UnitFile, Join(Code), 18, 'Ersatz', 0);
  Assert.IsFalse(TAtlasBookmarks.Save(mList, False), 'beim Laden gesperrt: nicht überschreiben');
  Assert.Contains(TFile.ReadAllText(mFileName, TEncoding.UTF8), 'Rundung');
  Assert.DoesNotContain(TFile.ReadAllText(mFileName, TEncoding.UTF8), 'Ersatz');
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBookmarkFindTests);
  TDUnitX.RegisterTestFixture(TAtlasBookmarkListTests);
  TDUnitX.RegisterTestFixture(TAtlasBookmarkStorageTests);

end.
