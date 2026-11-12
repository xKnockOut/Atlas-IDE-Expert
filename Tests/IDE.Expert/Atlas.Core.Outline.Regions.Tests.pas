unit Atlas.Core.Outline.Regions.Tests;

// Region in der Brotkrumenleiste (#1764): Regionen mit Tiefe, innerste am
// Caret, Regionen ohne Namen, Glied hinter Unit bzw. Abschnitt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasRegionsTests = class
  public
    [Test]
    procedure RegionsWithDepth;
    [Test]
    procedure InnermostRegionAtCaret;
    [Test]
    procedure PathShowsRegionBehindUnitAndSection;
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
  Atlas.Core.Outline.Directives,
  Atlas.Core.Outline.Regions;

const
  cCode =
    'unit uKunden;'#13#10 +                                  // 0
    'interface'#13#10 +                                      // 1
    '{$REGION ''Datenbankzugriff''}'#13#10 +                 // 2
    'type'#13#10 +                                           // 3
    '  TKunde = class'#13#10 +                               // 4
    '    procedure Speichern;'#13#10 +                       // 5
    '  end;'#13#10 +                                         // 6
    '{$ENDREGION}'#13#10 +                                   // 7
    'const'#13#10 +                                          // 8
    '  cMax = 1;'#13#10 +                                    // 9
    'implementation'#13#10 +                                 // 10
    '{$REGION ''Kunde''}'#13#10 +                            // 11
    'procedure TKunde.Speichern;'#13#10 +                    // 12
    'begin'#13#10 +                                          // 13
    '  {$REGION}'#13#10 +                                    // 14
    '  Schreibe;'#13#10 +                                    // 15
    '  {$ENDREGION}'#13#10 +                                 // 16
    'end;'#13#10 +                                           // 17
    '{$ENDREGION}'#13#10 +                                   // 18
    'end.';                                                  // 19

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

function Path(ALine, ACharacter: Integer; AParts: TAtlasCrumbParts): string;
begin
  Result := Joined(TAtlasBreadcrumbs.Path(Nodes, Lines, ALine, ACharacter, 'uKunden', True, AParts));
end;

procedure TAtlasRegionsTests.RegionsWithDepth;
var
  mPlace: TAtlasRegionPlace;
  mRegion: TAtlasRegionMark;
  mText: string;
begin
  mPlace := TAtlasRegionFinder.At(Lines, 0, 0);
  Assert.AreEqual(-1, mPlace.Current);
  mText := '';
  for mRegion in mPlace.Regions do
  begin
    mText := mText + mRegion.Name + '@' + IntToStr(mRegion.Line) + '-' + IntToStr(mRegion.EndLine) + '/' +
      IntToStr(mRegion.Depth) + ';';
  end;
  Assert.AreEqual('Datenbankzugriff@2-7/0;Kunde@11-18/0;@14-16/1;', mText);
end;

procedure TAtlasRegionsTests.InnermostRegionAtCaret;
begin
  Assert.AreEqual(0, TAtlasRegionFinder.At(Lines, 5, 4).Current);
  Assert.AreEqual(1, TAtlasRegionFinder.At(Lines, 13, 0).Current);
  Assert.AreEqual(2, TAtlasRegionFinder.At(Lines, 15, 2).Current, 'innerste');
  Assert.AreEqual(-1, TAtlasRegionFinder.At(Lines, 9, 2).Current, 'außerhalb');
  Assert.AreEqual(-1, TAtlasRegionFinder.At(Lines, 1, 0).Current, 'vor der ersten');
  // Einmal gelesene Direktiven geben dieselbe Stelle.
  Assert.AreEqual(2, TAtlasRegionFinder.At(TAtlasDirectiveScanner.Scan(Lines), Length(Lines), 15, 2).Current);
  Assert.AreEqual(-1, TAtlasRegionFinder.At(TAtlasDirectiveScanner.Scan(Lines), Length(Lines), 9, 2).Current);
end;

procedure TAtlasRegionsTests.PathShowsRegionBehindUnitAndSection;
var
  mCrumbs: TAtlasCrumbs;
begin
  mCrumbs := TAtlasBreadcrumbs.Path(Nodes, Lines, 5, 6, 'uKunden', True, [TAtlasCrumbPart.Regions]);
  Assert.AreEqual('uKunden › Datenbankzugriff › TKunde › Speichern', Joined(mCrumbs));
  Assert.AreEqual('rg', mCrumbs[1].Badge.Code);
  Assert.AreEqual(3, Integer(Length(mCrumbs[1].Places)));
  Assert.AreEqual(0, mCrumbs[1].Current);
  Assert.AreEqual(1, mCrumbs[1].Places[2].Depth);
  // Mit Deklarationsblock: hinter dem Teil, vor dem Block.
  Assert.AreEqual('uKunden › interface › Datenbankzugriff › type › TKunde › Speichern',
    Path(5, 6, [TAtlasCrumbPart.Regions, TAtlasCrumbPart.DeclarationBlocks]));
  // Ohne Namen: leerer Text, die Anzeige ergänzt ihn.
  mCrumbs := TAtlasBreadcrumbs.Path(Nodes, Lines, 15, 2, 'uKunden', True, [TAtlasCrumbPart.Regions]);
  Assert.AreEqual('uKunden ›  › TKunde › Speichern', Joined(mCrumbs));
  Assert.AreEqual(2, mCrumbs[1].Current);
  Assert.AreEqual(14, mCrumbs[1].Places[2].Line);
end;

procedure TAtlasRegionsTests.PathWithoutSettingIsUnchanged;
begin
  Assert.AreEqual('uKunden › TKunde › Speichern', Path(5, 6, []));
  Assert.AreEqual('uKunden › cMax', Path(9, 4, [TAtlasCrumbPart.Regions]), 'außerhalb jeder Region');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRegionsTests);

end.
