unit Atlas.Common.Lsp.IdeBuild.Tests;

// Tests für Build-Ergebnisse aus der IDE (#528).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspIdeBuildTests = class
  public
    [Test]
    procedure ParsesMessagesZeroBased;
    [Test]
    procedure RemembersLastBuildAndRaisesEvent;
    [Test]
    procedure TracksRunningCompiles;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.IdeBuild;

const
  Sample = '{"project":"C:\\P\\A.dproj","platform":"Win32","success":false,"messages":[' +
    '{"file":"C:\\P\\A.dpr","line":10,"column":11,"severity":"error","code":"E2003","text":"Undeklarierter Bezeichner"},' +
    '{"file":"C:\\P\\A.dpr","line":7,"column":3,"severity":"hint","code":"H2164","text":"Variable nicht verwendet"},' +
    '{"file":"","line":0,"column":0,"severity":"fatal","code":"F1026","text":"Datei nicht gefunden"}]}';

procedure TLspIdeBuildTests.ParsesMessagesZeroBased;
var
  Params: TJSONValue;
  Messages: TArray<TCompilerMessage>;
begin
  Params := TJSONObject.ParseJSONValue(Sample);
  try
    Messages := TLspIdeBuild.ParseMessages(Params);
  finally
    Params.Free;
  end;
  Assert.AreEqual(3, Integer(Length(Messages)));
  Assert.AreEqual(9, Messages[0].Line);
  Assert.AreEqual(10, Messages[0].Column);
  Assert.AreEqual(Ord(TCompilerSeverity.Error), Ord(Messages[0].Severity));
  Assert.AreEqual('E2003', Messages[0].Code);
  Assert.AreEqual(Ord(TCompilerSeverity.Hint), Ord(Messages[1].Severity));
  // Ohne Datei und Zeile: Zeile und Spalte -1.
  Assert.AreEqual(-1, Messages[2].Line);
  Assert.AreEqual(-1, Messages[2].Column);
  Assert.AreEqual(Ord(TCompilerSeverity.Fatal), Ord(Messages[2].Severity));
end;

procedure Notify(ADispatcher: TJsonRpcDispatcher; const AMethod, AParams: string);
var
  Message: TJSONObject;
begin
  Message := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","method":"' + AMethod + '","params":' + AParams + '}')
    as TJSONObject;
  try
    ADispatcher.DispatchMessage(Message).Free;
  finally
    Message.Free;
  end;
end;

procedure TLspIdeBuildTests.RemembersLastBuildAndRaisesEvent;
var
  Build: TLspIdeBuild;
  Dispatcher: TJsonRpcDispatcher;
  Received: Integer;
begin
  Build := TLspIdeBuild.Create;
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Received := -1;
    Build.OnMessages :=
      procedure(const AMessages: TArray<TCompilerMessage>)
      begin
        Received := Length(AMessages);
      end;
    Build.Attach(Dispatcher);
    Assert.IsFalse(Build.LastBuild.Known);
    Notify(Dispatcher, TLspIdeBuild.FinishedMethod,
      '{"project":"C:\\P\\A.dproj","kind":"build","configuration":"Debug","platform":"Win32","success":false,"durationMs":1234}');
    Notify(Dispatcher, TLspIdeBuild.MessagesMethod, Sample);
    Assert.AreEqual(3, Received);
    Assert.IsTrue(Build.LastBuild.Known);
    Assert.AreEqual('C:\P\A.dproj', Build.LastBuild.Project);
    Assert.AreEqual('build', Build.LastBuild.Kind);
    Assert.AreEqual('Debug', Build.LastBuild.Configuration);
    Assert.AreEqual(Int64(1234), Build.LastBuild.DurationMs);
    Assert.IsFalse(Build.LastBuild.Success);
    Assert.AreEqual(3, Integer(Length(Build.LastBuild.Messages)));
  finally
    Dispatcher.Free;
    Build.Free;
  end;
end;

procedure TLspIdeBuildTests.TracksRunningCompiles;
var
  Build: TLspIdeBuild;
  Dispatcher: TJsonRpcDispatcher;
  Events: string;
begin
  // Die Projektprüfung pausiert, solange die IDE kompiliert (#1247).
  Build := TLspIdeBuild.Create;
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Events := '';
    Build.OnCompiling :=
      procedure(ARunning: Boolean)
      begin
        if ARunning then
          Events := Events + '+'
        else
          Events := Events + '-';
      end;
    Build.Attach(Dispatcher);
    Notify(Dispatcher, TLspIdeBuild.StartedMethod, '{"group":true,"kind":"make"}');
    Notify(Dispatcher, TLspIdeBuild.StartedMethod, '{"project":"C:\\P\\A.dproj"}');
    Notify(Dispatcher, TLspIdeBuild.StartedMethod, '{"project":"C:\\P\\B.dproj"}');
    Assert.IsTrue(Build.Compiling);
    Notify(Dispatcher, TLspIdeBuild.FinishedMethod, '{"project":"C:\\P\\A.dproj","success":true}');
    Assert.IsTrue(Build.Compiling, 'B und die Gruppe laufen noch');
    // Fehlt das Ende von B, beendet das Ende der Gruppe alles.
    Notify(Dispatcher, TLspIdeBuild.FinishedMethod, '{"group":true,"success":true}');
    Assert.IsFalse(Build.Compiling);
    // Einzelnes Projekt im Hintergrund (#548).
    Notify(Dispatcher, TLspIdeBuild.StartedMethod, '{"project":"C:\\P\\A.dproj","background":true}');
    Assert.IsTrue(Build.Compiling);
    Notify(Dispatcher, TLspIdeBuild.FinishedMethod, '{"project":"c:\\p\\a.dproj","background":true}');
    Assert.IsFalse(Build.Compiling);
    Assert.AreEqual('+-+-', Events);
  finally
    Dispatcher.Free;
    Build.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspIdeBuildTests);

end.