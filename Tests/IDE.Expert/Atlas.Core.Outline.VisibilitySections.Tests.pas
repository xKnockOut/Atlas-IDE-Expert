unit Atlas.Core.Outline.VisibilitySections.Tests;

// Sichtbarkeitsabschnitt in der Brotkrumenleiste (#1759): Abschnitt am Caret
// auch zwischen den Mitgliedern, verschachtelte Typen, implizite Sichtbarkeit,
// Typen ohne Abschnitte und das Glied im Pfad.

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
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, 7, 6, '', False, True);
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
  Assert.AreEqual('TKunde › strict private', Joined(TAtlasBreadcrumbs.Path(mList, Lines, 9, 0, '', False, True)));
  // Verschachtelt: Es zählt der innerste Typ.
  Assert.AreEqual('TKunde › TInnen › private › FWert',
    Joined(TAtlasBreadcrumbs.Path(mList, Lines, 16, 9, '', False, True)));
  // Implizit: kursiv, ohne aktuellen Abschnitt.
  mCrumbs := TAtlasBreadcrumbs.Path(mList, Lines, 5, 6, '', False, True);
  Assert.AreEqual('TKunde › published › btnOk', Joined(mCrumbs));
  Assert.IsTrue(mCrumbs[1].Implicit);
  Assert.AreEqual(-1, mCrumbs[1].Current);
  // Interface und Methodenrumpf: kein Abschnittsglied.
  Assert.AreEqual('IDienst › Rufe', Joined(TAtlasBreadcrumbs.Path(mList, Lines, 30, 6, '', False, True)));
  Assert.AreEqual('TKunde › Speichere', Joined(TAtlasBreadcrumbs.Path(mList, Lines, 48, 0, '', False, True)));
end;

procedure TAtlasVisibilitySectionsTests.PathWithoutSettingIsUnchanged;
var
  mCrumbs: TAtlasCrumbs;
begin
  mCrumbs := TAtlasBreadcrumbs.Path(Nodes, Lines, 7, 6, '', False);
  Assert.AreEqual('TKunde › FName', Joined(mCrumbs));
  Assert.IsFalse(TAtlasBreadcrumbs.HasMenu(Default(TAtlasCrumb)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVisibilitySectionsTests);

end.
