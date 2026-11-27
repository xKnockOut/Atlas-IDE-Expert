unit Editing.Providers.MethodOrder.Tests;

// Tests für IEditingMethodOrderReview (#1840): Typ außer der Ordnung samt Korrektur, fehlender Typkommentar,
// verstandene Ordnung, off und ein fehlender Baum liefern nichts.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingMethodOrderProviderTests = class
  public
    [Test]
    procedure DisorderedTypeIsArranged;
    [Test]
    procedure MissingCommentIsInserted;
    [Test]
    procedure PlacementOffGivesNothing;
    [Test]
    procedure NoTreeGivesNothing;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Editing.Contract.MethodOrder,
  Editing.Composition,
  Atlas.Tests.TextEdits;

const
  // TFoo deklariert A vor B, die Rümpfe stehen umgekehrt.
  cHead =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure A;'#10 +
    '    procedure B;'#10 +
    '  end;'#10 +
    'implementation'#10;
  cBodies =
    'procedure TFoo.B;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TFoo.A;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.'#10;

function Request(const APlacement, ATypeComment: string): TEditingMethodOrderRequest;
begin
  Result := Default(TEditingMethodOrderRequest);
  Result.Placement := APlacement;
  Result.TypeComment := ATypeComment;
end;

/// <summary>Prüfung von AText auf einem eigenen Baum.</summary>
function Review(const AText: string; const ARequest: TEditingMethodOrderRequest): TEditingMethodOrderReview;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := TEditingComposition.MethodOrder.Review(AText, TSyntaxTree.HandleOf(mTree), ARequest);
  finally
    mTree.Free;
  end;
end;

{ TEditingMethodOrderProviderTests }

procedure TEditingMethodOrderProviderTests.DisorderedTypeIsArranged;
var
  mSource: string;
  mReview: TEditingMethodOrderReview;
  mText: string;
begin
  mSource := cHead + '{ TFoo }'#10 + cBodies;
  mReview := Review(mSource, Request('declaration', 'brace'));
  Assert.AreEqual('declaration', mReview.Placement);
  Assert.AreEqual(1, Integer(Length(mReview.Types)));
  Assert.AreEqual('TFoo', mReview.Types[0].TypeName);
  Assert.IsTrue(mReview.Types[0].CommentEdits = nil, 'Kommentar steht schon da');
  mText := TTestEdits.Apply(mSource, mReview.Types[0].OrderEdits);
  Assert.IsTrue(Pos('procedure TFoo.A;'#10'begin', mText) < Pos('procedure TFoo.B;'#10'begin', mText), mText);
end;

procedure TEditingMethodOrderProviderTests.MissingCommentIsInserted;
var
  mSource: string;
  mReview: TEditingMethodOrderReview;
begin
  // Leere Ordnung ist grouped; dort zählt die Deklarationsreihenfolge ebenso.
  mSource := cHead + cBodies;
  mReview := Review(mSource, Request('', 'brace'));
  Assert.AreEqual('grouped', mReview.Placement);
  Assert.AreEqual(1, Integer(Length(mReview.Types)));
  Assert.AreEqual('{ TFoo }', mReview.Types[0].CommentText);
  Assert.IsTrue(Pos('{ TFoo }', TTestEdits.Apply(mSource, mReview.Types[0].CommentEdits)) > 0);
end;

procedure TEditingMethodOrderProviderTests.PlacementOffGivesNothing;
var
  mReview: TEditingMethodOrderReview;
begin
  mReview := Review(cHead + cBodies, Request('off', 'brace'));
  Assert.AreEqual('off', mReview.Placement);
  Assert.AreEqual(0, Integer(Length(mReview.Types)));
end;

procedure TEditingMethodOrderProviderTests.NoTreeGivesNothing;
begin
  Assert.AreEqual(0, Integer(Length(TEditingComposition.MethodOrder.Review(cHead + cBodies, nil,
    Request('declaration', 'brace')).Types)));
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingMethodOrderProviderTests);

end.
