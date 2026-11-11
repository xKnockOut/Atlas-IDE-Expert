unit Atlas.Core.Outline.SectionEdit.Tests;

// Neue Zeile am Ende eines Abschnitts und Abschnitt anlegen (#1768): hinter
// dem letzten Mitglied, Kommentare bleiben darunter, leerer Abschnitt,
// übliche Reihenfolge, Records, verschachtelte Typen, Mitgliederzahl im
// Sprungmenü.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSectionEditTests = class
  public
    [Test]
    procedure AppendBehindLastMember;
    [Test]
    procedure AppendIntoEmptySection;
    [Test]
    procedure MissingInOrder;
    [Test]
    procedure AddBetweenSections;
    [Test]
    procedure AddAtEndOfType;
    [Test]
    procedure RecordAndNestedType;
    [Test]
    procedure SingleLineTypeIsLeftAlone;
    [Test]
    procedure PlacesCarryCountAndMark;
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
  Atlas.Core.Outline.VisibilitySections,
  Atlas.Core.Outline.SectionEdit;

const
  cCode =
    'unit uKunden;'#13#10 +                                  // 0
    'interface'#13#10 +                                      // 1
    'type'#13#10 +                                           // 2
    '  TKunde = class'#13#10 +                               // 3
    '  private'#13#10 +                                      // 4
    '    FName: string;'#13#10 +                             // 5
    '    procedure Pruefe(A: Integer;'#13#10 +               // 6
    '      B: Integer);'#13#10 +                             // 7
    '    // Kommentar am Ende'#13#10 +                       // 8
    ''#13#10 +                                               // 9
    '  public'#13#10 +                                       // 10
    '  published'#13#10 +                                    // 11
    '    property Name: string read FName;'#13#10 +          // 12
    '  end;'#13#10 +                                         // 13
    '  TPunkt = record'#13#10 +                              // 14
    '    X: Integer;'#13#10 +                                // 15
    '  public'#13#10 +                                       // 16
    '    type'#13#10 +                                       // 17
    '      TInnen = class'#13#10 +                           // 18
    '        FWert: Integer;'#13#10 +                        // 19
    '      end;'#13#10 +                                     // 20
    '  end;'#13#10 +                                         // 21
    '  TKurz = class private F: Integer; end;'#13#10 +       // 22
    'implementation'#13#10 +                                 // 23
    'end.';                                                  // 24

