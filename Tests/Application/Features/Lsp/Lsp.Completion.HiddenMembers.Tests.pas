unit Lsp.Completion.HiddenMembers.Tests;

// Tests für die nur wegen ihrer Sichtbarkeit fehlenden Mitglieder (#2108): Sammeln in der Namensauflösung,
// Sichtbarkeitsregeln und der Zusatz "hiddenMembers" der CompletionList.

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Lsp.Completion,
  Lsp.Completion.Server.TestSupport;

type
  [TestFixture]
  TCompletionHiddenMembersTests = class
  private
    FServer: TCompletionServer;
    FSettings: TCompletionSettings;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PrivateOfOtherUnitIsNamed;
    [Test]
    procedure ProtectedOfAncestorIsNamed;
    [Test]
    procedure StrictProtectedIsNamed;
    [Test]
    procedure NoPrefixNoNotice;
    [Test]
    procedure VisibleMatchesAreNotNamed;
    [Test]
    procedure VisibleOverloadHidesNotice;
    [Test]
    procedure PrivateInSameUnitIsVisible;
    [Test]
    procedure StrictPrivateInSameUnitIsNamed;
    [Test]
    procedure LibraryUnitIsExternal;
    [Test]
    procedure SwitchedOffNamesNothing;
    [Test]
    [Category('Benchmark')]
    procedure ManyPrivateMembersStayFast;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.Diagnostics,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.Extractor;

const
  cUnitZaehler =
    'unit Zaehler;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TBasis = class'#13#10 +
    '  protected'#13#10 +
    '    FSchutz: Integer;'#13#10 +
    '  end;'#13#10 +
    '  TZaehler = class(TBasis)'#13#10 +
    '  private'#13#10 +
    '    FEintraege: Integer;'#13#10 +
    '    procedure Leere; overload;'#13#10 +
    '  strict protected'#13#10 +
    '    FStrengSchutz: Integer;'#13#10 +
    '  public'#13#10 +
    '    FEnde: Integer;'#13#10 +
    '    procedure Leere(AZahl: Integer); overload;'#13#10 +
    '    function Anzahl: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TZaehler.Leere; begin end;'#13#10 +
    'procedure TZaehler.Leere(AZahl: Integer); begin end;'#13#10 +
    'function TZaehler.Anzahl: Integer; begin Result := 0; end;'#13#10 +
    'end.';

  /// <summary>Zusatz "hiddenMembers" der Antwort; nil ohne.</summary>
  function HiddenOf(AResult: TJSONObject): TJSONObject;
  begin
    Result := nil;
    if AResult.GetValue('hiddenMembers') is TJSONObject then
    begin
      Result := TJSONObject(AResult.GetValue('hiddenMembers'));
    end;
  end;

  /// <summary>Feld AName des ersten nicht sichtbaren Mitglieds; '' ohne.</summary>
  function FirstHidden(AResult: TJSONObject; const AName: string): string;
  var
    mItems: TJSONArray;
  begin
    Result := '';
    if (HiddenOf(AResult) = nil) or not (HiddenOf(AResult).GetValue('items') is TJSONArray) then
    begin
      Exit;
    end;
    mItems := TJSONArray(HiddenOf(AResult).GetValue('items'));
    if (mItems.Count > 0) and (TJSONObject(mItems.Items[0]).GetValue(AName) <> nil) then
    begin
      Result := TJSONObject(mItems.Items[0]).GetValue(AName).Value;
    end;
  end;

  /// <summary>Hat die Antwort einen Eintrag mit dem Label ALabel?</summary>
  function HasItem(AResult: TJSONObject; const ALabel: string): Boolean;
  var
    mItem: TJSONValue;
  begin
    for mItem in AResult.GetValue('items') as TJSONArray do
    begin
      if (mItem as TJSONObject).GetValue<string>('label') = ALabel then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

{ TCompletionHiddenMembersTests }

procedure TCompletionHiddenMembersTests.Setup;
begin
  FSettings := TCompletionSettings.Default;
  FServer := TCompletionServer.Create(
    function(const AUri: string): TCompletionSettings
    begin
      Result := FSettings;
    end);
  FServer.Index.AddUnit(TIndexExtractor.ExtractText(cUnitZaehler, 'C:\P\Zaehler.pas', nil));
