unit Atlas.Core.Outline.DeclarationBlocks.Tests;

// Deklarationsblock der Unit in der Brotkrumenleiste (#1766): Blöcke beider
// Teile, Ende an Routinen und Schlüsselwörtern, lokale Blöcke und
// Unterblöcke in Typen zählen nicht, Glieder im Pfad.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDeclarationBlocksTests = class
  public
    [Test]
    procedure BlocksOfBothSections;
    [Test]
    procedure BlockAtCaret;
    [Test]
    procedure MembersOfABlock;
    [Test]
    procedure PathShowsSectionAndBlock;
    [Test]
    procedure NoBlockInRoutinesAndWithoutSetting;
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
  Atlas.Core.Outline.DeclarationBlocks;

const
  cCode =
    'unit uKunden;'#13#10 +                                  // 0
    'interface'#13#10 +                                      // 1
    'uses'#13#10 +                                           // 2
    '  System.SysUtils;'#13#10 +                             // 3
    'type'#13#10 +                                           // 4
    '  TKunde = class'#13#10 +                               // 5
    '  private'#13#10 +                                      // 6
    '    const cMax = 3;'#13#10 +                            // 7
    '    var FName: string;'#13#10 +                         // 8
    '  end;'#13#10 +                                         // 9
    'const'#13#10 +                                          // 10
    '  cRabatt = 5;'#13#10 +                                 // 11
    '  // var im Kommentar'#13#10 +                          // 12
    '  cText = ''type'';'#13#10 +                            // 13
    'resourcestring'#13#10 +                                 // 14
    '  sKundeFehlt = ''Kunde fehlt'';'#13#10 +               // 15
    'procedure Lade(const AName: string);'#13#10 +           // 16
    'var'#13#10 +                                            // 17
    '  gZaehler: Integer;'#13#10 +                           // 18
    'threadvar'#13#10 +                                      // 19
    '  tDaten: Integer;'#13#10 +                             // 20
    'implementation'#13#10 +                                 // 21
    'const'#13#10 +                                          // 22
    '  cIntern = 1;'#13#10 +                                 // 23
    'procedure Lade(const AName: string);'#13#10 +           // 24
    'var'#13#10 +                                            // 25
    '  mWert: Integer;'#13#10 +                              // 26
    'begin'#13#10 +                                          // 27
    'end;'#13#10 +                                           // 28
    'label'#13#10 +                                          // 29
    '  Weiter;'#13#10 +                                      // 30
    'initialization'#13#10 +                                 // 31
    '  gZaehler := 0;'#13#10 +                               // 32
    'end.';                                                  // 33

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

function Path(ALine, ACharacter: Integer; AParts: TAtlasCrumbParts = [TAtlasCrumbPart.DeclarationBlocks]): string;
begin
  Result := Joined(TAtlasBreadcrumbs.Path(Nodes, Lines, ALine, ACharacter, '', False, AParts));
end;

function CurrentKeyword(ALine: Integer): string;
var
  mPlace: TAtlasDeclarationBlockPlace;
begin
  mPlace := TAtlasDeclarationBlockFinder.At(Nodes, Lines, ALine);
  // Einmal vorbereitete Blöcke geben dieselbe Stelle.
  Assert.AreEqual(mPlace.Current,
    TAtlasDeclarationBlockFinder.Locate(TAtlasDeclarationBlockFinder.Prepare(Nodes, Lines), ALine).Current);
  if mPlace.Current < 0 then
  begin
    Exit('-');
  end;
  Result := mPlace.Blocks[mPlace.Current].Keyword;
end;

procedure TAtlasDeclarationBlocksTests.BlocksOfBothSections;
var
  mBlock: TAtlasDeclarationBlock;
  mText: string;
begin
  mText := '';
  for mBlock in TAtlasDeclarationBlockFinder.BlocksOf(Nodes, Lines) do
  begin
    if mText <> '' then
    begin
      mText := mText + ',';
    end;
    mText := mText + mBlock.Section + ':' + mBlock.Keyword + '@' + IntToStr(mBlock.Line) + '-' +
      IntToStr(mBlock.EndLine);
  end;
  // Unterblöcke in TKunde, Wörter in Kommentar und String und die lokale var zählen nicht.
  Assert.AreEqual('interface:type@4-10,interface:const@10-14,interface:resourcestring@14-16,' +
    'interface:var@17-19,interface:threadvar@19-21,implementation:const@22-24,implementation:label@29-31', mText);
