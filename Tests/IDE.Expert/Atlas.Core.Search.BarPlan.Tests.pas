unit Atlas.Core.Search.BarPlan.Tests;

// Tests für die Entscheidungen der Suchleiste (#877, #893): Vorschlag,
// Stufen für „Methode“, Bereich Auswahl, Ursprung und Frist für den Fokus.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Search')]
  TAtlasSearchBarPlanTests = class
  public
    /// <summary>Markierung vor Bezeichner am Cursor vor letzter Suche.</summary>
    [Test]
    procedure ProposalPrefersSelection;
    /// <summary>Stufen sind die Routinen um den Cursor, innerste zuerst.</summary>
    [Test]
    procedure LevelsInnermostFirst;
    /// <summary>Nur mehrzeilige Markierung ist Auswahl; Ursprung ist ihr Anfang.</summary>
    [Test]
    procedure SelectionAndOrigin;
    /// <summary>Fokusverlust gilt bis zur Frist als zurückgeholt.</summary>
    [Test]
    procedure FocusGrace;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Search.Matching,
  Atlas.Core.Search.BarPlan;

{ TAtlasSearchBarPlanTests }

procedure TAtlasSearchBarPlanTests.ProposalPrefersSelection;
var
  mLines: TArray<string>;
begin
  mLines := TArray<string>.Create('  Result := Value;');
  Assert.AreEqual('Res', TAtlasSearchBarPlan.Proposal('Res', mLines, TAtlasSearchPos.Create(0, 12), 'alt'));
  Assert.AreEqual('value', LowerCase(TAtlasSearchBarPlan.Proposal('', mLines, TAtlasSearchPos.Create(0, 13), 'alt')),
    'Bezeichner am Cursor');
  Assert.AreEqual('alt', TAtlasSearchBarPlan.Proposal('', mLines, TAtlasSearchPos.Create(5, 0), 'alt'), 'außerhalb');
  Assert.AreEqual('alt', TAtlasSearchBarPlan.Proposal('', mLines, TAtlasSearchPos.Create(0, 0), 'alt'), 'Leerraum');
  mLines := nil;
end;

procedure TAtlasSearchBarPlanTests.LevelsInnermostFirst;
var
  mText: string;
  mLevels: TArray<string>;
begin
  mText := 'procedure Outer;' + sLineBreak + '  procedure Inner;' + sLineBreak + '  begin' + sLineBreak +
    '    X := 1;' + sLineBreak + '  end;' + sLineBreak + 'begin' + sLineBreak + '  Inner;' + sLineBreak + 'end;';
  mLevels := TAtlasSearchBarPlan.Levels(mText, TAtlasSearchPos.Create(3, 4));
  Assert.AreEqual(2, Integer(Length(mLevels)));
  Assert.AreEqual('procedure Inner;', mLevels[0]);
  Assert.AreEqual('procedure Outer;', mLevels[1]);
  Assert.AreEqual(0, Integer(Length(TAtlasSearchBarPlan.Levels('unit A;', TAtlasSearchPos.Create(0, 0)))));
  mLevels := nil;
  mText := '';
end;

procedure TAtlasSearchBarPlanTests.SelectionAndOrigin;
var
  mOne, mMany: TAtlasSearchArea;
  mOrigin: TAtlasSearchPos;
begin
  mOne := TAtlasSearchArea.Create(2, 1, 2, 5);
  mMany := TAtlasSearchArea.Create(2, 1, 4, 0);
  Assert.IsFalse(TAtlasSearchBarPlan.AsSelection(True, mOne), 'einzeilig');
  Assert.IsTrue(TAtlasSearchBarPlan.AsSelection(True, mMany));
  Assert.IsFalse(TAtlasSearchBarPlan.AsSelection(False, mMany), 'ohne Markierung');
  mOrigin := TAtlasSearchBarPlan.Origin(TAtlasSearchPos.Create(9, 3), True, mMany);
  Assert.AreEqual(2, mOrigin.Line);
  Assert.AreEqual(1, mOrigin.Character);
  mOrigin := TAtlasSearchBarPlan.Origin(TAtlasSearchPos.Create(9, 3), False, mMany);
  Assert.AreEqual(9, mOrigin.Line, 'Cursor');
end;

procedure TAtlasSearchBarPlanTests.FocusGrace;
begin
  Assert.IsTrue(TAtlasSearchBarPlan.WithinFocusGrace(1000, 1400));
  Assert.IsFalse(TAtlasSearchBarPlan.WithinFocusGrace(1000, 1401));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSearchBarPlanTests);

end.
