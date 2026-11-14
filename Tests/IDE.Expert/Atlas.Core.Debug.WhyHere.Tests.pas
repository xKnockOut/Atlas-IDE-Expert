unit Atlas.Core.Debug.WhyHere.Tests;

// Tests für „Warum bin ich hier?“ (#1878) ohne IDE: Antwort lesen,
// Reihenfolge der Auswertung mit Kurzschluss, Aufrufe erst nach Freigabe,
// Text je Kopfzeile.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.WhyHere;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasWhyHereTests = class
  private
    FWhy: TAtlasWhyHere;
    FTexts: TAtlasWhyHereTexts;
    procedure Load(const AJson: string);
    /// <summary>Wertet alle ausstehenden Teile mit AValues (Ausdruck=Wert, ';' getrennt) aus; Rückgabe: die
    /// Ausdrücke in Reihenfolge.</summary>
    function EvaluateAll(const AValues: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsAnswerAndArguments;
    [Test]
    procedure AcceptanceCaseInIfInFor;
    [Test]
    procedure ShortCircuitLeavesSecondPartNotNeeded;
    [Test]
    procedure CallStaysUnevaluatedUntilAllowed;
    [Test]
    procedure ElseBranchShowsFalse;
    [Test]
    procedure NotAndOrAndXor;
    [Test]
    procedure WithAndForInDoNotEvaluateCollections;
    [Test]
    procedure FailedValueShowsQuestionMark;
    [Test]
    procedure OtherFileHasNoText;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

const
  // Wie die Antwort des Servers für den Halt in einem case-Zweig im if in einer for-Schleife (#1878).
  cAcceptance =
    '{"format":1,"blocks":[' +
    '{"kind":"case","line":10,"branch":"paRabatt","parts":[{"kind":"value","text":"Art","parent":-1}]},' +
    '{"kind":"if","line":9,"branch":"then","parts":[' +
      '{"kind":"and","operator":"and","text":"(Summe > 1000) and Pruefe(I) and Aktiv","parent":-1,"call":true},' +
      '{"kind":"compare","operator":">","text":"Summe > 1000","parent":0},' +
      '{"kind":"value","text":"Summe","parent":1},' +
      '{"kind":"value","text":"1000","parent":1},' +
      '{"kind":"value","text":"Pruefe(I)","parent":0,"call":true},' +
      '{"kind":"value","text":"Aktiv","parent":0}]},' +
    '{"kind":"for","line":7,"parts":[{"kind":"value","text":"I","parent":-1},' +
      '{"kind":"value","text":"N","parent":-1}]}]}';

{ TAtlasWhyHereTests }

procedure TAtlasWhyHereTests.Setup;
begin
  FWhy := TAtlasWhyHere.Create;
  FTexts := Default(TAtlasWhyHereTexts);
  FTexts.NotNeeded := 'nicht nötig';
  FTexts.NotEvaluated := '‹Aufruf›';
  FTexts.Failed := '?';
  FTexts.ElseBranch := 'else-Zweig';
  FTexts.Of_ := 'von';
end;

procedure TAtlasWhyHereTests.TearDown;
begin
  FreeAndNil(FWhy);
  FTexts := Default(TAtlasWhyHereTexts);
end;

procedure TAtlasWhyHereTests.Load(const AJson: string);
var
  mJson: TJSONValue;
  mBlocks: TAtlasWhyHereBlocks;
begin
  mJson := TJSONObject.ParseJSONValue(AJson);
  try
    Assert.IsTrue(TAtlasWhyHere.ReadAnswer(mJson, mBlocks));
  finally
    mJson.Free;
  end;
  FWhy.Start('C:\P\Ablauf.pas', mBlocks);
end;

function TAtlasWhyHereTests.EvaluateAll(const AValues: string): string;
var
  mRef: TAtlasWhyHereRef;
  mPairs: TArray<string>;
  mPair: string;
  mFound: Boolean;
  mOrder: TArray<string>;
begin
  mPairs := AValues.Split([';']);
  mOrder := nil;
  while FWhy.NextPending(mRef) do
  begin
    mOrder := mOrder + [mRef.Expression];
    mFound := False;
    for mPair in mPairs do
    begin
      if mPair.StartsWith(mRef.Expression + '=') then
      begin
        FWhy.Put(mRef, Copy(mPair, Length(mRef.Expression) + 2, MaxInt), True);
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      FWhy.Put(mRef, '', False);
    end;
  end;
  Result := string.Join(',', mOrder);
end;

procedure TAtlasWhyHereTests.ReadsAnswerAndArguments;
var
  mJson: TJSONValue;
  mBlocks: TAtlasWhyHereBlocks;
begin
  mJson := TJSONObject.ParseJSONValue(cAcceptance);
  try
    Assert.IsTrue(TAtlasWhyHere.ReadAnswer(mJson, mBlocks));
  finally
    mJson.Free;
  end;
  Assert.AreEqual(3, Integer(Length(mBlocks)));
  Assert.AreEqual('if', mBlocks[1].Kind);
  Assert.AreEqual(9, mBlocks[1].Line);
  Assert.AreEqual(6, Integer(Length(mBlocks[1].Parts)));
  Assert.IsTrue(mBlocks[1].Parts[4].Call);
  Assert.AreEqual(1, mBlocks[1].Parts[2].Parent);
  mJson := TJSONObject.ParseJSONValue('{"format":2,"blocks":[]}');
  try
    Assert.IsFalse(TAtlasWhyHere.ReadAnswer(mJson, mBlocks));
  finally
    mJson.Free;
  end;
  Assert.IsFalse(TAtlasWhyHere.ReadAnswer(nil, mBlocks));
  Assert.IsFalse(TAtlasWhyHere.ReadAnswerText('', mBlocks), 'leere Antwort');
  Assert.IsFalse(TAtlasWhyHere.ReadAnswerText('{kaputt', mBlocks), 'kaputtes JSON');
  Assert.IsTrue(TAtlasWhyHere.ReadAnswerText('{"format":1,"blocks":[]}', mBlocks));
  Assert.AreEqual(0, Integer(Length(mBlocks)));
  Assert.AreEqual('["file:///c:/a.pas",12,3]', TAtlasWhyHere.Arguments('file:///c:/a.pas', 12, 3));
end;

procedure TAtlasWhyHereTests.AcceptanceCaseInIfInFor;
begin
  Load(cAcceptance);
  // Pruefe(I) ist ein Aufruf und bleibt aus; der Vergleich vor seinen Seiten.
  Assert.AreEqual('Art,Summe > 1000,Summe,1000,Aktiv,I,N',
    EvaluateAll('Art=paRabatt;Summe > 1000=True;Summe=1200;1000=1000;Aktiv=True;I=3;N=7'));
  Assert.AreEqual('Art = paRabatt → paRabatt', FWhy.LineText('C:\P\Ablauf.pas', 10, FTexts));
  Assert.AreEqual('(1200 > 1000) and ‹Aufruf› and True → ?', FWhy.LineText('C:\P\Ablauf.pas', 9, FTexts));
  Assert.AreEqual('I = 3 von 7', FWhy.LineText('c:\p\ablauf.pas', 7, FTexts));
  Assert.AreEqual('', FWhy.LineText('C:\P\Ablauf.pas', 8, FTexts));
end;

procedure TAtlasWhyHereTests.ShortCircuitLeavesSecondPartNotNeeded;
begin
  Load(cAcceptance);
  // Summe > 1000 = False entscheidet die and-Kette: Aktiv wird nicht ausgewertet, die Seiten des Vergleichs schon.
  Assert.AreEqual('Art,Summe > 1000,Summe,1000,I,N',
    EvaluateAll('Art=paNormal;Summe > 1000=False;Summe=10;1000=1000;I=1;N=7'));
  Assert.AreEqual('(10 > 1000) and nicht nötig and nicht nötig → False', FWhy.LineText('C:\P\Ablauf.pas', 9, FTexts));
  Assert.IsFalse(FWhy.Needed(1, 5));
  Assert.IsTrue(FWhy.Needed(1, 1));
end;

procedure TAtlasWhyHereTests.CallStaysUnevaluatedUntilAllowed;
var
  mRef: TAtlasWhyHereRef;
begin
  Load(cAcceptance);
  EvaluateAll('Art=paRabatt;Summe > 1000=True;Summe=1200;1000=1000;Aktiv=True;I=3;N=7');
  Assert.AreEqual('Pruefe(I)', string.Join(',', FWhy.CallsAt(9)));
  Assert.AreEqual(0, Integer(Length(FWhy.CallsAt(10))));
  FWhy.AllowCalls(9);
  Assert.IsTrue(FWhy.NextPending(mRef));
  Assert.AreEqual('Pruefe(I)', mRef.Expression);
  Assert.IsTrue(mRef.SideEffects);
  FWhy.Put(mRef, 'True', True);
  Assert.IsFalse(FWhy.NextPending(mRef));
  Assert.AreEqual(0, Integer(Length(FWhy.CallsAt(9))));
  Assert.AreEqual('(1200 > 1000) and True and True → True', FWhy.LineText('C:\P\Ablauf.pas', 9, FTexts));
end;

procedure TAtlasWhyHereTests.ElseBranchShowsFalse;
begin
  Load('{"format":1,"blocks":[{"kind":"if","line":20,"branch":"else","parts":[' +
    '{"kind":"compare","operator":"=","text":"N = 0","parent":-1},' +
    '{"kind":"value","text":"N","parent":0},{"kind":"value","text":"0","parent":0}]},' +
    '{"kind":"case","line":30,"branch":"else","parts":[{"kind":"value","text":"Art","parent":-1}]}]}');
  EvaluateAll('N = 0=False;N=4;0=0;Art=paX');
  Assert.AreEqual('(4 = 0) → False, else-Zweig', FWhy.LineText('C:\P\Ablauf.pas', 20, FTexts));
  Assert.AreEqual('Art = paX → else-Zweig', FWhy.LineText('C:\P\Ablauf.pas', 30, FTexts));
end;

procedure TAtlasWhyHereTests.NotAndOrAndXor;
begin
  // not (Aktiv or (N in [1, 2])): Aktiv = True entscheidet das or, der Vergleich ist nicht nötig.
  Load('{"format":1,"blocks":[{"kind":"while","line":5,"parts":[' +
    '{"kind":"not","operator":"not","text":"not (Aktiv or (N in [1, 2]))","parent":-1},' +
    '{"kind":"or","operator":"or","text":"Aktiv or (N in [1, 2])","parent":0},' +
    '{"kind":"value","text":"Aktiv","parent":1},' +
    '{"kind":"compare","operator":"in","text":"N in [1, 2]","parent":1},' +
    '{"kind":"value","text":"N","parent":3},{"kind":"value","text":"[1, 2]","parent":3}]},' +
    '{"kind":"repeat","line":8,"parts":[' +
    '{"kind":"xor","operator":"xor","text":"A xor B","parent":-1},' +
    '{"kind":"value","text":"A","parent":0},{"kind":"value","text":"B","parent":0}]}]}');
  Assert.AreEqual('Aktiv,A,B', EvaluateAll('Aktiv=True;A=True;B=True'));
  Assert.AreEqual('not True or nicht nötig → False', FWhy.LineText('C:\P\Ablauf.pas', 5, FTexts));
  Assert.AreEqual('True xor True → False', FWhy.LineText('C:\P\Ablauf.pas', 8, FTexts));
end;

procedure TAtlasWhyHereTests.WithAndForInDoNotEvaluateCollections;
begin
  Load('{"format":1,"blocks":[{"kind":"with","line":3,"parts":[{"kind":"value","text":"Kunde","parent":-1}]},' +
    '{"kind":"forIn","line":2,"parts":[{"kind":"value","text":"E","parent":-1},' +
    '{"kind":"value","text":"Liste","parent":-1}]}]}');
  Assert.AreEqual('E', EvaluateAll('E=''x'''));
  Assert.AreEqual('with Kunde', FWhy.LineText('C:\P\Ablauf.pas', 3, FTexts));
  Assert.AreEqual('E = ''x''', FWhy.LineText('C:\P\Ablauf.pas', 2, FTexts));
end;

procedure TAtlasWhyHereTests.FailedValueShowsQuestionMark;
begin
  Load('{"format":1,"blocks":[{"kind":"if","line":4,"branch":"then","parts":[' +
    '{"kind":"value","text":"P.Wert","parent":-1}]}]}');
  Assert.AreEqual('P.Wert', EvaluateAll(''));
  Assert.AreEqual('? → ?', FWhy.LineText('C:\P\Ablauf.pas', 4, FTexts));
end;

procedure TAtlasWhyHereTests.OtherFileHasNoText;
begin
  Load(cAcceptance);
  Assert.AreEqual('', FWhy.LineText('C:\P\Anders.pas', 10, FTexts));
  Assert.IsTrue(FWhy.Active);
  FWhy.Clear;
  Assert.IsFalse(FWhy.Active);
end;

end.
