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
  [Category('Atlas.IDE.Debugger')]
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
  begin
    Result.Name := Copy(AExpression, LastDelimiter('.', AExpression) + 1, MaxInt);
  end;
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
  mKunde: TAtlasAvLink;
begin
  mKunde := Link('Auftrag.Kunde', TAtlasAvLinkKind.ClassRef, 'TKunde');
  mKunde.Call := AKundeCall;
  mKunde.Fields := TArray<TAtlasAvField>.Create(Field('FName', 4), Field('FAdresse', 8), Field('FOrt', 12));
  Result := Chains(TArray<TAtlasAvChain>.Create(Chain('Auftrag.Kunde.Adresse',
    TArray<TAtlasAvLink>.Create(Link('Auftrag', TAtlasAvLinkKind.ClassRef, 'TAuftrag'), mKunde))));
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
  mRequest: TAtlasAvRequest;
  mValue: string;
  mSteps: Integer;
begin
  mSteps := 0;
  while AAnalysis.Next(mRequest) do
  begin
    FAsked := FAsked + [mRequest.Expression];
    FSideEffects := FSideEffects + [mRequest.SideEffects];
    if FAnswers.TryGetValue(mRequest.Expression, mValue) then
    begin
      AAnalysis.Answer(True, mValue);
    end
    else
    begin
      AAnalysis.Answer(False, 'E2003 Undeklarierter Bezeichner');
    end;
    Inc(mSteps);
    if mSteps > 200 then
    begin
      Assert.Fail('Die Analyse endet nicht');
    end;
  end;
  Assert.IsTrue(AAnalysis.Done);
end;

function TAtlasAccessViolationTests.Asked(const AExpression: string): Boolean;
var
  mItem: string;
begin
  for mItem in FAsked do
  begin
    if mItem = AExpression then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasAccessViolationTests.ParsesGermanMessage;
var
  mParsed: TAtlasAvMessage;
begin
  mParsed := TAtlasAvMessage.Parse('EAccessViolation',
    'Zugriffsverletzung bei Adresse 00451234 in Modul ''Kasse.exe''. Lesen von Adresse 0000001C');
  Assert.IsTrue(mParsed.IsAccessViolation);
  Assert.IsTrue(mParsed.AddressKnown);
  Assert.IsTrue(mParsed.Operation = TAtlasAvOperation.Read);
  Assert.AreEqual<UInt64>(UInt64($1C), mParsed.Address);
  mParsed := TAtlasAvMessage.Parse('EAccessViolation',
    'Zugriffsverletzung bei Adresse 00451234 in Modul ''Kasse.exe''. Schreiben von Adresse 00000008');
  Assert.IsTrue(mParsed.Operation = TAtlasAvOperation.Write);
  Assert.AreEqual<UInt64>(UInt64(8), mParsed.Address);
  mParsed := TAtlasAvMessage.Parse('EAccessViolation',
    'Zugriffsverletzung bei Adresse 00000000. Ausführung von Adresse 00000000');
  Assert.IsTrue(mParsed.Operation = TAtlasAvOperation.Execute);
  Assert.AreEqual<UInt64>(UInt64(0), mParsed.Address);
end;

procedure TAtlasAccessViolationTests.ParsesEnglishWin64Message;
var
  mParsed: TAtlasAvMessage;
begin
  mParsed := TAtlasAvMessage.Parse('EAccessViolation',
    'Access violation at address 00007FF6A1B21234 in module ''Kasse.exe''. Write of address 0000000000000010');
  Assert.IsTrue(mParsed.AddressKnown);
  Assert.IsTrue(mParsed.Operation = TAtlasAvOperation.Write);
  Assert.AreEqual<UInt64>(UInt64($10), mParsed.Address);
  mParsed := TAtlasAvMessage.Parse('EAccessViolation',
    'Access violation at address 00451234. Read of address FEEEFEEEFEEEFEF2');
  Assert.AreEqual<UInt64>(UInt64($FEEEFEEEFEEEFEF2), mParsed.Address);
end;

procedure TAtlasAccessViolationTests.ExternalExceptionOnlyWithC0000005;
var
  mParsed: TAtlasAvMessage;