function Lines: TArray<string>;
begin
  Result := cCode.Split([#13#10]);
end;

function Nodes: TAtlasOutlineNodes;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(cCode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, cCode);
  finally
    mTree.Free;
  end;
  try
    Result := TAtlasOutline.FromJson(mSymbols);
  finally
    mSymbols.Free;
  end;
end;

function PlaceAt(ALine, ACharacter: Integer): TAtlasVisibilityPlace;
begin
  Result := TAtlasVisibilitySectionFinder.At(Nodes, Lines, ALine, ACharacter);
end;

function Joined(const AEdit: TAtlasSectionEdit): string;
begin
  Result := IntToStr(AEdit.Line) + ':' + string.Join('|', AEdit.Lines) + '@' + IntToStr(AEdit.CaretLine) + ',' +
    IntToStr(AEdit.CaretCharacter);
end;

function Appended(ALine, ASection: Integer): string;
var
  mEdit: TAtlasSectionEdit;
begin
  Result := '-';
  if TAtlasSectionEditor.Append(Nodes, Lines, PlaceAt(ALine, 4), ASection, 2, mEdit) then
  begin
    Result := Joined(mEdit);
  end;
end;

function Added(ALine: Integer; const AKeyword: string): string;
var
  mEdit: TAtlasSectionEdit;
begin
  Result := '-';
  if TAtlasSectionEditor.Add(Nodes, Lines, PlaceAt(ALine, 4), AKeyword, 2, mEdit) then
  begin
    Result := Joined(mEdit);
  end;
end;

procedure TAtlasSectionEditTests.AppendBehindLastMember;
var
  mEdit: TAtlasSectionEdit;
  mLines: TArray<string>;
begin
  // Hinter Pruefe (zweizeilig), vor dem Kommentar.
  Assert.AreEqual('8:    @8,4', Appended(5, 0));
  Assert.AreEqual('13:    @13,4', Appended(5, 2), 'published');
  Assert.IsTrue(TAtlasSectionEditor.Append(Nodes, Lines, PlaceAt(5, 4), 0, 2, mEdit));
  mLines := mEdit.Applied(Lines);
  Assert.AreEqual(Integer(Length(Lines)) + 1, Integer(Length(mLines)));
  Assert.AreEqual('      B: Integer);', mLines[7]);
  Assert.AreEqual('    ', mLines[8]);
  Assert.AreEqual('    // Kommentar am Ende', mLines[9]);
end;

procedure TAtlasSectionEditTests.AppendIntoEmptySection;
begin
  // public ist leer: unter dem Schlüsselwort, eine Ebene tiefer.
  Assert.AreEqual('11:    @11,4', Appended(5, 1));
  // Vor dem ersten Schlüsselwort des Records: hinter X.
  Assert.AreEqual('16:    @16,4', Appended(15, -1));
end;

procedure TAtlasSectionEditTests.MissingInOrder;
begin
  Assert.AreEqual('strict private,strict protected,protected',
    string.Join(',', TAtlasSectionEditor.Missing(Nodes, PlaceAt(5, 4))));
  Assert.AreEqual('strict private,private', string.Join(',', TAtlasSectionEditor.Missing(Nodes, PlaceAt(15, 4))),
    'Record');
end;

procedure TAtlasSectionEditTests.AddBetweenSections;
begin
  // protected zwischen private und public, Mitglieder wie FName eingerückt.
  Assert.AreEqual('10:  protected|    @11,4', Added(5, 'protected'));
  Assert.AreEqual('4:  strict private|    @5,4', Added(5, 'strict private'));
  Assert.AreEqual('-', Added(5, 'private'), 'gibt es schon');
end;

procedure TAtlasSectionEditTests.AddAtEndOfType;
begin
  // Record ohne private-Abschnitt: vor public.
  Assert.AreEqual('16:  private|    @17,4', Added(15, 'private'));
  // Innerer Typ ohne Abschnitte: vor seinem end, wie das end eingerückt.
  Assert.AreEqual('20:      public|        @21,8', Added(19, 'public'));
end;

procedure TAtlasSectionEditTests.RecordAndNestedType;
begin
  // Innerster Typ zählt.
  Assert.AreEqual('20:        @20,8', Appended(19, -1));
  Assert.AreEqual('strict private,private,strict protected,protected,public,published',
    string.Join(',', TAtlasSectionEditor.Missing(Nodes, PlaceAt(19, 8))));
end;

procedure TAtlasSectionEditTests.SingleLineTypeIsLeftAlone;
begin
  Assert.AreEqual('-', Appended(22, 0));
  Assert.AreEqual('-', Added(22, 'public'));
end;

procedure TAtlasSectionEditTests.PlacesCarryCountAndMark;
var
  mCrumbs: TAtlasCrumbs;
  mCrumb: TAtlasCrumb;
begin
  mCrumbs := TAtlasBreadcrumbs.Path(Nodes, Lines, 5, 6, '', False, [TAtlasCrumbPart.Visibility]);
  mCrumb := mCrumbs[1];
  Assert.AreEqual('private', mCrumb.Text);
  Assert.AreEqual(3, Integer(Length(mCrumb.Places)));
  Assert.AreEqual(2, mCrumb.Places[0].Count);
  Assert.AreEqual('−', mCrumb.Places[0].Mark);
  Assert.AreEqual(0, mCrumb.Places[1].Count);
  Assert.AreEqual('+', mCrumb.Places[1].Mark);
  Assert.AreEqual(1, mCrumb.Places[2].Count);
  Assert.AreEqual('◆', mCrumb.Places[2].Mark);
  Assert.AreEqual('TKunde', Nodes[mCrumb.SectionType].Name);
  Assert.AreEqual(-1, mCrumbs[0].SectionType);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSectionEditTests);

end.
