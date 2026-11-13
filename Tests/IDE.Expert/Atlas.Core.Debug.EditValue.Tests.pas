unit Atlas.Core.Debug.EditValue.Tests;

// Tests für „Werte ändern“ (#868) ohne IDE: Antwort lesen, Prüfung der
// Eingabe je Typ und der Text für das Ändern, Mengen, Farben, Umschalten und
// gemerkte Änderungen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.EditValue;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasEditValueTests = class
  private
    function Info(AKind: TAtlasEditKind): TAtlasEditInfo;
    function Value(AKind: TAtlasEditKind; const AInput: string): string;
    function Problem(AKind: TAtlasEditKind; const AInput: string): TAtlasEditProblem;
  public
    [Test]
    procedure ReadsAnswerAndArguments;
    [Test]
    procedure IntegerInRange;
    [Test]
    procedure FloatWithComma;
    [Test]
    procedure BooleanCharAndString;
    [Test]
    procedure EnumWithPrefix;
    [Test]
    procedure SetsFromNames;
    [Test]
    procedure Colors;
    [Test]
    procedure ToggleAndReadOnly;
    [Test]
    procedure ChangesKeepFirstOldValue;
  end;

implementation

uses
  System.SysUtils;

const
  cAnswer = '{"expression":"M","type":"TModus","kind":"enum","values":["mdAuto","mdHand"],"prefix":"TModus.",' +
    '"low":"","high":"","setter":"SetModus","readOnly":false}';

{ TAtlasEditValueTests }

function TAtlasEditValueTests.Info(AKind: TAtlasEditKind): TAtlasEditInfo;
begin
  Result := TAtlasEditInfo.Plain('X');
  Result.Kind := AKind;
  if AKind = TAtlasEditKind.Integer_ then
  begin
    Result.Low := '0';
    Result.High := '255';
  end;
  if AKind in [TAtlasEditKind.Enum, TAtlasEditKind.Set_] then
  begin
    Result.Values := TArray<string>.Create('mdAuto', 'mdHand', 'mdAus');
  end;
end;

function TAtlasEditValueTests.Value(AKind: TAtlasEditKind; const AInput: string): string;
var
  mCheck: TAtlasEditCheck;
begin
  mCheck := TAtlasEditValue.Check(Info(AKind), AInput);
  Assert.IsTrue(mCheck.Ok, 'angenommen: ' + AInput);
  Result := mCheck.Value;
end;

function TAtlasEditValueTests.Problem(AKind: TAtlasEditKind; const AInput: string): TAtlasEditProblem;
begin
  Result := TAtlasEditValue.Check(Info(AKind), AInput).Problem;
end;

procedure TAtlasEditValueTests.ReadsAnswerAndArguments;
var
  mInfo: TAtlasEditInfo;
begin
  mInfo := TAtlasEditValue.ReadAnswerText(cAnswer, 'M');
  Assert.AreEqual(Ord(TAtlasEditKind.Enum), Ord(mInfo.Kind));
  Assert.AreEqual('TModus', mInfo.TypeName);
  Assert.AreEqual(2, Integer(Length(mInfo.Values)));
  Assert.AreEqual('TModus.', mInfo.Prefix);
  Assert.AreEqual('SetModus', mInfo.Setter);
  mInfo := TAtlasEditValue.ReadAnswerText('', 'Y');
  Assert.AreEqual(Ord(TAtlasEditKind.Other), Ord(mInfo.Kind), 'ohne Antwort freie Eingabe');
  Assert.AreEqual('Y', mInfo.Expression);
  Assert.AreEqual('["file:///a.pas",4,"K.Betrag"]', TAtlasEditValue.Arguments('file:///a.pas', 4, 'K.Betrag'));
end;

procedure TAtlasEditValueTests.IntegerInRange;
begin
  Assert.AreEqual('150', Value(TAtlasEditKind.Integer_, ' 150 '));
  Assert.AreEqual('255', Value(TAtlasEditKind.Integer_, '$FF'));
  Assert.AreEqual(Ord(TAtlasEditProblem.NotInteger), Ord(Problem(TAtlasEditKind.Integer_, 'abc')), 'abc abgelehnt');
  Assert.AreEqual(Ord(TAtlasEditProblem.OutOfRange), Ord(Problem(TAtlasEditKind.Integer_, '256')));
  Assert.AreEqual(Ord(TAtlasEditProblem.OutOfRange), Ord(Problem(TAtlasEditKind.Integer_, '-1')));
  Assert.AreEqual('0..255', TAtlasEditValue.Check(Info(TAtlasEditKind.Integer_), '300').Detail);
  Assert.AreEqual(Ord(TAtlasEditProblem.Empty), Ord(Problem(TAtlasEditKind.Integer_, '')));
end;

procedure TAtlasEditValueTests.FloatWithComma;
begin
  Assert.AreEqual('150.5', Value(TAtlasEditKind.Float, '150,5'));
  Assert.AreEqual('150', Value(TAtlasEditKind.Float, '150'));
  Assert.AreEqual(Ord(TAtlasEditProblem.NotFloat), Ord(Problem(TAtlasEditKind.Float, '1,2,3')));
end;

