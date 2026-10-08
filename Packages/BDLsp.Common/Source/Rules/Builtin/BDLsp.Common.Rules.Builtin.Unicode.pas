unit BDLsp.Common.Rules.Builtin.Unicode;

// Unicode-Sicherheit im Quelltext (#150):
//   bidi-control          bidirektionale Steuerzeichen (Trojan Source, CVE-2021-42574)
//   invisible-char        unsichtbare und Nullbreiten-Zeichen
//   control-char          NUL- und Steuerzeichen sowie U+FFFD (ungültige Bytes beim Dekodieren)
//   confusable-identifier Bezeichner mit gemischten Schriften (z. B. kyrillisches "а"
//                         in lateinischem Namen, hohe Konfidenz) oder sonstigen
//                         Nicht-ASCII-Zeichen (niedrige Konfidenz, standardmäßig ausgeblendet)

interface

uses
  System.SysUtils,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Registry;

type
  TBidiControlRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInvisibleCharRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TControlCharRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TConfusableIdentifierRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert alle Unicode-Regeln.</summary>
procedure RegisterUnicodeRules(const ARegistry: TRuleRegistry);

implementation

uses
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Contract;

type
  TCharTest = function(C: Char): Boolean;

function IsBidiControl(C: Char): Boolean;
begin
  case Ord(C) of
    $061C, $200E, $200F, $202A..$202E, $2066..$2069:
      Result := True;
  else
    Result := False;
  end;
end;

function IsInvisible(C: Char): Boolean;
begin
  case Ord(C) of
    $00AD, $180E, $200B..$200D, $2060..$2064, $FEFF:
      Result := True;
  else
    Result := False;
  end;
end;

function IsBadControl(C: Char): Boolean;
begin
  case Ord(C) of
    0..8, 11, 14..31, $7F, $FFFD:
      Result := True;
  else
    Result := False;
  end;
end;

function CodeName(C: Char): string;
begin
  Result := 'U+' + IntToHex(Ord(C), 4);
end;

/// <summary>Meldet jedes Zeichen, das ATest erfüllt; die BOM am Dateianfang ist erlaubt.</summary>
procedure ReportChars(const AText: string; ATest: TCharTest; const AReport: IRuleReport;
  const AMessage: string);
var
  I, Line, Column: Integer;
  C: Char;
begin
  Line := 0;
  Column := 0;
  for I := 1 to Length(AText) do
  begin
    C := AText[I];
    if ATest(C) and not ((I = 1) and (Ord(C) = $FEFF)) then
      AReport.Add(TTextRange.Create(Line, Column, Line, Column + 1), Format(AMessage, [CodeName(C)]));
    if C = #10 then
    begin
      Inc(Line);
      Column := 0;
    end
    else
      Inc(Column);
  end;
end;

{ TBidiControlRule }

function TBidiControlRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('bidi-control', TRuleSeverity.Error,
    'Bidirektionale Steuerzeichen können Code anders anzeigen, als er kompiliert wird (Trojan Source)');
end;

procedure TBidiControlRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  ReportChars(AContext.Text, IsBidiControl, AReport,
    'Bidirektionales Steuerzeichen %s: Anzeige und Bedeutung können abweichen (Trojan Source)');
end;

{ TInvisibleCharRule }

function TInvisibleCharRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('invisible-char', TRuleSeverity.Warning,
    'Unsichtbare oder Nullbreiten-Zeichen im Quelltext');
end;

procedure TInvisibleCharRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  ReportChars(AContext.Text, IsInvisible, AReport, 'Unsichtbares Zeichen %s');
end;

{ TControlCharRule }

function TControlCharRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('control-char', TRuleSeverity.Error,
    'NUL- und Steuerzeichen oder ungültige Bytes (U+FFFD) im Quelltext');
end;

procedure TControlCharRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  ReportChars(AContext.Text, IsBadControl, AReport, 'Steuerzeichen oder ungültiges Byte %s');
end;

{ TConfusableIdentifierRule }

type
  TScript = (Other, Latin, Greek, Cyrillic);

function ScriptOf(C: Char): TScript;
begin
  case Ord(C) of
    Ord('A')..Ord('Z'), Ord('a')..Ord('z'), $00C0..$024F:
      Result := TScript.Latin;
    $0370..$03FF:
      Result := TScript.Greek;
    $0400..$04FF:
      Result := TScript.Cyrillic;
  else
    Result := TScript.Other;
  end;
end;

function TConfusableIdentifierRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('confusable-identifier', TRuleSeverity.Warning,
    'Bezeichner mit Zeichen aus mehreren Schriften oder Nicht-ASCII-Zeichen (Verwechslungsgefahr)');
end;

procedure TConfusableIdentifierRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Token: TPascalToken;
  C: Char;
  Scripts: set of TScript;
  NonAscii: Boolean;
  Range: TTextRange;
begin
  if AContext.Tree = nil then
    Exit;
  for Token in AContext.Tree.Tokens do
  begin
    if Token.Kind <> TPascalTokenKind.Identifier then
      Continue;
    Scripts := [];
    NonAscii := False;
    for C in Token.Text do
    begin
      if Ord(C) > 127 then
        NonAscii := True;
      Include(Scripts, ScriptOf(C));
    end;
    if not NonAscii then
      Continue;
    Range := TTextRange.Create(Token.StartPos, Token.EndPos);
    if (TScript.Latin in Scripts) and ((TScript.Greek in Scripts) or (TScript.Cyrillic in Scripts)) then
      AReport.Add(Range, Format('Bezeichner "%s" mischt Schriften; Verwechslung mit ähnlich aussehenden Namen möglich',
        [Token.Text]), TRuleConfidence.High)
    else
      AReport.Add(Range, Format('Bezeichner "%s" enthält Nicht-ASCII-Zeichen', [Token.Text]), TRuleConfidence.Low);
  end;
end;

procedure RegisterUnicodeRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TBidiControlRule.Create);
  ARegistry.Register(TInvisibleCharRule.Create);
  ARegistry.Register(TControlCharRule.Create);
  ARegistry.Register(TConfusableIdentifierRule.Create);
end;

end.
