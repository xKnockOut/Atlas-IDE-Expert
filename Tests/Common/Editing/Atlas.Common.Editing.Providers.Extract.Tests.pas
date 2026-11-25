unit Atlas.Common.Editing.Providers.Extract.Tests;

// Tests für IEditingExtract (#2054): mit Duplicates samt gleicher Stelle, ohne gleiche Stelle nur die Auswahl mit
// Grund, nicht extrahierbare Zeilen mit Grund; Bedingung auslagern und Konstante einführen für die Prüfregeln,
// ohne Baum keine Korrektur.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingExtractProviderTests = class
  public
    [Test]
    procedure ExtractsWithEqualPlaces;
    [Test]
    procedure FallsBackToSelectionWithReason;
    [Test]
    procedure RefusesPartialStatementWithReason;
    [Test]
    procedure ExtractsCondition;
    [Test]
    procedure ExtractsConstantsOfOneText;
    [Test]
    procedure NoTreeNoFix;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Pascal.TreeHandles,
  Atlas.Common.Editing.Contract.Extract,
  Atlas.Tests.TextEdits,
  Atlas.Common.Editing.Composition;

const
  cSource = 'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TParser = class'#10 +
    '  private'#10 +
    '    FCount: Integer;'#10 +
    '  public'#10 +
    '    procedure A(AValue: Integer);'#10 +
    '    procedure B(AValue: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TParser.A(AValue: Integer);'#10 +
    'begin'#10 +
    '  FCount := FCount + AValue;'#10 +
    '  Writeln(FCount);'#10 +
    'end;'#10 +
    'procedure TParser.B(AValue: Integer);'#10 +
    'begin'#10 +
    '  FCount := FCount + AValue;'#10 +
    '  Writeln(FCount);'#10 +
    'end;'#10 +
    'end.'#10;

  // Zeile 5: Bedingung ab Spalte 5 bis 24, Zeile 6: Literale 42 (Spalte 10) und 7 (Spalte 14).
  cRoutine = 'unit U;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P(A, B: Integer);'#10 +
    'begin'#10 +
    '  if (A > 1) and (B > 2) then'#10 +
    '    Writeln(42, 7);'#10 +
    'end;'#10 +
    'end.'#10;

function Wish(ADuplicates: Boolean): TEditingExtractWish;
begin
  Result := Default(TEditingExtractWish);
  Result.MethodName := 'Add';
  Result.Duplicates := ADuplicates;
  Result.InlineVar := True;
  Result.Style := TFormatStyle.Default;
end;

{ TEditingExtractProviderTests }

procedure TEditingExtractProviderTests.ExtractsWithEqualPlaces;
var
  mResult: TEditingExtractResult;
begin
  mResult := TEditingComposition.Extract.ExtractMethod(cSource, TTextRange.Create(13, 0, 14, 17), Wish(True));
  Assert.IsTrue(mResult.Extracted, mResult.Reason);
  Assert.AreEqual('', mResult.DuplicatesReason);
  Assert.AreEqual(1, Integer(Length(mResult.Action.Choices)));
  Assert.IsTrue(Length(mResult.Action.Edits) > 0);
end;

procedure TEditingExtractProviderTests.FallsBackToSelectionWithReason;
var
  mSource: string;
  mResult: TEditingExtractResult;
begin
  // B tut etwas anderes: keine gleiche Stelle, die Aktion gilt nur der Auswahl, mit Grund.
  mSource := StringReplace(cSource, '  FCount := FCount + AValue;'#10'  Writeln(FCount);'#10'end;'#10'end.',
    '  FCount := 0;'#10'end;'#10'end.', []);
  mResult := TEditingComposition.Extract.ExtractMethod(mSource, TTextRange.Create(13, 0, 14, 17), Wish(True));
  Assert.IsTrue(mResult.Extracted, mResult.Reason);
  Assert.AreEqual(0, Integer(Length(mResult.Action.Choices)));
  Assert.AreNotEqual('', mResult.DuplicatesReason);
end;

procedure TEditingExtractProviderTests.RefusesPartialStatementWithReason;
var
  mResult: TEditingExtractResult;
begin
  mResult := TEditingComposition.Extract.ExtractMethod(cSource, TTextRange.Create(0, 0, 1, 9), Wish(False));
  Assert.IsFalse(mResult.Extracted);
  Assert.AreNotEqual('', mResult.Reason);
end;

procedure TEditingExtractProviderTests.ExtractsCondition;
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
  mText: string;
begin
  mTree := TSyntaxTreeCache.Parse(cRoutine);
  try
    Assert.IsTrue(TEditingComposition.ExtractFixes.ExtractCondition(cRoutine, TSyntaxTreeHandles.Wrap(mTree),
      TTextRange.Create(5, 5, 5, 24), TFormatStyle.Default, mAction));
  finally
    mTree.Free;
  end;
  mText := TTestEdits.Apply(cRoutine, mAction.Edits);
  Assert.IsTrue(Pos('function ', mText) > 0, mText);
  Assert.IsFalse(Pos('if (A > 1) and (B > 2) then', mText) > 0, mText);
end;

procedure TEditingExtractProviderTests.ExtractsConstantsOfOneText;
var
  mTree: TSyntaxTree;
  mExtraction: IEditingConstantExtraction;
  mAction: TCodeAction;
begin
  mTree := TSyntaxTreeCache.Parse(cRoutine);
  try
    mExtraction := TEditingComposition.ExtractFixes.ConstantExtraction(cRoutine, TSyntaxTreeHandles.Wrap(mTree),
      Default(TPascalNamePrefixes));
    Assert.IsTrue(mExtraction.Run(TTextRange.Create(6, 12, 6, 14), mAction));
    Assert.IsTrue(Pos('= 42;', TTestEdits.Apply(cRoutine, mAction.Edits)) > 0);
    Assert.IsTrue(mExtraction.Run(TTextRange.Create(6, 16, 6, 17), mAction));
    Assert.IsTrue(Pos('= 7;', TTestEdits.Apply(cRoutine, mAction.Edits)) > 0);
    // Kein Literal: nichts zu tun.
    Assert.IsFalse(mExtraction.Run(TTextRange.Create(3, 0, 3, 9), mAction));
    // Die Extraktion gilt nur, solange der Baum lebt.
    mExtraction := nil;
  finally
    mTree.Free;
  end;
end;

procedure TEditingExtractProviderTests.NoTreeNoFix;
var
  mAction: TCodeAction;
begin
  Assert.IsFalse(TEditingComposition.ExtractFixes.ExtractCondition(cRoutine, nil, TTextRange.Create(5, 5, 5, 24),
    TFormatStyle.Default, mAction));
  Assert.IsNull(TEditingComposition.ExtractFixes.ConstantExtraction(cRoutine, nil, Default(TPascalNamePrefixes)));
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingExtractProviderTests);

end.
