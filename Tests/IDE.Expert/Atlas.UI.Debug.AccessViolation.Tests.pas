unit Atlas.UI.Debug.AccessViolation.Tests;

// Zugriffsverletzung erklären (#865), Texte: Ergebniszeile, Feld und Versatz, geprüfte Glieder mit ✓/✗,
// Knöpfe, kopierter Text und Zeilen für die Meldungen.

interface

uses
  System.Generics.Collections,
  DUnitX.TestFramework,
  Atlas.UI.Strings,
  Atlas.Core.Lsp.AccessChains,
  Atlas.Core.Debug.AccessViolation,
  Atlas.UI.Debug.AccessViolation;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasAvTextsTests = class
  private
    FLanguage: TAtlasLanguage;
    FAnswers: TDictionary<string, string>;
    function Analyse(const AChains: TAtlasAvChains; AAddress: UInt64; AAllowCalls: Boolean): TAtlasAvAnalysis;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NilLinkNamesFieldAndOffset;
    [Test]
    procedure EstimatedFieldIsMarked;
    [Test]
    procedure VmtAccess;
    [Test]
    procedure FreedShowsPattern;
    [Test]
    procedure OutOfRangeNamesIndexAndLength;
    [Test]
    procedure AmbiguousWithSeveralStatements;
    [Test]
    procedure CheckLinesShowState;
    [Test]
    procedure WhereButtonOnlyForNamedLinkAndWhenAllowed;
    [Test]
    procedure CopyTextAndMessageLines;
    [Test]
    procedure BusyAndFailed;
  end;

implementation

uses
  Atlas.UI.Debug.Strings,
  Atlas.Core.Debug.ExceptionBanner,
  System.SysUtils;

function Link(const AExpression, AName: string; AKind: TAtlasAvLinkKind; const ATypeName: string): TAtlasAvLink;
begin
  Result := Default(TAtlasAvLink);
  Result.Expression := AExpression;
  Result.Name := AName;
  Result.Kind := AKind;
  Result.TypeName := ATypeName;
end;

function KundenKette(AKundeCall: Boolean): TAtlasAvChains;
var
  mKunde: TAtlasAvLink;
  mField: TAtlasAvField;
  mChain: TAtlasAvChain;
begin
  mKunde := Link('Auftrag.Kunde', 'Kunde', TAtlasAvLinkKind.ClassRef, 'TKunde');
  mKunde.Call := AKundeCall;
  mField.Name := 'FAdresse';
  mField.Offset := $1C;
  mKunde.Fields := TArray<TAtlasAvField>.Create(mField);
  mChain.Text := 'Auftrag.Kunde.Adresse';
  mChain.Links := TArray<TAtlasAvLink>.Create(Link('Auftrag', 'Auftrag', TAtlasAvLinkKind.ClassRef, 'TAuftrag'),
    mKunde);
  Result := Default(TAtlasAvChains);
  Result.Found := True;
  Result.Statements := 1;
  Result.Chains := TArray<TAtlasAvChain>.Create(mChain);
end;

{ TAtlasAvTextsTests }

procedure TAtlasAvTextsTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
  FAnswers := TDictionary<string, string>.Create;
end;

procedure TAtlasAvTextsTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
  FreeAndNil(FAnswers);
end;

function TAtlasAvTextsTests.Analyse(const AChains: TAtlasAvChains; AAddress: UInt64;
  AAllowCalls: Boolean): TAtlasAvAnalysis;
var
  mMessage: TAtlasAvMessage;
  mRequest: TAtlasAvRequest;
  mValue: string;
begin
  mMessage := Default(TAtlasAvMessage);
  mMessage.IsAccessViolation := True;
  mMessage.AddressKnown := True;
  mMessage.Address := AAddress;
  Result := TAtlasAvAnalysis.Create(AChains, mMessage, 4, AAllowCalls);
  while Result.Next(mRequest) do
  begin
    if FAnswers.TryGetValue(mRequest.Expression, mValue) then
    begin
      Result.Answer(True, mValue);
    end
    else
    begin
      Result.Answer(False, '');
    end;
  end;
