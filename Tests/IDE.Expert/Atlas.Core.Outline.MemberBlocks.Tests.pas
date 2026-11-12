unit Atlas.Core.Outline.MemberBlocks.Tests;

// Unterblöcke in Typen für die Brotkrumenleiste (#1767): const, type und
// class var, Ende an var, Methoden, Eigenschaften und Abschnitten,
// Parameterlisten zählen nicht, Glied hinter dem Sichtbarkeitsabschnitt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasMemberBlocksTests = class
  public
    [Test]
    procedure BlocksInSourceOrder;
    [Test]
    procedure BlockAtCaret;
    [Test]
    procedure BlocksOfTheSectionOnly;
    [Test]
    procedure NestedTypeHasItsOwnBlocks;
    [Test]
    procedure MembersOfABlock;
    [Test]
    procedure PathShowsBlockBehindSection;
    [Test]
    procedure TypeTextSkipsCommentsAndStrings;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.TypeText,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.Outline.MemberBlocks;

const
  cCode =
    'unit uBloecke;'#13#10 +                                  // 0
    'interface'#13#10 +                                       // 1
    'type'#13#10 +                                            // 2
    '  TKunde = class'#13#10 +                                // 3
    '  private'#13#10 +                                       // 4
    '    const'#13#10 +                                       // 5
    '      cRabatt = 3;'#13#10 +                              // 6
    ''#13#10 +                                                // 7
    '      cGrenze = 10; // type im Kommentar'#13#10 +        // 8
    '    type'#13#10 +                                        // 9
    '      TInnen = record'#13#10 +                           // 10
    '      const'#13#10 +                                     // 11
    '        cTief = 1;'#13#10 +                              // 12
    '      end;'#13#10 +                                      // 13
    '    class var'#13#10 +                                   // 14
    '      FZaehler: Integer;'#13#10 +                        // 15
    '    var'#13#10 +                                         // 16
    '      FName: string;'#13#10 +                            // 17
    '  public'#13#10 +                                        // 18
    '    procedure Rechne(const AWert: Integer; var AErgebnis: Integer);'#13#10 + // 19
    '    const'#13#10 +                                       // 20
    '      cOffen = ''type'';'#13#10 +                        // 21
    '    property Name: string read FName;'#13#10 +           // 22
    '  end;'#13#10 +                                          // 23
    'implementation'#13#10 +                                  // 24
    'procedure TKunde.Rechne(const AWert: Integer; var AErgebnis: Integer); begin end;'#13#10 + // 25
    'end.';                                                   // 26

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

function Keywords(const ABlocks: TAtlasMemberBlocks): string;
var
  mBlock: TAtlasMemberBlock;
begin
  Result := '';
  for mBlock in ABlocks do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mBlock.Keyword + '@' + IntToStr(mBlock.Line);
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

function BlockAt(ALine, ACharacter: Integer): string;
var
  mPlace: TAtlasMemberBlockPlace;
begin
  mPlace := TAtlasMemberBlockFinder.At(Nodes, Lines, ALine, ACharacter);
  Result := '-';
  if mPlace.Current >= 0 then
  begin
    Result := mPlace.Blocks[mPlace.Current].Keyword;
  end;
end;

function PathAt(ALine, ACharacter: Integer): string;
begin
  Result := Joined(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(ALine, ACharacter, '', False, [TAtlasCrumbPart.Visibility, TAtlasCrumbPart.MemberBlocks])));
end;

procedure TAtlasMemberBlocksTests.BlocksInSourceOrder;
var
  mList: TAtlasOutlineNodes;
begin
  mList := Nodes;
  // var beendet class var; const und var in der Parameterliste zählen nicht.
  Assert.AreEqual('const@5,type@9,class var@14,const@20',
    Keywords(TAtlasMemberBlockFinder.BlocksOf(mList, Lines, Find(mList, 'TKunde'))));
  Assert.AreEqual(0, Integer(Length(TAtlasMemberBlockFinder.BlocksOf(mList, Lines, -1))));
end;

procedure TAtlasMemberBlocksTests.BlockAtCaret;
begin
  Assert.AreEqual('const', BlockAt(6, 6));
  Assert.AreEqual('const', BlockAt(7, 0), 'Leerzeile');
  Assert.AreEqual('type', BlockAt(9, 4), 'Zeile des Schlüsselworts');
  Assert.AreEqual('type', BlockAt(10, 8), 'Kopfzeile des verschachtelten Typs');
  Assert.AreEqual('class var', BlockAt(15, 6));
  Assert.AreEqual('-', BlockAt(16, 4), 'Zeile von var');
  Assert.AreEqual('-', BlockAt(17, 6), 'Feldteil nach var');
  Assert.AreEqual('-', BlockAt(19, 6), 'Methode');
  Assert.AreEqual('const', BlockAt(21, 6));
  Assert.AreEqual('-', BlockAt(22, 6), 'Eigenschaft beendet den Block');
