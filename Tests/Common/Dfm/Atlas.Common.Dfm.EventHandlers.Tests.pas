unit Atlas.Common.Dfm.EventHandlers.Tests;

// Beim nächsten Ereignis anhalten (#856): Handler je Ereignis aus Formular
// und Code, mit der Zeile des begin.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Dfm.EventHandlers;

type
  [TestFixture]
  TEventHandlersTests = class
  private
    FHandlers: TArray<TEventHandler>;
    function Find(const AComponent, AEvent: string): TEventHandler;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FormEventsWithBodies;
    [Test]
    procedure SharedHandlerTwice;
    [Test]
    procedure DataSetAndActionEvents;
    [Test]
    procedure TimerInterval;
    [Test]
    procedure CodeAssignments;
    [Test]
    procedure IgnoresNilAnonymousAndForeign;
    [Test]
    procedure MissingBodyStaysOpen;
    [Test]
    procedure PrefilterFindsAssignments;
    [Test]
    procedure BodyLineIsFirstStatement;
  end;

implementation

uses
  System.SysUtils;

const
  UnitText =
    'unit Kunde;'#13#10 +                                         // 0
    'interface'#13#10 +                                           // 1
    'type'#13#10 +                                                // 2
    '  TfrmKunde = class(TForm)'#13#10 +                          // 3
    '    procedure btnSpeichernClick(Sender: TObject);'#13#10 +   // 4
    '    procedure FormShow(Sender: TObject);'#13#10 +            // 5
    '    procedure TabelleBeforePost(DataSet: TDataSet);'#13#10 + // 6
    '    procedure actDruckenExecute(Sender: TObject);'#13#10 +   // 7
    '    procedure TimerTick(Sender: TObject);'#13#10 +           // 8
    '    procedure FormCreate(Sender: TObject);'#13#10 +          // 9
    '  end;'#13#10 +                                              // 10
    'implementation'#13#10 +                                      // 11
    'procedure TfrmKunde.btnSpeichernClick(Sender: TObject);'#13#10 + // 12
    'begin'#13#10 +                                               // 13
    'end;'#13#10 +                                                // 14
    'procedure TfrmKunde.FormShow(Sender: TObject);'#13#10 +      // 15
    'var'#13#10 +                                                 // 16
    '  I: Integer;'#13#10 +                                       // 17
    'begin'#13#10 +                                               // 18
    'end;'#13#10 +                                                // 19
    'procedure TfrmKunde.TabelleBeforePost(DataSet: TDataSet);'#13#10 + // 20
    'begin'#13#10 +                                               // 21
    'end;'#13#10 +                                                // 22
    'procedure TfrmKunde.actDruckenExecute(Sender: TObject);'#13#10 + // 23
    'begin'#13#10 +                                               // 24
    'end;'#13#10 +                                                // 25
    'procedure TfrmKunde.TimerTick(Sender: TObject);'#13#10 +     // 26
    'begin'#13#10 +                                               // 27
    'end;'#13#10 +                                                // 28
    'procedure TfrmKunde.FormCreate(Sender: TObject);'#13#10 +    // 29
    'begin'#13#10 +                                               // 30
    '  FTimer.OnTimer := TimerTick;'#13#10 +                      // 31
    '  OnShow := Self.FormShow;'#13#10 +                          // 32
    '  btnAbbrechen.OnClick := nil;'#13#10 +                      // 33
    '  btnHilfe.OnClick := Form2.HilfeClick;'#13#10 +             // 34
    '  OnlineCount := 5;'#13#10 +                                 // 35
    'end;'#13#10 +                                                // 36
    'end.'#13#10;

  FormText =
    'object frmKunde: TfrmKunde'#13#10 +
    '  OnShow = FormShow'#13#10 +
    '  object btnSpeichern: TButton'#13#10 +
    '    OnClick = btnSpeichernClick'#13#10 +
    '  end'#13#10 +
    '  object btnOk: TButton'#13#10 +
    '    OnClick = btnSpeichernClick'#13#10 +
    '  end'#13#10 +
    '  object Tabelle: TFDQuery'#13#10 +
    '    BeforePost = TabelleBeforePost'#13#10 +
    '    AfterScroll = TabelleAfterScroll'#13#10 +
    '  end'#13#10 +
    '  object ActionList1: TActionList'#13#10 +
    '    object actDrucken: TAction'#13#10 +
    '      Caption = ''Drucken'''#13#10 +
    '      OnExecute = actDruckenExecute'#13#10 +
    '    end'#13#10 +
    '  end'#13#10 +
    '  object Timer1: TTimer'#13#10 +
    '    Interval = 50'#13#10 +
    '    OnTimer = TimerTick'#13#10 +
    '  end'#13#10 +
    'end'#13#10;

