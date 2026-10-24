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
  Atlas.Common.Pascal.Contract;

const
  Minimums: array[TLanguageFeature] of string = ('20.0', '20.0', '21.0', '23.0', '37.0', '22.0', '22.0', '37.0',
    '37.0');
  Names: array[TLanguageFeature] of string = ('Inline-Variable', 'Inline-Konstante',
    'Managed Record (class operator Initialize/Finalize)', 'Mehrzeiliger String', 'If-Ausdruck',
    'Ziffern-Trennzeichen (_)', 'Binärliteral (%)', 'Operator "is not"', 'Operator "not in"');

type
  TProduct = record
    Bds: string;
    Name: string;
  end;

const
  Products: array[0..7] of TProduct = (
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
  Result := Minimums[AFeature];
end;

class function TLanguageFeatures.DisplayName(AFeature: TLanguageFeature): string;
begin
  Result := Names[AFeature];
end;

class function TLanguageFeatures.ProductName(const ABdsVersion: string): string;
var
  Product: TProduct;
  Version: Integer;
begin
  Version := ParseVersion(ABdsVersion);
  for Product in Products do
    if ParseVersion(Product.Bds) = Version then
      Exit(Product.Name);
  Result := 'BDS ' + ABdsVersion;
end;

class function TLanguageFeatures.ParseVersion(const AVersion: string): Integer;
var
  Text, MajorText, MinorText: string;
  Dot, Major, Minor: Integer;
begin
  Text := Trim(AVersion);
  Dot := Pos('.', Text);
  if Dot > 0 then
  begin
    MajorText := Copy(Text, 1, Dot - 1);
    MinorText := Copy(Text, Dot + 1, MaxInt);
  end
  else
  begin
    MajorText := Text;
    MinorText := '0';
  end;
  if not TryStrToInt(MajorText, Major) or not TryStrToInt(MinorText, Minor) or
    (Major < 0) or (Minor < 0) or (Minor > 999) then
    Exit(-1);
  Result := Major * 1000 + Minor;
end;

class function TLanguageFeatures.IsAvailable(AFeature: TLanguageFeature; const AVersion: string): Boolean;
var
  Version: Integer;
begin
  Version := ParseVersion(AVersion);
  Result := (Version < 0) or (Version >= ParseVersion(Minimums[AFeature]));
end;

class function TLanguageFeatures.LanguageLevel(const AVersion, AMinimum: string): string;
var
  Version, Minimum: Integer;
begin
  Version := ParseVersion(AVersion);
  Minimum := ParseVersion(AMinimum);
  if (Minimum >= 0) and ((Version < 0) or (Minimum < Version)) then
    Result := Trim(AMinimum)
  else if Version >= 0 then
    Result := Trim(AVersion)
  else
    Result := '';
end;

procedure AddFinding(AList: TList<TLanguageFeatureFinding>; AFeature: TLanguageFeature;
  const AStartPos, AEndPos: TTextPosition; const AVersion: string);
var
  Finding: TLanguageFeatureFinding;
begin
  Finding.Feature := AFeature;
  Finding.StartPos := AStartPos;
  Finding.EndPos := AEndPos;
  Finding.Message := Format('%s erst ab %s verfügbar (eingestellt: %s)',
    [Names[AFeature], TLanguageFeatures.ProductName(Minimums[AFeature]), TLanguageFeatures.ProductName(AVersion)]);
  AList.Add(Finding);
end;

procedure CheckNode(ANode: TSyntaxNode; AList: TList<TLanguageFeatureFinding>; const AVersion: string);
var
  Feature: TLanguageFeature;
  Found: Boolean;
begin
  Found := True;
  Feature := TLanguageFeature.InlineVariable;
  case ANode.Kind of
    TSyntaxKind.InlineVar:
      Feature := TLanguageFeature.InlineVariable;
    TSyntaxKind.InlineConst:
      Feature := TLanguageFeature.InlineConstant;
    TSyntaxKind.IfExpr:
      Feature := TLanguageFeature.IfExpression;
  else
    Found := False;
  end;
  if Found and not TLanguageFeatures.IsAvailable(Feature, AVersion) then
    AddFinding(AList, Feature, ANode.StartPos, ANode.EndPos, AVersion);
end;

procedure WalkNodes(ANode: TSyntaxNode; AList: TList<TLanguageFeatureFinding>; const AVersion: string);
var
  List: TList<TLanguageFeatureFinding>;
  Version: string;
begin
  List := AList;
  Version := AVersion;
  // Walk statt Rekursion (Bericht M1).
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    begin
      CheckNode(AChild, List, Version);
      Result := True;
    end);
