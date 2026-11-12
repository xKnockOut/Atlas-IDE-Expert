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
  [Category('Atlas.IDE.Bookmarks')]
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
    [Test]
    procedure RowGuessAboveAndBelow;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Bookmarks.Quick,
  Atlas.Core.Marks.Ids;

const
  cKundeFile = 'C:\Projekte\Source\Kunde.pas';
  cLagerFile = 'C:\Projekte\Source\Lager.pas';
  cProject = 'C:\Projekte\Demo.dproj';

/// <summary>Unit mit 60 Zeilen: Zeile i (0-basiert) heißt „  Schritt{i};“, dazwischen eine Methode.</summary>
function Lines(ACount: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := ['unit Kunde;', '', 'implementation', '', 'procedure Laden;', 'begin'];
  for mIndex := Length(Result) to ACount - 3 do
  begin
    Result := Result + ['  Schritt' + IntToStr(mIndex) + ';'];
  end;
  Result := Result + ['end;', 'end.'];
end;

function Text: string;
begin
  Result := string.Join(#13#10, Lines(60));
end;

{ TAtlasQuickBookmarkTests }

procedure TAtlasQuickBookmarkTests.Setup;
begin
  FList := TAtlasBookmarkList.Create(cProject);
end;

procedure TAtlasQuickBookmarkTests.TearDown;
begin
  FList := Default(TAtlasBookmarkList);
end;

procedure TAtlasQuickBookmarkTests.NumberSetMovesAndRemoves;
var
  mMarks: TArray<TAtlasBookmark>;
begin
  Assert.AreEqual(Ord(TAtlasQuickChange.Added), Ord(TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 32, 3, 0)));
  mMarks := TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 32);
  Assert.AreEqual(1, Integer(Length(mMarks)));
  Assert.AreEqual(3, mMarks[0].Number);
  Assert.AreEqual(Ord(TAtlasBookmarkKind.Quick), Ord(mMarks[0].Kind));
  Assert.AreEqual('', mMarks[0].Name, 'schnelle Lesezeichen ohne Namen');
  // Strg+Umschalt+3 in Zeile 40: die 3 zieht um.
  Assert.AreEqual(Ord(TAtlasQuickChange.Moved), Ord(TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 39, 3, 0)));
  Assert.AreEqual(0, Integer(Length(TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 32))));
  Assert.AreEqual(3, TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 39)[0].Number);
  Assert.AreEqual(1, Integer(FList.Count), 'jede Nummer höchstens einmal');
  // Nochmals in Zeile 40: entfernt.
  Assert.AreEqual(Ord(TAtlasQuickChange.Removed),
    Ord(TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 39, 3, 0)));
  Assert.AreEqual(0, Integer(FList.Count));
  Assert.AreEqual(Ord(TAtlasQuickChange.None), Ord(TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 39, 0, 0)));
  Assert.AreEqual(Ord(TAtlasQuickChange.None), Ord(TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 39, 10, 0)));
end;

procedure TAtlasQuickBookmarkTests.NumberMovesAcrossFiles;
begin
  TAtlasQuickBookmarks.SetNumber(FList, cLagerFile, Text, 10, 5, 0);
  Assert.AreEqual(Ord(TAtlasQuickChange.Moved), Ord(TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 20, 5, 0)));
  Assert.AreEqual(1, Integer(FList.Count));
  Assert.IsTrue(TAtlasMarkIds.SameFile(cKundeFile, FList.Bookmarks[0].FileName));
  Assert.AreEqual(20, FList.Bookmarks[0].Line);
end;

procedure TAtlasQuickBookmarkTests.SeveralMarksSmallestNumberFirst;
var
  mMarks: TArray<TAtlasBookmark>;
