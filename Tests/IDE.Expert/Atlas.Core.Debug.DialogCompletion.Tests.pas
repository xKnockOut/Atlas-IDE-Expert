unit Atlas.Core.Debug.DialogCompletion.Tests;

// Vervollständigung in den Debugger-Dialogen (#538), Plugin ohne IDE: Dialoge
// und Felder an Klasse, Titel und Beschriftung (deutsch und englisch), Zeile
// des Haltepunkts, Präfix und automatisches Öffnen, Übernehmen mitten im Wort,
// Verlauf mit 20 Einträgen je Projekt samt Datei, Einträge aus der Antwort
// des Servers und aus dem Verlauf.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.DialogCompletion;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugDialogCompletionTests = class
  public
    [Test]
    procedure RecognizesDialogs;
    [Test]
    procedure RecognizesFields;
    [Test]
    procedure BreakpointLine;
    [Test]
    procedure PrefixAndOpening;
    [Test]
    procedure ApplyReplacesWord;
    [Test]
    procedure HistoryKeepsTwentyNewestFirst;
    [Test]
    procedure HistoryRoundTrip;
    /// <summary>#784: 50 Einträge im Fenster „Auswerten“, Entfernen für festgeheftete Ausdrücke.</summary>
    [Test]
    procedure HistoryLimitAndRemove;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasDebugDialogCompletionTests }

procedure TAtlasDebugDialogCompletionTests.RecognizesDialogs;
begin
  Assert.IsTrue(TAtlasDebugDialogs.DialogOf('TEvaluateDialog', 'Auswerten/Ändern') = TAtlasDebugDialog.Evaluate);
  Assert.IsTrue(TAtlasDebugDialogs.DialogOf('TForm1', 'Evaluate/Modify') = TAtlasDebugDialog.Evaluate);
  Assert.IsTrue(TAtlasDebugDialogs.DialogOf('TWatchPropertiesDlg', 'Watch Properties') = TAtlasDebugDialog.Watch);
  Assert.IsTrue(TAtlasDebugDialogs.DialogOf('TDialog', 'Überwachungseigenschaften') = TAtlasDebugDialog.Watch);
  Assert.IsTrue(TAtlasDebugDialogs.DialogOf('TSourceBreakpointDlg', 'Add Source Breakpoint') =
    TAtlasDebugDialog.Breakpoint);
  Assert.IsTrue(TAtlasDebugDialogs.DialogOf('TBpDialog', 'Quelltext-Haltepunkt hinzufügen') =
    TAtlasDebugDialog.Breakpoint);
  Assert.IsTrue(TAtlasDebugDialogs.DialogOf('TAppBuilder', 'Projekt1 - RAD Studio') = TAtlasDebugDialog.None);
end;

procedure TAtlasDebugDialogCompletionTests.RecognizesFields;
begin
  Assert.IsTrue(TAtlasDebugDialogs.FieldOf(TAtlasDebugDialog.Evaluate, '&Ausdruck:') =
    TAtlasDebugField.Expression);
  Assert.IsTrue(TAtlasDebugDialogs.FieldOf(TAtlasDebugDialog.Evaluate, '') = TAtlasDebugField.Expression,
    'ohne Beschriftung');
  Assert.IsTrue(TAtlasDebugDialogs.FieldOf(TAtlasDebugDialog.Evaluate, '&New value:') = TAtlasDebugField.None);
  Assert.IsTrue(TAtlasDebugDialogs.FieldOf(TAtlasDebugDialog.Watch, 'E&xpression:') = TAtlasDebugField.Expression);
  Assert.IsTrue(TAtlasDebugDialogs.FieldOf(TAtlasDebugDialog.Watch, '') = TAtlasDebugField.None,
    'Gruppenname ohne Beschriftung nicht');
  Assert.IsTrue(TAtlasDebugDialogs.FieldOf(TAtlasDebugDialog.Breakpoint, '&Bedingung:') =
    TAtlasDebugField.Condition);
  Assert.IsTrue(TAtlasDebugDialogs.FieldOf(TAtlasDebugDialog.Breakpoint, 'Eval e&xpression:') =
    TAtlasDebugField.LogExpression);
  Assert.IsTrue(TAtlasDebugDialogs.FieldOf(TAtlasDebugDialog.Breakpoint, 'Log &message:') = TAtlasDebugField.None,
    'Meldung ist Text, kein Ausdruck');
  Assert.IsTrue(TAtlasDebugDialogs.FieldOf(TAtlasDebugDialog.Breakpoint, '&Dateiname:') =
    TAtlasDebugField.FileName);
  Assert.IsTrue(TAtlasDebugDialogs.FieldOf(TAtlasDebugDialog.Breakpoint, '&Line number:') =
    TAtlasDebugField.LineNumber);
  Assert.IsTrue(TAtlasDebugDialogs.Completes(TAtlasDebugField.LogExpression));
  Assert.IsFalse(TAtlasDebugDialogs.Completes(TAtlasDebugField.LineNumber));
end;

procedure TAtlasDebugDialogCompletionTests.BreakpointLine;
begin
  Assert.AreEqual(41, TAtlasDebugDialogs.ScopeLine(' 42 '));
  Assert.AreEqual(-1, TAtlasDebugDialogs.ScopeLine('0'));
  Assert.AreEqual(-1, TAtlasDebugDialogs.ScopeLine('zwölf'));
end;