end;

/// <summary>Nächstes Token nach AIndex, das kein Kommentar und keine Direktive ist; -1 ohne.</summary>
function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
    Inc(Result);
  if Result > High(ATokens) then
    Result := -1;
end;

procedure WalkTokens(const ATokens: TArray<TPascalToken>; AList: TList<TLanguageFeatureFinding>;
  const AVersion: string);

  procedure Report(AFeature: TLanguageFeature; AFirst, ALast: Integer);
  begin
    if not TLanguageFeatures.IsAvailable(AFeature, AVersion) then
      AddFinding(AList, AFeature, ATokens[AFirst].StartPos, ATokens[ALast].EndPos, AVersion);
  end;

var
  Index, Next: Integer;
begin
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].Kind = TPascalTokenKind.Number then
    begin
      if Pos('_', ATokens[Index].Text) > 0 then
        Report(TLanguageFeature.DigitSeparator, Index, Index);
      if Copy(ATokens[Index].Text, 1, 1) = '%' then
        Report(TLanguageFeature.BinaryLiteral, Index, Index);
    end;
    Next := NextCode(ATokens, Index);
    if (Next >= 0) and ATokens[Index].IsKeyword('is') and ATokens[Next].IsKeyword('not') then
      Report(TLanguageFeature.IsNotOperator, Index, Next);
    if (Next >= 0) and ATokens[Index].IsKeyword('not') and ATokens[Next].IsKeyword('in') then
      Report(TLanguageFeature.NotInOperator, Index, Next);
    if (ATokens[Index].Kind = TPascalTokenKind.StringLiteral) and
      (Copy(ATokens[Index].Text, 1, 3) = '''''''') and
      (ATokens[Index].StartPos.Line <> ATokens[Index].EndPos.Line) and
      not TLanguageFeatures.IsAvailable(TLanguageFeature.MultilineString, AVersion) then
      AddFinding(AList, TLanguageFeature.MultilineString, ATokens[Index].StartPos,
        ATokens[Index].EndPos, AVersion);
    if (Index + 2 <= High(ATokens)) and ATokens[Index].IsKeyword('class') and
      SameText(ATokens[Index + 1].Text, 'operator') and
      (SameText(ATokens[Index + 2].Text, 'Initialize') or SameText(ATokens[Index + 2].Text, 'Finalize')) and
      not TLanguageFeatures.IsAvailable(TLanguageFeature.ManagedRecord, AVersion) then
      AddFinding(AList, TLanguageFeature.ManagedRecord, ATokens[Index].StartPos,
        ATokens[Index + 2].EndPos, AVersion);
  end;
end;

class function TLanguageFeatures.Check(ATree: TSyntaxTree; const AVersion: string): TArray<TLanguageFeatureFinding>;
begin
  Result := Check(ATree, AVersion, nil);
end;

function Inside(const APosition: TTextPosition; const ARanges: TArray<TTextRange>): Boolean;
var
  Range: TTextRange;
begin
  for Range in ARanges do
    if ((APosition.Line > Range.StartPos.Line) or ((APosition.Line = Range.StartPos.Line) and
      (APosition.Character >= Range.StartPos.Character))) and ((APosition.Line < Range.EndPos.Line) or
      ((APosition.Line = Range.EndPos.Line) and (APosition.Character <= Range.EndPos.Character))) then
      Exit(True);
  Result := False;
end;

class function TLanguageFeatures.Check(ATree: TSyntaxTree; const AVersion: string;
  const AInactive: TArray<TTextRange>): TArray<TLanguageFeatureFinding>;
var
  Finding: TLanguageFeatureFinding;
  Active: TList<TLanguageFeatureFinding>;
var
  List: TList<TLanguageFeatureFinding>;
begin
  if ParseVersion(AVersion) < 0 then
    Exit(nil);
  List := TList<TLanguageFeatureFinding>.Create;
  try
    WalkNodes(ATree.Root, List, AVersion);
    WalkTokens(ATree.Tokens, List, AVersion);
    Active := TList<TLanguageFeatureFinding>.Create;
    try
      for Finding in List do
        if not Inside(Finding.StartPos, AInactive) then
          Active.Add(Finding);
      Result := Active.ToArray;
    finally
      Active.Free;
    end;
  finally
    List.Free;
  end;
end;

end.
