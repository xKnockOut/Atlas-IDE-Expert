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
    procedure SectionTableMatchesSectionAt;
    [Test]
    procedure PreparedTextGivesTheSamePath;
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
  cCode =
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

  /// <summary>Regionen, Bedingungszweige und Abschnitte für den Vergleich mit dem vorbereiteten Text.</summary>
  cDirectiveCode =
    'unit uRegionen;'#13#10 +
    'interface'#13#10 +
    'uses'#13#10 +
    '  System.SysUtils;'#13#10 +
    '{$REGION ''Typen''}'#13#10 +
    'type'#13#10 +
    '  TKunde = class'#13#10 +
    '  private'#13#10 +
    '    FName: string;'#13#10 +
    '  public'#13#10 +
    '    procedure Speichere;'#13#10 +
    '  end;'#13#10 +
    '{$ENDREGION}'#13#10 +
    'const Grenze = 3;'#13#10 +
    'var Zaehler: Integer;'#13#10 +
    'implementation'#13#10 +
    'uses System.Classes;'#13#10 +
    '{$REGION ''Rümpfe''}'#13#10 +
    'procedure TKunde.Speichere;'#13#10 +
    'begin'#13#10 +
    '{$IFDEF DEBUG}'#13#10 +
    '  if FName = '''' then'#13#10 +
    '  begin'#13#10 +
    '    Exit;'#13#10 +
    '  end;'#13#10 +
    '{$ELSE}'#13#10 +
    '  Inc(Zaehler);'#13#10 +
    '{$ENDIF}'#13#10 +
    'end;'#13#10 +
    '{$ENDREGION}'#13#10 +
    'initialization'#13#10 +
    '  Zaehler := 0;'#13#10 +
    'end.';

function Lines: TArray<string>;
begin
  Result := cCode.Split([#13#10]);
end;

function NodesOf(const AText: string): TAtlasOutlineNodes;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(AText);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, AText);
  finally
    mTree.Free;
  end;
  try
    Result := TAtlasOutline.FromJson(mSymbols);
  finally
    mSymbols.Free;
  end;
end;

function Nodes: TAtlasOutlineNodes;
begin
  Result := NodesOf(cCode);
end;

function Joined(const ACrumbs: TAtlasCrumbs): string;
var
  mCrumb: TAtlasCrumb;
begin
  Result := '';
  for mCrumb in ACrumbs do
  begin
    if Result <> '' then
    begin
      Result := Result + ' › ';
    end;
    Result := Result + mCrumb.Text;
  end;
end;

function NamesOf(const ANodes: TAtlasOutlineNodes; const AItems: TArray<Integer>): string;
var
  mItem: Integer;
begin
  Result := '';
  for mItem in AItems do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + TAtlasBreadcrumbs.ShortName(ANodes[mItem].Name);
  end;
end;

function Find(const ANodes: TAtlasOutlineNodes; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ANodes) do
  begin
    if ANodes[mIndex].Name = AName then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasBreadcrumbsTests.PathInLocalProcedureOfMethod;
var
  mList: TAtlasOutlineNodes;
  mCrumbs: TAtlasCrumbs;
begin
  mList := Nodes;
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, TAtlasCrumbRequest.Create(24, 4, 'uKundeForm', True, []));
  Assert.AreEqual('uKundeForm › TfrmKunde › btnSpeichernClick › Pruefe', Joined(mCrumbs));
  Assert.AreEqual<TAtlasBadgeKind>(TAtlasBadgeKind.Unit_, mCrumbs[0].Badge.Kind);
  // Unit-Glied: alle Elemente der Unit-Ebene als Menü und als Kinder.
  Assert.AreEqual('TfrmKunde,TAndere,Limit,Hilfe', NamesOf(mList, mCrumbs[0].Siblings));
  Assert.AreEqual('TfrmKunde,TAndere,Limit,Hilfe', NamesOf(mList, mCrumbs[0].Children));
  // Das Glied der Methode ist die Deklaration im Typ.
  Assert.AreEqual(8, mList[mCrumbs[2].Node].StartLine);
  // Ohne Unit-Namen (Vorgabe).
  Assert.AreEqual('TfrmKunde › btnSpeichernClick', Joined(TAtlasBreadcrumbs.Path(mList, Lines,
    TAtlasCrumbRequest.Create(28, 2, 'uKundeForm', False, []))));
end;

procedure TAtlasBreadcrumbsTests.PathInInterfaceEndsAtMember;
begin
  Assert.AreEqual('TfrmKunde › SpeichereAdresse', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(10, 8, '', False, []))));
  Assert.AreEqual('TfrmKunde › btnSpeichern', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(7, 6, '', False, []))));
  Assert.AreEqual('Limit', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(20, 7, '', False, []))));
end;

procedure TAtlasBreadcrumbsTests.PathThroughNestedTypes;
begin
  Assert.AreEqual('TfrmKunde › TInner › Tief', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(16, 12, '', False, []))));
  Assert.AreEqual('TfrmKunde › TInner › Tief', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(33, 40, '', False, []))),
    'Rumpf der Methode des verschachtelten Typs');
end;

procedure TAtlasBreadcrumbsTests.SectionsFromText;
var
  mText: TArray<string>;
begin
  mText := Lines;
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.InterfacePart, TAtlasBreadcrumbs.SectionAt(mText, 1));
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.UsesClause,
    TAtlasBreadcrumbs.SectionAt(mText, 3), 'Semikolon im Kommentar');
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.UsesClause,
    TAtlasBreadcrumbs.SectionAt(mText, 4), 'Zeile mit dem Semikolon');
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.InterfacePart, TAtlasBreadcrumbs.SectionAt(mText, 5));
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.ImplementationPart, TAtlasBreadcrumbs.SectionAt(mText, 30));
  Assert.AreEqual<TAtlasCodeSection>(TAtlasCodeSection.Initialization_, TAtlasBreadcrumbs.SectionAt(mText, 36));
  Assert.AreEqual('U › uses', Joined(TAtlasBreadcrumbs.Path(Nodes, mText,
    TAtlasCrumbRequest.Create(3, 4, 'U', True, []))));
  Assert.AreEqual('initialization', Joined(TAtlasBreadcrumbs.Path(Nodes, mText,
    TAtlasCrumbRequest.Create(36, 2, 'U', False, []))));
end;

procedure TAtlasBreadcrumbsTests.SectionTableMatchesSectionAt;
var
  mText: TArray<string>;
  mTable: TArray<TAtlasCodeSection>;
  mLine: Integer;
begin
  mText := cDirectiveCode.Split([#13#10]);
  mTable := TAtlasBreadcrumbs.SectionTable(mText);
  Assert.AreEqual(Length(mText), Length(mTable));
  for mLine := 0 to High(mText) do
  begin
    Assert.AreEqual<TAtlasCodeSection>(TAtlasBreadcrumbs.SectionAt(mText, mLine), mTable[mLine], 'Zeile ' + IntToStr(mLine));
  end;
  mText := Lines;
  mTable := TAtlasBreadcrumbs.SectionTable(mText);
  for mLine := 0 to High(mText) do
  begin
    Assert.AreEqual<TAtlasCodeSection>(TAtlasBreadcrumbs.SectionAt(mText, mLine), mTable[mLine], 'Zeile ' + IntToStr(mLine));
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.SectionTable(nil))));
end;

procedure TAtlasBreadcrumbsTests.PreparedTextGivesTheSamePath;
const
  cAll = [Low(TAtlasCrumbPart)..High(TAtlasCrumbPart)];
var
  mSource: string;
  mText: TArray<string>;
  mList: TAtlasOutlineNodes;
  mPrepared: TAtlasCrumbText;
  mLine, mCharacter: Integer;
  mExpected, mActual: TAtlasCrumbs;
begin
  // Der einmal ausgewertete Text gibt an jeder Stelle denselben Pfad wie der Weg über den ganzen Text.
  for mSource in [cCode, cDirectiveCode] do
  begin
    mText := mSource.Split([#13#10]);
    mList := NodesOf(mSource);
    mPrepared := TAtlasBreadcrumbs.Prepare(mList, mText);
    for mLine := 0 to Length(mText) do
    begin
      for mCharacter in [0, 4, 12] do
      begin
        mExpected := TAtlasBreadcrumbs.Path(mList, mText, TAtlasCrumbRequest.Create(mLine, mCharacter, 'U', True, cAll));
        mActual := TAtlasBreadcrumbs.Path(mPrepared, TAtlasCrumbRequest.Create(mLine, mCharacter, 'U', True, cAll));
        Assert.AreEqual(Joined(mExpected), Joined(mActual), Format('Zeile %d, Spalte %d', [mLine, mCharacter]));
      end;
    end;
  end;
  mText := cDirectiveCode.Split([#13#10]);
  Assert.AreEqual('U › Rümpfe › TKunde › Speichere › {$IFDEF DEBUG}',
    Joined(TAtlasBreadcrumbs.Path(TAtlasBreadcrumbs.Prepare(NodesOf(cDirectiveCode), mText),
    TAtlasCrumbRequest.Create(23, 4, 'U', True, [TAtlasCrumbPart.Regions, TAtlasCrumbPart.Conditionals]))));
end;

procedure TAtlasBreadcrumbsTests.SiblingsOfMethodAreMethodsOfTheType;
var
  mList: TAtlasOutlineNodes;
  mCrumbs: TAtlasCrumbs;
begin
  mList := Nodes;
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, TAtlasCrumbRequest.Create(24, 4, '', False, []));
  Assert.AreEqual('btnSpeichernClick,SpeichereAdresse,SpaltenBreite,Display', NamesOf(mList, mCrumbs[1].Siblings));
  Assert.AreEqual(0, mCrumbs[1].Current);
  // Lokale Prozeduren desselben Rumpfs.
  Assert.AreEqual('Pruefe,Melde', NamesOf(mList, mCrumbs[2].Siblings));
  Assert.AreEqual(0, mCrumbs[2].Current);
  // Typen der Unit.
  Assert.AreEqual('TfrmKunde,TAndere', NamesOf(mList, mCrumbs[0].Siblings));
  // Feld: alle Mitglieder des Typs.
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, TAtlasCrumbRequest.Create(7, 6, '', False, []));
  Assert.AreEqual('btnSpeichern,btnSpeichernClick,SpeichereAdresse,SpaltenBreite,Display,TInner',
    NamesOf(mList, mCrumbs[1].Siblings));
end;

procedure TAtlasBreadcrumbsTests.SiblingsOnUnitLevel;
var
  mList: TAtlasOutlineNodes;
  mCrumbs: TAtlasCrumbs;
begin
  mList := Nodes;
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, TAtlasCrumbRequest.Create(34, 20, '', False, []));
  Assert.AreEqual('Hilfe', Joined(mCrumbs));
  Assert.AreEqual('Hilfe', NamesOf(mList, mCrumbs[0].Siblings));
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, TAtlasCrumbRequest.Create(20, 7, '', False, []));
  Assert.AreEqual('Limit', NamesOf(mList, mCrumbs[0].Siblings));
end;

procedure TAtlasBreadcrumbsTests.FilterAtWordStarts;
var
  mList: TAtlasOutlineNodes;
  mCrumbs: TAtlasCrumbs;
begin
  mList := Nodes;
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, TAtlasCrumbRequest.Create(24, 4, '', False, []));
  // „sp“ an einer Wortgrenze; Display enthält „sp“ nur mitten im Wort.
  Assert.AreEqual('btnSpeichernClick,SpeichereAdresse,SpaltenBreite',
    NamesOf(mList, TAtlasBreadcrumbs.Filter(mList, mCrumbs[1].Siblings, 'sp')));
  Assert.AreEqual(4, Integer(Length(TAtlasBreadcrumbs.Filter(mList, mCrumbs[1].Siblings, ''))));
  Assert.IsTrue(TAtlasBreadcrumbs.MatchesAtWordStart('SA', 'SpeichereAdresse'));
  Assert.IsFalse(TAtlasBreadcrumbs.MatchesAtWordStart('isp', 'Display'));
end;

procedure TAtlasBreadcrumbsTests.TargetPrefersImplementation;
var
  mList: TAtlasOutlineNodes;
  mDeclaration: Integer;
begin
  mList := Nodes;
  mDeclaration := Find(mList, 'SpaltenBreite');
  Assert.AreEqual(31, mList[TAtlasBreadcrumbs.Target(mList, mDeclaration, True)].StartLine);
  Assert.AreEqual(mDeclaration, TAtlasBreadcrumbs.Target(mList, mDeclaration, False));
  // Rumpf → Deklaration.
  Assert.AreEqual(mDeclaration, TAtlasBreadcrumbs.Target(mList, mList[mDeclaration].Body, False));
  // Lokale Routine: sie selbst.
  Assert.AreEqual(Find(mList, 'Pruefe'), TAtlasBreadcrumbs.Target(mList, Find(mList, 'Pruefe'), True));
  Assert.AreEqual(-1, TAtlasBreadcrumbs.Target(mList, -1, True));
end;

procedure TAtlasBreadcrumbsTests.BadgesFollowTheHeader;
var
  mList: TAtlasOutlineNodes;
  mText: TArray<string>;
begin
  mList := Nodes;
  mText := Lines;
  Assert.AreEqual('pr', TAtlasBreadcrumbs.BadgeOf(mList, mText, Find(mList, 'SpeichereAdresse')).Code);
  Assert.AreEqual('fn', TAtlasBreadcrumbs.BadgeOf(mList, mText, Find(mList, 'SpaltenBreite')).Code);
  Assert.AreEqual('ty', TAtlasBreadcrumbs.BadgeOf(mList, mText, Find(mList, 'TfrmKunde')).Code);
  Assert.AreEqual('fd', TAtlasBreadcrumbs.BadgeOf(mList, mText, Find(mList, 'btnSpeichern')).Code);
  Assert.AreEqual('co', TAtlasBreadcrumbs.BadgeOf(mList, mText, Find(mList, 'Limit')).Code);
end;

procedure TAtlasBreadcrumbsTests.UnitCrumbListsUnitMembers;
var
  mList: TAtlasOutlineNodes;
  mCrumbs: TAtlasCrumbs;
begin
  mList := Nodes;
  // Rümpfe der Methoden zählen nicht doppelt, Routinen ohne Deklaration (Hilfe) schon.
  Assert.AreEqual('TfrmKunde,TAndere,Limit,Hilfe', NamesOf(mList, TAtlasBreadcrumbs.UnitMembers(mList)));
  // Auch in uses und initialization hat das Unit-Glied sein Menü.
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, TAtlasCrumbRequest.Create(3, 4, 'U', True, []));
  Assert.AreEqual('U › uses', Joined(mCrumbs));
  Assert.AreEqual(4, Integer(Length(mCrumbs[0].Siblings)));
  Assert.AreEqual(0, Integer(Length(mCrumbs[1].Children)), 'uses ohne Kinder');
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.UnitMembers(nil))));
end;

procedure TAtlasBreadcrumbsTests.ChildrenOfTypesAndRoutines;
var
  mList: TAtlasOutlineNodes;
  mCrumbs: TAtlasCrumbs;
begin
  mList := Nodes;
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, TAtlasCrumbRequest.Create(24, 4, '', False, []));
  Assert.AreEqual('TfrmKunde › btnSpeichernClick › Pruefe', Joined(mCrumbs));
  // Typ: alle Mitglieder in Quelltextreihenfolge.
  Assert.AreEqual('btnSpeichern,btnSpeichernClick,SpeichereAdresse,SpaltenBreite,Display,TInner',
    NamesOf(mList, mCrumbs[0].Children));
  // Methode (Deklaration im Typ): die lokalen Routinen ihres Rumpfs.
  Assert.AreEqual('Pruefe,Melde', NamesOf(mList, mCrumbs[1].Children));
  // Lokale Routine ohne eigene lokale Routinen.
  Assert.AreEqual(0, Integer(Length(mCrumbs[2].Children)));
  // Verschachtelter Typ.
  Assert.AreEqual('Tief', NamesOf(mList, TAtlasBreadcrumbs.Children(mList, Find(mList, 'TInner'))));
  // Methode ohne lokale Routinen, ungültiger Knoten.
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.Children(mList, Find(mList, 'SpaltenBreite')))));
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.Children(mList, -1))));
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.Children(mList, Length(mList)))));
end;

procedure TAtlasBreadcrumbsTests.RoutinesForFindMethod;
var
  mList: TAtlasOutlineNodes;
  mItem: Integer;
  mNames: string;
begin
  mList := Nodes;
  // „Methode suchen“ der Editorleiste (#1101): Methoden mit Besitzer, Routinen, keine lokalen Routinen und
  // keine Rümpfe doppelt.
  mNames := '';
  for mItem in TAtlasBreadcrumbs.Routines(mList) do
  begin
    if mNames <> '' then
    begin
      mNames := mNames + ',';
    end;
    mNames := mNames + TAtlasBreadcrumbs.QualifiedName(mList, mItem);
  end;
  Assert.AreEqual('TfrmKunde.btnSpeichernClick,TfrmKunde.SpeichereAdresse,TfrmKunde.SpaltenBreite,' +
    'TfrmKunde.Display,TfrmKunde.TInner.Tief,Hilfe', mNames);
  Assert.AreEqual('', TAtlasBreadcrumbs.QualifiedName(mList, -1));
  Assert.AreEqual('TAndere', TAtlasBreadcrumbs.QualifiedName(mList, Find(mList, 'TAndere')));
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.Routines(nil))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreadcrumbsTests);

end.
