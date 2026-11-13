unit Atlas.Core.Debug.Forecast.Tests;

// Tests für „Bedingungen vorausschauen“ (#2169) ohne IDE: Antwort lesen,
// Zweig bei if, while und case, Kurzschluss ohne Aufruf, Text je Kopfzeile,
// blasse Zeilen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.Forecast;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasForecastTests = class
  private
    FForecast: TAtlasForecast;
    FTexts: TAtlasForecastTexts;
    procedure Load(const AJson: string);
    /// <summary>Wertet alle ausstehenden Teile mit AValues (Ausdruck=Wert, ';' getrennt) aus; Rückgabe: die
    /// Ausdrücke in Reihenfolge.</summary>
    function EvaluateAll(const AValues: string): string;
    /// <summary>Blasse Zeilen von 0 bis ALast als Liste „3 4“.</summary>
    function DimmedLines(ALast: Integer): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsAnswerWithBranches;
    [Test]
    procedure AcceptanceIfAndCase;
    [Test]
    procedure CallIsNeverEvaluated;
    [Test]
    procedure TrueTakesThenBranch;
    [Test]
    procedure IfWithoutElseFalseDimsThen;
    [Test]
    procedure WhileFalseDimsBody;
    [Test]
    procedure CaseWithoutMatchTakesElse;
    [Test]
    procedure CaseWithoutMatchAndElse;
    [Test]
    procedure CaseRangeWithNumbers;
    [Test]
    procedure UnknownValueGivesNoForecast;
    [Test]
    procedure OtherFileHasNothing;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Debug.WhyHere;

const
  cFile = 'C:\Src\Sender.pas';
  // Wie die Antwort des Servers für das Beispiel aus #2169:
  //   1  if (mOffen > 0) and FOnline then
  //   2    SendQueue
  //   3  else
  //   4    Log('nichts');
  //   5  case FMode of
  //   6    smAuto: Reschedule;
  //   7    smManual: ;
  //   8  end;
  cAcceptance =
    '{"format":1,"blocks":[' +
    '{"kind":"if","line":1,"parts":[' +
      '{"kind":"and","operator":"and","text":"(mOffen > 0) and FOnline","parent":-1},' +
      '{"kind":"compare","operator":">","text":"mOffen > 0","parent":0},' +
      '{"kind":"value","text":"mOffen","parent":1},' +
      '{"kind":"value","text":"0","parent":1},' +
      '{"kind":"value","text":"FOnline","parent":0}],' +
      '"branches":[{"name":"then","from":2,"to":2,"labels":[]},{"name":"else","from":4,"to":4,"labels":[]}]},' +
    '{"kind":"case","line":5,"parts":[' +
      '{"kind":"value","text":"FMode","parent":-1},' +
      '{"kind":"value","text":"smAuto","parent":-1},' +
      '{"kind":"value","text":"smManual","parent":-1}],' +
      '"branches":[{"name":"item","from":6,"to":6,"labels":[[1,-1]]},' +
      '{"name":"item","from":7,"to":7,"labels":[[2,-1]]}]}]}';

  // if Bereit and Pruefe then … else …: Pruefe ist ein Aufruf.
  cWithCall =
    '{"format":1,"blocks":[{"kind":"if","line":1,"parts":[' +
      '{"kind":"and","operator":"and","text":"Bereit and Pruefe","parent":-1,"call":true},' +
      '{"kind":"value","text":"Bereit","parent":0},' +
      '{"kind":"value","text":"Pruefe","parent":0,"call":true}],' +
      '"branches":[{"name":"then","from":2,"to":3,"labels":[]},{"name":"else","from":4,"to":5,"labels":[]}]}]}';

  // if Fertig then (ohne else) und while Laeuft do.
  cIfWhile =
    '{"format":1,"blocks":[' +
    '{"kind":"if","line":1,"parts":[{"kind":"value","text":"Fertig","parent":-1}],' +
      '"branches":[{"name":"then","from":2,"to":4,"labels":[]}]},' +
    '{"kind":"while","line":6,"parts":[{"kind":"value","text":"Laeuft","parent":-1}],' +
      '"branches":[{"name":"body","from":7,"to":9,"labels":[]}]}]}';

  // case N of 1: …; 2..5: …; else … end;
  cCaseRange =
    '{"format":1,"blocks":[{"kind":"case","line":1,"parts":[' +
      '{"kind":"value","text":"N","parent":-1},' +
      '{"kind":"value","text":"1","parent":-1},' +
      '{"kind":"value","text":"2","parent":-1},' +
      '{"kind":"value","text":"5","parent":-1}],' +
      '"branches":[{"name":"item","from":2,"to":2,"labels":[[1,-1]]},' +
      '{"name":"item","from":3,"to":3,"labels":[[2,3]]},' +
      '{"name":"else","from":5,"to":5,"labels":[]}]}]}';

  // Wie cCaseRange ohne else.
  cCaseNoElse =
    '{"format":1,"blocks":[{"kind":"case","line":1,"parts":[' +
      '{"kind":"value","text":"N","parent":-1},' +
      '{"kind":"value","text":"1","parent":-1}],' +
      '"branches":[{"name":"item","from":2,"to":2,"labels":[[1,-1]]}]}]}';

