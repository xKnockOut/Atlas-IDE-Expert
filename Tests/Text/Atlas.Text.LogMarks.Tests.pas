unit Atlas.Text.LogMarks.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Kennzeichen für Namen, Pfade und fremden Text in Protokollzeilen (#1478).</summary>
  [TestFixture]
  TLogMarksTests = class
  public
    [Test]
    procedure PlainRestoresValues;
    [Test]
    procedure ResolvePassesKindAndValue;
    [Test]
    procedure EmptyValueStaysEmpty;
    [Test]
    procedure MarkCharsInValueCannotEscape;
    [Test]
    procedure UnterminatedMarkReachesEnd;
    [Test]
    procedure TextWithoutMarksIsUnchanged;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.LogMarks;

procedure TLogMarksTests.PlainRestoresValues;
var
  mLine: string;
begin
  mLine := 'Projekt ' + TLogMarks.Name('Kunden') + ' in ' + TLogMarks.Path('C:\Kunden\Kunden.dproj') + ': ' +
    TLogMarks.Text('Zugriff auf TKunde.Speichern');
  Assert.IsTrue(TLogMarks.HasMarks(mLine));
  Assert.AreEqual('Projekt Kunden in C:\Kunden\Kunden.dproj: Zugriff auf TKunde.Speichern', TLogMarks.Plain(mLine));
end;

procedure TLogMarksTests.ResolvePassesKindAndValue;
var
  mText: string;
begin
  mText := TLogMarks.Resolve('a ' + TLogMarks.Name('N1') + ' b ' + TLogMarks.Path('P1') + ' c ' +
    TLogMarks.Text('T1'),
    function(AKind: TLogMarkKind; const AValue: string): string
    begin
      Result := '[' + TLogMarks.KindChars[AKind] + ':' + AValue + ']';
    end);
  Assert.AreEqual('a [N:N1] b [P:P1] c [T:T1]', mText);
end;

procedure TLogMarksTests.EmptyValueStaysEmpty;
begin
  Assert.AreEqual('', TLogMarks.Name(''));
  Assert.AreEqual('x', TLogMarks.Plain('x' + TLogMarks.Path('')));
end;

procedure TLogMarksTests.MarkCharsInValueCannotEscape;
var
  mValue, mText: string;
begin
  // Ein Wert mit eigenem Endzeichen darf das Kennzeichen nicht vorzeitig schließen.
  mValue := 'Geheim' + TLogMarks.StopChar + 'Rest';
  mText := TLogMarks.Resolve(TLogMarks.Name(mValue),
    function(AKind: TLogMarkKind; const AValue: string): string
    begin
      Result := '<name>';
    end);
  Assert.AreEqual('<name>', mText);
end;

procedure TLogMarksTests.UnterminatedMarkReachesEnd;
var
  mText: string;
begin
  mText := TLogMarks.Resolve('a ' + TLogMarks.StartChar + 'NGeheim',
    function(AKind: TLogMarkKind; const AValue: string): string
    begin
      Result := '<' + AValue.Length.ToString + '>';
    end);
  Assert.AreEqual('a <6>', mText);
  Assert.AreEqual('ab', TLogMarks.Plain('a' + TLogMarks.StopChar + 'b'));
end;

procedure TLogMarksTests.TextWithoutMarksIsUnchanged;
begin
  Assert.IsFalse(TLogMarks.HasMarks('index project#1 done 12 ms mem 40 MB'));
  Assert.AreEqual('index project#1 done 12 ms mem 40 MB', TLogMarks.Plain('index project#1 done 12 ms mem 40 MB'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLogMarksTests);

end.
