unit Atlas.Core.Debug.CallStackFlow.Tests;

// Tests für die Entscheidungen des Fensters „Atlas-Aufrufstapel“ außerhalb von Inhalt und Parametern (#843, #1967):
// Nachfragen, Antworten, nächster Parameter, Namensfeld, Rahmen öffnen; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasCallStackFlowTests = class
  public
    [Test]
    procedure RetryUpToMax;
    [Test]
    procedure AcceptsNewestWhileWaiting;
    [Test]
    procedure NextParamSkipsGroupsAndDone;
    [Test]
    procedure NameOnlyForStrings;
    [Test]
    procedure OpensFramesWithSource;
  end;

implementation

uses
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.CallStackParams,
  Atlas.Core.Debug.OwnCode,
  Atlas.Core.Debug.CallStackView,
  Atlas.Core.Debug.CallStackFlow;

function Param(const AName, ARaw: string; ADone: Boolean): TAtlasCallStackParam;
begin
  Result := Default(TAtlasCallStackParam);
  Result.Name := AName;
  Result.TypeName := 'TKunde';
  Result.Raw := ARaw;
  Result.Done := ADone;
end;

function Row(AKind: TAtlasDebugStackRowKind; AFirst: Integer): TAtlasDebugStackRow;
begin
  Result := Default(TAtlasDebugStackRow);
  Result.Kind := AKind;
  Result.First := AFirst;
  Result.Count := 1;
end;

function Stack: TAtlasDebugStackView;
begin
  Result := Default(TAtlasDebugStackView);
  SetLength(Result.Entries, 3);
  Result.Entries[0].Frame := TAtlasDebugFrame.Create('Kunden.TKunde.Speichere', 'Kunden.pas', 12);
  Result.Entries[0].Params := [Param('AKunde', '$2A3F2C0', True)];
  Result.Entries[1].Frame := TAtlasDebugFrame.Create('Vcl.Forms', '', 0);
  Result.Entries[1].Params := [Param('ASender', '$1000', False)];
  Result.Entries[2].Frame := TAtlasDebugFrame.Create('Main.TForm1.Click', 'Main.pas', 30);
  Result.Entries[2].Params := [Param('', '$1', False), Param('AKunde', '$2A3F2C0', False)];
end;

{ TAtlasCallStackFlowTests }

procedure TAtlasCallStackFlowTests.RetryUpToMax;
var
  mRetries: Integer;
begin
  mRetries := 1;
  Assert.IsTrue(TAtlasCallStackFlow.Retry(mRetries, 2));
  Assert.AreEqual(2, mRetries);
  Assert.IsFalse(TAtlasCallStackFlow.Retry(mRetries, 2));
end;

procedure TAtlasCallStackFlowTests.AcceptsNewestWhileWaiting;
var
  mStack: TAtlasDebugStackView;
begin
  mStack := Stack;
  Assert.IsTrue(TAtlasCallStackFlow.Accepts(4, 4, True, 2, mStack));
  Assert.IsFalse(TAtlasCallStackFlow.Accepts(3, 4, True, 2, mStack));
  Assert.IsFalse(TAtlasCallStackFlow.Accepts(4, 4, False, 2, mStack));
  Assert.IsFalse(TAtlasCallStackFlow.Accepts(4, 4, True, 3, mStack));
end;

procedure TAtlasCallStackFlowTests.NextParamSkipsGroupsAndDone;
var
  mFrame, mParam: Integer;
begin
  // Rahmen 0 ist fertig, Rahmen 1 steckt in einer Gruppe, in Rahmen 2 hat der erste Parameter keinen Namen.
  Assert.IsTrue(TAtlasCallStackFlow.NextParam(Stack, [Row(TAtlasDebugStackRowKind.Frame, 0),
    Row(TAtlasDebugStackRowKind.LibraryGroup, 1), Row(TAtlasDebugStackRowKind.Frame, 2)], mFrame, mParam));
  Assert.AreEqual(2, mFrame);
  Assert.AreEqual(1, mParam);
  Assert.IsFalse(TAtlasCallStackFlow.NextParam(Stack, [Row(TAtlasDebugStackRowKind.Frame, 0)], mFrame, mParam));
  Assert.AreEqual(-1, mFrame);
end;

procedure TAtlasCallStackFlowTests.NameOnlyForStrings;
begin
  Assert.IsTrue(TAtlasCallStackFlow.AsksName('$2A3F2C0', 3));
  Assert.IsTrue(TAtlasCallStackFlow.AsksName('nil', 0));
  Assert.IsFalse(TAtlasCallStackFlow.AsksName('nil', 3));
  Assert.AreEqual('''Kunde1''', TAtlasCallStackFlow.NameOf(True, '''Kunde1'''));
  Assert.AreEqual('', TAtlasCallStackFlow.NameOf(True, 'E2003'));
  Assert.AreEqual('', TAtlasCallStackFlow.NameOf(False, '''Kunde1'''));
end;

procedure TAtlasCallStackFlowTests.OpensFramesWithSource;
var
  mStack: TAtlasDebugStackView;
begin
  mStack := Stack;
  Assert.IsTrue(TAtlasCallStackFlow.CanOpen(mStack, 0));
  Assert.IsFalse(TAtlasCallStackFlow.CanOpen(mStack, 1));
  Assert.IsFalse(TAtlasCallStackFlow.CanOpen(mStack, 3));
  Assert.IsFalse(TAtlasCallStackFlow.CanOpen(mStack, -1));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCallStackFlowTests);

end.
