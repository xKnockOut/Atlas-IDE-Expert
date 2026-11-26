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
    [Test]
    procedure RoutinesForFindMethodWithNestedLocalRoutines;
    [Test]
    procedure RoutineAtFindsTheInnermostRoutine;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Plugin.Style.Palette,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.Outline.CrumbMenu,
  Atlas.Core.Outline.TestSupport;

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

  /// <summary>Lokale Routinen in zwei Ebenen, in einer Methode und in einer freien Routine.</summary>
  cLocalCode =
    'unit uLokal;'#13#10 +                    // 0
    'interface'#13#10 +                       // 1
    'type'#13#10 +                            // 2
    '  TFoo = class'#13#10 +                  // 3
    '    procedure Bar;'#13#10 +              // 4
    '  end;'#13#10 +                          // 5
    'implementation'#13#10 +                  // 6
    'procedure TFoo.Bar;'#13#10 +             // 7
    '  procedure Aussen;'#13#10 +             // 8
    '    function Innen: Integer;'#13#10 +    // 9
    '    begin'#13#10 +                       // 10
    '      Result := 1;'#13#10 +              // 11
    '    end;'#13#10 +                        // 12
    '  begin'#13#10 +                         // 13
    '    Innen;'#13#10 +                      // 14
    '  end;'#13#10 +                          // 15
    'begin'#13#10 +                           // 16
    '  Aussen;'#13#10 +                       // 17
    'end;'#13#10 +                            // 18
    'procedure Frei;'#13#10 +                 // 19
    '  procedure Hilf; begin end;'#13#10 +    // 20
    'begin'#13#10 +                           // 21
    '  Hilf;'#13#10 +                         // 22
    'end;'#13#10 +                            // 23
    'end.';                                   // 24

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

function Nodes: TAtlasOutlineNodes;
begin
  Result := TOutlineTest.NodesOf(cCode);
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

/// <summary>Namen der Routinen für „Methode suchen“, durch Komma getrennt.</summary>
function RoutineNamesOf(const ANodes: TAtlasOutlineNodes): string;
var
  mItem: Integer;
begin
  Result := '';
  for mItem in TAtlasBreadcrumbs.Routines(ANodes) do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + TAtlasBreadcrumbs.RoutineName(ANodes, mItem);
  end;
end;

/// <summary>Name der innersten Routine an Zeile ALine von cLocalCode; leer ohne.</summary>
function RoutineNameAt(const ANodes: TAtlasOutlineNodes; ALine: Integer): string;
begin
  Result := TAtlasBreadcrumbs.RoutineName(ANodes, TAtlasBreadcrumbs.RoutineAt(ANodes,
    TAtlasBreadcrumbs.Routines(ANodes), ALine));
end;

{ TAtlasBreadcrumbsTests }

procedure TAtlasBreadcrumbsTests.PathInLocalProcedureOfMethod;
var
  mList: TAtlasOutlineNodes;
  mCrumbs: TAtlasCrumbs;
begin
  mList := Nodes;
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, TAtlasCrumbRequest.Create(24, 4, 'uKundeForm', True, []));
  Assert.AreEqual('uKundeForm › TfrmKunde › btnSpeichernClick › Pruefe', TAtlasCrumbMenu.PathOf(mCrumbs));
  Assert.AreEqual<TAtlasBadgeKind>(TAtlasBadgeKind.Unit_, mCrumbs[0].Badge.Kind);
  // Unit-Glied: alle Elemente der Unit-Ebene als Menü und als Kinder.
  Assert.AreEqual('TfrmKunde,TAndere,Limit,Hilfe', NamesOf(mList, mCrumbs[0].Siblings));
  Assert.AreEqual('TfrmKunde,TAndere,Limit,Hilfe', NamesOf(mList, mCrumbs[0].Children));
  // Das Glied der Methode ist die Deklaration im Typ.
  Assert.AreEqual(8, mList[mCrumbs[2].Node].StartLine);
  // Ohne Unit-Namen (Vorgabe).
  Assert.AreEqual('TfrmKunde › btnSpeichernClick', TAtlasCrumbMenu.PathOf(TAtlasBreadcrumbs.Path(mList, Lines,
    TAtlasCrumbRequest.Create(28, 2, 'uKundeForm', False, []))));
end;

