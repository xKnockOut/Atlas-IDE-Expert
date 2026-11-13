unit Atlas.Common.Lsp.Completion.TypeConversions.Tests;

// Typverträglichkeit (#417) und Umwandlung in den erwarteten Typ (#490).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeConversionsTests = class
  public
    [Test]
    procedure TypeFitsFamiliesAndDescent;
    [Test]
    procedure TypeConversionPairs;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Lsp.Completion.TypeConversions;

procedure TTypeConversionsTests.TypeFitsFamiliesAndDescent;
var
  CheckDescent: Boolean;
begin
  Assert.IsTrue(TypeFits('Integer', 'Double', CheckDescent));
  Assert.IsTrue(TypeFits('Char', 'string', CheckDescent));
  Assert.IsTrue(TypeFits('System.Classes.TStrings', 'TStrings', CheckDescent));
  Assert.IsFalse(TypeFits('Double', 'Integer', CheckDescent));
  Assert.IsFalse(CheckDescent);
  Assert.IsFalse(TypeFits('TButton', 'TControl', CheckDescent));
  Assert.IsTrue(CheckDescent, 'Klassen klärt die Namensauflösung');
end;

function Converted(const AActual, AExpected: string; AHelper: Boolean): string;
var
  Conversion: TTypeConversion;
begin
  Result := '-';
  if TypeConversion(AActual, AExpected, '', 'X', AHelper, Conversion) then
  begin
    if Conversion.Lossy then
    begin
      Result := 'lossy';
    end
    else
    begin
      Result := Conversion.Text + ' | ' + string.Join(',', Conversion.Units);
    end;
  end;
end;

procedure TTypeConversionsTests.TypeConversionPairs;
var
  Conversion: TTypeConversion;
begin
  // Tabelle aus #490, Funktions- und Helper-Stil.
  Assert.AreEqual('IntToStr(X) | System.SysUtils', Converted('Integer', 'string', False));
  Assert.AreEqual('X.ToString | System.SysUtils', Converted('Int64', 'string', True));
  Assert.AreEqual('StrToInt(X) | System.SysUtils', Converted('string', 'Integer', False));
  Assert.AreEqual('X.ToInteger | System.SysUtils', Converted('string', 'Integer', True));
  Assert.AreEqual('X.ToInt64 | System.SysUtils', Converted('string', 'Int64', True));
  Assert.AreEqual('FloatToStr(X) | System.SysUtils', Converted('Currency', 'string', False));
  Assert.AreEqual('X.ToString | System.SysUtils', Converted('Double', 'string', True));
  Assert.AreEqual('StrToFloat(X) | System.SysUtils', Converted('string', 'Double', False));
  Assert.AreEqual('X.ToDouble | System.SysUtils', Converted('string', 'Double', True));
  Assert.AreEqual('BoolToStr(X, True) | System.SysUtils', Converted('Boolean', 'string', False));
  Assert.AreEqual('X.ToString(TUseBoolStrs.True) | System.SysUtils', Converted('Boolean', 'string', True));
  // TDateTime und Aufzählung haben keinen Helper: immer die Funktion.
  Assert.AreEqual('DateTimeToStr(X) | System.SysUtils', Converted('TDateTime', 'string', True));
  Assert.IsTrue(TypeConversion('', 'string', 'TFarbe', 'X', True, Conversion));
  Assert.AreEqual('GetEnumName(TypeInfo(TFarbe), Ord(X))', Conversion.Text);
  Assert.AreEqual('System.TypInfo', string.Join(',', Conversion.Units));
  // Verlustbehaftet nur als Hinweis; Passendes und Unbekanntes ohne Umwandlung.
  Assert.AreEqual('lossy', Converted('Double', 'Integer', True));
  Assert.AreEqual('-', Converted('Integer', 'Double', True));
  Assert.AreEqual('-', Converted('string', 'string', True));
  Assert.AreEqual('-', Converted('TKunde', 'string', True));
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeConversionsTests);

end.
