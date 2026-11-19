unit Atlas.Common.Rules.Builtin.Declarations.Includes;

// Include-Dateien für declared-not-implemented (#124): Bindet eine Unit
// Include-Dateien ein, können dort Methodenrümpfe stehen (mORMot legt sie in
// mormot.core.rtti.delphi.inc). Bodies liest die Include-Dateien des
// implementation-Teils über TRuleContext.ReadFile (verschachtelt bis
// cMaxDepth Ebenen) und sammelt ihre Rümpfe als 'typ.methode'; HasIncludes
// sagt, ob es überhaupt welche gibt (dann nur mittlere Konfidenz).

interface

uses
  System.Classes,
  Atlas.Common.Rules.Contract;

type
  TDeclarationIncludes = class
  public const
    /// <summary>Tiefe verschachtelter Include-Dateien, die Bodies verfolgt.</summary>
    cMaxDepth = 8;
  public
    /// <summary>Bindet die Datei Include-Dateien ein ({$I datei} oder {$INCLUDE datei})?</summary>
    class function HasIncludes(const AContext: TRuleContext): Boolean; static;
    /// <summary>Dateiname aus {$I datei} bzw. {$INCLUDE 'datei'}; '' bei anderen Direktiven ({$I+}, {$IF …}).
    /// </summary>
    class function IncludeName(const ADirective: string): string; static;
    /// <summary>Letzte zwei Teile eines Methodennamens ohne Typparameter, klein: 'TAussen.TInnen&lt;T&gt;' und
    /// 'Lies' ergeben 'tinnen.lies'.</summary>
    class function BodyKey(const ATypeName, AMethod: string): string; static;
    /// <summary>Methodenrümpfe in Include-Dateien des implementation-Teils als BodyKey; Rümpfe der Datei selbst
    /// zählen nicht. Der Aufrufer gibt die Liste frei.</summary>
    class function Bodies(const AContext: TRuleContext): TStringList; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Documents.FileEncoding;

/// <summary>Hängt die Rümpfe "Typ.Methode" der Tokens ATokens an ABodies an; Include-Dateien darin
/// (bis cMaxDepth Ebenen) liest CollectInclude.</summary>
procedure CollectBodies(const ATokens: TArray<TPascalToken>; const AContext: TRuleContext; ADepth: Integer;
  ABodies: TStrings); forward;

/// <summary>Liest die Include-Datei AName neben der Unit und sammelt ihre Rümpfe; lässt sie sich nicht lesen,
/// bleibt es bei der mittleren Konfidenz.</summary>
procedure CollectInclude(const AName: string; const AContext: TRuleContext; ADepth: Integer; ABodies: TStrings);
var
  mBytes: TBytes;
  mFormat: TFileFormat;
begin
  if (AName <> '') and (ADepth < TDeclarationIncludes.cMaxDepth) and Assigned(AContext.ReadFile) and
    AContext.ReadFile(AName, mBytes) then
  begin
    CollectBodies(TPascalLexer.Tokenize(TFileEncoding.Decode(mBytes, mFormat)), AContext, ADepth + 1, ABodies);
  end;
end;

function IsRoutineKeyword(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Keyword) and
    MatchText(AToken.Text, ['procedure', 'function', 'constructor', 'destructor', 'operator']);
end;

/// <summary>Teile des Namens ab ATokens[AIndex] ('TFoo', 'Bar' aus TFoo&lt;T&gt;.Bar); AIndex steht danach auf
/// dem ersten Token hinter dem Namen.</summary>
function NameParts(const ATokens: TArray<TPascalToken>; var AIndex: Integer): TArray<string>;
var
  mDepth: Integer;
begin
  Result := nil;
  mDepth := 0;
  while AIndex <= High(ATokens) do
  begin
    if ATokens[AIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      // Kommentare und Direktiven im Namen überspringen.
    end
    else if ATokens[AIndex].Text = '<' then
    begin
      Inc(mDepth);
    end
    else if ATokens[AIndex].Text = '>' then
    begin
      Dec(mDepth);
    end
    else if mDepth = 0 then
    begin
      if ATokens[AIndex].Kind = TPascalTokenKind.Identifier then
      begin
        Result := Result + [ATokens[AIndex].Text];
      end
      else if ATokens[AIndex].Text <> '.' then
      begin
        Exit;
      end;
    end;
    Inc(AIndex);
  end;
end;

procedure CollectBodies(const ATokens: TArray<TPascalToken>; const AContext: TRuleContext; ADepth: Integer;
  ABodies: TStrings);
var
  mIndex: Integer;
  mParts: TArray<string>;
begin
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if ATokens[mIndex].Kind = TPascalTokenKind.Directive then
    begin
      CollectInclude(TDeclarationIncludes.IncludeName(ATokens[mIndex].Text), AContext, ADepth, ABodies);
    end;
    if IsRoutineKeyword(ATokens[mIndex]) then
    begin
      Inc(mIndex);
      mParts := NameParts(ATokens, mIndex);
      if Length(mParts) >= 2 then
      begin
        ABodies.Add(TDeclarationIncludes.BodyKey(mParts[High(mParts) - 1], mParts[High(mParts)]));
      end;
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
end;

{ TDeclarationIncludes }

class function TDeclarationIncludes.HasIncludes(const AContext: TRuleContext): Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in AContext.Tree.Tokens do
  begin
    // {$I+} und {$I-} schalten die E/A-Prüfung um und sind keine Includes.
    if (mToken.Kind = TPascalTokenKind.Directive) and (IncludeName(mToken.Text) <> '') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDeclarationIncludes.IncludeName(const ADirective: string): string;
var
  mText: string;
begin
  Result := '';
  mText := UpperCase(ADirective);
  if not StartsStr('{$INCLUDE ', mText) and not StartsStr('{$I ', mText) then
  begin
    Exit;
  end;
  Result := Trim(Copy(ADirective, Pos(' ', ADirective) + 1, MaxInt));
  if EndsStr('}', Result) then
  begin
    Result := Trim(Copy(Result, 1, Length(Result) - 1));
  end;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
end;

class function TDeclarationIncludes.BodyKey(const ATypeName, AMethod: string): string;
var
  mType: string;
begin
  mType := ATypeName;
  if Pos('<', mType) > 0 then
  begin
    mType := Copy(mType, 1, Pos('<', mType) - 1);
  end;
  if Pos('.', mType) > 0 then
  begin
    mType := Copy(mType, LastDelimiter('.', mType) + 1, MaxInt);
  end;
  Result := LowerCase(mType + '.' + AMethod);
end;

class function TDeclarationIncludes.Bodies(const AContext: TRuleContext): TStringList;
var
  mIndex: Integer;
  mTokens: TArray<TPascalToken>;
  mInImplementation: Boolean;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  Result.CaseSensitive := False;
  mTokens := AContext.Tree.Tokens;
  mInImplementation := False;
  // Rümpfe der Datei selbst ordnet TClassCompletion zu (auch Überladungen); hier zählen nur die Include-Dateien.
  for mIndex := 0 to High(mTokens) do
  begin
    if (mTokens[mIndex].Kind = TPascalTokenKind.Keyword) and SameText(mTokens[mIndex].Text, 'implementation') then
    begin
      mInImplementation := True;
    end
    else if mInImplementation and (mTokens[mIndex].Kind = TPascalTokenKind.Directive) then
    begin
      CollectInclude(IncludeName(mTokens[mIndex].Text), AContext, 0, Result);
    end;
  end;
end;

end.
