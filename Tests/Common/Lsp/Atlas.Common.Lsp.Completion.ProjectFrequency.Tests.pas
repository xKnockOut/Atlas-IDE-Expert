unit Atlas.Common.Lsp.Completion.ProjectFrequency.Tests;

// Tests für die Rangfolge aus der Verwendung im Projekt (#2109): Zahl "projectUses" an den Mitgliedern nach "X.",
// Einstellung completion.projectFrequency und Antwortzeit.

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.Completion.Server.TestSupport;

type
  [TestFixture]
  TCompletionProjectFrequencyTests = class
  private
    FServer: TCompletionServer;
    FSettings: TCompletionSettings;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MembersCarryProjectCount;
    [Test]
    procedure UnusedMemberHasNoCount;
    [Test]
    procedure ScopeListHasNoCount;
    [Test]
    procedure SwitchedOffHasNoCount;
    [Test]
    procedure ChangedUnitUpdatesCount;
    [Test]
    [Category('Benchmark')]
    procedure ManyMembersStayFast;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.Diagnostics,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.Extractor;

const
  cUnitZaehler =
    'unit Zaehler;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TZaehler = class'#13#10 +
    '  public'#13#10 +
    '    FEnde: Integer;'#13#10 +
    '    procedure Leere;'#13#10 +
    '    function Anzahl: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TZaehler.Leere; begin end;'#13#10 +
    'function TZaehler.Anzahl: Integer; begin Result := 0; end;'#13#10 +
    'end.';

  /// <summary>Projekt-Unit, die Anzahl dreimal und FEnde einmal verwendet.</summary>
  cUnitNutzer =
    'unit Nutzer;'#13#10 +
    'interface'#13#10 +
    'uses Zaehler;'#13#10 +
    'implementation'#13#10 +
    'procedure Lauf(AZaehler: TZaehler);'#13#10 +
    'begin'#13#10 +
    '  if AZaehler.Anzahl > AZaehler.Anzahl then AZaehler.FEnde := AZaehler.Anzahl;'#13#10 +
    'end;'#13#10 +
    'end.';

  /// <summary>data.projectUses des Eintrags ALabel; 0 ohne Zahl, -1 ohne Eintrag.</summary>
  function ProjectUsesOf(AResult: TJSONObject; const ALabel: string): Integer;
  var
    mItem: TJSONValue;
    mData: TJSONValue;
  begin
    Result := -1;
    for mItem in AResult.GetValue('items') as TJSONArray do
    begin
      if (mItem as TJSONObject).GetValue<string>('label') <> ALabel then
      begin
        Continue;
      end;
      Result := 0;
      mData := TJSONObject(mItem).GetValue('data');
      if (mData is TJSONObject) and (TJSONObject(mData).GetValue('projectUses') <> nil) then
      begin
        Result := StrToInt(TJSONObject(mData).GetValue('projectUses').Value);
      end;
      Exit;
    end;
  end;

{ TCompletionProjectFrequencyTests }

procedure TCompletionProjectFrequencyTests.Setup;
begin
  FSettings := TCompletionSettings.Default;
  FServer := TCompletionServer.Create(
    function(const AUri: string): TCompletionSettings
    begin
      Result := FSettings;
    end);
  FServer.Index.AddUnit(TIndexExtractor.ExtractText(cUnitZaehler, 'C:\P\Zaehler.pas', nil, nil, True));
  FServer.Index.AddUnit(TIndexExtractor.ExtractText(cUnitNutzer, 'C:\P\Nutzer.pas', nil, nil, True));
end;

procedure TCompletionProjectFrequencyTests.TearDown;
begin
  FreeAndNil(FServer);
end;

procedure TCompletionProjectFrequencyTests.MembersCarryProjectCount;
var
  mAnswer: TJSONObject;
