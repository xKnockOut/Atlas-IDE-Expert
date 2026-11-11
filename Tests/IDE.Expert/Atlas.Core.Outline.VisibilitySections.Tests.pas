unit Atlas.Core.Outline.VisibilitySections.Tests;

// Sichtbarkeitsabschnitt in der Brotkrumenleiste (#1759): Abschnitt am Caret
// auch zwischen den Mitgliedern, verschachtelte Typen, implizite Sichtbarkeit,
// Typen ohne Abschnitte und das Glied im Pfad. Sichtbarkeitsmarke am
// Methodenglied im implementation-Teil (#1765).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasVisibilitySectionsTests = class
  public
    [Test]
    procedure SectionsInSourceOrder;
    [Test]
    procedure SectionBetweenMembersAndOnKeywordLine;
    [Test]
    procedure NestedTypeHasItsOwnSections;
    [Test]
    procedure ImplicitVisibility;
    [Test]
    procedure NoSectionsOutsideClassLikeTypes;
    [Test]
    procedure HelpersHaveSections;
    [Test]
    procedure MembersOfASection;
    [Test]
    procedure PathShowsSectionBehindType;
    [Test]
    procedure PathWithoutSettingIsUnchanged;
    [Test]
    procedure MarkOnMethodBodies;
    [Test]
    procedure NoMarkOutsideMethodsOfTheUnit;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.Outline.VisibilitySections;

const
  cCode =
    'unit uSicht;'#13#10 +                                   // 0
    'interface'#13#10 +                                      // 1
    'type'#13#10 +                                           // 2
    '  TVorwaerts = class;'#13#10 +                          // 3
    '  TKunde = class(TForm)'#13#10 +                        // 4
    '    btnOk: TButton;'#13#10 +                            // 5
    '  strict private'#13#10 +                               // 6
    '    FName: string;'#13#10 +                             // 7
    '    // public im Kommentar'#13#10 +                     // 8
    ''#13#10 +                                               // 9
    '  private'#13#10 +                                      // 10
    '    FAlter: Integer;'#13#10 +                           // 11
    '  public'#13#10 +                                       // 12
    '    type'#13#10 +                                       // 13
    '      TInnen = record'#13#10 +                          // 14
    '      private'#13#10 +                                  // 15
    '        FWert: Integer;'#13#10 +                        // 16
    '      public'#13#10 +                                   // 17
    '        Wert: Integer;'#13#10 +                         // 18
    '      end;'#13#10 +                                     // 19
    '    procedure Speichere(const ATitel: string = ''public'');'#13#10 + // 20
    '  published'#13#10 +                                    // 21
    '    property Name: string read FName;'#13#10 +          // 22
    '  end;'#13#10 +                                         // 23
    '  TEinfach = class'#13#10 +                             // 24
    '    FZahl: Integer;'#13#10 +                            // 25
    '  protected'#13#10 +                                    // 26
    '    procedure Tue;'#13#10 +                             // 27
    '  end;'#13#10 +                                         // 28
    '  IDienst = interface'#13#10 +                          // 29
    '    procedure Rufe;'#13#10 +                            // 30
    '  end;'#13#10 +                                         // 31
    '  TErbe = class(TKunde)'#13#10 +                        // 32
    '    FZ: Integer;'#13#10 +                               // 33
    '  end;'#13#10 +                                         // 34
    '  TAbgeleitet = class(TEinfach)'#13#10 +                // 35
    '    FX: Integer;'#13#10 +                               // 36
    '  end;'#13#10 +                                         // 37
    '  {$M+}'#13#10 +                                        // 38
    '  TMitInfo = class'#13#10 +                             // 39
    '    FY: Integer;'#13#10 +                               // 40
    '  end;'#13#10 +                                         // 41
    '  {$M-}'#13#10 +                                        // 42
    '  TPunkt = record'#13#10 +                              // 43
    '    X: Integer;'#13#10 +                                // 44
    '  end;'#13#10 +                                         // 45
    'implementation'#13#10 +                                 // 46
    'procedure TKunde.Speichere(const ATitel: string);'#13#10 + // 47
    'begin'#13#10 +                                          // 48
    'end;'#13#10 +                                           // 49
    'procedure TEinfach.Tue; begin end;'#13#10 +             // 50
    'end.';                                                  // 51

