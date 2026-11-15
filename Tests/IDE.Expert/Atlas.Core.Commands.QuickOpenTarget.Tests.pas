unit Atlas.Core.Commands.QuickOpenTarget.Tests;

// Tests für das Ziel eines Eintrags von „Datei und Symbol schnell öffnen“ (#503, #1967): Kennung hin und zurück,
// Hinweise ohne Ziel, Zeile aus der Eingabe und die zweite Zeile eines Projektsymbols.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasQuickOpenTargetTests = class
  public
    [Test]
    procedure IdRoundTrips;
    [Test]
    procedure HintsHaveNoTarget;
    [Test]
    procedure UnreadableNumbersOpenFile;
    [Test]
    procedure FileLineFromQuery;
    [Test]
    procedure SymbolPlaceWithAndWithoutContainer;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Commands.QuickOpenTarget;

{ TAtlasQuickOpenTargetTests }

procedure TAtlasQuickOpenTargetTests.IdRoundTrips;
var
  mTarget: TAtlasQuickOpenTarget;
begin
  Assert.AreEqual('12:4', TAtlasQuickOpenTarget.IdOf(12, 4));
  Assert.IsTrue(TAtlasQuickOpenTarget.TryParse(TAtlasQuickOpenTarget.IdOf(12, 4), 'Unit1.pas', mTarget));
  Assert.AreEqual('Unit1.pas', mTarget.FileName);
  Assert.AreEqual(12, mTarget.Line);
  Assert.AreEqual(4, mTarget.Character);
  Assert.IsTrue(mTarget.GoesToLine);
  Assert.IsTrue(TAtlasQuickOpenTarget.TryParse(TAtlasQuickOpenTarget.IdOf(-1, 0), 'Unit1.pas', mTarget));
  Assert.IsFalse(mTarget.GoesToLine, 'Zeile -1: nur öffnen');
end;

procedure TAtlasQuickOpenTargetTests.HintsHaveNoTarget;
var
  mTarget: TAtlasQuickOpenTarget;
begin
  Assert.IsFalse(TAtlasQuickOpenTarget.TryParse('', '', mTarget), 'Hinweis ohne Kennung und Datei');
  Assert.IsFalse(TAtlasQuickOpenTarget.TryParse('3:0', '', mTarget), 'ohne Datei');
  Assert.IsFalse(TAtlasQuickOpenTarget.TryParse('3', 'Unit1.pas', mTarget), 'ohne Zeichen');
  Assert.IsFalse(TAtlasQuickOpenTarget.TryParse('1:2:3', 'Unit1.pas', mTarget));
  Assert.AreEqual('', mTarget.FileName);
end;

procedure TAtlasQuickOpenTargetTests.UnreadableNumbersOpenFile;
var
  mTarget: TAtlasQuickOpenTarget;
begin
  Assert.IsTrue(TAtlasQuickOpenTarget.TryParse('x:y', 'Unit1.pas', mTarget));
  Assert.AreEqual(-1, mTarget.Line);
  Assert.AreEqual(0, mTarget.Character);
  Assert.IsFalse(mTarget.GoesToLine);
end;

procedure TAtlasQuickOpenTargetTests.FileLineFromQuery;
begin
  Assert.AreEqual(-1, TAtlasQuickOpenTarget.FileLine(0), 'ohne Zeile');
  Assert.AreEqual(0, TAtlasQuickOpenTarget.FileLine(1));
  Assert.AreEqual(122, TAtlasQuickOpenTarget.FileLine(123));
  Assert.AreEqual(-1, TAtlasQuickOpenTarget.FileLine(-4));
end;

procedure TAtlasQuickOpenTargetTests.SymbolPlaceWithAndWithoutContainer;
begin
  Assert.AreEqual('TForm1 · Unit1.pas', TAtlasQuickOpenTarget.SymbolPlace('TForm1',
    'Src' + PathDelim + 'Unit1.pas'));
  Assert.AreEqual('Unit1.pas', TAtlasQuickOpenTarget.SymbolPlace('', 'Src' + PathDelim + 'Unit1.pas'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuickOpenTargetTests);

end.
