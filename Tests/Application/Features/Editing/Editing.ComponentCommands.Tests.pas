unit Editing.ComponentCommands.Tests;

// Tests für die Schnellbefehle /notify, /changed, /loaded und /notification (#320).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TComponentCommandsTests = class
  public
    [Test]
    procedure NotifyCreatesEvent;
    [Test]
    procedure NotifyTwiceOnlyHint;
    [Test]
    procedure NotifyWithEventType;
    [Test]
    procedure ChangedInControlInvalidates;
    [Test]
    procedure ChangedCreatesSetter;
    [Test]
    procedure LoadedOnlyForComponents;
    [Test]
    procedure NotificationExtendsExisting;
    [Test]
    procedure OutsideClassFails;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Editing.SlashCommands,
  Editing.SlashCommands.TestSupport;

const
  cKnopf =
    'unit U;'#10 +                          // 0
    'interface'#10 +                        // 1
    'uses System.Classes;'#10 +             // 2
    'type'#10 +                             // 3
    '  TKnopf = class(TComponent)'#10 +     // 4
    '  private'#10 +                        // 5
    '    FText: string;'#10 +               // 6
    '  public'#10 +                         // 7
    '    %s'#10 +                           // 8 Befehl
    '  end;'#10 +                           // 9
    'implementation'#10 +                   // 10
    'end.';

{ TComponentCommandsTests }

procedure TComponentCommandsTests.NotifyCreatesEvent;
var
  mText: string;
begin
  mText := TSlashTest.ExpandOrEmpty(Format(cKnopf, ['/notify OnChange']), 8);
  Assert.AreEqual(
    'unit U;'#10'interface'#10'uses System.Classes;'#10'type'#10 +
    '  TKnopf = class(TComponent)'#10 +
    '  private'#10 +
    '    FOnChange: TNotifyEvent;'#10 +
    '    FText: string;'#10 +
    '  public'#10 +
    '  protected'#10 +
    '    procedure DoChange; virtual;'#10 +
    '  published'#10 +
    '    property OnChange: TNotifyEvent read FOnChange write FOnChange;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKnopf.DoChange;'#10 +
    'begin'#10 +
    '  if Assigned(FOnChange) then'#10 +
    '    FOnChange(Self);'#10 +
    'end;'#10 +
    #10 +
    'end.', mText);
end;

procedure TComponentCommandsTests.NotifyTwiceOnlyHint;
var
  mOnce: string;