function Forms: TArray<TEventHandlerForm>;
begin
  SetLength(Result, 1);
  Result[0].FileName := 'C:\P\Kunde.dfm';
  Result[0].Text := FormText;
end;

procedure TEventHandlersTests.TearDown;
begin
  FHandlers := nil;
end;

function TEventHandlersTests.Find(const AComponent, AEvent: string): TEventHandler;
var
  Item: TEventHandler;
begin
  for Item in FHandlers do
    if SameText(Item.Component, AComponent) and SameText(Item.Event, AEvent) then
      Exit(Item);
  Assert.Fail('nicht gefunden: ' + AComponent + '.' + AEvent);
  Result := Default(TEventHandler);
end;

procedure TEventHandlersTests.FormEventsWithBodies;
var
  Handler: TEventHandler;
begin
  FHandlers := TEventHandlers.Collect('C:\P\Kunde.pas', UnitText, Forms);
  Handler := Find('btnSpeichern', 'OnClick');
  Assert.AreEqual(Ord(TEventHandlerOrigin.Form), Ord(Handler.Origin));
  Assert.AreEqual('TfrmKunde', Handler.FormClass);
  Assert.AreEqual('TButton', Handler.ComponentClass);
  Assert.AreEqual('btnSpeichernClick', Handler.Handler);
  Assert.AreEqual('TfrmKunde', Handler.Container);
  Assert.AreEqual('C:\P\Kunde.pas', Handler.FileName);
  Assert.AreEqual(13, Handler.Line);
  // Leerer Rumpf: Halt am end.
  Assert.AreEqual(14, Handler.BodyLine);
  Assert.AreEqual('C:\P\Kunde.dfm', Handler.SourceFile);
  Assert.AreEqual(3, Handler.SourceLine);
  // Das Formular selbst; begin hinter dem var-Abschnitt.
  Handler := Find('frmKunde', 'OnShow');
  Assert.AreEqual('TfrmKunde', Handler.ComponentClass);
  Assert.AreEqual(18, Handler.Line);
end;

procedure TEventHandlersTests.SharedHandlerTwice;
begin
  FHandlers := TEventHandlers.Collect('C:\P\Kunde.pas', UnitText, Forms);
  Assert.AreEqual(13, Find('btnSpeichern', 'OnClick').Line);
  Assert.AreEqual(13, Find('btnOk', 'OnClick').Line);
end;

procedure TEventHandlersTests.DataSetAndActionEvents;
begin
  FHandlers := TEventHandlers.Collect('C:\P\Kunde.pas', UnitText, Forms);
  Assert.AreEqual(21, Find('Tabelle', 'BeforePost').Line);
  Assert.AreEqual('TAction', Find('actDrucken', 'OnExecute').ComponentClass);
  Assert.AreEqual(24, Find('actDrucken', 'OnExecute').Line);
end;

procedure TEventHandlersTests.TimerInterval;
begin
  FHandlers := TEventHandlers.Collect('C:\P\Kunde.pas', UnitText, Forms);
  Assert.AreEqual(50, Find('Timer1', 'OnTimer').Interval);
  Assert.AreEqual(-1, Find('btnSpeichern', 'OnClick').Interval);
