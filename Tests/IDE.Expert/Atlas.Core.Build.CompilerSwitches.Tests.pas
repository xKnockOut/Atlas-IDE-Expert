unit Atlas.Core.Build.CompilerSwitches.Tests;

// Fenster „Compiler-Schalter“ (#558), Kern: Antwort des Servers in Zeilen je
// Abschnitt mit Herkunft, Sprung nur mit Datei und Zeile, Projektoptionen
// bei Werten aus der .dproj, Minuszeichen, Entprellen der Cursorbewegung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
  Answer =
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
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AText);
  try
    Result := TAtlasCompilerSwitchView.FromJson(Value, AView);
  finally
    Value.Free;
  end;
end;

{ TAtlasCompilerSwitchViewTests }

procedure TAtlasCompilerSwitchViewTests.ReadsSectionsInOrder;
var
  View: TAtlasCompilerSwitchView;
  Names: string;
  Row: TAtlasSwitchRow;
begin
  Assert.IsTrue(Parse(Answer, View));
  Assert.AreEqual('Debug', View.Configuration);
  Assert.AreEqual('Win64', View.Platform);
  Assert.AreEqual('HINTS OFF', View.Summary);
  Names := '';
  for Row in View.Rows do
    Names := Names + IntToStr(Ord(Row.Section)) + ':' + Row.Name + ' ';
  Assert.AreEqual('0:R 0:Q 1:HINTS 1:WARNINGS 1:SYMBOL_PLATFORM 2:DEBUG 3:platform 3:configuration ', Names);
  Assert.AreEqual('RANGECHECKS', View.Rows[0].LongName);
  Assert.AreEqual('Konfiguration Debug (.dproj)', View.Rows[5].OriginText);
end;

procedure TAtlasCompilerSwitchViewTests.DirectiveOriginCanJump;
var
  View: TAtlasCompilerSwitchView;
begin
  Assert.IsTrue(Parse(Answer, View));
  Assert.IsTrue(View.Rows[0].CanJump);
  Assert.AreEqual('C:\P\A.pas', View.Rows[0].FileName);
  Assert.AreEqual(9, View.Rows[0].Line);
  Assert.IsTrue(View.Rows[4].Kind = TAtlasSwitchOriginKind.Include);
  Assert.IsTrue(View.Rows[4].CanJump);
  Assert.AreEqual('C:\P\Opt.inc', View.Rows[4].FileName);
  Assert.IsFalse(View.Rows[1].CanJump);
  Assert.IsFalse(View.Rows[2].CanJump);
end;

procedure TAtlasCompilerSwitchViewTests.ProjectOriginOpensOptions;
var
  View: TAtlasCompilerSwitchView;
begin
  Assert.IsTrue(Parse(Answer, View));
  Assert.IsTrue(View.Rows[1].FromProject);
  Assert.AreEqual('DCC_IntegerOverflowCheck', View.Rows[1].OriginText);
  Assert.IsFalse(View.Rows[0].FromProject);
  Assert.IsFalse(View.Rows[2].FromProject);
  Assert.IsTrue(View.Rows[6].FromProject);
end;

procedure TAtlasCompilerSwitchViewTests.TargetOnlyWithProject;
var
  View: TAtlasCompilerSwitchView;
begin
  Assert.IsTrue(Parse('{"configuration":"","platform":"","hasProject":false,"summary":"","switches":[]}', View));
  Assert.AreEqual(0, Integer(Length(View.Rows)));
end;

procedure TAtlasCompilerSwitchViewTests.NullIsNoView;
var
  View: TAtlasCompilerSwitchView;
begin
  Assert.IsFalse(Parse('null', View));
  Assert.IsFalse(TAtlasCompilerSwitchView.FromJson(nil, View));
  Assert.AreEqual(0, Integer(Length(View.Rows)));
end;

procedure TAtlasCompilerSwitchViewTests.DeviationsOnly;
var
  View: TAtlasCompilerSwitchView;
  Rows: TAtlasSwitchRows;
begin
  Assert.IsTrue(Parse(Answer, View));
  Rows := View.Deviations;
  Assert.AreEqual(2, Integer(Length(Rows)));
  Assert.AreEqual('R', Rows[0].Name);
  Assert.AreEqual('SYMBOL_PLATFORM', Rows[1].Name);
end;

procedure TAtlasCompilerSwitchViewTests.MinusIsTypographic;
begin
  Assert.AreEqual(string(#$2212), TAtlasCompilerSwitchTexts.Value('-'));
  Assert.AreEqual('+', TAtlasCompilerSwitchTexts.Value('+'));
  Assert.AreEqual('OFF', TAtlasCompilerSwitchTexts.Value('OFF'));
end;

procedure TAtlasCompilerSwitchViewTests.FollowWaitsForQuietCursor;
var
  Follow: TAtlasSwitchFollow;
begin
  Follow := TAtlasSwitchFollow.Create;
  try
    Assert.IsFalse(Follow.Due(1000), 'ohne Cursor nichts fällig');
    Assert.IsTrue(Follow.Moved('C:\P\A.pas', 3, 0, 1000));
    Assert.IsFalse(Follow.Due(1100));
    Assert.IsTrue(Follow.Moved('C:\P\A.pas', 4, 0, 1100), 'neue Zeile');
    Assert.IsFalse(Follow.Due(1200), '150 ms ab der letzten Bewegung');
    Assert.IsFalse(Follow.Moved('c:\p\a.pas', 4, 0, 1240), 'gleiche Stelle');
    Assert.IsTrue(Follow.Due(1250));
    Assert.IsFalse(Follow.Due(1400), 'nur einmal');
    Assert.AreEqual(4, Follow.Line);
  finally
    Follow.Free;
  end;
end;

procedure TAtlasCompilerSwitchViewTests.FollowInvalidateAsksAtOnce;
var
  Follow: TAtlasSwitchFollow;
begin
  Follow := TAtlasSwitchFollow.Create;
  try
    Follow.Moved('C:\P\A.pas', 3, 0, 1000);
    Assert.IsTrue(Follow.Due(1200));
    Follow.Invalidate;
    Assert.IsTrue(Follow.Due(1201));
    Assert.IsFalse(Follow.Due(1500));
  finally
    Follow.Free;
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
