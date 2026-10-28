unit Atlas.Core.Bookmarks.Quick.Tests;

// Tests der schnellen Lesezeichen (#1104): Nummer setzen, umziehen,
// entfernen; mehrere an einer Zeile (Reihenfolge); Klick in die Spalte;
// unnummerierte umschalten; Sprungziel projektweit und je Datei; reihum
// springen; Format 1 → 2; Übernahme der IDE-Lesezeichen; Entscheidung nach
// Strg+Umschalt+K (Faltungsbuchstabe, Zeitüberschreitung, andere Taste,
// Wartezeit 0); Tasten 1–9 aus einer Grundtaste.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Bookmarks.Store;

type
  [TestFixture]
  TAtlasQuickBookmarkTests = class
  private
    FList: TAtlasBookmarkList;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Abnahme: Strg+Umschalt+3 in Zeile 33, umziehen nach 40, dort nochmals = entfernt.</summary>
    [Test]
    procedure NumberSetMovesAndRemoves;
    [Test]
    procedure NumberMovesAcrossFiles;
    [Test]
    procedure SeveralMarksSmallestNumberFirst;
    [Test]
    procedure ClickSetsAndRemoves;
    [Test]
    procedure ClickTakesFreeNumberOrNone;
    [Test]
    procedure ClickOnNamedNumberKeepsNamedBookmark;
    [Test]
    procedure ToggleUnnumbered;
    [Test]
    procedure AssignNumberFromWindow;
    [Test]
    procedure RemoveFileKeepsNamed;
    [Test]
    procedure JumpProjectAndFileScope;
    [Test]
    procedure StepCyclesThroughFile;
    [Test]
    procedure QuickBookmarksFollowInsertedLines;
    [Test]
    procedure DisplayNameWithoutName;
    [Test]
    procedure FormatOneLoadsAndSavesAsTwo;
    [Test]
    procedure KindAndNumberRoundTrip;
    [Test]
    procedure ImportTakesIdeBookmarks;
    [Test]
    procedure ChordDecision;
    [Test]
    procedure KeysForNumbers;
    [Test]
    procedure ColumnWidthFollowsLineHeight;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Bookmarks.Quick;

const
  KundeFile = 'C:\Projekte\Source\Kunde.pas';
  LagerFile = 'C:\Projekte\Source\Lager.pas';
  Project = 'C:\Projekte\Demo.dproj';

/// <summary>Unit mit 60 Zeilen: Zeile i (0-basiert) heißt „  Schritt{i};“, dazwischen eine Methode.</summary>
function Lines(ACount: Integer): TArray<string>;
var
  Index: Integer;
begin
  Result := ['unit Kunde;', '', 'implementation', '', 'procedure Laden;', 'begin'];
  for Index := Length(Result) to ACount - 3 do
    Result := Result + ['  Schritt' + IntToStr(Index) + ';'];
  Result := Result + ['end;', 'end.'];
end;

function Text: string;
begin
  Result := string.Join(#13#10, Lines(60));
end;

{ TAtlasQuickBookmarkTests }

procedure TAtlasQuickBookmarkTests.Setup;
begin
  FList := TAtlasBookmarkList.Create(Project);
end;

procedure TAtlasQuickBookmarkTests.TearDown;
begin
  FList := Default(TAtlasBookmarkList);
end;

procedure TAtlasQuickBookmarkTests.NumberSetMovesAndRemoves;
var
  Marks: TArray<TAtlasBookmark>;
begin
  Assert.AreEqual(Ord(TAtlasQuickChange.Added), Ord(TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 32, 3, 0)));
  Marks := TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 32);
  Assert.AreEqual(1, Integer(Length(Marks)));
  Assert.AreEqual(3, Marks[0].Number);
  Assert.AreEqual(Ord(TAtlasBookmarkKind.Quick), Ord(Marks[0].Kind));
  Assert.AreEqual('', Marks[0].Name, 'schnelle Lesezeichen ohne Namen');
  // Strg+Umschalt+3 in Zeile 40: die 3 zieht um.
  Assert.AreEqual(Ord(TAtlasQuickChange.Moved), Ord(TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 39, 3, 0)));
  Assert.AreEqual(0, Integer(Length(TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 32))));
  Assert.AreEqual(3, TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 39)[0].Number);
  Assert.AreEqual(1, Integer(FList.Count), 'jede Nummer höchstens einmal');
  // Nochmals in Zeile 40: entfernt.
  Assert.AreEqual(Ord(TAtlasQuickChange.Removed),
    Ord(TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 39, 3, 0)));
  Assert.AreEqual(0, Integer(FList.Count));
  Assert.AreEqual(Ord(TAtlasQuickChange.None), Ord(TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 39, 0, 0)));
  Assert.AreEqual(Ord(TAtlasQuickChange.None), Ord(TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 39, 10, 0)));
