unit Atlas.Core.Debug.Note.Tests;

// Debug-Notiz als Markdown (#582, #1276) aus gefälschten Debug-Daten ohne IDE:
// Kopf, Ort mit Ausschnitt und Marke, Aufrufstapel mit eigenem Code, letzte
// Exception, lokale Variablen und überwachte Ausdrücke aus einer Auswerteliste,
// die letzten Zeilen des Ereignisprotokolls und das Ausblenden von Werten
// geheimer Namen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugNoteTests = class
  public
    [Test]
    procedure MarkdownWithLocationStackAndException;
    /// <summary>Abnahme (#582): Eine Variable Password erscheint als ***.</summary>
    [Test]
    procedure SecretsAreMasked;
    [Test]
    procedure SecretNames;
    [Test]
    procedure ExcerptStaysInsideFile;
    [Test]
    procedure WithoutSourceOrException;
    [Test]
    procedure FileNameHasDateAndTime;
    [Test]
    procedure HistoryTextLimitsAndMasks;
    /// <summary>Abnahme (#582): lokale Variablen mit Teilen, eine Variable Password als ***.</summary>
    [Test]
    procedure LocalsAndWatchesInNote;
    [Test]
    procedure ValuesOfListShowsStatesAndParts;
    [Test]
    procedure LongValuesShortenedOnOneLine;
    [Test]
    procedure EventsTakeLastLinesMasked;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.Note;

/// <summary>Überschriften wie die deutsche Oberfläche (Atlas.UI.Debug.Note.Strings und .Exceptions.Strings).
/// </summary>
function GermanTexts: TAtlasDebugNoteTexts;
begin
  Result.Title := 'Debug-Notiz';
  Result.Project := 'Projekt';
  Result.Configuration := 'Konfiguration';
  Result.TargetPlatform := 'Plattform';
  Result.Time := 'Zeit';
  Result.Thread := 'Thread';
  Result.Location := 'Ort';
  Result.CallStack := 'Aufrufstapel';
  Result.LastException := 'Letzte Exception';
  Result.Count := '%d x an dieser Stelle';
  Result.NoLocation := 'Kein Halt mit Quelltext.';
  Result.Locals := 'Lokale Variablen';
  Result.Watches := 'Überwachte Ausdrücke';
  Result.Events := 'Ereignisprotokoll';
  Result.Unavailable := 'nicht auswertbar';
  Result.Pending := 'nicht ausgewertet';
end;

function SampleData: TAtlasDebugNoteData;
var
  mFrame: TAtlasDebugFrame;
begin
  Result := TAtlasDebugNoteData.Empty;
  Result.Project := 'C:\Projekte\Kasse\Kasse.dproj';
  Result.Configuration := 'Debug';
  Result.TargetPlatform := 'Win64';
  Result.Time := EncodeDateTime(2026, 10, 28, 14, 5, 9, 0);
  Result.Thread := 'Hauptthread 4711';
  Result.FileName := 'C:\Projekte\Kasse\Main.pas';
  Result.Line := 12;
  Result.Routine := 'Main.TMainForm.SaveClick';
  Result.Source := ['unit Main;', '', 'interface', '', 'implementation', '', 'procedure TMainForm.SaveClick;',
    'var', '  Password: string;', 'begin', '  Password := ''geheim'';', '  Save(Password);', 'end;', '', 'end.'];
  Result.SourceFirstLine := 1;
  mFrame := TAtlasDebugFrame.Create('Main.TMainForm.SaveClick(Self=$02A3F2C0)', 'C:\Projekte\Kasse\Main.pas', 12);
  mFrame.Own := True;
  Result.Frames := [mFrame, TAtlasDebugFrame.Create('Vcl.Controls.TControl.Click', '', 0)];
  Result.HasException := True;
  Result.Exception := TAtlasDebugException.Create(Result.Time, 'EConvertError', 'Token=abc123 ungültig', 4711,
    '').At('C:\Projekte\Kasse\Main.pas', 12, 'Main.TMainForm.SaveClick');
  Result.Exception.Count := 3;
end;

{ TAtlasDebugNoteTests }

procedure TAtlasDebugNoteTests.MarkdownWithLocationStackAndException;
var
  mText: string;
