unit Atlas.Core.Outline.Breadcrumbs.Tests;

// Brotkrumenleiste (#590): Pfad aus der Gliederung (verschachtelte Typen,
// lokale Prozeduren, interface/implementation, uses und initialization),
// Geschwister für das Sprungmenü, Sprungziel und Wortgrenzen-Suche.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBreadcrumbsTests = class
  public
    [Test]
    procedure PathInLocalProcedureOfMethod;
    [Test]
    procedure PathInInterfaceEndsAtMember;
    [Test]
    procedure PathThroughNestedTypes;
    [Test]
    procedure SectionsFromText;
    [Test]
    procedure SiblingsOfMethodAreMethodsOfTheType;
    [Test]
    procedure SiblingsOnUnitLevel;
    [Test]
    procedure FilterAtWordStarts;
    [Test]
    procedure TargetPrefersImplementation;
    [Test]
    procedure BadgesFollowTheHeader;
    [Test]
    procedure UnitCrumbListsUnitMembers;
    [Test]
    procedure ChildrenOfTypesAndRoutines;
    [Test]
    procedure RoutinesForFindMethod;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs;

const
  Code =
    'unit uKundeForm;'#13#10 +                                        // 0
    'interface'#13#10 +                                               // 1
    'uses'#13#10 +                                                    // 2
    '  Vcl.Forms, // Kommentar;'#13#10 +                              // 3
    '  Vcl.StdCtrls;'#13#10 +                                         // 4
    'type'#13#10 +                                                    // 5
    '  TfrmKunde = class(TForm)'#13#10 +                              // 6
    '    btnSpeichern: TButton;'#13#10 +                              // 7
    '    procedure btnSpeichernClick(Sender: TObject);'#13#10 +       // 8
    '  private'#13#10 +                                               // 9
    '    procedure SpeichereAdresse;'#13#10 +                         // 10
    '    function SpaltenBreite: Integer;'#13#10 +                    // 11
    '    procedure Display;'#13#10 +                                  // 12
    '  public'#13#10 +                                                // 13
    '    type'#13#10 +                                                // 14
    '      TInner = class'#13#10 +                                    // 15
    '        procedure Tief;'#13#10 +                                 // 16
    '      end;'#13#10 +                                              // 17
    '  end;'#13#10 +                                                  // 18
    '  TAndere = record X: Integer; end;'#13#10 +                     // 19
    'const Limit = 10;'#13#10 +                                       // 20
    'implementation'#13#10 +                                          // 21
    'procedure TfrmKunde.btnSpeichernClick(Sender: TObject);'#13#10 + // 22
    '  procedure Pruefe;'#13#10 +                                     // 23
    '  begin'#13#10 +                                                 // 24
    '  end;'#13#10 +                                                  // 25
    '  procedure Melde; begin end;'#13#10 +                           // 26
    'begin'#13#10 +                                                   // 27
    '  Pruefe;'#13#10 +                                               // 28
    'end;'#13#10 +                                                    // 29
    'procedure TfrmKunde.SpeichereAdresse; begin end;'#13#10 +        // 30
    'function TfrmKunde.SpaltenBreite: Integer; begin Result := 0; end;'#13#10 + // 31
    'procedure TfrmKunde.Display; begin end;'#13#10 +                 // 32
    'procedure TfrmKunde.TInner.Tief; begin end;'#13#10 +             // 33
    'procedure Hilfe; begin end;'#13#10 +                             // 34
    'initialization'#13#10 +                                          // 35
    '  Hilfe;'#13#10 +                                                // 36
    'end.';                                                           // 37