begin
  TAtlasQuickBookmarks.Toggle(FList, cKundeFile, Text, 12, 0);
  TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 12, 7, 0);
  TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 12, 2, 0);
  // Ein benanntes ohne Nummer steht nicht in der Spalte.
  FList.Add(cKundeFile, Text, 12, 'Benannt', 0);
  mMarks := TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 12);
  Assert.AreEqual(3, Integer(Length(mMarks)));
  Assert.AreEqual(2, mMarks[0].Number);
  Assert.AreEqual(7, mMarks[1].Number);
  Assert.AreEqual(0, mMarks[2].Number, 'unnummerierte hinten');
  Assert.IsTrue(TAtlasQuickBookmarks.HasColumnMarks(FList, cKundeFile));
  Assert.IsFalse(TAtlasQuickBookmarks.HasColumnMarks(FList, cLagerFile));
end;

procedure TAtlasQuickBookmarkTests.ClickSetsAndRemoves;
begin
  Assert.AreEqual(Ord(TAtlasQuickChange.Added), Ord(TAtlasQuickBookmarks.Click(FList, cKundeFile, Text, 23, 0)));
  Assert.AreEqual(1, Integer(Length(TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 23))));
  Assert.AreEqual(1, TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 23)[0].Number, 'kleinste freie Nummer');
  TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 23, 4, 0);
  // Klick auf den Marker: alle Marker der Zeile weg.
  Assert.AreEqual(Ord(TAtlasQuickChange.Removed), Ord(TAtlasQuickBookmarks.Click(FList, cKundeFile, Text, 23, 0)));
  Assert.AreEqual(0, Integer(FList.Count));
  Assert.AreEqual(Ord(TAtlasQuickChange.None), Ord(TAtlasQuickBookmarks.Click(FList, cKundeFile, Text, -1, 0)));
end;

procedure TAtlasQuickBookmarkTests.ClickTakesFreeNumberOrNone;
var
  mNumber: Integer;
begin
  TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 3, 1, 0);
  TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 4, 3, 0);
  Assert.AreEqual(2, TAtlasQuickBookmarks.FreeNumber(FList), 'Lücke zuerst');
  TAtlasQuickBookmarks.Click(FList, cKundeFile, Text, 10, 0);
  Assert.AreEqual(2, TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 10)[0].Number);
  for mNumber := 1 to 9 do
  begin
    TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 20 + mNumber, mNumber, 0);
  end;
  Assert.AreEqual(0, TAtlasQuickBookmarks.FreeNumber(FList), 'alle belegt');
  TAtlasQuickBookmarks.Click(FList, cKundeFile, Text, 40, 0);
  Assert.AreEqual(0, TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 40)[0].Number, 'dann ohne Nummer');
end;

procedure TAtlasQuickBookmarkTests.ClickOnNamedNumberKeepsNamedBookmark;
var
  mId: string;
begin
  mId := FList.Add(cKundeFile, Text, 30, 'Prüfung', 0);
  Assert.AreEqual(Ord(TAtlasQuickChange.Added), Ord(TAtlasQuickBookmarks.AssignNumber(FList, mId, 1)));
  Assert.AreEqual(1, Integer(Length(TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 30))), 'nummeriert = Spalte');
  Assert.AreEqual(Ord(TAtlasQuickChange.Removed), Ord(TAtlasQuickBookmarks.Click(FList, cKundeFile, Text, 30, 0)));
  Assert.AreEqual(1, Integer(FList.Count), 'das benannte Lesezeichen bleibt');
  Assert.AreEqual(0, FList.Bookmarks[0].Number);
  // Nummer erneut setzen und per Strg+Umschalt+1 an anderer Stelle umziehen: das benannte bleibt ohne Nummer.
  TAtlasQuickBookmarks.AssignNumber(FList, mId, 1);
  TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 40, 1, 0);
  Assert.AreEqual(2, Integer(FList.Count));
  Assert.AreEqual(0, FList.Bookmarks[FList.IndexOf(mId)].Number);
end;