function Lines: TArray<string>;
begin
  Result := cCode.Split([#13#10]);
end;

function NodesOf(const ACode: string): TAtlasOutlineNodes;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(ACode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, ACode);
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

function Keywords(const ASections: TAtlasVisibilitySections): string;
var
  mSection: TAtlasVisibilitySection;
begin
  Result := '';
  for mSection in ASections do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mSection.Keyword + '@' + IntToStr(mSection.Line);
  end;
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
    Result := Result + ANodes[mItem].Name;
  end;
end;

function CurrentKeyword(ALine, ACharacter: Integer): string;
var
  mPlace: TAtlasVisibilityPlace;
begin
  mPlace := TAtlasVisibilitySectionFinder.At(Nodes, Lines, ALine, ACharacter);
  if mPlace.TypeNode < 0 then
  begin
    Exit('-');
  end;
  if mPlace.Current < 0 then
  begin
    Exit('(' + mPlace.Implicit + ')');
  end;
  Result := mPlace.Sections[mPlace.Current].Keyword;
end;

procedure TAtlasVisibilitySectionsTests.SectionsInSourceOrder;
var
  mList: TAtlasOutlineNodes;
begin
  mList := Nodes;
  // Die Abschnitte des inneren Records, „public“ im Kommentar und im String zählen nicht.
  Assert.AreEqual('strict private@6,private@10,public@12,published@21',
    Keywords(TAtlasVisibilitySectionFinder.SectionsOf(mList, Lines, Find(mList, 'TKunde'))));
  Assert.AreEqual(0, Integer(Length(TAtlasVisibilitySectionFinder.SectionsOf(mList, Lines, -1))));
end;

procedure TAtlasVisibilitySectionsTests.SectionBetweenMembersAndOnKeywordLine;
begin
  Assert.AreEqual('strict private', CurrentKeyword(7, 6));
  Assert.AreEqual('strict private', CurrentKeyword(8, 4), 'Kommentarzeile');
  Assert.AreEqual('strict private', CurrentKeyword(9, 0), 'Leerzeile');
  Assert.AreEqual('private', CurrentKeyword(10, 0), 'Zeile des Schlüsselworts, vor dem Wort');
  Assert.AreEqual('public', CurrentKeyword(20, 6));
  Assert.AreEqual('published', CurrentKeyword(22, 6));
end;

procedure TAtlasVisibilitySectionsTests.NestedTypeHasItsOwnSections;
var
  mList: TAtlasOutlineNodes;
  mPlace: TAtlasVisibilityPlace;
begin
  mList := Nodes;
  mPlace := TAtlasVisibilitySectionFinder.At(mList, Lines, 16, 8);
  Assert.AreEqual(Find(mList, 'TInnen'), mPlace.TypeNode);
  Assert.AreEqual('private@15,public@17', Keywords(mPlace.Sections));
  Assert.AreEqual('private', CurrentKeyword(16, 8));
  Assert.AreEqual('public', CurrentKeyword(18, 8));
  // Kopfzeile des verschachtelten Typs: Abschnitt des umgebenden.
  Assert.AreEqual('public', CurrentKeyword(14, 8));
end;

procedure TAtlasVisibilitySectionsTests.ImplicitVisibility;
begin
  // Von TForm abgeleitet: published.
  Assert.AreEqual('(published)', CurrentKeyword(5, 4));
  // Über einen Vorfahren derselben Unit von TForm abgeleitet.
  Assert.AreEqual('(published)', CurrentKeyword(33, 4));
  // Ohne TPersistent: public, auch über einen Vorfahren der Unit.
  Assert.AreEqual('(public)', CurrentKeyword(25, 4));
  Assert.AreEqual('(public)', CurrentKeyword(36, 4));
  // {$M+} vor der Klasse.
  Assert.AreEqual('(published)', CurrentKeyword(40, 4));
  // Record.
  Assert.AreEqual('(public)', CurrentKeyword(44, 4));
end;

procedure TAtlasVisibilitySectionsTests.NoSectionsOutsideClassLikeTypes;
begin
  Assert.AreEqual('-', CurrentKeyword(30, 4), 'Interface');
  Assert.AreEqual('-', CurrentKeyword(3, 6), 'Vorwärtsdeklaration');
  Assert.AreEqual('-', CurrentKeyword(4, 6), 'Kopfzeile des Typs');
  Assert.AreEqual('-', CurrentKeyword(48, 0), 'Methodenrumpf');
  Assert.AreEqual('-', CurrentKeyword(1, 0), 'außerhalb jedes Typs');
end;

procedure TAtlasVisibilitySectionsTests.HelpersHaveSections;
const
  cHelpers =
    'unit uHelfer;'#13#10 +                                  // 0
    'interface'#13#10 +                                      // 1
    'type'#13#10 +                                           // 2
    '  TTextHelfer = record helper for string'#13#10 +       // 3
    '    function Laenge: Integer;'#13#10 +                  // 4
    '  private'#13#10 +                                      // 5
    '    function Intern: Integer;'#13#10 +                  // 6
    '  end;'#13#10 +                                         // 7
    '  TListHelfer = class helper for TList'#13#10 +         // 8
    '    procedure Leeren;'#13#10 +                          // 9
    '  end;'#13#10 +                                         // 10
    'implementation'#13#10 +                                 // 11
    'end.';                                                  // 12
var
  mList: TAtlasOutlineNodes;
  mLines: TArray<string>;
  mPlace: TAtlasVisibilityPlace;
begin
  mList := NodesOf(cHelpers);
  mLines := cHelpers.Split([#13#10]);
  mPlace := TAtlasVisibilitySectionFinder.At(mList, mLines, 6, 6);
  Assert.AreEqual(Find(mList, 'TTextHelfer'), mPlace.TypeNode);
  Assert.AreEqual('private@5', Keywords(mPlace.Sections));
  Assert.AreEqual(0, mPlace.Current);
  mPlace := TAtlasVisibilitySectionFinder.At(mList, mLines, 9, 6);
  Assert.AreEqual(Find(mList, 'TListHelfer'), mPlace.TypeNode);
  Assert.AreEqual(-1, mPlace.Current);
  Assert.AreEqual('public', mPlace.Implicit);
end;

procedure TAtlasVisibilitySectionsTests.MembersOfASection;
var
  mList: TAtlasOutlineNodes;
  mPlace: TAtlasVisibilityPlace;
begin
  mList := Nodes;
  mPlace := TAtlasVisibilitySectionFinder.At(mList, Lines, 7, 4);
  Assert.AreEqual('btnOk', NamesOf(mList, TAtlasVisibilitySectionFinder.MembersOf(mList, mPlace, -1)));
  Assert.AreEqual('FName', NamesOf(mList, TAtlasVisibilitySectionFinder.MembersOf(mList, mPlace, 0)));
  Assert.AreEqual('TInnen,Speichere', NamesOf(mList, TAtlasVisibilitySectionFinder.MembersOf(mList, mPlace, 2)));
  Assert.AreEqual('Name', NamesOf(mList, TAtlasVisibilitySectionFinder.MembersOf(mList, mPlace, 3)));
  Assert.AreEqual(0, Integer(Length(TAtlasVisibilitySectionFinder.MembersOf(mList, mPlace, 4))));
end;

procedure TAtlasVisibilitySectionsTests.PathShowsSectionBehindType;
var
  mList: TAtlasOutlineNodes;
  mCrumbs: TAtlasCrumbs;
begin
  mList := Nodes;
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, 7, 6, '', False, [TAtlasCrumbPart.Visibility]);
  Assert.AreEqual('TKunde › strict private › FName', Joined(mCrumbs));
  Assert.AreEqual('kw', mCrumbs[1].Badge.Code);
  Assert.AreEqual(-1, mCrumbs[1].Node);
  Assert.IsFalse(mCrumbs[1].Implicit);
  Assert.AreEqual(4, Integer(Length(mCrumbs[1].Places)));
  Assert.AreEqual(0, mCrumbs[1].Current);
  Assert.AreEqual(6, mCrumbs[1].Places[0].Line);
  Assert.AreEqual(2, mCrumbs[1].Places[0].Character);
  Assert.IsTrue(TAtlasBreadcrumbs.HasMenu(mCrumbs[1]));
  Assert.AreEqual('FName', NamesOf(mList, mCrumbs[1].Children));
  // Leerzeile: der Abschnitt ist das letzte Glied.
  Assert.AreEqual('TKunde › strict private', Joined(TAtlasBreadcrumbs.Path(mList, Lines, 9, 0, '', False, [TAtlasCrumbPart.Visibility])));
  // Verschachtelt: Es zählt der innerste Typ.
  Assert.AreEqual('TKunde › TInnen › private › FWert',
    Joined(TAtlasBreadcrumbs.Path(mList, Lines, 16, 9, '', False, [TAtlasCrumbPart.Visibility])));
  // Implizit: kursiv, ohne aktuellen Abschnitt.
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, 5, 6, '', False, [TAtlasCrumbPart.Visibility]);
  Assert.AreEqual('TKunde › published › btnOk', Joined(mCrumbs));
  Assert.IsTrue(mCrumbs[1].Implicit);
  Assert.AreEqual(-1, mCrumbs[1].Current);
  // Interface und Methodenrumpf: kein Abschnittsglied.
  Assert.AreEqual('IDienst › Rufe', Joined(TAtlasBreadcrumbs.Path(mList, Lines, 30, 6, '', False, [TAtlasCrumbPart.Visibility])));
  Assert.AreEqual('TKunde › Speichere', Joined(TAtlasBreadcrumbs.Path(mList, Lines, 48, 0, '', False, [TAtlasCrumbPart.Visibility])));
end;

procedure TAtlasVisibilitySectionsTests.PathWithoutSettingIsUnchanged;
var
  mCrumbs: TAtlasCrumbs;
begin
  mCrumbs := TAtlasBreadcrumbs.Path(Nodes, Lines, 7, 6, '', False, []);
  Assert.AreEqual('TKunde › FName', Joined(mCrumbs));
  Assert.IsFalse(TAtlasBreadcrumbs.HasMenu(Default(TAtlasCrumb)));
end;

const
  cMarks =
    'unit uMarke;'#13#10 +                                   // 0
    'interface'#13#10 +                                      // 1
    'type'#13#10 +                                           // 2
    '  TKonto = class'#13#10 +                               // 3
    '    procedure Ohne;'#13#10 +                            // 4
    '  strict private'#13#10 +                               // 5
    '    procedure Geheim;'#13#10 +                          // 6
    '  protected'#13#10 +                                    // 7
    '    function Schutz: Integer;'#13#10 +                  // 8
    '  public'#13#10 +                                       // 9
    '    class procedure Erzeuge;'#13#10 +                   // 10
    '    type'#13#10 +                                       // 11
    '      TInnen = class'#13#10 +                           // 12
    '      private'#13#10 +                                  // 13
    '        procedure Tief;'#13#10 +                        // 14
    '      end;'#13#10 +                                     // 15
    '  published'#13#10 +                                    // 16
    '    procedure Klick;'#13#10 +                           // 17
    '  end;'#13#10 +                                         // 18
    'procedure Frei;'#13#10 +                                // 19
    'implementation'#13#10 +                                 // 20
    'procedure TKonto.Ohne;'#13#10 +                         // 21
    'begin'#13#10 +                                          // 22
    'end;'#13#10 +                                           // 23
    'procedure TKonto.Geheim;'#13#10 +                       // 24
    '  procedure Lokal;'#13#10 +                             // 25
    '  begin'#13#10 +                                        // 26
    '  end;'#13#10 +                                         // 27
    'begin'#13#10 +                                          // 28
    'end;'#13#10 +                                           // 29
    'function TKonto.Schutz: Integer;'#13#10 +               // 30
    'begin'#13#10 +                                          // 31
    'end;'#13#10 +                                           // 32
    'class procedure TKonto.Erzeuge;'#13#10 +                // 33
    'begin'#13#10 +                                          // 34
    'end;'#13#10 +                                           // 35
    'procedure TKonto.TInnen.Tief;'#13#10 +                  // 36
    'begin'#13#10 +                                          // 37
    'end;'#13#10 +                                           // 38
    'procedure TKonto.Klick;'#13#10 +                        // 39
    'begin'#13#10 +                                          // 40
    'end;'#13#10 +                                           // 41
    'procedure Frei;'#13#10 +                                // 42
    'begin'#13#10 +                                          // 43
    'end;'#13#10 +                                           // 44
    'procedure TFremd.Tue;'#13#10 +                          // 45
    'begin'#13#10 +                                          // 46
    'end;'#13#10 +                                           // 47
    'end.';                                                  // 48

/// <summary>Letztes Glied des Pfads an ALine/ACharacter von cMarks als „Marke Text (Sichtbarkeit@Zeile)“.</summary>
function LastMarked(ALine: Integer; ACharacter: Integer = 0;
  AParts: TAtlasCrumbParts = [TAtlasCrumbPart.VisibilityMark]): string;
var
  mCrumbs: TAtlasCrumbs;
  mLast: TAtlasCrumb;
begin
  mCrumbs := TAtlasBreadcrumbs.Path(NodesOf(cMarks), cMarks.Split([#13#10]), ALine, ACharacter, '', False,
    AParts);
  if Length(mCrumbs) = 0 then
  begin
    Exit('');
  end;
  mLast := mCrumbs[High(mCrumbs)];
  Result := mLast.Text;
  if mLast.Mark <> '' then
  begin
    Result := mLast.Mark + ' ' + Result + ' (' + mLast.MarkVisibility + '@' + IntToStr(mLast.MarkLine) + ')';
  end
  else
  begin
    Assert.AreEqual(-1, mLast.MarkLine, 'ohne Marke keine Zeile');
  end;
end;

procedure TAtlasVisibilitySectionsTests.MarkOnMethodBodies;
begin
  // Vor dem ersten Schlüsselwort: implizite Sichtbarkeit.
  Assert.AreEqual('+ Ohne (public@4)', LastMarked(22));
  Assert.AreEqual('− Geheim (strict private@6)', LastMarked(28));
  Assert.AreEqual('# Schutz (protected@8)', LastMarked(31));
  // Klassenmethode wie normale Methode.
  Assert.AreEqual('+ Erzeuge (public@10)', LastMarked(34));
  // Methode eines verschachtelten Typs: dessen Abschnitt.
  Assert.AreEqual('− Tief (private@14)', LastMarked(37));
  Assert.AreEqual('◆ Klick (published@17)', LastMarked(40));
  // Nur das Methodenglied trägt die Marke.
  Assert.AreEqual('', TAtlasBreadcrumbs.Path(NodesOf(cMarks), cMarks.Split([#13#10]), 37, 0, '', False,
    [TAtlasCrumbPart.VisibilityMark])[0].Mark);
end;

procedure TAtlasVisibilitySectionsTests.NoMarkOutsideMethodsOfTheUnit;
begin
  // Lokale Prozedur, Routine ohne Klasse, Klasse aus einer anderen Unit.
  Assert.AreEqual('Lokal', LastMarked(26));
  Assert.AreEqual('Frei', LastMarked(43));
  Assert.AreEqual('Tue', LastMarked(46));
  // Deklarationsteil: keine Marke.
  Assert.AreEqual('Geheim', LastMarked(6, 15));
  // Ausgeschaltet: Leiste wie bisher.
  Assert.AreEqual('Geheim', LastMarked(28, 0, []));
  Assert.AreEqual('Geheim', LastMarked(28, 0, [TAtlasCrumbPart.Visibility, TAtlasCrumbPart.MemberBlocks]));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVisibilitySectionsTests);

end.
