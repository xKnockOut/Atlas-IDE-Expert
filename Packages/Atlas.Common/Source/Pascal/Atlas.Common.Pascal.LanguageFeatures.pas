unit Atlas.Common.Pascal.LanguageFeatures;

// Sprachmerkmale mit der Delphi-Version (BDS-Versionsnummer), ab der sie
// verfügbar sind (#109). Check findet im Syntaxbaum Merkmale, die die
// eingestellte Version noch nicht kennt. Ohne gültige Version wird nichts
// gemeldet, ebenso nicht in inaktiven Zweigen der bedingten Kompilierung:
// So lässt sich Code für mehrere Versionen gemeinsam pflegen.
//
// Merkmal                          ab
// Inline-Variable, -Konstante      Delphi 10.3 Rio (BDS 20.0)
// Managed Record                   Delphi 10.4 Sydney (BDS 21.0)
// Ziffern-Trennzeichen 1_000       Delphi 11 Alexandria (BDS 22.0)
// Binärliteral %1010               Delphi 11 Alexandria (BDS 22.0)
// Mehrzeiliger String '''          Delphi 12 Athens (BDS 23.0)
// If-Ausdruck, is not, not in      Delphi 13 Florence (BDS 37.0)
//
// Maßstab ist der Sprachstand (LanguageLevel, #1126): die ältere aus der
// gewählten Version und minDelphiVersion des Projekts, damit Code, der auch
// mit einer älteren Delphi-Version übersetzen muss, keine neueren Merkmale
// bekommt.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  TLanguageFeature = (InlineVariable, InlineConstant, ManagedRecord, MultilineString, IfExpression,
    DigitSeparator, BinaryLiteral, IsNotOperator, NotInOperator);

  TLanguageFeatureFinding = record
    Feature: TLanguageFeature;
    StartPos: TTextPosition;
    EndPos: TTextPosition;
    Message: string;
  end;

  TLanguageFeatures = class
  public
    /// <summary>Mindestversion als BDS-Nummer, z. B. 20.0 für Delphi 10.3.</summary>
    class function MinimumVersion(AFeature: TLanguageFeature): string; static;
    class function DisplayName(AFeature: TLanguageFeature): string; static;
    /// <summary>Produktname zur BDS-Version, z. B. "Delphi 10.3 Rio" für "20.0"; sonst "BDS 20.5".</summary>
    class function ProductName(const ABdsVersion: string): string; static;
    /// <summary>Wandelt "37.0" oder "37" in 37000 um; -1 bei ungültiger Angabe.</summary>
    class function ParseVersion(const AVersion: string): Integer; static;
    class function IsAvailable(AFeature: TLanguageFeature; const AVersion: string): Boolean; static;
    /// <summary>Ist AVersion mindestens AMinimum (BDS-Nummern)? Ohne gültige AVersion gilt die neueste Version:
    /// True (#1382, Codes der Compilermeldungen je Delphi-Version).</summary>
    class function IsAtLeast(const AVersion, AMinimum: string): Boolean; static;
    /// <summary>Sprachstand (#1126): die ältere aus AVersion (gewählte Version) und AMinimum (minDelphiVersion
    /// des Projekts). Eine ungültige oder leere Angabe zählt nicht; sind beide ungültig, ''.</summary>
    class function LanguageLevel(const AVersion, AMinimum: string): string; static;
    /// <summary>Merkmale im Baum, die AVersion nicht kennt.</summary>
    class function Check(ATree: TSyntaxTree; const AVersion: string): TArray<TLanguageFeatureFinding>;
      overload; static;
    /// <summary>Wie oben, ohne Merkmale, die in AInactive (inaktive Zweige) beginnen.</summary>
    class function Check(ATree: TSyntaxTree; const AVersion: string;
      const AInactive: TArray<TTextRange>): TArray<TLanguageFeatureFinding>; overload; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLanguageFeaturesText = (OnlyAvailableFromOnSet);

