unit Atlas.Common.Rules.Builtin.DelphiSemantics.Tests;

// Tests der Regeln aus #2309, Stellen, an denen Delphi zur Laufzeit anders arbeitet als FPC: Result als Variable
// des Aufrufers, TryGetValue setzt den out-Wert immer, Records teilen dynamische Arrays, ExtractFileName trennt unter
// Windows nur an '\', gewollter Hash-Überlauf außerhalb von {$Q-}. Die Fälle stammen aus dem Delphi-Bau von
// main-merging (TestExplorer.Visible, ProfileTools, StatusBar, LeakSetup, CrashSkip.Checksum).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDelphiSemanticsTests = class
  public
    [Test]
    procedure ResultSizedThenRead;
    [Test]
    procedure ResultReadBeforeSet;
    [Test]
    procedure ResultSilentCases;
    [Test]
    procedure TryGetValueOverwritesPreset;
    [Test]
    procedure TryGetValueSilentCases;
    [Test]
    procedure RecordCopySharesArray;
    [Test]
    procedure RecordCopySilentCases;
    [Test]
    procedure ExtractFileWithSlash;
    [Test]
    procedure ExtractFileSilentCases;
    [Test]
    procedure HashOverflowOutsideQMinus;
    [Test]
    procedure HashOverflowSilentCases;
    [Test]
    procedure RulesAreRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.DelphiSemantics,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message + '|';
  end;
end;

function Lines(const ALines: array of string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
  begin
    Result := Result + mLine + #10;
  end;
end;

/// <summary>Unit U mit den Zeilen ABody im implementation-Teil.</summary>
function UnitWith(const ABody: array of string): string;
begin
  Result := Lines(['unit U;', 'interface', 'implementation']) + Lines(ABody) + 'end.';
end;

/// <summary>Index mit Unit Werk.Ansicht: TExtra (Record), TAnsicht (Record mit dynamischem und statischem Array)
/// und TKlasse (Klasse mit dynamischem Array).</summary>
function AnsichtIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(Lines(['unit Werk.Ansicht;', 'interface', 'type',
    '  TExtra = record', '    State: Integer;', '  end;', '  TAnsicht = record', '    Extras: TArray<TExtra>;',
    '    Fest: array[0..2] of Integer;', '    Name: string;', '  end;', '  TKlasse = class',
    '    Extras: TArray<TExtra>;', '  end;', 'implementation']) + 'end.', 'C:\P\Werk.Ansicht.pas', nil));
end;