end;

procedure TAtlasDeclarationBlocksTests.BlockAtCaret;
begin
  Assert.AreEqual('type', CurrentKeyword(4));
  Assert.AreEqual('type', CurrentKeyword(8), 'im Typ');
  Assert.AreEqual('const', CurrentKeyword(12), 'Kommentarzeile');
  Assert.AreEqual('resourcestring', CurrentKeyword(15));
  Assert.AreEqual('-', CurrentKeyword(16), 'Routinendeklaration');
  Assert.AreEqual('threadvar', CurrentKeyword(20));
  Assert.AreEqual('-', CurrentKeyword(26), 'lokale var');
  Assert.AreEqual('-', CurrentKeyword(3), 'uses');
  Assert.AreEqual('-', CurrentKeyword(32), 'initialization');
end;

procedure TAtlasDeclarationBlocksTests.MembersOfABlock;
var
  mList: TAtlasOutlineNodes;
  mPlace: TAtlasDeclarationBlockPlace;
  mItem: Integer;
  mText: string;
begin
  mList := Nodes;
  mPlace := TAtlasDeclarationBlockFinder.At(mList, Lines, 11);
  mText := '';
  for mItem in TAtlasDeclarationBlockFinder.MembersOf(mList, mPlace, mPlace.Current) do
  begin
    mText := mText + mList[mItem].Name + ';';
  end;
  Assert.AreEqual('cRabatt;cText;', mText);
  Assert.AreEqual(0, Integer(Length(TAtlasDeclarationBlockFinder.MembersOf(mList, mPlace, 99))));
end;

procedure TAtlasDeclarationBlocksTests.PathShowsSectionAndBlock;
var
  mCrumbs: TAtlasCrumbs;
begin
  mCrumbs := TAtlasBreadcrumbs.Path(Nodes, Lines, 15, 4, 'uKunden', True, [TAtlasCrumbPart.DeclarationBlocks]);
  Assert.AreEqual('uKunden › interface › resourcestring › sKundeFehlt', Joined(mCrumbs));
  // Teil: Sprungziele interface und implementation.
  Assert.AreEqual('kw', mCrumbs[1].Badge.Code);
  Assert.AreEqual(2, Integer(Length(mCrumbs[1].Places)));
  Assert.AreEqual(0, mCrumbs[1].Current);
  Assert.AreEqual(21, mCrumbs[1].Places[1].Line);
  // Block: alle Blöcke der Unit, gruppiert nach Teil.
  Assert.AreEqual(7, Integer(Length(mCrumbs[2].Places)));
  Assert.AreEqual(2, mCrumbs[2].Current);
  Assert.AreEqual('implementation', mCrumbs[2].Places[5].Group);
  Assert.AreEqual(22, mCrumbs[2].Places[5].Line);
  Assert.AreEqual(1, Integer(Length(mCrumbs[2].Children)));
  Assert.IsTrue(TAtlasBreadcrumbs.HasMenu(mCrumbs[2]));
  // Im Typ wie bisher hinter dem Block.
  Assert.AreEqual('interface › type › TKunde › FName', Path(8, 9));
  Assert.AreEqual('implementation › const › cIntern', Path(23, 4));
  // Leerzeile im Block: der Block ist das letzte Glied.
  Assert.AreEqual('implementation › label', Path(29, 0));
end;

procedure TAtlasDeclarationBlocksTests.NoBlockInRoutinesAndWithoutSetting;
begin
  Assert.AreEqual('Lade', Path(27, 0), 'Rumpf');
  Assert.AreEqual('Lade › mWert', Path(26, 2), 'lokale var');
  Assert.AreEqual('uses', Path(3, 2));
  Assert.AreEqual('cRabatt', Path(11, 4, []));
  Assert.AreEqual('TKunde › private › FName', Path(8, 9, [TAtlasCrumbPart.Visibility, TAtlasCrumbPart.MemberBlocks,
    TAtlasCrumbPart.VisibilityMark]));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDeclarationBlocksTests);

end.
