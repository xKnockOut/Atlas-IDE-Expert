unit Argus.Common.Editing.ComponentCommands.Tests;

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
  Argus.Common.Documents.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Editing.SlashCommands;

/// <summary>Führt den Befehl in Zeile ALine aus und wendet die Änderungen an; '' wenn er nicht passt.</summary>
function Expand(const AText: string; ALine: Integer): string;
var
  Edits: TArray<TRuleEdit>;
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Offsets: TArray<Integer>;
  Index, Start, Stop: Integer;
begin
  if not TSlashCommandRegistry.Shared.AfterEnter(AText, TTextPosition.Create(ALine + 1, 0), nil, nil, Edits) then
    Exit('');
  Lines := AText.Split([#10]);
  SetLength(Offsets, Length(Lines) + 1);
  Offsets[0] := 0;
  for Index := 0 to High(Lines) do
    Offsets[Index + 1] := Offsets[Index] + Length(Lines[Index]) + 1;
  TArray.Sort<TRuleEdit>(Edits, TComparer<TRuleEdit>.Construct(
    function(const ALeft, ARight: TRuleEdit): Integer
    begin
      Result := (ARight.Range.StartPos.Line - ALeft.Range.StartPos.Line) * 100000 +
        ARight.Range.StartPos.Character - ALeft.Range.StartPos.Character;
    end));
  Result := AText;
  for Edit in Edits do
  begin
    Start := Offsets[Edit.Range.StartPos.Line] + Edit.Range.StartPos.Character;
    Stop := Offsets[Edit.Range.EndPos.Line] + Edit.Range.EndPos.Character;
    Result := Copy(Result, 1, Start) + Edit.NewText + Copy(Result, Stop + 1, MaxInt);
  end;
end;

const
  Knopf =
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

procedure TComponentCommandsTests.NotifyCreatesEvent;
var
  Text: string;
begin
  Text := Expand(Format(Knopf, ['/notify OnChange']), 8);
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
    'end.', Text);
end;

procedure TComponentCommandsTests.NotifyTwiceOnlyHint;
var
  Once: string;
begin
  Once := Expand(Format(Knopf, ['/notify OnChange']), 8);
  Assert.AreEqual('', Expand(StringReplace(Once, '  public'#10, '  public'#10'    /notify OnChange'#10, []), 9));
end;

procedure TComponentCommandsTests.NotifyWithEventType;
var
  Text: string;
begin
  Text := Expand(StringReplace(Format(Knopf, ['/notify OnFehler: TFehlerEvent']), 'type'#10,
    'type'#10'  TFehlerEvent = procedure(Sender: TObject; const AText: string) of object;'#10, []), 9);
  Assert.Contains(Text, '    procedure DoFehler(const AText: string); virtual;'#10);
  Assert.Contains(Text, '    FOnFehler(Self, AText);'#10);
  Assert.AreEqual('', Expand(Format(Knopf, ['/notify OnFehler: TUnbekannt']), 8));
end;

procedure TComponentCommandsTests.ChangedInControlInvalidates;
const
  Source =
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
  Text: string;
begin
  Text := Expand(Source, 8);
  Assert.Contains(Text, 'procedure TAnzeige.SetFarbe(const AFarbe: TColor);'#10'begin'#10 +
    '  if FFarbe <> AFarbe then'#10'  begin'#10'    FFarbe := AFarbe;'#10'    Invalidate;'#10'  end;'#10'end;'#10 +
    'end.');
  Assert.AreEqual(0, Pos('/changed', Text));
end;

procedure TComponentCommandsTests.ChangedCreatesSetter;
var
  Text: string;
begin
  Text := Expand(StringReplace(Format(Knopf, ['/changed Text']), '  end;'#10,
    '    property Text: string read FText write FText;'#10'  end;'#10, []), 8);
  Assert.Contains(Text, 'property Text: string read FText write SetText;');
  Assert.Contains(Text, '    procedure SetText(const Value: string);'#10);
  Assert.Contains(Text, '  if FText <> Value then'#10'  begin'#10'    FText := Value;'#10'    Changed;'#10);
end;

procedure TComponentCommandsTests.LoadedOnlyForComponents;
var
  Text: string;
begin
  Text := Expand(Format(Knopf, ['/loaded']), 8);
  Assert.Contains(Text, '  protected'#10'    procedure Loaded; override;'#10);
  Assert.Contains(Text, 'procedure TKnopf.Loaded;'#10'begin'#10'  inherited Loaded;'#10'end;');
  Assert.AreEqual('', Expand(StringReplace(Format(Knopf, ['/loaded']), 'class(TComponent)', 'class(TObject)', []),
    8));
end;

procedure TComponentCommandsTests.NotificationExtendsExisting;
const
  Source =
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
  Text: string;
begin
  Text := Expand(Source, 12);
  Assert.Contains(Text, '    FQuelle := nil;'#10'  if (Operation = opRemove) and (AComponent = FZiel) then'#10 +
    '    FZiel := nil;'#10'end;');
  // Keine zweite Notification, keine doppelte Bedingung.
  Assert.AreEqual(1, Integer(Length(Text.Split(['procedure TVerbinder.Notification']))) - 1);
  Assert.AreEqual(1, Integer(Length(Text.Split(['(AComponent = FQuelle)']))) - 1);
  Assert.Contains(Text, 'begin'#10'  if FZiel <> nil then'#10'    FZiel.RemoveFreeNotification(Self);'#10 +
    '  FZiel := Value;'#10'  if FZiel <> nil then'#10'    FZiel.FreeNotification(Self);'#10'end;');
  // Zweiter Aufruf: nichts mehr zu tun.
  Assert.AreEqual('', Expand(StringReplace(Text, '  public'#10, '  public'#10'    /notification'#10, []), 12));
end;

procedure TComponentCommandsTests.OutsideClassFails;
const
  Outside = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'  %s'#10'end;'#10'end.';
var
  Command: string;
begin
  for Command in TArray<string>.Create('/notify OnChange', '/changed Farbe', '/loaded', '/notification') do
    Assert.AreEqual('', Expand(Format(Outside, [Command]), 5), Command);
end;

initialization
  TDUnitX.RegisterTestFixture(TComponentCommandsTests);

end.
