unit Atlas.Core.Build.CompilerSwitches.Tests;

// Fenster „Compiler-Schalter“ (#558), Kern: Antwort des Servers in Zeilen je
// Abschnitt mit Herkunft, Sprung nur mit Datei und Zeile, Projektoptionen
// bei Werten aus der .dproj, Minuszeichen, Entprellen der Cursorbewegung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasCompilerSwitchViewTests = class
  public
    [Test]
    procedure ReadsSectionsInOrder;
    [Test]
    procedure DirectiveOriginCanJump;
    [Test]
    procedure ProjectOriginOpensOptions;
    [Test]
    procedure TargetOnlyWithProject;
    [Test]
    procedure NullIsNoView;
    [Test]
    procedure DeviationsOnly;
    [Test]
    procedure MinusIsTypographic;
    [Test]
    procedure FollowWaitsForQuietCursor;
    [Test]
    procedure FollowInvalidateAsksAtOnce;
    [Test]
    procedure OnlyPascalFiles;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Build.CompilerSwitches;

const
  cAnswer =
    '{"configuration":"Debug","platform":"Win64","hasProject":true,"summary":"HINTS OFF",' +
    '"switches":[{"name":"R","longName":"RANGECHECKS","value":"-","projectValue":"+","deviates":true,' +
    '"origin":{"kind":"directive","text":"{$R-}","file":"C:\\P\\A.pas","line":9}},' +
    '{"name":"Q","longName":"OVERFLOWCHECKS","value":"+","projectValue":"+","deviates":false,' +
    '"origin":{"kind":"project","text":"DCC_IntegerOverflowCheck"}}],' +
    '"hints":{"name":"HINTS","value":"ON","projectValue":"ON","deviates":false,"origin":{"kind":"default","text":""}},' +
    '"warnings":{"name":"WARNINGS","value":"ON","projectValue":"ON","deviates":false,' +
    '"origin":{"kind":"default","text":""}},' +
    '"warns":[{"name":"SYMBOL_PLATFORM","value":"OFF","projectValue":"ON","deviates":true,' +
    '"origin":{"kind":"include","text":"{$WARN SYMBOL_PLATFORM OFF}","file":"C:\\P\\Opt.inc","line":2}}],' +
    '"defines":[{"name":"DEBUG","origin":{"kind":"project","text":"Konfiguration Debug (.dproj)"}}]}';

function Parse(const AText: string; out AView: TAtlasCompilerSwitchView): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    Result := TAtlasCompilerSwitchView.FromJson(mValue, AView);
  finally
    mValue.Free;
  end;
end;

{ TAtlasCompilerSwitchViewTests }

procedure TAtlasCompilerSwitchViewTests.ReadsSectionsInOrder;
var
  mView: TAtlasCompilerSwitchView;
  mNames: string;
  mRow: TAtlasSwitchRow;
begin
  Assert.IsTrue(Parse(cAnswer, mView));
  Assert.AreEqual('Debug', mView.Configuration);
  Assert.AreEqual('Win64', mView.Platform);
  Assert.AreEqual('HINTS OFF', mView.Summary);
  mNames := '';
  for mRow in mView.Rows do
  begin
    mNames := mNames + IntToStr(Ord(mRow.Section)) + ':' + mRow.Name + ' ';
  end;
  Assert.AreEqual('0:R 0:Q 1:HINTS 1:WARNINGS 1:SYMBOL_PLATFORM 2:DEBUG 3:platform 3:configuration ', mNames);
  Assert.AreEqual('RANGECHECKS', mView.Rows[0].LongName);
  Assert.AreEqual('Konfiguration Debug (.dproj)', mView.Rows[5].OriginText);
end;

procedure TAtlasCompilerSwitchViewTests.DirectiveOriginCanJump;
var
  mView: TAtlasCompilerSwitchView;
begin
  Assert.IsTrue(Parse(cAnswer, mView));
  Assert.IsTrue(mView.Rows[0].CanJump);
  Assert.AreEqual('C:\P\A.pas', mView.Rows[0].FileName);
  Assert.AreEqual(9, mView.Rows[0].Line);
  Assert.IsTrue(mView.Rows[4].Kind = TAtlasSwitchOriginKind.Include);
  Assert.IsTrue(mView.Rows[4].CanJump);
  Assert.AreEqual('C:\P\Opt.inc', mView.Rows[4].FileName);
  Assert.IsFalse(mView.Rows[1].CanJump);
  Assert.IsFalse(mView.Rows[2].CanJump);
