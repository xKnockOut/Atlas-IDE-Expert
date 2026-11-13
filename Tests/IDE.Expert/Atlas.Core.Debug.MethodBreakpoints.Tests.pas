unit Atlas.Core.Debug.MethodBreakpoints.Tests;

// Haltepunkte auf Methoden nach Muster (#855), Kern: Anfrage und Antwort, Schlüssel unabhängig von der Zeile,
// neue Treffer für „Mitwachsen“, Ablage der Gruppen je Projekt.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.MethodBreakpoints;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasMethodBreakpointsTests = class
  private
    function Hit(const AContainer, AName: string; ALine: Integer): TAtlasMethodHit;
  public
    [Test]
    procedure WritesArguments;
    [Test]
    procedure ReadsAnswer;
    [Test]
    procedure ReadsErrorAndRejectsForeignFormat;
    [Test]
    procedure KeyIgnoresLineAndCase;
    [Test]
    procedure NewHitsSkipKnownAndMissingSource;
    [Test]
    procedure LearnAddsOnlyNewKeys;
    [Test]
    procedure StoreKeepsGroupsPerProject;
    [Test]
    procedure StoreRoundTrip;
    [Test]
    procedure StoreRejectsForeignText;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

function TAtlasMethodBreakpointsTests.Hit(const AContainer, AName: string; ALine: Integer): TAtlasMethodHit;
begin
  Result := Default(TAtlasMethodHit);
  Result.FileName := 'C:\P\Kunden.pas';
  Result.UnitName := 'Kunden';
  Result.Container := AContainer;
  Result.Name := AName;
  Result.Signature := 'procedure ' + AName + ';';
  Result.Line := ALine;
end;

procedure TAtlasMethodBreakpointsTests.WritesArguments;
var
  mValue: TJSONValue;
  mItem: TJSONObject;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasMethodBreakpoints.Arguments(TAtlasMethodQuery.Create('*.Validiere*',
    False, True)));
  try
    Assert.IsTrue(mValue is TJSONArray);
    mItem := TJSONArray(mValue).Items[0] as TJSONObject;
    Assert.AreEqual('*.Validiere*', mItem.GetValue('pattern').Value);
    Assert.IsFalse((mItem.GetValue('overrides') as TJSONBool).AsBoolean);
    Assert.IsTrue((mItem.GetValue('overloads') as TJSONBool).AsBoolean);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasMethodBreakpointsTests.ReadsAnswer;
const
  cAnswer = '{"format": 1, "pattern": "TKunde.*", "truncated": true, "hits": [' +
    '{"uri": "file:///C:/P/Kunden.pas", "unit": "Kunden", "container": "TKunde", "name": "Validiere", ' +
    '"signature": "procedure Validiere; override;", "line": 41, "source": true, "reason": "override", ' +
    '"via": "TBasis.Validiere"},' +
    '{"uri": "file:///C:/Lib/Basis.pas", "unit": "Basis", "container": "", "name": "Frei", "signature": "", ' +
    '"line": -1, "source": false, "reason": "implementation", "via": "IAuftrag.Pruefe"}]}';
var
  mValue: TJSONValue;
  mAnswer: TAtlasMethodAnswer;
begin
  mValue := TJSONObject.ParseJSONValue(cAnswer);
  try
    Assert.IsTrue(TAtlasMethodBreakpoints.ReadAnswer(mValue,
      function(const AUri: string): string
      begin
        Result := 'Pfad:' + AUri;
      end, mAnswer));
  finally
    mValue.Free;
  end;
  Assert.IsTrue(mAnswer.Truncated);
  Assert.AreEqual('', mAnswer.Error);
  Assert.AreEqual(2, Integer(Length(mAnswer.Hits)));
  Assert.AreEqual('Pfad:file:///C:/P/Kunden.pas', mAnswer.Hits[0].FileName);
  Assert.AreEqual('TKunde.Validiere', mAnswer.Hits[0].DisplayName);
  Assert.AreEqual('Kunden.TKunde.Validiere', mAnswer.Hits[0].QualifiedName);
  Assert.AreEqual(41, mAnswer.Hits[0].Line);
  Assert.IsTrue(mAnswer.Hits[0].Reason = TAtlasMethodHitReason.Override_);
  Assert.AreEqual('TBasis.Validiere', mAnswer.Hits[0].Via);
  Assert.AreEqual('Frei', mAnswer.Hits[1].DisplayName);
  Assert.IsFalse(mAnswer.Hits[1].HasSource);
  Assert.IsTrue(mAnswer.Hits[1].Reason = TAtlasMethodHitReason.Implementation_);
  Assert.AreEqual(1, TAtlasMethodBreakpoints.WithSource(mAnswer.Hits));
