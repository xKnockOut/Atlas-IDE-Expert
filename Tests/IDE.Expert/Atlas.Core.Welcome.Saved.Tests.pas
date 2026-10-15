unit Atlas.Core.Welcome.Saved.Tests;

// Tests des Reiters „Gemerkt“ ohne VCL (#755): Notizen (#545), Lesezeichen
// (#622) und Favoriten (#458) aus zwei Projekten in einer Liste mit Art, Text,
// Datei und Zeile sowie Projekt; Filter; Sprungziel eines Favoriten
// (Deklaration in der Unit, Unit aus dem Index-Cache) und die Projekte einer
// Projektgruppe für die Lesezeichen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWelcomeSavedTests = class
  public
    [Test]
    procedure CollectsNotesBookmarksAndFavoritesOfTwoProjects;
    [Test]
    procedure BookmarksOfSameFolderCountOnce;
    [Test]
    procedure FilterNeedsEveryWord;
    [Test]
    procedure DeclarationLineOfMethodPropertyAndRoutine;
    [Test]
    procedure FindUnitIgnoresCase;
    [Test]
    procedure GroupProjectsResolveRelativePaths;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Notes.Store,
  Atlas.Core.Bookmarks.Store,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Welcome.IndexFiles,
  Atlas.Core.Welcome.Saved;

function Note(const AId, AFileName, AText: string; ALine: Integer): TAtlasNote;
begin
  Result := Default(TAtlasNote);
  Result.Id := AId;
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.Anchor.Line := ALine;
end;

function Mark(const AId, AName, AFileName, AMethod: string; ALine: Integer): TAtlasBookmark;
begin
  Result := Default(TAtlasBookmark);
  Result.Id := AId;
  Result.Name := AName;
  Result.FileName := AFileName;
  Result.Method := AMethod;
  Result.Anchor.Line := ALine;
end;

function Favorite(const ATypeName, AMember, AUnitName: string): TAtlasFavorite;
begin
  Result := Default(TAtlasFavorite);
  Result.TypeName := ATypeName;
  Result.Member := AMember;
  Result.UnitName := AUnitName;
  Result.Signature := 'procedure ' + AMember;
end;

{ TAtlasWelcomeSavedTests }

procedure TAtlasWelcomeSavedTests.CollectsNotesBookmarksAndFavoritesOfTwoProjects;
var
  Books: TArray<TAtlasNoteBook>;
  Lists: TArray<TAtlasBookmarkList>;
  Items: TAtlasSavedItems;
  Book: TAtlasNoteBook;
  List: TAtlasBookmarkList;
