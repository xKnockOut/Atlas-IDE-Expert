unit Atlas.Common.Rules.Builtin.Flow.HandleLeak.Tests;

// Tests der Teilunit handle-leak: Leck, Schließen, Weitergabe, Prüfung des Öffnens (auch über einen Merker mit
// zweitem Versuch und über eine wiederholte Bedingung), Korrektur.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowHandleLeakTests = class
  public
    [Test]
    procedure NeverClosedIsReported;
    [Test]
    procedure ClosedIsSilent;
    [Test]
    procedure PassedOnIsSilent;
    [Test]
    procedure FailedOpenBranchIsSilent;
    [Test]
    procedure FixAppendsClose;
    [Test]
    procedure FlagGuardIsSilent;
    [Test]
    procedure WrongOrReassignedFlagIsReported;
    [Test]
    procedure FlagFromOpeningCallIsSilent;
    [Test]
    procedure WrongBranchOfOpeningFlagIsReported;
    [Test]
    procedure SecondAttemptOnFailureIsSilent;
    [Test]
    procedure UnguardedSecondAssignmentIsReported;
    [Test]
    procedure RepeatedConditionIsSilent;
    [Test]
    procedure ChangedConditionIsReported;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow.HandleLeak,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit "procedure P(const Name: string)", der Variablen H: THandle und dem Rumpf ABody.</summary>
