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
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.Derived,
  Atlas.Text.Chars,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TSecurityText = (CommandTitle, Command, PathTitle, Path, CryptoTitle, Crypto, TlsTitle, VerifyMode, AcceptsAny,
    HttpTitle, Http, ToHttps, RandomTitle, Random, SqlTitle, Sql);

const
  cTexts: array[TSecurityText] of TAtlasText = (
    (De: 'Befehl aus zusammengesetztem Text (Befehlsinjektion)'; En: 'Command from composed text (command injection)'),
    (De: '%s mit zusammengesetztem Argument: Eingaben könnten weitere Befehle einschleusen';
     En: '%s with composed argument: inputs could inject further commands'),
    (De: 'Dateizugriff mit Pfad aus Eingabedaten (Pfad-Traversal)';
     En: 'File access with path from input data (path traversal)'),
    (De: '%s mit einem Pfad aus Eingabedaten ohne Prüfung; ".." könnte Dateien außerhalb des erwarteten Ordners ' +
      'erreichen';
     En: '%s with a path from input data without check; ".." could reach files outside the expected folder'),
    (De: 'Schwacher Kryptoalgorithmus (MD5, SHA-1, DES, RC4)'; En: 'Weak crypto algorithm (MD5, SHA-1, DES, RC4)'),
    (De: '%s ist für Sicherheitszwecke zu schwach; für Kennwörter und Signaturen SHA-256 oder besser verwenden';
     En: '%s is too weak for security purposes; use SHA-256 or better for passwords and signatures'),
    (De: 'TLS-Zertifikatsprüfung abgeschaltet'; En: 'TLS certificate check switched off'),
    (De: 'VerifyMode := [] schaltet die Prüfung des Serverzertifikats ab';
     En: 'VerifyMode := [] switches off the check of the server certificate'),
    (De: 'Der Handler akzeptiert jedes Serverzertifikat ohne Prüfung';
     En: 'The handler accepts every server certificate without check'),
    (De: 'Unverschlüsselte http://-URL'; En: 'Unencrypted http:// URL'),
    (De: 'Unverschlüsselte http://-URL; https:// verwenden'; En: 'Unencrypted http:// URL; use https://'),
    (De: 'http:// durch https:// ersetzen'; En: 'Replace http:// with https://'),
    (De: 'Random für sicherheitsrelevante Werte'; En: 'Random for security-relevant values'),
    (De: 'Random ist vorhersagbar und für %s ungeeignet; einen kryptografischen Zufallsgenerator verwenden';
     En: 'Random is predictable and unsuitable for %s; use a cryptographic random generator'),
    (De: 'SQL-Text aus zusammengesetzten Werten (SQL-Injection)'; En: 'SQL text from composed values (SQL injection)'),
    (De: 'SQL-Text wird aus Werten zusammengesetzt: Eingaben könnten SQL einschleusen. Parameter verwenden (:Name, ' +
      'ParamByName)';
     En: 'SQL text is composed from values: inputs could inject SQL. Use parameters (:Name, ParamByName)'));

{$SCOPEDENUMS OFF}

const
  cCommandCalls: array[0..7] of string = ('ShellExecute', 'ShellExecuteA', 'ShellExecuteW', 'ShellExecuteEx',
    'CreateProcess', 'CreateProcessA', 'CreateProcessW', 'WinExec');
  cFileCalls: array[0..5] of string = ('AssignFile', 'LoadFromFile', 'SaveToFile', 'ReadAllText', 'ReadAllBytes',
    'WriteAllText');
  cInputMarkers: array[0..3] of string = ('ParamStr', 'Text', 'Request', 'QueryFields');
  cWeakCrypto: array[0..9] of string = ('THashMD5', 'THashSHA1', 'TIdHashMessageDigest5', 'TIdHashSHA1',
    'TDCP_des', 'TDCP_3des', 'TDCP_rc4', 'TCipher_DES', 'TCipher_RC4', 'TLbDES');
  cSensitiveHash: array[0..2] of string = ('password', 'secret', 'signature');
  cSensitiveRandom: array[0..6] of string = ('token', 'password', 'passwort', 'salt', 'nonce', 'key', 'secret');
  // URLs, die kein Netzverkehr sind oder lokal bleiben.
  // Dazu JSON-Schema-Kennungen ($schema, #1109).
  cHttpExceptions: array[0..6] of string = ('http://localhost', 'http://127.0.0.1', 'http://[::1]',
    'http://www.w3.org/', 'http://schemas.', 'http://ns.', 'http://json-schema.org/');

/// <summary>Token ohne Kommentare und Direktiven, je Lauf einmal berechnet.</summary>
function CodeTokens(const AContext: TRuleContext): TArray<TPascalToken>;
var
  mCache: IRuleDerivedCache;
