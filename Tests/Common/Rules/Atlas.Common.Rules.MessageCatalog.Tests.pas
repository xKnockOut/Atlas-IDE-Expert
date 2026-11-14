unit Atlas.Common.Rules.MessageCatalog.Tests;

// Tests für die Erklärungen der Compilermeldungen (#54).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMessageCatalogTests = class
  public
    [Test]
    procedure FindsE2003InBothLanguages;
    [Test]
    procedure EveryEntryIsComplete;
    [Test]
    procedure UnknownCodeIsNotFound;
    [Test]
    procedure CodeOfReadsCompilerOutput;
    [Test]
    procedure DocWikiSearchesTheRelease;
    [Test]
    procedure SettingsCatalogListsMessages;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Rules.MessageCatalog,
  Atlas.Common.Lsp.SettingsCommands;

procedure TMessageCatalogTests.FindsE2003InBothLanguages;
var
  mGerman, mEnglish: TCompilerMessageEntry;
begin
  Assert.IsTrue(TCompilerMessageCatalog.TryFind('e2003', TTextLanguage.German, mGerman));
  Assert.IsTrue(TCompilerMessageCatalog.TryFind('E2003', TTextLanguage.English, mEnglish));
  Assert.AreEqual('E2003', mGerman.Code);
  Assert.AreEqual('Undeklarierter Bezeichner', mGerman.Name);
  Assert.AreEqual('Undeclared identifier', mEnglish.Name);
  Assert.AreNotEqual(mGerman.Cause, mEnglish.Cause);
  // Das Beispiel ist Code und in beiden Sprachen gleich.
  Assert.AreEqual(mGerman.Good, mEnglish.Good);
end;

procedure TMessageCatalogTests.EveryEntryIsComplete;
var
  mLanguage: TTextLanguage;
  mEntry: TCompilerMessageEntry;
  mCount: Integer;
begin
  for mLanguage := Low(TTextLanguage) to High(TTextLanguage) do
  begin
    mCount := 0;
    for mEntry in TCompilerMessageCatalog.Entries(mLanguage) do
    begin
      Inc(mCount);
      Assert.AreEqual(mEntry.Code, TCompilerMessageCatalog.CodeOf(mEntry.Code), mEntry.Code);
      Assert.IsTrue((mEntry.Name <> '') and (mEntry.Description <> '') and (mEntry.Cause <> ''), mEntry.Code);
      Assert.IsTrue((mEntry.Bad <> '') and (mEntry.Good <> ''), mEntry.Code);
    end;
    // Abnahme #54: mindestens die 20 häufigsten Meldungen.
    Assert.IsTrue(mCount >= 20, IntToStr(mCount));
  end;
end;

procedure TMessageCatalogTests.UnknownCodeIsNotFound;
var
  mEntry: TCompilerMessageEntry;
begin
  Assert.IsFalse(TCompilerMessageCatalog.TryFind('E9999', TTextLanguage.German, mEntry));
  Assert.IsFalse(TCompilerMessageCatalog.TryFind('unused-local', TTextLanguage.German, mEntry));
  Assert.AreEqual('', mEntry.Code);
end;

procedure TMessageCatalogTests.CodeOfReadsCompilerOutput;
begin
  Assert.AreEqual('E2003', TCompilerMessageCatalog.CodeOf('E2003'));
  Assert.AreEqual('E2003', TCompilerMessageCatalog.CodeOf('[dcc32 Fehler] Main.pas(12): E2003 Undeklarierter ' +
    'Bezeichner: ''Wert'''));
  Assert.AreEqual('W1036', TCompilerMessageCatalog.CodeOf('w1036 Variable ''X'' ist möglicherweise nicht ' +
    'initialisiert worden'));
  Assert.AreEqual('', TCompilerMessageCatalog.CodeOf('Keine Meldung'));
  Assert.AreEqual('', TCompilerMessageCatalog.CodeOf('E20031'));
  Assert.AreEqual('', TCompilerMessageCatalog.CodeOf('XE2003'));
end;

procedure TMessageCatalogTests.DocWikiSearchesTheRelease;
begin
  Assert.AreEqual('https://docwiki.embarcadero.com/RADStudio/Athens/e/index.php?search=E2003',
    TCompilerMessageCatalog.DocWikiUrl('e2003', '23.0'));
  Assert.AreEqual('https://docwiki.embarcadero.com/RADStudio/Florence/e/index.php?search=W1036',
    TCompilerMessageCatalog.DocWikiUrl('W1036', ''));
end;

procedure TMessageCatalogTests.SettingsCatalogListsMessages;
var
  mCatalog: TJSONObject;
  mArguments, mMessages: TJSONArray;
  mItem: TJSONValue;
  mFound: Boolean;
begin
  mCatalog := TJSONObject.Create;
  mArguments := TJSONArray.Create;
  try
    mArguments.Add('de');
    mArguments.Add('23.0');
    TLspSettingsCommands.AddMessages(mCatalog, mArguments);
    mMessages := mCatalog.GetValue('messages') as TJSONArray;
    Assert.IsTrue(mMessages.Count >= 20);
    mFound := False;
    for mItem in mMessages do
    begin
      if mItem.GetValue<string>('code') = 'E2003' then
      begin
        mFound := True;
        Assert.AreEqual('Undeklarierter Bezeichner', mItem.GetValue<string>('name'));
        Assert.AreNotEqual('', mItem.GetValue<string>('cause'));
        Assert.AreEqual('https://docwiki.embarcadero.com/RADStudio/Athens/e/index.php?search=E2003',
          mItem.GetValue<string>('docWiki'));
      end;
    end;
    Assert.IsTrue(mFound);
  finally
    mArguments.Free;
    mCatalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMessageCatalogTests);

end.
