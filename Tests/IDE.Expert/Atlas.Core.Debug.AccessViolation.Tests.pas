unit Atlas.Core.Debug.AccessViolation.Tests;

// Zugriffsverletzung erklären (#865), Plugin-Kern: Meldung lesen und die Folge der Fragen an den Debugger bis
// zum Urteil.

interface

uses
  System.Generics.Collections,
  DUnitX.TestFramework,
  Atlas.Core.Lsp.AccessChains,
  Atlas.Core.Debug.AccessViolation;

type
  [TestFixture]
  TAtlasAccessViolationTests = class
  private
    FAnswers: TDictionary<string, string>;
    FAsked: TArray<string>;
    FSideEffects: TArray<Boolean>;
    procedure Give(const AExpression, AValue: string);
    procedure Run(AAnalysis: TAtlasAvAnalysis);
    function Asked(const AExpression: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ParsesGermanMessage;
    [Test]
    procedure ParsesEnglishWin64Message;
    [Test]
    procedure ExternalExceptionOnlyWithC0000005;
    [Test]
    procedure OtherExceptionsAreNoAccessViolation;
    [Test]
    procedure ParsesAddresses;
    [Test]
    procedure RecognisesFreedPatterns;
    [Test]
    procedure NilLinkWithConfirmedField;
    [Test]
    procedure NilLinkKeepsEstimateWhenDebuggerCannotCompute;
    [Test]
    procedure NilLinkWithoutFieldWhenEstimateRefuted;
    [Test]
    procedure AddressZeroIsVmtAccess;
    [Test]
    procedure FreedValue;
    [Test]
    procedure FreedObjectHeader;
    [Test]
    procedure FreedObjectSecondWordFullDebugMode;
    [Test]
    procedure InvalidPointer;
    [Test]
    procedure IndexOutOfRange;
    [Test]
    procedure GetterStaysUnevaluatedWithoutAllowCalls;
    [Test]
    procedure GetterEvaluatedWithAllowCalls;
    [Test]
    procedure TwoCausesAreAmbiguous;
    [Test]
    procedure AddressInFreedPatternIsFreedMemory;
    [Test]
    procedure PlainExpressionWhenCastFails;
    [Test]
    procedure AbortLeavesRestUnevaluated;
  end;

implementation

uses
  System.SysUtils;

function Link(const AExpression: string; AKind: TAtlasAvLinkKind; const ATypeName: string): TAtlasAvLink;
begin
  Result := Default(TAtlasAvLink);
  Result.Expression := AExpression;
  Result.Name := AExpression;
  if LastDelimiter('.', AExpression) > 0 then
    Result.Name := Copy(AExpression, LastDelimiter('.', AExpression) + 1, MaxInt);
  Result.Kind := AKind;
  Result.TypeName := ATypeName;
end;

function Field(const AName: string; AOffset: Integer): TAtlasAvField;
begin
  Result.Name := AName;
  Result.Offset := AOffset;
end;

function Chain(const AText: string; const ALinks: TArray<TAtlasAvLink>): TAtlasAvChain;
begin
  Result.Text := AText;
  Result.Links := ALinks;
end;

function Chains(const AChains: TArray<TAtlasAvChain>): TAtlasAvChains;
begin
  Result := Default(TAtlasAvChains);
  Result.Found := True;
  Result.Statements := 1;
  Result.Chains := AChains;
end;

/// <summary>Auftrag.Kunde.Adresse.Ort: Glieder Auftrag und Auftrag.Kunde (TKunde mit FName und FAdresse).</summary>
function KundenKette(AKundeCall: Boolean): TAtlasAvChains;
var
  Kunde: TAtlasAvLink;
begin
  Kunde := Link('Auftrag.Kunde', TAtlasAvLinkKind.ClassRef, 'TKunde');
  Kunde.Call := AKundeCall;
  Kunde.Fields := TArray<TAtlasAvField>.Create(Field('FName', 4), Field('FAdresse', 8), Field('FOrt', 12));
  Result := Chains(TArray<TAtlasAvChain>.Create(Chain('Auftrag.Kunde.Adresse',
    TArray<TAtlasAvLink>.Create(Link('Auftrag', TAtlasAvLinkKind.ClassRef, 'TAuftrag'), Kunde))));
end;

function AvMessage(AAddress: UInt64): TAtlasAvMessage;
begin
  Result := Default(TAtlasAvMessage);
  Result.IsAccessViolation := True;
  Result.AddressKnown := True;
  Result.Operation := TAtlasAvOperation.Read;
  Result.Address := AAddress;
end;

{ TAtlasAccessViolationTests }

procedure TAtlasAccessViolationTests.Setup;
begin
  FAnswers := TDictionary<string, string>.Create;
end;

procedure TAtlasAccessViolationTests.TearDown;
begin
  FreeAndNil(FAnswers);
  FAsked := nil;
  FSideEffects := nil;
end;

procedure TAtlasAccessViolationTests.Give(const AExpression, AValue: string);
begin
  FAnswers.AddOrSetValue(AExpression, AValue);
end;

procedure TAtlasAccessViolationTests.Run(AAnalysis: TAtlasAvAnalysis);
var
  Request: TAtlasAvRequest;
  Value: string;
  Steps: Integer;
begin
  Steps := 0;
  while AAnalysis.Next(Request) do
  begin
    FAsked := FAsked + [Request.Expression];
    FSideEffects := FSideEffects + [Request.SideEffects];
    if FAnswers.TryGetValue(Request.Expression, Value) then
      AAnalysis.Answer(True, Value)
    else
      AAnalysis.Answer(False, 'E2003 Undeklarierter Bezeichner');
    Inc(Steps);
    if Steps > 200 then
      Assert.Fail('Die Analyse endet nicht');
  end;
  Assert.IsTrue(AAnalysis.Done);
end;

function TAtlasAccessViolationTests.Asked(const AExpression: string): Boolean;
var
  Item: string;
begin
  for Item in FAsked do
    if Item = AExpression then
      Exit(True);
  Result := False;
end;

procedure TAtlasAccessViolationTests.ParsesGermanMessage;
var
  Parsed: TAtlasAvMessage;
begin
  Parsed := TAtlasAvMessage.Parse('EAccessViolation',
    'Zugriffsverletzung bei Adresse 00451234 in Modul ''Kasse.exe''. Lesen von Adresse 0000001C');
  Assert.IsTrue(Parsed.IsAccessViolation);
  Assert.IsTrue(Parsed.AddressKnown);
  Assert.IsTrue(Parsed.Operation = TAtlasAvOperation.Read);
  Assert.AreEqual<UInt64>(UInt64($1C), Parsed.Address);
  Parsed := TAtlasAvMessage.Parse('EAccessViolation',
    'Zugriffsverletzung bei Adresse 00451234 in Modul ''Kasse.exe''. Schreiben von Adresse 00000008');
  Assert.IsTrue(Parsed.Operation = TAtlasAvOperation.Write);
  Assert.AreEqual<UInt64>(UInt64(8), Parsed.Address);
  Parsed := TAtlasAvMessage.Parse('EAccessViolation',
    'Zugriffsverletzung bei Adresse 00000000. Ausführung von Adresse 00000000');
  Assert.IsTrue(Parsed.Operation = TAtlasAvOperation.Execute);
  Assert.AreEqual<UInt64>(UInt64(0), Parsed.Address);
end;

procedure TAtlasAccessViolationTests.ParsesEnglishWin64Message;
var
  Parsed: TAtlasAvMessage;
begin
  Parsed := TAtlasAvMessage.Parse('EAccessViolation',
    'Access violation at address 00007FF6A1B21234 in module ''Kasse.exe''. Write of address 0000000000000010');
  Assert.IsTrue(Parsed.AddressKnown);
  Assert.IsTrue(Parsed.Operation = TAtlasAvOperation.Write);
  Assert.AreEqual<UInt64>(UInt64($10), Parsed.Address);
  Parsed := TAtlasAvMessage.Parse('EAccessViolation',
    'Access violation at address 00451234. Read of address FEEEFEEEFEEEFEF2');
  Assert.AreEqual<UInt64>(UInt64($FEEEFEEEFEEEFEF2), Parsed.Address);
end;

procedure TAtlasAccessViolationTests.ExternalExceptionOnlyWithC0000005;
var
  Parsed: TAtlasAvMessage;
begin
  Parsed := TAtlasAvMessage.Parse('EExternalException', 'Externe Exception C0000005');
  Assert.IsTrue(Parsed.IsAccessViolation);
  Assert.IsFalse(Parsed.AddressKnown);
  Parsed := TAtlasAvMessage.Parse('EExternalException', 'Externe Exception C000001D');
  Assert.IsFalse(Parsed.IsAccessViolation);
end;

procedure TAtlasAccessViolationTests.OtherExceptionsAreNoAccessViolation;
begin
  Assert.IsFalse(TAtlasAvMessage.Parse('EConvertError', '''abc'' ist kein gültiger Integerwert').IsAccessViolation);
  Assert.IsTrue(TAtlasAvMessage.Parse('EAccessViolation', '').IsAccessViolation);
  Assert.IsFalse(TAtlasAvMessage.Parse('EAccessViolation', '').AddressKnown);
end;

procedure TAtlasAccessViolationTests.ParsesAddresses;
var
  Value: UInt64;
  Number: Int64;
begin
  Assert.IsTrue(TAtlasAvAnalysis.ParseAddress('nil', Value));
  Assert.AreEqual<UInt64>(UInt64(0), Value);
  Assert.IsTrue(TAtlasAvAnalysis.ParseAddress('$02A41230', Value));
  Assert.AreEqual<UInt64>(UInt64($02A41230), Value);
  Assert.IsTrue(TAtlasAvAnalysis.ParseAddress('0x7ff6a1b2', Value));
  Assert.AreEqual<UInt64>(UInt64($7FF6A1B2), Value);
  Assert.IsTrue(TAtlasAvAnalysis.ParseAddress('($1C)', Value));
  Assert.AreEqual<UInt64>(UInt64($1C), Value);
  Assert.IsTrue(TAtlasAvAnalysis.ParseAddress('28', Value));
  Assert.AreEqual<UInt64>(UInt64(28), Value);
  Assert.IsTrue(TAtlasAvAnalysis.ParseAddress('18369900232523579118', Value));
  Assert.AreEqual<UInt64>(UInt64($FEEEFEEEFEEEFEEE), Value);
  Assert.IsFalse(TAtlasAvAnalysis.ParseAddress('''Text''', Value));
  Assert.IsFalse(TAtlasAvAnalysis.ParseAddress('', Value));
  Assert.IsTrue(TAtlasAvAnalysis.ParseInteger(' 7 ', Number));
  Assert.AreEqual<Int64>(Int64(7), Number);
  Assert.IsTrue(TAtlasAvAnalysis.ParseInteger('-1', Number));
  Assert.AreEqual<Int64>(Int64(-1), Number);
  Assert.AreEqual('$0000001C', TAtlasAvAnalysis.HexText($1C));
  Assert.AreEqual('$00007FF6A1B21234', TAtlasAvAnalysis.HexText($7FF6A1B21234));
end;

procedure TAtlasAccessViolationTests.RecognisesFreedPatterns;
begin
  Assert.IsTrue(TAtlasAvAnalysis.IsFreedPattern($80808080, 4));
  Assert.IsTrue(TAtlasAvAnalysis.IsFreedPattern($FEEEFEEE, 4));
  Assert.IsFalse(TAtlasAvAnalysis.IsFreedPattern($8080808080808080, 4));
  Assert.IsTrue(TAtlasAvAnalysis.IsFreedPattern($8080808080808080, 8));
  Assert.IsTrue(TAtlasAvAnalysis.IsFreedPattern($80808080, 8));
  Assert.IsFalse(TAtlasAvAnalysis.IsFreedPattern($02A41230, 4));
  Assert.IsTrue(TAtlasAvAnalysis.NearFreedPattern($80808094, 4));
  Assert.IsFalse(TAtlasAvAnalysis.NearFreedPattern($80908080, 4));
  Assert.IsTrue(TAtlasAvAnalysis.NearFreedPattern($FEEEFEEEFEEEFEF2, 8));
end;

procedure TAtlasAccessViolationTests.NilLinkWithConfirmedField;
var
  Analysis: TAtlasAvAnalysis;
  Verdict: TAtlasAvVerdict;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', 'nil');
  Give('NativeInt(@TKunde(nil).FAdresse)', '8');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage(8), 4, False);
  try
    Run(Analysis);
    Verdict := Analysis.Verdict;
    Assert.IsTrue(Verdict.Kind = TAtlasAvVerdictKind.NilLink);
    Assert.IsTrue(Verdict.HasCulprit);
    Assert.AreEqual('Auftrag.Kunde', Verdict.Culprit.Expression);
    Assert.AreEqual('FAdresse', Verdict.Field);
    Assert.AreEqual(8, Verdict.FieldOffset);
    Assert.IsTrue(Verdict.FieldExact);
    Assert.IsFalse(Verdict.VmtAccess);
    Assert.AreEqual(1, Verdict.Causes);
    Assert.IsTrue(Analysis.Checks[0].State = TAtlasAvCheckState.Ok);
    Assert.AreEqual('$02A41230', Analysis.Checks[0].Value);
    Assert.IsTrue(Analysis.Checks[1].State = TAtlasAvCheckState.NilValue);
    // Die Schätzung zuerst: eine einzige Frage nach dem Versatz, kein Kopf.
    Assert.AreEqual('NativeInt(@TKunde(nil).FAdresse)', FAsked[High(FAsked)]);
    Assert.AreEqual(3, Integer(Length(FAsked)));
    Assert.IsFalse(Asked('NativeInt(@TKunde(nil).FName)'));
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.NilLinkKeepsEstimateWhenDebuggerCannotCompute;
var
  Analysis: TAtlasAvAnalysis;
  Verdict: TAtlasAvVerdict;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', 'nil');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage(8), 4, False);
  try
    Run(Analysis);
    Verdict := Analysis.Verdict;
    Assert.IsTrue(Verdict.Kind = TAtlasAvVerdictKind.NilLink);
    Assert.AreEqual('FAdresse', Verdict.Field);
    Assert.IsFalse(Verdict.FieldExact);
    // Nach dem ersten Fehler fragt Atlas nicht weiter.
    Assert.IsFalse(Asked('NativeInt(@TKunde(nil).FName)'));
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.NilLinkWithoutFieldWhenEstimateRefuted;
var
  Analysis: TAtlasAvAnalysis;
  Verdict: TAtlasAvVerdict;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', 'nil');
  Give('NativeInt(@TKunde(nil).FName)', '8');
  Give('NativeInt(@TKunde(nil).FAdresse)', '16');
  Give('NativeInt(@TKunde(nil).FOrt)', '24');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage($C), 4, False);
  try
    Run(Analysis);
    Verdict := Analysis.Verdict;
    Assert.IsTrue(Verdict.Kind = TAtlasAvVerdictKind.NilLink);
    // Geschätzt war FOrt (12), der Debugger sagt 24; kein anderes Feld liegt bei 12.
    Assert.AreEqual('', Verdict.Field);
    Assert.IsTrue(Asked('NativeInt(@TKunde(nil).FName)'));
    Assert.IsTrue(Asked('NativeInt(@TKunde(nil).FOrt)'));
  finally
    Analysis.Free;
  end;
  FAsked := nil;
  // Ohne Schätzung, aber der Debugger findet das Feld.
  Give('NativeInt(@TKunde(nil).FAdresse)', '20');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage(20), 4, False);
  try
    Run(Analysis);
    Assert.AreEqual('FAdresse', Analysis.Verdict.Field);
    Assert.IsTrue(Analysis.Verdict.FieldExact);
    Assert.AreEqual(20, Analysis.Verdict.FieldOffset);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.AddressZeroIsVmtAccess;
var
  Analysis: TAtlasAvAnalysis;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', 'nil');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage(0), 4, False);
  try
    Run(Analysis);
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.NilLink);
    Assert.IsTrue(Analysis.Verdict.VmtAccess);
    Assert.AreEqual('', Analysis.Verdict.Field);
    Assert.AreEqual(2, Integer(Length(FAsked)));
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.FreedValue;
var
  Analysis: TAtlasAvAnalysis;
begin
  Give('Pointer(Auftrag)', '$80808080');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage($80808088), 4, False);
  try
    Run(Analysis);
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.Freed);
    Assert.AreEqual('Auftrag', Analysis.Verdict.Culprit.Expression);
    Assert.AreEqual<UInt64>(UInt64($80808080), Analysis.Verdict.Value);
    Assert.IsTrue(Analysis.Checks[1].State = TAtlasAvCheckState.NotReached);
    Assert.IsFalse(Asked('Pointer(Auftrag.Kunde)'));
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.FreedObjectHeader;
var
  Analysis: TAtlasAvAnalysis;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', '$02A50000');
  Give('PNativeUInt($02A41230)^', '$00401000');
  Give('PNativeUInt($02A50000)^', '$80808080');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage($02A50008), 4, False);
  try
    Run(Analysis);
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.Freed);
    Assert.AreEqual('Auftrag.Kunde', Analysis.Verdict.Culprit.Expression);
    Assert.IsTrue(Analysis.Checks[0].State = TAtlasAvCheckState.Ok);
    Assert.IsTrue(Analysis.Checks[1].State = TAtlasAvCheckState.Freed);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.FreedObjectSecondWordFullDebugMode;
var
  Analysis: TAtlasAvAnalysis;
begin
  // FastMM FullDebugMode: VMT-Zeiger auf TFreedObject, dahinter das Füllmuster.
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', '$02A50000');
  Give('PNativeUInt($02A41230)^', '$00401000');
  Give('PNativeUInt($02A41234)^', '$02A60000');
  Give('PNativeUInt($02A50000)^', '$00450000');
  Give('PNativeUInt($02A50004)^', '2155905152');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage($02A50008), 4, False);
  try
    Run(Analysis);
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.Freed);
    Assert.AreEqual('Auftrag.Kunde', Analysis.Verdict.Culprit.Expression);
    Assert.IsTrue(Asked('PNativeUInt($02A41234)^'), 'zweites Wort auch beim ersten Objekt');
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.InvalidPointer;
var
  Analysis: TAtlasAvAnalysis;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', '$0000001C');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage($24), 4, False);
  try
    Run(Analysis);
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.Invalid);
    Assert.AreEqual<UInt64>(UInt64($1C), Analysis.Verdict.Value);
    Assert.AreEqual('Auftrag.Kunde', Analysis.Verdict.Culprit.Expression);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.IndexOutOfRange;
var
  Liste: TAtlasAvLink;
  Analysis: TAtlasAvAnalysis;
begin
  Liste := Link('Liste', TAtlasAvLinkKind.DynArray, 'TArray<TKunde>');
  Liste.IndexText := 'I';
  Liste.IndexPlain := True;
  Give('Pointer(Liste)', '$03000010');
  Give('Length(Liste)', '5');
  Give('I', '7');
  Analysis := TAtlasAvAnalysis.Create(Chains(TArray<TAtlasAvChain>.Create(Chain('Liste[I].Name',
    TArray<TAtlasAvLink>.Create(Liste, Link('Liste[I]', TAtlasAvLinkKind.ClassRef, 'TKunde'))))),
    AvMessage($03000030), 4, False);
  try
    Run(Analysis);
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.OutOfRange);
    Assert.AreEqual<Int64>(Int64(7), Analysis.Verdict.Index);
    Assert.AreEqual<Int64>(Int64(5), Analysis.Verdict.Length);
    Assert.IsTrue(Analysis.Checks[1].State = TAtlasAvCheckState.NotReached);
    Assert.AreEqual('$03000010 · I = 7 / 5', Analysis.Checks[0].Value);
  finally
    Analysis.Free;
  end;
  // Index im Bereich: kein Fehler am Array, weiter mit dem nächsten Glied.
  FAsked := nil;
  Give('I', '2');
  Give('Pointer(Liste[I])', 'nil');
  Analysis := TAtlasAvAnalysis.Create(Chains(TArray<TAtlasAvChain>.Create(Chain('Liste[I].Name',
    TArray<TAtlasAvLink>.Create(Liste, Link('Liste[I]', TAtlasAvLinkKind.ClassRef, 'TKunde'))))),
    AvMessage(4), 4, False);
  try
    Run(Analysis);
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.NilLink);
    Assert.AreEqual('Liste[I]', Analysis.Verdict.Culprit.Expression);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.GetterStaysUnevaluatedWithoutAllowCalls;
var
  Analysis: TAtlasAvAnalysis;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('PNativeUInt($02A41230)^', '$00401000');
  Give('Pointer(Auftrag.Kunde)', 'nil');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(True), AvMessage(8), 4, False);
  try
    Run(Analysis);
    Assert.IsTrue(Analysis.Checks[1].State = TAtlasAvCheckState.NotEvaluated);
    Assert.IsFalse(Asked('Pointer(Auftrag.Kunde)'));
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.Ambiguous);
    Assert.AreEqual(0, Analysis.Verdict.Causes);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.GetterEvaluatedWithAllowCalls;
var
  Analysis: TAtlasAvAnalysis;
  Index: Integer;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', 'nil');
  Give('NativeInt(@TKunde(nil).FAdresse)', '8');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(True), AvMessage(8), 4, True);
  try
    Run(Analysis);
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.NilLink);
    Assert.AreEqual('Auftrag.Kunde', Analysis.Verdict.Culprit.Expression);
    for Index := 0 to High(FAsked) do
      Assert.AreEqual(FAsked[Index] = 'Pointer(Auftrag.Kunde)', FSideEffects[Index], FAsked[Index]);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.TwoCausesAreAmbiguous;
var
  Analysis: TAtlasAvAnalysis;
  Input: TAtlasAvChains;
begin
  Input := Chains(TArray<TAtlasAvChain>.Create(
    Chain('A.X', TArray<TAtlasAvLink>.Create(Link('A', TAtlasAvLinkKind.ClassRef, 'TA'))),
    Chain('B.Y', TArray<TAtlasAvLink>.Create(Link('B', TAtlasAvLinkKind.ClassRef, 'TB')))));
  Input.Statements := 2;
  Give('Pointer(A)', 'nil');
  Give('Pointer(B)', 'nil');
  Analysis := TAtlasAvAnalysis.Create(Input, AvMessage(4), 4, False);
  try
    Run(Analysis);
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.Ambiguous);
    Assert.AreEqual(2, Analysis.Verdict.Causes);
    Assert.IsFalse(Analysis.Verdict.HasCulprit);
    Assert.IsTrue(Analysis.Checks[0].State = TAtlasAvCheckState.NilValue);
    Assert.IsTrue(Analysis.Checks[1].State = TAtlasAvCheckState.NilValue);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.AddressInFreedPatternIsFreedMemory;
var
  Analysis: TAtlasAvAnalysis;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', '$02A50000');
  Give('PNativeUInt($02A41230)^', '$00401000');
  Give('PNativeUInt($02A50000)^', '$00402000');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage($80808094), 4, False);
  try
    Run(Analysis);
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.FreedMemory);
    Assert.AreEqual<UInt64>(UInt64($80808094), Analysis.Verdict.Value);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.PlainExpressionWhenCastFails;
var
  Analysis: TAtlasAvAnalysis;
begin
  Give('Auftrag', 'nil');
  Analysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage(4), 4, False);
  try
    Run(Analysis);
    Assert.IsTrue(Asked('Pointer(Auftrag)'));
    Assert.IsTrue(Asked('Auftrag'));
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.NilLink);
    Assert.AreEqual('Auftrag', Analysis.Verdict.Culprit.Expression);
  finally
    Analysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.AbortLeavesRestUnevaluated;
var
  Analysis: TAtlasAvAnalysis;
  Request: TAtlasAvRequest;
begin
  Analysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage(8), 4, False);
  try
    Assert.IsTrue(Analysis.Next(Request));
    Assert.AreEqual('Pointer(Auftrag)', Request.Expression);
    Analysis.Abort;
    Assert.IsTrue(Analysis.Done);
    Assert.IsFalse(Analysis.Next(Request));
    Assert.IsTrue(Analysis.Checks[0].State = TAtlasAvCheckState.NotEvaluated);
    Assert.IsTrue(Analysis.Checks[1].State = TAtlasAvCheckState.NotEvaluated);
    Assert.IsTrue(Analysis.Verdict.Kind = TAtlasAvVerdictKind.Ambiguous);
  finally
    Analysis.Free;
  end;
end;

end.