procedure TAtlasEditValueTests.BooleanCharAndString;
begin
  Assert.AreEqual('True', Value(TAtlasEditKind.Boolean_, 'true'));
  Assert.AreEqual(Ord(TAtlasEditProblem.NotBoolean), Ord(Problem(TAtlasEditKind.Boolean_, 'ja')));
  Assert.AreEqual('''x''', Value(TAtlasEditKind.Char_, 'x'));
  Assert.AreEqual('#13', Value(TAtlasEditKind.Char_, '#13'));
  Assert.AreEqual('''''''''', Value(TAtlasEditKind.Char_, ''''''''''), 'Hochkomma in Hochkommas');
  Assert.AreEqual(Ord(TAtlasEditProblem.NotChar), Ord(Problem(TAtlasEditKind.Char_, 'xy')));
  Assert.AreEqual('''O''''Neil''', Value(TAtlasEditKind.String_, 'O''Neil'));
  Assert.AreEqual('''schon''', Value(TAtlasEditKind.String_, '''schon'''));
  Assert.AreEqual('''''', Value(TAtlasEditKind.String_, ''), 'leerer String erlaubt');
end;

procedure TAtlasEditValueTests.EnumWithPrefix;
var
  mInfo: TAtlasEditInfo;
begin
  Assert.AreEqual('mdHand', Value(TAtlasEditKind.Enum, 'MDHAND'));
  Assert.AreEqual(Ord(TAtlasEditProblem.UnknownValue), Ord(Problem(TAtlasEditKind.Enum, 'mdNein')));
  mInfo := Info(TAtlasEditKind.Enum);
  mInfo.Prefix := 'TModus.';
  Assert.AreEqual('TModus.mdAus', TAtlasEditValue.Check(mInfo, 'mdAus').Value);
  Assert.AreEqual('TModus.mdAus', TAtlasEditValue.Check(mInfo, 'TModus.mdAus').Value);
end;

procedure TAtlasEditValueTests.SetsFromNames;
begin
  Assert.AreEqual('[mdAuto, mdAus]', Value(TAtlasEditKind.Set_, '[mdauto,mdAus]'));
  Assert.AreEqual('[]', Value(TAtlasEditKind.Set_, ''));
  Assert.AreEqual(Ord(TAtlasEditProblem.UnknownValue), Ord(Problem(TAtlasEditKind.Set_, '[mdAuto, mdNein]')));
  Assert.AreEqual(2, Integer(Length(TAtlasEditValue.SetItems('[mdAuto,mdHand]'))));
  Assert.AreEqual(0, Integer(Length(TAtlasEditValue.SetItems('[]'))));
end;

procedure TAtlasEditValueTests.Colors;
var
  mColor: Integer;
begin
  Assert.IsTrue(TAtlasEditValue.ColorOf('#FF0000', mColor));
  Assert.AreEqual($000000FF, mColor, 'Rot als $00BBGGRR');
  Assert.AreEqual('$000000FF', TAtlasEditValue.ColorText(mColor));
  Assert.AreEqual('$00FF0000', Value(TAtlasEditKind.Color, '#0000FF'));
  Assert.AreEqual('clRed', Value(TAtlasEditKind.Color, 'clRed'));
  Assert.AreEqual('$0000FF00', Value(TAtlasEditKind.Color, '65280'));
  Assert.AreEqual(Ord(TAtlasEditProblem.NotInteger), Ord(Problem(TAtlasEditKind.Color, 'grünlich')));
end;

procedure TAtlasEditValueTests.ToggleAndReadOnly;
var
  mNew: string;
  mInfo: TAtlasEditInfo;
begin
  Assert.IsTrue(TAtlasEditValue.Toggled('True', mNew));
  Assert.AreEqual('False', mNew);
  Assert.IsFalse(TAtlasEditValue.Toggled('3', mNew));
  mInfo := Info(TAtlasEditKind.Integer_);
  mInfo.ReadOnly := True;
  Assert.AreEqual(Ord(TAtlasEditProblem.ReadOnly), Ord(TAtlasEditValue.Check(mInfo, '1').Problem));
  mInfo := TAtlasEditInfo.Plain('K.Betrag');
  Assert.AreEqual('', TAtlasEditValue.SetterCall(mInfo, '150'), 'ohne Setter');
  mInfo.Setter := 'SetBetrag';
  Assert.AreEqual('K.SetBetrag(150)', TAtlasEditValue.SetterCall(mInfo, '150'));
  mInfo.Expression := 'Betrag';
  Assert.AreEqual('SetBetrag(150)', TAtlasEditValue.SetterCall(mInfo, '150'));
end;

procedure TAtlasEditValueTests.ChangesKeepFirstOldValue;
var
  mChanges: TAtlasEditChanges;
  mChange: TAtlasEditChange;
begin
  mChanges := TAtlasEditChanges.Create;
  try
    mChange := Default(TAtlasEditChange);
    mChange.FileName := 'C:\a.pas';
    mChange.Expression := 'Betrag';
    mChange.OldValue := '125';
    mChange.NewValue := '150';
    mChanges.Add(mChange);
    mChange.OldValue := '150';
    mChange.NewValue := '175';
    mChanges.Add(mChange);
    Assert.AreEqual(1, mChanges.Count);
    Assert.AreEqual('175', mChanges.Items[0].NewValue);
    Assert.IsTrue(mChanges.Find('c:\A.pas', 'betrag', mChange));
    Assert.AreEqual('125', mChange.OldValue);
    Assert.AreEqual('175', mChange.NewValue);
    mChanges.Remove('C:\a.pas', 'Betrag');
    Assert.IsFalse(mChanges.Find('C:\a.pas', 'Betrag', mChange));
    mChanges.Add(mChange);
    mChanges.Clear;
    Assert.AreEqual(0, mChanges.Count);
  finally
    mChanges.Free;
  end;
end;

end.