const
  cTexts: array[TLanguageFeaturesText] of TAtlasText = (
    (De: '%s erst ab %s verfügbar (eingestellt: %s)'; En: '%s only available from %s on (set: %s)'));

const
  cMinimums: array[TLanguageFeature] of string = ('20.0', '20.0', '21.0', '23.0', '37.0', '22.0', '22.0', '37.0',
    '37.0');
  cNames: array[TLanguageFeature] of TAtlasText = (
    (De: 'Inline-Variable'; En: 'inline variable'),
    (De: 'Inline-Konstante'; En: 'inline constant'),
    (De: 'Managed Record (class operator Initialize/Finalize)';
     En: 'managed record (class operator Initialize/Finalize)'),
    (De: 'Mehrzeiliger String'; En: 'multi-line string'),
    (De: 'If-Ausdruck'; En: 'if expression'),
    (De: 'Ziffern-Trennzeichen (_)'; En: 'digit separator (_)'),
    (De: 'Binärliteral (%)'; En: 'binary literal (%)'),
    (De: 'Operator "is not"'; En: 'operator "is not"'),
    (De: 'Operator "not in"'; En: 'operator "not in"'));

type
  TProduct = record
    Bds: string;
    Name: string;
  end;

const
  cProducts: array[0..7] of TProduct = (
    (Bds: '17.0'; Name: 'Delphi 10 Seattle'),
    (Bds: '18.0'; Name: 'Delphi 10.1 Berlin'),
    (Bds: '19.0'; Name: 'Delphi 10.2 Tokyo'),
    (Bds: '20.0'; Name: 'Delphi 10.3 Rio'),
    (Bds: '21.0'; Name: 'Delphi 10.4 Sydney'),
    (Bds: '22.0'; Name: 'Delphi 11 Alexandria'),
    (Bds: '23.0'; Name: 'Delphi 12 Athens'),
    (Bds: '37.0'; Name: 'Delphi 13 Florence'));

class function TLanguageFeatures.MinimumVersion(AFeature: TLanguageFeature): string;
begin
  Result := cMinimums[AFeature];
end;

class function TLanguageFeatures.DisplayName(AFeature: TLanguageFeature): string;
begin
  Result := cNames[AFeature].Text;
end;

class function TLanguageFeatures.ProductName(const ABdsVersion: string): string;
var
  mProduct: TProduct;
  mVersion: Integer;
begin
  mVersion := ParseVersion(ABdsVersion);
  for mProduct in cProducts do
  begin
    if ParseVersion(mProduct.Bds) = mVersion then
    begin
      Exit(mProduct.Name);
    end;
  end;
  Result := 'BDS ' + ABdsVersion;
end;

class function TLanguageFeatures.ParseVersion(const AVersion: string): Integer;
var
  mText, mMajorText, mMinorText: string;
  mDot, mMajor, mMinor: Integer;
begin
  mText := Trim(AVersion);
  mDot := Pos('.', mText);
  if mDot > 0 then
  begin
    mMajorText := Copy(mText, 1, mDot - 1);
    mMinorText := Copy(mText, mDot + 1, MaxInt);
  end
  else
  begin
    mMajorText := mText;
    mMinorText := '0';
  end;
  if not TryStrToInt(mMajorText, mMajor) or not TryStrToInt(mMinorText, mMinor) or
    (mMajor < 0) or (mMinor < 0) or (mMinor > 999) then
  begin
    Exit(-1);
  end;
  Result := mMajor * 1000 + mMinor;
end;

class function TLanguageFeatures.IsAvailable(AFeature: TLanguageFeature; const AVersion: string): Boolean;
var
  mVersion: Integer;
begin
  mVersion := ParseVersion(AVersion);
  Result := (mVersion < 0) or (mVersion >= ParseVersion(cMinimums[AFeature]));
end;

class function TLanguageFeatures.IsAtLeast(const AVersion, AMinimum: string): Boolean;
var
  mVersion: Integer;
begin
  mVersion := ParseVersion(AVersion);
  Result := (mVersion < 0) or (mVersion >= ParseVersion(AMinimum));
