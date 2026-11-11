unit Atlas.Core.Outline.Statements.Tests;

// try/except/finally und case-Zweig in der Brotkrumenleiste (#1769): Teile
// des try-Blocks, case-Kopf und Zweig, else des case gegen else des if,
// lokale Routinen, höchstens drei Glieder.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStatementsTests = class
  public
    [Test]
    procedure TryParts;
    [Test]
    procedure CaseBranches;
    [Test]
    procedure CaseElseAndIfElse;
    [Test]
    procedure LocalRoutineHasItsOwnFrames;
    [Test]
    procedure PathShowsAtMostThree;
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
  Atlas.Core.Outline.Statements;

const
  cCode =
    'unit uRahmen;'#13#10 +                                  // 0
    'interface'#13#10 +                                      // 1
    'implementation'#13#10 +                                 // 2
    'procedure Laden(Art: Integer);'#13#10 +                 // 3
    '  procedure Lokal;'#13#10 +                             // 4
    '  begin'#13#10 +                                        // 5
    '    try'#13#10 +                                        // 6
    '      Tue;'#13#10 +                                     // 7
    '    finally'#13#10 +                                    // 8
    '      Ende;'#13#10 +                                    // 9
    '    end;'#13#10 +                                       // 10
    '  end;'#13#10 +                                         // 11
    'begin'#13#10 +                                          // 12
    '  try'#13#10 +                                          // 13
    '    case Art of'#13#10 +                                // 14
    '      1, 2:'#13#10 +                                    // 15
    '        if Art = 1 then A else B;'#13#10 +              // 16
    '      akFirma: begin'#13#10 +                           // 17
    '        try'#13#10 +                                    // 18
    '          C;'#13#10 +                                   // 19
    '        except'#13#10 +                                 // 20
    '          on E: Exception do D;'#13#10 +                // 21
    '        end;'#13#10 +                                   // 22
    '      end;'#13#10 +                                     // 23
    '    else'#13#10 +                                       // 24
    '      F;'#13#10 +                                       // 25
    '    end;'#13#10 +                                       // 26
    '  finally'#13#10 +                                      // 27
    '    G;'#13#10 +                                         // 28
    '  end;'#13#10 +                                         // 29
    'end;'#13#10 +                                           // 30
    'end.';                                                  // 31

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

function FramesAt(ALine, ACharacter: Integer): string;
var
  mFrame: TAtlasStatementFrame;
begin
  Result := '';
  for mFrame in TAtlasStatementFinder.At(Nodes, Lines, ALine, ACharacter) do
  begin
    if Result <> '' then
    begin
      Result := Result + ' › ';
    end;
    Result := Result + mFrame.Text;
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

procedure TAtlasStatementsTests.TryParts;
var
  mFrames: TAtlasStatementFrames;
begin
  Assert.AreEqual('finally', FramesAt(28, 4));
  mFrames := TAtlasStatementFinder.At(Nodes, Lines, 28, 4);
  Assert.AreEqual(2, Integer(Length(mFrames[0].Parts)));
  Assert.AreEqual(1, mFrames[0].Current);
  Assert.AreEqual(13, mFrames[0].Parts[0].Line);
  Assert.AreEqual(2, mFrames[0].Parts[0].Character);
  Assert.AreEqual('', FramesAt(12, 0), 'begin des Rumpfs');
  Assert.AreEqual('', FramesAt(30, 0), 'hinter dem Rahmen');
end;

procedure TAtlasStatementsTests.CaseBranches;
var
  mFrames: TAtlasStatementFrames;
begin
  Assert.AreEqual('try › case Art of › 1, 2', FramesAt(16, 8));
  Assert.AreEqual('try › case Art of › akFirma › except', FramesAt(21, 10));
  Assert.AreEqual('try › case Art of', FramesAt(14, 10), 'Kopf');
  mFrames := TAtlasStatementFinder.At(Nodes, Lines, 16, 8);
  Assert.AreEqual(-1, mFrames[1].Current);
  Assert.AreEqual(3, Integer(Length(mFrames[2].Parts)));
  Assert.AreEqual('akFirma', mFrames[2].Parts[1].Text);
  Assert.AreEqual(17, mFrames[2].Parts[1].Line);
  Assert.AreEqual(6, mFrames[2].Parts[1].Character);
  Assert.AreEqual('else', mFrames[2].Parts[2].Text);
end;

procedure TAtlasStatementsTests.CaseElseAndIfElse;
begin
  // else des if in Zeile 16 gehört nicht zum case.
  Assert.AreEqual('try › case Art of › 1, 2', FramesAt(16, 28));
  Assert.AreEqual('try › case Art of › else', FramesAt(25, 6));
end;

procedure TAtlasStatementsTests.LocalRoutineHasItsOwnFrames;
begin
  Assert.AreEqual('finally', FramesAt(9, 6));
  Assert.AreEqual('try', FramesAt(7, 6));
end;

procedure TAtlasStatementsTests.PathShowsAtMostThree;
begin
  Assert.AreEqual('Laden › case Art of › akFirma › except', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines, 21, 10, '', False,
    [TAtlasCrumbPart.Statements])));
  Assert.AreEqual('Laden', Joined(TAtlasBreadcrumbs.Path(Nodes, Lines, 21, 10, '', False, [])), 'ausgeschaltet');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatementsTests);

end.