function Lines: TArray<string>;
begin
  Result := Code.Split([#13#10]);
end;

function Nodes: TAtlasOutlineNodes;
var
  Tree: TSyntaxTree;
  Symbols: TJSONArray;
begin
  Tree := TPascalParser.Parse(Code);
  try
    Symbols := TLspDocumentSymbols.BuildSymbols(Tree, Code);
  finally
    Tree.Free;
  end;
  try
    Result := TAtlasOutline.FromJson(Symbols);
  finally
    Symbols.Free;
  end;
end;

function Joined(const ACrumbs: TAtlasCrumbs): string;
var
  Crumb: TAtlasCrumb;
begin
  Result := '';
  for Crumb in ACrumbs do
  begin
    if Result <> '' then
      Result := Result + ' › ';
    Result := Result + Crumb.Text;
  end;
end;

function NamesOf(const ANodes: TAtlasOutlineNodes; const AItems: TArray<Integer>): string;
var
  Item: Integer;
begin
  Result := '';
  for Item in AItems do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + TAtlasBreadcrumbs.ShortName(ANodes[Item].Name);
  end;
end;

function Find(const ANodes: TAtlasOutlineNodes; const AName: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ANodes) do
    if ANodes[Index].Name = AName then
      Exit(Index);
  Result := -1;
end;

procedure TAtlasBreadcrumbsTests.PathInLocalProcedureOfMethod;
var
  List: TAtlasOutlineNodes;
  Crumbs: TAtlasCrumbs;
begin
  List := Nodes;
  Crumbs := TAtlasBreadcrumbs.Path(List, Lines, 24, 4, 'uKundeForm', True);
  Assert.AreEqual('uKundeForm › TfrmKunde › btnSpeichernClick › Pruefe', Joined(Crumbs));
  Assert.IsTrue(Crumbs[0].Badge.Kind = TAtlasBadgeKind.Unit_);
  // Unit-Glied: alle Elemente der Unit-Ebene als Menü und als Kinder.
  Assert.AreEqual('TfrmKunde,TAndere,Limit,Hilfe', NamesOf(List, Crumbs[0].Siblings));
  Assert.AreEqual('TfrmKunde,TAndere,Limit,Hilfe', NamesOf(List, Crumbs[0].Children));
  // Das Glied der Methode ist die Deklaration im Typ.
  Assert.AreEqual(8, List[Crumbs[2].Node].StartLine);
  // Ohne Unit-Namen (Vorgabe).
  Assert.AreEqual('TfrmKunde › btnSpeichernClick', Joined(TAtlasBreadcrumbs.Path(List, Lines, 28, 2, 'uKundeForm',
    False)));
end;

procedure TAtlasBreadcrumbsTests.PathInInterfaceEndsAtMember;
begin
  Assert.AreEqual('TfrmKunde › SpeichereAdresse', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines, 10, 8, '', False)));
  Assert.AreEqual('TfrmKunde › btnSpeichern', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines, 7, 6, '', False)));
  Assert.AreEqual('Limit', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines, 20, 7, '', False)));
end;

procedure TAtlasBreadcrumbsTests.PathThroughNestedTypes;
begin
  Assert.AreEqual('TfrmKunde › TInner › Tief', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines, 16, 12, '', False)));
  Assert.AreEqual('TfrmKunde › TInner › Tief', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines, 33, 40, '', False)),
    'Rumpf der Methode des verschachtelten Typs');
end;

procedure TAtlasBreadcrumbsTests.SectionsFromText;
var
  Text: TArray<string>;
begin
  Text := Lines;
  Assert.IsTrue(TAtlasBreadcrumbs.SectionAt(Text, 1) = TAtlasCodeSection.InterfacePart);
  Assert.IsTrue(TAtlasBreadcrumbs.SectionAt(Text, 3) = TAtlasCodeSection.UsesClause, 'Semikolon im Kommentar');
  Assert.IsTrue(TAtlasBreadcrumbs.SectionAt(Text, 4) = TAtlasCodeSection.UsesClause, 'Zeile mit dem Semikolon');
  Assert.IsTrue(TAtlasBreadcrumbs.SectionAt(Text, 5) = TAtlasCodeSection.InterfacePart);
  Assert.IsTrue(TAtlasBreadcrumbs.SectionAt(Text, 30) = TAtlasCodeSection.ImplementationPart);
  Assert.IsTrue(TAtlasBreadcrumbs.SectionAt(Text, 36) = TAtlasCodeSection.Initialization_);
  Assert.AreEqual('U › uses', Joined(TAtlasBreadcrumbs.Path(Nodes, Text, 3, 4, 'U', True)));
  Assert.AreEqual('initialization', Joined(TAtlasBreadcrumbs.Path(Nodes, Text, 36, 2, 'U', False)));
end;