begin
  mCache := TRuleDerived.Open(AContext);
  Result := TRuleDerived.CodeTokens(mCache, AContext);
end;

function IsOneOf(const AText: string; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  for mWord in AWords do
  begin
    if SameText(AText, mWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function ContainsOneOf(const AText: string; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  for mWord in AWords do
  begin
    if ContainsText(AText, mWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TokenRange(const AToken: TPascalToken): TTextRange;
begin
  Result := TTextRange.Create(AToken.StartPos, AToken.EndPos);
end;

/// <summary>Argumente eines Aufrufs als [Anfang, Ende]-Paare (Indizes inklusive).</summary>
function Arguments(const ATokens: TArray<TPascalToken>; AOpen, AClose: Integer): TArray<TArray<Integer>>;
var
  mIndex, mDepth, mStart: Integer;
begin
  Result := nil;
  mDepth := 0;
  mStart := AOpen + 1;
  for mIndex := AOpen + 1 to AClose do
  begin
    if ATokens[mIndex].IsSymbol('(') or ATokens[mIndex].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if (ATokens[mIndex].IsSymbol(')') or ATokens[mIndex].IsSymbol(']')) and (mDepth > 0) then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and (ATokens[mIndex].IsSymbol(',') or (mIndex = AClose)) then
    begin
      if mIndex > mStart then
      begin
        Result := Result + [TArray<Integer>.Create(mStart, mIndex - 1)];
      end;
      mStart := mIndex + 1;
    end;
  end;
end;

/// <summary>Zusammengesetzt (+, Format, Concat) und mit mindestens einem Bezeichner, der kein Cast ist?</summary>
function IsComposed(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
  mJoined, mVariable: Boolean;
begin
  mJoined := False;
  mVariable := False;
  for mIndex := AFirst to ALast do
  begin
    if ATokens[mIndex].IsSymbol('+') then
    begin
      mJoined := True;
    end
    else if ATokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      if IsOneOf(ATokens[mIndex].Text, ['Format', 'Concat']) then
      begin
        mJoined := True;
      end
      else if not IsOneOf(ATokens[mIndex].Text, ['PChar', 'PWideChar', 'PAnsiChar', 'string', 'nil']) then
      begin
        mVariable := True;
      end;
    end;
  end;
  Result := mJoined and mVariable;
end;

const
  // Programme, die ihre Argumente als Befehle auslegen.
  cShellPrograms: array[0..13] of string = ('cmd', 'cmd.exe', 'powershell', 'powershell.exe', 'pwsh', 'pwsh.exe',
    'wscript', 'wscript.exe', 'cscript', 'cscript.exe', 'mshta', 'mshta.exe', 'bash', 'sh');

/// <summary>Inhalt eines String-Literals ohne die äußeren Hochkommas ('' bleibt ').</summary>
function LiteralValue(const AToken: TPascalToken): string;
begin
  Result := StringReplace(Copy(AToken.Text, 2, Length(AToken.Text) - 2), '''''', '''', [rfReplaceAll]);
end;

/// <summary>Ist AToken eines der Schlüsselwörter AWords?</summary>
function IsAnyKeyword(const AToken: TPascalToken; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  for mWord in AWords do
  begin
    if AToken.IsKeyword(mWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ist der Bereich ARange (erstes und letztes Token) genau ein String-Literal?</summary>
function IsLiteralPart(const ATokens: TArray<TPascalToken>; const ARange: TArray<Integer>): Boolean;
begin
  Result := (ARange[0] = ARange[1]) and (ATokens[ARange[0]].Kind = TPascalTokenKind.StringLiteral);
end;

/// <summary>Ist das Programm (drittes Argument von ShellExecute) ein festes Literal, das keine Shell ist?</summary>
function IsFixedProgram(const ATokens: TArray<TPascalToken>; const AArgs: TArray<TArray<Integer>>): Boolean;
begin
  Result := (Length(AArgs) >= 4) and IsLiteralPart(ATokens, AArgs[2]) and
    not IsOneOf(ExtractFileName(LiteralValue(ATokens[AArgs[2][0]])), cShellPrograms);
end;

/// <summary>Glieder der Verkettung ATokens[AFirst..ALast] auf oberster Ebene; False bei offener Klammer.</summary>
function ConcatParts(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  out AParts: TArray<TArray<Integer>>): Boolean;
var
  mIndex, mPart: Integer;
begin
  AParts := nil;
  mIndex := AFirst;
  mPart := AFirst;
  while mIndex <= ALast do
  begin
    if ATokens[mIndex].IsSymbol('(') or ATokens[mIndex].IsSymbol('[') then
    begin
      mIndex := MatchingParen(ATokens, mIndex);
    end
    else if ATokens[mIndex].IsSymbol('+') then
    begin
      AParts := AParts + [TArray<Integer>.Create(mPart, mIndex - 1)];
      mPart := mIndex + 1;
    end;
    if mIndex < 0 then
    begin
      Exit(False);
    end;
    Inc(mIndex);
  end;
  AParts := AParts + [TArray<Integer>.Create(mPart, ALast)];
  Result := True;
end;

/// <summary>Ist das Glied AIndex ein Literal oder ein Wert zwischen zwei Literalen, die mit " enden bzw.
/// beginnen?</summary>
function QuotedPart(const ATokens: TArray<TPascalToken>; const AParts: TArray<TArray<Integer>>;
  AIndex: Integer): Boolean;
begin
  if IsLiteralPart(ATokens, AParts[AIndex]) then
  begin
    Exit(True);
  end;
  Result := (AIndex > 0) and (AIndex < High(AParts)) and IsLiteralPart(ATokens, AParts[AIndex - 1]) and
    IsLiteralPart(ATokens, AParts[AIndex + 1]);
  Result := Result and EndsStr('"', LiteralValue(ATokens[AParts[AIndex - 1][0]])) and
    StartsStr('"', LiteralValue(ATokens[AParts[AIndex + 1][0]]));
end;

/// <summary>
/// ShellExecute mit festem Programm, das keine Shell ist, und Parametern, deren eingesetzte Werte alle in
/// Anführungszeichen stehen ('/select,"' + Pfad + '"'): Kein Befehlsinterpreter wertet die Parameter aus, und ein
/// Windows-Pfad kann kein " enthalten (#1109).
/// </summary>
function QuotedForFixedProgram(const ATokens: TArray<TPascalToken>; const AArgs: TArray<TArray<Integer>>): Boolean;
var
  mFirst, mLast, mIndex: Integer;
  mParts: TArray<TArray<Integer>>;
begin
  if not IsFixedProgram(ATokens, AArgs) then
  begin
    Exit(False);
  end;
  mFirst := AArgs[3][0];
  mLast := AArgs[3][1];
  // PChar(…) um die Parameter.
  if IsOneOf(ATokens[mFirst].Text, ['PChar', 'PWideChar']) and (mFirst < mLast) and
    ATokens[mFirst + 1].IsSymbol('(') and (MatchingParen(ATokens, mFirst + 1) = mLast) then
  begin
    Inc(mFirst, 2);
    Dec(mLast);
  end;
  Result := ConcatParts(ATokens, mFirst, mLast, mParts);
  mIndex := 0;
  while Result and (mIndex <= High(mParts)) do
  begin
    Result := QuotedPart(ATokens, mParts, mIndex);
    Inc(mIndex);
  end;
end;

/// <summary>Anfang der Anweisung vor AIndex: Token nach ";", begin, then, else, do; sonst 0.</summary>
function StatementStart(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result > 0) and not ATokens[Result - 1].IsSymbol(';') and not IsAnyKeyword(ATokens[Result - 1],
    ['begin', 'then', 'else', 'do', 'try', 'finally', 'except']) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Index des ";" oder end am Ende der Anweisung ab AIndex.</summary>
function StatementEnd(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  for Result := AIndex to High(ATokens) do
  begin
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(mDepth);
    end
    else if (mDepth <= 0) and (ATokens[Result].IsSymbol(';') or ATokens[Result].IsKeyword('end') or
      ATokens[Result].IsKeyword('else')) then
    begin
      Exit;
    end;
  end;
  Result := High(ATokens);
end;

{ TSecurityCommandInjectionRule }

function TSecurityCommandInjectionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-command-injection', TRuleSeverity.Warning,
    cTexts[TSecurityText.CommandTitle].Text);
end;

/// <summary>Steht bei AIndex ein Aufruf eines Befehls (CommandCalls) mit Klammer?</summary>
function IsCommandCall(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and IsOneOf(ATokens[AIndex].Text, cCommandCalls) and
    ATokens[AIndex + 1].IsSymbol('(');
end;

/// <summary>Hat der Befehlsaufruf bei AIndex (Klammer bis AClose) ein zusammengesetztes Argument?</summary>
function HasComposedCommand(const ATokens: TArray<TPascalToken>; AIndex, AClose: Integer): Boolean;
var
  mArgs: TArray<TArray<Integer>>;
  mArgument: TArray<Integer>;
begin
  mArgs := Arguments(ATokens, AIndex + 1, AClose);
  if StartsText('ShellExecute', ATokens[AIndex].Text) and QuotedForFixedProgram(ATokens, mArgs) then
  begin
    Exit(False);
  end;
  for mArgument in mArgs do
  begin
    if IsComposed(ATokens, mArgument[0], mArgument[1]) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TSecurityCommandInjectionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mIndex, mClose: Integer;
begin
  mTokens := CodeTokens(AContext);
  for mIndex := 0 to High(mTokens) - 1 do
  begin
    if not IsCommandCall(mTokens, mIndex) then
    begin
      Continue;
    end;
    mClose := MatchingParen(mTokens, mIndex + 1);
    if (mClose >= 0) and HasComposedCommand(mTokens, mIndex, mClose) then
    begin
      AReport.Add(TokenRange(mTokens[mIndex]), cTexts[TSecurityText.Command].Fmt([mTokens[mIndex].Text]),
        TRuleConfidence.Medium);
    end;
  end;
end;

{ TSecurityPathTraversalRule }

function TSecurityPathTraversalRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-path-traversal', TRuleSeverity.Warning,
    cTexts[TSecurityText.PathTitle].Text);
end;

/// <summary>Nennt AIndex einen Dateizugriff (FileCalls, TFileStream.Create)?</summary>
function IsFileCallName(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := IsOneOf(ATokens[AIndex].Text, cFileCalls) or (SameText(ATokens[AIndex].Text, 'Create') and (AIndex >= 2) and
    SameText(ATokens[AIndex - 2].Text, 'TFileStream'));
end;

/// <summary>Steht bei AIndex ein Dateizugriff mit Klammer?</summary>
function IsFileCall(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and ATokens[AIndex + 1].IsSymbol('(') and
    IsFileCallName(ATokens, AIndex);
end;

/// <summary>Nennt ATokens[AFirst..ALast] Eingabedaten, ohne den Pfad zu prüfen (GetFullPath …)?</summary>
function UncheckedInput(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Boolean;
var
  mInner: Integer;
  mFromInput, mChecked: Boolean;
begin
  mFromInput := False;
  mChecked := False;
  for mInner := AFirst to ALast do
  begin
    if ATokens[mInner].Kind = TPascalTokenKind.Identifier then
    begin
      mFromInput := mFromInput or IsOneOf(ATokens[mInner].Text, cInputMarkers);
      mChecked := mChecked or IsOneOf(ATokens[mInner].Text, ['GetFullPath', 'ExpandFileName', 'ExtractFileName']);
    end;
  end;
  Result := mFromInput and not mChecked;
end;

procedure TSecurityPathTraversalRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mIndex, mClose: Integer;
  mArguments: TArray<TArray<Integer>>;
begin
  mTokens := CodeTokens(AContext);
  for mIndex := 0 to High(mTokens) - 1 do
  begin
    if not IsFileCall(mTokens, mIndex) then
    begin
      Continue;
    end;
    mClose := MatchingParen(mTokens, mIndex + 1);
    if mClose < 0 then
    begin
      Continue;
    end;
    // Nur der Pfad (erstes Argument) zählt: WriteAllText(Pfad, Liste.Text) schreibt Eingabedaten, aber nicht dorthin,
    // wohin sie zeigen.
    mArguments := Arguments(mTokens, mIndex + 1, mClose);
    if (Length(mArguments) > 0) and UncheckedInput(mTokens, mArguments[0][0], mArguments[0][1]) then
    begin
      AReport.Add(TokenRange(mTokens[mIndex]), cTexts[TSecurityText.Path].Fmt([mTokens[mIndex].Text]),
        TRuleConfidence.Medium);
    end;
  end;
end;

{ TSecurityWeakCryptoRule }

function TSecurityWeakCryptoRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-weak-crypto', TRuleSeverity.Hint,
    cTexts[TSecurityText.CryptoTitle].Text);
end;

procedure TSecurityWeakCryptoRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mIndex, mInner, mStop: Integer;
  mConfidence: TRuleConfidence;
begin
  mTokens := CodeTokens(AContext);
  for mIndex := 0 to High(mTokens) do
  begin
    if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and IsOneOf(mTokens[mIndex].Text, cWeakCrypto) then
    begin
      // Prüfsummen sind legitim; nur mit Kennwort, Geheimnis oder Signatur in der Anweisung ist es mittel.
      mConfidence := TRuleConfidence.Low;
      mStop := StatementEnd(mTokens, mIndex);
      for mInner := StatementStart(mTokens, mIndex) to mStop do
      begin
        if (mTokens[mInner].Kind = TPascalTokenKind.Identifier) and
          ContainsOneOf(mTokens[mInner].Text, cSensitiveHash) then
        begin
          mConfidence := TRuleConfidence.Medium;
        end;
      end;
      AReport.Add(TokenRange(mTokens[mIndex]), cTexts[TSecurityText.Crypto].Fmt([mTokens[mIndex].Text]), mConfidence);
    end;
  end;
end;

{ TSecurityTlsVerificationDisabledRule }

function TSecurityTlsVerificationDisabledRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-tls-verification-disabled', TRuleSeverity.Warning,
    cTexts[TSecurityText.TlsTitle].Text);
end;

type
  /// <summary>Kopf der aktuellen Routine (bis zum ersten ";" nach der Parameterliste).</summary>
  THeaderTracker = record
    Header: string;
    Depth: Integer;
    InHeader: Boolean;
    /// <summary>Nimmt AToken auf; True, solange es zum Kopf gehört.</summary>
    function Feed(const AToken: TPascalToken): Boolean;
  end;

function THeaderTracker.Feed(const AToken: TPascalToken): Boolean;
begin
  if AToken.IsKeyword('procedure') or AToken.IsKeyword('function') then
  begin
    Header := '';
    Depth := 0;
    InHeader := True;
  end;
  Result := InHeader;
  if not InHeader then
  begin
    Exit;
  end;
  Header := Header + ' ' + AToken.Text;
  if AToken.IsSymbol('(') then
  begin
    Inc(Depth);
  end
  else if AToken.IsSymbol(')') then
  begin
    Dec(Depth);
  end
  else if (Depth = 0) and AToken.IsSymbol(';') then
  begin
    InHeader := False;
  end;
end;

/// <summary>Indy: SSLOptions.VerifyMode := [];</summary>
function IsClearedVerifyMode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := SameText(ATokens[AIndex].Text, 'VerifyMode') and ATokens[AIndex + 1].IsSymbol(':=') and
    ATokens[AIndex + 2].IsSymbol('[') and ATokens[AIndex + 3].IsSymbol(']');
end;

/// <summary>X := True; bei AIndex?</summary>
function IsTrueAssignment(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := ATokens[AIndex + 1].IsSymbol(':=') and SameText(ATokens[AIndex + 2].Text, 'True') and
    (ATokens[AIndex + 3].IsSymbol(';') or ATokens[AIndex + 3].IsKeyword('end'));
end;

/// <summary>Steht die Anweisung bei AIndex für sich und ohne vorherige Bedingung im Rumpf?</summary>
function IsUnconditional(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mInner: Integer;
begin
  if (StatementStart(ATokens, AIndex) <> AIndex) or ((AIndex > 0) and
    IsAnyKeyword(ATokens[AIndex - 1], ['then', 'else'])) then
  begin
    Exit(False);
  end;
  // Steht vorher im Rumpf eine Bedingung, wird geprüft.
  mInner := AIndex - 1;
  while (mInner > 0) and not IsAnyKeyword(ATokens[mInner], ['procedure', 'function', 'if', 'case']) do
  begin
    Dec(mInner);
  end;
  Result := (mInner <= 0) or not IsAnyKeyword(ATokens[mInner], ['if', 'case']);
end;

/// <summary>Akzeptiert die Zuweisung bei AIndex im Prüf-Handler mit dem Kopf AHeader jedes Zertifikat?</summary>
function AcceptsAll(const ATokens: TArray<TPascalToken>; AIndex: Integer; const AHeader: string): Boolean;
begin
  Result := (IsOneOf(ATokens[AIndex].Text, ['Accepted', 'AAccepted']) and ContainsText(AHeader, 'Certificate')) or
    (SameText(ATokens[AIndex].Text, 'Result') and (ContainsText(AHeader, 'TIdX509') or
    ContainsText(AHeader, 'VerifyPeer')));
end;

procedure TSecurityTlsVerificationDisabledRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mTracker: THeaderTracker;
begin
  mTokens := CodeTokens(AContext);
  mTracker := Default(THeaderTracker);
  for mIndex := 0 to High(mTokens) do
  begin
    if mTracker.Feed(mTokens[mIndex]) or (mIndex + 3 > High(mTokens)) then
    begin
      Continue;
    end;
    if IsClearedVerifyMode(mTokens, mIndex) then
    begin
      AReport.Add(TokenRange(mTokens[mIndex]), cTexts[TSecurityText.VerifyMode].Text,
        TRuleConfidence.High);
    end
    // Accepted := True bzw. Result := True ohne Bedingung in einem Prüf-Handler.
    else if IsTrueAssignment(mTokens, mIndex) and IsUnconditional(mTokens, mIndex) and
      AcceptsAll(mTokens, mIndex, mTracker.Header) then
    begin
      AReport.Add(TokenRange(mTokens[mIndex]), cTexts[TSecurityText.AcceptsAny].Text,
        TRuleConfidence.High);
    end;
  end;
end;

{ TSecurityInsecureHttpRule }

function TSecurityInsecureHttpRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-insecure-http', TRuleSeverity.Hint, cTexts[TSecurityText.HttpTitle].Text);
end;

/// <summary>Gilt das http:// bei AOffset nicht als Ziel (kein Rechnername, Ausnahme aus HttpExceptions)?</summary>
function IsExceptedUrl(const ALower: string; AOffset: Integer): Boolean;
var
  mException: string;
begin
  Result := not CharInSet(Copy(ALower + ' ', AOffset + Length('http://'), 1)[1], ['a'..'z', '0'..'9', '[']);
  for mException in cHttpExceptions do
  begin
    if Copy(ALower, AOffset, Length(mException)) = mException then
    begin
      Result := True;
    end;
  end;
end;

/// <summary>Erste URL mit Rechnernamen: Ein bloßes 'http://' (StartsText('http://', Url), Hilfetext "http:// oder
/// https://") nennt kein Ziel (#1109). 0 ohne.</summary>
function FirstHostUrl(const ALower: string): Integer;
begin
  Result := Pos('http://', ALower);
  while (Result > 0) and IsExceptedUrl(ALower, Result) do
  begin
    Result := PosEx('http://', ALower, Result + 1);
  end;
end;

/// <summary>Meldet das http:// bei AOffset im Literal AToken, einzeilig mit Korrektur.</summary>
procedure ReportHttp(const AReport: IRuleReport; const AToken: TPascalToken; AOffset: Integer);
var
  mStart: TTextPosition;
  mRange: TTextRange;
begin
  // Einzeilige Strings: Spalte des "http://" im Token.
  if AToken.StartPos.Line <> AToken.EndPos.Line then
  begin
    AReport.Add(TokenRange(AToken), cTexts[TSecurityText.Http].Text, TRuleConfidence.Medium);
    Exit;
  end;
  mStart := TTextPosition.Create(AToken.StartPos.Line, AToken.StartPos.Character + AOffset - 1);
  mRange := TTextRange.Create(mStart.Line, mStart.Character, mStart.Line, mStart.Character + Length('http://'));
  AReport.Add(mRange, cTexts[TSecurityText.Http].Text, TRuleConfidence.Medium,
    [TRuleFix.Create(cTexts[TSecurityText.ToHttps].Text, [TRuleEdit.Create(mRange, Copy(AToken.Text, AOffset, 4) +
    's://')])]);
end;

procedure TSecurityInsecureHttpRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mIndex, mOffset: Integer;
  mLower: string;
begin
  mTokens := CodeTokens(AContext);
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].Kind <> TPascalTokenKind.StringLiteral then
    begin
      Continue;
    end;
    mLower := LowerCase(mTokens[mIndex].Text);
    mOffset := 0;
    if Pos('xmlns', mLower) = 0 then
    begin
      mOffset := FirstHostUrl(mLower);
    end;
    if mOffset > 0 then
    begin
      ReportHttp(AReport, mTokens[mIndex], mOffset);
    end;
  end;
end;

{ TSecurityInsecureRandomRule }

function TSecurityInsecureRandomRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-insecure-random', TRuleSeverity.Warning,
    cTexts[TSecurityText.RandomTitle].Text);
end;

procedure TSecurityInsecureRandomRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mIndex, mInner, mStop, mTarget: Integer;
begin
  mTokens := CodeTokens(AContext);
  for mIndex := 1 to High(mTokens) do
  begin
    if not mTokens[mIndex].IsSymbol(':=') then
    begin
      Continue;
    end;
    // Ziel der Zuweisung: letzter Bezeichner vor := (auch Self.FToken).
    mTarget := mIndex - 1;
    if (mTokens[mTarget].Kind <> TPascalTokenKind.Identifier) or
      not ContainsOneOf(mTokens[mTarget].Text, cSensitiveRandom) then
    begin
      Continue;
    end;
    mStop := StatementEnd(mTokens, mIndex + 1);
    for mInner := mIndex + 1 to mStop do
    begin
      if (mTokens[mInner].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mInner].Text, 'Random') then
      begin
        AReport.Add(TokenRange(mTokens[mInner]), cTexts[TSecurityText.Random].Fmt([mTokens[mTarget].Text]),
          TRuleConfidence.Medium);
        Break;
      end;
    end;
  end;
end;

{ TSecuritySqlInjectionRule }

function TSecuritySqlInjectionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-sql-injection', TRuleSeverity.Warning,
    cTexts[TSecurityText.SqlTitle].Text);
end;

const
  cSqlCalls: array[0..4] of string = ('ExecSQL', 'Open', 'ExecSQLScalar', 'ExecuteDirect', 'Execute');
  // Allgemeine Namen (Dialog.Execute, Datei.Open): SQL nur, wenn ein Literal im Argument SQL enthält (#1109).
  cGenericSqlCalls: array[0..1] of string = ('Open', 'Execute');
  cSqlKeywords: array[0..9] of string = ('select', 'insert', 'update', 'delete', 'merge', 'where', 'from',
    'values', 'exec', 'truncate');
  // Umwandlungen, deren Ergebnis keine SQL-Syntax einschleusen kann.
  cSafeConversions: array[0..5] of string = ('IntToStr', 'QuotedStr', 'FloatToStr', 'IntToHex', 'BoolToStr',
    'UIntToStr');
  // Bezeichner, die Benutzereingaben liefern: TEdit.Text, TMemo.Lines, ParamStr, Webanfragen.
  cUserInputs: array[0..5] of string = ('Text', 'Lines', 'ParamStr', 'Request', 'QueryFields', 'ContentFields');

/// <summary>Änderung der Klammertiefe: +1 bei "(" und "[", -1 bei ")" und "]".</summary>
function BracketDelta(const AToken: TPascalToken): Integer;
begin
  Result := 0;
  if AToken.IsSymbol('(') or AToken.IsSymbol('[') then
  begin
    Result := 1;
  end
  else if AToken.IsSymbol(')') or AToken.IsSymbol(']') then
  begin
    Result := -1;
  end;
end;

/// <summary>Steht bei AIndex ein Konstantenname (Name = bzw. Name: in einem Konstantenabschnitt)?</summary>
function IsConstantName(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    (ATokens[AIndex + 1].IsSymbol('=') or ATokens[AIndex + 1].IsSymbol(':')) and
    ((AIndex = 0) or not ATokens[AIndex - 1].IsSymbol('.'));
end;

/// <summary>Namen aus const- und resourcestring-Abschnitten der Datei.</summary>
function ConstantNames(const ATokens: TArray<TPascalToken>): TArray<string>;
var
  mIndex, mDepth, mDelta: Integer;
  mInConst: Boolean;
begin
  Result := nil;
  mInConst := False;
  mDepth := 0;
  for mIndex := 0 to High(ATokens) - 1 do
  begin
    // "const" in Parameterlisten ist kein Konstantenabschnitt.
    mDelta := BracketDelta(ATokens[mIndex]);
    mDepth := mDepth + mDelta;
    if (mDelta <> 0) or (mDepth > 0) then
    begin
      Continue;
    end;
    if IsAnyKeyword(ATokens[mIndex], ['const', 'resourcestring']) then
    begin
      mInConst := True;
    end
    else if IsAnyKeyword(ATokens[mIndex], ['var', 'type', 'begin', 'procedure', 'function', 'implementation']) then
    begin
      mInConst := False;
    end
    else if mInConst and IsConstantName(ATokens, mIndex) then
    begin
      Result := Result + [ATokens[mIndex].Text];
    end;
  end;
end;

/// <summary>Enthält AText (klein) das Wort AWord als ganzes Wort?</summary>
function ContainsWord(const AText, AWord: string): Boolean;
var
  mStart, mAfter: Integer;
begin
  mStart := Pos(AWord, AText);
  while mStart > 0 do
  begin
    mAfter := mStart + Length(AWord);
    if ((mStart = 1) or not TTextChars.IsAsciiIdentChar(AText[mStart - 1])) and ((mAfter > Length(AText)) or
      not TTextChars.IsAsciiIdentChar(AText[mAfter])) then
    begin
      Exit(True);
    end;
    mStart := PosEx(AWord, AText, mStart + 1);
  end;
  Result := False;
end;

/// <summary>Enthält AText (klein) ein SQL-Schlüsselwort als ganzes Wort?</summary>
function HasSqlKeyword(const AText: string): Boolean;
var
  mWord: string;
begin
  for mWord in cSqlKeywords do
  begin
    if ContainsWord(AText, mWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Enthält ein String-Literal in ATokens[AFirst..ALast] ein SQL-Schlüsselwort als ganzes Wort?</summary>
function HasSqlLiteral(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := AFirst to ALast do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.StringLiteral) and
      HasSqlKeyword(LowerCase(LiteralValue(ATokens[mIndex]))) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  /// <summary>Befund über einen SQL-Ausdruck: verkettet, mit Variablen, aus Benutzereingaben.</summary>
  TSqlComposition = record
    Joined: Boolean;
    Variable: Boolean;
    FromInput: Boolean;
  end;

/// <summary>Bezeichner bei AIndex im SQL-Ausdruck bis ALast auswerten; überspringt sichere Umwandlungen.</summary>
procedure NoteSqlIdentifier(const ATokens: TArray<TPascalToken>; var AIndex: Integer; ALast: Integer;
  const AConstants: TArray<string>; var AComposition: TSqlComposition);
var
  mText: string;
  mClose: Integer;
begin
  mText := ATokens[AIndex].Text;
  if IsOneOf(mText, cSafeConversions) and (AIndex < ALast) and ATokens[AIndex + 1].IsSymbol('(') then
  begin
    // IntToStr(Id), QuotedStr(Name): Inhalt überspringen.
    mClose := MatchingParen(ATokens, AIndex + 1);
    if mClose > 0 then
    begin
      AIndex := mClose;
    end;
  end
  else if IsOneOf(mText, ['Format', 'Concat']) then
  begin
    AComposition.Joined := True;
  end
  else if not IsOneOf(mText, AConstants) and not IsOneOf(mText, ['string', 'nil', 'sLineBreak']) then
  begin
    AComposition.Variable := True;
    AComposition.FromInput := AComposition.FromInput or IsOneOf(mText, cUserInputs);
  end;
end;

/// <summary>Ist der SQL-Ausdruck ATokens[AFirst..ALast] aus Nicht-Konstanten zusammengesetzt?
/// AFromInput: eine Quelle ist Benutzereingabe.</summary>
function IsComposedSql(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  const AConstants: TArray<string>; out AFromInput: Boolean): Boolean;
var
  mIndex: Integer;
  mComposition: TSqlComposition;
begin
  mComposition := Default(TSqlComposition);
  mIndex := AFirst;
  while mIndex <= ALast do
  begin
    if ATokens[mIndex].IsSymbol('+') then
    begin
      mComposition.Joined := True;
    end
    else if ATokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      NoteSqlIdentifier(ATokens, mIndex, ALast, AConstants, mComposition);
    end;
    Inc(mIndex);
  end;
  AFromInput := mComposition.FromInput;
  Result := mComposition.Joined and mComposition.Variable;
end;

/// <summary>Steht bei AIndex AOwner.AName (SQL.Text, SQL.Add)?</summary>
function IsMemberOf(const ATokens: TArray<TPascalToken>; AIndex: Integer; const AOwner, AName: string): Boolean;
begin
  Result := SameText(ATokens[AIndex].Text, AName) and (AIndex >= 2) and ATokens[AIndex - 1].IsSymbol('.') and
    SameText(ATokens[AIndex - 2].Text, AOwner);
end;

/// <summary>SQL.Text := …, CommandText := …</summary>
function IsSqlTextTarget(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (IsMemberOf(ATokens, AIndex, 'SQL', 'Text') or SameText(ATokens[AIndex].Text, 'CommandText')) and
    ATokens[AIndex + 1].IsSymbol(':=');
end;

/// <summary>SQL.Add(…), ExecSQL(…), Open(…)</summary>
function IsSqlCall(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := ATokens[AIndex + 1].IsSymbol('(') and (IsMemberOf(ATokens, AIndex, 'SQL', 'Add') or
    (IsOneOf(ATokens[AIndex].Text, cSqlCalls) and (AIndex >= 1) and ATokens[AIndex - 1].IsSymbol('.')));
end;

/// <summary>Bereich des SQL-Texts zur Senke bei AIndex; False ohne.</summary>
function SqlRange(const ATokens: TArray<TPascalToken>; AIndex: Integer; out AFirst, ALast: Integer): Boolean;
var
  mClose: Integer;
  mArgs: TArray<TArray<Integer>>;
begin
  AFirst := -1;
  ALast := -1;
  if IsSqlTextTarget(ATokens, AIndex) then
  begin
    AFirst := AIndex + 2;
    ALast := StatementEnd(ATokens, AFirst) - 1;
  end
  else if IsSqlCall(ATokens, AIndex) then
  begin
    mClose := MatchingParen(ATokens, AIndex + 1);
    if mClose >= 0 then
    begin
      mArgs := Arguments(ATokens, AIndex + 1, mClose);
    end;
    // Nur das erste Argument ist der SQL-Text; weitere sind Parameterwerte.
    if (mClose >= 0) and (mArgs <> nil) then
    begin
      AFirst := mArgs[0][0];
      ALast := mArgs[0][1];
    end;
  end;
  Result := (AFirst >= 0) and (ALast >= AFirst);
end;

procedure TSecuritySqlInjectionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mConstants: TArray<string>;
  mIndex, mFirst, mLast: Integer;
  mFromInput: Boolean;
  mConfidence: TRuleConfidence;
begin
  mTokens := CodeTokens(AContext);
  mConstants := ConstantNames(mTokens);
  for mIndex := 0 to High(mTokens) - 2 do
  begin
    if (mTokens[mIndex].Kind <> TPascalTokenKind.Identifier) or not SqlRange(mTokens, mIndex, mFirst, mLast) or
      not IsComposedSql(mTokens, mFirst, mLast, mConstants, mFromInput) then
    begin
      Continue;
    end;
    if IsOneOf(mTokens[mIndex].Text, cGenericSqlCalls) and not HasSqlLiteral(mTokens, mFirst, mLast) then
    begin
      Continue;
    end;
    mConfidence := TRuleConfidence.Medium;
    if mFromInput then
    begin
      mConfidence := TRuleConfidence.High;
    end;
    AReport.Add(TokenRange(mTokens[mIndex]), cTexts[TSecurityText.Sql].Text, mConfidence);
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Security', cTexts);

end.
