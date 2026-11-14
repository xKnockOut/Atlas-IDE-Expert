unit Atlas.Core.Build.Messages.Tests;

// Tests für die Compilermeldungen der IDE (#528), mit aufgezeichneten Werten
// aus dem Meldungsfenster von RAD Studio 13 (deutsch).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCompilerMessagesTests = class
  public
    [Test]
    procedure SplitsCodeAndSeverity;
    [Test]
    procedure SeverityFromCodeWhenKindUnknown;
    [Test]
    procedure JsonSkipsInfo;
    [Test]
    procedure ResolvesFileNamesWithoutPath;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Build.Messages;

procedure TAtlasCompilerMessagesTests.SplitsCodeAndSeverity;
var
  mMessage: TAtlasCompilerMessage;
begin
  // So steht es im Meldungsfenster (TCompilerMsgLine): Kind, Message, Line, Column, FileName.
  mMessage := TAtlasCompilerMessages.FromIde('msgError', 'E2010 Inkompatible Typen: ''Integer'' und ''string''',
    'C:\P\MsgProbe.dpr', 9, 14);
  Assert.AreEqual('E2010', mMessage.Code);
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''string''', mMessage.Text);
  Assert.AreEqual(Ord(TAtlasCompilerSeverity.Error), Ord(mMessage.Severity));
  Assert.AreEqual(9, mMessage.Line);
  Assert.AreEqual(14, mMessage.Column);
  mMessage := TAtlasCompilerMessages.FromIde('msgHint', 'H2164 Variable ''Unbenutzt'' wurde deklariert, aber in ''MsgProbe'' nicht verwendet',
    'C:\P\MsgProbe.dpr', 7, 3);
  Assert.AreEqual('H2164', mMessage.Code);
  Assert.AreEqual(Ord(TAtlasCompilerSeverity.Hint), Ord(mMessage.Severity));
  mMessage := TAtlasCompilerMessages.FromIde('msgInfo', 'dcc32 Befehlszeile für "MsgProbe.dpr"', '', 1, 0);
  Assert.AreEqual('', mMessage.Code);
  Assert.AreEqual(Ord(TAtlasCompilerSeverity.Info), Ord(mMessage.Severity));
end;

procedure TAtlasCompilerMessagesTests.SeverityFromCodeWhenKindUnknown;
begin
  Assert.AreEqual(Ord(TAtlasCompilerSeverity.Warning),
    Ord(TAtlasCompilerMessages.FromIde('msgSonstwas', 'W1036 Variable ''X'' ist möglicherweise nicht initialisiert', '', 1, 1).Severity));
  Assert.AreEqual(Ord(TAtlasCompilerSeverity.Fatal),
    Ord(TAtlasCompilerMessages.FromIde('', 'F2063 Verwendete Unit ''X'' kann nicht compiliert werden', '', 1, 1).Severity));
end;

procedure TAtlasCompilerMessagesTests.ResolvesFileNamesWithoutPath;
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mDir: string;
begin
  mDir := TPath.Combine(TPath.GetTempPath, 'AtlasResolve');
  TDirectory.CreateDirectory(mDir);
  TFile.WriteAllText(TPath.Combine(mDir, 'ImOrdner.pas'), 'unit ImOrdner;');
  try
    SetLength(mMessages, 5);
    mMessages[0].FileName := 'Gallery.Main.pas';
    mMessages[1].FileName := 'C:\X\Abs.pas';
    mMessages[2].FileName := 'Fehlt.pas';
    mMessages[3].FileName := 'sub/gallery.main.pas';
    mMessages[4].FileName := 'ImOrdner.pas';
    mMessages := TAtlasCompilerMessages.Resolve(mMessages, TPath.Combine(mDir, 'P.dproj'),
      ['C:\P\Other.pas', 'C:\P\Sub\Gallery.Main.pas']);
    Assert.AreEqual('C:\P\Sub\Gallery.Main.pas', mMessages[0].FileName, 'bekannte Datei');
    Assert.AreEqual('C:\X\Abs.pas', mMessages[1].FileName, 'voller Pfad bleibt');
    Assert.AreEqual('Fehlt.pas', mMessages[2].FileName, 'nicht gefunden: bleibt');
    Assert.AreEqual('C:\P\Sub\Gallery.Main.pas', mMessages[3].FileName, 'Teilpfad mit /');
    Assert.AreEqual(TPath.Combine(mDir, 'ImOrdner.pas'), mMessages[4].FileName, 'Projektordner');
  finally
    TDirectory.Delete(mDir, True);
  end;
end;

procedure TAtlasCompilerMessagesTests.JsonSkipsInfo;
var
  mJson: TJSONObject;
begin
  mJson := TAtlasCompilerMessages.ToJson([
    TAtlasCompilerMessages.FromIde('msgInfo', 'brcc32 Befehlszeile', '', 1, 0),
    TAtlasCompilerMessages.FromIde('msgError', 'E2003 Undeklarierter Bezeichner: ''Gibtsnicht''', 'C:\P\A.dpr', 10, 11)],
    'C:\P\A.dproj', 'Win32', False);
  try
    Assert.AreEqual('{"project":"C:\\P\\A.dproj","platform":"Win32","success":false,"messages":[{"file":"C:\\P\\A.dpr",' +
      '"line":10,"column":11,"severity":"error","code":"E2003","text":"Undeklarierter Bezeichner: ''Gibtsnicht''"}]}',
      mJson.ToJSON);
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCompilerMessagesTests);

end.