end;

procedure TAtlasMethodBreakpointsTests.ReadsErrorAndRejectsForeignFormat;
var
  mValue: TJSONValue;
  mAnswer: TAtlasMethodAnswer;
begin
  mValue := TJSONObject.ParseJSONValue('{"format": 1, "error": "Ungültiges Muster: a..b"}');
  try
    Assert.IsTrue(TAtlasMethodBreakpoints.ReadAnswer(mValue, nil, mAnswer));
    Assert.AreEqual('Ungültiges Muster: a..b', mAnswer.Error);
    Assert.AreEqual(0, Integer(Length(mAnswer.Hits)));
  finally
    mValue.Free;
  end;
  mValue := TJSONObject.ParseJSONValue('{"format": 2, "hits": []}');
  try
    Assert.IsFalse(TAtlasMethodBreakpoints.ReadAnswer(mValue, nil, mAnswer));
  finally
    mValue.Free;
  end;
  Assert.IsFalse(TAtlasMethodBreakpoints.ReadAnswer(nil, nil, mAnswer));
end;

procedure TAtlasMethodBreakpointsTests.KeyIgnoresLineAndCase;
var
  mMoved: TAtlasMethodHit;
begin
  mMoved := Hit('TKunde', 'Validiere', 80);
  mMoved.Container := 'tkunde';
  mMoved.Signature := 'procedure  Validiere;';
  Assert.AreEqual(Hit('TKunde', 'Validiere', 41).Key, mMoved.Key);
  Assert.AreNotEqual(Hit('TKunde', 'Validiere', 41).Key, Hit('TAndere', 'Validiere', 41).Key);
end;

procedure TAtlasMethodBreakpointsTests.NewHitsSkipKnownAndMissingSource;
var
  mGroup: TAtlasMethodGroup;
  mNew: TAtlasMethodHits;
begin
  mGroup := Default(TAtlasMethodGroup);
  mGroup.Pattern := '*.Validiere*';
  mGroup.Learn([Hit('TKunde', 'Validiere', 41), Hit('TAlt', 'ValidiereAlt', 10)]);
  mNew := TAtlasMethodBreakpoints.NewHits(mGroup, [Hit('TKunde', 'Validiere', 50), Hit('TKunde',
    'ValidiereAdresse', 60), Hit('TListe', 'Validiere', -1)]);
  Assert.AreEqual(1, Integer(Length(mNew)));
  Assert.AreEqual('TKunde.ValidiereAdresse', mNew[0].DisplayName);
end;

procedure TAtlasMethodBreakpointsTests.LearnAddsOnlyNewKeys;
var
  mGroup: TAtlasMethodGroup;
begin
  mGroup := Default(TAtlasMethodGroup);
  mGroup.Learn([Hit('TKunde', 'Validiere', 41), Hit('TKunde', 'Validiere', 41)]);
  mGroup.Learn([Hit('TKunde', 'Validiere', 99), Hit('TKunde', 'Speichere', 3)]);
  Assert.AreEqual(2, Integer(Length(mGroup.Known)));
  Assert.IsTrue(mGroup.Knows(Hit('TKunde', 'Speichere', 7).Key));
  Assert.AreEqual('*.X', TAtlasMethodBreakpoints.GroupName('  *.X '));