begin
  mOnce := TSlashTest.ExpandOrEmpty(Format(cKnopf, ['/notify OnChange']), 8);
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty(StringReplace(mOnce, '  public'#10, '  public'#10'    /notify OnChange'#10, []), 9));
end;

procedure TComponentCommandsTests.NotifyWithEventType;
var
  mText: string;
begin
  mText := TSlashTest.ExpandOrEmpty(StringReplace(Format(cKnopf, ['/notify OnFehler: TFehlerEvent']), 'type'#10,
    'type'#10'  TFehlerEvent = procedure(Sender: TObject; const AText: string) of object;'#10, []), 9);
  Assert.Contains(mText, '    procedure DoFehler(const AText: string); virtual;'#10);
  Assert.Contains(mText, '    FOnFehler(Self, AText);'#10);
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty(Format(cKnopf, ['/notify OnFehler: TUnbekannt']), 8));
end;

procedure TComponentCommandsTests.ChangedInControlInvalidates;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAnzeige = class(TCustomControl)'#10 +
    '  private'#10 +
    '    FFarbe: TColor;'#10 +
    '    procedure SetFarbe(const AFarbe: TColor);'#10 +
    '  published'#10 +
    '    /changed Farbe'#10 +                    // 8
    '    property Farbe: TColor read FFarbe write SetFarbe;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TAnzeige.SetFarbe(const AFarbe: TColor);'#10 +
    'begin'#10 +
    '  FFarbe := AFarbe;'#10 +
    'end;'#10 +
    'end.';
var
  mText: string;
begin
  mText := TSlashTest.ExpandOrEmpty(cSource, 8);
  Assert.Contains(mText, 'procedure TAnzeige.SetFarbe(const AFarbe: TColor);'#10'begin'#10 +
    '  if FFarbe <> AFarbe then'#10'  begin'#10'    FFarbe := AFarbe;'#10'    Invalidate;'#10'  end;'#10'end;'#10 +
    'end.');
  Assert.AreEqual(0, Pos('/changed', mText));
end;

procedure TComponentCommandsTests.ChangedCreatesSetter;
var
  mText: string;
begin
  mText := TSlashTest.ExpandOrEmpty(StringReplace(Format(cKnopf, ['/changed Text']), '  end;'#10,
    '    property Text: string read FText write FText;'#10'  end;'#10, []), 8);
  Assert.Contains(mText, 'property Text: string read FText write SetText;');
  Assert.Contains(mText, '    procedure SetText(const Value: string);'#10);
  Assert.Contains(mText, '  if FText <> Value then'#10'  begin'#10'    FText := Value;'#10'    Changed;'#10);
end;

procedure TComponentCommandsTests.LoadedOnlyForComponents;
var
  mText: string;
begin
  mText := TSlashTest.ExpandOrEmpty(Format(cKnopf, ['/loaded']), 8);
  Assert.Contains(mText, '  protected'#10'    procedure Loaded; override;'#10);
  Assert.Contains(mText, 'procedure TKnopf.Loaded;'#10'begin'#10'  inherited Loaded;'#10'end;');
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty(StringReplace(Format(cKnopf, ['/loaded']), 'class(TComponent)', 'class(TObject)', []),
    8));
end;

procedure TComponentCommandsTests.NotificationExtendsExisting;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TVerbinder = class(TComponent)'#10 +
    '  private'#10 +
    '    FQuelle: TComponent;'#10 +
    '    FZiel: TControl;'#10 +
    '    FAnzahl: Integer;'#10 +
    '    procedure SetZiel(const Value: TControl);'#10 +
    '  protected'#10 +
    '    procedure Notification(AComponent: TComponent; Operation: TOperation); override;'#10 +
    '  public'#10 +
    '    /notification'#10 +                     // 12
    '    property Ziel: TControl read FZiel write SetZiel;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TVerbinder.Notification(AComponent: TComponent; Operation: TOperation);'#10 +
    'begin'#10 +
    '  inherited Notification(AComponent, Operation);'#10 +
    '  if (Operation = opRemove) and (AComponent = FQuelle) then'#10 +
    '    FQuelle := nil;'#10 +
    'end;'#10 +
    'procedure TVerbinder.SetZiel(const Value: TControl);'#10 +
    'begin'#10 +
    '  FZiel := Value;'#10 +
    'end;'#10 +
    'end.';
var
  mText: string;
begin
  mText := TSlashTest.ExpandOrEmpty(cSource, 12);
  Assert.Contains(mText, '    FQuelle := nil;'#10'  if (Operation = opRemove) and (AComponent = FZiel) then'#10 +
    '    FZiel := nil;'#10'end;');
  // Keine zweite Notification, keine doppelte Bedingung.
  Assert.AreEqual(1, Integer(Length(mText.Split(['procedure TVerbinder.Notification']))) - 1);
  Assert.AreEqual(1, Integer(Length(mText.Split(['(AComponent = FQuelle)']))) - 1);
  Assert.Contains(mText, 'begin'#10'  if FZiel <> nil then'#10'    FZiel.RemoveFreeNotification(Self);'#10 +
    '  FZiel := Value;'#10'  if FZiel <> nil then'#10'    FZiel.FreeNotification(Self);'#10'end;');
  // Zweiter Aufruf: nichts mehr zu tun.
  Assert.AreEqual('', TSlashTest.ExpandOrEmpty(StringReplace(mText, '  public'#10, '  public'#10'    /notification'#10, []), 12));
end;

procedure TComponentCommandsTests.OutsideClassFails;
const
  cOutside = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  %s'#10'end;'#10'end.';
var
  mCommand: string;
begin
  for mCommand in TArray<string>.Create('/notify OnChange', '/changed Farbe', '/loaded', '/notification') do
  begin
    Assert.AreEqual('', TSlashTest.ExpandOrEmpty(Format(cOutside, [mCommand]), 5), mCommand);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TComponentCommandsTests);

end.