begin
  mAnswer := FServer.Complete(HauptWith('  AZaehler.|'));
  try
    Assert.AreEqual(3, ProjectUsesOf(mAnswer, 'Anzahl'), mAnswer.ToJSON);
    Assert.AreEqual(1, ProjectUsesOf(mAnswer, 'FEnde'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionProjectFrequencyTests.UnusedMemberHasNoCount;
var
  mAnswer: TJSONObject;
begin
  mAnswer := FServer.Complete(HauptWith('  AZaehler.|'));
  try
    Assert.AreEqual(0, ProjectUsesOf(mAnswer, 'Leere'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionProjectFrequencyTests.ScopeListHasNoCount;
var
  mAnswer: TJSONObject;
begin
  // Nur nach "X.": In der Liste ohne Punkt ordnet die Zählung nichts.
  mAnswer := FServer.Complete(HauptWith('  AZae|'));
  try
    Assert.AreEqual(0, ProjectUsesOf(mAnswer, 'AZaehler'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionProjectFrequencyTests.SwitchedOffHasNoCount;
var
  mAnswer: TJSONObject;
begin
  FSettings.ProjectFrequency := False;
  mAnswer := FServer.Complete(HauptWith('  AZaehler.|'));
  try
    Assert.AreEqual(0, ProjectUsesOf(mAnswer, 'Anzahl'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionProjectFrequencyTests.ChangedUnitUpdatesCount;
var
  mAnswer: TJSONObject;
begin
  FServer.Index.AddUnit(TIndexExtractor.ExtractText(cUnitNutzer.Replace('AZaehler.Anzahl > AZaehler.Anzahl',
    'AZaehler.Leere'), 'C:\P\Nutzer.pas', nil, nil, True));
  mAnswer := FServer.Complete(HauptWith('  AZaehler.|'));
  try
    Assert.AreEqual(1, ProjectUsesOf(mAnswer, 'Anzahl'), mAnswer.ToJSON);
    Assert.AreEqual(1, ProjectUsesOf(mAnswer, 'Leere'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionProjectFrequencyTests.ManyMembersStayFast;
const
  cMembers = 3000;
  cRounds = 5;
var
  mUnit: TStringBuilder;
  mIndex: Integer;
  mWatch: TStopwatch;
  mWith, mWithout: Int64;
  mAnswer: TJSONObject;
  mText: string;
begin
  // Klasse mit vielen Mitgliedern, eine Projekt-Unit verwendet jedes: Die Zahlen dürfen die Antwort nur
  // geringfügig verlangsamen.
  mUnit := TStringBuilder.Create;
  try
    mUnit.Append('unit Gross;'#13#10'interface'#13#10'type'#13#10'  TGross = class'#13#10'  public'#13#10);
    for mIndex := 1 to cMembers do
    begin
      mUnit.Append('    FFeld' + IntToStr(mIndex) + ': Integer;'#13#10);
    end;
    mUnit.Append('  end;'#13#10'implementation'#13#10'end.');
    FServer.Index.AddUnit(TIndexExtractor.ExtractText(mUnit.ToString, 'C:\P\Gross.pas', nil, nil, True));
    mUnit.Clear;
    mUnit.Append('unit Gebrauch;'#13#10'interface'#13#10'uses Gross;'#13#10'implementation'#13#10 +
      'procedure Lauf(AGross: TGross);'#13#10'begin'#13#10);
    for mIndex := 1 to cMembers do
    begin
      mUnit.Append('  AGross.FFeld' + IntToStr(mIndex) + ' := 0;'#13#10);
    end;
    mUnit.Append('end;'#13#10'end.');
    FServer.Index.AddUnit(TIndexExtractor.ExtractText(mUnit.ToString, 'C:\P\Gebrauch.pas', nil, nil, True));
  finally
    mUnit.Free;
  end;
  mText := 'unit Haupt;'#13#10'interface'#13#10'uses Gross;'#13#10'implementation'#13#10 +
    'procedure Pruefe(AGross: TGross);'#13#10'begin'#13#10'  AGross.FFeld7|'#13#10'end;'#13#10'end.';
  mWith := 0;
  mWithout := 0;
  for mIndex := 1 to cRounds do
  begin
    FSettings.ProjectFrequency := False;
    mWatch := TStopwatch.StartNew;
    FServer.Complete(mText).Free;
    Inc(mWithout, mWatch.ElapsedMilliseconds);
    FSettings.ProjectFrequency := True;
    mWatch := TStopwatch.StartNew;
    mAnswer := FServer.Complete(mText);
    Inc(mWith, mWatch.ElapsedMilliseconds);
    try
      Assert.AreEqual(1, ProjectUsesOf(mAnswer, 'FFeld7'));
    finally
      mAnswer.Free;
    end;
  end;
  Assert.IsTrue(mWith <= 2 * mWithout + 50 * cRounds, Format('%d ms mit, %d ms ohne', [mWith, mWithout]));
end;

end.
