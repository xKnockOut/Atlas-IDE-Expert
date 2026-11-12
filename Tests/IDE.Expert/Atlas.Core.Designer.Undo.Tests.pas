unit Atlas.Core.Designer.Undo.Tests;

// Tests für „Rückgängig im Designer“ ohne IDE (#1887): Formulartext lesen,
// Schritte zum Zurückladen planen (setzen, zurücksetzen, Ereignisse,
// löschen, anlegen, umbenennen, Kollektionen), Änderungstext und Verlauf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerUndoTests = class
  public
    [Test]
    procedure ParseReadsObjectsAndValues;
    [Test]
    procedure ParseKeysInFrames;
    [Test]
    procedure PlanSetsResetsAndEvents;
    [Test]
    procedure PlanCollectionAsObjectText;
    [Test]
    procedure PlanDeletesAndCreates;
    [Test]
    procedure PlanRenames;
    [Test]
    procedure PlanParentChangeRecreates;
    [Test]
    procedure PlanSkipsInheritedAndFrames;
    [Test]
    procedure PlanEmptyForSameOrBrokenText;
    [Test]
    procedure DescribesSteps;
    [Test]
    procedure ShownShortensValues;
    [Test]
    procedure HistoryUndoRedoAndLimit;
    [Test]
    procedure HistoryMoveToKeepsActualText;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Designer.Undo;

