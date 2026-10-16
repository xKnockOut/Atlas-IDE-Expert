unit Atlas.Text.Defines.Tests;

// Tests der Compilersymbole (#759): vordefinierte Symbole je Plattform,
// Compilerversion zur BDS-Version und Erkennung von Symbolen des Compilers.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextDefinesTests = class
  public
    [Test]
    procedure PredefinedForWin32AndVersion;
    [Test]
    procedure PredefinedForWin64WithoutVersion;
    [Test]
    procedure PredefinedForMobile;
    [Test]
    procedure CompilerVersionOfBds;
    [Test]
    procedure KnowsCompilerSymbols;
    [Test]
    procedure RejectsProjectSymbols;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Defines;

function Has(const ASymbols: TArray<string>; const AName: string): Boolean;
var
  Symbol: string;
begin
  for Symbol in ASymbols do
    if SameText(Symbol, AName) then
      Exit(True);
  Result := False;
end;

procedure TTextDefinesTests.PredefinedForWin32AndVersion;
var
  Symbols: TArray<string>;
begin
  Symbols := TTextDefines.Predefined('Win32', 36.0);
  Assert.IsTrue(Has(Symbols, 'MSWINDOWS'));
  Assert.IsTrue(Has(Symbols, 'WIN32'));
  Assert.IsTrue(Has(Symbols, 'CPUX86'));
  Assert.IsTrue(Has(Symbols, 'VER360'));
  Assert.IsTrue(Has(Symbols, 'UNICODE'));
  Assert.IsFalse(Has(Symbols, 'WIN64'));
  // Leere Plattform gilt als Win32.
  Assert.IsTrue(Has(TTextDefines.Predefined('', 0), 'WIN32'));
end;

procedure TTextDefinesTests.PredefinedForWin64WithoutVersion;
var
  Symbols: TArray<string>;
  Symbol: string;
begin
  Symbols := TTextDefines.Predefined('win64', 0);
  Assert.IsTrue(Has(Symbols, 'WIN64'));
  Assert.IsTrue(Has(Symbols, 'CPU64BITS'));
  for Symbol in Symbols do
    Assert.IsFalse(Symbol.StartsWith('VER'), Symbol);
end;

procedure TTextDefinesTests.PredefinedForMobile;
begin
  Assert.IsTrue(Has(TTextDefines.Predefined('Android64', 37.0), 'ANDROID'));
  Assert.IsTrue(Has(TTextDefines.Predefined('Android64', 37.0), 'VER370'));
  Assert.IsTrue(Has(TTextDefines.Predefined('iOSSimARM64', 37.0), 'IOSSIMULATOR'));
  Assert.IsTrue(Has(TTextDefines.Predefined('OSXARM64', 37.0), 'CPUARM64'));
  Assert.IsFalse(Has(TTextDefines.Predefined('OSXARM64', 37.0), 'CPUX64'));
end;

procedure TTextDefinesTests.CompilerVersionOfBds;
begin
  Assert.AreEqual(36.0, TTextDefines.CompilerVersionOfBds(23.0), 0.001);
  Assert.AreEqual(37.0, TTextDefines.CompilerVersionOfBds(37.0), 0.001);
  Assert.AreEqual(0.0, TTextDefines.CompilerVersionOfBds(5), 0.001);
end;

procedure TTextDefinesTests.KnowsCompilerSymbols;
begin
  Assert.IsTrue(TTextDefines.IsCompilerSymbol('MSWINDOWS'));
  Assert.IsTrue(TTextDefines.IsCompilerSymbol('android'));
  Assert.IsTrue(TTextDefines.IsCompilerSymbol('VER150'));
  Assert.IsTrue(TTextDefines.IsCompilerSymbol('VER370'));
  Assert.IsTrue(TTextDefines.IsCompilerSymbol(' CONSOLE '));
end;

procedure TTextDefinesTests.RejectsProjectSymbols;
begin
  Assert.IsFalse(TTextDefines.IsCompilerSymbol(''));
  Assert.IsFalse(TTextDefines.IsCompilerSymbol('DEBUG'));
  Assert.IsFalse(TTextDefines.IsCompilerSymbol('USE_LOGGING'));
  Assert.IsFalse(TTextDefines.IsCompilerSymbol('VER'));
  Assert.IsFalse(TTextDefines.IsCompilerSymbol('VERBOSE'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextDefinesTests);

end.
