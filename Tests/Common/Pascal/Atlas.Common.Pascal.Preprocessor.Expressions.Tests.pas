unit Atlas.Common.Pascal.Preprocessor.Expressions.Tests;

// Tests des $IF-Auswerters (Pascal.Preprocessor.Expressions) ohne den
// Präprozessor: Typgrößen der Zielplattform, Teilwerte und Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPreprocessorExpressionsTests = class
  public
    [Test]
    procedure SizesFollowPointerSize;
    [Test]
    procedure PlatformSizesNameTheirOrigin;
    [Test]
    procedure RangesOfIntegerTypes;
    [Test]
    procedure ComparisonsAndFunctions;
    [Test]
    procedure UnknownConstantIsUnknownPart;
    [Test]
    procedure DeclaredAsksSettings;
    [Test]
    procedure VersionConstantsFollowCompilerVersion;
    [Test]
    procedure SyntaxErrorRaises;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Preprocessor.Expressions;

function Defines(const ANames: array of string): TDictionary<string, Boolean>;
var
  mName: string;
begin
  Result := TDictionary<string, Boolean>.Create;
  for mName in ANames do
  begin
    Result.AddOrSetValue(UpperCase(mName), True);
  end;
end;

function Win64Settings: TExpressionSettings;
begin
  Result := Default(TExpressionSettings);
  Result.CompilerVersion := 37;
  Result.RTLVersion := 37;
  Result.ProductName := 'Delphi 13';
  Result.Platform := 'Win64';
end;

/// <summary>Wert von AExpression unter Win64 mit ASettings.</summary>
function EvaluateWith(const ASettings: TExpressionSettings; const AExpression: string;
  out AParts: TArray<TConditionPart>): TConditionValue;
var
  mDefines: TDictionary<string, Boolean>;
  mEvaluator: TExpressionEvaluator;
begin
  mDefines := Defines(['MSWINDOWS', 'WIN64', 'CPU64BITS', 'CPUX64']);
  try
    mEvaluator := TExpressionEvaluator.Create(ASettings, mDefines);
    try
      Result := mEvaluator.Evaluate(AExpression);
      AParts := mEvaluator.Parts;
    finally
      mEvaluator.Free;
    end;
  finally
    mDefines.Free;
  end;
end;

function Evaluate(const AExpression: string): TConditionValue;
var
  mParts: TArray<TConditionPart>;
begin
  Result := EvaluateWith(Win64Settings, AExpression, mParts);
end;

procedure TPreprocessorExpressionsTests.SizesFollowPointerSize;
var
  mDefines: TDictionary<string, Boolean>;
  mTypes: TTargetTypes;
  mOrigin: string;
begin
  mDefines := Defines(['MSWINDOWS', 'WIN32', 'CPU32BITS']);
  try
    mTypes := Default(TTargetTypes);
    mTypes.Init(mDefines, 'Win32');
    Assert.AreEqual(4, mTypes.Size('Pointer', mOrigin));
    Assert.AreEqual(10, mTypes.Size('Extended', mOrigin));
    Assert.AreEqual(16, mTypes.Size('Variant', mOrigin));
    Assert.AreEqual(4, mTypes.Size('LongInt', mOrigin));
  finally
    mDefines.Free;
  end;
  mDefines := Defines(['LINUX', 'CPU64BITS', 'CPUX64']);
  try
    mTypes := Default(TTargetTypes);
    mTypes.Init(mDefines, 'Linux64');
    Assert.AreEqual(8, mTypes.Size('Pointer', mOrigin));
    Assert.AreEqual(16, mTypes.Size('Extended', mOrigin));
    Assert.AreEqual(8, mTypes.Size('LongInt', mOrigin));
    Assert.AreEqual(0, mTypes.Size('TMyRecord', mOrigin));
  finally
    mDefines.Free;
  end;
end;

procedure TPreprocessorExpressionsTests.PlatformSizesNameTheirOrigin;
var
  mDefines: TDictionary<string, Boolean>;
  mTypes: TTargetTypes;
  mOrigin: string;
begin
  mDefines := Defines(['MSWINDOWS', 'WIN64', 'CPU64BITS']);
  try
    mTypes := Default(TTargetTypes);
    mTypes.Init(mDefines, 'Win64');
    Assert.AreEqual(8, mTypes.Size('NativeInt', mOrigin));
    Assert.AreEqual('Zielplattform Win64', mOrigin);
    Assert.AreEqual(4, mTypes.Size('Integer', mOrigin));
    Assert.AreEqual('', mOrigin);
    Assert.AreEqual(0, mTypes.Size('TFoo', mOrigin));
    Assert.AreEqual('', mOrigin);
  finally
    mDefines.Free;
  end;
end;