begin
  Book := TAtlasNoteBook.Create('C:\Zeta\Zeta.dproj');
  Book.Notes := [Note('n2', 'C:\Zeta\Haupt.pas', 'Aufräumen', 4)];
  Books := [Book];
  Book := TAtlasNoteBook.Create('C:\Atlas\Atlas.dproj');
  Book.Notes := [Note('n1', 'C:\Atlas\Kunde.pas', 'Prüfen, ob leer'#10'mit Eva klären', 41)];
  Book.Notes[0].Orphaned := True;
  Books := Books + [Book];
  List := TAtlasBookmarkList.Create('C:\Atlas\Atlas.dproj');
  List.Bookmarks := [Mark('b2', 'Speichern', 'C:\Atlas\Kunde.pas', 'TKunde.Speichern', 80),
    Mark('b1', 'Einstieg', 'C:\Atlas\Atlas.dpr', '', 9)];
  Lists := [List];
  List := TAtlasBookmarkList.Create('C:\Zeta\Zeta.dproj');
  List.Bookmarks := [Mark('b3', 'Start', 'C:\Zeta\Haupt.pas', 'Start', 2)];
  Lists := Lists + [List];
  Items := TAtlasWelcomeSaved.Collect(Books, Lists, [Favorite('TDataSet', 'Open', 'Data.DB'),
    Favorite('', 'Format', 'System.SysUtils')]);
  Assert.AreEqual(7, Integer(Length(Items)));
  // Atlas vor Zeta; je Projekt erst Notizen, dann Lesezeichen nach Datei und Zeile; Favoriten am Ende.
  Assert.IsTrue(Items[0].Kind = TAtlasSavedKind.Note);
  Assert.AreEqual('Atlas', Items[0].ProjectName);
  Assert.AreEqual('Prüfen, ob leer …', Items[0].Text, 'Titel der Notiz');
  Assert.AreEqual('Kunde.pas:42', Items[0].Place, 'Zeile ab 1');
  Assert.AreEqual(41, Items[0].Line, '0-basiert für den Sprung');
  Assert.IsTrue(Items[0].Lost, 'verwaist');
  Assert.Contains(Items[0].Detail, 'Eva');
  Assert.IsTrue(Items[1].Kind = TAtlasSavedKind.Bookmark);
  Assert.AreEqual('Einstieg', Items[1].Text);
  Assert.AreEqual('Atlas.dpr:10', Items[1].Place);
  Assert.IsTrue(Items[2].Kind = TAtlasSavedKind.Bookmark);
  Assert.AreEqual('Speichern', Items[2].Text);
  Assert.AreEqual('TKunde.Speichern', Items[2].Detail);
  Assert.AreEqual('b2', Items[2].Id);
  Assert.AreEqual('C:\Atlas\Atlas.dproj', Items[2].Project);
  Assert.IsTrue(Items[3].Kind = TAtlasSavedKind.Note);
  Assert.AreEqual('Zeta', Items[3].ProjectName);
  Assert.IsTrue(Items[4].Kind = TAtlasSavedKind.Bookmark);
  Assert.AreEqual('Zeta', Items[4].ProjectName);
  Assert.IsTrue(Items[5].Kind = TAtlasSavedKind.Favorite);
  Assert.AreEqual('TDataSet.Open', Items[5].Text);
  Assert.AreEqual('Data.DB', Items[5].Place, 'Ort eines Favoriten ist die Unit');
  Assert.AreEqual('', Items[5].ProjectName, 'gilt für alle Projekte');
  Assert.AreEqual(-1, Items[5].Line);
  Assert.AreEqual('TDataSet', Items[5].TypeName);
  Assert.AreEqual('Open', Items[5].Member);
  Assert.AreEqual('tdataset|open', Items[5].Id);
  Assert.AreEqual('Format', Items[6].Text, 'Routine ohne Typ');
  Assert.AreEqual(5, Integer(Length(TAtlasWelcomeSaved.Collect(Books, Lists, nil))));
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeSaved.Collect(nil, nil, nil))));
end;

procedure TAtlasWelcomeSavedTests.BookmarksOfSameFolderCountOnce;
var
  First, Second: TAtlasBookmarkList;
  Items: TAtlasSavedItems;
begin
  // Zwei Projekte im selben Ordner lesen dieselbe Lesezeichen-Datei.
  First := TAtlasBookmarkList.Create('C:\Atlas\Atlas.dproj');
  First.Bookmarks := [Mark('b1', 'Einstieg', 'C:\Atlas\Atlas.dpr', '', 9)];
  Second := TAtlasBookmarkList.Create('C:\Atlas\Werkzeug.dproj');
  Second.Bookmarks := [Mark('b1', 'Einstieg', 'c:\atlas\ATLAS.dpr', '', 9),
    Mark('b2', 'Werkzeug', 'C:\Atlas\Werkzeug.dpr', '', 1)];
  Items := TAtlasWelcomeSaved.FromBookmarks([First, Second]);
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual('C:\Atlas\Atlas.dproj', Items[0].Project);
  Assert.AreEqual('b2', Items[1].Id);
end;

procedure TAtlasWelcomeSavedTests.FilterNeedsEveryWord;
var
  Items, Found: TAtlasSavedItems;
  Book: TAtlasNoteBook;
  List: TAtlasBookmarkList;
begin
  Book := TAtlasNoteBook.Create('C:\Atlas\Atlas.dproj');
  Book.Notes := [Note('n1', 'C:\Atlas\Kunde.pas', 'Prüfen', 1)];
  List := TAtlasBookmarkList.Create('C:\Zeta\Zeta.dproj');
  List.Bookmarks := [Mark('b1', 'Speichern', 'C:\Zeta\Haupt.pas', 'THaupt.Speichern', 2)];
  Items := TAtlasWelcomeSaved.Collect([Book], [List], [Favorite('TDataSet', 'Open', 'Data.DB')]);
  Assert.AreEqual(3, Integer(Length(TAtlasWelcomeSaved.Filter(Items, '  '))), 'leer: alle');
  Found := TAtlasWelcomeSaved.Filter(Items, 'kunde');
  Assert.AreEqual(1, Integer(Length(Found)), 'Datei');
  Found := TAtlasWelcomeSaved.Filter(Items, 'ZETA haupt');
  Assert.AreEqual(1, Integer(Length(Found)), 'Projekt und Datei');
  Assert.AreEqual('b1', Found[0].Id);
  Found := TAtlasWelcomeSaved.Filter(Items, 'data.db');
  Assert.AreEqual(1, Integer(Length(Found)), 'Unit des Favoriten');
  Found := TAtlasWelcomeSaved.Filter(Items, 'speichern atlas');
  Assert.AreEqual(0, Integer(Length(Found)), 'jedes Wort muss passen');
