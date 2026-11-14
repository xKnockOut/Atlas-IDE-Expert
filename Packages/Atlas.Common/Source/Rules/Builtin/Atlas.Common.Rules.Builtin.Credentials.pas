unit Atlas.Common.Rules.Builtin.Credentials;

// Sicherheitsregeln, Teil 1 (#57): security-hardcoded-credential meldet
// Zugangsdaten im Quelltext und in der Formulardatei.
//
// Erkannt werden drei Muster, jeweils nur in String-Literalen (Kommentare
// zählen nicht):
//   - Password= bzw. Pwd= mit Wert in Verbindungszeichenfolgen (ConnectionString,
//     Params, Params.Add) ohne Leerzeichen vor "=", damit SQL wie
//     "WHERE Password = :Pwd" still bleibt. Konfidenz hoch.
//   - Bekannte Schlüsselformate (GitHub-Token, AWS-Zugriffsschlüssel, privater
//     Schlüssel, Slack- und Google-Schlüssel) in jedem Literal, auch in
//     resourcestring; die Option "patterns" ergänzt eigene reguläre Ausdrücke.
//     Konfidenz hoch.
//   - Ein Literal, das einem Namen auf Password, Passwd, Passwort, Kennwort, Pwd,
//     Secret, ApiKey, Token oder PrivateKey zugewiesen wird (const, var-
//     Vorbelegung, :=, Vergleich, Params.Values['Password']). Der Name muss so
//     enden (DbPassword, cApiKey, nicht TokenKind oder PasswordChar), damit
//     Lexer-Konstanten wie cEndToken still bleiben; bei Secret, ApiKey, Token und
//     PrivateKey zählen nur Werte ab acht Zeichen. Konfidenz mittel.
//
// Still bleiben leere Werte, Platzhalter ('***', 'xxx', '<…>', '%s', '{0}',
// 'changeme', :Parameter), Texte mit Leerzeichen (Meldungen an den Benutzer),
// Werte, die selbst wie ein Schlüsselname aussehen ('Password'), und
// resourcestring-Texte ohne Schlüsselformat.
//
// Der Befund zeigt den Wert nie im Klartext: höchstens die ersten vier Zeichen
// (bei kurzen Werten die Hälfte), dahinter "****".

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TSecurityHardcodedCredentialRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>AValue für die Meldung: höchstens vier Zeichen (bei kurzen Werten die Hälfte), dann "****".
    /// </summary>
    class function Masked(const AValue: string): string; static;
    /// <summary>Ist AValue kein echter Wert (leer, Platzhalter, Parameter, Formatangabe)?</summary>
    class function IsPlaceholder(const AValue: string): Boolean; static;
    /// <summary>Endet der Bezeichner AName auf ein Wort für Zugangsdaten? AStrong: Kennwort (jeder Wert
    /// zählt), sonst Schlüssel oder Token (erst ab acht Zeichen).</summary>
    class function IsCredentialName(const AName: string; out AStrong: Boolean): Boolean; static;
  end;

procedure RegisterCredentialRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Editing.SqlText,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TCredentialText = (Title, Connection, Named, KeyFormat, InForm);

const
  cTexts: array[TCredentialText] of TAtlasText = (
    (De: 'Zugangsdaten im Code'; En: 'Credentials in code'),
    (De: '%s= mit festem Wert %s in einer Verbindungszeichenfolge; Kennwörter aus der Konfiguration oder einem ' +
      'Tresor lesen';
     En: '%s= with fixed value %s in a connection string; read passwords from the configuration or a vault'),
    (De: '%s erhält den festen Wert %s; Zugangsdaten nicht im Quelltext ablegen';
     En: '%s gets the fixed value %s; do not keep credentials in source code'),
    (De: 'Literal %s hat das Format eines Schlüssels (%s); Schlüssel nicht im Quelltext ablegen';
     En: 'Literal %s has the format of a key (%s); do not keep keys in source code'),
    (De: '%s (Formulardatei: %s.%s)'; En: '%s (form file: %s.%s)'));

{$SCOPEDENUMS OFF}

type
  TKeyFormat = record
    Name: string;
    Pattern: string;
  end;