procedure TAtlasBreadcrumbsTests.PathInInterfaceEndsAtMember;
begin
  Assert.AreEqual('TfrmKunde › SpeichereAdresse', TAtlasCrumbMenu.PathOf(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(10, 8, '', False, []))));
  Assert.AreEqual('TfrmKunde › btnSpeichern', TAtlasCrumbMenu.PathOf(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(7, 6, '', False, []))));
  Assert.AreEqual('Limit', TAtlasCrumbMenu.PathOf(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(20, 7, '', False, []))));
end;

procedure TAtlasBreadcrumbsTests.PathThroughNestedTypes;
begin
  Assert.AreEqual('TfrmKunde › TInner › Tief', TAtlasCrumbMenu.PathOf(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(16, 12, '', False, []))));
  Assert.AreEqual('TfrmKunde › TInner › Tief', TAtlasCrumbMenu.PathOf(TAtlasBreadcrumbs.Path(Nodes, Lines,
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
  Assert.AreEqual('U › uses', TAtlasCrumbMenu.PathOf(TAtlasBreadcrumbs.Path(Nodes, mText,
    TAtlasCrumbRequest.Create(3, 4, 'U', True, []))));
  Assert.AreEqual('initialization', TAtlasCrumbMenu.PathOf(TAtlasBreadcrumbs.Path(Nodes, mText,
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
  Assert.AreEqual(Integer(Length(mText)), Integer(Length(mTable)));
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
    mList := TOutlineTest.NodesOf(mSource);
    mPrepared := TAtlasBreadcrumbs.Prepare(mList, mText);
    for mLine := 0 to Length(mText) do
    begin
      for mCharacter in [0, 4, 12] do
      begin
        mExpected := TAtlasBreadcrumbs.Path(mList, mText, TAtlasCrumbRequest.Create(mLine, mCharacter, 'U', True, cAll));
        mActual := TAtlasBreadcrumbs.Path(mPrepared, TAtlasCrumbRequest.Create(mLine, mCharacter, 'U', True, cAll));
        Assert.AreEqual(TAtlasCrumbMenu.PathOf(mExpected), TAtlasCrumbMenu.PathOf(mActual),
          Format('Zeile %d, Spalte %d', [mLine, mCharacter]));
      end;
    end;
  end;
  mText := cDirectiveCode.Split([#13#10]);
  Assert.AreEqual('U › Rümpfe › TKunde › Speichere › {$IFDEF DEBUG}',
    TAtlasCrumbMenu.PathOf(TAtlasBreadcrumbs.Path(TAtlasBreadcrumbs.Prepare(TOutlineTest.NodesOf(cDirectiveCode), mText),
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
  Assert.AreEqual('Hilfe', TAtlasCrumbMenu.PathOf(mCrumbs));
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
  mDeclaration := TOutlineTest.Find(mList, 'SpaltenBreite');
  Assert.AreEqual(31, mList[TAtlasBreadcrumbs.Target(mList, mDeclaration, True)].StartLine);
  Assert.AreEqual(mDeclaration, TAtlasBreadcrumbs.Target(mList, mDeclaration, False));
  // Rumpf → Deklaration.
  Assert.AreEqual(mDeclaration, TAtlasBreadcrumbs.Target(mList, mList[mDeclaration].Body, False));
  // Lokale Routine: sie selbst.
  Assert.AreEqual(TOutlineTest.Find(mList, 'Pruefe'), TAtlasBreadcrumbs.Target(mList, TOutlineTest.Find(mList, 'Pruefe'), True));
  Assert.AreEqual(-1, TAtlasBreadcrumbs.Target(mList, -1, True));
end;

procedure TAtlasBreadcrumbsTests.BadgesFollowTheHeader;
var
  mList: TAtlasOutlineNodes;
  mText: TArray<string>;
begin
  mList := Nodes;
  mText := Lines;
  Assert.AreEqual('pr', TAtlasBreadcrumbs.BadgeOf(mList, mText, TOutlineTest.Find(mList, 'SpeichereAdresse')).Code);
  Assert.AreEqual('fn', TAtlasBreadcrumbs.BadgeOf(mList, mText, TOutlineTest.Find(mList, 'SpaltenBreite')).Code);
  Assert.AreEqual('ty', TAtlasBreadcrumbs.BadgeOf(mList, mText, TOutlineTest.Find(mList, 'TfrmKunde')).Code);
  Assert.AreEqual('fd', TAtlasBreadcrumbs.BadgeOf(mList, mText, TOutlineTest.Find(mList, 'btnSpeichern')).Code);
  Assert.AreEqual('co', TAtlasBreadcrumbs.BadgeOf(mList, mText, TOutlineTest.Find(mList, 'Limit')).Code);
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
  Assert.AreEqual('U › uses', TAtlasCrumbMenu.PathOf(mCrumbs));
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
  Assert.AreEqual('TfrmKunde › btnSpeichernClick › Pruefe', TAtlasCrumbMenu.PathOf(mCrumbs));
  // Typ: alle Mitglieder in Quelltextreihenfolge.
  Assert.AreEqual('btnSpeichern,btnSpeichernClick,SpeichereAdresse,SpaltenBreite,Display,TInner',
    NamesOf(mList, mCrumbs[0].Children));
  // Methode (Deklaration im Typ): die lokalen Routinen ihres Rumpfs.
  Assert.AreEqual('Pruefe,Melde', NamesOf(mList, mCrumbs[1].Children));
  // Lokale Routine ohne eigene lokale Routinen.
  Assert.AreEqual(0, Integer(Length(mCrumbs[2].Children)));
  // Verschachtelter Typ.
  Assert.AreEqual('Tief', NamesOf(mList, TAtlasBreadcrumbs.Children(mList, TOutlineTest.Find(mList, 'TInner'))));
  // Methode ohne lokale Routinen, ungültiger Knoten.
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.Children(mList, TOutlineTest.Find(mList, 'SpaltenBreite')))));
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.Children(mList, -1))));
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.Children(mList, Length(mList)))));
end;

procedure TAtlasBreadcrumbsTests.RoutinesForFindMethod;
var
  mList: TAtlasOutlineNodes;
begin
  mList := Nodes;
  // „Methode suchen“ der Editorleiste (#1101): Methoden mit Besitzer, Routinen, lokale Routinen hinter ihrer
  // Methode und keine Rümpfe doppelt.
  Assert.AreEqual('TfrmKunde.btnSpeichernClick,TfrmKunde.btnSpeichernClick › Pruefe,' +
    'TfrmKunde.btnSpeichernClick › Melde,TfrmKunde.SpeichereAdresse,TfrmKunde.SpaltenBreite,' +
    'TfrmKunde.Display,TfrmKunde.TInner.Tief,Hilfe', RoutineNamesOf(mList));
  // QualifiedName bleibt ohne Routine davor (Brotkrumen, Statusleiste).
  Assert.AreEqual('Pruefe', TAtlasBreadcrumbs.QualifiedName(mList, TOutlineTest.Find(mList, 'Pruefe')));
  Assert.AreEqual('', TAtlasBreadcrumbs.QualifiedName(mList, -1));
  Assert.AreEqual('TAndere', TAtlasBreadcrumbs.QualifiedName(mList, TOutlineTest.Find(mList, 'TAndere')));
  Assert.AreEqual(0, Integer(Length(TAtlasBreadcrumbs.Routines(nil))));
end;

procedure TAtlasBreadcrumbsTests.RoutinesForFindMethodWithNestedLocalRoutines;
begin
  Assert.AreEqual('TFoo.Bar,TFoo.Bar › Aussen,TFoo.Bar › Aussen › Innen,Frei,Frei › Hilf',
    RoutineNamesOf(TOutlineTest.NodesOf(cLocalCode)));
end;

procedure TAtlasBreadcrumbsTests.RoutineAtFindsTheInnermostRoutine;
var
  mList: TAtlasOutlineNodes;
begin
  mList := TOutlineTest.NodesOf(cLocalCode);
  Assert.AreEqual('TFoo.Bar › Aussen › Innen', RoutineNameAt(mList, 11));
  Assert.AreEqual('TFoo.Bar › Aussen', RoutineNameAt(mList, 14));
  Assert.AreEqual('TFoo.Bar', RoutineNameAt(mList, 17));
  Assert.AreEqual('TFoo.Bar', RoutineNameAt(mList, 4), 'Deklaration in der Klasse');
  Assert.AreEqual('Frei › Hilf', RoutineNameAt(mList, 20));
  Assert.AreEqual('Frei', RoutineNameAt(mList, 22));
  Assert.AreEqual(-1, TAtlasBreadcrumbs.RoutineAt(mList, TAtlasBreadcrumbs.Routines(mList), 2), 'Typ');
  Assert.AreEqual(-1, TAtlasBreadcrumbs.RoutineAt(mList, nil, 11), 'ohne Routinen');
  Assert.AreEqual(-1, TAtlasBreadcrumbs.RoutineAt(mList, [Length(mList)], 11), 'ungültiger Knoten');
  Assert.AreEqual('', TAtlasBreadcrumbs.RoutineName(mList, -1));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreadcrumbsTests);

end.
