unit Atlas.UI.Editor.ExpressionType.Tests;

// Typ des markierten Ausdrucks (#689), Fensterteil: Texte aus den Strings,
// Zeilen untereinander, anklickbare Typzeile nur mit Fundort und Sprung über
// OnNavigate.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasExpressionTypeTipTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure TextsFromStrings;
    [Test]
    procedure RowsAndLink;
    [Test]
    procedure WithoutLocationNoNavigation;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.ExpressionType,
  Atlas.UI.Strings,
  Atlas.UI.Editor.ExpressionType;

function NewTip: TAtlasExpressionTypeTip;
begin
  Result := TAtlasExpressionTypeTip.Create(nil);
  Result.Colors := TAtlasColors.Light;
  Result.SetScaling(96, 1, 'Consolas', 10);
end;

function Sample(ALocated: Boolean): TAtlasExpressionTypeInfo;
begin
  Result := Default(TAtlasExpressionTypeInfo);
  Result.Expression := 'Price * Count';
  Result.TypeName := 'Currency';
  if ALocated then
  begin
    Result.FileName := 'C:\P\Preise.pas';
  end;
  SetLength(Result.Conversions, 1);
  Result.Conversions[0].Expression := 'Count';
  Result.Conversions[0].FromType := 'Integer';
  Result.Conversions[0].ToType := 'Currency';
end;

procedure TAtlasExpressionTypeTipTests.WarmUpFirstUse;
begin
  TextsFromStrings;
  RowsAndLink;
end;

procedure TAtlasExpressionTypeTipTests.TextsFromStrings;
var
  mTexts: TAtlasExpressionTypeTexts;
  mRows: TArray<TAtlasExpressionTypeRow>;
begin
  TAtlasStrings.Language := TAtlasLanguage.German;
  mTexts := TAtlasExpressionTypeTip.Texts('Strg+Umschalt+T');
  mRows := TAtlasExpressionType.Rows(Sample(True), mTexts);
  Assert.AreEqual(4, Integer(Length(mRows)));
  Assert.AreEqual('Count: Integer wird zu Currency erweitert', mRows[2].Text);
  Assert.AreEqual('Strg+Umschalt+T erneut: umschließender Ausdruck', mRows[3].Text);
  Assert.AreEqual('', TAtlasExpressionTypeTip.Texts('').Expand, 'ohne Kürzel keine Zeile');
  TAtlasStrings.Language := TAtlasLanguage.English;
  try
    Assert.AreEqual('Count: Integer is widened to Currency',
      TAtlasExpressionType.Rows(Sample(True), TAtlasExpressionTypeTip.Texts(''))[2].Text);
  finally
    TAtlasStrings.Language := TAtlasLanguage.German;
  end;
end;

procedure TAtlasExpressionTypeTipTests.RowsAndLink;
var
  mTip: TAtlasExpressionTypeTip;
  mNavigated: Integer;
begin
  mNavigated := 0;
  mTip := NewTip;
  try
    mTip.OnNavigate :=
      procedure
      begin
        Inc(mNavigated);
      end;
    mTip.ShowFor(TAtlasExpressionType.Rows(Sample(True), TAtlasExpressionTypeTip.Texts('')), Point(100, 100));
    try
      Assert.IsTrue(mTip.IsShown);
      Assert.AreEqual(3, Integer(Length(mTip.Rows)));
      Assert.IsFalse(mTip.LinkRect.IsEmpty, 'Typ mit Fundort ist anklickbar');
      Assert.IsTrue(mTip.LinkRect.Top > 0);
      Assert.IsTrue(mTip.ClientWidth >= mTip.LinkRect.Right);
      mTip.Navigate;
      Assert.AreEqual(1, mNavigated);
      Assert.IsFalse(mTip.IsShown, 'nach dem Sprung zu');
    finally
      mTip.Dismiss;
    end;
  finally
    mTip.Free;
  end;
end;

procedure TAtlasExpressionTypeTipTests.WithoutLocationNoNavigation;
var
  mTip: TAtlasExpressionTypeTip;
  mNavigated: Integer;
begin
  mNavigated := 0;
  mTip := NewTip;
  try
    mTip.OnNavigate :=
      procedure
      begin
        Inc(mNavigated);
      end;
    mTip.ShowFor(TAtlasExpressionType.Rows(Sample(False), TAtlasExpressionTypeTip.Texts('')), Point(100, 100));
    try
      Assert.IsTrue(mTip.LinkRect.IsEmpty);
      mTip.Navigate;
      Assert.AreEqual(0, mNavigated);
      Assert.IsTrue(mTip.IsShown);
    finally
      mTip.Dismiss;
    end;
  finally
    mTip.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExpressionTypeTipTests);

end.
