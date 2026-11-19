unit Atlas.UI.Debug.ExceptionRuleList.Tests;

// Fenster „Exception-Regeln“ (#838): Zeilen mit Treffern, persönliche vor
// denen des Projekts, anlegen, verschieben (Knöpfe und Ziehen, nur in der
// Gruppe), ein- und ausschalten, löschen, Herkunft wechseln.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasExceptionRuleListDialogTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CellsOfRule;
    [Test]
    procedure MovesStayInGroup;
    [Test]
    procedure NewMoveToggleDelete;
    [Test]
    procedure OriginChangeMovesRule;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.ExceptionRules,
  Atlas.UI.Debug.ExceptionRuleList;

function Rule(const AClass: string; AAction: TAtlasExceptionAction): TAtlasExceptionRule;
begin
  Result := TAtlasExceptionRule.Create(AClass, '', TAtlasMessageMatch.Matches, AAction);
end;

function SampleRules: TAtlasExceptionRuleList;
begin
  Result := TAtlasExceptionRules.Combined(
    TAtlasExceptionRuleList.Create(Rule('EAbort', TAtlasExceptionAction.Continue),
    Rule('EConvertError', TAtlasExceptionAction.Log)),
    TAtlasExceptionRuleList.Create(Rule('EDatabaseError', TAtlasExceptionAction.Stop)));
end;

/// <summary>Editor ohne Fenster: macht die Regel zu einer des Projekts mit Nachfahren.</summary>
function ToProjectEditor: TAtlasExceptionRuleEditor;
begin
  Result :=
    function(var ARule: TAtlasExceptionRule; ANew: Boolean): Boolean
    begin
      ARule.Origin := TAtlasExceptionRuleOrigin.Project;
      ARule.Descendants := True;
      Result := True;
    end;
end;

/// <summary>Editor ohne Fenster: legt EInOutError an bzw. setzt beim Bearbeiten die Aktion auf Anhalten.</summary>
function FakeEditor: TAtlasExceptionRuleEditor;
begin
  Result :=
    function(var ARule: TAtlasExceptionRule; ANew: Boolean): Boolean
    begin
      if ANew then
      begin
        ARule.ExceptionClass := 'EInOutError';
      end;
      ARule.Action := TAtlasExceptionAction.Stop;
      Result := True;
    end;
end;

{ TAtlasExceptionRuleListDialogTests }

procedure TAtlasExceptionRuleListDialogTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasExceptionRuleListDialogTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasExceptionRuleListDialogTests.CellsOfRule;
var
  mRule: TAtlasExceptionRule;
  mCells: TArray<string>;
begin
  mRule := TAtlasExceptionRule.Create('EKonfig', 'unbekannt', TAtlasMessageMatch.NotMatches,
    TAtlasExceptionAction.Log);
  mRule.Origin := TAtlasExceptionRuleOrigin.Project;
  mCells := TAtlasExceptionRuleListDialog.Cells(mRule, 3);
  Assert.AreEqual(7, Integer(Length(mCells)));
  Assert.AreEqual('✓', mCells[0]);
  Assert.AreEqual('EKonfig', mCells[1]);
  Assert.AreEqual('überall', mCells[2]);
  Assert.AreEqual('nicht: unbekannt', mCells[3]);
  Assert.AreEqual('Nur protokollieren', mCells[4]);
  Assert.AreEqual('Projekt', mCells[5]);
  Assert.AreEqual('3', mCells[6]);
  mRule.Enabled := False;
  mRule.Location := 'Kunden.*';
  mCells := TAtlasExceptionRuleListDialog.Cells(mRule, 0);
  Assert.AreEqual('', mCells[0], 'ausgeschaltet');
  Assert.AreEqual('Kunden.*', mCells[2]);
  mRule.Descendants := True;
  mCells := TAtlasExceptionRuleListDialog.Cells(mRule, 0);
  Assert.AreEqual('EKonfig (mit Nachfahren)', mCells[1]);
end;

procedure TAtlasExceptionRuleListDialogTests.MovesStayInGroup;
var
  mDialog: TAtlasExceptionRuleListDialog;
  mHits: TAtlasExceptionRuleHits;
  mRules: TAtlasExceptionRuleList;