end;

procedure TAtlasQuickBookmarkTests.NumberMovesAcrossFiles;
begin
  TAtlasQuickBookmarks.SetNumber(FList, LagerFile, Text, 10, 5, 0);
  Assert.AreEqual(Ord(TAtlasQuickChange.Moved), Ord(TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 20, 5, 0)));
  Assert.AreEqual(1, Integer(FList.Count));
  Assert.IsTrue(TAtlasBookmarks.SameFile(KundeFile, FList.Bookmarks[0].FileName));
  Assert.AreEqual(20, FList.Bookmarks[0].Line);
end;

procedure TAtlasQuickBookmarkTests.SeveralMarksSmallestNumberFirst;
var
  Marks: TArray<TAtlasBookmark>;
begin
  TAtlasQuickBookmarks.Toggle(FList, KundeFile, Text, 12, 0);
  TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 12, 7, 0);
  TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 12, 2, 0);
  // Ein benanntes ohne Nummer steht nicht in der Spalte.
  FList.Add(KundeFile, Text, 12, 'Benannt', 0);
  Marks := TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 12);
  Assert.AreEqual(3, Integer(Length(Marks)));
  Assert.AreEqual(2, Marks[0].Number);
  Assert.AreEqual(7, Marks[1].Number);
  Assert.AreEqual(0, Marks[2].Number, 'unnummerierte hinten');
  Assert.IsTrue(TAtlasQuickBookmarks.HasColumnMarks(FList, KundeFile));
  Assert.IsFalse(TAtlasQuickBookmarks.HasColumnMarks(FList, LagerFile));
end;

procedure TAtlasQuickBookmarkTests.ClickSetsAndRemoves;
begin
  Assert.AreEqual(Ord(TAtlasQuickChange.Added), Ord(TAtlasQuickBookmarks.Click(FList, KundeFile, Text, 23, 0)));
  Assert.AreEqual(1, Integer(Length(TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 23))));
  Assert.AreEqual(1, TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 23)[0].Number, 'kleinste freie Nummer');
  TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 23, 4, 0);
  // Klick auf den Marker: alle Marker der Zeile weg.
  Assert.AreEqual(Ord(TAtlasQuickChange.Removed), Ord(TAtlasQuickBookmarks.Click(FList, KundeFile, Text, 23, 0)));
  Assert.AreEqual(0, Integer(FList.Count));
  Assert.AreEqual(Ord(TAtlasQuickChange.None), Ord(TAtlasQuickBookmarks.Click(FList, KundeFile, Text, -1, 0)));
end;

procedure TAtlasQuickBookmarkTests.ClickTakesFreeNumberOrNone;
var
  Number: Integer;
begin
  TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 3, 1, 0);
  TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 4, 3, 0);
  Assert.AreEqual(2, TAtlasQuickBookmarks.FreeNumber(FList), 'Lücke zuerst');
  TAtlasQuickBookmarks.Click(FList, KundeFile, Text, 10, 0);
  Assert.AreEqual(2, TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 10)[0].Number);
  for Number := 1 to 9 do
    TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 20 + Number, Number, 0);
  Assert.AreEqual(0, TAtlasQuickBookmarks.FreeNumber(FList), 'alle belegt');
  TAtlasQuickBookmarks.Click(FList, KundeFile, Text, 40, 0);
  Assert.AreEqual(0, TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 40)[0].Number, 'dann ohne Nummer');
end;

procedure TAtlasQuickBookmarkTests.ClickOnNamedNumberKeepsNamedBookmark;
var
  Id: string;
