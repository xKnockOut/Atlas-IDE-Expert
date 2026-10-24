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
  Atlas.Core.Debug.ExceptionBanner,
  Atlas.UI.Debug.AccessViolation;

type
  [TestFixture]
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
  Kunde: TAtlasAvLink;
  Field: TAtlasAvField;
  Chain: TAtlasAvChain;
begin
  Kunde := Link('Auftrag.Kunde', 'Kunde', TAtlasAvLinkKind.ClassRef, 'TKunde');
  Kunde.Call := AKundeCall;
  Field.Name := 'FAdresse';
  Field.Offset := $1C;
  Kunde.Fields := TArray<TAtlasAvField>.Create(Field);
  Chain.Text := 'Auftrag.Kunde.Adresse';
  Chain.Links := TArray<TAtlasAvLink>.Create(Link('Auftrag', 'Auftrag', TAtlasAvLinkKind.ClassRef, 'TAuftrag'),
    Kunde);
  Result := Default(TAtlasAvChains);
  Result.Found := True;
  Result.Statements := 1;
  Result.Chains := TArray<TAtlasAvChain>.Create(Chain);
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
  Message: TAtlasAvMessage;
  Request: TAtlasAvRequest;
  Value: string;
begin
  Message := Default(TAtlasAvMessage);
  Message.IsAccessViolation := True;
  Message.AddressKnown := True;
  Message.Address := AAddress;
  Result := TAtlasAvAnalysis.Create(AChains, Message, 4, AAllowCalls);
  while Result.Next(Request) do
    if FAnswers.TryGetValue(Request.Expression, Value) then
      Result.Answer(True, Value)
    else
      Result.Answer(False, '');
end;

procedure TAtlasAvTextsTests.NilLinkNamesFieldAndOffset;
var
  Analysis: TAtlasAvAnalysis;
  Explanation: TAtlasDebugBannerExplanation;
begin
  FAnswers.Add('Pointer(Auftrag)', '$02A41230');
  FAnswers.Add('Pointer(Auftrag.Kunde)', 'nil');
  FAnswers.Add('NativeInt(@TKunde(nil).FAdresse)', '28');
  Analysis := Analyse(KundenKette(False), $1C, False);
  try
    Explanation := TAtlasAvTexts.FromAnalysis(Analysis, True, True, '');
    Assert.IsTrue(Explanation.Active);
    Assert.IsFalse(Explanation.Busy);
    Assert.AreEqual('Auftrag.Kunde ist nil', Explanation.Headline);
    Assert.AreEqual('Zugriff auf Feld FAdresse (Versatz $1C)', Explanation.Detail);
    Assert.IsTrue(Explanation.HeadlineMark = TAtlasDebugBannerMark.Bad);
    Assert.AreEqual('Kunde', Explanation.WhereName);
    Assert.AreEqual('Auftrag.Kunde', Explanation.EvaluateExpression);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.EstimatedFieldIsMarked;
var
  Analysis: TAtlasAvAnalysis;
begin
  FAnswers.Add('Pointer(Auftrag)', '$02A41230');
  FAnswers.Add('Pointer(Auftrag.Kunde)', 'nil');
  Analysis := Analyse(KundenKette(False), $1C, False);
  try
    Assert.AreEqual('Zugriff auf Feld FAdresse (Versatz $1C, geschätzt)',
      TAtlasAvTexts.FromAnalysis(Analysis, True, True, '').Detail);
  finally
    Analysis.Free;
  end;
  // Kein Feld an der Adresse: nur der Versatz.
  Analysis := Analyse(KundenKette(False), $30, False);
  try
    Assert.AreEqual('Versatz $30, kein Feld bekannt', TAtlasAvTexts.FromAnalysis(Analysis, True, True, '').Detail);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.VmtAccess;
var
  Analysis: TAtlasAvAnalysis;
begin
  FAnswers.Add('Pointer(Auftrag)', 'nil');
  Analysis := Analyse(KundenKette(False), 0, False);
  try
    Assert.AreEqual('Auftrag ist nil', TAtlasAvTexts.FromAnalysis(Analysis, True, True, '').Headline);
    Assert.IsTrue(TAtlasAvTexts.FromAnalysis(Analysis, True, True, '').Detail.StartsWith('Zugriff auf die VMT'));
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.FreedShowsPattern;
var
  Analysis: TAtlasAvAnalysis;
  Explanation: TAtlasDebugBannerExplanation;
