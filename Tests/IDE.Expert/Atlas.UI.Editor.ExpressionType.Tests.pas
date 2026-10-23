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
    Result.FileName := 'C:\P\Preise.pas';
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
  Texts: TAtlasExpressionTypeTexts;
  Rows: TArray<TAtlasExpressionTypeRow>;
begin
  TAtlasStrings.Language := TAtlasLanguage.German;
  Texts := TAtlasExpressionTypeTip.Texts('Strg+Umschalt+T');
  Rows := TAtlasExpressionType.Rows(Sample(True), Texts);
  Assert.AreEqual(4, Integer(Length(Rows)));
  Assert.AreEqual('Count: Integer wird zu Currency erweitert', Rows[2].Text);
  Assert.AreEqual('Strg+Umschalt+T erneut: umschließender Ausdruck', Rows[3].Text);
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
  Tip: TAtlasExpressionTypeTip;
  Navigated: Integer;
begin
  Navigated := 0;
  Tip := NewTip;
  try
    Tip.OnNavigate :=
      procedure
      begin
        Inc(Navigated);
      end;
    Tip.ShowFor(TAtlasExpressionType.Rows(Sample(True), TAtlasExpressionTypeTip.Texts('')), Point(100, 100));
    try
      Assert.IsTrue(Tip.IsShown);
      Assert.AreEqual(3, Integer(Length(Tip.Rows)));
      Assert.IsFalse(Tip.LinkRect.IsEmpty, 'Typ mit Fundort ist anklickbar');
      Assert.IsTrue(Tip.LinkRect.Top > 0);
      Assert.IsTrue(Tip.ClientWidth >= Tip.LinkRect.Right);
      Tip.Navigate;
      Assert.AreEqual(1, Navigated);
      Assert.IsFalse(Tip.IsShown, 'nach dem Sprung zu');
    finally
      Tip.Dismiss;
    end;
  finally
    Tip.Free;
  end;
end;

procedure TAtlasExpressionTypeTipTests.WithoutLocationNoNavigation;
var
  Tip: TAtlasExpressionTypeTip;
  Navigated: Integer;
begin
  Navigated := 0;
  Tip := NewTip;
  try
    Tip.OnNavigate :=
      procedure
      begin
        Inc(Navigated);
      end;
    Tip.ShowFor(TAtlasExpressionType.Rows(Sample(False), TAtlasExpressionTypeTip.Texts('')), Point(100, 100));
    try
      Assert.IsTrue(Tip.LinkRect.IsEmpty);
      Tip.Navigate;
      Assert.AreEqual(0, Navigated);
      Assert.IsTrue(Tip.IsShown);
    finally
      Tip.Dismiss;
    end;
  finally
    Tip.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExpressionTypeTipTests);

end.