const
  cMinKeyLength = 8;
  cShownChars = 4;
  cMask = '****';
  cStrongWords: array[0..4] of string = ('password', 'passwd', 'passwort', 'kennwort', 'pwd');
  cKeyWords: array[0..4] of string = ('secret', 'apikey', 'token', 'privatekey', 'accesskey');
  cPlaceholders: array[0..9] of string = ('***', 'xxx', 'changeme', 'password', 'passwort', 'kennwort', 'secret',
    'todo', 'dummy', '...');
  // Password= bzw. Pwd= ohne Leerraum davor; Wert bis ; oder Zeilenende.
  cConnectionPattern = '(?i)(?<![A-Za-z0-9_])(password|pwd)=([^;\r\n]*)';
  cKeyFormats: array[0..5] of TKeyFormat = (
    (Name: 'GitHub'; Pattern: '\bgh[pousr]_[A-Za-z0-9]{36}\b'),
    (Name: 'GitHub'; Pattern: '\bgithub_pat_[A-Za-z0-9_]{22,}'),
    (Name: 'AWS'; Pattern: '\bAKIA[0-9A-Z]{16}\b'),
    (Name: 'Private Key'; Pattern: '-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----'),
    (Name: 'Slack'; Pattern: '\bxox[abprs]-[A-Za-z0-9-]{10,}'),
    (Name: 'Google'; Pattern: '\bAIza[0-9A-Za-z_-]{35}\b'));
  cSectionEnds: array[0..13] of string = ('const', 'var', 'type', 'procedure', 'function', 'constructor',
    'destructor', 'begin', 'implementation', 'initialization', 'finalization', 'threadvar', 'label', 'exports');

type
  /// <summary>Ein Fund vor der Meldung: Text und Konfidenz.</summary>
  THit = record
    Message: string;
    Confidence: TRuleConfidence;
  end;

  /// <summary>Ein Prüflauf mit den kompilierten Mustern; TRegEx hält Zustand, daher je Lauf eigene.</summary>
  TCredentialScan = class
  private
    FConnection: TRegEx;
    FKeys: TArray<TRegEx>;
    FKeyNames: TArray<string>;
    function ConnectionHit(const AText: string; out AHit: THit): Boolean;
    function KeyHit(const AText: string; out AHit: THit): Boolean;
  public
    constructor Create(const AExtraPatterns: TArray<string>);
    /// <summary>Muster ohne Namensbezug in AText (Schlüsselformat, mit AConnection auch Password=).</summary>
    function TextHit(const AText: string; AConnection: Boolean; out AHit: THit): Boolean;
    /// <summary>AValue, zugewiesen an AName: Fund nach Namensmuster.</summary>
    class function NamedHit(const AName, AValue: string; out AHit: THit): Boolean; static;
  end;

{ TCredentialScan }

constructor TCredentialScan.Create(const AExtraPatterns: TArray<string>);
var
  mFormat: TKeyFormat;
  mPattern: string;
begin
  inherited Create;
  FConnection := TRegEx.Create(cConnectionPattern);
  for mFormat in cKeyFormats do
  begin
    FKeys := FKeys + [TRegEx.Create(mFormat.Pattern)];
    FKeyNames := FKeyNames + [mFormat.Name];
  end;
  for mPattern in AExtraPatterns do
  begin
    if mPattern <> '' then
    begin
      FKeys := FKeys + [TRegEx.Create(mPattern)];
      FKeyNames := FKeyNames + [mPattern];
    end;
  end;
end;

