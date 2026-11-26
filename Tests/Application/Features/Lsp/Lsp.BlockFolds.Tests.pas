unit Lsp.BlockFolds.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspBlockFoldsTests = class
  public
    [Test]
    procedure FindsIfAndElseBranches;
    [Test]
    procedure SkipsRoutineBodies;
    [Test]
    procedure FindsLoopsTryRepeatAndCase;
    [Test]
    procedure CaptionSkipsCommentsAndQuotes;
    [Test]
    procedure IgnoresSingleLineBlocks;
    [Test]
    procedure BeginOnOwnLine;
    [Test]
    procedure WritesJson;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Lsp.BlockFolds;

function Lines(const ALines: array of string): string;
begin
  Result := string.Join(#13#10, ALines);
end;

// Blöcke als Text, z. B. "if@2:20-5:5[if A then]".
function Describe(const AText: string): string;
var
  mTree: TSyntaxTree;
  mFold: TBlockFold;
begin
  Result := '';
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    for mFold in TLspBlockFolds.Collect(mTree) do
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + Format('%s@%d:%d-%d:%d[%s]', [mFold.Kind, mFold.OpenPos.Line, mFold.OpenPos.Character,
        mFold.ClosePos.Line, mFold.ClosePos.Character, mFold.Caption]);
    end;
  finally
    mTree.Free;
  end;
end;

function InRoutine(const ABody: array of string): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  // Zeile 0: program, 1: procedure, 2: begin, ab 3 der Rumpf.
  SetLength(mLines, Length(ABody) + 5);
  mLines[0] := 'program P;';
  mLines[1] := 'procedure A;';
  mLines[2] := 'begin';
  for mIndex := 0 to High(ABody) do
  begin
    mLines[3 + mIndex] := ABody[mIndex];
  end;
  mLines[High(mLines) - 1] := 'end;';
  mLines[High(mLines)] := 'begin end.';
  Result := Lines(mLines);
end;

{ TLspBlockFoldsTests }

procedure TLspBlockFoldsTests.FindsIfAndElseBranches;
begin
  Assert.AreEqual('if@3:21-5:5[if X > 5 then],else@5:16-7:5[else]',
    Describe(InRoutine([
      '  if X > 5 then begin',      // 3
      '    Y;',                     // 4
      '  end else begin',           // 5
      '    Z;',                     // 6
      '  end;'])));                 // 7
end;

procedure TLspBlockFoldsTests.SkipsRoutineBodies;
begin
  Assert.AreEqual('', Describe(InRoutine(['  Y;', '  Z;'])));
end;

procedure TLspBlockFoldsTests.FindsLoopsTryRepeatAndCase;
begin
  Assert.AreEqual('for@3:26-5:5[for I := 0 to 9 do],try@6:5-10:5[try],repeat@11:8-13:9[repeat],' +
    'case@14:11-17:5[case X of],case@15:12-16:7[1:]',
    Describe(InRoutine([
      '  for I := 0 to 9 do begin', // 3
      '    Y;',                     // 4
      '  end;',                     // 5
      '  try',                      // 6
      '    Y;',                     // 7
      '  finally',                  // 8
      '    Z;',                     // 9
      '  end;',                     // 10
      '  repeat',                   // 11
      '    Y;',                     // 12
      '  until X;',                 // 13
      '  case X of',                // 14
      '    1: begin',               // 15
      '    end;',                   // 16
      '  end;'])));                 // 17
end;

procedure TLspBlockFoldsTests.CaptionSkipsCommentsAndQuotes;
begin
  Assert.AreEqual('if@3:38-5:5[if S = "a)" then]',
    Describe(InRoutine([
      '  if S = ''a}'' { Kommentar } then begin', // 3
      '    Y;',                                    // 4
      '  end;'])));                                // 5
end;

procedure TLspBlockFoldsTests.IgnoresSingleLineBlocks;
begin
  Assert.AreEqual('', Describe(InRoutine(['  if X then begin Y; end;', '  try Y; finally Z; end;'])));
end;

procedure TLspBlockFoldsTests.BeginOnOwnLine;
begin
  Assert.AreEqual('if@4:7-6:5[if X then],else@8:7-10:5[else]',
    Describe(InRoutine([
      '  if X then',                // 3
      '  begin',                    // 4
      '    Y;',                     // 5
      '  end',                      // 6
      '  else',                     // 7
      '  begin',                    // 8
      '    Z;',                     // 9
      '  end;'])));                 // 10
end;

procedure TLspBlockFoldsTests.WritesJson;
var
  mFold: TBlockFold;
  mJson: TJSONObject;
begin
  mFold := Default(TBlockFold);
  mFold.Kind := 'if';
  mFold.OpenPos := TTextPosition.Create(3, 19);
  mFold.ClosePos := TTextPosition.Create(5, 5);
  mFold.Caption := 'if X then';
  mJson := TLspBlockFolds.ToJson([mFold]);
  try
    Assert.AreEqual('{"blocks":[{"kind":"if","open":{"line":3,"character":19},"close":{"line":5,"character":5},' +
      '"caption":"if X then"}]}', mJson.ToJSON);
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspBlockFoldsTests);

end.
