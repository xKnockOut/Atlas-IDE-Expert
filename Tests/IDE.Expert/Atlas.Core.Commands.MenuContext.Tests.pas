unit Atlas.Core.Commands.MenuContext.Tests;

// Tests der Regeln für das Kontextmenü Atlas im Editor (#2102): Testunit und
// Regionen erkennen, Bedingungen nur mit bekannter Lage und eingeschalteter
// Einstellung, Zahl am Namen, Trennlinien nur zwischen sichtbaren Einträgen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasMenuContextRulesTests = class
  public
    [Test]
    procedure RecognizesTestUnits;
    [Test]
    procedure RecognizesRegions;
    [Test]
    procedure ReadFillsContext;
    /// <summary>Ohne Lage, mit abgeschalteter Einstellung oder ohne Bedingung immer sichtbar.</summary>
    [Test]
    procedure AppliesOnlyWithKnownContextAndSetting;
    [Test]
    procedure CountedCaption;
    /// <summary>Keine Linie am Anfang, am Ende oder doppelt; Befehle behalten ihre Sichtbarkeit.</summary>
    [Test]
    procedure SeparatorsOnlyBetweenVisibleEntries;
  end;

implementation

uses
  Atlas.Core.Modules.Contract,
  Atlas.Core.Commands.MenuContext;

/// <summary>Bedingung „Debug-Sitzung“ für die Tests.</summary>
function WhileDebugging(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := AContext.Debugging;
end;

/// <summary>Sichtbarkeit als Text: x = sichtbar, - = aus.</summary>
function Shape(const AVisible: TArray<Boolean>): string;
var
  mVisible: Boolean;
begin
  Result := '';
  for mVisible in AVisible do
  begin
    Result := Result + 'x';
    if not mVisible then
    begin
      Result[Length(Result)] := '-';
    end;
  end;
end;

{ TAtlasMenuContextRulesTests }

procedure TAtlasMenuContextRulesTests.RecognizesTestUnits;
begin
  Assert.IsTrue(TAtlasMenuContextRules.IsTestUnit('unit A.Tests;'#13#10'uses'#13#10'  DUnitX.TestFramework;'));
  Assert.IsTrue(TAtlasMenuContextRules.IsTestUnit('type'#13#10'  [testfixture]'#13#10'  TA = class'));
  Assert.IsFalse(TAtlasMenuContextRules.IsTestUnit('unit A;'#13#10'uses System.SysUtils;'));
end;

procedure TAtlasMenuContextRulesTests.RecognizesRegions;
begin
  Assert.IsTrue(TAtlasMenuContextRules.HasRegions('{$region ''Hilfen''}'#13#10'{$ENDREGION}'));
  Assert.IsFalse(TAtlasMenuContextRules.HasRegions('{$IFDEF DEBUG}{$ENDIF}'));
end;

procedure TAtlasMenuContextRulesTests.ReadFillsContext;
var
  mContext: TAtlasMenuContext;
begin
  mContext := TAtlasMenuContextRules.Read('C:\P\A.pas', 'uses DUnitX.TestFramework;', True, False, 3);
  Assert.AreEqual('C:\P\A.pas', mContext.FileName);
  Assert.IsTrue(mContext.TestUnit);
  Assert.IsFalse(mContext.HasRegions);
  Assert.IsTrue(mContext.HasForm);
  Assert.IsFalse(mContext.Debugging);
  Assert.AreEqual(3, mContext.ProblemCount);
  mContext.FileName := '';
end;

procedure TAtlasMenuContextRulesTests.AppliesOnlyWithKnownContextAndSetting;
var
  mContext: TAtlasMenuContext;
begin
  mContext := Default(TAtlasMenuContext);
  Assert.IsFalse(TAtlasMenuContextRules.Applies(True, True, WhileDebugging, mContext), 'nicht beim Debuggen');
  Assert.IsTrue(TAtlasMenuContextRules.Applies(False, True, WhileDebugging, mContext), 'Lage unbekannt');
  Assert.IsTrue(TAtlasMenuContextRules.Applies(True, False, WhileDebugging, mContext), 'Einstellung aus');
  Assert.IsTrue(TAtlasMenuContextRules.Applies(True, True, nil, mContext), 'ohne Bedingung');
  mContext.Debugging := True;
  Assert.IsTrue(TAtlasMenuContextRules.Applies(True, True, WhileDebugging, mContext), 'beim Debuggen');
end;

procedure TAtlasMenuContextRulesTests.CountedCaption;
begin
  Assert.AreEqual('Befunde (3)', TAtlasMenuContextRules.CountedCaption('Befunde', 3));
  Assert.AreEqual('Findings', TAtlasMenuContextRules.CountedCaption('Findings', 0));
end;

procedure TAtlasMenuContextRulesTests.SeparatorsOnlyBetweenVisibleEntries;
var
  mIsLine, mVisible: TArray<Boolean>;
begin
  // Linie, Befehl, Linie, Linie, ausgeblendeter Befehl, Befehl, Linie
  mIsLine := TArray<Boolean>.Create(True, False, True, True, False, False, True);
  mVisible := TArray<Boolean>.Create(True, True, True, True, False, True, True);
  Assert.AreEqual('-x-x-x-', Shape(TAtlasMenuContextRules.Separators(mIsLine, mVisible)));
  // Alles zwischen zwei Linien ausgeblendet: nur die zweite Linie bleibt.
  mIsLine := TArray<Boolean>.Create(False, True, False, True, False);
  mVisible := TArray<Boolean>.Create(True, True, False, True, True);
  Assert.AreEqual('x--xx', Shape(TAtlasMenuContextRules.Separators(mIsLine, mVisible)));
  Assert.AreEqual('', Shape(TAtlasMenuContextRules.Separators(nil, nil)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMenuContextRulesTests);

end.