begin
  FAnswers.Add('Pointer(Auftrag)', '$80808080');
  Analysis := Analyse(KundenKette(False), $80808088, False);
  try
    Explanation := TAtlasAvTexts.FromAnalysis(Analysis, True, True, '');
    Assert.AreEqual('Auftrag ist bereits freigegeben', Explanation.Headline);
    Assert.AreEqual('Füllmuster des Speichermanagers $80808080', Explanation.Detail);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.OutOfRangeNamesIndexAndLength;
var
  Liste: TAtlasAvLink;
  Input: TAtlasAvChains;
  Analysis: TAtlasAvAnalysis;
begin
  Liste := Link('Liste', 'Liste', TAtlasAvLinkKind.DynArray, 'TArray<TKunde>');
  Liste.IndexText := 'I';
  Liste.IndexPlain := True;
  Input := Default(TAtlasAvChains);
  Input.Statements := 1;
  SetLength(Input.Chains, 1);
  Input.Chains[0].Text := 'Liste[I].Name';
  Input.Chains[0].Links := TArray<TAtlasAvLink>.Create(Liste);
  FAnswers.Add('Pointer(Liste)', '$03000010');
  FAnswers.Add('Length(Liste)', '5');
  FAnswers.Add('I', '7');
  Analysis := Analyse(Input, $03000030, False);
  try
    Assert.AreEqual('Index I = 7 liegt außerhalb von Liste (Länge 5)',
      TAtlasAvTexts.FromAnalysis(Analysis, True, True, '').Headline);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.AmbiguousWithSeveralStatements;
var
  Input: TAtlasAvChains;
  Analysis: TAtlasAvAnalysis;
  Explanation: TAtlasDebugBannerExplanation;
begin
  Input := KundenKette(False);
  Input.Statements := 2;
  FAnswers.Add('Pointer(Auftrag)', '$02A41230');
  FAnswers.Add('Pointer(Auftrag.Kunde)', '$02A50000');
  FAnswers.Add('PNativeUInt($02A41230)^', '$00401000');
  FAnswers.Add('PNativeUInt($02A50000)^', '$00402000');
  Analysis := Analyse(Input, $1C, False);
  try
    Explanation := TAtlasAvTexts.FromAnalysis(Analysis, True, True, '');
    Assert.AreEqual('Ursache nicht eindeutig', Explanation.Headline);
    Assert.IsTrue(Explanation.Detail.Contains('kein geprüftes Glied'), Explanation.Detail);
    Assert.IsTrue(Explanation.Detail.EndsWith('2 Anweisungen in der Zeile'), Explanation.Detail);
    Assert.IsTrue(Explanation.HeadlineMark = TAtlasDebugBannerMark.Neutral);
    Assert.AreEqual('', Explanation.WhereName);
    Assert.AreEqual('Auftrag.Kunde.Adresse', Explanation.EvaluateExpression);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.CheckLinesShowState;
var
  Analysis: TAtlasAvAnalysis;
  Explanation: TAtlasDebugBannerExplanation;
begin
  FAnswers.Add('Pointer(Auftrag)', '$02A41230');
  FAnswers.Add('PNativeUInt($02A41230)^', '$00401000');
  Analysis := Analyse(KundenKette(True), $1C, False);
  try
    Explanation := TAtlasAvTexts.FromAnalysis(Analysis, True, True, '');
    Assert.AreEqual(2, Integer(Length(Explanation.Lines)));
    Assert.IsTrue(Explanation.Lines[0].Mark = TAtlasDebugBannerMark.Ok);
    Assert.AreEqual('Auftrag = $02A41230', Explanation.Lines[0].Text);
    Assert.IsTrue(Explanation.Lines[1].Mark = TAtlasDebugBannerMark.Neutral);
    Assert.AreEqual('Auftrag.Kunde: nicht ausgewertet: ruft etwas auf (debug.explainAccessViolation.allowCalls)',
      Explanation.Lines[1].Text);
  finally
    Analysis.Free;
  end;
  FAnswers.Add('Pointer(Auftrag.Kunde)', 'nil');
  Analysis := Analyse(KundenKette(True), $1C, True);
  try
    Explanation := TAtlasAvTexts.FromAnalysis(Analysis, True, True, '');
    Assert.IsTrue(Explanation.Lines[1].Mark = TAtlasDebugBannerMark.Bad);
    Assert.AreEqual('Auftrag.Kunde = nil', Explanation.Lines[1].Text);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.WhereButtonOnlyForNamedLinkAndWhenAllowed;
