unit Argus.Core.Build.Messages.Tests;

// Tests für die Compilermeldungen der IDE (#528), mit aufgezeichneten Werten
// aus dem Meldungsfenster von RAD Studio 13 (deutsch).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusCompilerMessagesTests = class
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
  Argus.Core.Build.Messages;

procedure TArgusCompilerMessagesTests.SplitsCodeAndSeverity;
var
  Message: TArgusCompilerMessage;
begin
  // So steht es im Meldungsfenster (TCompilerMsgLine): Kind, Message, Line, Column, FileName.
  Message := TArgusCompilerMessages.FromIde('msgError', 'E2010 Inkompatible Typen: ''Integer'' und ''string''',
    'C:\P\MsgProbe.dpr', 9, 14);
  Assert.AreEqual('E2010', Message.Code);
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''string''', Message.Text);
  Assert.AreEqual(Ord(TArgusCompilerSeverity.Error), Ord(Message.Severity));
  Assert.AreEqual(9, Message.Line);
  Assert.AreEqual(14, Message.Column);
  Message := TArgusCompilerMessages.FromIde('msgHint', 'H2164 Variable ''Unbenutzt'' wurde deklariert, aber in ''MsgProbe'' nicht verwendet',
    'C:\P\MsgProbe.dpr', 7, 3);
  Assert.AreEqual('H2164', Message.Code);
  Assert.AreEqual(Ord(TArgusCompilerSeverity.Hint), Ord(Message.Severity));
  Message := TArgusCompilerMessages.FromIde('msgInfo', 'dcc32 Befehlszeile für "MsgProbe.dpr"', '', 1, 0);
  Assert.AreEqual('', Message.Code);
  Assert.AreEqual(Ord(TArgusCompilerSeverity.Info), Ord(Message.Severity));
end;

procedure TArgusCompilerMessagesTests.SeverityFromCodeWhenKindUnknown;
begin
  Assert.AreEqual(Ord(TArgusCompilerSeverity.Warning),
    Ord(TArgusCompilerMessages.FromIde('msgSonstwas', 'W1036 Variable ''X'' ist möglicherweise nicht initialisiert', '', 1, 1).Severity));
  Assert.AreEqual(Ord(TArgusCompilerSeverity.Fatal),
    Ord(TArgusCompilerMessages.FromIde('', 'F2063 Verwendete Unit ''X'' kann nicht compiliert werden', '', 1, 1).Severity));
end;

procedure TArgusCompilerMessagesTests.ResolvesFileNamesWithoutPath;
var
  Messages: TArray<TArgusCompilerMessage>;
  Dir: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'ArgusResolve');
  TDirectory.CreateDirectory(Dir);
  TFile.WriteAllText(TPath.Combine(Dir, 'ImOrdner.pas'), 'unit ImOrdner;');
  try
    SetLength(Messages, 5);
    Messages[0].FileName := 'Gallery.Main.pas';
    Messages[1].FileName := 'C:\X\Abs.pas';
    Messages[2].FileName := 'Fehlt.pas';
    Messages[3].FileName := 'sub/gallery.main.pas';
    Messages[4].FileName := 'ImOrdner.pas';
    Messages := TArgusCompilerMessages.Resolve(Messages, TPath.Combine(Dir, 'P.dproj'),
      ['C:\P\Other.pas', 'C:\P\Sub\Gallery.Main.pas']);
    Assert.AreEqual('C:\P\Sub\Gallery.Main.pas', Messages[0].FileName, 'bekannte Datei');
    Assert.AreEqual('C:\X\Abs.pas', Messages[1].FileName, 'voller Pfad bleibt');
    Assert.AreEqual('Fehlt.pas', Messages[2].FileName, 'nicht gefunden: bleibt');
    Assert.AreEqual('C:\P\Sub\Gallery.Main.pas', Messages[3].FileName, 'Teilpfad mit /');
    Assert.AreEqual(TPath.Combine(Dir, 'ImOrdner.pas'), Messages[4].FileName, 'Projektordner');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TArgusCompilerMessagesTests.JsonSkipsInfo;
var
  Json: TJSONObject;
begin
  Json := TArgusCompilerMessages.ToJson([
    TArgusCompilerMessages.FromIde('msgInfo', 'brcc32 Befehlszeile', '', 1, 0),
    TArgusCompilerMessages.FromIde('msgError', 'E2003 Undeklarierter Bezeichner: ''Gibtsnicht''', 'C:\P\A.dpr', 10, 11)],
    'C:\P\A.dproj', 'Win32', False);
  try
    Assert.AreEqual('{"project":"C:\\P\\A.dproj","platform":"Win32","success":false,"messages":[{"file":"C:\\P\\A.dpr",' +
      '"line":10,"column":11,"severity":"error","code":"E2003","text":"Undeklarierter Bezeichner: ''Gibtsnicht''"}]}',
      Json.ToJSON);
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusCompilerMessagesTests);

end.