unit Atlas.Common.Semantics.FreeRoutineMembers.Tests;

// Mitglied einer Klasse ohne Objekt in einer freien Routine (#2309, wie E2003), über die Regel
// unresolved-identifier: Fall aus Atlas.UI.Debug.BreakpointsFrame (List.OnSelectItem := ListSelectItem in einer
// freien Routine), ohne und mit System im Index, Korrektur mit dem Parameter vom Typ der Klasse, stille Fälle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFreeRoutineMembersTests = class
  public
    /// <summary>Ohne System im Index (Cloud, CI): nur die Methode als Wert, mit Korrektur.</summary>
    [Test]
    procedure MethodAsValueWithoutSystem;
    /// <summary>Mit System und allen Units aus uses: auch Aufrufe und Felder, sicher, ohne zweiten Befund.</summary>
    [Test]
    procedure CallsAndFieldsWithCompleteIndex;
    [Test]
    procedure MethodsLocalsAndUnitNamesAreSilent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry,
  Atlas.Common.Rules.Builtin.Unresolved,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert;

const
  cTypen = 'type'#10'  TMeldung = procedure(ASender: TObject) of object;'#10'  TRahmen = class'#10 +
    '    FOnWahl: TMeldung;'#10'    FFertig: Boolean;'#10'    procedure ListSelect(ASender: TObject);'#10 +
    '    procedure Baue;'#10'  end;'#10;
  cRuempfe = 'procedure TRahmen.ListSelect(ASender: TObject);'#10'begin'#10'end;'#10;

/// <summary>Befunde von unresolved-identifier in einer Unit mit AImplementation hinter den Rümpfen; mit ASystem
/// steht System im Index.</summary>
function Findings(const AImplementation: string; ASystem: Boolean): TArray<TRuleFinding>;
var
  mRegistry: TRuleRegistry;
  mRule, mIdentifier: IRule;
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  if ASystem then
  begin
    mIndex.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
      '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  end;
  mRegistry := TRuleRegistry.Create;
  try
    RegisterUnresolvedRules(mRegistry);
    mIdentifier := nil;
    for mRule in mRegistry.Rules do
    begin
      if mRule.Descriptor.Id = 'unresolved-identifier' then
      begin
        mIdentifier := mRule;
      end;
    end;
    Result := TRuleAssert.IndexFindings(mIdentifier, 'unit Fall;'#10'interface'#10 + cTypen + 'implementation'#10 +
      cRuempfe + AImplementation + 'end.', mIndex, '', 'Fall.pas');
  finally
    mRegistry.Free;
  end;
end;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    if Result <> '' then
    begin
      Result := Result + ' | ';
    end;
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message;
  end;
end;

procedure TFreeRoutineMembersTests.MethodAsValueWithoutSystem;
const
  cFall = 'procedure CreateList(AFrame: TRahmen);'#10'begin'#10'  AFrame.FOnWahl := ListSelect;'#10 +
    '  ListSelect(nil);'#10'  FFertig := True;'#10'end;'#10;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(cFall, False);
  Assert.AreEqual('16: "ListSelect" ist nicht deklariert: ListSelect ist ein Mitglied von TRahmen, die freie ' +
    'Routine CreateList hat aber kein Self (wie E2003). Gemeint ist wohl AFrame.ListSelect.', Messages(mFound));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFound[0].Confidence));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('AFrame.ListSelect einsetzen', mFound[0].Fixes[0].Title);
  Assert.AreEqual('AFrame.', mFound[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(20, mFound[0].Fixes[0].Edits[0].Range.StartPos.Character);
end;

procedure TFreeRoutineMembersTests.CallsAndFieldsWithCompleteIndex;
const
  cFall = 'procedure Ohne;'#10'begin'#10'  ListSelect(nil);'#10'  FFertig := True;'#10'end;'#10;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(cFall, True);
  Assert.AreEqual('16: "ListSelect" ist nicht deklariert: ListSelect ist ein Mitglied von TRahmen, die freie ' +
    'Routine Ohne hat aber kein Self (wie E2003). | 17: "FFertig" ist nicht deklariert: FFertig ist ein Mitglied ' +
    'von TRahmen, die freie Routine Ohne hat aber kein Self (wie E2003).', Messages(mFound));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFound[0].Confidence));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
end;

procedure TFreeRoutineMembersTests.MethodsLocalsAndUnitNamesAreSilent;
const
  cFall = 'procedure FFertig;'#10'begin'#10'end;'#10 +
    'procedure TRahmen.Baue;'#10'  procedure Innen;'#10'  begin'#10'    FOnWahl := ListSelect;'#10'  end;'#10 +
    'begin'#10'  FOnWahl := ListSelect;'#10'  Innen;'#10'end;'#10 +
    'procedure Frei(AFrame: TRahmen; ListSelect: TMeldung);'#10'var'#10'  FOnWahl: TMeldung;'#10'begin'#10 +
    '  FOnWahl := ListSelect;'#10'  FFertig;'#10'  with AFrame do'#10'    FOnWahl := Baue;'#10 +
    '  AFrame.FOnWahl := AFrame.ListSelect;'#10'end;'#10;
begin
  Assert.AreEqual('', Messages(Findings(cFall, True)));
  Assert.AreEqual('', Messages(Findings(cFall, False)));
end;

initialization
  TDUnitX.RegisterTestFixture(TFreeRoutineMembersTests);

end.