function SharedFindings(const ABody: array of string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.IndexFindings(TRecordArraySharedRule.Create, Lines(['unit U;', 'interface', 'uses',
    '  Werk.Ansicht;', 'implementation']) + Lines(ABody) + 'end.', AnsichtIndex, '', 'U.pas');
end;

{ TDelphiSemanticsTests }

procedure TDelphiSemanticsTests.ResultSizedThenRead;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  // TAtlasTestExplorer.Visible: SetLength auf gleiche Länge behält die Werte eines früheren Aufrufs.
  mSource := UnitWith(['function Visible(const A: TArray<Integer>): TArray<Boolean>;', 'var', '  I: Integer;',
    'begin', '  SetLength(Result, Length(A));', '  for I := 0 to High(A) do', '  begin', '    if A[I] > 0 then',
    '      Result[I] := True;', '    if Result[I] then', '      Result[0] := True;', '  end;', 'end;']);
  mFound := TRuleAssert.Findings(TManagedResultReadRule.Create, mSource);
  Assert.AreEqual('7: SetLength(Result, ...) ohne vorheriges Result := nil: Delphi übergibt Result als Variable des ' +
    'Aufrufers, SetLength behält deren alte Werte, und Result[I] liest sie (FPC beginnt leer). Erst Result := ' +
    'nil.|', Messages(mFound));
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(StringReplace(mSource, '  SetLength(Result', '  Result := nil;'#10'  SetLength(Result', []), mFixed);
  TRuleAssert.Silent(TManagedResultReadRule.Create, mFixed);
  // Zählen in Result nach SetLength und Anhängen an die Länge des Aufrufers.
  TRuleAssert.Reports(TManagedResultReadRule.Create, UnitWith(['function Zaehle: TArray<Integer>;', 'begin',
    '  SetLength(Result, 3);', '  Inc(Result[1]);', 'end;', 'function Mehr: TArray<Integer>;', 'begin',
    '  SetLength(Result, Length(Result) + 1);', 'end;']), 2);
end;

procedure TDelphiSemanticsTests.ResultReadBeforeSet;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TManagedResultReadRule.Create, UnitWith(['function Namen: TArray<string>;',
    'begin', '  Result := Result + [''a''];', 'end;', 'function Text: string;', 'begin', '  Result := Result + ''x'';',
    'end;', 'function Anzahl: TArray<Integer>;', 'begin', '  if Length(Result) = 0 then', '    Result := [1];',
    'end;']));
  Assert.AreEqual(3, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('5: Result := Result + [''a''] liest Result, bevor die Funktion es setzt: Delphi übergibt Result ' +
    'als Variable des Aufrufers, der Wert stammt von dort (FPC beginnt leer). Erst Result := nil.|',
    Messages(TArray<TRuleFinding>.Create(mFound[0])));
  Assert.AreEqual(9, mFound[1].Range.StartPos.Line);
  Assert.IsTrue(Pos('Erst Result := ''''.', mFound[1].Message) > 0, mFound[1].Message);
end;

procedure TDelphiSemanticsTests.ResultSilentCases;
begin
  // Erst geleert, alle Elemente geschrieben, Länge nach SetLength, anderer Ergebnistyp, Result als Argument einer
  // Routine (var- oder out-Parameter), anonyme Methode mit eigenem Result.
  TRuleAssert.Silent(TManagedResultReadRule.Create, UnitWith(['function A: TArray<Boolean>;', 'begin',
    '  Result := nil;', '  SetLength(Result, 2);', '  if Result[0] then', '    Exit;', 'end;',
    'function B(N: Integer): TArray<Integer>;', 'var', '  I: Integer;', 'begin', '  SetLength(Result, N);',
    '  for I := 0 to High(Result) do', '    Result[I] := I;', 'end;', 'function C: Integer;', 'begin',
    '  Result := Result + 1;', 'end;', 'function D: TArray<string>;', 'begin', '  Fuelle(Result);',
    '  Result := Result + [''x''];', 'end;', 'function E: string;', 'var', '  F: TFunc<string>;', 'begin',
    '  F := function: string', '    begin', '      Result := '''';', '    end;', '  Result := F() + ''y'';', 'end;']));
  // Geschriebene Elemente lesen, Felder und Teil-Arrays schreiben, Move.
  TRuleAssert.Silent(TManagedResultReadRule.Create, UnitWith(['function G(const A: TArray<string>): TArray<string>;',
    'var', '  I: Integer;', 'begin', '  SetLength(Result, Length(A));', '  for I := 0 to High(A) do', '  begin',
    '    Result[I] := A[I];', '    if SameText(Result[0], Result[I]) then', '      Exit;', '  end;', 'end;',
    'function H: TArray<TZeile>;', 'begin', '  SetLength(Result, 2);', '  Result[0].Marks[3] := 1;',
    '  if Result[0].Marks[3] = 1 then', '    Exit;', 'end;', 'function M(const P: Pointer): TBytes;', 'begin',
    '  SetLength(Result, 4);', '  Move(P^, Result[0], 4);', '  if Result[0] = 0 then', '    Exit;', 'end;']));
end;

procedure TDelphiSemanticsTests.TryGetValueOverwritesPreset;
var
  mFound: TArray<TRuleFinding>;
begin
  // ProfileTools: Vorgabe 30, TryGetValue setzt ohne Schlüssel 0.
  mFound := TRuleAssert.Findings(TTryGetValueOutDefaultRule.Create, UnitWith([
    'function Anfrage(const A: TJSONObject): TAnfrage;', 'begin', '  Result := Default(TAnfrage);',
    '  Result.Top := 30;', '  A.TryGetValue<Integer>(''top'', Result.Top);', 'end;', 'procedure Lies(D: TWerte);',
    'var', '  W: Integer;', 'begin', '  W := 5;', '  D.TryGetValue(''k'', W);', '  Zeige(W);', 'end;']));
  Assert.AreEqual('7: Result.Top bekam in Zeile 7 den Wert 30, TryGetValue verwirft das Ergebnis: Delphi setzt ' +
    'das out-Argument auch ohne Schlüssel auf den Vorgabewert, die Vorbelegung geht verloren (FPC lässt sie ' +
    'stehen). In eine eigene Variable lesen und nur bei True übernehmen.|', Messages(TArray<TRuleFinding>.Create(mFound[0])));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(14, mFound[1].Range.StartPos.Line);
end;

procedure TDelphiSemanticsTests.TryGetValueSilentCases;
begin
  // Vorbelegung mit dem Vorgabewert, Ergebnis ausgewertet, keine Vorbelegung, Vorbelegung nach dem Aufruf.
  TRuleAssert.Silent(TTryGetValueOutDefaultRule.Create, UnitWith(['procedure A(D: TWerte);', 'var',
    '  W: Integer;', '  S: string;', '  L: TArray<Integer>;', '  R: TRec;', 'begin', '  W := 0;', '  S := '''';',
    '  L := nil;', '  R := Default(TRec);', '  D.TryGetValue(''a'', W);', '  D.TryGetValue(''b'', S);',
    '  D.TryGetValue(''c'', L);', '  D.TryGetValue(''d'', R);', '  W := 7;', '  if not D.TryGetValue(''e'', W) then',
    '    W := 7;', '  D.TryGetValue(''f'', mNeu);', 'end;']));
end;

procedure TDelphiSemanticsTests.RecordCopySharesArray;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  // StatusBar: Die Kopie und das Original teilen Extras; die Änderung in place trifft beide.
  mFound := SharedFindings(['procedure Zeige(const AAnsicht: TAnsicht);', 'var', '  mKopie: TAnsicht;', 'begin',
    '  mKopie := AAnsicht;', '  mKopie.Extras[0].State := 1;', 'end;']);
  Assert.AreEqual('10: mKopie.Extras ist seit Zeile 10 (mKopie := AAnsicht) dasselbe Array wie in AAnsicht: ' +
    'Dynamische Arrays sind in Delphi Referenzen ohne Copy-on-Write, das Schreiben ändert auch AAnsicht. Vorher ' +
    'mKopie.Extras := Copy(mKopie.Extras).|', Messages(mFound));
  mSource := Lines(['unit U;', 'interface', 'uses', '  Werk.Ansicht;', 'implementation',
    'procedure Zeige(const AAnsicht: TAnsicht);', 'var', '  mKopie: TAnsicht;', 'begin', '  mKopie := AAnsicht;',
    '  mKopie.Extras[0].State := 1;', 'end;']) + 'end.';
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  Assert.IsTrue(Pos('  mKopie.Extras := Copy(mKopie.Extras);'#10'  mKopie.Extras[0].State := 1;', mFixed) > 0, mFixed);
  Assert.AreEqual('', Messages(TRuleAssert.IndexFindings(TRecordArraySharedRule.Create, mFixed, AnsichtIndex, '',
    'U.pas')));
  // Auch das Original ändert die Kopie; ein Element direkt (ohne Feld dahinter).
  Assert.AreEqual(1, Integer(Length(SharedFindings(['procedure Merke(var A: TAnsicht; var B: TAnsicht);', 'begin',
    '  B := A;', '  A.Extras[1] := B.Extras[0];', 'end;']))));
end;

procedure TDelphiSemanticsTests.RecordCopySilentCases;
begin
  // Eigenes Array vor dem Schreiben (Copy, SetLength, neue Zuweisung), statisches Array, String-Feld, Klasse,
  // Record neu zugewiesen.
  Assert.AreEqual('', Messages(SharedFindings(['procedure A(const X: TAnsicht; O: TKlasse; P: TKlasse);', 'var',
    '  B, C, D, E: TAnsicht;', 'begin', '  B := X;', '  B.Extras := Copy(B.Extras);', '  B.Extras[0].State := 1;',
    '  C := X;', '  SetLength(C.Extras, 2);', '  C.Extras[0].State := 1;', '  D := X;', '  D.Fest[0] := 1;',
    '  D.Name := ''n'';', '  O := P;', '  O.Extras[0].State := 1;', '  E := X;', '  E := Default(TAnsicht);',
    '  E.Extras[0].State := 1;', 'end;'])));
  // Funktion ohne Klammern liefert einen neuen Record.
  Assert.AreEqual('', Messages(SharedFindings(['function Probe: TAnsicht;', 'begin', '  Result := Default(TAnsicht);',
    'end;', 'procedure B;', 'var', '  F: TAnsicht;', 'begin', '  F := Probe;', '  F.Extras[0].State := 1;', 'end;'])));
end;

procedure TDelphiSemanticsTests.ExtractFileWithSlash;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  // LeakSetup: Windows-Pfad nach '/' umgestellt, dann ExtractFileName.
  mSource := UnitWith(['function Name(const A: string): string;', 'var', '  P: string;', 'begin',
    '  Result := ExtractFileName(StringReplace(A, ''\'', ''/'', [rfReplaceAll]));', '  P := A + ''/sub'';',
    '  Result := ExtractFilePath(P) + ExtractFileDir(''a/b.pas'');', 'end;']);
  mFound := TRuleAssert.Findings(TExtractFileSlashRule.Create, mSource);
  Assert.AreEqual(3, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('7: ExtractFileName bekommt einen Pfad mit ''/'': Unter Windows trennt Delphi nur an ''\'' ' +
    '(PathDelim), unter Linux an ''/''. Trenner vorher auf PathDelim angleichen.|', Messages(TArray<TRuleFinding>.Create(mFound[0])));
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  Assert.IsTrue(Pos('StringReplace(A, ''\'', PathDelim, [rfReplaceAll])', mFixed) > 0, mFixed);
  Assert.AreEqual(0, Integer(Length(mFound[1].Fixes)));
end;

procedure TDelphiSemanticsTests.ExtractFileSilentCases;
begin
  TRuleAssert.Silent(TExtractFileSlashRule.Create, UnitWith(['function Name(const A: string): string;', 'var',
    '  P: string;', 'begin', '  Result := ExtractFileName(StringReplace(A, ''/'', PathDelim, [rfReplaceAll]));',
    '  P := A + PathDelim + ''x'';', '  Result := ExtractFilePath(P) + ExtractFileDir(''C:\a\b.pas'');',
    '  P := ''a/b'';', '  P := A;', '  Result := ExtractFileExt(P);', '  if PathDelim = ''/'' then',
    '    P := ''/home''', '  else', '    P := ''C:\'';', '  Result := ExtractFilePath(P);', 'end;']));
end;

procedure TDelphiSemanticsTests.HashOverflowOutsideQMinus;
var
  mFound: TArray<TRuleFinding>;
begin
  // CrashSkip.Checksum: Die {$Q-}-Klammer stand um die Routine davor.
  mFound := TRuleAssert.Findings(THashOverflowCheckedRule.Create, UnitWith([
    '{$IFOPT Q+}{$DEFINE UEBERLAUF}{$Q-}{$ENDIF}', 'function IndexOf: Integer;', 'begin', '  Result := 1;', 'end;',
    '{$IFDEF UEBERLAUF}{$Q+}{$UNDEF UEBERLAUF}{$ENDIF}', 'function Checksum(const A: string): UInt64;', 'var',
    '  C: Char;', 'begin', '  Result := UInt64($CBF29CE484222325);', '  for C in A do',
    '    Result := (Result xor Ord(C)) * UInt64($00000100000001B3);', 'end;', 'function Hash(H: Cardinal): Cardinal;',
    'const', '  cPrime = 16777619;', 'begin', '  Result := Cardinal((H xor 1) * cPrime);', 'end;']));
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(15, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(1, Pos('(Result xor Ord(C)) * UInt64($00000100000001B3) läuft gewollt über', mFound[0].Message),
    mFound[0].Message);
  Assert.AreEqual(21, mFound[1].Range.StartPos.Line);
end;

procedure TDelphiSemanticsTests.HashOverflowSilentCases;
begin
  // Richtig geklammert, 32-Bit-Produkt in 64 Bit, Überlaufprüfung für die ganze Datei aus, andere Zahl.
  TRuleAssert.Silent(THashOverflowCheckedRule.Create, UnitWith(['{$IFOPT Q+}{$DEFINE UEBERLAUF}{$Q-}{$ENDIF}',
    'function Checksum(H: UInt64): UInt64;', 'begin', '  Result := H * UInt64($00000100000001B3);', 'end;',
    '{$IFDEF UEBERLAUF}{$Q+}{$UNDEF UEBERLAUF}{$ENDIF}', 'function Hash(H: Cardinal): Cardinal;', 'begin',
    '  Result := Cardinal(UInt64(H xor 1) * 16777619);', 'end;', 'function Mal(H: Integer): Integer;', 'begin',
    '  Result := H * 16777618;', 'end;', '{$OVERFLOWCHECKS OFF}', 'function Spaet(H: Cardinal): Cardinal;', 'begin',
    '  Result := H * 16777619;', 'end;']));
end;

procedure TDelphiSemanticsTests.RulesAreRegistered;
var
  mRule: IRule;
  mIds: string;
begin
  mIds := '';
  for mRule in BuiltinRules do
  begin
    if (mRule.Descriptor.Id = cManagedResultReadRuleId) or (mRule.Descriptor.Id = cTryGetValueOutDefaultRuleId) or
      (mRule.Descriptor.Id = cRecordArraySharedRuleId) or (mRule.Descriptor.Id = cExtractFileSlashRuleId) or
      (mRule.Descriptor.Id = cHashOverflowCheckedRuleId) then
    begin
      mIds := mIds + mRule.Descriptor.Id + ' ';
    end;
  end;
  Assert.AreEqual('managed-result-read-before-set trygetvalue-out-default record-array-shared ' +
    'extractfile-forward-slash hash-overflow-checked ', mIds);
end;

initialization
  TDUnitX.RegisterTestFixture(TDelphiSemanticsTests);

end.