procedure TAtlasBreadcrumbsTests.SiblingsOfMethodAreMethodsOfTheType;
var
  List: TAtlasOutlineNodes;
  Crumbs: TAtlasCrumbs;
begin
  List := Nodes;
  Crumbs := TAtlasBreadcrumbs.Path(List, Lines, 24, 4, '', False);
  Assert.AreEqual('btnSpeichernClick,SpeichereAdresse,SpaltenBreite,Display', NamesOf(List, Crumbs[1].Siblings));
  Assert.AreEqual(0, Crumbs[1].Current);
  // Lokale Prozeduren desselben Rumpfs.
  Assert.AreEqual('Pruefe,Melde', NamesOf(List, Crumbs[2].Siblings));
  Assert.AreEqual(0, Crumbs[2].Current);
  // Typen der Unit.
  Assert.AreEqual('TfrmKunde,TAndere', NamesOf(List, Crumbs[0].Siblings));
  // Feld: alle Mitglieder des Typs.
  Crumbs := TAtlasBreadcrumbs.Path(List, Lines, 7, 6, '', False);
  Assert.AreEqual('btnSpeichern,btnSpeichernClick,SpeichereAdresse,SpaltenBreite,Display,TInner',
    NamesOf(List, Crumbs[1].Siblings));
end;

procedure TAtlasBreadcrumbsTests.SiblingsOnUnitLevel;
var
  List: TAtlasOutlineNodes;
  Crumbs: TAtlasCrumbs;
begin
  List := Nodes;
  Crumbs := TAtlasBreadcrumbs.Path(List, Lines, 34, 20, '', False);
  Assert.AreEqual('Hilfe', Joined(Crumbs));
  Assert.AreEqual('Hilfe', NamesOf(List, Crumbs[0].Siblings));
  Crumbs := TAtlasBreadcrumbs.Path(List, Lines, 20, 7, '', False);
  Assert.AreEqual('Limit', NamesOf(List, Crumbs[0].Siblings));
end;

procedure TAtlasBreadcrumbsTests.FilterAtWordStarts;
var
  List: TAtlasOutlineNodes;
  Crumbs: TAtlasCrumbs;
begin
  List := Nodes;
  Crumbs := TAtlasBreadcrumbs.Path(List, Lines, 24, 4, '', False);
  // „sp“ an einer Wortgrenze; Display enthält „sp“ nur mitten im Wort.
  Assert.AreEqual('btnSpeichernClick,SpeichereAdresse,SpaltenBreite',
    NamesOf(List, TAtlasBreadcrumbs.Filter(List, Crumbs[1].Siblings, 'sp')));
  Assert.AreEqual(4, Integer(Length(TAtlasBreadcrumbs.Filter(List, Crumbs[1].Siblings, ''))));
  Assert.IsTrue(TAtlasBreadcrumbs.MatchesAtWordStart('SA', 'SpeichereAdresse'));
  Assert.IsFalse(TAtlasBreadcrumbs.MatchesAtWordStart('isp', 'Display'));
end;

procedure TAtlasBreadcrumbsTests.TargetPrefersImplementation;
var
  List: TAtlasOutlineNodes;
  Declaration: Integer;
begin
  List := Nodes;
  Declaration := Find(List, 'SpaltenBreite');
  Assert.AreEqual(31, List[TAtlasBreadcrumbs.Target(List, Declaration, True)].StartLine);
  Assert.AreEqual(Declaration, TAtlasBreadcrumbs.Target(List, Declaration, False));
  // Rumpf → Deklaration.
  Assert.AreEqual(Declaration, TAtlasBreadcrumbs.Target(List, List[Declaration].Body, False));
  // Lokale Routine: sie selbst.
  Assert.AreEqual(Find(List, 'Pruefe'), TAtlasBreadcrumbs.Target(List, Find(List, 'Pruefe'), True));
  Assert.AreEqual(-1, TAtlasBreadcrumbs.Target(List, -1, True));
end;

procedure TAtlasBreadcrumbsTests.BadgesFollowTheHeader;
var
  List: TAtlasOutlineNodes;
  Text: TArray<string>;