end;

procedure TCompletionHiddenMembersTests.TearDown;
begin
  FreeAndNil(FServer);
end;

procedure TCompletionHiddenMembersTests.PrivateOfOtherUnitIsNamed;
var
  mAnswer: TJSONObject;
begin
  mAnswer := FServer.Complete(HauptWith('  AZaehler.FEi|'));
  try
    Assert.IsFalse(HasItem(mAnswer, 'FEintraege'));
    Assert.IsNotNull(HiddenOf(mAnswer), mAnswer.ToJSON);
    Assert.AreEqual('1', HiddenOf(mAnswer).GetValue('count').Value);
    Assert.AreEqual('FEintraege', FirstHidden(mAnswer, 'name'));
    Assert.AreEqual('private', FirstHidden(mAnswer, 'visibility'));
    Assert.AreEqual('TZaehler', FirstHidden(mAnswer, 'container'));
    Assert.AreEqual('Zaehler', FirstHidden(mAnswer, 'unit'));
    Assert.AreEqual('false', FirstHidden(mAnswer, 'external'));
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\Zaehler.pas'), FirstHidden(mAnswer, 'uri'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionHiddenMembersTests.ProtectedOfAncestorIsNamed;
var
  mAnswer: TJSONObject;
begin
  mAnswer := FServer.Complete(HauptWith('  AZaehler.FSch|'));
  try
    Assert.AreEqual('FSchutz', FirstHidden(mAnswer, 'name'), mAnswer.ToJSON);
    Assert.AreEqual('protected', FirstHidden(mAnswer, 'visibility'));
    Assert.AreEqual('TBasis', FirstHidden(mAnswer, 'container'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionHiddenMembersTests.StrictProtectedIsNamed;
var
  mAnswer: TJSONObject;
begin
  mAnswer := FServer.Complete(HauptWith('  AZaehler.FStr|'));
  try
    Assert.AreEqual('FStrengSchutz', FirstHidden(mAnswer, 'name'), mAnswer.ToJSON);
    Assert.AreEqual('strict protected', FirstHidden(mAnswer, 'visibility'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionHiddenMembersTests.NoPrefixNoNotice;
var
  mAnswer: TJSONObject;
begin
  mAnswer := FServer.Complete(HauptWith('  AZaehler.|'));
  try
    Assert.IsTrue(HasItem(mAnswer, 'Anzahl'));
    Assert.IsNull(HiddenOf(mAnswer), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionHiddenMembersTests.VisibleMatchesAreNotNamed;
var
  mAnswer: TJSONObject;
begin
  // "FE" passt auf das sichtbare FEnde und das private FEintraege: nur FEintraege kommt in den Zusatz.
  mAnswer := FServer.Complete(HauptWith('  AZaehler.FE|'));
  try
    Assert.IsTrue(HasItem(mAnswer, 'FEnde'));
    Assert.IsNotNull(HiddenOf(mAnswer), mAnswer.ToJSON);
    Assert.AreEqual('1', HiddenOf(mAnswer).GetValue('count').Value);
    Assert.AreEqual('FEintraege', FirstHidden(mAnswer, 'name'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionHiddenMembersTests.VisibleOverloadHidesNotice;
var
  mAnswer: TJSONObject;
begin
  // Leere hat eine private und eine öffentliche Überladung: sichtbar, also kein Hinweis.
  mAnswer := FServer.Complete(HauptWith('  AZaehler.Lee|'));
  try
    Assert.IsTrue(HasItem(mAnswer, 'Leere'));
    Assert.IsNull(HiddenOf(mAnswer), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionHiddenMembersTests.PrivateInSameUnitIsVisible;
var
  mAnswer: TJSONObject;
begin
  mAnswer := FServer.Complete(
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TLager = class'#13#10 +
    '  private'#13#10 +
    '    FBestand: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure Pruefe(ALager: TLager);'#13#10 +
    'begin'#13#10 +
    '  ALager.FBe|'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.IsTrue(HasItem(mAnswer, 'FBestand'), mAnswer.ToJSON);
    Assert.IsNull(HiddenOf(mAnswer));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionHiddenMembersTests.StrictPrivateInSameUnitIsNamed;
var
  mAnswer: TJSONObject;
begin
  mAnswer := FServer.Complete(
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TLager = class'#13#10 +
    '  strict private'#13#10 +
    '    FBestand: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure Pruefe(ALager: TLager);'#13#10 +
    'begin'#13#10 +
    '  ALager.FBe|'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.IsFalse(HasItem(mAnswer, 'FBestand'));
    Assert.AreEqual('FBestand', FirstHidden(mAnswer, 'name'), mAnswer.ToJSON);
    Assert.AreEqual('strict private', FirstHidden(mAnswer, 'visibility'));
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionHiddenMembersTests.LibraryUnitIsExternal;
var
  mUnit: TUnitIndex;
  mAnswer: TJSONObject;
begin
  mUnit := TIndexExtractor.ExtractText(cUnitZaehler, 'C:\P\Zaehler.pas', nil);
  mUnit.Library_ := True;
  FServer.Index.AddUnit(mUnit);
  mAnswer := FServer.Complete(HauptWith('  AZaehler.FEi|'));
  try
    Assert.AreEqual('true', FirstHidden(mAnswer, 'external'), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionHiddenMembersTests.SwitchedOffNamesNothing;
var
  mAnswer: TJSONObject;
begin
  FSettings.HiddenMembers := False;
  mAnswer := FServer.Complete(HauptWith('  AZaehler.FEi|'));
  try
    Assert.IsNull(HiddenOf(mAnswer), mAnswer.ToJSON);
  finally
    mAnswer.Free;
  end;
end;

procedure TCompletionHiddenMembersTests.ManyPrivateMembersStayFast;
const
  cFields = 3000;
  cRounds = 5;
var
  mUnit: TStringBuilder;
  mIndex: Integer;
  mWatch: TStopwatch;
  mWith, mWithout: Int64;
  mAnswer: TJSONObject;
begin
  // Klasse mit vielen privaten Feldern (Formulare): Das Merken darf die Antwort nur geringfügig verlangsamen.
  mUnit := TStringBuilder.Create;
  try
    mUnit.Append('unit Gross;'#13#10'interface'#13#10'type'#13#10'  TGross = class'#13#10'  private'#13#10);
    for mIndex := 1 to cFields do
    begin
      mUnit.Append('    FFeld' + IntToStr(mIndex) + ': Integer;'#13#10);
    end;
    mUnit.Append('  public'#13#10'    FOffen: Integer;'#13#10'  end;'#13#10'implementation'#13#10'end.');
    FServer.Index.AddUnit(TIndexExtractor.ExtractText(mUnit.ToString, 'C:\P\Gross.pas', nil));
  finally
    mUnit.Free;
  end;
  mWith := 0;
  mWithout := 0;
  for mIndex := 1 to cRounds do
  begin
    FSettings.HiddenMembers := False;
    mWatch := TStopwatch.StartNew;
    FServer.Complete('unit Haupt;'#13#10'interface'#13#10'uses Gross;'#13#10'implementation'#13#10 +
      'procedure Pruefe(AGross: TGross);'#13#10'begin'#13#10'  AGross.FF|'#13#10'end;'#13#10'end.').Free;
    Inc(mWithout, mWatch.ElapsedMilliseconds);
    FSettings.HiddenMembers := True;
    mWatch := TStopwatch.StartNew;
    mAnswer := FServer.Complete('unit Haupt;'#13#10'interface'#13#10'uses Gross;'#13#10'implementation'#13#10 +
      'procedure Pruefe(AGross: TGross);'#13#10'begin'#13#10'  AGross.FF|'#13#10'end;'#13#10'end.');
    Inc(mWith, mWatch.ElapsedMilliseconds);
    try
      Assert.AreEqual(IntToStr(cFields), HiddenOf(mAnswer).GetValue('count').Value);
    finally
      mAnswer.Free;
    end;
  end;
  Assert.IsTrue(mWith <= 2 * mWithout + 50 * cRounds, Format('%d ms mit, %d ms ohne', [mWith, mWithout]));
end;

end.