begin
  mText := TAtlasDebugNote.Markdown(SampleData, GermanTexts);
  Assert.IsTrue(mText.StartsWith('# Debug-Notiz'#13#10#13#10), mText);
  Assert.Contains(mText, '- **Projekt:** Kasse.dproj'#13#10);
  Assert.Contains(mText, '- **Konfiguration:** Debug'#13#10'- **Plattform:** Win64'#13#10);
  Assert.Contains(mText, '- **Zeit:** 2026-10-28 14:05:09'#13#10'- **Thread:** Hauptthread 4711'#13#10);
  Assert.Contains(mText, '## Ort'#13#10#13#10'`Main.pas:12` – `Main.TMainForm.SaveClick`'#13#10);
  // ±5 Zeilen, die Haltzeile mit Marke, Nummern rechtsbündig.
  Assert.Contains(mText, '```pascal'#13#10'   7 procedure TMainForm.SaveClick;'#13#10);
  Assert.Contains(mText, '> 12   Save(Password);'#13#10);
  Assert.Contains(mText, '  15 end.'#13#10'```'#13#10);
  Assert.DoesNotContain(mText, '   6 ');
  Assert.Contains(mText, '## Aufrufstapel'#13#10#13#10 +
    '- **`Main.TMainForm.SaveClick(Self=$02A3F2C0)` (Main.pas:12)**'#13#10 +
    '- `Vcl.Controls.TControl.Click`'#13#10);
  Assert.Contains(mText, '## Letzte Exception'#13#10#13#10'**EConvertError**: Token=*** ungültig'#13#10);
  Assert.Contains(mText, '3 x an dieser Stelle');
end;

procedure TAtlasDebugNoteTests.SecretsAreMasked;
var
  mText: string;
begin
  mText := TAtlasDebugNote.Markdown(SampleData, GermanTexts);
  Assert.Contains(mText, '  Password := ***;');
  Assert.DoesNotContain(mText, 'geheim');
  Assert.DoesNotContain(mText, 'abc123');
  Assert.AreEqual('Password = ***', TAtlasDebugNote.Redact('Password = "a b c"'));
  Assert.AreEqual('FApiKey: ***, Name: Max', TAtlasDebugNote.Redact('FApiKey: 1234, Name: Max'));
  Assert.AreEqual('db_password=***;user=sa', TAtlasDebugNote.Redact('db_password=s3cr3t;user=sa'));
  // Ohne Zuweisung bleibt der Text.
  Assert.AreEqual('Password vergessen', TAtlasDebugNote.Redact('Password vergessen'));
  Assert.AreEqual('Save(Password);', TAtlasDebugNote.Redact('Save(Password);'));
  // Im Code ist „Name: Typ“ eine Deklaration.
  Assert.AreEqual('  Password: string;', TAtlasDebugNote.RedactCode('  Password: string;'));
  Assert.Contains(TAtlasDebugNote.Markdown(SampleData, GermanTexts), '   9   Password: string;');
end;

procedure TAtlasDebugNoteTests.SecretNames;
begin
  Assert.IsTrue(TAtlasDebugNote.IsSecretName('Password'));
  Assert.IsTrue(TAtlasDebugNote.IsSecretName('FUserPasswort'));
  Assert.IsTrue(TAtlasDebugNote.IsSecretName('client_secret'));
  Assert.IsTrue(TAtlasDebugNote.IsSecretName('AccessToken'));
  Assert.IsTrue(TAtlasDebugNote.IsSecretName('API-Key'));
  Assert.IsFalse(TAtlasDebugNote.IsSecretName('UserName'));
  Assert.IsFalse(TAtlasDebugNote.IsSecretName('Count'));
end;

procedure TAtlasDebugNoteTests.ExcerptStaysInsideFile;
var
  mLines: TArray<string>;
  mStart: Integer;
begin
  mLines := TAtlasDebugNote.Excerpt(['a', 'b', 'c', 'd'], 1, 2, 5, mStart);
  Assert.AreEqual(1, mStart);
  Assert.AreEqual(4, Integer(Length(mLines)));
  // Ausschnitt ab Zeile 10.
  mLines := TAtlasDebugNote.Excerpt(['j', 'k', 'l', 'm', 'n'], 10, 14, 1, mStart);
  Assert.AreEqual(13, mStart);
  Assert.AreEqual('m', mLines[0]);
  Assert.AreEqual(2, Integer(Length(mLines)));
  // Zeile außerhalb: nichts.
  mLines := TAtlasDebugNote.Excerpt(['a'], 1, 5, 5, mStart);
  Assert.AreEqual(0, Integer(Length(mLines)));
end;

procedure TAtlasDebugNoteTests.WithoutSourceOrException;
var
  mData: TAtlasDebugNoteData;
  mText: string;
begin
  mData := TAtlasDebugNoteData.Empty;
  mData.Project := 'Kasse.dproj';
  mText := TAtlasDebugNote.Markdown(mData, GermanTexts);
  Assert.Contains(mText, '## Ort'#13#10#13#10'Kein Halt mit Quelltext.'#13#10);
  Assert.DoesNotContain(mText, '## Aufrufstapel');
  Assert.DoesNotContain(mText, '## Letzte Exception');
  Assert.DoesNotContain(mText, 'Konfiguration');
end;

procedure TAtlasDebugNoteTests.FileNameHasDateAndTime;
begin
  Assert.AreEqual('debug-notiz-2026-10-28-1405.md', TAtlasDebugNote.FileName('debug-notiz',
    EncodeDateTime(2026, 10, 28, 14, 5, 9, 0)));
  Assert.AreEqual('debug-note-2026-10-28-1405.md', TAtlasDebugNote.FileName('debug-note',
    EncodeDateTime(2026, 10, 28, 14, 5, 9, 0)));
end;

procedure TAtlasDebugNoteTests.HistoryTextLimitsAndMasks;
var
  mExceptions: TAtlasDebugExceptions;
  mText: string;
begin
  mExceptions := [TAtlasDebugException.Create(Now, 'EAccessViolation', 'Zugriffsverletzung', 1, ''),
    TAtlasDebugException.Create(Now, 'EConvertError', 'Password=geheim', 2, '').At('Main.pas', 7, 'Main.Save'),
    TAtlasDebugException.Create(Now, 'EThird', '', 3, '')];
  mText := TAtlasDebugNote.HistoryText(mExceptions, 2);
  Assert.IsTrue(mText.StartsWith('EAccessViolation: Zugriffsverletzung'), mText);
  Assert.Contains(mText, #13#10#13#10'EConvertError: Password=***');
  Assert.DoesNotContain(mText, 'geheim');
  Assert.DoesNotContain(mText, 'EThird');
  Assert.IsTrue(mText.EndsWith(#13#10), mText);
  Assert.AreEqual('', TAtlasDebugNote.HistoryText(nil, 5));
end;

procedure TAtlasDebugNoteTests.LocalsAndWatchesInNote;
var
  mData: TAtlasDebugNoteData;
  mText: string;
begin
  mData := SampleData;
  mData.Locals := [TAtlasDebugNoteValue.Create('Count', '3', 0, False),
    TAtlasDebugNoteValue.Create('Password', '''geheim''', 0, True),
    TAtlasDebugNoteValue.Create('Kunde', '(Name: ''Meier''; Nr: 7)', 0, False),
    TAtlasDebugNoteValue.Create('Name', '''Meier''', 1, False)];
  mData.Watches := [TAtlasDebugNoteValue.Create('FList.Count', '12', 0, False)];
  mText := TAtlasDebugNote.Markdown(mData, GermanTexts);
  Assert.Contains(mText, '## Lokale Variablen' + #13#10#13#10 + '- `Count` = `3`' + #13#10);
  Assert.Contains(mText, '- `Password` = `***`');
  Assert.DoesNotContain(mText, '''geheim''');
  Assert.Contains(mText, '  - `Name` = `''Meier''`');
  Assert.Contains(mText, '## Überwachte Ausdrücke' + #13#10#13#10 + '- `FList.Count` = `12`');
  // Reihenfolge: Aufrufstapel, Variablen, Ausdrücke, Exception.
  Assert.IsTrue(Pos('## Aufrufstapel', mText) < Pos('## Lokale Variablen', mText), 'nach dem Stapel');
  Assert.IsTrue(Pos('## Überwachte Ausdrücke', mText) < Pos('## Letzte Exception', mText), 'vor der Exception');
  // Ohne Werte keine Abschnitte.
  mText := TAtlasDebugNote.Markdown(SampleData, GermanTexts);
  Assert.DoesNotContain(mText, '## Lokale Variablen');
  Assert.DoesNotContain(mText, '## Überwachte Ausdrücke');
end;

procedure TAtlasDebugNoteTests.ValuesOfListShowsStatesAndParts;
var
  mList: TAtlasEvalList;
  mValues: TAtlasDebugNoteValues;
  mTexts: TAtlasDebugNoteTexts;
begin
  mTexts := GermanTexts;
  mList := TAtlasEvalList.Create;
  try
    mList.Replace(['Count', 'FToken', 'Kunde', 'Fehlt', 'Offen']);
    mList.SetResult(mList.Roots[0], True, '3');
    mList.SetResult(mList.Roots[1], True, '(Wert: ''abc''; Ablauf: 5)');
    mList.SetResult(mList.Roots[2], True, '(Name: ''Meier''; Nr: 7)');
    mList.Roots[3].State := TAtlasEvalState.Unavailable;
    mValues := TAtlasDebugNote.ValuesOf(mList, mTexts);
  finally
    mList.Free;
  end;
  Assert.AreEqual(9, Integer(Length(mValues)));
  Assert.AreEqual('Count', mValues[0].Name);
  Assert.AreEqual('3', mValues[0].Value);
  Assert.AreEqual(0, mValues[0].Level);
  // Teile unter einem geheimen Namen sind selbst geheim.
  Assert.IsTrue(mValues[1].Secret, 'FToken');
  Assert.AreEqual('Wert', mValues[2].Name);
  Assert.AreEqual(1, mValues[2].Level);
  Assert.IsTrue(mValues[2].Secret, 'Teil von FToken');
  Assert.AreEqual('Kunde', mValues[4].Name);
  Assert.IsFalse(mValues[5].Secret, 'Teil von Kunde');
  Assert.AreEqual('Nr', mValues[6].Name);
  Assert.AreEqual(mTexts.Unavailable, mValues[7].Value);
  Assert.AreEqual(mTexts.Pending, mValues[8].Value);
  Assert.AreEqual(0, Integer(Length(TAtlasDebugNote.ValuesOf(nil, mTexts))), 'ohne Liste');
end;

procedure TAtlasDebugNoteTests.LongValuesShortenedOnOneLine;
var
  mData: TAtlasDebugNoteData;
  mText: string;
begin
  mData := TAtlasDebugNoteData.Empty;
  mData.Locals := [TAtlasDebugNoteValue.Create('Text', StringOfChar('x', 500), 0, False),
    TAtlasDebugNoteValue.Create('Zeilen', 'a' + #13#10 + 'b', 0, False),
    TAtlasDebugNoteValue.Create('Tick', 'a`b', 0, False),
    TAtlasDebugNoteValue.Create('Leer', '', 0, False)];
  mText := TAtlasDebugNote.Markdown(mData, GermanTexts);
  Assert.Contains(mText, '- `Text` = `' + StringOfChar('x', TAtlasDebugNote.cMaxValueLength - 1) + '…`');
  Assert.Contains(mText, '- `Zeilen` = `a b`');
  Assert.Contains(mText, '- `Tick` = `` a`b ``');
  Assert.Contains(mText, '- `Leer` = –');
end;

procedure TAtlasDebugNoteTests.EventsTakeLastLinesMasked;
var
  mData: TAtlasDebugNoteData;
  mText: string;
  mIndex: Integer;
begin
  mData := TAtlasDebugNoteData.Empty;
  for mIndex := 1 to TAtlasDebugNote.cMaxEvents + 5 do
  begin
    mData.Events := mData.Events + ['Zeile ' + IntToStr(mIndex)];
  end;
  mData.Events := mData.Events + ['Anmeldung Password=hunter2'];
  mText := TAtlasDebugNote.Markdown(mData, GermanTexts);
  Assert.Contains(mText, '## Ereignisprotokoll' + #13#10#13#10 + '```text' + #13#10 + 'Zeile 7' + #13#10);
  Assert.DoesNotContain(mText, 'Zeile 6' + #13#10);
  Assert.Contains(mText, 'Anmeldung Password=***' + #13#10 + '```');
  Assert.DoesNotContain(mText, 'hunter2');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugNoteTests);

end.