function Routine(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Merke(A: THandle);'#10'begin'#10'end;'#10 +
    'procedure P(const Name: string);'#10'var'#10'  H: THandle;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

{ TFlowHandleLeakTests }

procedure TFlowHandleLeakTests.NeverClosedIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(THandleLeakRule.Create, Routine('  H := OpenProcess(0, False, 1);'#10 +
    '  WaitForSingleObject(H, 0);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cHandleLeakRuleId, mFindings[0].RuleId);
  Assert.AreEqual('H wird nie mit CloseHandle geschlossen (Handle-Leck).', mFindings[0].Message);
end;

procedure TFlowHandleLeakTests.ClosedIsSilent;
begin
  TRuleAssert.Silent(THandleLeakRule.Create, Routine('  H := OpenProcess(0, False, 1);'#10'  try'#10 +
    '    WaitForSingleObject(H, 0);'#10'  finally'#10'    CloseHandle(H);'#10'  end;'));
end;

procedure TFlowHandleLeakTests.PassedOnIsSilent;
begin
  TRuleAssert.Silent(THandleLeakRule.Create, Routine('  H := OpenProcess(0, False, 1);'#10'  Merke(H);'));
end;

procedure TFlowHandleLeakTests.FailedOpenBranchIsSilent;
begin
  TRuleAssert.Silent(THandleLeakRule.Create, Routine('  H := OpenProcess(0, False, 1);'#10 +
    '  if H = 0 then'#10'    Exit;'#10'  CloseHandle(H);'));
end;

procedure TFlowHandleLeakTests.FixAppendsClose;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(THandleLeakRule.Create, Routine('  H := OpenProcess(0, False, 1);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual(';'#10'  CloseHandle(H)', mFindings[0].Fixes[0].Edits[0].NewText);
end;

/// <summary>Funktion F: Boolean mit H: THandle und Ok: Boolean und dem Rumpf ABody.</summary>
function FlagRoutine(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'function F: Boolean;'#10'var'#10'  H: THandle;'#10 +
    '  Ok: Boolean;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TFlowHandleLeakTests.FlagGuardIsSilent;
begin
  // Result := H <> 0; if Result then CloseHandle(H) (#1519, AtlasUpdate).
  TRuleAssert.Silent(THandleLeakRule.Create, FlagRoutine('  H := OpenProcess(0, False, 1);'#10 +
    '  Result := H <> 0;'#10'  if Result then'#10'  begin'#10'    CloseHandle(H);'#10'  end;'));
  TRuleAssert.Silent(THandleLeakRule.Create, FlagRoutine('  H := CreateFile(nil, 0, 0, nil, 0, 0, 0);'#10 +
    '  Ok := H = INVALID_HANDLE_VALUE;'#10'  if not (Ok) then'#10'    CloseHandle(H);'#10'  Result := not Ok;'));
  // Weitere Zuweisung im then-Zweig (TUpdateWindowsProcesses.IsRunning).
  TRuleAssert.Silent(THandleLeakRule.Create, FlagRoutine('  H := OpenProcess(0, False, 1);'#10 +
    '  Result := H <> 0;'#10'  if Result then'#10'  begin'#10'    Result := WaitForSingleObject(H, 0) = 0;'#10 +
    '    CloseHandle(H);'#10'  end;'));
end;

procedure TFlowHandleLeakTests.WrongOrReassignedFlagIsReported;
begin
  // Falscher Zweig.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create,
    FlagRoutine('  H := OpenProcess(0, False, 1);'#10'  Result := H <> 0;'#10'  if not Result then'#10 +
    '    CloseHandle(H);')))));
  // Zweimal zugewiesen: der Merker sagt nichts mehr über das Handle.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create,
    FlagRoutine('  H := OpenProcess(0, False, 1);'#10'  Ok := H <> 0;'#10'  Ok := True;'#10'  if Ok then'#10 +
    '    CloseHandle(H);'#10'  Result := Ok;')))));
  // Vor dem Öffnen zugewiesen.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create,
    FlagRoutine('  Ok := H <> 0;'#10'  H := OpenProcess(0, False, 1);'#10'  if Ok then'#10 +
    '    CloseHandle(H);'#10'  Result := Ok;')))));
end;

procedure TFlowHandleLeakTests.FlagFromOpeningCallIsSilent;
begin
  // Der Merker kommt aus dem Aufruf, der öffnet: Im Zweig ohne Erfolg ist nichts offen.
  TRuleAssert.Silent(THandleLeakRule.Create, FlagRoutine('  Result := OpenProcessToken(0, 8, H);'#10 +
    '  if not Result then'#10'  begin'#10'    Exit;'#10'  end;'#10'  CloseHandle(H);'));
  TRuleAssert.Silent(THandleLeakRule.Create, FlagRoutine('  Ok := RegOpenKeyEx(0, nil, 0, 0, H) = ERROR_SUCCESS;'#10 +
    '  if Ok then'#10'  begin'#10'    RegCloseKey(H);'#10'  end;'#10'  Result := Ok;'));
  TRuleAssert.Silent(THandleLeakRule.Create, FlagRoutine('  Result := OpenProcessToken(0, 8, H);'#10 +
    '  if Result then'#10'  begin'#10'    try'#10'      Result := H <> 0;'#10'    finally'#10 +
    '      CloseHandle(H);'#10'    end;'#10'  end;'));
end;

procedure TFlowHandleLeakTests.WrongBranchOfOpeningFlagIsReported;
begin
  // Geschlossen nur, wenn das Öffnen misslang: Der Erfolgszweig bleibt offen.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create,
    FlagRoutine('  Result := OpenProcessToken(0, 8, H);'#10'  if not Result then'#10'  begin'#10 +
    '    CloseHandle(H);'#10'  end;')))));
end;

procedure TFlowHandleLeakTests.SecondAttemptOnFailureIsSilent;
begin
  // Zweiter Versuch nur, wenn der erste misslang: Der Merker sagt weiter, ob H offen ist (JclSecurity).
  TRuleAssert.Silent(THandleLeakRule.Create, FlagRoutine('  Ok := OpenThreadToken(0, 8, True, H);'#10 +
    '  if (not Ok) and (GetLastError = 1008) then'#10'    Ok := OpenProcessToken(0, 8, H);'#10'  if Ok then'#10 +
    '    CloseHandle(H);'#10'  Result := Ok;'));
end;

procedure TFlowHandleLeakTests.UnguardedSecondAssignmentIsReported;
begin
  // Die zweite Zuweisung hängt nicht am Misserfolg: Der Merker sagt nichts mehr über H.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create,
    FlagRoutine('  Ok := OpenThreadToken(0, 8, True, H);'#10'  if GetLastError = 5 then'#10'    Ok := False;'#10 +
    '  if Ok then'#10'    CloseHandle(H);'#10'  Result := Ok;')))));
end;

procedure TFlowHandleLeakTests.RepeatedConditionIsSilent;
begin
  // Geöffnet und geschlossen unter derselben, dazwischen unveränderten Bedingung (IdGlobalProtocols).
  TRuleAssert.Silent(THandleLeakRule.Create, FlagRoutine('  if IstNT = 2 then'#10'  begin'#10 +
    '    if not OpenProcessToken(0, 8, H) then'#10'      Exit;'#10'  end;'#10'  Result := True;'#10 +
    '  if IstNT  =  2 then'#10'    CloseHandle(H);'));
  // Geöffnet im else-Zweig, geschlossen im else-Zweig derselben Bedingung.
  TRuleAssert.Silent(THandleLeakRule.Create, FlagRoutine('  if IstNT then'#10'    Ok := False'#10'  else'#10 +
    '    H := OpenProcess(0, False, 1);'#10'  Result := True;'#10'  if IstNT then'#10'    Ok := True'#10 +
    '  else'#10'    CloseHandle(H);'));
end;

procedure TFlowHandleLeakTests.ChangedConditionIsReported;
begin
  // Die Bedingung ändert sich dazwischen bzw. enthält einen Aufruf: Der zweite Zweig kann ein anderer sein.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create,
    FlagRoutine('  if IstNT then'#10'    H := OpenProcess(0, False, 1);'#10'  IstNT := False;'#10 +
    '  if IstNT then'#10'    CloseHandle(H);'#10'  Result := True;')))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create,
    FlagRoutine('  if IstNT() then'#10'    H := OpenProcess(0, False, 1);'#10'  Result := True;'#10 +
    '  if IstNT() then'#10'    CloseHandle(H);')))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowHandleLeakTests);

end.