/// <summary>Wert ohne umschließende Leerzeichen und Anführungszeichen.</summary>
function CleanValue(const AValue: string): string;
begin
  Result := Trim(AValue);
  if (Length(Result) >= 2) and CharInSet(Result[1], ['"', '''']) and (Result[Length(Result)] = Result[1]) then
  begin
    Result := Trim(Copy(Result, 2, Length(Result) - 2));
  end;
end;

function TCredentialScan.ConnectionHit(const AText: string; out AHit: THit): Boolean;
var
  mMatch: TMatch;
  mValue: string;
begin
  for mMatch in FConnection.Matches(AText) do
  begin
    mValue := CleanValue(mMatch.Groups[2].Value);
    // Ein Wert mit Leerzeichen ist Fließtext ("Password= oder Pwd= mit …"), kein Kennwort.
    if not TSecurityHardcodedCredentialRule.IsPlaceholder(mValue) and (Pos(' ', mValue) = 0) then
    begin
      AHit.Message := cTexts[TCredentialText.Connection].Fmt([mMatch.Groups[1].Value,
        TSecurityHardcodedCredentialRule.Masked(mValue)]);
      AHit.Confidence := TRuleConfidence.High;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TCredentialScan.KeyHit(const AText: string; out AHit: THit): Boolean;
var
  mIndex: Integer;
  mMatch: TMatch;
begin
  for mIndex := 0 to High(FKeys) do
  begin
    mMatch := FKeys[mIndex].Match(AText);
    if mMatch.Success then
    begin
      AHit.Message := cTexts[TCredentialText.KeyFormat].Fmt([TSecurityHardcodedCredentialRule.Masked(mMatch.Value),
        FKeyNames[mIndex]]);
      AHit.Confidence := TRuleConfidence.High;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TCredentialScan.TextHit(const AText: string; AConnection: Boolean; out AHit: THit): Boolean;
begin
  Result := KeyHit(AText, AHit) or (AConnection and ConnectionHit(AText, AHit));
end;

/// <summary>Sieht AValue wie ein Text oder ein Schlüsselname aus, nicht wie ein Geheimnis?</summary>
function LooksLikeText(const AValue: string): Boolean;
var
  mStrong: Boolean;
begin
  Result := (Pos(' ', AValue) > 0) or (Pos(#9, AValue) > 0) or
    TSecurityHardcodedCredentialRule.IsCredentialName(AValue, mStrong) or
    ContainsText(AValue, 'password') or ContainsText(AValue, 'token');
end;

class function TCredentialScan.NamedHit(const AName, AValue: string; out AHit: THit): Boolean;
var
  mStrong: Boolean;
begin
  Result := TSecurityHardcodedCredentialRule.IsCredentialName(AName, mStrong) and
    not TSecurityHardcodedCredentialRule.IsPlaceholder(AValue) and not LooksLikeText(AValue) and
    (mStrong or (Length(AValue) >= cMinKeyLength));
  if Result then
  begin
    AHit.Message := cTexts[TCredentialText.Named].Fmt([AName, TSecurityHardcodedCredentialRule.Masked(AValue)]);
    AHit.Confidence := TRuleConfidence.Medium;
  end;
end;

{ Quelltext }

/// <summary>Inhalt eines String-Literals ohne die äußeren Hochkommas ('' bleibt ').</summary>
function LiteralText(const AToken: TPascalToken): string;
begin
  Result := StringReplace(Copy(AToken.Text, 2, Length(AToken.Text) - 2), '''''', '''', [rfReplaceAll]);
end;

function IsSectionEnd(const AToken: TPascalToken): Boolean;
var
  mWord: string;
begin
  for mWord in cSectionEnds do
  begin
    if AToken.IsKeyword(mWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ist das Literal bei AIndex der ganze Wert (nicht Teil von 'a' + B)?</summary>
function IsWholeValue(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (AIndex = High(ATokens)) or ATokens[AIndex + 1].IsSymbol(';') or
    (ATokens[AIndex + 1].Kind = TPascalTokenKind.Keyword);
end;

/// <summary>Beginnt bei AStart eine Deklaration (Konstante, vorbelegte Variable)? Sonst ist „=“ ein Vergleich
/// wie in if X = 'a'.</summary>
function IsDeclarationStart(const ATokens: TArray<TPascalToken>; AStart: Integer): Boolean;
begin
  Result := (AStart = 0) or ATokens[AStart - 1].IsSymbol(';') or ATokens[AStart - 1].IsKeyword('const') or
    ATokens[AStart - 1].IsKeyword('var');
end;

/// <summary>AName, wenn das Literal ihm zugewiesen wird (AAssign, Deklaration ab AStart) oder er mit einem
/// festen Kennwort verglichen wird (if mPassword = 'x'); Token, Schlüssel und Geheimnisse nur bei Zuweisung, denn
/// mToken = 'external' vergleicht Text.</summary>
function AssignedName(const ATokens: TArray<TPascalToken>; const AName: string; AStart: Integer;
  AAssign: Boolean): string;
var
  mStrong: Boolean;
begin
  Result := AName;
  if not AAssign and not IsDeclarationStart(ATokens, AStart) and
    not (TSecurityHardcodedCredentialRule.IsCredentialName(AName, mStrong) and mStrong) then
  begin
    Result := '';
  end;
end;

/// <summary>Name, dem das Literal bei AIndex zugewiesen wird (X := 'a', Konstante X = 'a', Values['X'] := 'a')
/// oder mit dem ein Kennwort verglichen wird; '' bei Ausdrücken und Argumenten.</summary>
function TargetName(const ATokens: TArray<TPascalToken>; AIndex: Integer): string;
var
  mBefore: Integer;
  mAssign: Boolean;
begin
  Result := '';
  mBefore := AIndex - 2;
  if (mBefore < 0) or not IsWholeValue(ATokens, AIndex) then
  begin
    Exit;
  end;
  mAssign := ATokens[AIndex - 1].IsSymbol(':=');
  if not mAssign and not ATokens[AIndex - 1].IsSymbol('=') then
  begin
    Exit;
  end;
  if ATokens[mBefore].IsSymbol(']') and (mBefore >= 1) and
    (ATokens[mBefore - 1].Kind = TPascalTokenKind.StringLiteral) then
  begin
    if mAssign then
    begin
      Result := LiteralText(ATokens[mBefore - 1]);
    end;
    Exit;
  end;
  // Typisierte Konstante bzw. Vorbelegung: Name: string = 'x' (string ist ein Schlüsselwort).
  if (ATokens[mBefore].Kind <> TPascalTokenKind.Identifier) and not ATokens[mBefore].IsKeyword('string') then
  begin
    Exit;
  end;
  if (mBefore >= 2) and ATokens[mBefore - 1].IsSymbol(':') and
    (ATokens[mBefore - 2].Kind = TPascalTokenKind.Identifier) then
  begin
    Result := AssignedName(ATokens, ATokens[mBefore - 2].Text, mBefore - 2, mAssign);
  end
  else
  begin
    Result := AssignedName(ATokens, ATokens[mBefore].Text, mBefore, mAssign);
  end;
end;

/// <summary>Fund am Literal bei AIndex; AResource: im resourcestring-Abschnitt (nur Schlüsselformate).</summary>
function SourceHit(AScan: TCredentialScan; const ATokens: TArray<TPascalToken>; AIndex: Integer;
  AResource: Boolean; out AHit: THit): Boolean;
var
  mText: string;
begin
  mText := LiteralText(ATokens[AIndex]);
  Result := AScan.TextHit(mText, not AResource, AHit) or
    (not AResource and TCredentialScan.NamedHit(TargetName(ATokens, AIndex), mText, AHit));
end;

procedure CheckSource(AScan: TCredentialScan; const ATokens: TArray<TPascalToken>; const AReport: IRuleReport);
var
  mIndex: Integer;
  mResource: Boolean;
  mHit: THit;
begin
  mResource := False;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('resourcestring') then
    begin
      mResource := True;
    end
    else if IsSectionEnd(ATokens[mIndex]) then
    begin
      mResource := False;
    end
    else if (ATokens[mIndex].Kind = TPascalTokenKind.StringLiteral) and
      SourceHit(AScan, ATokens, mIndex, mResource, mHit) then
    begin
      AReport.Add(TTextRange.Create(ATokens[mIndex].StartPos, ATokens[mIndex].EndPos), mHit.Message,
        mHit.Confidence);
    end;
  end;
end;

{ Formulardatei }

/// <summary>Token des Felds AName in der Klassendeklaration, sonst des Formularklassennamens; -1 ohne.</summary>
function FormAnchor(const ATokens: TArray<TPascalToken>; const AName, AFormClass: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ATokens) - 1 do
  begin
    if ATokens[mIndex].IsKeyword('implementation') then
    begin
      Break;
    end;
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and ATokens[mIndex + 1].IsSymbol(':') and
      SameText(ATokens[mIndex].Text, AName) then
    begin
      Exit(mIndex);
    end;
    if (Result < 0) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      ATokens[mIndex + 1].IsSymbol('=') and SameText(ATokens[mIndex].Text, AFormClass) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Letzter Teil eines Property-Namens mit Punkten (Params.Password → Password).</summary>
function LastPart(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function PropertyHit(AScan: TCredentialScan; const AProp: TDfmProperty; out AHit: THit): Boolean;
var
  mText: string;
begin
  Result := not AProp.IsEvent and TSqlText.FormValue(AProp.Value, mText) and
    (AScan.TextHit(mText, True, AHit) or TCredentialScan.NamedHit(LastPart(AProp.Name), mText, AHit));
end;

type
  /// <summary>Gang durch die Objekte der Formulardatei; meldet am Feld bzw. an der Formularklasse.</summary>
  TFormWalk = record
    Scan: TCredentialScan;
    Tokens: TArray<TPascalToken>;
    FormClass: string;
    Report: IRuleReport;
    procedure Walk(AObject: TDfmObject);
  end;

procedure TFormWalk.Walk(AObject: TDfmObject);
var
  mProp: TDfmProperty;
  mChild: TDfmObject;
  mHit: THit;
  mAnchor: Integer;
begin
  for mProp in AObject.Properties do
  begin
    mAnchor := FormAnchor(Tokens, AObject.Name, FormClass);
    if (mAnchor >= 0) and PropertyHit(Scan, mProp, mHit) then
    begin
      Report.Add(TTextRange.Create(Tokens[mAnchor].StartPos, Tokens[mAnchor].EndPos),
        cTexts[TCredentialText.InForm].Fmt([mHit.Message, AObject.Name, mProp.Name]), mHit.Confidence);
    end;
  end;
  for mChild in AObject.Children do
  begin
    Walk(mChild);
  end;
end;

procedure CheckForm(AScan: TCredentialScan; const AContext: TRuleContext; const ATokens: TArray<TPascalToken>;
  const AReport: IRuleReport);
var
  mDocument: TDfmDocument;
  mWalk: TFormWalk;
begin
  mDocument := TDfmParser.Parse(AContext.FormText);
  try
    if mDocument.Root = nil then
    begin
      Exit;
    end;
    mWalk.Scan := AScan;
    mWalk.Tokens := ATokens;
    mWalk.FormClass := mDocument.Root.TypeName;
    mWalk.Report := AReport;
    mWalk.Walk(mDocument.Root);
  finally
    mDocument.Free;
  end;
end;

{ TSecurityHardcodedCredentialRule }

function TSecurityHardcodedCredentialRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('security-hardcoded-credential', TRuleSeverity.Warning,
    cTexts[TCredentialText.Title].Text);
end;

procedure TSecurityHardcodedCredentialRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TCredentialScan;
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TRuleDerived.CodeTokens(TRuleDerived.Open(AContext), AContext);
  mScan := TCredentialScan.Create(TRuleOptions.Strings(AContext.Options, 'patterns', nil));
  try
    CheckSource(mScan, mTokens, AReport);
    if AContext.FormText <> '' then
    begin
      CheckForm(mScan, AContext, mTokens, AReport);
    end;
  finally
    mScan.Free;
  end;
end;

class function TSecurityHardcodedCredentialRule.Masked(const AValue: string): string;
var
  mShown: Integer;
begin
  mShown := Length(AValue) div 2;
  if mShown > cShownChars then
  begin
    mShown := cShownChars;
  end;
  Result := '''' + Copy(AValue, 1, mShown) + cMask + '''';
end;

class function TSecurityHardcodedCredentialRule.IsPlaceholder(const AValue: string): Boolean;
var
  mValue: string;
begin
  mValue := Trim(AValue);
  Result := (mValue = '') or (IndexText(mValue, cPlaceholders) >= 0) or
    (StartsStr('<', mValue) and EndsStr('>', mValue)) or (StartsStr('{', mValue) and EndsStr('}', mValue)) or
    (StartsStr('$(', mValue) and EndsStr(')', mValue)) or CharInSet(mValue[1], [':', '?', '@', '%']) or
    (Pos('%s', mValue) > 0) or (mValue = StringOfChar(mValue[1], Length(mValue)));
end;

/// <summary>AName ohne Ziffern am Ende (Password2 → Password), in Kleinbuchstaben.</summary>
function NameStem(const AName: string): string;
var
  mLength: Integer;
begin
  mLength := Length(AName);
  while (mLength > 0) and CharInSet(AName[mLength], ['0'..'9', '_']) do
  begin
    Dec(mLength);
  end;
  Result := LowerCase(Copy(AName, 1, mLength));
end;

class function TSecurityHardcodedCredentialRule.IsCredentialName(const AName: string; out AStrong: Boolean): Boolean;
var
  mStem, mWord: string;
begin
  mStem := NameStem(AName);
  AStrong := False;
  if mStem = '' then
  begin
    Exit(False);
  end;
  for mWord in cStrongWords do
  begin
    if EndsStr(mWord, mStem) then
    begin
      AStrong := True;
      Exit(True);
    end;
  end;
  for mWord in cKeyWords do
  begin
    if EndsStr(mWord, mStem) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure RegisterCredentialRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TSecurityHardcodedCredentialRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Credentials', cTexts);

end.
