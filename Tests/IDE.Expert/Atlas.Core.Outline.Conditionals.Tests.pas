unit Atlas.Core.Outline.Conditionals.Tests;

// Bedingungszweig in der Brotkrumenleiste (#1763): Direktiven ohne
// Kommentare und Strings, Zweige von IFDEF, ELSE und ELSEIF, verschachtelte
// Blöcke außen zuerst, Sprungziele und die Glieder im Pfad.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasConditionalsTests = class
  public
    [Test]
    procedure DirectivesWithoutCommentsAndStrings;
    [Test]
    procedure BranchTexts;
    [Test]
    procedure NestedBlocksOuterFirst;
    [Test]
    procedure PartsAsPlaces;
    [Test]
    procedure PathEndsWithBranches;
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
  Atlas.Core.Outline.Conditionals;

const
  cCode =
    'unit uBedingt;'#13#10 +                                 // 0
    'interface'#13#10 +                                      // 1
    '{$IFDEF MSWINDOWS}'#13#10 +                             // 2
    'uses'#13#10 +                                           // 3
    '  Winapi.Windows;'#13#10 +                              // 4
    '{$ENDIF}'#13#10 +                                       // 5
    'implementation'#13#10 +                                 // 6
    'procedure Laden;'#13#10 +                               // 7
    'begin'#13#10 +                                          // 8
    '  {$IFDEF DEBUG}'#13#10 +                               // 9
    '  Log(''{$IFDEF STRING}'');'#13#10 +                    // 10
    '    {$IFNDEF TEST}'#13#10 +                             // 11
    '    Pruefe; // {$ENDIF}'#13#10 +                        // 12
    '    {$ENDIF}'#13#10 +                                   // 13
    '  { {$ELSE} im Kommentar }'#13#10 +                     // 14
    '  {$ELSE}'#13#10 +                                      // 15
    '  Leise;'#13#10 +                                       // 16
    '  {$ENDIF}'#13#10 +                                     // 17
    '  (*$IF CompilerVersion >= 36*)'#13#10 +                // 18
    '  Neu;'#13#10 +                                         // 19
    '  {$ELSEIF Defined(FPC)}'#13#10 +                       // 20
    '  Frei;'#13#10 +                                        // 21
    '  {$IFEND}'#13#10 +                                     // 22
    'end;'#13#10 +                                           // 23
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

/// <summary>Texte der Zweige um ALine/ACharacter, mit „ › “ verbunden.</summary>
function BranchesAt(ALine, ACharacter: Integer): string;
var
  mBranch: TAtlasConditionalBranch;
begin
  Result := '';
  for mBranch in TAtlasConditionalFinder.At(Lines, ALine, ACharacter) do
  begin
    if Result <> '' then
    begin
      Result := Result + ' › ';
    end;
    Result := Result + mBranch.Text;
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

procedure TAtlasConditionalsTests.DirectivesWithoutCommentsAndStrings;
var
  mDirective: TAtlasDirective;
  mText: string;
begin
  mText := '';
  for mDirective in TAtlasDirectiveScanner.Scan(Lines) do
  begin
    mText := mText + mDirective.Name + '@' + IntToStr(mDirective.Line) + ';';
  end;
  Assert.AreEqual('IFDEF@2;ENDIF@5;IFDEF@9;IFNDEF@11;ENDIF@13;ELSE@15;ENDIF@17;IF@18;ELSEIF@20;IFEND@22;', mText);
  mDirective := TAtlasDirectiveScanner.Scan(Lines)[7];
  Assert.AreEqual('CompilerVersion >= 36', mDirective.Argument);
  Assert.AreEqual(2, mDirective.Character);
  Assert.AreEqual(31, mDirective.EndCharacter);
end;

procedure TAtlasConditionalsTests.BranchTexts;
begin
  Assert.AreEqual('{$IFDEF MSWINDOWS}', BranchesAt(4, 2), 'auch in uses');
  Assert.AreEqual('{$ELSE DEBUG}', BranchesAt(16, 2));
  Assert.AreEqual('{$IF CompilerVersion >= 36}', BranchesAt(19, 2));
  Assert.AreEqual('{$ELSEIF Defined(FPC)}', BranchesAt(21, 2));
  Assert.AreEqual('', BranchesAt(7, 2), 'außerhalb');
  Assert.AreEqual('', BranchesAt(23, 0), 'hinter IFEND');
  Assert.AreEqual('', BranchesAt(9, 4), 'auf der Direktive');
end;

procedure TAtlasConditionalsTests.NestedBlocksOuterFirst;
begin
  Assert.AreEqual('{$IFDEF DEBUG} › {$IFNDEF TEST}', BranchesAt(12, 4));
  Assert.AreEqual('{$IFDEF DEBUG}', BranchesAt(10, 2));
  Assert.AreEqual('{$IFDEF DEBUG}', BranchesAt(14, 2), 'Kommentar mit ELSE');
end;

procedure TAtlasConditionalsTests.PartsAsPlaces;
var
  mBranches: TAtlasConditionalBranches;
begin
  mBranches := TAtlasConditionalFinder.At(Lines, 16, 2);
  Assert.AreEqual(1, Integer(Length(mBranches)));
  Assert.AreEqual(3, Integer(Length(mBranches[0].Parts)));
  Assert.AreEqual(1, mBranches[0].Current);
  Assert.AreEqual('{$IFDEF DEBUG}', mBranches[0].Parts[0].Text);
  Assert.AreEqual('{$ELSE}', mBranches[0].Parts[1].Text);
  Assert.AreEqual('{$ENDIF}', mBranches[0].Parts[2].Text);
  Assert.AreEqual(17, mBranches[0].Parts[2].Line);
  Assert.AreEqual(2, mBranches[0].Parts[2].Character);
end;

procedure TAtlasConditionalsTests.PathEndsWithBranches;
var
  mCrumbs: TAtlasCrumbs;
begin
  mCrumbs := TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(12, 4, '', False, [TAtlasCrumbPart.Conditionals]));
  Assert.AreEqual('Laden › {$IFDEF DEBUG} › {$IFNDEF TEST}', Joined(mCrumbs));
  Assert.AreEqual('if', mCrumbs[1].Badge.Code);
  Assert.AreEqual(-1, mCrumbs[1].Node);
  Assert.AreEqual(3, Integer(Length(mCrumbs[1].Places)));
  Assert.AreEqual(0, mCrumbs[1].Current);
  Assert.IsTrue(TAtlasBreadcrumbs.HasMenu(mCrumbs[2]));
  Assert.AreEqual('uses › {$IFDEF MSWINDOWS}', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(4, 2, '', False, [TAtlasCrumbPart.Conditionals]))));
  Assert.AreEqual('Laden', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines,
    TAtlasCrumbRequest.Create(12, 4, '', False, []))), 'ausgeschaltet');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasConditionalsTests);

end.