begin
  mParsed := TAtlasAvMessage.Parse('EExternalException', 'Externe Exception C0000005');
  Assert.IsTrue(mParsed.IsAccessViolation);
  Assert.IsFalse(mParsed.AddressKnown);
  mParsed := TAtlasAvMessage.Parse('EExternalException', 'Externe Exception C000001D');
  Assert.IsFalse(mParsed.IsAccessViolation);
end;

procedure TAtlasAccessViolationTests.OtherExceptionsAreNoAccessViolation;
begin
  Assert.IsFalse(TAtlasAvMessage.Parse('EConvertError', '''abc'' ist kein gültiger Integerwert').IsAccessViolation);
  Assert.IsTrue(TAtlasAvMessage.Parse('EAccessViolation', '').IsAccessViolation);
  Assert.IsFalse(TAtlasAvMessage.Parse('EAccessViolation', '').AddressKnown);
end;

procedure TAtlasAccessViolationTests.ParsesAddresses;
var
  mValue: UInt64;
  mNumber: Int64;
begin
  Assert.IsTrue(TAtlasAvValues.ParseAddress('nil', mValue));
  Assert.AreEqual<UInt64>(UInt64(0), mValue);
  Assert.IsTrue(TAtlasAvValues.ParseAddress('$02A41230', mValue));
  Assert.AreEqual<UInt64>(UInt64($02A41230), mValue);
  Assert.IsTrue(TAtlasAvValues.ParseAddress('0x7ff6a1b2', mValue));
  Assert.AreEqual<UInt64>(UInt64($7FF6A1B2), mValue);
  Assert.IsTrue(TAtlasAvValues.ParseAddress('($1C)', mValue));
  Assert.AreEqual<UInt64>(UInt64($1C), mValue);
  Assert.IsTrue(TAtlasAvValues.ParseAddress('28', mValue));
  Assert.AreEqual<UInt64>(UInt64(28), mValue);
  Assert.IsTrue(TAtlasAvValues.ParseAddress('18369900232523579118', mValue));
  Assert.AreEqual<UInt64>(UInt64($FEEEFEEEFEEEFEEE), mValue);
  Assert.IsFalse(TAtlasAvValues.ParseAddress('''Text''', mValue));
  Assert.IsFalse(TAtlasAvValues.ParseAddress('', mValue));
  Assert.IsTrue(TAtlasAvValues.ParseInteger(' 7 ', mNumber));
  Assert.AreEqual<Int64>(Int64(7), mNumber);
  Assert.IsTrue(TAtlasAvValues.ParseInteger('-1', mNumber));
  Assert.AreEqual<Int64>(Int64(-1), mNumber);
  Assert.AreEqual('$0000001C', TAtlasAvValues.HexText($1C));
  Assert.AreEqual('$00007FF6A1B21234', TAtlasAvValues.HexText($7FF6A1B21234));
end;

procedure TAtlasAccessViolationTests.RecognisesFreedPatterns;
begin
  Assert.IsTrue(TAtlasAvValues.IsFreedPattern($80808080, 4));
  Assert.IsTrue(TAtlasAvValues.IsFreedPattern($FEEEFEEE, 4));
  Assert.IsFalse(TAtlasAvValues.IsFreedPattern($8080808080808080, 4));
  Assert.IsTrue(TAtlasAvValues.IsFreedPattern($8080808080808080, 8));
  Assert.IsTrue(TAtlasAvValues.IsFreedPattern($80808080, 8));
  Assert.IsFalse(TAtlasAvValues.IsFreedPattern($02A41230, 4));
  Assert.IsTrue(TAtlasAvValues.NearFreedPattern($80808094, 4));
  Assert.IsFalse(TAtlasAvValues.NearFreedPattern($80908080, 4));
  Assert.IsTrue(TAtlasAvValues.NearFreedPattern($FEEEFEEEFEEEFEF2, 8));
end;

procedure TAtlasAccessViolationTests.NilLinkWithConfirmedField;
var
  mAnalysis: TAtlasAvAnalysis;
  mVerdict: TAtlasAvVerdict;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', 'nil');
  Give('NativeInt(@TKunde(nil).FAdresse)', '8');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage(8), 4, False);
  try
    Run(mAnalysis);
    mVerdict := mAnalysis.Verdict;
    Assert.IsTrue(mVerdict.Kind = TAtlasAvVerdictKind.NilLink);
    Assert.IsTrue(mVerdict.HasCulprit);
    Assert.AreEqual('Auftrag.Kunde', mVerdict.Culprit.Expression);
    Assert.AreEqual('FAdresse', mVerdict.Field);
    Assert.AreEqual(8, mVerdict.FieldOffset);
    Assert.IsTrue(mVerdict.FieldExact);
    Assert.IsFalse(mVerdict.VmtAccess);
    Assert.AreEqual(1, mVerdict.Causes);
    Assert.IsTrue(mAnalysis.Checks[0].State = TAtlasAvCheckState.Ok);
    Assert.AreEqual('$02A41230', mAnalysis.Checks[0].Value);
    Assert.IsTrue(mAnalysis.Checks[1].State = TAtlasAvCheckState.NilValue);
    // Die Schätzung zuerst: eine einzige Frage nach dem Versatz, kein Kopf.
    Assert.AreEqual('NativeInt(@TKunde(nil).FAdresse)', FAsked[High(FAsked)]);
    Assert.AreEqual(3, Integer(Length(FAsked)));
    Assert.IsFalse(Asked('NativeInt(@TKunde(nil).FName)'));
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.NilLinkKeepsEstimateWhenDebuggerCannotCompute;
var
  mAnalysis: TAtlasAvAnalysis;
  mVerdict: TAtlasAvVerdict;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', 'nil');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage(8), 4, False);
  try
    Run(mAnalysis);
    mVerdict := mAnalysis.Verdict;
    Assert.IsTrue(mVerdict.Kind = TAtlasAvVerdictKind.NilLink);
    Assert.AreEqual('FAdresse', mVerdict.Field);
    Assert.IsFalse(mVerdict.FieldExact);
    // Nach dem ersten Fehler fragt Atlas nicht weiter.
    Assert.IsFalse(Asked('NativeInt(@TKunde(nil).FName)'));
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.NilLinkWithoutFieldWhenEstimateRefuted;
var
  mAnalysis: TAtlasAvAnalysis;
  mVerdict: TAtlasAvVerdict;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', 'nil');
  Give('NativeInt(@TKunde(nil).FName)', '8');
  Give('NativeInt(@TKunde(nil).FAdresse)', '16');
  Give('NativeInt(@TKunde(nil).FOrt)', '24');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage($C), 4, False);
  try
    Run(mAnalysis);
    mVerdict := mAnalysis.Verdict;
    Assert.IsTrue(mVerdict.Kind = TAtlasAvVerdictKind.NilLink);
    // Geschätzt war FOrt (12), der Debugger sagt 24; kein anderes Feld liegt bei 12.
    Assert.AreEqual('', mVerdict.Field);
    Assert.IsTrue(Asked('NativeInt(@TKunde(nil).FName)'));
    Assert.IsTrue(Asked('NativeInt(@TKunde(nil).FOrt)'));
  finally
    mAnalysis.Free;
  end;
  FAsked := nil;
  // Ohne Schätzung, aber der Debugger findet das Feld.
  Give('NativeInt(@TKunde(nil).FAdresse)', '20');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage(20), 4, False);
  try
    Run(mAnalysis);
    Assert.AreEqual('FAdresse', mAnalysis.Verdict.Field);
    Assert.IsTrue(mAnalysis.Verdict.FieldExact);
    Assert.AreEqual(20, mAnalysis.Verdict.FieldOffset);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.AddressZeroIsVmtAccess;
var
  mAnalysis: TAtlasAvAnalysis;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', 'nil');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage(0), 4, False);
  try
    Run(mAnalysis);
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.NilLink);
    Assert.IsTrue(mAnalysis.Verdict.VmtAccess);
    Assert.AreEqual('', mAnalysis.Verdict.Field);
    Assert.AreEqual(2, Integer(Length(FAsked)));
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.FreedValue;
var
  mAnalysis: TAtlasAvAnalysis;
begin
  Give('Pointer(Auftrag)', '$80808080');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage($80808088), 4, False);
  try
    Run(mAnalysis);
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.Freed);
    Assert.AreEqual('Auftrag', mAnalysis.Verdict.Culprit.Expression);
    Assert.AreEqual<UInt64>(UInt64($80808080), mAnalysis.Verdict.Value);
    Assert.IsTrue(mAnalysis.Checks[1].State = TAtlasAvCheckState.NotReached);
    Assert.IsFalse(Asked('Pointer(Auftrag.Kunde)'));
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.FreedObjectHeader;
var
  mAnalysis: TAtlasAvAnalysis;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', '$02A50000');
  Give('PNativeUInt($02A41230)^', '$00401000');
  Give('PNativeUInt($02A50000)^', '$80808080');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage($02A50008), 4, False);
  try
    Run(mAnalysis);
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.Freed);
    Assert.AreEqual('Auftrag.Kunde', mAnalysis.Verdict.Culprit.Expression);
    Assert.IsTrue(mAnalysis.Checks[0].State = TAtlasAvCheckState.Ok);
    Assert.IsTrue(mAnalysis.Checks[1].State = TAtlasAvCheckState.Freed);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.FreedObjectSecondWordFullDebugMode;
var
  mAnalysis: TAtlasAvAnalysis;
begin
  // FastMM FullDebugMode: VMT-Zeiger auf TFreedObject, dahinter das Füllmuster.
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', '$02A50000');
  Give('PNativeUInt($02A41230)^', '$00401000');
  Give('PNativeUInt($02A41234)^', '$02A60000');
  Give('PNativeUInt($02A50000)^', '$00450000');
  Give('PNativeUInt($02A50004)^', '2155905152');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage($02A50008), 4, False);
  try
    Run(mAnalysis);
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.Freed);
    Assert.AreEqual('Auftrag.Kunde', mAnalysis.Verdict.Culprit.Expression);
    Assert.IsTrue(Asked('PNativeUInt($02A41234)^'), 'zweites Wort auch beim ersten Objekt');
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.InvalidPointer;
var
  mAnalysis: TAtlasAvAnalysis;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', '$0000001C');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage($24), 4, False);
  try
    Run(mAnalysis);
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.Invalid);
    Assert.AreEqual<UInt64>(UInt64($1C), mAnalysis.Verdict.Value);
    Assert.AreEqual('Auftrag.Kunde', mAnalysis.Verdict.Culprit.Expression);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.IndexOutOfRange;
var
  mListe: TAtlasAvLink;
  mAnalysis: TAtlasAvAnalysis;
begin
  mListe := Link('Liste', TAtlasAvLinkKind.DynArray, 'TArray<TKunde>');
  mListe.IndexText := 'I';
  mListe.IndexPlain := True;
  Give('Pointer(Liste)', '$03000010');
  Give('Length(Liste)', '5');
  Give('I', '7');
  mAnalysis := TAtlasAvAnalysis.Create(Chains(TArray<TAtlasAvChain>.Create(Chain('Liste[I].Name',
    TArray<TAtlasAvLink>.Create(mListe, Link('Liste[I]', TAtlasAvLinkKind.ClassRef, 'TKunde'))))),
    AvMessage($03000030), 4, False);
  try
    Run(mAnalysis);
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.OutOfRange);
    Assert.AreEqual<Int64>(Int64(7), mAnalysis.Verdict.Index);
    Assert.AreEqual<Int64>(Int64(5), mAnalysis.Verdict.Length);
    Assert.IsTrue(mAnalysis.Checks[1].State = TAtlasAvCheckState.NotReached);
    Assert.AreEqual('$03000010 · I = 7 / 5', mAnalysis.Checks[0].Value);
  finally
    mAnalysis.Free;
  end;
  // Index im Bereich: kein Fehler am Array, weiter mit dem nächsten Glied.
  FAsked := nil;
  Give('I', '2');
  Give('Pointer(Liste[I])', 'nil');
  mAnalysis := TAtlasAvAnalysis.Create(Chains(TArray<TAtlasAvChain>.Create(Chain('Liste[I].Name',
    TArray<TAtlasAvLink>.Create(mListe, Link('Liste[I]', TAtlasAvLinkKind.ClassRef, 'TKunde'))))),
    AvMessage(4), 4, False);
  try
    Run(mAnalysis);
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.NilLink);
    Assert.AreEqual('Liste[I]', mAnalysis.Verdict.Culprit.Expression);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.GetterStaysUnevaluatedWithoutAllowCalls;
var
  mAnalysis: TAtlasAvAnalysis;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('PNativeUInt($02A41230)^', '$00401000');
  Give('Pointer(Auftrag.Kunde)', 'nil');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(True), AvMessage(8), 4, False);
  try
    Run(mAnalysis);
    Assert.IsTrue(mAnalysis.Checks[1].State = TAtlasAvCheckState.NotEvaluated);
    Assert.IsFalse(Asked('Pointer(Auftrag.Kunde)'));
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.Ambiguous);
    Assert.AreEqual(0, mAnalysis.Verdict.Causes);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.GetterEvaluatedWithAllowCalls;
var
  mAnalysis: TAtlasAvAnalysis;
  mIndex: Integer;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', 'nil');
  Give('NativeInt(@TKunde(nil).FAdresse)', '8');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(True), AvMessage(8), 4, True);
  try
    Run(mAnalysis);
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.NilLink);
    Assert.AreEqual('Auftrag.Kunde', mAnalysis.Verdict.Culprit.Expression);
    for mIndex := 0 to High(FAsked) do
    begin
      Assert.AreEqual(FAsked[mIndex] = 'Pointer(Auftrag.Kunde)', FSideEffects[mIndex], FAsked[mIndex]);
    end;
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.TwoCausesAreAmbiguous;
var
  mAnalysis: TAtlasAvAnalysis;
  mInput: TAtlasAvChains;
begin
  mInput := Chains(TArray<TAtlasAvChain>.Create(
    Chain('A.X', TArray<TAtlasAvLink>.Create(Link('A', TAtlasAvLinkKind.ClassRef, 'TA'))),
    Chain('B.Y', TArray<TAtlasAvLink>.Create(Link('B', TAtlasAvLinkKind.ClassRef, 'TB')))));
  mInput.Statements := 2;
  Give('Pointer(A)', 'nil');
  Give('Pointer(B)', 'nil');
  mAnalysis := TAtlasAvAnalysis.Create(mInput, AvMessage(4), 4, False);
  try
    Run(mAnalysis);
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.Ambiguous);
    Assert.AreEqual(2, mAnalysis.Verdict.Causes);
    Assert.IsFalse(mAnalysis.Verdict.HasCulprit);
    Assert.IsTrue(mAnalysis.Checks[0].State = TAtlasAvCheckState.NilValue);
    Assert.IsTrue(mAnalysis.Checks[1].State = TAtlasAvCheckState.NilValue);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.AddressInFreedPatternIsFreedMemory;
var
  mAnalysis: TAtlasAvAnalysis;
begin
  Give('Pointer(Auftrag)', '$02A41230');
  Give('Pointer(Auftrag.Kunde)', '$02A50000');
  Give('PNativeUInt($02A41230)^', '$00401000');
  Give('PNativeUInt($02A50000)^', '$00402000');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage($80808094), 4, False);
  try
    Run(mAnalysis);
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.FreedMemory);
    Assert.AreEqual<UInt64>(UInt64($80808094), mAnalysis.Verdict.Value);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.PlainExpressionWhenCastFails;
var
  mAnalysis: TAtlasAvAnalysis;
begin
  Give('Auftrag', 'nil');
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage(4), 4, False);
  try
    Run(mAnalysis);
    Assert.IsTrue(Asked('Pointer(Auftrag)'));
    Assert.IsTrue(Asked('Auftrag'));
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.NilLink);
    Assert.AreEqual('Auftrag', mAnalysis.Verdict.Culprit.Expression);
  finally
    mAnalysis.Free;
  end;
end;

procedure TAtlasAccessViolationTests.AbortLeavesRestUnevaluated;
var
  mAnalysis: TAtlasAvAnalysis;
  mRequest: TAtlasAvRequest;
begin
  mAnalysis := TAtlasAvAnalysis.Create(KundenKette(False), AvMessage(8), 4, False);
  try
    Assert.IsTrue(mAnalysis.Next(mRequest));
    Assert.AreEqual('Pointer(Auftrag)', mRequest.Expression);
    mAnalysis.Abort;
    Assert.IsTrue(mAnalysis.Done);
    Assert.IsFalse(mAnalysis.Next(mRequest));
    Assert.IsTrue(mAnalysis.Checks[0].State = TAtlasAvCheckState.NotEvaluated);
    Assert.IsTrue(mAnalysis.Checks[1].State = TAtlasAvCheckState.NotEvaluated);
    Assert.IsTrue(mAnalysis.Verdict.Kind = TAtlasAvVerdictKind.Ambiguous);
  finally
    mAnalysis.Free;
  end;
end;

end.