begin
  Id := FList.Add(KundeFile, Text, 30, 'Prüfung', 0);
  Assert.AreEqual(Ord(TAtlasQuickChange.Added), Ord(TAtlasQuickBookmarks.AssignNumber(FList, Id, 1)));
  Assert.AreEqual(1, Integer(Length(TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 30))), 'nummeriert = Spalte');
  Assert.AreEqual(Ord(TAtlasQuickChange.Removed), Ord(TAtlasQuickBookmarks.Click(FList, KundeFile, Text, 30, 0)));
  Assert.AreEqual(1, Integer(FList.Count), 'das benannte Lesezeichen bleibt');
  Assert.AreEqual(0, FList.Bookmarks[0].Number);
  // Nummer erneut setzen und per Strg+Umschalt+1 an anderer Stelle umziehen: das benannte bleibt ohne Nummer.
  TAtlasQuickBookmarks.AssignNumber(FList, Id, 1);
  TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 40, 1, 0);
  Assert.AreEqual(2, Integer(FList.Count));
  Assert.AreEqual(0, FList.Bookmarks[FList.IndexOf(Id)].Number);
end;

procedure TAtlasQuickBookmarkTests.ToggleUnnumbered;
begin
  Assert.AreEqual(Ord(TAtlasQuickChange.Added), Ord(TAtlasQuickBookmarks.Toggle(FList, KundeFile, Text, 8, 0)));
  TAtlasQuickBookmarks.Toggle(FList, KundeFile, Text, 9, 0);
  TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 8, 6, 0);
  Assert.AreEqual(3, Integer(FList.Count), 'beliebig viele je Datei');
  // Entfernt nur das unnummerierte der Zeile; die 6 bleibt.
  Assert.AreEqual(Ord(TAtlasQuickChange.Removed), Ord(TAtlasQuickBookmarks.Toggle(FList, KundeFile, Text, 8, 0)));
  Assert.AreEqual(2, Integer(FList.Count));
  Assert.AreEqual(6, TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 8)[0].Number);
end;

procedure TAtlasQuickBookmarkTests.AssignNumberFromWindow;
var
  A, B: string;
begin
  A := TAtlasQuickBookmarks.AddQuick(FList, KundeFile, Text, 10, 0, 0);
  B := TAtlasQuickBookmarks.AddQuick(FList, KundeFile, Text, 11, 2, 0);
  Assert.AreEqual(Ord(TAtlasQuickChange.Moved), Ord(TAtlasQuickBookmarks.AssignNumber(FList, A, 2)));
  Assert.AreEqual(2, FList.Bookmarks[FList.IndexOf(A)].Number);
  Assert.AreEqual(0, FList.Bookmarks[FList.IndexOf(B)].Number, 'der bisherige Träger bleibt unnummeriert');
  Assert.AreEqual(Ord(TAtlasQuickChange.Removed), Ord(TAtlasQuickBookmarks.AssignNumber(FList, A, 2)));
  Assert.AreEqual(2, Integer(FList.Count));
  Assert.AreEqual(Ord(TAtlasQuickChange.None), Ord(TAtlasQuickBookmarks.AssignNumber(FList, 'gibt-es-nicht', 2)));
end;

procedure TAtlasQuickBookmarkTests.RemoveFileKeepsNamed;
begin
  TAtlasQuickBookmarks.Toggle(FList, KundeFile, Text, 8, 0);
  TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 9, 1, 0);
  TAtlasQuickBookmarks.Toggle(FList, LagerFile, Text, 8, 0);
  FList.Add(KundeFile, Text, 12, 'Benannt', 0);
  Assert.AreEqual(2, TAtlasQuickBookmarks.RemoveFile(FList, KundeFile));
  Assert.AreEqual(2, Integer(FList.Count));
  Assert.AreEqual(1, TAtlasQuickBookmarks.RemoveAt(FList, LagerFile, 8));
  Assert.AreEqual('Benannt', FList.Bookmarks[0].Name);
end;

procedure TAtlasQuickBookmarkTests.JumpProjectAndFileScope;
var
  Index: Integer;
