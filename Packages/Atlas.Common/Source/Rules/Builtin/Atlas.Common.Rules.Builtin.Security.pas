unit Atlas.Common.Rules.Builtin.Security;

// Sicherheitsregeln, Teil 2 (#149), auf den Token der Datei:
//   security-command-injection          ShellExecute, CreateProcess, WinExec mit zusammengesetztem Argument
//   security-path-traversal             Dateizugriff mit Pfad aus Eingabedaten (experimentell)
//   security-weak-crypto                MD5, SHA-1, DES, RC4
//   security-tls-verification-disabled  Zertifikatsprüfung abgeschaltet oder immer erfolgreich
//   security-insecure-http              http://-URLs in Strings
//   security-insecure-random            Random für Token, Kennwörter, Salt, Nonce, Schlüssel
//   security-sql-injection              SQL-Text aus zusammengesetzten Nicht-Konstanten (#270)
//
// Ohne Datenflussanalyse (#143) erkennen die Regeln nur einfache Muster und
// melden mit mittlerer oder niedriger Konfidenz.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TSecurityCommandInjectionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSecurityPathTraversalRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSecurityWeakCryptoRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSecurityTlsVerificationDisabledRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSecurityInsecureHttpRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSecurityInsecureRandomRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSecuritySqlInjectionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterSecurityRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Derived;

const
  CommandCalls: array[0..7] of string = ('ShellExecute', 'ShellExecuteA', 'ShellExecuteW', 'ShellExecuteEx',
    'CreateProcess', 'CreateProcessA', 'CreateProcessW', 'WinExec');
  FileCalls: array[0..5] of string = ('AssignFile', 'LoadFromFile', 'SaveToFile', 'ReadAllText', 'ReadAllBytes',
    'WriteAllText');
  InputMarkers: array[0..3] of string = ('ParamStr', 'Text', 'Request', 'QueryFields');
  WeakCrypto: array[0..9] of string = ('THashMD5', 'THashSHA1', 'TIdHashMessageDigest5', 'TIdHashSHA1',
    'TDCP_des', 'TDCP_3des', 'TDCP_rc4', 'TCipher_DES', 'TCipher_RC4', 'TLbDES');
  SensitiveHash: array[0..2] of string = ('password', 'secret', 'signature');
  SensitiveRandom: array[0..6] of string = ('token', 'password', 'passwort', 'salt', 'nonce', 'key', 'secret');
  // URLs, die kein Netzverkehr sind oder lokal bleiben.
  // Dazu JSON-Schema-Kennungen ($schema, #1109).
  HttpExceptions: array[0..6] of string = ('http://localhost', 'http://127.0.0.1', 'http://[::1]',
    'http://www.w3.org/', 'http://schemas.', 'http://ns.', 'http://json-schema.org/');

/// <summary>Token ohne Kommentare und Direktiven, je Lauf einmal berechnet (Review P-03, P-08).</summary>
function CodeTokens(const AContext: TRuleContext): TArray<TPascalToken>;
var
  Cache: IRuleDerivedCache;
begin
  Cache := TRuleDerived.Open(AContext);
  Result := TRuleDerived.CodeTokens(Cache, AContext);
end;

function IsOneOf(const AText: string; const AWords: array of string): Boolean;
var
  Word: string;
begin
  for Word in AWords do
    if SameText(AText, Word) then
      Exit(True);
  Result := False;
end;

function ContainsOneOf(const AText: string; const AWords: array of string): Boolean;
var
  Word: string;
begin
  for Word in AWords do
    if ContainsText(AText, Word) then
      Exit(True);
  Result := False;
end;

function TokenRange(const AToken: TPascalToken): TTextRange;
begin
  Result := TTextRange.Create(AToken.StartPos, AToken.EndPos);
end;

/// <summary>Index der schließenden Klammer zu ATokens[AOpen]; -1 ohne.</summary>
function MatchingParen(const ATokens: TArray<TPascalToken>; AOpen: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  for Result := AOpen to High(ATokens) do
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit;
    end;
  Result := -1;
end;

/// <summary>Argumente eines Aufrufs als [Anfang, Ende]-Paare (Indizes inklusive).</summary>
function Arguments(const ATokens: TArray<TPascalToken>; AOpen, AClose: Integer): TArray<TArray<Integer>>;
var
  Index, Depth, Start: Integer;
begin
  Result := nil;
  Depth := 0;
  Start := AOpen + 1;
  for Index := AOpen + 1 to AClose do
  begin
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if (ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']')) and (Depth > 0) then
      Dec(Depth)
    else if (Depth = 0) and (ATokens[Index].IsSymbol(',') or (Index = AClose)) then
    begin
      if Index > Start then
        Result := Result + [TArray<Integer>.Create(Start, Index - 1)];
      Start := Index + 1;
    end;
  end;
