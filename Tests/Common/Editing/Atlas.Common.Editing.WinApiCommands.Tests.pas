unit Atlas.Common.Editing.WinApiCommands.Tests;

// Tests für die Schnellbefehle /external, /exports, /oscheck und /olecheck (#321).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TWinApiCommandsTests = class
  public
    [Test]
    procedure ExternalDeclaration;
    [Test]
    procedure ExternalUsesConstantForThirdImport;
    [Test]
    procedure ExternalInClassFails;
    [Test]
    procedure ExportsAddsRoutines;
    [Test]
    procedure ExportsOutsideLibraryFails;
    [Test]
    procedure OsCheckWrapsBoolCall;
    [Test]
    procedure OsCheckAfterAssignment;
    [Test]
    procedure OsCheckWithoutBoolFails;
    [Test]
    procedure OleCheckWraps;
    [Test]
    procedure ResultsParse;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Common.Editing.SlashCommands.TestSupport,
  Atlas.Tests.SourceText;

const
  cRoutine =
    'unit U;'#10 +                             // 0
    'interface'#10 +                           // 1
    'uses Winapi.Windows, System.SysUtils;'#10 + // 2
    'implementation'#10 +                      // 3
    'procedure P(H: THandle);'#10 +            // 4
    'var'#10 +                                 // 5
    '  Ok: BOOL;'#10 +                         // 6
    'begin'#10 +                               // 7
    '  %s'#10 +                                // 8 Befehl
    '  %s'#10 +                                // 9 Anweisung
    'end;'#10 +                                // 10
    'end.';

{ TWinApiCommandsTests }

procedure TWinApiCommandsTests.ExternalDeclaration;
begin
  Assert.AreEqual('unit U;'#10'interface'#10'procedure MeineFunktion(); cdecl; external ''meine.dll'' delayed;'#10 +
    'implementation'#10'end.', TSlashTest.ExpandOrEmpty('unit U;'#10'interface'#10'/external MeineFunktion meine.dll delayed cdecl'#10 +
    'implementation'#10'end.', 2));
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty('unit U;'#10'interface'#10'/external MeineFunktion'#10'implementation'#10'end.', 2));
end;

procedure TWinApiCommandsTests.ExternalUsesConstantForThirdImport;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'procedure A; stdcall; external ''meine.dll'';'#10 +
    'procedure B; stdcall; external ''meine.dll'';'#10 +
    '/external C meine.dll'#10 +
    'implementation'#10 +
    'end.';
begin
  Assert.Contains(TSlashTest.ExpandOrEmpty(cSource, 4), 'const'#10'  MeineDll = ''meine.dll'';'#10#10 +
    'procedure C(); stdcall; external MeineDll;'#10'implementation');
end;

procedure TWinApiCommandsTests.ExternalInClassFails;
begin
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty('unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    /external A a.dll'#10 +
    '  end;'#10'implementation'#10'end.', 4));
end;

procedure TWinApiCommandsTests.ExportsAddsRoutines;
const
  cSource =
    'library L;'#10 +
    'procedure A; stdcall;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function B: Integer; cdecl;'#10 +
    'begin'#10 +
    '  Result := 0;'#10 +
    'end;'#10 +
    'procedure Intern;'#10 +
    'begin'#10 +
    'end;'#10 +
    '/exports'#10 +
    'begin'#10 +
    'end.';
var
  mText: string;
begin
  mText := TSlashTest.ExpandOrEmpty(cSource, 11);
  Assert.Contains(mText, 'end;'#10'exports'#10'  A,'#10'  B;'#10'begin'#10'end.');
  Assert.IsTrue(TTestSource.Parses(mText), mText);
  // Zweiter Aufruf: A und B stehen schon drin, Intern fehlt die Aufrufkonvention.
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty(StringReplace(mText, 'exports'#10, '/exports'#10'exports'#10, []), 11));
end;

procedure TWinApiCommandsTests.ExportsOutsideLibraryFails;
begin
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty('unit U;'#10'interface'#10'/exports'#10'implementation'#10'end.', 2));
end;

procedure TWinApiCommandsTests.OsCheckWrapsBoolCall;
var
  mText: string;
begin
  mText := TSlashTest.ExpandOrEmpty(Format(cRoutine, ['/oscheck', 'CloseHandle(H);']), 8);
  Assert.Contains(mText, 'begin'#10'  Win32Check(CloseHandle(H));'#10'end;');
end;

procedure TWinApiCommandsTests.OsCheckAfterAssignment;
var
  mText: string;
begin
  mText := TSlashTest.ExpandOrEmpty(Format(cRoutine, ['/oscheck', 'H := CreateMutex(nil, False, nil);']), 8);
  Assert.Contains(mText, '  H := CreateMutex(nil, False, nil);'#10'  if H = 0 then'#10'    RaiseLastOSError;'#10);
  mText := TSlashTest.ExpandOrEmpty(Format(cRoutine, ['/oscheck', 'Ok := DeleteFile(''x'');']), 8);
  Assert.Contains(mText, '  if not Ok then'#10);
end;

procedure TWinApiCommandsTests.OsCheckWithoutBoolFails;
begin
  // GetTickCount ist unbekannt, P liefert nichts.
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty(Format(cRoutine, ['/oscheck', 'GetTickCount();']), 8));
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty(Format(cRoutine, ['/oscheck', 'P(H);']), 8));
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty(Format(cRoutine, ['/oscheck', 'Ok := True;']), 8));
end;

procedure TWinApiCommandsTests.OleCheckWraps;
var
  mText: string;
begin
  mText := TSlashTest.ExpandOrEmpty(Format(cRoutine, ['/olecheck', 'Obj.QueryInterface(IID, Intf);']), 8);
  Assert.Contains(mText, '  OleCheck(Obj.QueryInterface(IID, Intf));'#10);
  Assert.Contains(mText, 'System.Win.ComObj');
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty('unit U;'#10'interface'#10'/olecheck'#10'implementation'#10'end.', 2));
end;

procedure TWinApiCommandsTests.ResultsParse;
begin
  Assert.IsTrue(TTestSource.Parses(TSlashTest.ExpandOrEmpty(Format(cRoutine, ['/oscheck', 'CloseHandle(H);']), 8)));
  Assert.IsTrue(TTestSource.Parses(TSlashTest.ExpandOrEmpty('unit U;'#10'interface'#10'/external F f.dll'#10'implementation'#10'end.', 2)));
end;

initialization
  TDUnitX.RegisterTestFixture(TWinApiCommandsTests);

end.