begin
  mRules := SampleRules;
  mHits := Default(TAtlasExceptionRuleHits);
  mHits.Add(mRules[2].Key);
  mDialog := TAtlasExceptionRuleListDialog.CreateFor(nil, mRules, mHits);
  try
    mDialog.List.HandleNeeded;
    mDialog.Fill;
    Assert.AreEqual(3, mDialog.List.Items.Count);
    Assert.AreEqual('1', mDialog.List.Items[2].SubItems[5], 'Treffer der Projektregel');
    mDialog.Select(2);
    Assert.IsTrue(mDialog.Buttons[TAtlasRuleListButton.Edit].Enabled, 'Regel des Projekts');
    Assert.IsTrue(mDialog.Buttons[TAtlasRuleListButton.Delete].Enabled);
    Assert.IsFalse(mDialog.Buttons[TAtlasRuleListButton.Up].Enabled, 'nicht über die persönlichen');
    mDialog.Select(1);
    Assert.IsTrue(mDialog.Buttons[TAtlasRuleListButton.Up].Enabled);
    Assert.IsFalse(mDialog.Buttons[TAtlasRuleListButton.Down].Enabled, 'nicht unter die Projektregeln');
    Assert.IsFalse(mDialog.Buttons[TAtlasRuleListButton.OpenProject].Enabled, 'ohne Rückruf');
    Assert.IsFalse(mDialog.DropAt(2), 'Ziehen in die andere Gruppe');
    Assert.IsTrue(mDialog.DropAt(0), 'Ziehen in der Gruppe');
    Assert.AreEqual('EConvertError', mDialog.Rules[0].ExceptionClass);
    Assert.AreEqual(0, mDialog.Selected);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasExceptionRuleListDialogTests.NewMoveToggleDelete;
var
  mDialog: TAtlasExceptionRuleListDialog;
  mPersonal: TAtlasExceptionRuleList;
begin
  mDialog := TAtlasExceptionRuleListDialog.CreateFor(nil, SampleRules, Default(TAtlasExceptionRuleHits));
  try
    mDialog.Editor := FakeEditor;
    mDialog.List.HandleNeeded;
    mDialog.Fill;
    mDialog.Buttons[TAtlasRuleListButton.New].Click;
    Assert.AreEqual(4, Integer(Length(mDialog.Rules)));
    Assert.AreEqual('EInOutError', mDialog.Rules[2].ExceptionClass, 'ans Ende der persönlichen');
    Assert.AreEqual(2, mDialog.Selected);
    mDialog.Buttons[TAtlasRuleListButton.Up].Click;
    Assert.AreEqual('EInOutError', mDialog.Rules[1].ExceptionClass);
    Assert.AreEqual(1, mDialog.Selected);
    mDialog.Buttons[TAtlasRuleListButton.Toggle].Click;
    Assert.IsFalse(mDialog.Rules[1].Enabled);
    mDialog.Select(0);
    mDialog.Buttons[TAtlasRuleListButton.Edit].Click;
    Assert.AreEqual(Ord(TAtlasExceptionAction.Stop), Ord(mDialog.Rules[0].Action));
    mDialog.Buttons[TAtlasRuleListButton.Delete].Click;
    mPersonal := mDialog.RulesOf(TAtlasExceptionRuleOrigin.Personal);
    Assert.AreEqual(2, Integer(Length(mPersonal)), 'Projektregel nicht dabei');
    Assert.AreEqual('EInOutError', mPersonal[0].ExceptionClass);
    Assert.AreEqual('EConvertError', mPersonal[1].ExceptionClass);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasExceptionRuleListDialogTests.OriginChangeMovesRule;
var
  mDialog: TAtlasExceptionRuleListDialog;
  mProject: TAtlasExceptionRuleList;
begin
  mDialog := TAtlasExceptionRuleListDialog.CreateFor(nil, SampleRules, Default(TAtlasExceptionRuleHits));
  try
    mDialog.Editor := ToProjectEditor;
    mDialog.List.HandleNeeded;
    mDialog.Fill;
    mDialog.Select(0);
    mDialog.Buttons[TAtlasRuleListButton.Edit].Click;
    Assert.AreEqual(2, mDialog.Selected, 'ans Ende der Projektregeln');
    mProject := mDialog.RulesOf(TAtlasExceptionRuleOrigin.Project);
    Assert.AreEqual(2, Integer(Length(mProject)));
    Assert.AreEqual('EAbort', mProject[1].ExceptionClass);
    Assert.IsTrue(mProject[1].Descendants);
    Assert.AreEqual(1, Integer(Length(mDialog.RulesOf(TAtlasExceptionRuleOrigin.Personal))));
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExceptionRuleListDialogTests);

end.
