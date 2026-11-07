unit Atlas.Common.Pascal.EventAssignments.Tests;

// Tests der Erkennung von Methoden, die der Code einem Ereignis zuweist (OnClose := FormClose).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEventAssignmentsTests = class
  public
    [Test]
    procedure FindsAssignedMethods;
    [Test]
    procedure IgnoresCallsAndOtherProperties;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.EventAssignments;

function NamesOf(const AText: string): string;
begin
  Result := string.Join(',', TEventAssignments.Names(TPascalLexer.Tokenize(AText)));
end;

procedure TEventAssignmentsTests.FindsAssignedMethods;
begin
  Assert.AreEqual('FormClose,PaintLine,Tick,Run,Stop', NamesOf('begin'#10'  OnClose := FormClose;'#10 +
    '  FEvents.OnEditorPaintLine := PaintLine;'#10'  Later.OnTimer := Later_.Tick;'#10 +
    '  if X then Button.OnClick := Self.Run else Button.OnClick := nil;'#10'  OnClose := FormClose;'#10 +
    '  FTimer.OnTimer := TStopTicker(FTicker).Stop'#10'end'));
  Assert.IsTrue(TEventAssignments.IsEventName('OnTimer'));
  Assert.IsFalse(TEventAssignments.IsEventName('Online'));
  Assert.IsFalse(TEventAssignments.IsEventName('On'));
end;

procedure TEventAssignmentsTests.IgnoresCallsAndOtherProperties;
begin
  Assert.AreEqual('', NamesOf('begin'#10'  OnClose := MakeHandler(1);'#10'  Caption := Title;'#10 +
    '  OnClick := Factory.Handler(Self);'#10'  OnClick := THandlers(Liste);'#10'end'));
end;

initialization
  TDUnitX.RegisterTestFixture(TEventAssignmentsTests);

end.
