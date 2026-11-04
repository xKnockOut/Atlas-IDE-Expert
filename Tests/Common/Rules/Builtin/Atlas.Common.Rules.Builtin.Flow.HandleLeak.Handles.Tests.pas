unit Atlas.Common.Rules.Builtin.Flow.HandleLeak.Handles.Tests;

// Tests der Handle-Hilfen für handle-leak: Paare aus Option, Namen mit A/W, Erfolg einer Bedingung, Weitergabe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowHandleLeakHandlesTests = class
  public
    [Test]
    procedure OptionPairsAreAppended;
    [Test]
    procedure InvalidOptionPairsAreIgnored;
    [Test]
    procedure RoutineNamesWithSuffix;
    [Test]
    procedure TableSplitsPairs;
    [Test]
    procedure ConditionVerdicts;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Flow.HandleLeak.Handles;

procedure TFlowHandleLeakHandlesTests.OptionPairsAreAppended;
var
  mPairs: TArray<string>;
begin
  mPairs := HandlePairs('{"pairs": ["Oeffne>Schliesse", {"open": "Hole", "close": "Gib"}]}');
  Assert.AreEqual('Oeffne|r|Schliesse(%h)', mPairs[High(mPairs) - 1]);
  Assert.AreEqual('Hole|r|Gib(%h)', mPairs[High(mPairs)]);
end;

procedure TFlowHandleLeakHandlesTests.InvalidOptionPairsAreIgnored;
begin
  Assert.AreEqual(Integer(Length(HandlePairs(''))), Integer(Length(HandlePairs(
    '{"pairs": ["Ohne", "a b>c", {"open": "Nur"}]}'))));
end;

procedure TFlowHandleLeakHandlesTests.RoutineNamesWithSuffix;
begin
  Assert.IsTrue(SameRoutine('CreateFileW', 'CreateFile'));
  Assert.IsTrue(SameRoutine('createfile', 'CreateFile'));
  Assert.IsFalse(SameRoutine('CreateFileX', 'CreateFile'));
end;

procedure TFlowHandleLeakHandlesTests.TableSplitsPairs;
var
  mTable: TArray<THandlePair>;
begin
  mTable := HandleTable(TArray<string>.Create('CreatePipe|0,1|CloseHandle(%h)'));
  Assert.AreEqual('CreatePipe', mTable[0].Open);
  Assert.AreEqual('0,1', mTable[0].Where);
  Assert.AreEqual('CloseHandle(%h)', mTable[0].Close);
end;

/// <summary>Wert von OpenSuccess für die Bedingung des ersten if in "if ACondition then".</summary>
function Verdict(const ACondition: string): Integer;
var
  mTree: TSyntaxTree;
  mIf, mCondition: TSyntaxNode;
  mHandle: TOpenedHandle;
begin
  mTree := TPascalParser.Parse('unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  if ' + ACondition + ' then'#10'    Exit;'#10'end;'#10'end.');
  try
    mIf := mTree.Root.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        Result := TSyntaxSearchStep.Descend;
        if ANode.Kind = TSyntaxKind.IfStatement then
        begin
          Result := TSyntaxSearchStep.Found;
        end;
      end);
    mCondition := mIf[0];
    mHandle := Default(TOpenedHandle);
    mHandle.Path := 'H';
    mHandle.Root := 'H';
    Result := OpenSuccess(mCondition, mHandle, nil);
  finally
    mTree.Free;
  end;
end;

procedure TFlowHandleLeakHandlesTests.ConditionVerdicts;
begin
  Assert.AreEqual(1, Verdict('H <> 0'));
  Assert.AreEqual(-1, Verdict('H = INVALID_HANDLE_VALUE'));
  Assert.AreEqual(-1, Verdict('not (H <> 0)'));
  Assert.AreEqual(1, Verdict('(H <> 0) and B'));
  Assert.AreEqual(0, Verdict('B'));
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowHandleLeakHandlesTests);

end.