{ TAtlasForecastTests }

procedure TAtlasForecastTests.Setup;
begin
  FForecast := TAtlasForecast.Create;
  FTexts := Default(TAtlasForecastTexts);
  FTexts.ElseBranch := 'else-Zweig';
  FTexts.NoBranch := 'kein Zweig';
end;

procedure TAtlasForecastTests.TearDown;
begin
  FreeAndNil(FForecast);
  FTexts := Default(TAtlasForecastTexts);
end;

procedure TAtlasForecastTests.Load(const AJson: string);
var
  mBlocks: TAtlasWhyHereBlocks;
  mBranches: TArray<TAtlasForecastBranches>;
begin
  Assert.IsTrue(TAtlasForecast.ReadAnswerText(AJson, mBlocks, mBranches), 'Antwort lesbar');
  FForecast.Start(cFile, mBlocks, mBranches);
end;

function TAtlasForecastTests.EvaluateAll(const AValues: string): string;
var
  mValues: TArray<string>;
  mRef: TAtlasWhyHereRef;
  mPair, mValue: string;
  mFound: Boolean;
begin
  Result := '';
  mValues := AValues.Split([';']);
  while FForecast.NextPending(mRef) do
  begin
    Assert.IsFalse(mRef.SideEffects, 'nie mit Nebenwirkungen: ' + mRef.Expression);
    Result := Result + mRef.Expression + '|';
    mFound := False;
    mValue := '';
    for mPair in mValues do
    begin
      if mPair.StartsWith(mRef.Expression + '=') then
      begin
        mValue := mPair.Substring(Length(mRef.Expression) + 1);
        mFound := True;
      end;
    end;
    FForecast.Put(mRef, mValue, mFound);
  end;
end;

function TAtlasForecastTests.DimmedLines(ALast: Integer): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := 0 to ALast do
  begin
    if FForecast.Dimmed(cFile, mLine) then
    begin
      Result := Trim(Result + ' ' + IntToStr(mLine));
    end;
  end;
end;

procedure TAtlasForecastTests.ReadsAnswerWithBranches;
var
  mBlocks: TAtlasWhyHereBlocks;
  mBranches: TArray<TAtlasForecastBranches>;
begin
  Assert.IsTrue(TAtlasForecast.ReadAnswerText(cAcceptance, mBlocks, mBranches));
  Assert.AreEqual(2, Integer(Length(mBlocks)));
  Assert.AreEqual(2, Integer(Length(mBranches)));
  Assert.AreEqual('if', mBlocks[0].Kind);
  Assert.AreEqual('else', mBranches[0][1].Name);
  Assert.AreEqual(4, mBranches[0][1].FromLine);
  Assert.AreEqual(2, mBranches[1][1].Labels[0][0]);
  Assert.AreEqual(-1, mBranches[1][1].Labels[0][1]);
  Assert.IsFalse(TAtlasForecast.ReadAnswerText('', mBlocks, mBranches), 'leer');
  Assert.IsFalse(TAtlasForecast.ReadAnswerText('{"format":2}', mBlocks, mBranches), 'falsches Format');
  Assert.AreEqual('["file:///a.pas",4,20]', TAtlasForecast.Arguments('file:///a.pas', 4, 20));
end;

procedure TAtlasForecastTests.AcceptanceIfAndCase;
begin
  Load(cAcceptance);
  EvaluateAll('mOffen > 0=True;mOffen=3;0=0;FOnline=False;FMode=smManual;smAuto=smAuto;smManual=smManual');
  Assert.AreEqual('⟨= False · FOnline⟩', FForecast.LineText(cFile, 1, FTexts));
  Assert.AreEqual('⟨→ smManual⟩', FForecast.LineText(cFile, 5, FTexts));
  Assert.AreEqual(1, FForecast.Taken(0), 'else');
  Assert.AreEqual(1, FForecast.Taken(1), 'smManual');
  // then-Zweig (2) und smAuto (6) blass, else (4) und smManual (7) normal.
  Assert.AreEqual('2 6', DimmedLines(8));
end;

procedure TAtlasForecastTests.CallIsNeverEvaluated;
var
  mOrder: string;
