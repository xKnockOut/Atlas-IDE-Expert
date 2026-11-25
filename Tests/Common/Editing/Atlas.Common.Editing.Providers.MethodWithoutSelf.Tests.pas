unit Atlas.Common.Editing.Providers.MethodWithoutSelf.Tests;

// Tests für IEditingMethodsWithoutSelf (#686): Treffer samt Umwandlung in eine class-Methode, Methoden mit Feldern
// und Ereignisse der Formulardatei bleiben draußen, ohne Syntaxbaum kein Treffer.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingMethodsWithoutSelfProviderTests = class
  public
    [Test]
    procedure FindsMethodWithClassMethodFix;
    [Test]
    procedure FormEventIsLeftOut;
    [Test]
    procedure NoUnitNoResult;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.Contract.MethodWithoutSelf,
  Atlas.Common.Editing.Composition,
  Atlas.Tests.TextEdits;

const
  cSource =
    'unit Rechner;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TRechner = class'#10 +
    '  private'#10 +
    '    FWert: Integer;'#10 +
    '  public'#10 +
    '    function Doppelt(A: Integer): Integer;'#10 +
    '    function Wert: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TRechner.Doppelt(A: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A * 2;'#10 +
    'end;'#10 +
    'function TRechner.Wert: Integer;'#10 +
    'begin'#10 +
    '  Result := FWert;'#10 +
    'end;'#10 +
    'end.';

function ScanOf(const AText, AFormText: string): TEditingMethodScan;
begin
  Result := Default(TEditingMethodScan);
  Result.FileName := 'Rechner.pas';
  Result.Text := AText;
  Result.FormText := AFormText;
  Result.WithStatic := True;
  Result.Style := TFormatStyle.Default;
end;

{ TEditingMethodsWithoutSelfProviderTests }

procedure TEditingMethodsWithoutSelfProviderTests.FindsMethodWithClassMethodFix;
var
  mFound: TArray<TEditingMethodWithoutSelf>;
  mText: string;
begin
  mFound := TEditingComposition.MethodsWithoutSelf.Scan(ScanOf(cSource, ''));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('TRechner', mFound[0].ClassName);
  Assert.AreEqual('Doppelt', mFound[0].Name);
  Assert.AreEqual(11, mFound[0].NamePosition.Line);
  Assert.IsTrue(mFound[0].HasFix);
  Assert.AreEqual('In class-Methode umwandeln', mFound[0].Fix.Title);
  mText := TTestEdits.Apply(cSource, mFound[0].Fix.Edits);
  Assert.IsTrue(Pos('class function Doppelt(A: Integer): Integer; static;', mText) > 0, mText);
end;

procedure TEditingMethodsWithoutSelfProviderTests.FormEventIsLeftOut;
begin
  Assert.AreEqual(0, Integer(Length(TEditingComposition.MethodsWithoutSelf.Scan(ScanOf(cSource,
    'object Form1: TForm1'#10'  OnClick = Doppelt'#10'end')))));
end;

procedure TEditingMethodsWithoutSelfProviderTests.NoUnitNoResult;
begin
  Assert.AreEqual(0, Integer(Length(TEditingComposition.MethodsWithoutSelf.Scan(ScanOf('', '')))));
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingMethodsWithoutSelfProviderTests);

end.