function Lines(const ALines: array of string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
  begin
    Result := Result + mLine + sLineBreak;
  end;
end;

/// <summary>Formular mit Panel1 (Kind Button1), ListView1 mit Spalten und Memo1 mit Zeilen.</summary>
function BaseForm: string;
begin
  Result := Lines(['object Form1: TForm1',
    '  Left = 0',
    '  Caption = ''Form1''',
    '  OnCreate = FormCreate',
    '  object Panel1: TPanel',
    '    Left = 8',
    '    Top = 8',
    '    Width = 185',
    '    Height = 41',
    '    Caption = ''Panel1''',
    '    object Button1: TButton',
    '      Left = 312',
    '      Top = 410',
    '      Width = 75',
    '      Height = 25',
    '      Caption = ''OK''',
    '      OnClick = Button1Click',
    '    end',
    '  end',
    '  object ListView1: TListView',
    '    Columns = <',
    '      item',
    '        Caption = ''Name''',
    '      end>',
    '  end',
    '  object Memo1: TMemo',
    '    Hint = ',
    '      ''Erste Zeile '' +',
    '      ''zweite Zeile''',
    '    Lines.Strings = (',
    '      ''Memo1'')',
    '  end',
    'end']);
end;

function Changed(const AOld, ANew: string): string;
begin
  Result := StringReplace(BaseForm, AOld, ANew, []);
end;

/// <summary>Formate wie aus der Oberfläche, hier englisch und ohne Pfeil: FPC vergleicht Strings mit
/// Zeichen außerhalb von ASCII aus der Quelle anders als Delphi.</summary>
function Words: TAtlasUndoWords;
begin
  Result.Moved := '%s moved (%s, %s) -> (%s, %s)';
  Result.Resized := '%s size (%s, %s) -> (%s, %s)';
  Result.Changed := '%s.%s: %s -> %s';
  Result.ChangedMany := '%s: %d properties changed';
  Result.Inserted := '%s inserted';
  Result.Deleted := '%s deleted';
  Result.Renamed := '%s renamed to %s';
  Result.MovedMany := '%d components moved';
  Result.Several := '%d changes';
  Result.DefaultValue := '(default)';
end;

procedure TAtlasDesignerUndoTests.ParseReadsObjectsAndValues;
var
  mObjects: TArray<TAtlasUndoObject>;
begin
  mObjects := TAtlasFormUndo.Parse(BaseForm);
  Assert.AreEqual(5, Integer(Length(mObjects)));
  Assert.AreEqual('', mObjects[0].Key, 'Formular ohne Schlüssel');
  Assert.AreEqual('Form1', mObjects[0].Name);
  Assert.AreEqual('Button1', mObjects[2].Key);
  Assert.AreEqual('Panel1', mObjects[2].ParentKey, 'Elternelement aus der Verschachtelung');
  Assert.AreEqual('', mObjects[1].ParentKey);
  Assert.IsTrue(mObjects[0].Values[mObjects[0].IndexOf('OnCreate')].IsEvent, 'Ereignis erkannt');
  Assert.IsFalse(mObjects[0].Values[mObjects[0].IndexOf('Caption')].IsEvent);
  Assert.AreEqual('<'#10'item'#10'Caption = ''Name'''#10'end>', mObjects[3].ValueOf('Columns'),
    'Kollektion als ein Wert');
  Assert.AreEqual(4, Integer(Length(mObjects[3].Values[0].Lines)));
  Assert.AreEqual('  item', mObjects[3].Values[0].Lines[1], 'Einrückung relativ zur Eigenschaft');
  Assert.AreEqual('''Erste Zeile '' +'#10'''zweite Zeile''', mObjects[4].ValueOf('Hint'),
    'Wert ab der nächsten Zeile, mit + verkettet');
  Assert.AreEqual('('#10'''Memo1'')', mObjects[4].ValueOf('Lines.Strings'));
  Assert.AreEqual(0, mObjects[4].IndexOf('hint'), 'Pfad ohne Groß-/Kleinschreibung');
end;

procedure TAtlasDesignerUndoTests.ParseKeysInFrames;
var
  mObjects: TArray<TAtlasUndoObject>;
begin
  mObjects := TAtlasFormUndo.Parse(Lines(['inherited Form2: TForm2',
    '  inline Frame11: TFrame1',
    '    inherited Button1: TButton',
    '      Caption = ''Frame''',
    '    end',
    '  end',
    '  inherited Label1: TLabel',
    '  end',
    'end']));
  Assert.AreEqual(4, Integer(Length(mObjects)));
  Assert.AreEqual('Frame11.Button1', mObjects[2].Key, 'Kind eines eingebetteten Frames');
  Assert.AreEqual('Frame11', mObjects[2].ParentKey);
  Assert.AreEqual('Label1', mObjects[3].Key);
  Assert.IsFalse(mObjects[1].Plain, 'inline');
  Assert.IsFalse(mObjects[3].Plain, 'geerbt');
end;

procedure TAtlasDesignerUndoTests.PlanSetsResetsAndEvents;
var
  mPlan: TAtlasUndoPlan;
begin
  // Ziel: Panel1 wieder ohne Align, Caption auf die Vorgabe, Button1 ohne Handler, Formular mit anderem Handler.
  mPlan := TAtlasFormUndo.Plan(Changed('    Caption = ''Panel1''', '    Align = alClient'#13#10 +
    '    Caption = ''Panel1'''), Changed('    Caption = ''Panel1''' + sLineBreak, ''));
  Assert.IsFalse(mPlan.Structural);
  Assert.AreEqual(1, Integer(Length(mPlan.Changes)));
  Assert.AreEqual('Panel1', mPlan.Changes[0].Key);
  Assert.AreEqual(0, Integer(Length(mPlan.Changes[0].Paths)));
  Assert.AreEqual('', mPlan.Changes[0].Text, 'nichts zu setzen');
  Assert.AreEqual(2, Integer(Length(mPlan.Changes[0].Resets)));
  Assert.AreEqual('Align', mPlan.Changes[0].Resets[0]);
  Assert.AreEqual('Caption', mPlan.Changes[0].Resets[1]);

  mPlan := TAtlasFormUndo.Plan(BaseForm, Changed('      OnClick = Button1Click' + sLineBreak, '').Replace(
    'OnCreate = FormCreate', 'OnCreate = FormStart').Replace('Left = 312', 'Left = 296'));
  Assert.AreEqual(2, Integer(Length(mPlan.Changes)));
  Assert.AreEqual('', mPlan.Changes[0].Key, 'Formular');
  Assert.AreEqual('OnCreate', mPlan.Changes[0].Events[0].Path);
  Assert.AreEqual('FormStart', mPlan.Changes[0].Events[0].Handler);
  Assert.AreEqual('Button1', mPlan.Changes[1].Key);
  Assert.AreEqual('OnClick', mPlan.Changes[1].Events[0].Path);
  Assert.AreEqual('', mPlan.Changes[1].Events[0].Handler, 'Zuordnung entfernen');
  Assert.AreEqual('object Button1: TButton' + sLineBreak + '  Left = 296' + sLineBreak + 'end',
    mPlan.Changes[1].Text, 'nur der geänderte Wert');
end;

procedure TAtlasDesignerUndoTests.PlanCollectionAsObjectText;
var
  mPlan: TAtlasUndoPlan;
begin
  mPlan := TAtlasFormUndo.Plan(Changed('Caption = ''Name''', 'Caption = ''Vorname'''), BaseForm);
  Assert.AreEqual(1, Integer(Length(mPlan.Changes)));
  Assert.AreEqual('Columns', mPlan.Changes[0].Paths[0]);
  Assert.AreEqual(Lines(['object ListView1: TListView', '  Columns = <', '    item', '      Caption = ''Name''',
    '    end>']) + 'end', mPlan.Changes[0].Text, 'ganze Kollektion für TReader');
end;

procedure TAtlasDesignerUndoTests.PlanDeletesAndCreates;
var
  mWithout: string;
  mPlan: TAtlasUndoPlan;
begin
  mWithout := Lines(['object Form1: TForm1', '  Left = 0', '  Caption = ''Form1''', '  OnCreate = FormCreate',
    'end']);
  // Zurück zum vollen Formular: Panel1 vor Button1 anlegen, Ereignisse getrennt.
  mPlan := TAtlasFormUndo.Plan(mWithout, BaseForm);
  Assert.AreEqual(0, Integer(Length(mPlan.Deletes)));
  Assert.AreEqual(4, Integer(Length(mPlan.Creates)));
  Assert.AreEqual('Panel1', mPlan.Creates[0].Key);
  Assert.AreEqual('', mPlan.Creates[0].ParentKey);
  Assert.AreEqual('Button1', mPlan.Creates[1].Key);
  Assert.AreEqual('Panel1', mPlan.Creates[1].ParentKey, 'Eltern vor Kindern');
  Assert.AreEqual('TButton', mPlan.Creates[1].TypeName);
  Assert.AreEqual('Button1Click', mPlan.Creates[1].Events[0].Handler);
  Assert.IsFalse(mPlan.Creates[1].Text.Contains('OnClick'), 'Ereignisse nicht im Text für TReader');
  Assert.AreEqual(5, Integer(Length(mPlan.Creates[1].Paths)));
  Assert.AreEqual(0, Integer(Length(mPlan.Changes)));
  // Und vor: nur die obersten löschen.
  mPlan := TAtlasFormUndo.Plan(BaseForm, mWithout);
  Assert.AreEqual(3, Integer(Length(mPlan.Deletes)));
  Assert.AreEqual('Panel1', mPlan.Deletes[0], 'Button1 geht mit Panel1');
  Assert.AreEqual('ListView1', mPlan.Deletes[1]);
  Assert.AreEqual(0, Integer(Length(mPlan.Creates)));
end;

procedure TAtlasDesignerUndoTests.PlanRenames;
var
  mPlan: TAtlasUndoPlan;
begin
  mPlan := TAtlasFormUndo.Plan(Changed('object Panel1: TPanel', 'object pnlTop: TPanel'), BaseForm);
  Assert.AreEqual(1, Integer(Length(mPlan.Renames)));
  Assert.AreEqual('pnlTop', mPlan.Renames[0].OldKey);
  Assert.AreEqual('Panel1', mPlan.Renames[0].NewName);
  Assert.AreEqual(0, Integer(Length(mPlan.Deletes)), 'Umbenennen statt löschen');
  Assert.AreEqual(0, Integer(Length(mPlan.Creates)));
  Assert.AreEqual(0, Integer(Length(mPlan.Changes)), 'Kind Button1 bleibt');
end;

procedure TAtlasDesignerUndoTests.PlanParentChangeRecreates;
var
  mMoved: string;
  mPlan: TAtlasUndoPlan;
begin
  // Button1 liegt im aktuellen Stand direkt auf dem Formular.
  mMoved := Lines(['object Form1: TForm1', '  object Panel1: TPanel', '  end', '  object Button1: TButton',
    '    Left = 8', '  end', 'end']);
  mPlan := TAtlasFormUndo.Plan(mMoved, Lines(['object Form1: TForm1', '  object Panel1: TPanel',
    '    object Button1: TButton', '      Left = 8', '    end', '  end', 'end']));
  Assert.AreEqual(1, Integer(Length(mPlan.Deletes)));
  Assert.AreEqual('Button1', mPlan.Deletes[0]);
  Assert.AreEqual(1, Integer(Length(mPlan.Creates)));
  Assert.AreEqual('Panel1', mPlan.Creates[0].ParentKey);
end;

procedure TAtlasDesignerUndoTests.PlanSkipsInheritedAndFrames;
var
  mPlan: TAtlasUndoPlan;
  mBase: string;
begin
  mBase := Lines(['inherited Form2: TForm2', '  inline Frame11: TFrame1', '    inherited Button1: TButton',
    '      Caption = ''Frame''', '    end', '  end', '  inherited Label1: TLabel', '  end', 'end']);
  mPlan := TAtlasFormUndo.Plan(mBase, Lines(['inherited Form2: TForm2', 'end']));
  Assert.AreEqual(0, Integer(Length(mPlan.Deletes)));
  Assert.AreEqual(2, Integer(Length(mPlan.Skipped)), 'Frame und geerbtes Label nicht löschbar');
  mPlan := TAtlasFormUndo.Plan(mBase, mBase.Replace('''Frame''', '''Neu'''));
  Assert.AreEqual(1, Integer(Length(mPlan.Changes)));
  Assert.AreEqual('Frame11.Button1', mPlan.Changes[0].Key, 'Werte im Frame lassen sich setzen');
end;

procedure TAtlasDesignerUndoTests.PlanEmptyForSameOrBrokenText;
begin
  Assert.IsTrue(TAtlasFormUndo.Plan(BaseForm, BaseForm).IsEmpty);
  Assert.IsTrue(TAtlasFormUndo.Plan(BaseForm, '').IsEmpty, 'ohne Zielstand nichts löschen');
  Assert.IsTrue(TAtlasFormUndo.Plan('', BaseForm).IsEmpty);
end;

procedure TAtlasDesignerUndoTests.DescribesSteps;
begin
  Assert.AreEqual('Button1 moved (312, 410) -> (296, 410)',
    TAtlasFormUndo.Describe(BaseForm, Changed('Left = 312', 'Left = 296'), Words));
  Assert.AreEqual('Button1 size (75, 25) -> (100, 25)',
    TAtlasFormUndo.Describe(BaseForm, Changed('Width = 75', 'Width = 100'), Words));
  Assert.AreEqual('Panel1.Align: (default) -> alClient', TAtlasFormUndo.Describe(BaseForm,
    Changed('    Caption = ''Panel1''', '    Align = alClient'#13#10'    Caption = ''Panel1'''), Words));
  Assert.AreEqual('Button1: 2 properties changed', TAtlasFormUndo.Describe(BaseForm,
    Changed('Caption = ''OK''', 'Caption = ''Ja''').Replace('Button1Click', 'Button1Ja'), Words));
  Assert.AreEqual('pnlTop renamed to Panel1', TAtlasFormUndo.Describe(Changed('object Panel1: TPanel',
    'object pnlTop: TPanel'), BaseForm, Words));
  Assert.AreEqual('Memo1 deleted', TAtlasFormUndo.Describe(BaseForm, Changed(Lines(['  object Memo1: TMemo',
    '    Hint = ', '      ''Erste Zeile '' +', '      ''zweite Zeile''', '    Lines.Strings = (', '      ''Memo1'')',
    '  end']), ''), Words));
  Assert.AreEqual('Memo1 inserted', TAtlasFormUndo.Describe(Changed(Lines(['  object Memo1: TMemo',
    '    Hint = ', '      ''Erste Zeile '' +', '      ''zweite Zeile''', '    Lines.Strings = (', '      ''Memo1'')',
    '  end']), ''), BaseForm, Words));
  Assert.AreEqual('2 components moved', TAtlasFormUndo.Describe(BaseForm,
    Changed('Left = 312', 'Left = 296').Replace('    Left = 8', '    Left = 16'), Words));
  Assert.AreEqual('2 changes', TAtlasFormUndo.Describe(BaseForm,
    Changed('Left = 312', 'Left = 296').Replace('''Form1''', '''Haupt'''), Words));
  Assert.AreEqual('', TAtlasFormUndo.Describe(BaseForm, BaseForm, Words), 'keine Änderung');
end;

procedure TAtlasDesignerUndoTests.ShownShortensValues;
begin
  Assert.AreEqual('(default)', TAtlasFormUndo.Shown('', '(default)'));
  Assert.AreEqual('alClient', TAtlasFormUndo.Shown('alClient', '-'));
  Assert.AreEqual('( …', TAtlasFormUndo.Shown('('#10'''a'')', '-'), 'nur die erste Zeile');
  Assert.AreEqual(StringOfChar('x', 39) + '…', TAtlasFormUndo.Shown(StringOfChar('x', 60), '-'));
end;

procedure TAtlasDesignerUndoTests.HistoryUndoRedoAndLimit;
var
  mHistory: TAtlasFormUndoHistory;
  mIndex: Integer;
begin
  mHistory := TAtlasFormUndoHistory.Create(1);
  try
    Assert.AreEqual(Integer(TAtlasFormUndoHistory.cMinSteps), mHistory.MaxSteps, 'Untergrenze');
    Assert.IsTrue(mHistory.Add('a', 'egal'));
    Assert.AreEqual('', mHistory.State(0).Caption, 'Ausgangsstand ohne Text');
    Assert.IsFalse(mHistory.CanUndo);
    Assert.IsFalse(mHistory.Add('a', 'gleich'), 'gleicher Stand zählt nicht');
    Assert.IsTrue(mHistory.Add('b', 'zu b'));
    Assert.IsTrue(mHistory.Add('c', 'zu c'));
    Assert.IsTrue(mHistory.CanUndo);
    Assert.IsFalse(mHistory.CanRedo);
    mHistory.MoveTo(0, 'a');
    Assert.IsTrue(mHistory.CanRedo);
    Assert.IsTrue(mHistory.Add('d', 'zu d'), 'neue Änderung nach dem Zurückgehen');
    Assert.AreEqual(2, mHistory.Count, 'b und c fallen weg');
    Assert.IsFalse(mHistory.CanRedo);
    for mIndex := 1 to 10 do
    begin
      mHistory.Add('n' + IntToStr(mIndex), 'zu n' + IntToStr(mIndex));
    end;
    Assert.AreEqual(6, mHistory.Count, 'Ausgangsstand und fünf Schritte');
    Assert.AreEqual(5, mHistory.Index);
    Assert.AreEqual('n5', mHistory.State(0).Text, 'älteste fallen weg');
    Assert.AreEqual('', mHistory.State(0).Caption, 'neuer Ausgangsstand');
    mHistory.MaxSteps := 500;
    Assert.AreEqual(Integer(TAtlasFormUndoHistory.cMaxSteps), mHistory.MaxSteps, 'Obergrenze');
    mHistory.Clear;
    Assert.AreEqual(0, mHistory.Count);
    Assert.IsFalse(mHistory.CanUndo);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasDesignerUndoTests.HistoryMoveToKeepsActualText;
var
  mHistory: TAtlasFormUndoHistory;
begin
  mHistory := TAtlasFormUndoHistory.Create(50);
  try
    mHistory.Add('a', '');
    mHistory.Add('b', 'zu b');
    mHistory.MoveTo(0, 'a ohne Frame');
    Assert.AreEqual(0, mHistory.Index);
    Assert.AreEqual('a ohne Frame', mHistory.State(0).Text, 'tatsächlich hergestellter Stand');
    mHistory.MoveTo(7, 'x');
    Assert.AreEqual(0, mHistory.Index, 'ungültiger Index ändert nichts');
  finally
    mHistory.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDesignerUndoTests);

end.