end;

procedure TAtlasCompilerSwitchViewTests.ProjectOriginOpensOptions;
var
  mView: TAtlasCompilerSwitchView;
begin
  Assert.IsTrue(Parse(cAnswer, mView));
  Assert.IsTrue(mView.Rows[1].FromProject);
  Assert.AreEqual('DCC_IntegerOverflowCheck', mView.Rows[1].OriginText);
  Assert.IsFalse(mView.Rows[0].FromProject);
  Assert.IsFalse(mView.Rows[2].FromProject);
  Assert.IsTrue(mView.Rows[6].FromProject);
end;

procedure TAtlasCompilerSwitchViewTests.TargetOnlyWithProject;
var
  mView: TAtlasCompilerSwitchView;
begin
  Assert.IsTrue(Parse('{"configuration":"","platform":"","hasProject":false,"summary":"","switches":[]}', mView));
  Assert.AreEqual(0, Integer(Length(mView.Rows)));
end;

procedure TAtlasCompilerSwitchViewTests.NullIsNoView;
var
  mView: TAtlasCompilerSwitchView;
begin
  Assert.IsFalse(Parse('null', mView));
  Assert.IsFalse(TAtlasCompilerSwitchView.FromJson(nil, mView));
  Assert.AreEqual(0, Integer(Length(mView.Rows)));
end;

procedure TAtlasCompilerSwitchViewTests.DeviationsOnly;
var
  mView: TAtlasCompilerSwitchView;
  mRows: TAtlasSwitchRows;
begin
  Assert.IsTrue(Parse(cAnswer, mView));
  mRows := mView.Deviations;
  Assert.AreEqual(2, Integer(Length(mRows)));
  Assert.AreEqual('R', mRows[0].Name);
  Assert.AreEqual('SYMBOL_PLATFORM', mRows[1].Name);
end;

procedure TAtlasCompilerSwitchViewTests.MinusIsTypographic;
begin
  Assert.AreEqual(string(#$2212), TAtlasCompilerSwitchTexts.Value('-'));
  Assert.AreEqual('+', TAtlasCompilerSwitchTexts.Value('+'));
  Assert.AreEqual('OFF', TAtlasCompilerSwitchTexts.Value('OFF'));
end;

procedure TAtlasCompilerSwitchViewTests.FollowWaitsForQuietCursor;
var
  mFollow: TAtlasSwitchFollow;
begin
  mFollow := TAtlasSwitchFollow.Create;
  try
    Assert.IsFalse(mFollow.Due(1000), 'ohne Cursor nichts fällig');
    Assert.IsTrue(mFollow.Moved('C:\P\A.pas', 3, 0, 1000));
    Assert.IsFalse(mFollow.Due(1100));
    Assert.IsTrue(mFollow.Moved('C:\P\A.pas', 4, 0, 1100), 'neue Zeile');
    Assert.IsFalse(mFollow.Due(1200), '150 ms ab der letzten Bewegung');
    Assert.IsFalse(mFollow.Moved('c:\p\a.pas', 4, 0, 1240), 'gleiche Stelle');
    Assert.IsTrue(mFollow.Due(1250));
    Assert.IsFalse(mFollow.Due(1400), 'nur einmal');
    Assert.AreEqual(4, mFollow.Line);
  finally
    mFollow.Free;
  end;
end;

procedure TAtlasCompilerSwitchViewTests.FollowInvalidateAsksAtOnce;
var
  mFollow: TAtlasSwitchFollow;
begin
  mFollow := TAtlasSwitchFollow.Create;
  try
    mFollow.Moved('C:\P\A.pas', 3, 0, 1000);
    Assert.IsTrue(mFollow.Due(1200));
    mFollow.Invalidate;
    Assert.IsTrue(mFollow.Due(1201));
    Assert.IsFalse(mFollow.Due(1500));
  finally
    mFollow.Free;
  end;
end;

procedure TAtlasCompilerSwitchViewTests.OnlyPascalFiles;
begin
  Assert.IsTrue(TAtlasSwitchFollow.Applies('C:\P\A.pas'));
  Assert.IsTrue(TAtlasSwitchFollow.Applies('C:\P\Projekt.DPR'));
  Assert.IsTrue(TAtlasSwitchFollow.Applies('C:\P\Optionen.inc'));
  Assert.IsFalse(TAtlasSwitchFollow.Applies('C:\P\Form.dfm'));
  Assert.IsFalse(TAtlasSwitchFollow.Applies(''));
end;

end.