begin
  TAtlasQuickBookmarks.SetNumber(FList, LagerFile, Text, 10, 3, 0);
  Assert.AreEqual(Ord(TAtlasQuickJump.Found),
    Ord(TAtlasQuickBookmarks.Jump(FList, 3, KundeFile, TAtlasQuickScope.Project, Index)));
  Assert.AreEqual(10, FList.Bookmarks[Index].Line);
  Assert.AreEqual(Ord(TAtlasQuickJump.OtherFile),
    Ord(TAtlasQuickBookmarks.Jump(FList, 3, KundeFile, TAtlasQuickScope.CurrentFile, Index)));
  Assert.AreEqual(Ord(TAtlasQuickJump.Found),
    Ord(TAtlasQuickBookmarks.Jump(FList, 3, LagerFile, TAtlasQuickScope.CurrentFile, Index)));
  Assert.AreEqual(Ord(TAtlasQuickJump.NotAssigned),
    Ord(TAtlasQuickBookmarks.Jump(FList, 4, LagerFile, TAtlasQuickScope.Project, Index)));
  Assert.AreEqual(-1, Index);
end;

procedure TAtlasQuickBookmarkTests.StepCyclesThroughFile;
var
  Target: Integer;
begin
  Assert.IsFalse(TAtlasQuickBookmarks.Step(FList, KundeFile, 5, True, Target));
  TAtlasQuickBookmarks.Toggle(FList, KundeFile, Text, 30, 0);
  TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 10, 1, 0);
  FList.Add(KundeFile, Text, 20, 'Benannt', 0);
  TAtlasQuickBookmarks.Toggle(FList, LagerFile, Text, 15, 0);
  Assert.IsTrue(TAtlasQuickBookmarks.Step(FList, KundeFile, 5, True, Target));
  Assert.AreEqual(10, Target);
  TAtlasQuickBookmarks.Step(FList, KundeFile, 10, True, Target);
  Assert.AreEqual(20, Target, 'auch benannte');
  TAtlasQuickBookmarks.Step(FList, KundeFile, 30, True, Target);
  Assert.AreEqual(10, Target, 'reihum');
  TAtlasQuickBookmarks.Step(FList, KundeFile, 10, False, Target);
  Assert.AreEqual(30, Target, 'rückwärts reihum');
  TAtlasQuickBookmarks.Step(FList, KundeFile, 25, False, Target);
  Assert.AreEqual(20, Target);
end;

procedure TAtlasQuickBookmarkTests.QuickBookmarksFollowInsertedLines;
var
  Code, Moved: TArray<string>;
  Index: Integer;
