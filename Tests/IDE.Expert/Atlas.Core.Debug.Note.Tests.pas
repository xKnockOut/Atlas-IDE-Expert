unit Atlas.Core.Debug.Note.Tests;

// Debug-Notiz als Markdown (#582, #1276) aus gefälschten Debug-Daten ohne IDE:
// Kopf, Ort mit Ausschnitt und Marke, Aufrufstapel mit eigenem Code, letzte
// Exception und das Ausblenden von Werten geheimer Namen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.Note;

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
  Result.Exception := TAtlasDebugException.Create(Result.Time, 'EConvertError', 'Token=abc123 ungültig', 4711, '',
    'C:\Projekte\Kasse\Main.pas', 12, 'Main.TMainForm.SaveClick');
  Result.Exception.Count := 3;
end;

{ TAtlasDebugNoteTests }

procedure TAtlasDebugNoteTests.MarkdownWithLocationStackAndException;
var
  mText: string;
begin
  mText := TAtlasDebugNote.Markdown(SampleData, TAtlasDebugNoteTexts.Default);
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
  mText := TAtlasDebugNote.Markdown(SampleData, TAtlasDebugNoteTexts.Default);
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
  Assert.Contains(TAtlasDebugNote.Markdown(SampleData, TAtlasDebugNoteTexts.Default), '   9   Password: string;');
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
  mText := TAtlasDebugNote.Markdown(mData, TAtlasDebugNoteTexts.Default);
  Assert.Contains(mText, '## Ort'#13#10#13#10'Kein Halt mit Quelltext.'#13#10);
  Assert.DoesNotContain(mText, '## Aufrufstapel');
  Assert.DoesNotContain(mText, '## Letzte Exception');
  Assert.DoesNotContain(mText, 'Konfiguration');
end;

procedure TAtlasDebugNoteTests.FileNameHasDateAndTime;
begin
  Assert.AreEqual('debug-notiz-2026-10-28-1405.md', TAtlasDebugNote.FileName(EncodeDateTime(2026, 10, 28, 14, 5,
    9, 0)));
end;

procedure TAtlasDebugNoteTests.HistoryTextLimitsAndMasks;
var
  mExceptions: TAtlasDebugExceptions;
  mText: string;
begin
  mExceptions := [TAtlasDebugException.Create(Now, 'EAccessViolation', 'Zugriffsverletzung', 1, '', '', 0, ''),
    TAtlasDebugException.Create(Now, 'EConvertError', 'Password=geheim', 2, '', 'Main.pas', 7, 'Main.Save'),
    TAtlasDebugException.Create(Now, 'EThird', '', 3, '', '', 0, '')];
  mText := TAtlasDebugNote.HistoryText(mExceptions, 2);
  Assert.IsTrue(mText.StartsWith('EAccessViolation: Zugriffsverletzung'), mText);
  Assert.Contains(mText, #13#10#13#10'EConvertError: Password=***');
  Assert.DoesNotContain(mText, 'geheim');
  Assert.DoesNotContain(mText, 'EThird');
  Assert.IsTrue(mText.EndsWith(#13#10), mText);
  Assert.AreEqual('', TAtlasDebugNote.HistoryText(nil, 5));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugNoteTests);

end.