procedure TPreprocessorExpressionsTests.RangesOfIntegerTypes;
var
  mDefines: TDictionary<string, Boolean>;
  mTypes: TTargetTypes;
  mLow, mHigh: Double;
  mOrigin: string;
begin
  mDefines := Defines(['MSWINDOWS', 'WIN64', 'CPU64BITS']);
  try
    mTypes := Default(TTargetTypes);
    mTypes.Init(mDefines, 'Win64');
    Assert.IsTrue(mTypes.Range('Byte', mLow, mHigh, mOrigin));
    Assert.AreEqual(Double(0), mLow, 1E-9);
    Assert.AreEqual(Double(255), mHigh, 1E-9);
    Assert.IsTrue(mTypes.Range('SmallInt', mLow, mHigh, mOrigin));
    Assert.AreEqual(Double(-32768), mLow, 1E-9);
    Assert.AreEqual(Double(32767), mHigh, 1E-9);
    Assert.IsTrue(mTypes.Range('WideChar', mLow, mHigh, mOrigin));
    Assert.AreEqual(Double(65535), mHigh, 1E-9);
    Assert.IsFalse(mTypes.Range('Double', mLow, mHigh, mOrigin));
  finally
    mDefines.Free;
  end;
end;

procedure TPreprocessorExpressionsTests.ComparisonsAndFunctions;
begin
  Assert.IsTrue(Evaluate('SizeOf(Pointer) = 8') = TConditionValue.Yes);
  Assert.IsTrue(Evaluate('High(Word) <> 65535') = TConditionValue.No);
  Assert.IsTrue(Evaluate('Defined(WIN64) and not Defined(WIN32)') = TConditionValue.Yes);
  Assert.IsTrue(Evaluate('Ord(''A'') >= 65') = TConditionValue.Yes);
  Assert.IsTrue(Evaluate('CompilerVersion < 36') = TConditionValue.No);
  Assert.IsTrue(Evaluate('(2 * 3) div 4 = 1') = TConditionValue.Yes);
end;

procedure TPreprocessorExpressionsTests.UnknownConstantIsUnknownPart;
var
  mParts: TArray<TConditionPart>;
begin
  Assert.IsTrue(EvaluateWith(Win64Settings, 'MyConst > 2', mParts) = TConditionValue.Unknown);
  Assert.AreEqual(1, Integer(Length(mParts)));
  Assert.AreEqual('MyConst', mParts[0].Text);
  Assert.AreEqual('unbekannt', mParts[0].Value);
  Assert.AreEqual('Konstante aus dem Code', mParts[0].Origin);
end;

procedure TPreprocessorExpressionsTests.DeclaredAsksSettings;
var
  mSettings: TExpressionSettings;
  mParts: TArray<TConditionPart>;
begin
  mSettings := Win64Settings;
  mSettings.Declared :=
    function(const AName: string): Boolean
    begin
      Result := SameText(AName, 'TKnown');
    end;
  Assert.IsTrue(EvaluateWith(mSettings, 'Declared(TKnown)', mParts) = TConditionValue.Yes);
  Assert.AreEqual('Index', mParts[0].Origin);
  Assert.IsTrue(EvaluateWith(mSettings, 'Declared(TOther)', mParts) = TConditionValue.Unknown);
  mSettings.Constants := [TPair<string, Double>.Create('MyLevel', 3)];
  Assert.IsTrue(EvaluateWith(mSettings, 'MyLevel = 3', mParts) = TConditionValue.Yes);
  Assert.IsTrue(EvaluateWith(mSettings, 'Declared(MyLevel)', mParts) = TConditionValue.Yes);
end;

procedure TPreprocessorExpressionsTests.VersionConstantsFollowCompilerVersion;
var
  mSettings: TExpressionSettings;
  mParts: TArray<TConditionPart>;
begin
  Assert.IsTrue(Evaluate('RTLVersion123') = TConditionValue.Yes);
  mSettings := Win64Settings;
  mSettings.CompilerVersion := 35;
  Assert.IsTrue(EvaluateWith(mSettings, 'RTLVersion121', mParts) = TConditionValue.No);
  Assert.AreEqual('Delphi 13', mParts[0].Origin);
  mSettings.CompilerVersion := 0;
  Assert.IsTrue(EvaluateWith(mSettings, 'RTLVersion121', mParts) = TConditionValue.Unknown);
end;

procedure TPreprocessorExpressionsTests.SyntaxErrorRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      Evaluate('Defined(');
    end, EPreprocessorExpression);
  Assert.WillRaise(
    procedure
    begin
      Evaluate('Foo(1)');
    end, EPreprocessorExpression);
end;

initialization
  TDUnitX.RegisterTestFixture(TPreprocessorExpressionsTests);

end.