end;

procedure TEventHandlersTests.CodeAssignments;
var
  Handler: TEventHandler;
begin
  FHandlers := TEventHandlers.Collect('C:\P\Kunde.pas', UnitText, nil);
  Assert.AreEqual(2, Integer(Length(FHandlers)));
  Handler := Find('FTimer', 'OnTimer');
  Assert.AreEqual(Ord(TEventHandlerOrigin.Code), Ord(Handler.Origin));
  Assert.AreEqual('TimerTick', Handler.Handler);
  Assert.AreEqual('TfrmKunde', Handler.Container);
  Assert.AreEqual('', Handler.ComponentClass);
  Assert.AreEqual(27, Handler.Line);
  Assert.AreEqual(31, Handler.SourceLine);
  Assert.AreEqual(28, Handler.BodyLine);
  // Am Formular selbst, Wert mit Self.
  Handler := Find('', 'OnShow');
  Assert.AreEqual('FormShow', Handler.Handler);
  Assert.AreEqual(18, Handler.Line);
end;

procedure TEventHandlersTests.IgnoresNilAnonymousAndForeign;
var
  Item: TEventHandler;
begin
  FHandlers := TEventHandlers.Collect('C:\P\Kunde.pas', UnitText, nil);
  for Item in FHandlers do
  begin
    Assert.AreNotEqual('btnAbbrechen', Item.Component);
    Assert.AreNotEqual('btnHilfe', Item.Component);
    Assert.AreNotEqual('OnlineCount', Item.Event);
  end;
end;

procedure TEventHandlersTests.MissingBodyStaysOpen;
var
  Handler: TEventHandler;
begin
  // AfterScroll ohne Rumpf in der Unit (etwa im Vorfahren): Zeile offen.
  FHandlers := TEventHandlers.Collect('C:\P\Kunde.pas', UnitText, Forms);
  Handler := Find('Tabelle', 'AfterScroll');
  Assert.AreEqual(-1, Handler.Line);
  Assert.AreEqual('', Handler.FileName);
  Assert.AreEqual(-1, Handler.BodyLine);
end;

procedure TEventHandlersTests.PrefilterFindsAssignments;
begin
  Assert.IsTrue(TEventHandlers.MayAssignHandlers('  Btn.OnClick := X;'));
  Assert.IsTrue(TEventHandlers.MayAssignHandlers('Tabelle.BeforePost:=Pruefe;'));
  Assert.IsFalse(TEventHandlers.MayAssignHandlers('OnlineCount := 5; X := 1;'));
  Assert.IsFalse(TEventHandlers.MayAssignHandlers('if Btn.OnClick = nil then'));
  // Ohne Formular und ohne Zuweisung: nichts zu tun.
  Assert.AreEqual(0, Integer(Length(TEventHandlers.Collect('A.pas', 'unit A; interface implementation end.', nil))));
end;

procedure TEventHandlersTests.BodyLineIsFirstStatement;
var
  Forms: TArray<TEventHandlerForm>;
  Handler: TEventHandler;
begin
  // FormCreate als Handler: erste Anweisung in Zeile 31.
  SetLength(Forms, 1);
  Forms[0].FileName := 'C:\P\Kunde.dfm';
  Forms[0].Text := 'object frmKunde: TfrmKunde'#13#10'  OnCreate = FormCreate'#13#10'end'#13#10;
  FHandlers := TEventHandlers.Collect('C:\P\Kunde.pas', UnitText, Forms);
  Handler := Find('frmKunde', 'OnCreate');
  Assert.AreEqual(30, Handler.Line);
  Assert.AreEqual(31, Handler.BodyLine);
end;

initialization
  TDUnitX.RegisterTestFixture(TEventHandlersTests);

end.