end;

class function TLanguageFeatures.LanguageLevel(const AVersion, AMinimum: string): string;
var
  mVersion, mMinimum: Integer;
begin
  mVersion := ParseVersion(AVersion);
  mMinimum := ParseVersion(AMinimum);
  if (mMinimum >= 0) and ((mVersion < 0) or (mMinimum < mVersion)) then
  begin
    Result := Trim(AMinimum);
  end
  else if mVersion >= 0 then
  begin
    Result := Trim(AVersion);
  end
  else
  begin
    Result := '';
  end;
end;

procedure AddFinding(AList: TList<TLanguageFeatureFinding>; AFeature: TLanguageFeature;
  const AStartPos, AEndPos: TTextPosition; const AVersion: string);
var
  mFinding: TLanguageFeatureFinding;
begin
  mFinding.Feature := AFeature;
  mFinding.StartPos := AStartPos;
  mFinding.EndPos := AEndPos;
  mFinding.Message := cTexts[TLanguageFeaturesText.OnlyAvailableFromOnSet].Fmt([cNames[AFeature].Text,
    TLanguageFeatures.ProductName(cMinimums[AFeature]), TLanguageFeatures.ProductName(AVersion)]);
  AList.Add(mFinding);
end;

procedure CheckNode(ANode: TSyntaxNode; AList: TList<TLanguageFeatureFinding>; const AVersion: string);
var
  mFeature: TLanguageFeature;
  mFound: Boolean;
begin
  mFound := True;
  mFeature := TLanguageFeature.InlineVariable;
  case ANode.Kind of
    TSyntaxKind.InlineVar:
      mFeature := TLanguageFeature.InlineVariable;
    TSyntaxKind.InlineConst:
      mFeature := TLanguageFeature.InlineConstant;
    TSyntaxKind.IfExpr:
      mFeature := TLanguageFeature.IfExpression;
  else
    mFound := False;
  end;
  if mFound and not TLanguageFeatures.IsAvailable(mFeature, AVersion) then
  begin
    AddFinding(AList, mFeature, ANode.StartPos, ANode.EndPos, AVersion);
  end;
end;

procedure WalkNodes(ANode: TSyntaxNode; AList: TList<TLanguageFeatureFinding>; const AVersion: string);
var
  mList: TList<TLanguageFeatureFinding>;
  mVersion: string;
begin
  mList := AList;
  mVersion := AVersion;
  // Walk statt Rekursion.
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      CheckNode(AChild, mList, mVersion);
      Result := True;
    end);
end;

/// <summary>Nächstes Token nach AIndex, das kein Kommentar und keine Direktive ist; -1 ohne.</summary>
function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(Result);
  end;
  if Result > High(ATokens) then
  begin
    Result := -1;
  end;
end;

/// <summary>Meldet AFeature für die Tokens AFirst bis ALast, wenn AVersion es noch nicht kennt.</summary>
procedure ReportIfMissing(AList: TList<TLanguageFeatureFinding>; const ATokens: TArray<TPascalToken>;
  AFeature: TLanguageFeature; AFirst, ALast: Integer; const AVersion: string);
begin
  if not TLanguageFeatures.IsAvailable(AFeature, AVersion) then
  begin
    AddFinding(AList, AFeature, ATokens[AFirst].StartPos, ATokens[ALast].EndPos, AVersion);
  end;
end;

function IsMultilineString(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.StringLiteral) and (Copy(AToken.Text, 1, 3) = '''''''') and
    (AToken.StartPos.Line <> AToken.EndPos.Line);
end;