procedure TAtlasQuickBookmarkTests.ToggleUnnumbered;
begin
  Assert.AreEqual(Ord(TAtlasQuickChange.Added), Ord(TAtlasQuickBookmarks.Toggle(FList, cKundeFile, Text, 8, 0)));
  TAtlasQuickBookmarks.Toggle(FList, cKundeFile, Text, 9, 0);
  TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 8, 6, 0);
  Assert.AreEqual(3, Integer(FList.Count), 'beliebig viele je Datei');
  // Entfernt nur das unnummerierte der Zeile; die 6 bleibt.
  Assert.AreEqual(Ord(TAtlasQuickChange.Removed), Ord(TAtlasQuickBookmarks.Toggle(FList, cKundeFile, Text, 8, 0)));
  Assert.AreEqual(2, Integer(FList.Count));
  Assert.AreEqual(6, TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 8)[0].Number);
end;

procedure TAtlasQuickBookmarkTests.AssignNumberFromWindow;
var
  A, B: string;
begin
  A := TAtlasQuickBookmarks.AddQuick(FList, cKundeFile, Text, 10, 0, 0);
  B := TAtlasQuickBookmarks.AddQuick(FList, cKundeFile, Text, 11, 2, 0);
  Assert.AreEqual(Ord(TAtlasQuickChange.Moved), Ord(TAtlasQuickBookmarks.AssignNumber(FList, A, 2)));
  Assert.AreEqual(2, FList.Bookmarks[FList.IndexOf(A)].Number);
  Assert.AreEqual(0, FList.Bookmarks[FList.IndexOf(B)].Number, 'der bisherige Träger bleibt unnummeriert');
  Assert.AreEqual(Ord(TAtlasQuickChange.Removed), Ord(TAtlasQuickBookmarks.AssignNumber(FList, A, 2)));
  Assert.AreEqual(2, Integer(FList.Count));
  Assert.AreEqual(Ord(TAtlasQuickChange.None), Ord(TAtlasQuickBookmarks.AssignNumber(FList, 'gibt-es-nicht', 2)));
end;

procedure TAtlasQuickBookmarkTests.RemoveFileKeepsNamed;
begin
  TAtlasQuickBookmarks.Toggle(FList, cKundeFile, Text, 8, 0);
  TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 9, 1, 0);
  TAtlasQuickBookmarks.Toggle(FList, cLagerFile, Text, 8, 0);
  FList.Add(cKundeFile, Text, 12, 'Benannt', 0);
  Assert.AreEqual(2, TAtlasQuickBookmarks.RemoveFile(FList, cKundeFile));
  Assert.AreEqual(2, Integer(FList.Count));
  Assert.AreEqual(1, TAtlasQuickBookmarks.RemoveAt(FList, cLagerFile, 8));
  Assert.AreEqual('Benannt', FList.Bookmarks[0].Name);
end;

procedure TAtlasQuickBookmarkTests.JumpProjectAndFileScope;
var
  mIndex: Integer;
begin
  TAtlasQuickBookmarks.SetNumber(FList, cLagerFile, Text, 10, 3, 0);
  Assert.AreEqual(Ord(TAtlasQuickJump.Found),
    Ord(TAtlasQuickBookmarks.Jump(FList, 3, cKundeFile, TAtlasQuickScope.Project, mIndex)));
  Assert.AreEqual(10, FList.Bookmarks[mIndex].Line);
  Assert.AreEqual(Ord(TAtlasQuickJump.OtherFile),
    Ord(TAtlasQuickBookmarks.Jump(FList, 3, cKundeFile, TAtlasQuickScope.CurrentFile, mIndex)));
  Assert.AreEqual(Ord(TAtlasQuickJump.Found),
    Ord(TAtlasQuickBookmarks.Jump(FList, 3, cLagerFile, TAtlasQuickScope.CurrentFile, mIndex)));
  Assert.AreEqual(Ord(TAtlasQuickJump.NotAssigned),
    Ord(TAtlasQuickBookmarks.Jump(FList, 4, cLagerFile, TAtlasQuickScope.Project, mIndex)));
  Assert.AreEqual(-1, mIndex);