begin
  List := Nodes;
  Text := Lines;
  Assert.AreEqual('pr', TAtlasBreadcrumbs.BadgeOf(List, Text, Find(List, 'SpeichereAdresse')).Code);
  Assert.AreEqual('fn', TAtlasBreadcrumbs.BadgeOf(List, Text, Find(List, 'SpaltenBreite')).Code);
  Assert.AreEqual('ty', TAtlasBreadcrumbs.BadgeOf(List, Text, Find(List, 'TfrmKunde')).Code);
  Assert.AreEqual('fd', TAtlasBreadcrumbs.BadgeOf(List, Text, Find(List, 'btnSpeichern')).Code);
  Assert.AreEqual('co', TAtlasBreadcrumbs.BadgeOf(List, Text, Find(List, 'Limit')).Code);
end;

procedure TAtlasBreadcrumbsTests.UnitCrumbListsUnitMembers;
var
  List: TAtlasOutlineNodes;
  Crumbs: TAtlasCrumbs;
begin
  List := Nodes;
  // Rümpfe der Methoden zählen nicht doppelt, Routinen ohne Deklaration (Hilfe) schon.
  Assert.AreEqual('TfrmKunde,TAndere,Limit,Hilfe', NamesOf(List, TAtlasBreadcrumbs.UnitMembers(List)));
  // Auch in uses und initialization hat das Unit-Glied sein Menü.
  Crumbs := TAtlasBreadcrumbs.Path(List, Lines, 3, 4, 'U', True);
  Assert.AreEqual('U › uses', Joined(Crumbs));
  Assert.AreEqual(4, Integer(Length(Crumbs[0].Siblings)));
  Assert.AreEqual(0, Integer(Length(Crumbs[1].Children)), 'uses ohne Kinder');
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.UnitMembers(nil))));
end;

procedure TAtlasBreadcrumbsTests.ChildrenOfTypesAndRoutines;
var
  List: TAtlasOutlineNodes;
  Crumbs: TAtlasCrumbs;
begin
  List := Nodes;
  Crumbs := TAtlasBreadcrumbs.Path(List, Lines, 24, 4, '', False);
  Assert.AreEqual('TfrmKunde › btnSpeichernClick › Pruefe', Joined(Crumbs));
  // Typ: alle Mitglieder in Quelltextreihenfolge.
  Assert.AreEqual('btnSpeichern,btnSpeichernClick,SpeichereAdresse,SpaltenBreite,Display,TInner',
    NamesOf(List, Crumbs[0].Children));
  // Methode (Deklaration im Typ): die lokalen Routinen ihres Rumpfs.
  Assert.AreEqual('Pruefe,Melde', NamesOf(List, Crumbs[1].Children));
  // Lokale Routine ohne eigene lokale Routinen.
  Assert.AreEqual(0, Integer(Length(Crumbs[2].Children)));
  // Verschachtelter Typ.
  Assert.AreEqual('Tief', NamesOf(List, TAtlasBreadcrumbs.Children(List, Find(List, 'TInner'))));
  // Methode ohne lokale Routinen, ungültiger Knoten.
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.Children(List, Find(List, 'SpaltenBreite')))));
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.Children(List, -1))));
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.Children(List, Length(List)))));
end;

procedure TAtlasBreadcrumbsTests.RoutinesForFindMethod;
var
  List: TAtlasOutlineNodes;
  Item: Integer;
  Names: string;
begin
  List := Nodes;
  // „Methode suchen“ der Editorleiste (#1101): Methoden mit Besitzer, Routinen, keine lokalen Routinen und
  // keine Rümpfe doppelt.
  Names := '';
  for Item in TAtlasBreadcrumbs.Routines(List) do
  begin
    if Names <> '' then
      Names := Names + ',';
    Names := Names + TAtlasBreadcrumbs.QualifiedName(List, Item);
  end;
  Assert.AreEqual('TfrmKunde.btnSpeichernClick,TfrmKunde.SpeichereAdresse,TfrmKunde.SpaltenBreite,' +
    'TfrmKunde.Display,TfrmKunde.TInner.Tief,Hilfe', Names);
  Assert.AreEqual('', TAtlasBreadcrumbs.QualifiedName(List, -1));
  Assert.AreEqual('TAndere', TAtlasBreadcrumbs.QualifiedName(List, Find(List, 'TAndere')));
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.Routines(nil))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreadcrumbsTests);

end.