var
  Input: TAtlasAvChains;
  Analysis: TAtlasAvAnalysis;
  Explanation: TAtlasDebugBannerExplanation;
begin
  FAnswers.Add('Pointer(Auftrag)', '$02A41230');
  FAnswers.Add('Pointer(Auftrag.Kunde)', 'nil');
  Analysis := Analyse(KundenKette(False), $1C, False);
  try
    Explanation := TAtlasAvTexts.FromAnalysis(Analysis, False, False, '');
    Assert.AreEqual('', Explanation.WhereName);
    Assert.AreEqual('', Explanation.EvaluateExpression);
    Assert.AreNotEqual('', Explanation.CopyText);
  finally
    Analysis.Free;
  end;
  // Self ist nil (Methode auf nil-Referenz): niemand weist Self zu.
  Input := KundenKette(False);
  Input.Chains[0].Links[0] := Link('Self', 'Self', TAtlasAvLinkKind.ClassRef, 'TForm1');
  FAnswers.Add('Pointer(Self)', 'nil');
  Analysis := Analyse(Input, $1C, False);
  try
    Explanation := TAtlasAvTexts.FromAnalysis(Analysis, True, True, '');
    Assert.AreEqual('Self ist nil', Explanation.Headline);
    Assert.AreEqual('', Explanation.WhereName);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.CopyTextAndMessageLines;
var
  Analysis: TAtlasAvAnalysis;
  Explanation: TAtlasDebugBannerExplanation;
  Lines: TArray<string>;
begin
  FAnswers.Add('Pointer(Auftrag)', '$02A41230');
  FAnswers.Add('Pointer(Auftrag.Kunde)', 'nil');
  FAnswers.Add('NativeInt(@TKunde(nil).FAdresse)', '28');
  Analysis := Analyse(KundenKette(False), $1C, False);
  try
    Explanation := TAtlasAvTexts.FromAnalysis(Analysis, True, True,
      'EAccessViolation: Zugriffsverletzung … Lesen von Adresse 0000001C (Unit1.pas:42)');
    Assert.IsTrue(Explanation.CopyText.StartsWith('Zugriffsverletzung erklärt (Atlas)' + sLineBreak +
      'Auftrag.Kunde ist nil' + sLineBreak + 'Zugriff auf Feld FAdresse'), Explanation.CopyText);
    Assert.IsTrue(Explanation.CopyText.Contains('(Unit1.pas:42)'), Explanation.CopyText);
    Assert.IsTrue(Explanation.CopyText.EndsWith(sLineBreak + '  ' + #$2717 + ' Auftrag.Kunde = nil'),
      Explanation.CopyText);
    Lines := TAtlasAvTexts.MessageLines(Explanation, 'Unit1.pas:42');
    Assert.AreEqual(3, Integer(Length(Lines)));
    Assert.AreEqual('Zugriffsverletzung in Unit1.pas:42: Auftrag.Kunde ist nil ' + #$00B7 +
      ' Zugriff auf Feld FAdresse (Versatz $1C)', Lines[0]);
    Assert.AreEqual('  ' + #$2713 + ' Auftrag = $02A41230', Lines[1]);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAvTextsTests.BusyAndFailed;
var
  Explanation: TAtlasDebugBannerExplanation;
begin
  Explanation := TAtlasAvTexts.Busy;
  Assert.IsTrue(Explanation.Active and Explanation.Busy);
  Assert.IsTrue(Explanation.Headline.StartsWith('Atlas prüft'), Explanation.Headline);
  Assert.AreEqual('', Explanation.CopyText);
  Explanation := TAtlasAvTexts.Failed(TAtlasStrings.Text(TAtlasTextId.DebugAvNoChains), 'EAccessViolation');
  Assert.IsFalse(Explanation.Busy);
  Assert.AreEqual('Ursache nicht eindeutig', Explanation.Headline);
  Assert.AreEqual('keine Zugriffskette in der Zeile', Explanation.Detail);
  Assert.IsTrue(Explanation.CopyText.Contains('EAccessViolation'));
  Assert.AreEqual('$1C', TAtlasAvTexts.OffsetText($1C));
  Assert.AreEqual('$08', TAtlasAvTexts.OffsetText(8));
end;

end.