end;

procedure TAtlasQuickBookmarkTests.StepCyclesThroughFile;
var
  mTarget: Integer;
begin
  Assert.IsFalse(TAtlasQuickBookmarks.Step(FList, cKundeFile, 5, True, mTarget));
  TAtlasQuickBookmarks.Toggle(FList, cKundeFile, Text, 30, 0);
  TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 10, 1, 0);
  FList.Add(cKundeFile, Text, 20, 'Benannt', 0);
  TAtlasQuickBookmarks.Toggle(FList, cLagerFile, Text, 15, 0);
  Assert.IsTrue(TAtlasQuickBookmarks.Step(FList, cKundeFile, 5, True, mTarget));
  Assert.AreEqual(10, mTarget);
  TAtlasQuickBookmarks.Step(FList, cKundeFile, 10, True, mTarget);
  Assert.AreEqual(20, mTarget, 'auch benannte');
  TAtlasQuickBookmarks.Step(FList, cKundeFile, 30, True, mTarget);
  Assert.AreEqual(10, mTarget, 'reihum');
  TAtlasQuickBookmarks.Step(FList, cKundeFile, 10, False, mTarget);
  Assert.AreEqual(30, mTarget, 'rückwärts reihum');
  TAtlasQuickBookmarks.Step(FList, cKundeFile, 25, False, mTarget);
  Assert.AreEqual(20, mTarget);
end;

procedure TAtlasQuickBookmarkTests.QuickBookmarksFollowInsertedLines;
var
  mCode, mMoved: TArray<string>;
  mIndex: Integer;