end;

procedure TAtlasAvTextsTests.NilLinkNamesFieldAndOffset;
var
  mAnalysis: TAtlasAvAnalysis;
  mExplanation: TAtlasDebugBannerExplanation;
begin
  FAnswers.Add('Pointer(Auftrag)', '$02A41230');
  FAnswers.Add('Pointer(Auftrag.Kunde)', 'nil');
  FAnswers.Add('NativeInt(@TKunde(nil).FAdresse)', '28');
  mAnalysis := Analyse(KundenKette(False), $1C, False);
  try
    mExplanation := TAtlasAvTexts.FromAnalysis(mAnalysis, True, True, '');
    Assert.IsTrue(mExplanation.Active);
    Assert.IsFalse(mExplanation.Busy);
    Assert.AreEqual('Auftrag.Kunde ist nil', mExplanation.Headline);
    Assert.AreEqual('Zugriff auf Feld FAdresse (Versatz $1C)', mExplanation.Detail);
    Assert.IsTrue(mExplanation.HeadlineMark = TAtlasDebugBannerMark.Bad);
    Assert.AreEqual('Kunde', mExplanation.WhereName);
    Assert.AreEqual('Auftrag.Kunde', mExplanation.EvaluateExpression);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.EstimatedFieldIsMarked;
var
  mAnalysis: TAtlasAvAnalysis;
begin
  FAnswers.Add('Pointer(Auftrag)', '$02A41230');
  FAnswers.Add('Pointer(Auftrag.Kunde)', 'nil');
  mAnalysis := Analyse(KundenKette(False), $1C, False);
  try
    Assert.AreEqual('Zugriff auf Feld FAdresse (Versatz $1C, geschätzt)',
      TAtlasAvTexts.FromAnalysis(mAnalysis, True, True, '').Detail);
  finally
    mAnalysis.Free;
  end;
  // Kein Feld an der Adresse: nur der Versatz.
  mAnalysis := Analyse(KundenKette(False), $30, False);
  try
    Assert.AreEqual('Versatz $30, kein Feld bekannt', TAtlasAvTexts.FromAnalysis(mAnalysis, True, True, '').Detail);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.VmtAccess;
var
  mAnalysis: TAtlasAvAnalysis;
begin
  FAnswers.Add('Pointer(Auftrag)', 'nil');
  mAnalysis := Analyse(KundenKette(False), 0, False);
  try
    Assert.AreEqual('Auftrag ist nil', TAtlasAvTexts.FromAnalysis(mAnalysis, True, True, '').Headline);
    Assert.IsTrue(TAtlasAvTexts.FromAnalysis(mAnalysis, True, True, '').Detail.StartsWith('Zugriff auf die VMT'));
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.FreedShowsPattern;
var
  mAnalysis: TAtlasAvAnalysis;
  mExplanation: TAtlasDebugBannerExplanation;
begin
  FAnswers.Add('Pointer(Auftrag)', '$80808080');
  mAnalysis := Analyse(KundenKette(False), $80808088, False);
  try
    mExplanation := TAtlasAvTexts.FromAnalysis(mAnalysis, True, True, '');
    Assert.AreEqual('Auftrag ist bereits freigegeben', mExplanation.Headline);
    Assert.AreEqual('Füllmuster des Speichermanagers $80808080', mExplanation.Detail);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.OutOfRangeNamesIndexAndLength;
var
  mListe: TAtlasAvLink;
  mInput: TAtlasAvChains;
  mAnalysis: TAtlasAvAnalysis;
