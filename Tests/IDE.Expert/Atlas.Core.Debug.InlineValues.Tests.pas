unit Atlas.Core.Debug.InlineValues.Tests;

// Werte im Editor beim Debuggen (#508): je Zeile jeder Name einmal und höchstens
// n Werte, nur schlichte Bezeichner, Auswertung ab der Zeile des Halts,
// lesbare Datumswerte, Kürzen, Hervorheben geänderter Werte nur in derselben
// Routine, Fortsetzen leert die Anzeige.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Debug.InlineValues;

type
  [TestFixture]
  TAtlasInlineValuesTests = class
  private
    FValues: TAtlasInlineValues;
    /// <summary>Alle offenen Namen in Auswertungsreihenfolge, mit Leerzeichen getrennt; setzt jeden auf
    /// AValue (Name + AValue).</summary>
    function EvaluateAll(const ASuffix: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure GroupsPerLineWithLimit;
    [Test]
    procedure OnlyPlainIdentifiers;
    [Test]
    procedure EvaluatesStoppedLineFirst;
    [Test]
    procedure FailedValuesAreHidden;
    [Test]
    procedure ShowsDatesAndShortensLongValues;
    [Test]
    procedure HighlightsChangedValuesInSameRoutine;
    [Test]
    procedure ClearHidesValues;
  end;

implementation

uses
  System.SysUtils;

function Refs: TAtlasInlineValueRefs;
begin
  Result := TAtlasInlineValueRefs.Create(
    TAtlasInlineValueRef.Create(10, 2, 'Count', 'Integer'),
    TAtlasInlineValueRef.Create(12, 2, 'Name', 'string'),
    TAtlasInlineValueRef.Create(12, 10, 'count', 'Integer'),
    TAtlasInlineValueRef.Create(12, 20, 'Name', 'string'),
    TAtlasInlineValueRef.Create(14, 2, 'I', 'Integer'),
    TAtlasInlineValueRef.Create(14, 8, 'Count', 'Integer'));
end;

{ TAtlasInlineValuesTests }

procedure TAtlasInlineValuesTests.Setup;
begin
  FValues := TAtlasInlineValues.Create;
end;

procedure TAtlasInlineValuesTests.TearDown;
begin
  FreeAndNil(FValues);
end;

function TAtlasInlineValuesTests.EvaluateAll(const ASuffix: string): string;
var
  Name: string;
begin
  Result := '';
  while FValues.NextPending(Name) do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Name;
    FValues.Put(Name, Name + ASuffix, True);
  end;
end;

procedure TAtlasInlineValuesTests.GroupsPerLineWithLimit;
begin
  FValues.Start('C:\P\A.pas', 'C:\P\A.pas|TA.Lauf', 14, Refs, 5);
  EvaluateAll('1');
  Assert.AreEqual('Count = Count1', TAtlasInlineValues.LineText(FValues.Line('C:\P\A.pas', 10)));
  Assert.AreEqual('Name = Name1, Count = Count1', TAtlasInlineValues.LineText(FValues.Line('c:\p\a.pas', 12)),
    'jeder Name einmal je Zeile, Groß-/Kleinschreibung egal');
  Assert.AreEqual(0, Integer(Length(FValues.Line('C:\P\B.pas', 12))), 'andere Datei');
  Assert.AreEqual(0, Integer(Length(FValues.Line('C:\P\A.pas', 11))), 'Zeile ohne Bezeichner');
  FValues.Start('C:\P\A.pas', 'C:\P\A.pas|TA.Lauf', 14, Refs, 1);
  EvaluateAll('1');
  Assert.AreEqual('Name = Name1', TAtlasInlineValues.LineText(FValues.Line('C:\P\A.pas', 12)), 'höchstens 1 je Zeile');
end;

procedure TAtlasInlineValuesTests.OnlyPlainIdentifiers;
begin
  Assert.IsTrue(TAtlasInlineValues.IsPlainIdentifier('FCount'));
  Assert.IsTrue(TAtlasInlineValues.IsPlainIdentifier('_Größe'));
  Assert.IsFalse(TAtlasInlineValues.IsPlainIdentifier('GetSize()'), 'Aufruf');
  Assert.IsFalse(TAtlasInlineValues.IsPlainIdentifier('Liste.Count'), 'Mitglied');
  Assert.IsFalse(TAtlasInlineValues.IsPlainIdentifier('P^'), 'Dereferenzierung');
  Assert.IsFalse(TAtlasInlineValues.IsPlainIdentifier('1X'));
  Assert.IsFalse(TAtlasInlineValues.IsPlainIdentifier('begin'), 'reserviertes Wort');
  Assert.IsFalse(TAtlasInlineValues.IsPlainIdentifier(''));
  FValues.Start('C:\P\A.pas', 'x', 3, TAtlasInlineValueRefs.Create(TAtlasInlineValueRef.Create(3, 0, 'Lade()', ''),
    TAtlasInlineValueRef.Create(3, 9, 'Wert', '')), 5);
  Assert.AreEqual('Wert', EvaluateAll(''), 'Aufruf nie ausgewertet');
end;

procedure TAtlasInlineValuesTests.EvaluatesStoppedLineFirst;
begin
  FValues.Start('C:\P\A.pas', 'x', 14, Refs, 5);
  Assert.AreEqual('I Count Name', EvaluateAll('1'), 'Zeile des Halts, dann die nächste darüber');
  Assert.IsTrue(FValues.Active);
  Assert.AreEqual(14, FValues.StoppedLine);
end;

procedure TAtlasInlineValuesTests.FailedValuesAreHidden;
var
  Name: string;
begin
  FValues.Start('C:\P\A.pas', 'x', 12, Refs, 5);
  Assert.IsTrue(FValues.NextPending(Name));
  Assert.AreEqual('Name', Name);
  FValues.Put('Name', 'Symbol wurde wegoptimiert', False);
  Assert.IsTrue(FValues.NextPending(Name));
  Assert.AreEqual('Count', Name, 'Schreibweise der ersten Stelle im Text (Zeile 10)');
  Assert.AreEqual(0, Integer(Length(FValues.Line('C:\P\A.pas', 12))), 'Count steht noch aus, Name fehlt');
  FValues.Put('COUNT', '3', True);
  Assert.AreEqual('Count = 3', TAtlasInlineValues.LineText(FValues.Line('C:\P\A.pas', 12)));
end;

procedure TAtlasInlineValuesTests.ShowsDatesAndShortensLongValues;
var
  Long: string;
begin
  Assert.AreEqual('2026-10-23', TAtlasInlineValues.Display('TDateTime', '46318'));
  Assert.AreEqual('2026-10-23 12:00:00', TAtlasInlineValues.Display('TDateTime', '46318.5'));
  Assert.AreEqual('2026-10-23 12:00:00', TAtlasInlineValues.Display('System.TDateTime', '46318,5'), 'Komma');
  Assert.AreEqual('2026-10-23', TAtlasInlineValues.Display('TDate', '46318.75'));
  Assert.AreEqual('18:00:00', TAtlasInlineValues.Display('TTime', '0.75'));
  Assert.AreEqual('kein Wert', TAtlasInlineValues.Display('TDateTime', 'kein Wert'), 'keine Zahl: unverändert');
  Assert.AreEqual('1E300', TAtlasInlineValues.Display('TDateTime', '1E300'), 'außerhalb der Datumsgrenzen');
  Assert.AreEqual('[fsBold, fsItalic]', TAtlasInlineValues.Display('TFontStyles', '[fsBold, fsItalic]'));
  Assert.AreEqual('nil', TAtlasInlineValues.Display('TObject', ' nil '));
  Assert.AreEqual('''a b''', TAtlasInlineValues.Display('string', '''a'#13#10'b'''), 'eine Zeile');
  Long := StringOfChar('x', 100);
  Assert.AreEqual(StringOfChar('x', TAtlasInlineValues.MaxValueLength) + ' …',
    TAtlasInlineValues.Display('string', Long));
end;

procedure TAtlasInlineValuesTests.HighlightsChangedValuesInSameRoutine;
var
  Items: TAtlasInlineValueItems;
begin
  FValues.Start('C:\P\A.pas', 'C:\P\A.pas|TA.Lauf', 14, Refs, 5);
  EvaluateAll('1');
  Items := FValues.Line('C:\P\A.pas', 14);
  Assert.IsFalse(Items[0].Changed, 'erster Halt: nichts hervorgehoben');
  FValues.Clear;
  FValues.Start('C:\P\A.pas', 'C:\P\A.pas|TA.Lauf', 14, Refs, 5);
  FValues.Put('I', 'I2', True);
  FValues.Put('Count', 'Count1', True);
  Items := FValues.Line('C:\P\A.pas', 14);
  Assert.AreEqual('I = I2, Count = Count1', TAtlasInlineValues.LineText(Items));
  Assert.IsTrue(Items[0].Changed, 'nach F8 geändert');
  Assert.IsFalse(Items[1].Changed, 'gleich geblieben');
  // Ohne Clear (Halt ohne Fortsetzen dazwischen) zählt der letzte Stand ebenso.
  FValues.Start('C:\P\A.pas', 'C:\P\A.pas|TA.Lauf', 14, Refs, 5);
  FValues.Put('I', 'I2', True);
  Assert.IsFalse(FValues.Line('C:\P\A.pas', 14)[0].Changed);
  // Andere Routine: gleiche Namen, aber nichts hervorgehoben.
  FValues.Start('C:\P\A.pas', 'C:\P\A.pas|TA.Andere', 14, Refs, 5);
  FValues.Put('I', 'I3', True);
  Assert.IsFalse(FValues.Line('C:\P\A.pas', 14)[0].Changed, 'andere Routine');
  FValues.Reset;
  FValues.Start('C:\P\A.pas', 'C:\P\A.pas|TA.Andere', 14, Refs, 5);
  FValues.Put('I', 'I4', True);
  Assert.IsFalse(FValues.Line('C:\P\A.pas', 14)[0].Changed, 'nach Reset nichts gemerkt');
end;

procedure TAtlasInlineValuesTests.ClearHidesValues;
var
  Name: string;
begin
  FValues.Start('C:\P\A.pas', 'x', 14, Refs, 5);
  EvaluateAll('1');
  FValues.Clear;
  Assert.IsFalse(FValues.Active);
  Assert.IsFalse(FValues.NextPending(Name));
  Assert.AreEqual(0, Integer(Length(FValues.Line('C:\P\A.pas', 14))));
  Assert.AreEqual('', FValues.FileName);
end;

end.