procedure TAtlasDebugDialogCompletionTests.PrefixAndOpening;
begin
  Assert.AreEqual('Kun', TAtlasExpressionEdit.PrefixAt('Kun', 3));
  Assert.AreEqual('Na', TAtlasExpressionEdit.PrefixAt('Kunde.Name', 8));
  Assert.AreEqual('', TAtlasExpressionEdit.PrefixAt('Kunde.', 6));
  Assert.IsTrue(TAtlasExpressionEdit.OpensAfter('', 'K', 1), 'Wortanfang');
  Assert.IsFalse(TAtlasExpressionEdit.OpensAfter('K', 'Ku', 2), 'mitten im Wort öffnet der Controller nicht neu');
  Assert.IsTrue(TAtlasExpressionEdit.OpensAfter('Kunde', 'Kunde.', 6), 'nach dem Punkt');
  Assert.IsFalse(TAtlasExpressionEdit.OpensAfter('A + ', 'A + 1', 5), 'Zahl');
  Assert.IsFalse(TAtlasExpressionEdit.OpensAfter('', 'Kunde', 5), 'eingefügt');
  Assert.IsFalse(TAtlasExpressionEdit.OpensAfter('Kunde', 'Kund', 4), 'gelöscht');
end;

procedure TAtlasDebugDialogCompletionTests.ApplyReplacesWord;
var
  mText: string;
  mCaret: Integer;
begin
  TAtlasExpressionEdit.Apply('Kunde.Na', 8, 2, 'Name', mText, mCaret);
  Assert.AreEqual('Kunde.Name', mText);
  Assert.AreEqual(10, mCaret);
  TAtlasExpressionEdit.Apply('Ku + 1', 2, 2, 'Kunde', mText, mCaret);
  Assert.AreEqual('Kunde + 1', mText);
  Assert.AreEqual(5, mCaret);
  TAtlasExpressionEdit.Apply('Kunde.Nxx', 7, 1, 'Name', mText, mCaret);
  Assert.AreEqual('Kunde.Name', mText, 'Rest des Worts mit ersetzt');
end;

procedure TAtlasDebugDialogCompletionTests.HistoryKeepsTwentyNewestFirst;
var
  mHistory: TAtlasExpressionHistory;
  mIndex: Integer;
  mItems: TArray<string>;
begin
  mHistory := TAtlasExpressionHistory.Create;
  try
    for mIndex := 1 to 25 do
    begin
      mHistory.Add('C:\P\Haupt.dproj', 'Wert' + IntToStr(mIndex));
    end;
    mItems := mHistory.Items('c:\p\haupt.dproj');
    Assert.AreEqual(TAtlasExpressionHistory.cMaxPerProject, Integer(Length(mItems)));
    Assert.AreEqual('Wert25', mItems[0]);
    Assert.AreEqual('Wert6', mItems[19]);
    Assert.IsTrue(mHistory.Add('C:\P\Haupt.dproj', ' Wert10 '), 'rückt nach vorn');
    mItems := mHistory.Items('C:\P\Haupt.dproj');
    Assert.AreEqual('Wert10', mItems[0]);
    Assert.AreEqual(TAtlasExpressionHistory.cMaxPerProject, Integer(Length(mItems)));
    Assert.IsFalse(mHistory.Add('C:\P\Haupt.dproj', 'Wert10'), 'schon vorn');
    Assert.IsFalse(mHistory.Add('C:\P\Haupt.dproj', '  '), 'leer');
    Assert.AreEqual(0, Integer(Length(mHistory.Items('C:\P\Anderes.dproj'))), 'je Projekt');
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasDebugDialogCompletionTests.HistoryRoundTrip;
var
  mHistory, mLoaded: TAtlasExpressionHistory;
  mItems: TArray<string>;
begin
  mHistory := TAtlasExpressionHistory.Create;
  mLoaded := TAtlasExpressionHistory.Create;
  try
    mHistory.Add('A.dproj', 'Kunde.Name');
    mHistory.Add('A.dproj', 'Summe');
    mHistory.Add('', 'Self');
    Assert.IsTrue(mLoaded.LoadFromText(mHistory.ToText));
    mItems := mLoaded.Items('a.dproj');
    Assert.AreEqual(2, Integer(Length(mItems)));
    Assert.AreEqual('Summe', mItems[0]);
    Assert.AreEqual('Self', mLoaded.Items('')[0]);
    Assert.IsFalse(mLoaded.LoadFromText('[1]'));
    Assert.AreEqual(0, Integer(Length(mLoaded.Items('a.dproj'))));
    Assert.IsTrue(mLoaded.LoadFromText('{"projects":{"b":["x", 3, "", "y"]}}'), 'einzelne Fehler übersprungen');
    Assert.AreEqual(2, Integer(Length(mLoaded.Items('b'))));
  finally
    mLoaded.Free;
    mHistory.Free;
  end;
end;

procedure TAtlasDebugDialogCompletionTests.HistoryLimitAndRemove;
var
  mHistory: TAtlasExpressionHistory;
  mIndex: Integer;
begin
  mHistory := TAtlasExpressionHistory.Create(50);
  try
    Assert.AreEqual(50, mHistory.Limit);
    for mIndex := 1 to 60 do
    begin
      mHistory.Add('P', 'W' + IntToStr(mIndex));
    end;
    Assert.AreEqual(50, Integer(Length(mHistory.Items('P'))));
    Assert.IsTrue(mHistory.Remove('P', ' W60 '));
    Assert.AreEqual('W59', mHistory.Items('P')[0]);
    Assert.IsFalse(mHistory.Remove('P', 'W60'), 'schon weg');
    Assert.IsFalse(mHistory.Remove('Q', 'W1'), 'anderes Projekt');
  finally
    mHistory.Free;
  end;
end;

end.