begin
  mListe := Link('Liste', 'Liste', TAtlasAvLinkKind.DynArray, 'TArray<TKunde>');
  mListe.IndexText := 'I';
  mListe.IndexPlain := True;
  mInput := Default(TAtlasAvChains);
  mInput.Statements := 1;
  SetLength(mInput.Chains, 1);
  mInput.Chains[0].Text := 'Liste[I].Name';
  mInput.Chains[0].Links := TArray<TAtlasAvLink>.Create(mListe);
  FAnswers.Add('Pointer(Liste)', '$03000010');
  FAnswers.Add('Length(Liste)', '5');
  FAnswers.Add('I', '7');
  mAnalysis := Analyse(mInput, $03000030, False);
  try
    Assert.AreEqual('Index I = 7 liegt außerhalb von Liste (Länge 5)',
      TAtlasAvTexts.FromAnalysis(mAnalysis, True, True, '').Headline);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.AmbiguousWithSeveralStatements;
var
  mInput: TAtlasAvChains;
  mAnalysis: TAtlasAvAnalysis;
  mExplanation: TAtlasDebugBannerExplanation;
begin
  mInput := KundenKette(False);
  mInput.Statements := 2;
  FAnswers.Add('Pointer(Auftrag)', '$02A41230');
  FAnswers.Add('Pointer(Auftrag.Kunde)', '$02A50000');
  FAnswers.Add('PNativeUInt($02A41230)^', '$00401000');
  FAnswers.Add('PNativeUInt($02A50000)^', '$00402000');
  mAnalysis := Analyse(mInput, $1C, False);
  try
    mExplanation := TAtlasAvTexts.FromAnalysis(mAnalysis, True, True, '');
    Assert.AreEqual('Ursache nicht eindeutig', mExplanation.Headline);
    Assert.IsTrue(mExplanation.Detail.Contains('kein geprüftes Glied'), mExplanation.Detail);
    Assert.IsTrue(mExplanation.Detail.EndsWith('2 Anweisungen in der Zeile'), mExplanation.Detail);
    Assert.IsTrue(mExplanation.HeadlineMark = TAtlasDebugBannerMark.Neutral);
    Assert.AreEqual('', mExplanation.WhereName);
    Assert.AreEqual('Auftrag.Kunde.Adresse', mExplanation.EvaluateExpression);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.CheckLinesShowState;
var
  mAnalysis: TAtlasAvAnalysis;
  mExplanation: TAtlasDebugBannerExplanation;
begin
  FAnswers.Add('Pointer(Auftrag)', '$02A41230');
  FAnswers.Add('PNativeUInt($02A41230)^', '$00401000');
  mAnalysis := Analyse(KundenKette(True), $1C, False);
  try
    mExplanation := TAtlasAvTexts.FromAnalysis(mAnalysis, True, True, '');
    Assert.AreEqual(2, Integer(Length(mExplanation.Lines)));
    Assert.IsTrue(mExplanation.Lines[0].Mark = TAtlasDebugBannerMark.Ok);
    Assert.AreEqual('Auftrag = $02A41230', mExplanation.Lines[0].Text);
    Assert.IsTrue(mExplanation.Lines[1].Mark = TAtlasDebugBannerMark.Neutral);
    Assert.AreEqual('Auftrag.Kunde: nicht ausgewertet: ruft etwas auf (debug.explainAccessViolation.allowCalls)',
      mExplanation.Lines[1].Text);
  finally
    mAnalysis.Free;
  end;
  FAnswers.Add('Pointer(Auftrag.Kunde)', 'nil');
  mAnalysis := Analyse(KundenKette(True), $1C, True);
  try
    mExplanation := TAtlasAvTexts.FromAnalysis(mAnalysis, True, True, '');
    Assert.IsTrue(mExplanation.Lines[1].Mark = TAtlasDebugBannerMark.Bad);
    Assert.AreEqual('Auftrag.Kunde = nil', mExplanation.Lines[1].Text);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.WhereButtonOnlyForNamedLinkAndWhenAllowed;
var
  mInput: TAtlasAvChains;
  mAnalysis: TAtlasAvAnalysis;
  mExplanation: TAtlasDebugBannerExplanation;