end;

procedure TAtlasWelcomeSavedTests.DeclarationLineOfMethodPropertyAndRoutine;
const
  Text = 'unit Data.DB;'#10 + 'interface'#10 + 'type'#10 + '  TDataSet = class(TComponent)'#10 + '  private'#10 +
    '    FActive: Boolean;'#10 + '  public'#10 + '    procedure Open;'#10 + '    property Active: Boolean read FActive;'#10 +
    '  end;'#10 + 'function Format(const S: string): string;'#10 + 'implementation'#10 +
    'procedure TDataSet.Open;'#10 + 'begin'#10 + 'end;'#10 + 'function Format(const S: string): string;'#10 +
    'begin'#10 + 'end;'#10 + 'end.'#10;
begin
  Assert.AreEqual(7, TAtlasWelcomeSaved.DeclarationLine(Text, 'TDataSet', 'Open'), 'Methodenkopf im Typ');
  Assert.AreEqual(8, TAtlasWelcomeSaved.DeclarationLine(Text, 'TDataSet', 'Active'), 'Eigenschaft');
  Assert.AreEqual(10, TAtlasWelcomeSaved.DeclarationLine(Text, '', 'Format'), 'Routine ohne Typ');
  Assert.AreEqual(-1, TAtlasWelcomeSaved.DeclarationLine(Text, 'TDataSet', 'Gibts'));
  Assert.AreEqual(-1, TAtlasWelcomeSaved.DeclarationLine(Text, 'TDataSet', ''));
end;

procedure TAtlasWelcomeSavedTests.FindUnitIgnoresCase;
var
  Files: TArray<TAtlasIndexFile>;
begin
  SetLength(Files, 2);
  Files[0].UnitName := 'System.SysUtils';
  Files[0].FileName := 'C:\RAD\source\rtl\sys\System.SysUtils.pas';
  Files[1].UnitName := 'Data.DB';
  Files[1].FileName := 'C:\RAD\source\data\Data.DB.pas';
  Assert.AreEqual('C:\RAD\source\data\Data.DB.pas', TAtlasWelcomeSaved.FindUnit(Files, ' data.db '));
  Assert.AreEqual('', TAtlasWelcomeSaved.FindUnit(Files, 'Vcl.Forms'));
  Assert.AreEqual('', TAtlasWelcomeSaved.FindUnit(Files, ''));
end;

procedure TAtlasWelcomeSavedTests.GroupProjectsResolveRelativePaths;
const
  Group = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <ItemGroup>'#13#10 +
    '    <Projects Include="Atlas.dproj">'#13#10 + '      <Dependencies/>'#13#10 + '    </Projects>'#13#10 +
    '    <Projects Include="..\Werkzeuge\Werkzeug.dproj">'#13#10 + '    </Projects>'#13#10 +
    '    <PROJECTS include="Tests/./Tests.dproj"/>'#13#10 +
    '    <Projects Include="D:\Fremd\Fremd.dproj"/>'#13#10 +
    '  </ItemGroup>'#13#10 + '</Project>';
var
  Projects: TArray<string>;
begin
  Projects := TAtlasWelcomeSaved.GroupProjects('C:\Code\Atlas\Atlas.groupproj', Group);
  Assert.AreEqual(4, Integer(Length(Projects)));
  Assert.AreEqual('C:\Code\Atlas\Atlas.dproj', Projects[0]);
  Assert.AreEqual('C:\Code\Werkzeuge\Werkzeug.dproj', Projects[1]);
  Assert.AreEqual('C:\Code\Atlas\Tests\Tests.dproj', Projects[2]);
  Assert.AreEqual('D:\Fremd\Fremd.dproj', Projects[3]);
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeSaved.GroupProjects('C:\X.groupproj', '<Project/>'))));
  Assert.AreEqual('\\server\share\A.dproj', TAtlasWelcomeSaved.ResolvePath('C:\X', '\\server\share\A.dproj'));
  Assert.AreEqual('C:\A.dproj', TAtlasWelcomeSaved.ResolvePath('C:\X', '..\..\A.dproj'), 'nie über das Laufwerk');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeSavedTests);

end.