end;

/// <summary>Zusammengesetzt (+, Format, Concat) und mit mindestens einem Bezeichner, der kein Cast ist?</summary>
function IsComposed(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Boolean;
var
  Index: Integer;
  Joined, Variable: Boolean;
begin
  Joined := False;
  Variable := False;
  for Index := AFirst to ALast do
    if ATokens[Index].IsSymbol('+') then
      Joined := True
    else if ATokens[Index].Kind = TPascalTokenKind.Identifier then
    begin
      if IsOneOf(ATokens[Index].Text, ['Format', 'Concat']) then
        Joined := True
      else if not IsOneOf(ATokens[Index].Text, ['PChar', 'PWideChar', 'PAnsiChar', 'string', 'nil']) then
        Variable := True;
    end;
  Result := Joined and Variable;
end;

const
  // Programme, die ihre Argumente als Befehle auslegen.
  ShellPrograms: array[0..13] of string = ('cmd', 'cmd.exe', 'powershell', 'powershell.exe', 'pwsh', 'pwsh.exe',
    'wscript', 'wscript.exe', 'cscript', 'cscript.exe', 'mshta', 'mshta.exe', 'bash', 'sh');

/// <summary>Inhalt eines String-Literals ohne die äußeren Hochkommas ('' bleibt ').</summary>
function LiteralValue(const AToken: TPascalToken): string;
begin
  Result := StringReplace(Copy(AToken.Text, 2, Length(AToken.Text) - 2), '''''', '''', [rfReplaceAll]);
end;

/// <summary>
/// ShellExecute mit festem Programm, das keine Shell ist, und Parametern, deren eingesetzte Werte alle in
/// Anführungszeichen stehen ('/select,"' + Pfad + '"'): Kein Befehlsinterpreter wertet die Parameter aus, und ein
/// Windows-Pfad kann kein " enthalten (#1109).
/// </summary>
function QuotedForFixedProgram(const ATokens: TArray<TPascalToken>; const AArgs: TArray<TArray<Integer>>): Boolean;
var
  First, Last, Index, Part: Integer;
  Parts: TArray<TArray<Integer>>;

  function IsLiteral(const ARange: TArray<Integer>): Boolean;
  begin
    Result := (ARange[0] = ARange[1]) and (ATokens[ARange[0]].Kind = TPascalTokenKind.StringLiteral);
  end;

begin
  Result := False;
  if (Length(AArgs) < 4) or (AArgs[2][0] <> AArgs[2][1]) or
    (ATokens[AArgs[2][0]].Kind <> TPascalTokenKind.StringLiteral) or
    IsOneOf(ExtractFileName(LiteralValue(ATokens[AArgs[2][0]])), ShellPrograms) then
    Exit;
  First := AArgs[3][0];
  Last := AArgs[3][1];
  // PChar(…) um die Parameter.
  if IsOneOf(ATokens[First].Text, ['PChar', 'PWideChar']) and (First < Last) and ATokens[First + 1].IsSymbol('(') and
    (MatchingParen(ATokens, First + 1) = Last) then
  begin
    Inc(First, 2);
    Dec(Last);
  end;
  // Glieder der Verkettung auf oberster Ebene.
  Parts := nil;
  Index := First;
  Part := First;
  while Index <= Last do
  begin
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
      Index := MatchingParen(ATokens, Index)
    else if ATokens[Index].IsSymbol('+') then
    begin
      Parts := Parts + [TArray<Integer>.Create(Part, Index - 1)];
      Part := Index + 1;
    end;
    if Index < 0 then
      Exit;
    Inc(Index);
  end;
  Parts := Parts + [TArray<Integer>.Create(Part, Last)];
  for Index := 0 to High(Parts) do
    if not IsLiteral(Parts[Index]) and ((Index = 0) or (Index = High(Parts)) or not IsLiteral(Parts[Index - 1]) or
      not IsLiteral(Parts[Index + 1]) or not EndsStr('"', LiteralValue(ATokens[Parts[Index - 1][0]])) or
      not StartsStr('"', LiteralValue(ATokens[Parts[Index + 1][0]]))) then
      Exit;
  Result := True;
end;

/// <summary>Anfang der Anweisung vor AIndex: Token nach ";", begin, then, else, do; sonst 0.</summary>
function StatementStart(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while Result > 0 do
  begin
    if ATokens[Result - 1].IsSymbol(';') or ATokens[Result - 1].IsKeyword('begin') or
      ATokens[Result - 1].IsKeyword('then') or ATokens[Result - 1].IsKeyword('else') or
      ATokens[Result - 1].IsKeyword('do') or ATokens[Result - 1].IsKeyword('try') or
      ATokens[Result - 1].IsKeyword('finally') or ATokens[Result - 1].IsKeyword('except') then
      Exit;
    Dec(Result);
  end;
end;

/// <summary>Index des ";" oder end am Ende der Anweisung ab AIndex.</summary>
function StatementEnd(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  Depth: Integer;
begin
  Depth := 0;
  for Result := AIndex to High(ATokens) do
  begin
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
      Dec(Depth)
    else if (Depth <= 0) and (ATokens[Result].IsSymbol(';') or ATokens[Result].IsKeyword('end') or
      ATokens[Result].IsKeyword('else')) then
      Exit;
  end;
  Result := High(ATokens);
end;

{ TSecurityCommandInjectionRule }

function TSecurityCommandInjectionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-command-injection', TRuleSeverity.Warning,
    'Befehl aus zusammengesetztem Text (Befehlsinjektion)');
end;

procedure TSecurityCommandInjectionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Index, Close: Integer;
  Argument: TArray<Integer>;
begin
  Tokens := CodeTokens(AContext);
  for Index := 0 to High(Tokens) - 1 do
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and IsOneOf(Tokens[Index].Text, CommandCalls) and
      Tokens[Index + 1].IsSymbol('(') then
    begin
      Close := MatchingParen(Tokens, Index + 1);
      if Close < 0 then
        Continue;
      if StartsText('ShellExecute', Tokens[Index].Text) and
        QuotedForFixedProgram(Tokens, Arguments(Tokens, Index + 1, Close)) then
        Continue;
      for Argument in Arguments(Tokens, Index + 1, Close) do
        if IsComposed(Tokens, Argument[0], Argument[1]) then
        begin
          AReport.Add(TokenRange(Tokens[Index]), Format('%s mit zusammengesetztem Argument: Eingaben könnten ' +
            'weitere Befehle einschleusen', [Tokens[Index].Text]), TRuleConfidence.Medium);
          Break;
        end;
    end;
end;

{ TSecurityPathTraversalRule }

function TSecurityPathTraversalRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-path-traversal', TRuleSeverity.Warning,
    'Dateizugriff mit Pfad aus Eingabedaten (Pfad-Traversal)', True);
end;

procedure TSecurityPathTraversalRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Index, Close, Inner: Integer;
  IsFileCall, FromInput, Checked: Boolean;
begin
  Tokens := CodeTokens(AContext);
  for Index := 0 to High(Tokens) - 1 do
  begin
    if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or not Tokens[Index + 1].IsSymbol('(') then
      Continue;
    IsFileCall := IsOneOf(Tokens[Index].Text, FileCalls) or
      (SameText(Tokens[Index].Text, 'Create') and (Index >= 2) and SameText(Tokens[Index - 2].Text, 'TFileStream'));
    if not IsFileCall then
      Continue;
    Close := MatchingParen(Tokens, Index + 1);
    if Close < 0 then
      Continue;
    FromInput := False;
    Checked := False;
    for Inner := Index + 2 to Close - 1 do
      if Tokens[Inner].Kind = TPascalTokenKind.Identifier then
      begin
        if IsOneOf(Tokens[Inner].Text, InputMarkers) then
          FromInput := True;
        if IsOneOf(Tokens[Inner].Text, ['GetFullPath', 'ExpandFileName', 'ExtractFileName']) then
          Checked := True;
      end;
    if FromInput and not Checked then
      AReport.Add(TokenRange(Tokens[Index]), Format('%s mit einem Pfad aus Eingabedaten ohne Prüfung; ".." ' +
        'könnte Dateien außerhalb des erwarteten Ordners erreichen', [Tokens[Index].Text]), TRuleConfidence.Medium);
  end;
end;

{ TSecurityWeakCryptoRule }

function TSecurityWeakCryptoRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-weak-crypto', TRuleSeverity.Hint,
    'Schwacher Kryptoalgorithmus (MD5, SHA-1, DES, RC4)');
end;

procedure TSecurityWeakCryptoRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Index, Inner, Stop: Integer;
  Confidence: TRuleConfidence;
begin
  Tokens := CodeTokens(AContext);
  for Index := 0 to High(Tokens) do
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and IsOneOf(Tokens[Index].Text, WeakCrypto) then
    begin
      // Prüfsummen sind legitim; nur mit Kennwort, Geheimnis oder Signatur in der Anweisung ist es mittel.
      Confidence := TRuleConfidence.Low;
      Stop := StatementEnd(Tokens, Index);
      for Inner := StatementStart(Tokens, Index) to Stop do
        if (Tokens[Inner].Kind = TPascalTokenKind.Identifier) and ContainsOneOf(Tokens[Inner].Text, SensitiveHash) then
          Confidence := TRuleConfidence.Medium;
      AReport.Add(TokenRange(Tokens[Index]), Format('%s ist für Sicherheitszwecke zu schwach; für Kennwörter und ' +
        'Signaturen SHA-256 oder besser verwenden', [Tokens[Index].Text]), Confidence);
    end;
end;

{ TSecurityTlsVerificationDisabledRule }

function TSecurityTlsVerificationDisabledRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-tls-verification-disabled', TRuleSeverity.Warning,
    'TLS-Zertifikatsprüfung abgeschaltet');
end;

procedure TSecurityTlsVerificationDisabledRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Index, Inner, Start, Depth: Integer;
  Header: string;
  InHeader: Boolean;
begin
  Tokens := CodeTokens(AContext);
  Header := '';
  Depth := 0;
  InHeader := False;
  for Index := 0 to High(Tokens) do
  begin
    // Kopf der aktuellen Routine merken (bis zum ersten ";" nach der Parameterliste).
    if Tokens[Index].IsKeyword('procedure') or Tokens[Index].IsKeyword('function') then
    begin
      Header := '';
      Depth := 0;
      InHeader := True;
    end;
    if InHeader then
    begin
      Header := Header + ' ' + Tokens[Index].Text;
      if Tokens[Index].IsSymbol('(') then
        Inc(Depth)
      else if Tokens[Index].IsSymbol(')') then
        Dec(Depth)
      else if (Depth = 0) and Tokens[Index].IsSymbol(';') then
        InHeader := False;
      Continue;
    end;
    if Index + 3 > High(Tokens) then
      Continue;
    // Indy: SSLOptions.VerifyMode := [];
    if SameText(Tokens[Index].Text, 'VerifyMode') and Tokens[Index + 1].IsSymbol(':=') and
      Tokens[Index + 2].IsSymbol('[') and Tokens[Index + 3].IsSymbol(']') then
    begin
      AReport.Add(TokenRange(Tokens[Index]), 'VerifyMode := [] schaltet die Prüfung des Serverzertifikats ab',
        TRuleConfidence.High);
      Continue;
    end;
    // Accepted := True bzw. Result := True ohne Bedingung in einem Prüf-Handler.
    if Tokens[Index + 1].IsSymbol(':=') and SameText(Tokens[Index + 2].Text, 'True') and
      (Tokens[Index + 3].IsSymbol(';') or Tokens[Index + 3].IsKeyword('end')) then
    begin
      Start := StatementStart(Tokens, Index);
      if (Start <> Index) or ((Index > 0) and (Tokens[Index - 1].IsKeyword('then') or
        Tokens[Index - 1].IsKeyword('else'))) then
        Continue;
      // Steht vorher im Rumpf eine Bedingung, wird geprüft.
      Inner := Index - 1;
      while (Inner > 0) and not (Tokens[Inner].IsKeyword('procedure') or Tokens[Inner].IsKeyword('function')) do
      begin
        if Tokens[Inner].IsKeyword('if') or Tokens[Inner].IsKeyword('case') then
          Break;
        Dec(Inner);
      end;
      if (Inner > 0) and (Tokens[Inner].IsKeyword('if') or Tokens[Inner].IsKeyword('case')) then
        Continue;
      if (IsOneOf(Tokens[Index].Text, ['Accepted', 'AAccepted']) and ContainsText(Header, 'Certificate')) or
        (SameText(Tokens[Index].Text, 'Result') and (ContainsText(Header, 'TIdX509') or
        ContainsText(Header, 'VerifyPeer'))) then
        AReport.Add(TokenRange(Tokens[Index]), 'Der Handler akzeptiert jedes Serverzertifikat ohne Prüfung',
          TRuleConfidence.High);
    end;
  end;
end;

{ TSecurityInsecureHttpRule }

function TSecurityInsecureHttpRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-insecure-http', TRuleSeverity.Hint, 'Unverschlüsselte http://-URL');
end;

procedure TSecurityInsecureHttpRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Index, Offset: Integer;
  Lower: string;
  Excepted: Boolean;
  Exception_: string;
  Start: TTextPosition;
begin
  Tokens := CodeTokens(AContext);
  for Index := 0 to High(Tokens) do
  begin
    if Tokens[Index].Kind <> TPascalTokenKind.StringLiteral then
      Continue;
    Lower := LowerCase(Tokens[Index].Text);
    if Pos('xmlns', Lower) > 0 then
      Continue;
    // Erste URL mit Rechnernamen: Ein bloßes 'http://' (StartsText('http://', Url), Hilfetext "http:// oder
    // https://") nennt kein Ziel (#1109).
    Offset := Pos('http://', Lower);
    while Offset > 0 do
    begin
      Excepted := not CharInSet(Copy(Lower + ' ', Offset + Length('http://'), 1)[1], ['a'..'z', '0'..'9', '[']);
      for Exception_ in HttpExceptions do
        if Copy(Lower, Offset, Length(Exception_)) = Exception_ then
          Excepted := True;
      if not Excepted then
        Break;
      Offset := PosEx('http://', Lower, Offset + 1);
    end;
    if Offset = 0 then
      Continue;
    // Einzeilige Strings: Spalte des "http://" im Token.
    if Tokens[Index].StartPos.Line <> Tokens[Index].EndPos.Line then
    begin
      AReport.Add(TokenRange(Tokens[Index]), 'Unverschlüsselte http://-URL; https:// verwenden', TRuleConfidence.Medium);
      Continue;
    end;
    Start := TTextPosition.Create(Tokens[Index].StartPos.Line, Tokens[Index].StartPos.Character + Offset - 1);
    AReport.Add(TTextRange.Create(Start.Line, Start.Character, Start.Line, Start.Character + Length('http://')),
      'Unverschlüsselte http://-URL; https:// verwenden', TRuleConfidence.Medium,
      [TRuleFix.Create('http:// durch https:// ersetzen',
      [TRuleEdit.Create(TTextRange.Create(Start.Line, Start.Character, Start.Line, Start.Character + Length('http://')),
      Copy(Tokens[Index].Text, Offset, 4) + 's://')])]);
  end;
end;

{ TSecurityInsecureRandomRule }

function TSecurityInsecureRandomRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-insecure-random', TRuleSeverity.Warning,
    'Random für sicherheitsrelevante Werte');
end;

procedure TSecurityInsecureRandomRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Index, Inner, Stop, Target: Integer;
begin
  Tokens := CodeTokens(AContext);
  for Index := 1 to High(Tokens) do
  begin
    if not Tokens[Index].IsSymbol(':=') then
      Continue;
    // Ziel der Zuweisung: letzter Bezeichner vor := (auch Self.FToken).
    Target := Index - 1;
    if (Tokens[Target].Kind <> TPascalTokenKind.Identifier) or
      not ContainsOneOf(Tokens[Target].Text, SensitiveRandom) then
      Continue;
    Stop := StatementEnd(Tokens, Index + 1);
    for Inner := Index + 1 to Stop do
      if (Tokens[Inner].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Inner].Text, 'Random') then
      begin
        AReport.Add(TokenRange(Tokens[Inner]), Format('Random ist vorhersagbar und für %s ungeeignet; einen ' +
          'kryptografischen Zufallsgenerator verwenden', [Tokens[Target].Text]), TRuleConfidence.Medium);
        Break;
      end;
  end;
end;

{ TSecuritySqlInjectionRule }

function TSecuritySqlInjectionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-sql-injection', TRuleSeverity.Warning,
    'SQL-Text aus zusammengesetzten Werten (SQL-Injection)');
end;

const
  SqlCalls: array[0..4] of string = ('ExecSQL', 'Open', 'ExecSQLScalar', 'ExecuteDirect', 'Execute');
  // Allgemeine Namen (Dialog.Execute, Datei.Open): SQL nur, wenn ein Literal im Argument SQL enthält (#1109).
  GenericSqlCalls: array[0..1] of string = ('Open', 'Execute');
  SqlKeywords: array[0..9] of string = ('select', 'insert', 'update', 'delete', 'merge', 'where', 'from',
    'values', 'exec', 'truncate');
  // Umwandlungen, deren Ergebnis keine SQL-Syntax einschleusen kann.
  SafeConversions: array[0..5] of string = ('IntToStr', 'QuotedStr', 'FloatToStr', 'IntToHex', 'BoolToStr',
    'UIntToStr');
  // Bezeichner, die Benutzereingaben liefern: TEdit.Text, TMemo.Lines, ParamStr, Webanfragen.
  UserInputs: array[0..5] of string = ('Text', 'Lines', 'ParamStr', 'Request', 'QueryFields', 'ContentFields');

/// <summary>Namen aus const- und resourcestring-Abschnitten der Datei.</summary>
function ConstantNames(const ATokens: TArray<TPascalToken>): TArray<string>;
var
  Index, Depth: Integer;
  InConst: Boolean;
begin
  Result := nil;
  InConst := False;
  Depth := 0;
  for Index := 0 to High(ATokens) - 1 do
  begin
    // "const" in Parameterlisten ist kein Konstantenabschnitt.
    if ATokens[Index].IsSymbol('(') or ATokens[Index].IsSymbol('[') then
      Inc(Depth)
    else if ATokens[Index].IsSymbol(')') or ATokens[Index].IsSymbol(']') then
      Dec(Depth)
    else if Depth > 0 then
      Continue
    else if ATokens[Index].IsKeyword('const') or ATokens[Index].IsKeyword('resourcestring') then
      InConst := True
    else if ATokens[Index].IsKeyword('var') or ATokens[Index].IsKeyword('type') or
      ATokens[Index].IsKeyword('begin') or ATokens[Index].IsKeyword('procedure') or
      ATokens[Index].IsKeyword('function') or ATokens[Index].IsKeyword('implementation') then
      InConst := False
    else if InConst and (ATokens[Index].Kind = TPascalTokenKind.Identifier) and
      (ATokens[Index + 1].IsSymbol('=') or ATokens[Index + 1].IsSymbol(':')) and
      ((Index = 0) or not ATokens[Index - 1].IsSymbol('.')) then
      Result := Result + [ATokens[Index].Text];
  end;
end;

/// <summary>Enthält ein String-Literal in ATokens[AFirst..ALast] ein SQL-Schlüsselwort als ganzes Wort?</summary>
function HasSqlLiteral(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Boolean;
var
  Index, Start, After: Integer;
  Text, Word: string;
begin
  for Index := AFirst to ALast do
    if ATokens[Index].Kind = TPascalTokenKind.StringLiteral then
    begin
      Text := LowerCase(LiteralValue(ATokens[Index]));
      for Word in SqlKeywords do
      begin
        Start := Pos(Word, Text);
        while Start > 0 do
        begin
          After := Start + Length(Word);
          if ((Start = 1) or not CharInSet(Text[Start - 1], ['a'..'z', '0'..'9', '_'])) and
            ((After > Length(Text)) or not CharInSet(Text[After], ['a'..'z', '0'..'9', '_'])) then
            Exit(True);
          Start := PosEx(Word, Text, Start + 1);
        end;
      end;
    end;
  Result := False;
end;

/// <summary>Ist der SQL-Ausdruck ATokens[AFirst..ALast] aus Nicht-Konstanten zusammengesetzt?
/// AFromInput: eine Quelle ist Benutzereingabe.</summary>
function IsComposedSql(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  const AConstants: TArray<string>; out AFromInput: Boolean): Boolean;
var
  Index, Close: Integer;
  Joined, Variable: Boolean;
begin
  Joined := False;
  Variable := False;
  AFromInput := False;
  Index := AFirst;
  while Index <= ALast do
  begin
    if ATokens[Index].IsSymbol('+') then
      Joined := True
    else if ATokens[Index].Kind = TPascalTokenKind.Identifier then
    begin
      if IsOneOf(ATokens[Index].Text, SafeConversions) and (Index < ALast) and ATokens[Index + 1].IsSymbol('(') then
      begin
        // IntToStr(Id), QuotedStr(Name): Inhalt überspringen.
        Close := MatchingParen(ATokens, Index + 1);
        if Close > 0 then
          Index := Close;
      end
      else if IsOneOf(ATokens[Index].Text, ['Format', 'Concat']) then
        Joined := True
      else if not IsOneOf(ATokens[Index].Text, AConstants) and
        not IsOneOf(ATokens[Index].Text, ['string', 'nil', 'sLineBreak']) then
      begin
        Variable := True;
        if IsOneOf(ATokens[Index].Text, UserInputs) then
          AFromInput := True;
      end;
    end;
    Inc(Index);
  end;
  Result := Joined and Variable;
end;

procedure TSecuritySqlInjectionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Constants: TArray<string>;
  Index, First, Last, Close: Integer;
  Sink: TPascalToken;
  FromInput: Boolean;
  Confidence: TRuleConfidence;
  Argument: TArray<Integer>;
begin
  Tokens := CodeTokens(AContext);
  Constants := ConstantNames(Tokens);
  for Index := 0 to High(Tokens) - 2 do
  begin
    if Tokens[Index].Kind <> TPascalTokenKind.Identifier then
      Continue;
    First := -1;
    Last := -1;
    Sink := Tokens[Index];
    // SQL.Text := …, CommandText := …
    if ((SameText(Tokens[Index].Text, 'Text') and (Index >= 2) and Tokens[Index - 1].IsSymbol('.') and
      SameText(Tokens[Index - 2].Text, 'SQL')) or SameText(Tokens[Index].Text, 'CommandText')) and
      Tokens[Index + 1].IsSymbol(':=') then
    begin
      First := Index + 2;
      Last := StatementEnd(Tokens, First) - 1;
    end
    // SQL.Add(…), ExecSQL(…), Open(…)
    else if Tokens[Index + 1].IsSymbol('(') and ((SameText(Tokens[Index].Text, 'Add') and (Index >= 2) and
      Tokens[Index - 1].IsSymbol('.') and SameText(Tokens[Index - 2].Text, 'SQL')) or
      (IsOneOf(Tokens[Index].Text, SqlCalls) and (Index >= 1) and Tokens[Index - 1].IsSymbol('.'))) then
    begin
      Close := MatchingParen(Tokens, Index + 1);
      if Close < 0 then
        Continue;
      for Argument in Arguments(Tokens, Index + 1, Close) do
      begin
        // Nur das erste Argument ist der SQL-Text; weitere sind Parameterwerte.
        First := Argument[0];
        Last := Argument[1];
        Break;
      end;
    end;
    if (First < 0) or (Last < First) then
      Continue;
    if not IsComposedSql(Tokens, First, Last, Constants, FromInput) then
      Continue;
    if IsOneOf(Sink.Text, GenericSqlCalls) and not HasSqlLiteral(Tokens, First, Last) then
      Continue;
    if FromInput then
      Confidence := TRuleConfidence.High
    else
      Confidence := TRuleConfidence.Medium;
    AReport.Add(TokenRange(Sink), 'SQL-Text wird aus Werten zusammengesetzt: Eingaben könnten SQL einschleusen. ' +
      'Parameter verwenden (:Name, ParamByName)', Confidence);
  end;
end;

procedure RegisterSecurityRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TSecurityCommandInjectionRule.Create);
  ARegistry.Register(TSecurityPathTraversalRule.Create);
  ARegistry.Register(TSecurityWeakCryptoRule.Create);
  ARegistry.Register(TSecurityTlsVerificationDisabledRule.Create);
  ARegistry.Register(TSecurityInsecureHttpRule.Create);
  ARegistry.Register(TSecurityInsecureRandomRule.Create);
  ARegistry.Register(TSecuritySqlInjectionRule.Create);
end;

end.