/// <summary>Beginnt bei AIndex "class operator Initialize" bzw. "Finalize"?</summary>
function IsManagedRecordOperator(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (AIndex + 2 <= High(ATokens)) and ATokens[AIndex].IsKeyword('class') and
    SameText(ATokens[AIndex + 1].Text, 'operator');
  if Result then
  begin
    Result := SameText(ATokens[AIndex + 2].Text, 'Initialize') or SameText(ATokens[AIndex + 2].Text, 'Finalize');
  end;
end;

procedure CheckNumber(const ATokens: TArray<TPascalToken>; AIndex: Integer; AList: TList<TLanguageFeatureFinding>;
  const AVersion: string);
begin
  if Pos('_', ATokens[AIndex].Text) > 0 then
  begin
    ReportIfMissing(AList, ATokens, TLanguageFeature.DigitSeparator, AIndex, AIndex, AVersion);
  end;
  if Copy(ATokens[AIndex].Text, 1, 1) = '%' then
  begin
    ReportIfMissing(AList, ATokens, TLanguageFeature.BinaryLiteral, AIndex, AIndex, AVersion);
  end;
end;

/// <summary>"is not" und "not in" ab AIndex.</summary>
procedure CheckOperators(const ATokens: TArray<TPascalToken>; AIndex: Integer; AList: TList<TLanguageFeatureFinding>;
  const AVersion: string);
var
  mNext: Integer;
begin
  mNext := NextCode(ATokens, AIndex);
  if mNext < 0 then
  begin
    Exit;
  end;
  if ATokens[AIndex].IsKeyword('is') and ATokens[mNext].IsKeyword('not') then
  begin
    ReportIfMissing(AList, ATokens, TLanguageFeature.IsNotOperator, AIndex, mNext, AVersion);
  end;
  if ATokens[AIndex].IsKeyword('not') and ATokens[mNext].IsKeyword('in') then
  begin
    ReportIfMissing(AList, ATokens, TLanguageFeature.NotInOperator, AIndex, mNext, AVersion);
  end;
end;

procedure WalkTokens(const ATokens: TArray<TPascalToken>; AList: TList<TLanguageFeatureFinding>;
  const AVersion: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].Kind = TPascalTokenKind.Number then
    begin
      CheckNumber(ATokens, mIndex, AList, AVersion);
    end;
    CheckOperators(ATokens, mIndex, AList, AVersion);
    if IsMultilineString(ATokens[mIndex]) then
    begin
      ReportIfMissing(AList, ATokens, TLanguageFeature.MultilineString, mIndex, mIndex, AVersion);
    end;
    if IsManagedRecordOperator(ATokens, mIndex) then
    begin
      ReportIfMissing(AList, ATokens, TLanguageFeature.ManagedRecord, mIndex, mIndex + 2, AVersion);
    end;
  end;
end;

class function TLanguageFeatures.Check(ATree: TSyntaxTree; const AVersion: string): TArray<TLanguageFeatureFinding>;
begin
  Result := Check(ATree, AVersion, nil);
end;

/// <summary>Liegt A vor oder auf B (Zeile, dann Spalte)?</summary>
function NotAfter(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

function Inside(const APosition: TTextPosition; const ARanges: TArray<TTextRange>): Boolean;
var
  mRange: TTextRange;
begin
  for mRange in ARanges do
  begin
    if NotAfter(mRange.StartPos, APosition) and NotAfter(APosition, mRange.EndPos) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TLanguageFeatures.Check(ATree: TSyntaxTree; const AVersion: string;
  const AInactive: TArray<TTextRange>): TArray<TLanguageFeatureFinding>;
var
  mFinding: TLanguageFeatureFinding;
  mActive: TList<TLanguageFeatureFinding>;
var
  mList: TList<TLanguageFeatureFinding>;
begin
  if ParseVersion(AVersion) < 0 then
  begin
    Exit(nil);
  end;
  mList := TList<TLanguageFeatureFinding>.Create;
  try
    WalkNodes(ATree.Root, mList, AVersion);
    WalkTokens(ATree.Tokens, mList, AVersion);
    mActive := TList<TLanguageFeatureFinding>.Create;
    try
      for mFinding in mList do
      begin
        if not Inside(mFinding.StartPos, AInactive) then
        begin
          mActive.Add(mFinding);
        end;
      end;
      Result := mActive.ToArray;
    finally
      mActive.Free;
    end;
  finally
    mList.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Pascal.LanguageFeatures', cTexts);

end.
