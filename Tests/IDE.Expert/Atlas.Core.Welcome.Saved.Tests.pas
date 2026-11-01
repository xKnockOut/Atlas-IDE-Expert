unit Atlas.Core.Welcome.Saved.Tests;

// Tests des Reiters „Gemerkt“ ohne VCL (#755): Notizen (#545) und
// Lesezeichen (#622) vom Modul Lesezeichen (Vertrag SavedPlaces, #1456) und
// Favoriten (#458) aus zwei Projekten in einer Liste mit Art, Text, Datei und
// Zeile sowie Projekt; Filter; Sprungziel eines Favoriten (Deklaration in der
// Unit, Unit aus dem Index-Cache) und die Projekte einer Projektgruppe für die
// Lesezeichen. Wie Notizen und Lesezeichen zu Einträgen werden, testet
// Atlas.Core.Bookmarks.SavedPlaces.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeSavedTests = class
  public
    [Test]
    procedure CollectsNotesBookmarksAndFavoritesOfTwoProjects;
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
  Atlas.Core.Completion.Favorites,
  Atlas.Core.SavedPlaces.Contract,
  Atlas.Core.Welcome.IndexFiles,
  Atlas.Core.Welcome.Saved;

function Place(AKind: TAtlasSavedPlaceKind; const AId, AText, AFileName, AProject: string;
  ALine: Integer): TAtlasSavedPlace;
begin
  Result := Default(TAtlasSavedPlace);
  Result.Kind := AKind;
  Result.Id := AId;
  Result.Text := AText;
  Result.FileName := AFileName;
  Result.Project := AProject;
  Result.Line := ALine;
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
  mPlaces: TAtlasSavedPlaces;
  mItems: TAtlasSavedItems;
begin
  mPlaces := TAtlasSavedPlaces.Create(
    Place(TAtlasSavedPlaceKind.Note, 'n2', 'Aufräumen', 'C:\Zeta\Haupt.pas', 'C:\Zeta\Zeta.dproj', 4),
    Place(TAtlasSavedPlaceKind.Note, 'n1', 'Prüfen, ob leer …', 'C:\Atlas\Kunde.pas', 'C:\Atlas\Atlas.dproj', 41),
    Place(TAtlasSavedPlaceKind.Bookmark, 'b2', 'Speichern', 'C:\Atlas\Kunde.pas', 'C:\Atlas\Atlas.dproj', 80),
    Place(TAtlasSavedPlaceKind.Bookmark, 'b1', 'Einstieg', 'C:\Atlas\Atlas.dpr', 'C:\Atlas\Atlas.dproj', 9),
    Place(TAtlasSavedPlaceKind.Bookmark, 'b3', 'Start', 'C:\Zeta\Haupt.pas', 'C:\Zeta\Zeta.dproj', 2));
  mPlaces[1].Lost := True;
  mPlaces[1].Detail := 'Prüfen, ob leer mit Eva klären';
  mPlaces[2].Detail := 'TKunde.Speichern';
  mItems := TAtlasWelcomeSaved.Collect(mPlaces, TArray<TAtlasFavorite>.Create(Favorite('TDataSet', 'Open', 'Data.DB'),
    Favorite('', 'Format', 'System.SysUtils')));
  Assert.AreEqual(7, Integer(Length(mItems)));
  // Atlas vor Zeta; je Projekt erst Notizen, dann Lesezeichen nach Datei und Zeile; Favoriten am Ende.
  Assert.IsTrue(mItems[0].Kind = TAtlasSavedKind.Note);
  Assert.AreEqual('Atlas', mItems[0].ProjectName);
  Assert.AreEqual('Prüfen, ob leer …', mItems[0].Text, 'Titel der Notiz');
  Assert.AreEqual('Kunde.pas:42', mItems[0].Place, 'Zeile ab 1');
  Assert.AreEqual(41, mItems[0].Line, '0-basiert für den Sprung');
  Assert.IsTrue(mItems[0].Lost, 'verwaist');
  Assert.Contains(mItems[0].Detail, 'Eva');
  Assert.IsTrue(mItems[1].Kind = TAtlasSavedKind.Bookmark);
  Assert.AreEqual('Einstieg', mItems[1].Text);
  Assert.AreEqual('Atlas.dpr:10', mItems[1].Place);
  Assert.IsTrue(mItems[2].Kind = TAtlasSavedKind.Bookmark);
  Assert.AreEqual('Speichern', mItems[2].Text);
  Assert.AreEqual('TKunde.Speichern', mItems[2].Detail);
  Assert.AreEqual('b2', mItems[2].Id);
  Assert.AreEqual('C:\Atlas\Atlas.dproj', mItems[2].Project);
  Assert.IsTrue(mItems[3].Kind = TAtlasSavedKind.Note);
  Assert.AreEqual('Zeta', mItems[3].ProjectName);
  Assert.IsTrue(mItems[4].Kind = TAtlasSavedKind.Bookmark);
  Assert.AreEqual('Zeta', mItems[4].ProjectName);
  Assert.IsTrue(mItems[5].Kind = TAtlasSavedKind.Favorite);
  Assert.AreEqual('TDataSet.Open', mItems[5].Text);
  Assert.AreEqual('Data.DB', mItems[5].Place, 'Ort eines Favoriten ist die Unit');
  Assert.AreEqual('', mItems[5].ProjectName, 'gilt für alle Projekte');
  Assert.AreEqual(-1, mItems[5].Line);
  Assert.AreEqual('TDataSet', mItems[5].TypeName);
  Assert.AreEqual('Open', mItems[5].Member);
  Assert.AreEqual('tdataset|open', mItems[5].Id);
  Assert.AreEqual('Format', mItems[6].Text, 'Routine ohne Typ');
  Assert.AreEqual(5, Integer(Length(TAtlasWelcomeSaved.Collect(mPlaces, nil))));
  // Ohne das Modul Lesezeichen: nur die Favoriten.
  Assert.AreEqual(2, Integer(Length(TAtlasWelcomeSaved.Collect(nil, TArray<TAtlasFavorite>.Create(
    Favorite('TDataSet', 'Open', 'Data.DB'), Favorite('', 'Format', 'System.SysUtils'))))));
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeSaved.Collect(nil, nil))));
  mPlaces := nil;
  mItems := nil;
end;

procedure TAtlasWelcomeSavedTests.FilterNeedsEveryWord;
var
  Items, Found: TAtlasSavedItems;
  mPlaces: TAtlasSavedPlaces;
begin
  mPlaces := TAtlasSavedPlaces.Create(
    Place(TAtlasSavedPlaceKind.Note, 'n1', 'Prüfen', 'C:\Atlas\Kunde.pas', 'C:\Atlas\Atlas.dproj', 1),
    Place(TAtlasSavedPlaceKind.Bookmark, 'b1', 'Speichern', 'C:\Zeta\Haupt.pas', 'C:\Zeta\Zeta.dproj', 2));
  mPlaces[1].Detail := 'THaupt.Speichern';
  Items := TAtlasWelcomeSaved.Collect(mPlaces, TArray<TAtlasFavorite>.Create(Favorite('TDataSet', 'Open', 'Data.DB')));
  mPlaces := nil;
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