end;

procedure TAtlasMethodBreakpointsTests.StoreKeepsGroupsPerProject;
var
  mStore: TAtlasMethodGroupStore;
  mGroup, mFound: TAtlasMethodGroup;
begin
  mStore := TAtlasMethodGroupStore.Create;
  try
    mGroup := Default(TAtlasMethodGroup);
    mGroup.Pattern := 'TKunde.*';
    mStore.Put('C:\P\Kunden.dproj', mGroup);
    mGroup.Pattern := '*.Validiere*';
    mStore.Put('C:\P\Kunden.dproj', mGroup);
    mStore.Put('C:\P\Andere.dproj', mGroup);
    // Gleiches Muster ersetzt die Gruppe.
    mGroup.Grow := True;
    mStore.Put('c:\p\kunden.DPROJ', mGroup);
    Assert.AreEqual(2, Integer(Length(mStore.Groups('C:\P\Kunden.dproj'))));
    Assert.IsTrue(mStore.Find('C:\P\Kunden.dproj', '*.validiere*', mFound));
    Assert.IsTrue(mFound.Grow);
    Assert.IsFalse(mStore.Find('C:\P\Andere.dproj', 'TKunde.*', mFound));
    Assert.IsTrue(mStore.Remove('C:\P\Kunden.dproj', 'TKunde.*'));
    Assert.IsFalse(mStore.Remove('C:\P\Kunden.dproj', 'TKunde.*'));
    Assert.AreEqual(1, Integer(Length(mStore.Groups('C:\P\Kunden.dproj'))));
    Assert.AreEqual(0, Integer(Length(mStore.Groups('C:\P\Fremd.dproj'))));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasMethodBreakpointsTests.StoreRoundTrip;
var
  mStore, mLoaded: TAtlasMethodGroupStore;
  mGroup, mFound: TAtlasMethodGroup;
begin
  mStore := TAtlasMethodGroupStore.Create;
  mLoaded := TAtlasMethodGroupStore.Create;
  try
    mGroup := Default(TAtlasMethodGroup);
    mGroup.Pattern := 'TKunde.Prüfe*';
    mGroup.Overrides := False;
    mGroup.Overloads := True;
    mGroup.Grow := True;
    mGroup.Condition := 'Betrag > 0';
    mGroup.LogOnly := True;
    mGroup.Learn([Hit('TKunde', 'Prüfe', 3)]);
    mStore.Put('C:\P\Kunden.dproj', mGroup);
    Assert.IsTrue(mLoaded.Parse(mStore.ToText));
    Assert.IsTrue(mLoaded.Find('C:\P\Kunden.dproj', 'TKunde.Prüfe*', mFound));
    Assert.IsFalse(mFound.Overrides);
    Assert.IsTrue(mFound.Overloads);
    Assert.IsTrue(mFound.Grow);
    Assert.AreEqual('Betrag > 0', mFound.Condition);
    Assert.IsTrue(mFound.LogOnly);
    Assert.AreEqual(1, Integer(Length(mFound.Known)));
    Assert.IsTrue(mFound.Knows(Hit('TKunde', 'Prüfe', 9).Key));
  finally
    mLoaded.Free;
    mStore.Free;
  end;
end;

procedure TAtlasMethodBreakpointsTests.StoreRejectsForeignText;
var
  mStore: TAtlasMethodGroupStore;
begin
  mStore := TAtlasMethodGroupStore.Create;
  try
    Assert.IsFalse(mStore.Parse('kein JSON'));
    Assert.IsFalse(mStore.Parse('{"format": 7}'));
    // Einträge ohne Muster fallen weg, der Rest bleibt.
    Assert.IsTrue(mStore.Parse('{"format": 1, "projects": [{"project": "A.dproj", "groups": [{"pattern": ""}, ' +
      '{"pattern": "X.*"}]}]}'));
    Assert.AreEqual(1, Integer(Length(mStore.Groups('A.dproj'))));
  finally
    mStore.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMethodBreakpointsTests);

end.