begin
  mCode := Lines(60);
  TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, string.Join(#13#10, mCode), 33, 3, 0);
  // 50 Zeilen über der Methode eingefügt: Der Marker wandert mit (Anker wie #622).
  mMoved := Copy(mCode, 0, 3);
  for mIndex := 1 to 50 do
  begin
    mMoved := mMoved + ['// Zeile ' + IntToStr(mIndex)];
  end;
  mMoved := mMoved + Copy(mCode, 3, Length(mCode) - 3);
  Assert.IsTrue(FList.Relocate(cKundeFile, string.Join(#13#10, mMoved)));
  Assert.AreEqual(83, FList.Bookmarks[0].Line);
  Assert.AreEqual(3, FList.Bookmarks[0].Number);
  Assert.IsFalse(FList.Bookmarks[0].Lost);
end;

procedure TAtlasQuickBookmarkTests.DisplayNameWithoutName;
var
  mIndex: Integer;
begin
  TAtlasQuickBookmarks.Toggle(FList, cKundeFile, Text, 10, 0);
  TAtlasQuickBookmarks.Toggle(FList, cKundeFile, Text, 0, 0);
  Assert.IsTrue(FList.Bookmarks[0].Unnamed);
  Assert.AreEqual('Laden', FList.Bookmarks[0].DisplayName, 'Methode statt Name');
  Assert.AreEqual('Kunde.pas:1', FList.Bookmarks[1].DisplayName, 'außerhalb einer Methode Datei und Zeile');
  Assert.AreEqual(1, Integer(Length(FList.Filter('laden'))), 'Filter findet den abgeleiteten Namen');
  // „Namen geben …“: wird ein benanntes Lesezeichen und behält die Nummer.
  mIndex := FList.IndexOf(FList.Bookmarks[0].Id);
  FList.Bookmarks[mIndex].Number := 4;
  Assert.IsTrue(FList.Rename(FList.Bookmarks[0].Id, 'Ladeschleife'));
  Assert.AreEqual(Ord(TAtlasBookmarkKind.Named), Ord(FList.Bookmarks[0].Kind));
  Assert.AreEqual(4, FList.Bookmarks[0].Number);
  Assert.AreEqual('Ladeschleife', FList.Bookmarks[0].DisplayName);
end;

procedure TAtlasQuickBookmarkTests.FormatOneLoadsAndSavesAsTwo;
const
  cJson = '{"format": 1, "project": "Demo.dproj", "bookmarks": [' +
    '{"id": "a", "name": "Rundung", "file": "Source/Kunde.pas", "line": 3, "lineText": "x"},' +
    '{"id": "b", "file": "Source/Kunde.pas", "line": 4}]}';
var
  mList: TAtlasBookmarkList;
  mRoot: TJSONObject;
begin
  Assert.IsTrue(TAtlasBookmarks.Parse(cJson, 'C:\Projekte\', mList));
  Assert.AreEqual(2, Integer(mList.Count), 'ohne Verlust');
  Assert.AreEqual(Ord(TAtlasBookmarkKind.Named), Ord(mList.Bookmarks[0].Kind));
  Assert.AreEqual(0, mList.Bookmarks[0].Number);
  Assert.AreEqual('Kunde.pas:4', mList.Bookmarks[1].Name, 'benannte ohne Namen wie bisher');
  mRoot := TJSONObject.ParseJSONValue(TAtlasBookmarks.ToJson(mList, 'C:\Projekte\')) as TJSONObject;
  try
    Assert.AreEqual(2, TJSONNumber(mRoot.GetValue('format')).AsInt);
    Assert.AreEqual('named',
      TJSONObject(TJSONArray(mRoot.GetValue('bookmarks')).Items[0]).GetValue('kind').Value);
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasQuickBookmarkTests.KindAndNumberRoundTrip;
var
  mBack: TAtlasBookmarkList;
  mRoot, mMark: TJSONObject;
  mJson: string;
begin
  TAtlasQuickBookmarks.SetNumber(FList, cKundeFile, Text, 33, 3, 0);
  TAtlasQuickBookmarks.Toggle(FList, cKundeFile, Text, 40, 0);
  mJson := TAtlasBookmarks.ToJson(FList, 'C:\Projekte\');
  mRoot := TJSONObject.ParseJSONValue(mJson) as TJSONObject;
  try
    mMark := TJSONObject(TJSONArray(mRoot.GetValue('bookmarks')).Items[0]);
    Assert.AreEqual('quick', mMark.GetValue('kind').Value);
    Assert.AreEqual(3, TJSONNumber(mMark.GetValue('number')).AsInt);
    Assert.IsNull(mMark.GetValue('name'), 'ohne Namen kein Feld');
    mMark := TJSONObject(TJSONArray(mRoot.GetValue('bookmarks')).Items[1]);
    Assert.IsNull(mMark.GetValue('number'), 'unnummeriert ohne Feld');
  finally
    mRoot.Free;
  end;
  Assert.IsTrue(TAtlasBookmarks.Parse(mJson, 'C:\Projekte\', mBack));
  Assert.AreEqual(Ord(TAtlasBookmarkKind.Quick), Ord(mBack.Bookmarks[0].Kind));
  Assert.AreEqual(3, mBack.Bookmarks[0].Number);
  Assert.AreEqual('', mBack.Bookmarks[0].Name);
  Assert.AreEqual(0, mBack.Bookmarks[1].Number);
  // Unsinnige Nummern fallen weg.
  Assert.IsTrue(TAtlasBookmarks.Parse('{"format": 2, "bookmarks": [{"id": "x", "kind": "quick", "number": 12, ' +
    '"file": "Source/Kunde.pas", "line": 1}]}', 'C:\Projekte\', mBack));
  Assert.AreEqual(0, mBack.Bookmarks[0].Number);
end;

procedure TAtlasQuickBookmarkTests.ImportTakesIdeBookmarks;
var
  mImported: TArray<Integer>;
begin
  TAtlasQuickBookmarks.SetNumber(FList, cLagerFile, Text, 5, 2, 0);
  mImported := TAtlasQuickBookmarks.Import(FList, cKundeFile, Text,
    [TAtlasIdeBookmarkPos.Create(0, 3), TAtlasIdeBookmarkPos.Create(1, 12), TAtlasIdeBookmarkPos.Create(2, 14),
    TAtlasIdeBookmarkPos.Create(9, -1)], 0);
  Assert.AreEqual(2, Integer(Length(mImported)), '0 bleibt bei der IDE, ohne Zeile nichts');
  Assert.AreEqual(1, mImported[0]);
  Assert.AreEqual(2, mImported[1]);
  Assert.AreEqual(1, TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 12)[0].Number);
  Assert.AreEqual(0, TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 14)[0].Number,
    'Nummer bei Atlas schon vergeben: unnummeriert');
  Assert.IsTrue(TAtlasMarkIds.SameFile(cLagerFile, FList.Bookmarks[FList.IndexOfNumber(2)].FileName));
  Assert.AreEqual(0, Integer(Length(TAtlasQuickBookmarks.ColumnMarks(FList, cKundeFile, 3))));
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
  cCtrlShift1 = $6000 or Ord('1');
  cCtrl1 = $4000 or Ord('1');
begin
  Assert.AreEqual(Integer($6000 or Ord('7')), Integer(TAtlasQuickBookmarks.KeyFor(cCtrlShift1, 7)));
  Assert.AreEqual(Integer($4000 or Ord('9')), Integer(TAtlasQuickBookmarks.KeyFor(cCtrl1, 9)));
  Assert.AreEqual(0, Integer(TAtlasQuickBookmarks.KeyFor(0, 3)), 'ohne Grundtaste keine Tasten');
  Assert.AreEqual(0, Integer(TAtlasQuickBookmarks.KeyFor(cCtrl1, 0)));
  Assert.AreEqual(4, TAtlasQuickBookmarks.NumberOfKey($6000 or Ord('4'), cCtrlShift1));
  Assert.AreEqual(0, TAtlasQuickBookmarks.NumberOfKey($4000 or Ord('4'), cCtrlShift1), 'andere Umschalttasten');
  Assert.AreEqual(0, TAtlasQuickBookmarks.NumberOfKey($6000 or Ord('0'), cCtrlShift1), '0 bleibt bei der IDE');
end;

procedure TAtlasQuickBookmarkTests.ColumnWidthFollowsLineHeight;
begin
  Assert.AreEqual(16, TAtlasQuickBookmarks.ColumnWidth(20));
  Assert.AreEqual(TAtlasQuickBookmarks.cMinColumnWidth, TAtlasQuickBookmarks.ColumnWidth(0), 'Mindestbreite');
  Assert.AreEqual(TAtlasQuickBookmarks.cMinColumnWidth, TAtlasQuickBookmarks.ColumnWidth(8));
end;

procedure TAtlasQuickBookmarkTests.RowGuessAboveAndBelow;
begin
  // Bekannt: Editorzeile 10 mit Oberkante 180, Höhe 18.
  Assert.AreEqual(10, TAtlasQuickBookmarks.RowGuess(10, 180, 18, 180), 'Oberkante');
  Assert.AreEqual(10, TAtlasQuickBookmarks.RowGuess(10, 180, 18, 197), 'Unterkante');
  Assert.AreEqual(11, TAtlasQuickBookmarks.RowGuess(10, 180, 18, 198), 'nächste Zeile');
  Assert.AreEqual(9, TAtlasQuickBookmarks.RowGuess(10, 180, 18, 179), 'knapp darüber');
  Assert.AreEqual(9, TAtlasQuickBookmarks.RowGuess(10, 180, 18, 162), 'Oberkante darüber');
  Assert.AreEqual(8, TAtlasQuickBookmarks.RowGuess(10, 180, 18, 161), 'zwei darüber');
  Assert.AreEqual(1, TAtlasQuickBookmarks.RowGuess(10, 180, 18, 18), 'oben im Editor');
  Assert.AreEqual(10, TAtlasQuickBookmarks.RowGuess(10, 180, 0, 500), 'ohne Höhe');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickBookmarkTests);

end.