begin
  Load(cWithCall);
  // Bereit = True: Pruefe müsste entscheiden, wird aber nie aufgerufen: keine Vorhersage.
  mOrder := EvaluateAll('Bereit=True;Pruefe=False');
  Assert.AreEqual('Bereit|', mOrder);
  Assert.AreEqual(TAtlasForecast.cUnknown, FForecast.Taken(0));
  Assert.AreEqual('', FForecast.LineText(cFile, 1, FTexts));
  Assert.AreEqual('', DimmedLines(6));
  // Bereit = False entscheidet ohne den Aufruf (Kurzschluss).
  Load(cWithCall);
  EvaluateAll('Bereit=False');
  Assert.AreEqual('⟨= False · Bereit⟩', FForecast.LineText(cFile, 1, FTexts));
  Assert.AreEqual('2 3', DimmedLines(6));
end;

procedure TAtlasForecastTests.TrueTakesThenBranch;
begin
  Load(cIfWhile);
  EvaluateAll('Fertig=True;Laeuft=True');
  Assert.AreEqual('⟨= True⟩', FForecast.LineText(cFile, 1, FTexts));
  Assert.AreEqual(0, FForecast.Taken(0));
  Assert.AreEqual(0, FForecast.Taken(1));
  Assert.AreEqual('', DimmedLines(10));
end;

procedure TAtlasForecastTests.IfWithoutElseFalseDimsThen;
begin
  Load(cIfWhile);
  EvaluateAll('Fertig=False;Laeuft=True');
  Assert.AreEqual(TAtlasForecast.cNone, FForecast.Taken(0));
  Assert.AreEqual('⟨= False⟩', FForecast.LineText(cFile, 1, FTexts));
  Assert.AreEqual('2 3 4', DimmedLines(10));
end;

procedure TAtlasForecastTests.WhileFalseDimsBody;
begin
  Load(cIfWhile);
  EvaluateAll('Fertig=True;Laeuft=False');
  Assert.AreEqual(TAtlasForecast.cNone, FForecast.Taken(1));
  Assert.AreEqual('⟨= False⟩', FForecast.LineText(cFile, 6, FTexts));
  Assert.AreEqual('7 8 9', DimmedLines(10));
end;

procedure TAtlasForecastTests.CaseWithoutMatchTakesElse;
begin
  Load(cCaseRange);
  EvaluateAll('N=9;1=1;2=2;5=5');
  Assert.AreEqual(2, FForecast.Taken(0));
  Assert.AreEqual('⟨→ else-Zweig⟩', FForecast.LineText(cFile, 1, FTexts));
  Assert.AreEqual('2 3', DimmedLines(6));
end;

procedure TAtlasForecastTests.CaseWithoutMatchAndElse;
begin
  Load(cCaseNoElse);
  EvaluateAll('N=9;1=1');
  Assert.AreEqual(TAtlasForecast.cNone, FForecast.Taken(0));
  Assert.AreEqual('⟨→ kein Zweig⟩', FForecast.LineText(cFile, 1, FTexts));
  Assert.AreEqual('2', DimmedLines(4));
end;

procedure TAtlasForecastTests.CaseRangeWithNumbers;
begin
  Load(cCaseRange);
  EvaluateAll('N=4;1=1;2=2;5=5');
  Assert.AreEqual(1, FForecast.Taken(0));
  Assert.AreEqual('⟨→ 2..5⟩', FForecast.LineText(cFile, 1, FTexts));
  Assert.AreEqual('2 5', DimmedLines(6));
end;

procedure TAtlasForecastTests.UnknownValueGivesNoForecast;
begin
  Load(cAcceptance);
  // FOnline lässt sich nicht auswerten, mOffen > 0 ist True: offen. Der Selektor scheitert: offen.
  EvaluateAll('mOffen > 0=True;mOffen=3;0=0;smAuto=smAuto;smManual=smManual');
  Assert.AreEqual('', FForecast.LineText(cFile, 1, FTexts));
  Assert.AreEqual('', FForecast.LineText(cFile, 5, FTexts));
  Assert.AreEqual('', DimmedLines(8));
end;

procedure TAtlasForecastTests.OtherFileHasNothing;
begin
  Load(cAcceptance);
  EvaluateAll('mOffen > 0=False;mOffen=0;0=0;FOnline=True;FMode=smAuto;smAuto=smAuto;smManual=smManual');
  Assert.AreEqual('', FForecast.LineText('C:\Src\Andere.pas', 1, FTexts));
  Assert.IsFalse(FForecast.Dimmed('C:\Src\Andere.pas', 2));
  Assert.AreEqual('⟨= False · mOffen > 0⟩', FForecast.LineText(cFile, 1, FTexts));
  FForecast.Clear;
  Assert.IsFalse(FForecast.Active);
  Assert.AreEqual('', FForecast.LineText(cFile, 1, FTexts));
end;

end.
