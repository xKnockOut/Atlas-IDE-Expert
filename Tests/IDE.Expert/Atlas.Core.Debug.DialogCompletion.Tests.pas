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
  Text: string;
  Caret: Integer;
begin
  TAtlasExpressionEdit.Apply('Kunde.Na', 8, 2, 'Name', Text, Caret);
  Assert.AreEqual('Kunde.Name', Text);
  Assert.AreEqual(10, Caret);
  TAtlasExpressionEdit.Apply('Ku + 1', 2, 2, 'Kunde', Text, Caret);
  Assert.AreEqual('Kunde + 1', Text);
  Assert.AreEqual(5, Caret);
  TAtlasExpressionEdit.Apply('Kunde.Nxx', 7, 1, 'Name', Text, Caret);
  Assert.AreEqual('Kunde.Name', Text, 'Rest des Worts mit ersetzt');
end;

procedure TAtlasDebugDialogCompletionTests.HistoryKeepsTwentyNewestFirst;
var
  History: TAtlasExpressionHistory;
  Index: Integer;
  Items: TArray<string>;
begin
  History := TAtlasExpressionHistory.Create;
  try
    for Index := 1 to 25 do
      History.Add('C:\P\Haupt.dproj', 'Wert' + IntToStr(Index));
    Items := History.Items('c:\p\haupt.dproj');
    Assert.AreEqual(TAtlasExpressionHistory.MaxPerProject, Integer(Length(Items)));
    Assert.AreEqual('Wert25', Items[0]);
    Assert.AreEqual('Wert6', Items[19]);
    Assert.IsTrue(History.Add('C:\P\Haupt.dproj', ' Wert10 '), 'rückt nach vorn');
    Items := History.Items('C:\P\Haupt.dproj');
    Assert.AreEqual('Wert10', Items[0]);
    Assert.AreEqual(TAtlasExpressionHistory.MaxPerProject, Integer(Length(Items)));
    Assert.IsFalse(History.Add('C:\P\Haupt.dproj', 'Wert10'), 'schon vorn');
    Assert.IsFalse(History.Add('C:\P\Haupt.dproj', '  '), 'leer');
    Assert.AreEqual(0, Integer(Length(History.Items('C:\P\Anderes.dproj'))), 'je Projekt');
  finally
    History.Free;
  end;
end;

procedure TAtlasDebugDialogCompletionTests.HistoryRoundTrip;
var
  History, Loaded: TAtlasExpressionHistory;
  Items: TArray<string>;
begin
  History := TAtlasExpressionHistory.Create;
  Loaded := TAtlasExpressionHistory.Create;
  try
    History.Add('A.dproj', 'Kunde.Name');
    History.Add('A.dproj', 'Summe');
    History.Add('', 'Self');
    Assert.IsTrue(Loaded.LoadFromText(History.ToText));
    Items := Loaded.Items('a.dproj');
    Assert.AreEqual(2, Integer(Length(Items)));
    Assert.AreEqual('Summe', Items[0]);
    Assert.AreEqual('Self', Loaded.Items('')[0]);
    Assert.IsFalse(Loaded.LoadFromText('[1]'));
    Assert.AreEqual(0, Integer(Length(Loaded.Items('a.dproj'))));
    Assert.IsTrue(Loaded.LoadFromText('{"projects":{"b":["x", 3, "", "y"]}}'), 'einzelne Fehler übersprungen');
    Assert.AreEqual(2, Integer(Length(Loaded.Items('b'))));
  finally
    Loaded.Free;
    History.Free;
  end;
end;

procedure TAtlasDebugDialogCompletionTests.HistoryLimitAndRemove;
var
  History: TAtlasExpressionHistory;
  Index: Integer;
begin
  History := TAtlasExpressionHistory.Create(50);
  try
    Assert.AreEqual(50, History.Limit);
    for Index := 1 to 60 do
      History.Add('P', 'W' + IntToStr(Index));
    Assert.AreEqual(50, Integer(Length(History.Items('P'))));
    Assert.IsTrue(History.Remove('P', ' W60 '));
    Assert.AreEqual('W59', History.Items('P')[0]);
    Assert.IsFalse(History.Remove('P', 'W60'), 'schon weg');
    Assert.IsFalse(History.Remove('Q', 'W1'), 'anderes Projekt');
  finally
    History.Free;
  end;
end;

end.