begin
  FAnswers.Add('Pointer(Auftrag)', '$02A41230');
  FAnswers.Add('Pointer(Auftrag.Kunde)', 'nil');
  mAnalysis := Analyse(KundenKette(False), $1C, False);
  try
    mExplanation := TAtlasAvTexts.FromAnalysis(mAnalysis, False, False, '');
    Assert.AreEqual('', mExplanation.WhereName);
    Assert.AreEqual('', mExplanation.EvaluateExpression);
    Assert.AreNotEqual('', mExplanation.CopyText);
  finally
    mAnalysis.Free;
  end;
  // Self ist nil (Methode auf nil-Referenz): niemand weist Self zu.
  mInput := KundenKette(False);
  mInput.Chains[0].Links[0] := Link('Self', 'Self', TAtlasAvLinkKind.ClassRef, 'TForm1');
  FAnswers.Add('Pointer(Self)', 'nil');
  mAnalysis := Analyse(mInput, $1C, False);
  try
    mExplanation := TAtlasAvTexts.FromAnalysis(mAnalysis, True, True, '');
    Assert.AreEqual('Self ist nil', mExplanation.Headline);
    Assert.AreEqual('', mExplanation.WhereName);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.CopyTextAndMessageLines;
var
  mAnalysis: TAtlasAvAnalysis;
  mExplanation: TAtlasDebugBannerExplanation;
  mLines: TArray<string>;
begin
  FAnswers.Add('Pointer(Auftrag)', '$02A41230');
  FAnswers.Add('Pointer(Auftrag.Kunde)', 'nil');
  FAnswers.Add('NativeInt(@TKunde(nil).FAdresse)', '28');
  mAnalysis := Analyse(KundenKette(False), $1C, False);
  try
    mExplanation := TAtlasAvTexts.FromAnalysis(mAnalysis, True, True,
      'EAccessViolation: Zugriffsverletzung … Lesen von Adresse 0000001C (Unit1.pas:42)');
    Assert.IsTrue(mExplanation.CopyText.StartsWith('Zugriffsverletzung erklärt (Atlas)' + sLineBreak +
      'Auftrag.Kunde ist nil' + sLineBreak + 'Zugriff auf Feld FAdresse'), mExplanation.CopyText);
    Assert.IsTrue(mExplanation.CopyText.Contains('(Unit1.pas:42)'), mExplanation.CopyText);
    Assert.IsTrue(mExplanation.CopyText.EndsWith(sLineBreak + '  ' + #$2717 + ' Auftrag.Kunde = nil'),
      mExplanation.CopyText);
    mLines := TAtlasAvTexts.MessageLines(mExplanation, 'Unit1.pas:42');
    Assert.AreEqual(3, Integer(Length(mLines)));
    Assert.AreEqual('Zugriffsverletzung in Unit1.pas:42: Auftrag.Kunde ist nil ' + #$00B7 +
      ' Zugriff auf Feld FAdresse (Versatz $1C)', mLines[0]);
    Assert.AreEqual('  ' + #$2713 + ' Auftrag = $02A41230', mLines[1]);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.BusyAndFailed;
var
  mExplanation: TAtlasDebugBannerExplanation;
begin
  mExplanation := TAtlasAvTexts.Busy;
  Assert.IsTrue(mExplanation.Active and mExplanation.Busy);
  Assert.IsTrue(mExplanation.Headline.StartsWith('Atlas prüft'), mExplanation.Headline);
  Assert.AreEqual('', mExplanation.CopyText);
  mExplanation := TAtlasAvTexts.Failed(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugAvNoChains), 'EAccessViolation');
  Assert.IsFalse(mExplanation.Busy);
  Assert.AreEqual('Ursache nicht eindeutig', mExplanation.Headline);
  Assert.AreEqual('keine Zugriffskette in der Zeile', mExplanation.Detail);
  Assert.IsTrue(mExplanation.CopyText.Contains('EAccessViolation'));
  Assert.AreEqual('$1C', TAtlasAvTexts.OffsetText($1C));
  Assert.AreEqual('$08', TAtlasAvTexts.OffsetText(8));
end;

end.