begin
  Code := Lines(60);
  TAtlasQuickBookmarks.SetNumber(FList, KundeFile, string.Join(#13#10, Code), 33, 3, 0);
  // 50 Zeilen über der Methode eingefügt: Der Marker wandert mit (Anker wie #622).
  Moved := Copy(Code, 0, 3);
  for Index := 1 to 50 do
    Moved := Moved + ['// Zeile ' + IntToStr(Index)];
  Moved := Moved + Copy(Code, 3, Length(Code) - 3);
  Assert.IsTrue(FList.Relocate(KundeFile, string.Join(#13#10, Moved)));
  Assert.AreEqual(83, FList.Bookmarks[0].Line);
  Assert.AreEqual(3, FList.Bookmarks[0].Number);
  Assert.IsFalse(FList.Bookmarks[0].Lost);
end;

procedure TAtlasQuickBookmarkTests.DisplayNameWithoutName;
var
  Index: Integer;
begin
  TAtlasQuickBookmarks.Toggle(FList, KundeFile, Text, 10, 0);
  TAtlasQuickBookmarks.Toggle(FList, KundeFile, Text, 0, 0);
  Assert.IsTrue(FList.Bookmarks[0].Unnamed);
  Assert.AreEqual('Laden', FList.Bookmarks[0].DisplayName, 'Methode statt Name');
  Assert.AreEqual('Kunde.pas:1', FList.Bookmarks[1].DisplayName, 'außerhalb einer Methode Datei und Zeile');
  Assert.AreEqual(1, Integer(Length(FList.Filter('laden'))), 'Filter findet den abgeleiteten Namen');
  // „Namen geben …“: wird ein benanntes Lesezeichen und behält die Nummer.
  Index := FList.IndexOf(FList.Bookmarks[0].Id);
  FList.Bookmarks[Index].Number := 4;
  Assert.IsTrue(FList.Rename(FList.Bookmarks[0].Id, 'Ladeschleife'));
  Assert.AreEqual(Ord(TAtlasBookmarkKind.Named), Ord(FList.Bookmarks[0].Kind));
  Assert.AreEqual(4, FList.Bookmarks[0].Number);
  Assert.AreEqual('Ladeschleife', FList.Bookmarks[0].DisplayName);
end;

procedure TAtlasQuickBookmarkTests.FormatOneLoadsAndSavesAsTwo;
const
  Json = '{"format": 1, "project": "Demo.dproj", "bookmarks": [' +
    '{"id": "a", "name": "Rundung", "file": "Source/Kunde.pas", "line": 3, "lineText": "x"},' +
    '{"id": "b", "file": "Source/Kunde.pas", "line": 4}]}';
var
  List: TAtlasBookmarkList;
  Root: TJSONObject;
begin
  Assert.IsTrue(TAtlasBookmarks.Parse(Json, 'C:\Projekte\', List));
  Assert.AreEqual(2, Integer(List.Count), 'ohne Verlust');
  Assert.AreEqual(Ord(TAtlasBookmarkKind.Named), Ord(List.Bookmarks[0].Kind));
  Assert.AreEqual(0, List.Bookmarks[0].Number);
  Assert.AreEqual('Kunde.pas:4', List.Bookmarks[1].Name, 'benannte ohne Namen wie bisher');
  Root := TJSONObject.ParseJSONValue(TAtlasBookmarks.ToJson(List, 'C:\Projekte\')) as TJSONObject;
  try
    Assert.AreEqual(2, TJSONNumber(Root.GetValue('format')).AsInt);
    Assert.AreEqual('named',
      TJSONObject(TJSONArray(Root.GetValue('bookmarks')).Items[0]).GetValue('kind').Value);
  finally
    Root.Free;
  end;
end;

procedure TAtlasQuickBookmarkTests.KindAndNumberRoundTrip;
var
  Back: TAtlasBookmarkList;
  Root, Mark: TJSONObject;
  Json: string;
begin
  TAtlasQuickBookmarks.SetNumber(FList, KundeFile, Text, 33, 3, 0);
  TAtlasQuickBookmarks.Toggle(FList, KundeFile, Text, 40, 0);
  Json := TAtlasBookmarks.ToJson(FList, 'C:\Projekte\');
  Root := TJSONObject.ParseJSONValue(Json) as TJSONObject;
  try
    Mark := TJSONObject(TJSONArray(Root.GetValue('bookmarks')).Items[0]);
    Assert.AreEqual('quick', Mark.GetValue('kind').Value);
    Assert.AreEqual(3, TJSONNumber(Mark.GetValue('number')).AsInt);
    Assert.IsNull(Mark.GetValue('name'), 'ohne Namen kein Feld');
    Mark := TJSONObject(TJSONArray(Root.GetValue('bookmarks')).Items[1]);
    Assert.IsNull(Mark.GetValue('number'), 'unnummeriert ohne Feld');
  finally
    Root.Free;
  end;
  Assert.IsTrue(TAtlasBookmarks.Parse(Json, 'C:\Projekte\', Back));
  Assert.AreEqual(Ord(TAtlasBookmarkKind.Quick), Ord(Back.Bookmarks[0].Kind));
  Assert.AreEqual(3, Back.Bookmarks[0].Number);
  Assert.AreEqual('', Back.Bookmarks[0].Name);
  Assert.AreEqual(0, Back.Bookmarks[1].Number);
  // Unsinnige Nummern fallen weg.
  Assert.IsTrue(TAtlasBookmarks.Parse('{"format": 2, "bookmarks": [{"id": "x", "kind": "quick", "number": 12, ' +
    '"file": "Source/Kunde.pas", "line": 1}]}', 'C:\Projekte\', Back));
  Assert.AreEqual(0, Back.Bookmarks[0].Number);
end;

procedure TAtlasQuickBookmarkTests.ImportTakesIdeBookmarks;
var
  Imported: TArray<Integer>;
begin
  TAtlasQuickBookmarks.SetNumber(FList, LagerFile, Text, 5, 2, 0);
  Imported := TAtlasQuickBookmarks.Import(FList, KundeFile, Text,
    [TAtlasIdeBookmarkPos.Create(0, 3), TAtlasIdeBookmarkPos.Create(1, 12), TAtlasIdeBookmarkPos.Create(2, 14),
    TAtlasIdeBookmarkPos.Create(9, -1)], 0);
  Assert.AreEqual(2, Integer(Length(Imported)), '0 bleibt bei der IDE, ohne Zeile nichts');
  Assert.AreEqual(1, Imported[0]);
  Assert.AreEqual(2, Imported[1]);
  Assert.AreEqual(1, TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 12)[0].Number);
  Assert.AreEqual(0, TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 14)[0].Number,
    'Nummer bei Atlas schon vergeben: unnummeriert');
  Assert.IsTrue(TAtlasBookmarks.SameFile(LagerFile, FList.Bookmarks[FList.IndexOfNumber(2)].FileName));
  Assert.AreEqual(0, Integer(Length(TAtlasQuickBookmarks.ColumnMarks(FList, KundeFile, 3))));
end;

procedure TAtlasQuickBookmarkTests.ChordDecision;
begin
  // Faltungsbuchstabe innerhalb der Wartezeit: an die IDE.
  Assert.AreEqual(Ord(TAtlasChordAction.PassOn), Ord(TAtlasQuickBookmarks.Chord(800, 300, Ord('U'))));
  Assert.AreEqual(Ord(TAtlasChordAction.PassOn), Ord(TAtlasQuickBookmarks.Chord(800, 300, Ord('A'))));
  // Noch keine Taste bzw. nur Umschalttasten: weiter warten.
  Assert.AreEqual(Ord(TAtlasChordAction.Wait), Ord(TAtlasQuickBookmarks.Chord(800, 300, 0)));
  Assert.AreEqual(Ord(TAtlasChordAction.Wait), Ord(TAtlasQuickBookmarks.Chord(800, 300, $11)));
  // Zeitüberschreitung: Lesezeichen, auch wenn danach ein Faltungsbuchstabe kommt.
  Assert.AreEqual(Ord(TAtlasChordAction.Toggle), Ord(TAtlasQuickBookmarks.Chord(800, 800, 0)));
  Assert.AreEqual(Ord(TAtlasChordAction.Toggle), Ord(TAtlasQuickBookmarks.Chord(800, 900, Ord('U'))));
  // Andere Taste: Lesezeichen.
  Assert.AreEqual(Ord(TAtlasChordAction.Toggle), Ord(TAtlasQuickBookmarks.Chord(800, 100, Ord('X'))));
  Assert.AreEqual(Ord(TAtlasChordAction.Toggle), Ord(TAtlasQuickBookmarks.Chord(800, 100, $28)));
  // Wartezeit 0: sofort.
  Assert.AreEqual(Ord(TAtlasChordAction.Toggle), Ord(TAtlasQuickBookmarks.Chord(0, 0, Ord('U'))));
end;

procedure TAtlasQuickBookmarkTests.KeysForNumbers;
const
  CtrlShift1 = $6000 or Ord('1');
  Ctrl1 = $4000 or Ord('1');
begin
  Assert.AreEqual(Integer($6000 or Ord('7')), Integer(TAtlasQuickBookmarks.KeyFor(CtrlShift1, 7)));
  Assert.AreEqual(Integer($4000 or Ord('9')), Integer(TAtlasQuickBookmarks.KeyFor(Ctrl1, 9)));
  Assert.AreEqual(0, Integer(TAtlasQuickBookmarks.KeyFor(0, 3)), 'ohne Grundtaste keine Tasten');
  Assert.AreEqual(0, Integer(TAtlasQuickBookmarks.KeyFor(Ctrl1, 0)));
  Assert.AreEqual(4, TAtlasQuickBookmarks.NumberOfKey($6000 or Ord('4'), CtrlShift1));
  Assert.AreEqual(0, TAtlasQuickBookmarks.NumberOfKey($4000 or Ord('4'), CtrlShift1), 'andere Umschalttasten');
  Assert.AreEqual(0, TAtlasQuickBookmarks.NumberOfKey($6000 or Ord('0'), CtrlShift1), '0 bleibt bei der IDE');
end;

procedure TAtlasQuickBookmarkTests.ColumnWidthFollowsLineHeight;
begin
  Assert.AreEqual(16, TAtlasQuickBookmarks.ColumnWidth(20));
  Assert.AreEqual(TAtlasQuickBookmarks.MinColumnWidth, TAtlasQuickBookmarks.ColumnWidth(0), 'Mindestbreite');
  Assert.AreEqual(TAtlasQuickBookmarks.MinColumnWidth, TAtlasQuickBookmarks.ColumnWidth(8));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickBookmarkTests);

end.