end;

procedure TAtlasMemberBlocksTests.BlocksOfTheSectionOnly;
var
  mPlace: TAtlasMemberBlockPlace;
begin
  mPlace := TAtlasMemberBlockFinder.At(Nodes, Lines, 6, 6);
  Assert.AreEqual('const@5,type@9,class var@14', Keywords(mPlace.Blocks));
  mPlace := TAtlasMemberBlockFinder.At(Nodes, Lines, 21, 6);
  Assert.AreEqual('const@20', Keywords(mPlace.Blocks));
  Assert.AreEqual(0, mPlace.Current);
end;

procedure TAtlasMemberBlocksTests.NestedTypeHasItsOwnBlocks;
var
  mList: TAtlasOutlineNodes;
  mPlace: TAtlasMemberBlockPlace;
begin
  mList := Nodes;
  mPlace := TAtlasMemberBlockFinder.At(mList, Lines, 12, 8);
  Assert.AreEqual(Find(mList, 'TInnen'), mPlace.TypeNode);
  Assert.AreEqual('const@11', Keywords(mPlace.Blocks));
  Assert.AreEqual(0, mPlace.Current);
end;

procedure TAtlasMemberBlocksTests.MembersOfABlock;
var
  mList: TAtlasOutlineNodes;
  mPlace: TAtlasMemberBlockPlace;
begin
  mList := Nodes;
  mPlace := TAtlasMemberBlockFinder.At(mList, Lines, 6, 6);
  Assert.AreEqual('cRabatt,cGrenze', NamesOf(mList, TAtlasMemberBlockFinder.MembersOf(mList, mPlace, 0)));
  Assert.AreEqual('TInnen', NamesOf(mList, TAtlasMemberBlockFinder.MembersOf(mList, mPlace, 1)));
  Assert.AreEqual('FZaehler', NamesOf(mList, TAtlasMemberBlockFinder.MembersOf(mList, mPlace, 2)));
  Assert.AreEqual(0, Integer(Length(TAtlasMemberBlockFinder.MembersOf(mList, mPlace, 3))));
end;

procedure TAtlasMemberBlocksTests.PathShowsBlockBehindSection;
var
  mCrumbs: TAtlasCrumbs;
begin
  Assert.AreEqual('TKunde › private › const › cRabatt', PathAt(6, 7));
  Assert.AreEqual('TKunde › private › type › TInnen', PathAt(10, 8));
  Assert.AreEqual('TKunde › TInnen › public › const › cTief', PathAt(12, 9));
  Assert.AreEqual('TKunde › private › FName', PathAt(17, 7));
  mCrumbs := TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(6, 7, '', False, [TAtlasCrumbPart.Visibility, TAtlasCrumbPart.MemberBlocks]));
  Assert.AreEqual('kw', mCrumbs[2].Badge.Code);
  Assert.AreEqual(3, Integer(Length(mCrumbs[2].Places)));
  Assert.AreEqual(0, mCrumbs[2].Current);
  Assert.AreEqual(5, mCrumbs[2].Places[0].Line);
  // Ohne Unterblöcke bzw. ohne Abschnitt.
  Assert.AreEqual('TKunde › private › cRabatt', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(6, 7, '', False, [TAtlasCrumbPart.Visibility]))));
  Assert.AreEqual('TKunde › const › cRabatt', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(6, 7, '', False, [TAtlasCrumbPart.MemberBlocks]))));
end;

procedure TAtlasMemberBlocksTests.TypeTextSkipsCommentsAndStrings;
var
  mList: TAtlasOutlineNodes;
  mToken: TAtlasTypeToken;
  mTypeWords: Integer;
begin
  mList := Nodes;
  // „type“ steht im Kommentar (Zeile 8), im String (Zeile 21) und im verschachtelten Typ nicht als Wort.
  mTypeWords := 0;
  for mToken in TAtlasTypeText.Tokens(mList, Lines, Find(mList, 'TKunde')) do
  begin
    if mToken.Word and (mToken.Text = 'type') then
    begin
      Inc(mTypeWords);
    end;
  end;
  Assert.AreEqual(1, mTypeWords);
  Assert.IsTrue(TAtlasTypeText.Before(1, 5, 2, 0));
  Assert.IsFalse(TAtlasTypeText.Before(2, 0, 2, 0));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMemberBlocksTests);

end.
